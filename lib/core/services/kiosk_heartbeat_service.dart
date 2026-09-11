import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../constants/app_constants.dart';

class KioskHeartbeatService {
  static final KioskHeartbeatService _instance = KioskHeartbeatService._internal();
  factory KioskHeartbeatService() => _instance;
  KioskHeartbeatService._internal();

  Timer? _heartbeatTimer;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Start sending device heartbeat ping to Firestore every intervalSeconds
  void startHeartbeat({
    required String businessId,
    required String shopId,
    required String deviceId,
    int intervalSeconds = 60,
  }) {
    stopHeartbeat();
    _sendPing(businessId, shopId, deviceId);

    _heartbeatTimer = Timer.periodic(Duration(seconds: intervalSeconds), (_) {
      _sendPing(businessId, shopId, deviceId);
    });
  }

  Future<void> _sendPing(String businessId, String shopId, String deviceId) async {
    try {
      final now = DateTime.now();
      await _firestore
          .collection(AppConstants.colBusinesses)
          .doc(businessId)
          .collection('kiosks')
          .doc(deviceId)
          .set({
        'deviceId': deviceId,
        'shopId': shopId,
        'businessId': businessId,
        'status': 'ONLINE',
        'lastHeartbeat': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Kiosk heartbeat ping error: $e');
    }
  }

  void stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }
}
