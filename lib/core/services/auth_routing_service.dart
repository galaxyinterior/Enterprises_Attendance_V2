import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
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
    debugPrint('Session saved successfully: role=$role, shopId=$shopId');
  }

  // Retrieve saved local session
  Future<Map<String, dynamic>?> getSavedSession() async {
    final prefs = await SharedPreferences.getInstance();
    final isLoggedIn = prefs.getBool(keyIsLoggedIn) ?? false;
    final firebaseUser = _auth.currentUser;

    // Restore if SharedPreferences flag is true OR Firebase user exists
    if (!isLoggedIn && firebaseUser == null) return null;

    String role = prefs.getString(keyRole) ?? '';
    String shopId = prefs.getString(keyShopId) ?? '';
    String businessId = prefs.getString(keyBusinessId) ?? '';
    String email = prefs.getString(keyEmail) ?? firebaseUser?.email ?? '';

    if (role.isEmpty) return null;

    return {
      'role': role,
      'shopId': shopId.isNotEmpty ? shopId : 'SHOP001',
      'businessId': businessId.isNotEmpty ? businessId : (shopId.isNotEmpty ? shopId : 'SHOP001'),
      'email': email,
    };
  }

  // Clear session on explicit logout
  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await _auth.signOut();
    debugPrint('Session cleared on explicit logout.');
  }

  // Login user and fetch role & business info
  Future<Map<String, dynamic>> loginUser({
    required String email,
    required String password,
  }) async {
    try {
      final cleanEmail = email.trim();
      UserCredential credential = await _auth.signInWithEmailAndPassword(
        email: cleanEmail,
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
          await saveSession(role: AppConstants.roleMaster, shopId: 'MASTER', businessId: 'MASTER', email: cleanEmail);
          return {
            'role': AppConstants.roleMaster,
            'uid': uid,
            'email': cleanEmail,
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
            await saveSession(role: role, shopId: bizModel.shopId, businessId: businessId, email: cleanEmail);
            return {
              'role': role,
              'uid': uid,
              'email': cleanEmail,
              'businessId': businessId,
              'shopId': bizModel.shopId,
              'business': bizModel,
            };
          }
        }

        await saveSession(role: role, shopId: businessId, businessId: businessId, email: cleanEmail);
        return {
          'role': role,
          'uid': uid,
          'email': cleanEmail,
          'businessId': businessId,
          'shopId': businessId,
        };
      } else {
        // Fallback: Check ID Token custom claims if Firestore doc is missing
        final idTokenResult = await credential.user?.getIdTokenResult();
        final claims = idTokenResult?.claims;
        final String role = (claims != null && claims['role'] != null) ? claims['role'] : AppConstants.roleShopAdmin;
        final String businessId = (claims != null && claims['businessId'] != null) ? claims['businessId'] : 'SHOP001';

        await saveSession(role: role, shopId: businessId, businessId: businessId, email: cleanEmail);
        return {
          'role': role,
          'uid': uid,
          'email': cleanEmail,
          'businessId': businessId,
          'shopId': businessId,
        };
      }
    } catch (e) {
      throw Exception('Login failed: ${e.toString()}');
    }
  }

  // Sign Out
  Future<void> signOut() async {
    await clearSession();
  }
}
