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

  void startAutoSync({String? activeBusinessId}) {
    _connectivitySubscription?.cancel();
    _periodicSyncTimer?.cancel();

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      if (results.any((res) => res != ConnectivityResult.none)) {
        syncPendingAttendance();
        if (activeBusinessId != null && activeBusinessId.isNotEmpty) {
          syncDownTenantData(activeBusinessId);
        }
      }
    });

    // Periodic background sync fallback every 30 seconds
    _periodicSyncTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      syncPendingAttendance();
      if (activeBusinessId != null && activeBusinessId.isNotEmpty) {
        syncDownTenantData(activeBusinessId);
      }
    });

    // Initial sync trigger on startup / reconnect
    syncPendingAttendance();
    if (activeBusinessId != null && activeBusinessId.isNotEmpty) {
      syncDownTenantData(activeBusinessId);
    }
  }

  /// SYNC DOWN: Download latest employees, face vectors, and shifts from Cloud Firestore to local SQLite
  Future<void> syncDownTenantData(String businessId) async {
    try {
      debugPrint('📥 Syncing down tenant data for $businessId from Cloud Firestore...');

      // 1. Download active employees & face embeddings
      final empSnap = await _firestore
          .collection(AppConstants.colBusinesses)
          .doc(businessId)
          .collection(AppConstants.colEmployees)
          .get()
          .timeout(const Duration(seconds: 5));

      if (empSnap.docs.isNotEmpty) {
        final empMaps = empSnap.docs
            .map((doc) => doc.data())
            .where((emp) => emp['faceEmbedding'] != null && (emp['faceEmbedding'] as List).isNotEmpty)
            .toList();

        await _offlineDb.saveLocalEmployees(empMaps);
        debugPrint('✓ Cached ${empMaps.length} employee face profiles to local SQLite!');
      }

      // 2. Download shift configurations
      final shiftSnap = await _firestore
          .collection(AppConstants.colBusinesses)
          .doc(businessId)
          .collection('shifts')
          .get()
          .timeout(const Duration(seconds: 5));

      if (shiftSnap.docs.isNotEmpty) {
        final shiftMaps = shiftSnap.docs.map((doc) => doc.data()).toList();
        await _offlineDb.saveLocalShifts(shiftMaps);
        debugPrint('✓ Cached ${shiftMaps.length} shift rules to local SQLite!');
      }
    } catch (e) {
      debugPrint('Sync down info (offline / timeout): $e');
    }
  }

  /// SYNC UP: Push queued SQLite attendance records to Cloud Firestore with state tracking & retries
  Future<int> syncPendingAttendance() async {
    if (_isSyncing) return 0;
    _isSyncing = true;
    int syncedCount = 0;

    try {
      final pendingRecords = await _offlineDb.getPendingAttendance();
      if (pendingRecords.isEmpty) {
        _isSyncing = false;
        return 0;
      }

      debugPrint('📤 Syncing up ${pendingRecords.length} pending attendance records to Cloud Firestore...');

      for (var record in pendingRecords) {
        // Mark state as SYNCING
        await _offlineDb.recordSyncAttempt(
          attendanceId: record.attendanceId,
          status: 'SYNCING',
          retryCount: 0,
        );

        try {
          // Check business status before pushing
          final bizDoc = await _firestore
              .collection(AppConstants.colBusinesses)
              .doc(record.businessId)
              .get()
              .timeout(const Duration(seconds: 3));

          if (bizDoc.exists) {
            final bizData = bizDoc.data()!;
            if (bizData['status'] == AppConstants.statusPaused) {
              debugPrint('Business ${record.businessId} is PAUSED. Sync postponed.');
              await _offlineDb.recordSyncAttempt(
                attendanceId: record.attendanceId,
                status: 'RETRY',
                retryCount: 1,
                errorMsg: 'Business account is paused',
              );
              continue;
            }
          }

          // Push record to Cloud Firestore (Idempotent operation using deterministic doc ID)
          await _firestore
              .collection(AppConstants.colBusinesses)
              .doc(record.businessId)
              .collection(AppConstants.colAttendance)
              .doc(record.attendanceId)
              .set(record.toMap())
              .timeout(const Duration(seconds: 5));

          // Update state as SYNCED with server acknowledgement
          await _offlineDb.markAttendanceSynced(record.attendanceId);
          syncedCount++;
          debugPrint('✓ Record ${record.attendanceId} synced to Cloud Firestore!');
        } catch (e) {
          debugPrint('❌ Failed syncing attendance ${record.attendanceId}: $e');
          await _offlineDb.recordSyncAttempt(
            attendanceId: record.attendanceId,
            status: 'RETRY',
            retryCount: 1,
            errorMsg: e.toString(),
          );
        }
      }
    } catch (e) {
      debugPrint('Sync engine general error: $e');
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
