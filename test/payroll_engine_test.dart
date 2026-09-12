import 'package:flutter_test/flutter_test.dart';
import 'package:attendance_app/models/employee_model.dart';
import 'package:attendance_app/models/leave_request_model.dart';
import 'package:attendance_app/models/payslip_model.dart';
import 'package:attendance_app/core/services/payroll_calculation_service.dart';
import 'package:attendance_app/core/services/leave_management_service.dart';

void main() {
  group('Payroll & Leave Engine Unit Tests', () {
    late EmployeeModel monthlyEmployee;
    late EmployeeModel dailyEmployee;
    late EmployeeModel hourlyEmployee;

    setUp(() {
      monthlyEmployee = EmployeeModel(
        employeeId: 'EMP-001',
        businessId: 'BIZ-100',
        employeeCode: 'E001',
        fullName: 'Aarav Sharma',
        phone: '+919876543210',
        department: 'Engineering',
        designation: 'Software Developer',
        assignedShiftId: 'SHIFT-01',
        joiningDate: DateTime(2025, 1, 1),
        salaryType: 'MONTHLY',
        monthlySalary: 60000.0,
        casualLeaveBalance: 12,
        sickLeaveBalance: 6,
        paidLeaveBalance: 15,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      dailyEmployee = EmployeeModel(
        employeeId: 'EMP-002',
        businessId: 'BIZ-100',
        employeeCode: 'E002',
        fullName: 'Vikram Singh',
        phone: '+919876543211',
        department: 'Operations',
        designation: 'Site Supervisor',
        assignedShiftId: 'SHIFT-01',
        joiningDate: DateTime(2025, 1, 1),
        salaryType: 'DAILY',
        dailySalary: 1500.0,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      hourlyEmployee = EmployeeModel(
        employeeId: 'EMP-003',
        businessId: 'BIZ-100',
        employeeCode: 'E003',
        fullName: 'Priya Verma',
        phone: '+919876543212',
        department: 'Support',
        designation: 'Consultant',
        assignedShiftId: 'SHIFT-01',
        joiningDate: DateTime(2025, 1, 1),
        salaryType: 'HOURLY',
        hourlyRate: 300.0,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    });

    test('1. Monthly Base Salary - Full Attendance (Zero Absences)', () {
      final PayslipModel payslip = PayrollCalculationService.calculatePayslip(
        employee: monthlyEmployee,
        month: 9,
        year: 2026,
        totalWorkingDays: 30,
        daysPresent: 30,
        paidLeavesCount: 0,
        unpaidLeavesCount: 0,
      );

      expect(payslip.baseSalary, equals(60000.0));
      expect(payslip.unpaidLeaveDeduction, equals(0.0));
      expect(payslip.grossSalary, equals(60000.0));
      expect(payslip.netSalary, equals(60000.0));
    });

    test('2. Monthly Base Salary with Unpaid Leaves Deduction', () {
      // 30 working days, 2 unpaid leaves (Per day rate = 60000 / 30 = 2000)
      final PayslipModel payslip = PayrollCalculationService.calculatePayslip(
        employee: monthlyEmployee,
        month: 9,
        year: 2026,
        totalWorkingDays: 30,
        daysPresent: 28,
        paidLeavesCount: 0,
        unpaidLeavesCount: 2,
      );

      expect(payslip.unpaidLeaveDeduction, equals(4000.0));
      expect(payslip.totalDeductions, equals(4000.0));
      expect(payslip.netSalary, equals(56000.0));
    });

    test('3. Overtime Pay with Custom Rate Multiplier (1.5x)', () {
      // Per day rate = 2000, Hourly rate = 250. 10 hours overtime @ 1.5x = 10 * 250 * 1.5 = 3750
      final PayslipModel payslip = PayrollCalculationService.calculatePayslip(
        employee: monthlyEmployee,
        month: 9,
        year: 2026,
        totalWorkingDays: 30,
        daysPresent: 30,
        paidLeavesCount: 0,
        unpaidLeavesCount: 0,
        overtimeHours: 10.0,
        overtimeRateMultiplier: 1.5,
      );

      expect(payslip.overtimePay, equals(3750.0));
      expect(payslip.grossSalary, equals(63750.0));
      expect(payslip.netSalary, equals(63750.0));
    });

    test('4. Salary Advance & Late Arrival Fine Deductions', () {
      final PayslipModel payslip = PayrollCalculationService.calculatePayslip(
        employee: monthlyEmployee,
        month: 9,
        year: 2026,
        totalWorkingDays: 30,
        daysPresent: 30,
        paidLeavesCount: 0,
        unpaidLeavesCount: 0,
        lateDays: 3,
        lateFinePerDay: 500.0, // 1500 late fine
        advanceDeduction: 5000.0, // 5000 advance
        bonusAmount: 2000.0, // 2000 bonus
      );

      expect(payslip.lateDeduction, equals(1500.0));
      expect(payslip.advanceDeduction, equals(5000.0));
      expect(payslip.grossSalary, equals(62000.0));
      expect(payslip.totalDeductions, equals(6500.0));
      expect(payslip.netSalary, equals(55500.0));
    });

    test('5. Daily & Hourly Employee Wage Calculations', () {
      // Daily employee: 20 present days + 2 paid leaves @ 1500/day = 22 * 1500 = 33000
      final PayslipModel dailyPayslip = PayrollCalculationService.calculatePayslip(
        employee: dailyEmployee,
        month: 9,
        year: 2026,
        totalWorkingDays: 25,
        daysPresent: 20,
        paidLeavesCount: 2,
        unpaidLeavesCount: 3,
      );

      expect(dailyPayslip.baseSalary, equals(33000.0));
      expect(dailyPayslip.netSalary, equals(33000.0));

      // Hourly employee: 15 present days (120 hrs) + 1 paid leave day (8 hrs) @ 300/hr = 128 * 300 = 38400
      final PayslipModel hourlyPayslip = PayrollCalculationService.calculatePayslip(
        employee: hourlyEmployee,
        month: 9,
        year: 2026,
        totalWorkingDays: 25,
        daysPresent: 15,
        paidLeavesCount: 1,
        unpaidLeavesCount: 9,
      );

      expect(hourlyPayslip.baseSalary, equals(38400.0));
      expect(hourlyPayslip.netSalary, equals(38400.0));
    });

    test('6. Leave Window Calculation Excluding Weekly Offs & Holidays', () {
      // Monday 2026-09-14 to Sunday 2026-09-20 (7 calendar days)
      // Sunday is Weekly Off. Wednesday 2026-09-16 is a Holiday.
      // Net working days should be 7 - 1 (Sunday) - 1 (Wednesday Holiday) = 5 days.
      final int workingDays = LeaveManagementService.calculateWorkingDaysInLeaveWindow(
        startDate: DateTime(2026, 9, 14),
        endDate: DateTime(2026, 9, 20),
        weeklyOffDays: ['SUNDAY'],
        holidayDatesISO: ['2026-09-16'],
      );

      expect(workingDays, equals(5));
    });

    test('7. Leave Approval & Entitlement Balance Decrement', () {
      final LeaveRequestModel request = LeaveRequestModel(
        leaveId: 'LV-100',
        businessId: 'BIZ-100',
        employeeId: 'EMP-001',
        employeeName: 'Aarav Sharma',
        leaveType: 'CASUAL',
        startDate: DateTime(2026, 9, 14),
        endDate: DateTime(2026, 9, 15), // 2 working days (Mon, Tue)
        reason: 'Personal work',
        createdAt: DateTime.now(),
      );

      final LeaveApprovalResult result = LeaveManagementService.approveLeaveRequest(
        request: request,
        employee: monthlyEmployee,
        reviewerId: 'ADMIN-01',
      );

      expect(result.updatedRequest.status, equals('APPROVED'));
      expect(result.updatedRequest.reviewedBy, equals('ADMIN-01'));
      expect(result.daysDeducted, equals(2));
      expect(result.updatedEmployee.casualLeaveBalance, equals(10)); // 12 - 2 = 10
    });
  });
}
