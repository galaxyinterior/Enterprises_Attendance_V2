import 'package:crypto/crypto.dart';
import 'dart:convert';
import '../constants/app_constants.dart';
import '../../models/shift_model.dart';

class ShiftStatusResult {
  final String status; // PRESENT / ABSENT (PENDING) / LATE
  final String statusLabel;
  final bool isLate;
  final bool isPastDeadline;
  final int lateMinutes;
  final String shiftName;
  final bool isOvernight;

  ShiftStatusResult({
    required this.status,
    required this.statusLabel,
    required this.isLate,
    required this.isPastDeadline,
    required this.lateMinutes,
    required this.shiftName,
    this.isOvernight = false,
  });
}

class CheckOutStatusResult {
  final bool isEarly;
  final int earlyCheckoutMinutes;
  final String label;

  CheckOutStatusResult({
    required this.isEarly,
    required this.earlyCheckoutMinutes,
    required this.label,
  });
}

class ShiftEngineService {
  static final ShiftEngineService _instance = ShiftEngineService._internal();
  factory ShiftEngineService() => _instance;
  ShiftEngineService._internal();

  /// Parse time string like "09:00 AM", "09:15", "06:30 PM", "22:00" into (hour, minute)
  Map<String, int> parseTimeString(String timeStr) {
    if (timeStr.isEmpty) return {'hour': 9, 'minute': 0};
    try {
      final clean = timeStr.trim().toUpperCase();
      bool isPm = clean.contains('PM');
      bool isAm = clean.contains('AM');
      String text = clean.replaceAll('AM', '').replaceAll('PM', '').trim();

      final parts = text.split(':');
      int hour = int.parse(parts[0]);
      int minute = parts.length > 1 ? int.parse(parts[1]) : 0;

      if (isPm && hour < 12) hour += 12;
      if (isAm && hour == 12) hour = 0;

      return {'hour': hour, 'minute': minute};
    } catch (_) {
      return {'hour': 9, 'minute': 0};
    }
  }

  /// Generate a deterministic, idempotent Event ID for attendance records
  /// Guarantees that repeated submissions for the same employee, business, and date produce the EXACT same document ID
  String generateDeterministicAttendanceId({
    required String businessId,
    required String employeeId,
    required String date,
  }) {
    final rawKey = '$businessId:$employeeId:$date';
    final bytes = utf8.encode(rawKey);
    final digest = sha256.convert(bytes);
    return 'ATT-${digest.toString().substring(0, 24)}';
  }

  /// Evaluate employee check-in timestamp against shift model or shift string
  ShiftStatusResult evaluateCheckInStatus({
    required DateTime checkInTime,
    required String assignedShiftId,
    ShiftModel? customShift,
  }) {
    String shiftName = customShift?.shiftName ?? (assignedShiftId.isNotEmpty ? assignedShiftId : 'General Shift (09:00 AM - 06:00 PM)');

    int startHour = 9;
    int startMinute = 0;
    int deadlineHour = 9;
    int deadlineMinute = 15;
    int endHour = 18;

    if (customShift != null) {
      final startParsed = parseTimeString(customShift.startTime);
      startHour = startParsed['hour']!;
      startMinute = startParsed['minute']!;

      final deadlineParsed = parseTimeString(customShift.maxCheckInTime);
      deadlineHour = deadlineParsed['hour']!;
      deadlineMinute = deadlineParsed['minute']!;

      final endParsed = parseTimeString(customShift.endTime);
      endHour = endParsed['hour']!;
    } else {
      final lower = shiftName.toLowerCase();
      if (lower.contains('morning') || lower.contains('10:00 am')) {
        startHour = 10;
        startMinute = 0;
        deadlineHour = 10;
        deadlineMinute = 15;
        endHour = 19;
      } else if (lower.contains('evening') || lower.contains('02:00 pm')) {
        startHour = 14;
        startMinute = 0;
        deadlineHour = 14;
        deadlineMinute = 15;
        endHour = 22;
      } else if (lower.contains('night') || lower.contains('09:00 pm')) {
        startHour = 21;
        startMinute = 0;
        deadlineHour = 21;
        deadlineMinute = 15;
        endHour = 6;
      }
    }

    bool isOvernight = (endHour < startHour);

    final scheduledStart = DateTime(
      checkInTime.year,
      checkInTime.month,
      checkInTime.day,
      startHour,
      startMinute,
    );

    final deadlineTime = DateTime(
      checkInTime.year,
      checkInTime.month,
      checkInTime.day,
      deadlineHour,
      deadlineMinute,
    );

    final bool isPastDeadline = checkInTime.isAfter(deadlineTime);
    final int lateMinutes = isPastDeadline ? checkInTime.difference(scheduledStart).inMinutes : 0;

    if (!isPastDeadline) {
      return ShiftStatusResult(
        status: AppConstants.attendancePresent,
        statusLabel: 'On Time (Present)',
        isLate: false,
        isPastDeadline: false,
        lateMinutes: 0,
        shiftName: shiftName,
        isOvernight: isOvernight,
      );
    } else {
      return ShiftStatusResult(
        status: AppConstants.attendanceAbsent,
        statusLabel: 'Late Arrival ($lateMinutes mins late) - Pending Reason Approval',
        isLate: true,
        isPastDeadline: true,
        lateMinutes: lateMinutes,
        shiftName: shiftName,
        isOvernight: isOvernight,
      );
    }
  }

  /// Evaluate employee check-out timestamp against shift end time
  CheckOutStatusResult evaluateCheckOutStatus({
    required DateTime checkOutTime,
    required DateTime checkInTime,
    ShiftModel? customShift,
  }) {
    int endHour = 18;
    int endMinute = 0;
    int startHour = 9;

    if (customShift != null) {
      final endParsed = parseTimeString(customShift.endTime);
      endHour = endParsed['hour']!;
      endMinute = endParsed['minute']!;

      final startParsed = parseTimeString(customShift.startTime);
      startHour = startParsed['hour']!;
    }

    bool isOvernight = (endHour < startHour);
    DateTime scheduledEnd = DateTime(
      checkInTime.year,
      checkInTime.month,
      checkInTime.day + (isOvernight ? 1 : 0),
      endHour,
      endMinute,
    );

    if (checkOutTime.isBefore(scheduledEnd)) {
      final earlyMins = scheduledEnd.difference(checkOutTime).inMinutes;
      return CheckOutStatusResult(
        isEarly: true,
        earlyCheckoutMinutes: earlyMins,
        label: 'Early Checkout ($earlyMins mins before shift end)',
      );
    }

    return CheckOutStatusResult(
      isEarly: false,
      earlyCheckoutMinutes: 0,
      label: 'Standard Checkout (Shift Complete)',
    );
  }
}
