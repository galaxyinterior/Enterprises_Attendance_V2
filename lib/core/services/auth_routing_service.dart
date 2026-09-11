import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_constants.dart';
import '../../models/business_model.dart';

class AuthRoutingService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;

  static const String keyIsLoggedIn = 'is_logged_in';
  static const String keyRole = 'user_role';
  static const String keyShopId = 'shop_id';
  static const String keyBusinessId = 'business_id';
  static const String keyEmail = 'user_email';

  // Save session details locally
  Future<void> saveSession({
    required String role,
    required String shopId,
    required String businessId,
    required String email,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyIsLoggedIn, true);
    await prefs.setString(keyRole, role);
    await prefs.setString(keyShopId, shopId);
    await prefs.setString(keyBusinessId, businessId);
    await prefs.setString(keyEmail, email);
  }

  // Retrieve saved local session
  Future<Map<String, dynamic>?> getSavedSession() async {
    final prefs = await SharedPreferences.getInstance();
    final isLoggedIn = prefs.getBool(keyIsLoggedIn) ?? false;
    if (!isLoggedIn) return null;

    final role = prefs.getString(keyRole) ?? '';
    final shopId = prefs.getString(keyShopId) ?? '';
    final businessId = prefs.getString(keyBusinessId) ?? '';
    final email = prefs.getString(keyEmail) ?? '';

    if (role.isEmpty) return null;

    return {
      'role': role,
      'shopId': shopId,
      'businessId': businessId,
      'email': email,
    };
  }

  // Clear session on explicit logout
  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await _auth.signOut();
  }

  // Login user and fetch role & business info
  Future<Map<String, dynamic>> loginUser({
    required String email,
    required String password,
  }) async {
    try {
      UserCredential credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      final uid = credential.user!.uid;

      // Check Master User collection
      final userDoc = await _firestore.collection(AppConstants.colUsers).doc(uid).get();

      if (userDoc.exists) {
        final data = userDoc.data()!;
        final role = data['role'] ?? AppConstants.roleShopAdmin;
        final businessId = data['businessId'] ?? '';

        if (role == AppConstants.roleMaster) {
          await saveSession(role: AppConstants.roleMaster, shopId: 'MASTER', businessId: 'MASTER', email: email);
          return {
            'role': AppConstants.roleMaster,
            'uid': uid,
            'email': email,
          };
        }

        // Fetch business profile to verify active status
        if (businessId.isNotEmpty) {
          final bizDoc = await _firestore
              .collection(AppConstants.colBusinesses)
              .doc(businessId)
              .get();

          if (bizDoc.exists) {
            final bizModel = BusinessModel.fromMap(bizDoc.data()!);
            await saveSession(role: role, shopId: bizModel.shopId, businessId: businessId, email: email);
            return {
              'role': role,
              'uid': uid,
              'email': email,
              'businessId': businessId,
              'shopId': bizModel.shopId,
              'business': bizModel,
            };
          }
        }

        await saveSession(role: role, shopId: businessId, businessId: businessId, email: email);
        return {
          'role': role,
          'uid': uid,
          'email': email,
          'businessId': businessId,
          'shopId': businessId,
        };
      } else {
        // Check if email format identifies Kiosk or Admin fallback
        if (email.endsWith('@kiosk.in')) {
          String shopId = email.split('@').first.toUpperCase();
          await saveSession(role: AppConstants.roleKiosk, shopId: shopId, businessId: shopId, email: email);
          return {
            'role': AppConstants.roleKiosk,
            'uid': uid,
            'email': email,
            'shopId': shopId,
            'businessId': shopId,
          };
        } else if (email.endsWith('@admin.in')) {
          String shopId = email.split('@').first.toUpperCase();
          await saveSession(role: AppConstants.roleShopAdmin, shopId: shopId, businessId: shopId, email: email);
          return {
            'role': AppConstants.roleShopAdmin,
            'uid': uid,
            'email': email,
            'shopId': shopId,
            'businessId': shopId,
          };
        } else if (email == 'master@admin.com') {
          await saveSession(role: AppConstants.roleMaster, shopId: 'MASTER', businessId: 'MASTER', email: email);
          return {
            'role': AppConstants.roleMaster,
            'uid': uid,
            'email': email,
          };
        }
      }

      await saveSession(role: AppConstants.roleShopAdmin, shopId: 'SHOP001', businessId: 'SHOP001', email: email);
      return {
        'role': AppConstants.roleShopAdmin,
        'uid': uid,
        'email': email,
        'shopId': 'SHOP001',
        'businessId': 'SHOP001',
      };
    } catch (e) {
      throw Exception('Login failed: ${e.toString()}');
    }
  }

  // Sign Out
  Future<void> signOut() async {
    await clearSession();
  }
}
