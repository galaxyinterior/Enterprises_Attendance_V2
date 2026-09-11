import '../constants/app_constants.dart';

class ShiftStatusResult {
  final String status; // AppConstants.attendancePresent / attendanceLate / attendanceHalfDay
  final String statusLabel;
  final bool isLate;
  final String shiftName;

  ShiftStatusResult({
    required this.status,
    required this.statusLabel,
    required this.isLate,
    required this.shiftName,
  });
}

class ShiftEngineService {
  static final ShiftEngineService _instance = ShiftEngineService._internal();
  factory ShiftEngineService() => _instance;
  ShiftEngineService._internal();

  /// Evaluate employee check-in timestamp against assigned shift
  ShiftStatusResult evaluateCheckInStatus({
    required DateTime checkInTime,
    required String assignedShiftId,
  }) {
    final shiftName = assignedShiftId.isNotEmpty
        ? assignedShiftId
        : 'Morning Shift (10:00 AM - 06:30 PM)';

    int startHour = 10;
    int startMinute = 0;
    int graceMinutes = 15;

    final lowerShift = shiftName.toLowerCase();

    if (lowerShift.contains('morning') || lowerShift.contains('10:00 am')) {
      startHour = 10;
      startMinute = 0;
    } else if (lowerShift.contains('general') || lowerShift.contains('09:00 am')) {
      startHour = 9;
      startMinute = 0;
    } else if (lowerShift.contains('evening') || lowerShift.contains('02:00 pm')) {
      startHour = 14;
      startMinute = 0;
    } else if (lowerShift.contains('night') || lowerShift.contains('09:00 pm')) {
      startHour = 21;
      startMinute = 0;
    }

    final scheduledStartTime = DateTime(
      checkInTime.year,
      checkInTime.month,
      checkInTime.day,
      startHour,
      startMinute,
    );

    final graceEndTime = scheduledStartTime.add(Duration(minutes: graceMinutes));
    final halfDayCutoff = scheduledStartTime.add(const Duration(hours: 4));

    if (checkInTime.isBefore(graceEndTime) || checkInTime.isAtSameMomentAs(graceEndTime)) {
      return ShiftStatusResult(
        status: AppConstants.attendancePresent,
        statusLabel: 'On Time (Present)',
        isLate: false,
        shiftName: shiftName,
      );
    } else if (checkInTime.isBefore(halfDayCutoff)) {
      final lateMinutes = checkInTime.difference(scheduledStartTime).inMinutes;
      return ShiftStatusResult(
        status: AppConstants.attendanceLate,
        statusLabel: 'Late Arrival ($lateMinutes mins late)',
        isLate: true,
        shiftName: shiftName,
      );
    } else {
      return ShiftStatusResult(
        status: AppConstants.attendanceHalfDay,
        statusLabel: 'Half Day Arrival',
        isLate: true,
        shiftName: shiftName,
      );
    }
  }
}
