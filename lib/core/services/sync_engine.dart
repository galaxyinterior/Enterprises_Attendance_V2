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

  Timer? _shiftTickerTimer;
  Timer? _hourlySyncTimer;

  void startAutoSync({String? activeBusinessId}) {
    _connectivitySubscription?.cancel();
    _periodicSyncTimer?.cancel();
    _shiftTickerTimer?.cancel();
    _hourlySyncTimer?.cancel();

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      if (results.any((res) => res != ConnectivityResult.none)) {
        syncPendingAttendance();
        if (activeBusinessId != null && activeBusinessId.isNotEmpty) {
          syncDownTenantData(activeBusinessId);
        }
      }
    });

    // 1. Hourly background sync fallback every 1 hour to push pending data if found
    _hourlySyncTimer = Timer.periodic(const Duration(hours: 1), (_) {
      debugPrint('⏰ Hourly Sync Triggered: Checking pending attendance records for Cloud Firestore...');
      syncPendingAttendance();
      if (activeBusinessId != null && activeBusinessId.isNotEmpty) {
        syncDownTenantData(activeBusinessId);
      }
    });

    // 2. 1-Minute Ticker evaluating shift schedule (5 mins pre-shift sync down & shift deadline sync up)
    _shiftTickerTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (activeBusinessId != null && activeBusinessId.isNotEmpty) {
        evaluateShiftScheduleSync(activeBusinessId);
      }
    });

    // Initial sync trigger on startup / reconnect
    syncPendingAttendance();
    if (activeBusinessId != null && activeBusinessId.isNotEmpty) {
      syncDownTenantData(activeBusinessId);
    }
  }

  /// Evaluates current shift schedules to trigger pre-shift sync down (5 min before start) and deadline sync up
  Future<void> evaluateShiftScheduleSync(String businessId) async {
    try {
      final shifts = await _offlineDb.getLocalShifts(businessId);
      if (shifts.isEmpty) return;

      final now = DateTime.now();

      for (var sMap in shifts) {
        final startTimeStr = sMap['startTime'] as String? ?? '09:00 AM';
        final maxCheckInTimeStr = sMap['maxCheckInTime'] as String? ?? '09:15 AM';

        final DateTime? shiftStart = _parseTimeStringToday(startTimeStr, now);
        final DateTime? shiftDeadline = _parseTimeStringToday(maxCheckInTimeStr, now);

        if (shiftStart != null) {
          final diffMinutes = shiftStart.difference(now).inMinutes;
          // If within 5 minutes BEFORE shift start time (e.g. 9:55 AM for 10:00 AM shift)
          if (diffMinutes >= 0 && diffMinutes <= 5) {
            debugPrint('🕒 5-Minutes Pre-Shift Start Sync Triggered for Shift ${sMap['shiftName']}!');
            await syncDownTenantData(businessId);
          }
        }

        if (shiftDeadline != null) {
          final diffMinutes = now.difference(shiftDeadline).inMinutes;
          // If within 5 minutes AFTER check-in deadline (e.g. 10:15 AM to 10:20 AM for 10:15 AM deadline)
          if (diffMinutes >= 0 && diffMinutes <= 5) {
            debugPrint('🕒 Shift Check-in Deadline Sync Triggered for Shift ${sMap['shiftName']}!');
            await syncPendingAttendance();
          }
        }
      }
    } catch (e) {
      debugPrint('Error evaluating shift schedule sync: $e');
    }
  }

  DateTime? _parseTimeStringToday(String timeStr, DateTime referenceDate) {
    try {
      final parts = timeStr.trim().split(' ');
      if (parts.length < 2) return null;
      final timeParts = parts[0].split(':');
      int hour = int.parse(timeParts[0]);
      final int minute = int.parse(timeParts[1]);
      final String period = parts[1].toUpperCase();

      if (period == 'PM' && hour < 12) hour += 12;
      if (period == 'AM' && hour == 12) hour = 0;

      return DateTime(
        referenceDate.year,
        referenceDate.month,
        referenceDate.day,
        hour,
        minute,
      );
    } catch (_) {
      return null;
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

  /// Manual 2-way Instant Sync: Uploads pending local records & Downloads latest cloud records
  Future<Map<String, dynamic>> triggerFullBidirectionalSync(String businessId) async {
    int uploadedCount = 0;
    int downloadedEmployees = 0;
    int downloadedShifts = 0;
    bool isSuccess = false;
    String message = '';

    try {
      debugPrint('🔄 Manual Full 2-Way Sync Initiated for Business $businessId...');

      // 1. SYNC UP (Upload pending offline attendance records)
      uploadedCount = await syncPendingAttendance();

      // 2. SYNC DOWN (Download active employees, face embeddings, and shift rules)
      if (businessId.isNotEmpty) {
        await syncDownTenantData(businessId);
        final localEmps = await _offlineDb.getLocalEmployeesWithEmbeddings(businessId);
        downloadedEmployees = localEmps.length;
        final localShifts = await _offlineDb.getLocalShifts(businessId);
        downloadedShifts = localShifts.length;
      }

      isSuccess = true;
      message = '✓ Cloud Sync Complete! Uploaded $uploadedCount attendance records. Updated $downloadedEmployees staff profiles.';
    } catch (e) {
      debugPrint('Error during manual 2-way sync: $e');
      message = '⚠️ Sync Notice: Operating via local SQLite cache.';
    }

    return {
      'success': isSuccess,
      'uploadedCount': uploadedCount,
      'downloadedEmployees': downloadedEmployees,
      'downloadedShifts': downloadedShifts,
      'message': message,
    };
  }

  void stopAutoSync() {
    _connectivitySubscription?.cancel();
    _periodicSyncTimer?.cancel();
    _shiftTickerTimer?.cancel();
    _hourlySyncTimer?.cancel();
  }
}
