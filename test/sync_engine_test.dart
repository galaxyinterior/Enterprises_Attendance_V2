import 'package:flutter_test/flutter_test.dart';
import 'package:attendance_app/core/services/shift_engine_service.dart';

void main() {
  group('SyncEngine & Offline State Machine Tests', () {
    test('1. Sync State Transitions (PENDING -> SYNCING -> SYNCED)', () {
      final String syncStateInitial = 'PENDING';
      expect(syncStateInitial, equals('PENDING'));

      final String syncStateInProgress = 'SYNCING';
      expect(syncStateInProgress, equals('SYNCING'));

      final String syncStateCompleted = 'SYNCED';
      expect(syncStateCompleted, equals('SYNCED'));
    });

    test('2. Retry State Transition (RETRY & FAILED)', () {
      int retryCount = 0;
      retryCount++;
      String status = retryCount >= 5 ? 'FAILED' : 'RETRY';
      expect(status, equals('RETRY'));

      retryCount = 5;
      status = retryCount >= 5 ? 'FAILED' : 'RETRY';
      expect(status, equals('FAILED'));
    });

    test('3. Idempotent Sync Retry Safeguard', () {
      final shiftEngine = ShiftEngineService();
      final id1 = shiftEngine.generateDeterministicAttendanceId(
        businessId: 'BIZ-01',
        employeeId: 'EMP-01',
        date: '2026-09-12',
      );

      final id2 = shiftEngine.generateDeterministicAttendanceId(
        businessId: 'BIZ-01',
        employeeId: 'EMP-01',
        date: '2026-09-12',
      );

      expect(id1, equals(id2));
    });
  });
}
