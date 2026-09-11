import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import '../constants/app_constants.dart';
import 'offline_db_service.dart';

class SyncEngine {
  static final SyncEngine _instance = SyncEngine._internal();
  factory SyncEngine() => _instance;
  SyncEngine._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final OfflineDbService _offlineDb = OfflineDbService();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _periodicSyncTimer;
  bool _isSyncing = false;

  void startAutoSync() {
    _connectivitySubscription?.cancel();
    _periodicSyncTimer?.cancel();

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      if (results.any((res) => res != ConnectivityResult.none)) {
        syncPendingAttendance();
      }
    });

    // Periodic background sync fallback every 30 seconds
    _periodicSyncTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      syncPendingAttendance();
    });

    // Initial sync trigger
    syncPendingAttendance();
  }

  // Push pending SQLite attendance logs to Cloud Firestore
  Future<int> syncPendingAttendance() async {
    if (_isSyncing) return 0;
    _isSyncing = true;
    int syncedCount = 0;

    try {
      final pendingRecords = await _offlineDb.getPendingAttendance();

      for (var record in pendingRecords) {
        // Check business status before syncing
        final bizDoc = await _firestore
            .collection(AppConstants.colBusinesses)
            .doc(record.businessId)
            .get();

        if (bizDoc.exists) {
          final bizData = bizDoc.data()!;
          if (bizData['status'] == AppConstants.statusPaused) {
            debugPrint('Business ${record.businessId} is PAUSED. Sync postponed.');
            continue;
          }
        }

        // Push record to Firestore
        await _firestore
            .collection(AppConstants.colBusinesses)
            .doc(record.businessId)
            .collection(AppConstants.colAttendance)
            .doc(record.attendanceId)
            .set(record.toMap());

        // Update local status as COMPLETED
        await _offlineDb.markAttendanceSynced(record.attendanceId);
        syncedCount++;
      }
    } catch (e) {
      debugPrint('Sync error: $e');
    } finally {
      _isSyncing = false;
    }

    return syncedCount;
  }

  void stopAutoSync() {
    _connectivitySubscription?.cancel();
    _periodicSyncTimer?.cancel();
  }
}
