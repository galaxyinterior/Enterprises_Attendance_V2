import 'package:flutter_test/flutter_test.dart';
import 'package:attendance_app/core/services/shift_engine_service.dart';
import 'package:attendance_app/models/shift_model.dart';

void main() {
  group('ShiftEngineService Unit Tests', () {
    final shiftEngine = ShiftEngineService();

    test('1. Normal Check-In On Time (Present)', () {
      final now = DateTime(2026, 9, 12, 9, 5); // 09:05 AM
      final result = shiftEngine.evaluateCheckInStatus(
        checkInTime: now,
        assignedShiftId: 'General Shift',
      );

      expect(result.isLate, false);
      expect(result.isPastDeadline, false);
      expect(result.lateMinutes, 0);
      expect(result.status, 'PRESENT');
    });

    test('2. Late Check-In Past Deadline (Absent Pending Reason)', () {
      final now = DateTime(2026, 9, 12, 9, 45); // 09:45 AM (30 mins after 9:15 deadline)
      final result = shiftEngine.evaluateCheckInStatus(
        checkInTime: now,
        assignedShiftId: 'General Shift',
      );

      expect(result.isLate, true);
      expect(result.isPastDeadline, true);
      expect(result.lateMinutes, 45); // 45 mins late from 09:00 AM scheduled start
      expect(result.status, 'ABSENT');
    });

    test('3. Custom Shift Evaluation with Grace Period', () {
      final customShift = ShiftModel(
        shiftId: 'SHIFT-CUSTOM-01',
        businessId: 'BIZ-01',
        shopId: 'BIZ-01',
        shiftName: 'Morning Express',
        startTime: '08:00 AM',
        endTime: '04:00 PM',
        maxCheckInTime: '08:30 AM',
        gracePeriodMinutes: 30,
        createdAt: DateTime.now(),
      );

      final checkInOnTime = DateTime(2026, 9, 12, 8, 20); // 08:20 AM (Before 08:30 deadline)
      final resOnTime = shiftEngine.evaluateCheckInStatus(
        checkInTime: checkInOnTime,
        assignedShiftId: customShift.shiftId,
        customShift: customShift,
      );

      expect(resOnTime.isLate, false);
      expect(resOnTime.status, 'PRESENT');

      final checkInLate = DateTime(2026, 9, 12, 8, 40); // 08:40 AM (After 08:30 deadline)
      final resLate = shiftEngine.evaluateCheckInStatus(
        checkInTime: checkInLate,
        assignedShiftId: customShift.shiftId,
        customShift: customShift,
      );

      expect(resLate.isLate, true);
      expect(resLate.lateMinutes, 40);
    });

    test('4. Early Checkout Calculation', () {
      final customShift = ShiftModel(
        shiftId: 'SHIFT-01',
        businessId: 'BIZ-01',
        shopId: 'BIZ-01',
        shiftName: 'Standard Day',
        startTime: '09:00 AM',
        endTime: '05:00 PM',
        maxCheckInTime: '09:15 AM',
        gracePeriodMinutes: 15,
        createdAt: DateTime.now(),
      );

      final checkIn = DateTime(2026, 9, 12, 9, 0);
      final earlyCheckout = DateTime(2026, 9, 12, 16, 30); // 4:30 PM (30 mins early)

      final checkoutRes = shiftEngine.evaluateCheckOutStatus(
        checkOutTime: earlyCheckout,
        checkInTime: checkIn,
        customShift: customShift,
      );

      expect(checkoutRes.isEarly, true);
      expect(checkoutRes.earlyCheckoutMinutes, 30);
    });

    test('5. Overnight Shift Detection and Checkout', () {
      final nightShift = ShiftModel(
        shiftId: 'NIGHT-01',
        businessId: 'BIZ-01',
        shopId: 'BIZ-01',
        shiftName: 'Night Guard Shift',
        startTime: '10:00 PM',
        endTime: '06:00 AM',
        maxCheckInTime: '10:15 PM',
        gracePeriodMinutes: 15,
        createdAt: DateTime.now(),
      );

      final checkIn = DateTime(2026, 9, 12, 22, 5); // 10:05 PM
      final checkInRes = shiftEngine.evaluateCheckInStatus(
        checkInTime: checkIn,
        assignedShiftId: nightShift.shiftId,
        customShift: nightShift,
      );

      expect(checkInRes.isOvernight, true);
      expect(checkInRes.isLate, false);

      final checkOutNextMorning = DateTime(2026, 9, 13, 6, 0); // 06:00 AM next day
      final checkoutRes = shiftEngine.evaluateCheckOutStatus(
        checkOutTime: checkOutNextMorning,
        checkInTime: checkIn,
        customShift: nightShift,
      );

      expect(checkoutRes.isEarly, false);
    });

    test('6. Idempotent Deterministic Attendance ID Generation', () {
      final id1 = shiftEngine.generateDeterministicAttendanceId(
        businessId: 'BIZ-SHOP-100',
        employeeId: 'EMP-9912',
        date: '2026-09-12',
      );

      final id2 = shiftEngine.generateDeterministicAttendanceId(
        businessId: 'BIZ-SHOP-100',
        employeeId: 'EMP-9912',
        date: '2026-09-12',
      );

      final idDifferentDate = shiftEngine.generateDeterministicAttendanceId(
        businessId: 'BIZ-SHOP-100',
        employeeId: 'EMP-9912',
        date: '2026-09-13',
      );

      expect(id1, equals(id2)); // Exact same ID generated for repeated submission
      expect(id1, isNot(equals(idDifferentDate))); // Different ID for different date
    });
  });
}
