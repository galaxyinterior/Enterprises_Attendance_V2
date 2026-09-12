import '../constants/app_constants.dart';
import '../../models/shift_model.dart';

class ShiftStatusResult {
  final String status; // AppConstants.attendancePresent / attendanceLate / AppConstants.attendanceAbsent
  final String statusLabel;
  final bool isLate;
  final bool isPastDeadline;
  final int lateMinutes;
  final String shiftName;

  ShiftStatusResult({
    required this.status,
    required this.statusLabel,
    required this.isLate,
    required this.isPastDeadline,
    required this.lateMinutes,
    required this.shiftName,
  });
}

class ShiftEngineService {
  static final ShiftEngineService _instance = ShiftEngineService._internal();
  factory ShiftEngineService() => _instance;
  ShiftEngineService._internal();

  /// Parse time string like "09:00 AM", "09:15", "06:30 PM" into (hour, minute)
  Map<String, int> _parseTimeString(String timeStr) {
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

    if (customShift != null) {
      final startParsed = _parseTimeString(customShift.startTime);
      startHour = startParsed['hour']!;
      startMinute = startParsed['minute']!;

      final deadlineParsed = _parseTimeString(customShift.maxCheckInTime);
      deadlineHour = deadlineParsed['hour']!;
      deadlineMinute = deadlineParsed['minute']!;
    } else {
      final lower = shiftName.toLowerCase();
      if (lower.contains('morning') || lower.contains('10:00 am')) {
        startHour = 10;
        startMinute = 0;
        deadlineHour = 10;
        deadlineMinute = 15;
      } else if (lower.contains('evening') || lower.contains('02:00 pm')) {
        startHour = 14;
        startMinute = 0;
        deadlineHour = 14;
        deadlineMinute = 15;
      } else if (lower.contains('night') || lower.contains('09:00 pm')) {
        startHour = 21;
        startMinute = 0;
        deadlineHour = 21;
        deadlineMinute = 15;
      } else {
        // Default General Shift: 9 AM, 9:15 AM cutoff
        startHour = 9;
        startMinute = 0;
        deadlineHour = 9;
        deadlineMinute = 15;
      }
    }

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
      );
    } else {
      return ShiftStatusResult(
        status: AppConstants.attendanceAbsent,
        statusLabel: 'Late Arrival ($lateMinutes mins late) - Pending Reason Approval',
        isLate: true,
        isPastDeadline: true,
        lateMinutes: lateMinutes,
        shiftName: shiftName,
      );
    }
  }
}
