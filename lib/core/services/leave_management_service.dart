import '../../models/employee_model.dart';
import '../../models/leave_request_model.dart';

class LeaveApprovalResult {
  final LeaveRequestModel updatedRequest;
  final EmployeeModel updatedEmployee;
  final int daysDeducted;
  final String note;

  LeaveApprovalResult({
    required this.updatedRequest,
    required this.updatedEmployee,
    required this.daysDeducted,
    required this.note,
  });
}

/// Canonical service managing leave entitlements, balance deductions,
/// and holiday/weekly-off exclusions.
class LeaveManagementService {
  LeaveManagementService._();

  /// Calculates net working days within a leave window, excluding weekly off days and holidays.
  static int calculateWorkingDaysInLeaveWindow({
    required DateTime startDate,
    required DateTime endDate,
    List<String> weeklyOffDays = const ['SUNDAY'],
    List<String> holidayDatesISO = const [],
  }) {
    if (endDate.isBefore(startDate)) return 0;

    int workingDays = 0;
    DateTime current = DateTime(startDate.year, startDate.month, startDate.day);
    final DateTime last = DateTime(endDate.year, endDate.month, endDate.day);

    final Set<String> holidaysSet = Set.from(holidayDatesISO);
    final Set<int> weeklyOffWeekdaySet = weeklyOffDays.map((day) {
      switch (day.toUpperCase()) {
        case 'MONDAY':
          return DateTime.monday;
        case 'TUESDAY':
          return DateTime.tuesday;
        case 'WEDNESDAY':
          return DateTime.wednesday;
        case 'THURSDAY':
          return DateTime.thursday;
        case 'FRIDAY':
          return DateTime.friday;
        case 'SATURDAY':
          return DateTime.saturday;
        case 'SUNDAY':
        default:
          return DateTime.sunday;
      }
    }).toSet();

    while (!current.isAfter(last)) {
      final String dateStr =
          "${current.year}-${current.month.toString().padLeft(2, '0')}-${current.day.toString().padLeft(2, '0')}";

      final bool isWeeklyOff = weeklyOffWeekdaySet.contains(current.weekday);
      final bool isHoliday = holidaysSet.contains(dateStr);

      if (!isWeeklyOff && !isHoliday) {
        workingDays++;
      }

      current = current.add(const Duration(days: 1));
    }

    return workingDays;
  }

  /// Approves a leave request, deducting from employee leave balance if applicable.
  static LeaveApprovalResult approveLeaveRequest({
    required LeaveRequestModel request,
    required EmployeeModel employee,
    required String reviewerId,
    List<String> weeklyOffDays = const ['SUNDAY'],
    List<String> holidayDatesISO = const [],
  }) {
    final int leaveDays = calculateWorkingDaysInLeaveWindow(
      startDate: request.startDate,
      endDate: request.endDate,
      weeklyOffDays: weeklyOffDays,
      holidayDatesISO: holidayDatesISO,
    );

    int casualBalance = employee.casualLeaveBalance;
    int sickBalance = employee.sickLeaveBalance;
    int paidBalance = employee.paidLeaveBalance;

    String finalType = request.leaveType.toUpperCase();
    String note = "Approved for $leaveDays working days.";

    if (finalType == 'CASUAL') {
      if (casualBalance >= leaveDays) {
        casualBalance -= leaveDays;
      } else {
        final int remaining = leaveDays - casualBalance;
        casualBalance = 0;
        finalType = 'UNPAID';
        note = "Partial balance exceeded. Converted $remaining days to UNPAID leave.";
      }
    } else if (finalType == 'SICK') {
      if (sickBalance >= leaveDays) {
        sickBalance -= leaveDays;
      } else {
        final int remaining = leaveDays - sickBalance;
        sickBalance = 0;
        finalType = 'UNPAID';
        note = "Sick balance exceeded. Converted $remaining days to UNPAID leave.";
      }
    } else if (finalType == 'PAID') {
      if (paidBalance >= leaveDays) {
        paidBalance -= leaveDays;
      } else {
        final int remaining = leaveDays - paidBalance;
        paidBalance = 0;
        finalType = 'UNPAID';
        note = "Paid leave balance exceeded. Converted $remaining days to UNPAID leave.";
      }
    }

    final updatedEmployee = EmployeeModel(
      employeeId: employee.employeeId,
      businessId: employee.businessId,
      employeeCode: employee.employeeCode,
      fullName: employee.fullName,
      phone: employee.phone,
      email: employee.email,
      profilePhotoUrl: employee.profilePhotoUrl,
      faceEmbedding: employee.faceEmbedding,
      faceEnrollmentStatus: employee.faceEnrollmentStatus,
      department: employee.department,
      designation: employee.designation,
      assignedShiftId: employee.assignedShiftId,
      joiningDate: employee.joiningDate,
      salaryType: employee.salaryType,
      monthlySalary: employee.monthlySalary,
      dailySalary: employee.dailySalary,
      hourlyRate: employee.hourlyRate,
      casualLeaveBalance: casualBalance,
      sickLeaveBalance: sickBalance,
      paidLeaveBalance: paidBalance,
      active: employee.active,
      createdAt: employee.createdAt,
      updatedAt: DateTime.now(),
    );

    final updatedRequest = LeaveRequestModel(
      leaveId: request.leaveId,
      businessId: request.businessId,
      employeeId: request.employeeId,
      employeeName: request.employeeName,
      leaveType: finalType,
      startDate: request.startDate,
      endDate: request.endDate,
      reason: request.reason,
      status: 'APPROVED',
      reviewedBy: reviewerId,
      reviewedAt: DateTime.now(),
      createdAt: request.createdAt,
    );

    return LeaveApprovalResult(
      updatedRequest: updatedRequest,
      updatedEmployee: updatedEmployee,
      daysDeducted: leaveDays,
      note: note,
    );
  }

  /// Rejects a leave request.
  static LeaveRequestModel rejectLeaveRequest({
    required LeaveRequestModel request,
    required String reviewerId,
    required String reason,
  }) {
    return LeaveRequestModel(
      leaveId: request.leaveId,
      businessId: request.businessId,
      employeeId: request.employeeId,
      employeeName: request.employeeName,
      leaveType: request.leaveType,
      startDate: request.startDate,
      endDate: request.endDate,
      reason: request.reason,
      status: 'REJECTED',
      reviewedBy: reviewerId,
      reviewedAt: DateTime.now(),
      rejectionReason: reason,
      createdAt: request.createdAt,
    );
  }

  /// Maps leave status to attendance record code.
  static String getAttendanceStatusCodeForLeave(String leaveType) {
    switch (leaveType.toUpperCase()) {
      case 'CASUAL':
        return 'CASUAL_LEAVE';
      case 'SICK':
        return 'SICK_LEAVE';
      case 'PAID':
        return 'PAID_LEAVE';
      case 'UNPAID':
      default:
        return 'UNPAID_LEAVE';
    }
  }
}
