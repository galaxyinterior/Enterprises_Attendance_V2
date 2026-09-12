import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../constants/app_constants.dart';
import '../../models/registration_request_model.dart';
import '../../models/business_model.dart';
import 'email_notification_service.dart';

class ProvisioningResult {
  final bool success;
  final String shopId;
  final String adminEmail;
  final String kioskEmail;
  final bool emailSent;
  final String provisioningState; // NOT_STARTED / IN_PROGRESS / COMPLETED / PARTIAL_FAILURE / FAILED
  final String? errorMessage;

  ProvisioningResult({
    required this.success,
    required this.shopId,
    required this.adminEmail,
    required this.kioskEmail,
    required this.emailSent,
    required this.provisioningState,
    this.errorMessage,
  });
}

class ShopProvisioningService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Check if Shop ID already exists in businesses collection
  Future<bool> checkShopIdExists(String shopId) async {
    final cleanId = shopId.trim().toUpperCase();
    final doc = await _firestore.collection(AppConstants.colBusinesses).doc(cleanId).get();
    return doc.exists;
  }

  /// Reject registration application with documented reason and retain history
  Future<void> rejectRegistration({
    required String applicationId,
    required String rejectionReason,
  }) async {
    await _firestore.collection(AppConstants.colRegistrationRequests).doc(applicationId).update({
      'status': 'REJECTED',
      'rejectionReason': rejectionReason,
      'reviewedAt': DateTime.now().toIso8601String(),
      'reviewedBy': 'MASTER',
    });

    await _firestore.collection(AppConstants.colMasterAuditLogs).add({
      'action': 'REJECT_REGISTRATION',
      'applicationId': applicationId,
      'rejectionReason': rejectionReason,
      'timestamp': DateTime.now().toIso8601String(),
      'performedBy': 'MASTER',
    });
  }

  /// Update Shop status (active / paused / suspended)
  Future<void> updateShopStatus(String shopId, String newStatus) async {
    await _firestore.collection(AppConstants.colBusinesses).doc(shopId).update({
      'status': newStatus,
      'updatedAt': DateTime.now().toIso8601String(),
    });

    await _firestore.collection(AppConstants.colMasterAuditLogs).add({
      'action': 'UPDATE_SHOP_STATUS',
      'shopId': shopId,
      'newStatus': newStatus,
      'timestamp': DateTime.now().toIso8601String(),
      'performedBy': 'MASTER',
    });
  }

  /// Unpair or revoke a Kiosk terminal device
  Future<void> unpairDevice(String businessId, String deviceId) async {
    await _firestore
        .collection(AppConstants.colBusinesses)
        .doc(businessId)
        .collection('devices')
        .doc(deviceId)
        .update({
      'status': 'UNPAIRED',
      'unpairedAt': DateTime.now().toIso8601String(),
    });

    await _firestore.collection(AppConstants.colMasterAuditLogs).add({
      'action': 'UNPAIR_DEVICE',
      'businessId': businessId,
      'deviceId': deviceId,
      'timestamp': DateTime.now().toIso8601String(),
      'performedBy': 'MASTER',
    });
  }

  /// Provision Shop & create Admin + Kiosk Firebase Auth accounts safely with state tracking
  Future<ProvisioningResult> provisionShop({
    required RegistrationRequestModel request,
    required String customShopId,
    required String adminPassword,
    required String kioskPassword,
    required String userEmail,
  }) async {
    final String shopId = customShopId.trim().toUpperCase();
    final String adminEmail = '$shopId@admin.in';
    final String kioskEmail = '$shopId@kiosk.in';
    final String recipientEmail = userEmail.trim();

    // 1. Mark request provisioningState as IN_PROGRESS
    await _firestore.collection(AppConstants.colRegistrationRequests).doc(request.applicationId).update({
      'provisioningState': 'IN_PROGRESS',
      'updatedAt': DateTime.now().toIso8601String(),
    }).catchError((_) {});

    try {
      // Verify Shop ID uniqueness
      final exists = await checkShopIdExists(shopId);
      if (exists) {
        await _firestore.collection(AppConstants.colRegistrationRequests).doc(request.applicationId).update({
          'provisioningState': 'FAILED',
          'lastError': 'Shop ID already exists',
        }).catchError((_) {});

        return ProvisioningResult(
          success: false,
          shopId: shopId,
          adminEmail: adminEmail,
          kioskEmail: kioskEmail,
          emailSent: false,
          provisioningState: 'FAILED',
          errorMessage: 'Shop ID "$shopId" already exists! Please enter a unique Shop ID.',
        );
      }

      // Initialize secondary FirebaseApp for Auth provisioning without logging out Master Admin
      FirebaseApp secondaryApp;
      try {
        secondaryApp = Firebase.app('ProvisioningApp');
      } catch (_) {
        secondaryApp = await Firebase.initializeApp(
          name: 'ProvisioningApp',
          options: Firebase.app().options,
        );
      }
      final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);

      String? adminUid;
      String? kioskUid;

      // Register Admin User in Auth
      try {
        final adminCred = await secondaryAuth.createUserWithEmailAndPassword(
          email: adminEmail,
          password: adminPassword,
        );
        adminUid = adminCred.user?.uid;
      } on FirebaseAuthException catch (e) {
        if (e.code == 'email-already-in-use') {
          try {
            final cred = await secondaryAuth.signInWithEmailAndPassword(email: adminEmail, password: adminPassword);
            adminUid = cred.user?.uid;
          } catch (_) {}
        } else {
          rethrow;
        }
      }

      // Register Kiosk User in Auth
      try {
        final kioskCred = await secondaryAuth.createUserWithEmailAndPassword(
          email: kioskEmail,
          password: kioskPassword,
        );
        kioskUid = kioskCred.user?.uid;
      } on FirebaseAuthException catch (e) {
        if (e.code == 'email-already-in-use') {
          try {
            final cred = await secondaryAuth.signInWithEmailAndPassword(email: kioskEmail, password: kioskPassword);
            kioskUid = cred.user?.uid;
          } catch (_) {}
        } else {
          rethrow;
        }
      }

      await secondaryAuth.signOut();

      final String state = (adminUid != null && kioskUid != null) ? 'COMPLETED' : 'PARTIAL_FAILURE';

      // Store Business Document in Firestore
      final bizModel = BusinessModel(
        businessId: shopId,
        shopId: shopId,
        shopName: request.shopName,
        ownerName: request.ownerName,
        email: recipientEmail,
        phone: request.phone,
        address: request.address,
        city: request.city,
        state: request.state,
        pincode: request.pincode,
        status: AppConstants.statusActive,
        createdAt: DateTime.now(),
        approvedAt: DateTime.now(),
        approvedBy: 'MASTER',
      );

      await _firestore.collection(AppConstants.colBusinesses).doc(shopId).set(bizModel.toMap());

      // Save User profiles in Firestore users collection
      if (adminUid != null) {
        await _firestore.collection(AppConstants.colUsers).doc(adminUid).set({
          'uid': adminUid,
          'email': adminEmail,
          'role': AppConstants.roleShopAdmin,
          'businessId': shopId,
          'shopId': shopId,
          'ownerName': request.ownerName,
          'createdAt': DateTime.now().toIso8601String(),
        });
      }

      if (kioskUid != null) {
        await _firestore.collection(AppConstants.colUsers).doc(kioskUid).set({
          'uid': kioskUid,
          'email': kioskEmail,
          'role': AppConstants.roleKiosk,
          'businessId': shopId,
          'shopId': shopId,
          'createdAt': DateTime.now().toIso8601String(),
        });
      }

      // Update Application Request status (Retains application history without immediate deletion)
      await _firestore.collection(AppConstants.colRegistrationRequests).doc(request.applicationId).update({
        'status': 'APPROVED',
        'provisioningState': state,
        'assignedShopId': shopId,
        'reviewedAt': DateTime.now().toIso8601String(),
        'reviewedBy': 'MASTER',
      });

      // Log Master Audit Trail
      await _firestore.collection(AppConstants.colMasterAuditLogs).add({
        'action': 'PROVISION_SHOP',
        'shopId': shopId,
        'shopName': request.shopName,
        'userEmail': recipientEmail,
        'provisioningState': state,
        'timestamp': DateTime.now().toIso8601String(),
        'performedBy': 'MASTER',
      });

      // Send Credentials Email
      final bool emailSent = await EmailNotificationService().sendApprovalCredentialsEmail(
        recipientEmail: recipientEmail,
        shopName: request.shopName,
        ownerName: request.ownerName,
        shopId: shopId,
        adminEmail: adminEmail,
        adminPassword: adminPassword,
        kioskEmail: kioskEmail,
        kioskPassword: kioskPassword,
      );

      return ProvisioningResult(
        success: true,
        shopId: shopId,
        adminEmail: adminEmail,
        kioskEmail: kioskEmail,
        emailSent: emailSent,
        provisioningState: state,
      );
    } catch (e) {
      await _firestore.collection(AppConstants.colRegistrationRequests).doc(request.applicationId).update({
        'provisioningState': 'FAILED',
        'lastError': e.toString(),
      }).catchError((_) {});

      return ProvisioningResult(
        success: false,
        shopId: shopId,
        adminEmail: adminEmail,
        kioskEmail: kioskEmail,
        emailSent: false,
        provisioningState: 'FAILED',
        errorMessage: e.toString(),
      );
    }
  }
}
