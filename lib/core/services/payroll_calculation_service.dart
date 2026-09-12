import '../../models/employee_model.dart';
import '../../models/payslip_model.dart';

/// Canonical service for deterministic payroll calculation.
/// Guarantees exact financial math independent of UI state.
class PayrollCalculationService {
  PayrollCalculationService._();

  /// Calculates a finalized or draft payslip for a given employee and period.
  static PayslipModel calculatePayslip({
    required EmployeeModel employee,
    required int month,
    required int year,
    required int totalWorkingDays,
    required int daysPresent,
    required int paidLeavesCount,
    required int unpaidLeavesCount,
    int lateDays = 0,
    double lateFinePerDay = 0.0,
    double overtimeHours = 0.0,
    double overtimeRateMultiplier = 1.5,
    double bonusAmount = 0.0,
    double advanceDeduction = 0.0,
    double otherDeductions = 0.0,
    String status = 'DRAFT',
  }) {
    if (totalWorkingDays <= 0) {
      totalWorkingDays = 30; // Fallback standard working month
    }

    double baseSalary = 0.0;
    double unpaidLeaveDeduction = 0.0;
    double perDayRate = 0.0;
    double hourlyRate = employee.hourlyRate;

    final String salaryType = employee.salaryType.toUpperCase();

    if (salaryType == 'MONTHLY') {
      baseSalary = employee.monthlySalary;
      perDayRate = baseSalary / totalWorkingDays;
      if (hourlyRate <= 0) {
        hourlyRate = perDayRate / 8.0;
      }
      unpaidLeaveDeduction = unpaidLeavesCount * perDayRate;
    } else if (salaryType == 'DAILY') {
      perDayRate = employee.dailySalary;
      baseSalary = (daysPresent + paidLeavesCount) * perDayRate;
      if (hourlyRate <= 0) {
        hourlyRate = perDayRate / 8.0;
      }
      unpaidLeaveDeduction = 0.0; // Base salary is earned per worked/paid day
    } else if (salaryType == 'HOURLY') {
      hourlyRate = employee.hourlyRate > 0 ? employee.hourlyRate : 10.0;
      baseSalary = (daysPresent * 8 + paidLeavesCount * 8) * hourlyRate;
      unpaidLeaveDeduction = 0.0;
    } else {
      baseSalary = employee.monthlySalary;
      perDayRate = baseSalary / totalWorkingDays;
      hourlyRate = perDayRate / 8.0;
      unpaidLeaveDeduction = unpaidLeavesCount * perDayRate;
    }

    final double overtimePay = overtimeHours * hourlyRate * overtimeRateMultiplier;
    final double lateDeduction = lateDays * lateFinePerDay;

    final double grossSalary = baseSalary + overtimePay + bonusAmount;
    final double totalDeductions =
        unpaidLeaveDeduction + lateDeduction + advanceDeduction + otherDeductions;
    final double rawNetSalary = grossSalary - totalDeductions;
    final double netSalary = rawNetSalary < 0.0 ? 0.0 : rawNetSalary;

    return PayslipModel(
      payslipId: 'PAY-${employee.employeeId}-$year-${month.toString().padLeft(2, '0')}',
      businessId: employee.businessId,
      employeeId: employee.employeeId,
      employeeName: employee.fullName,
      department: employee.department,
      designation: employee.designation,
      month: month,
      year: year,
      salaryType: salaryType,
      baseSalary: _round2(baseSalary),
      overtimeHours: _round2(overtimeHours),
      overtimePay: _round2(overtimePay),
      bonusAmount: _round2(bonusAmount),
      grossSalary: _round2(grossSalary),
      unpaidLeaveDeduction: _round2(unpaidLeaveDeduction),
      lateDeduction: _round2(lateDeduction),
      advanceDeduction: _round2(advanceDeduction),
      otherDeductions: _round2(otherDeductions),
      totalDeductions: _round2(totalDeductions),
      netSalary: _round2(netSalary),
      totalWorkingDays: totalWorkingDays,
      daysPresent: daysPresent,
      paidLeavesCount: paidLeavesCount,
      unpaidLeavesCount: unpaidLeavesCount,
      status: status,
      createdAt: DateTime.now(),
    );
  }

  static double _round2(double val) {
    return double.parse(val.toStringAsFixed(2));
  }
}
