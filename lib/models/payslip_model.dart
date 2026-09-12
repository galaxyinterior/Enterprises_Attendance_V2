class PayslipModel {
  final String payslipId;
  final String businessId;
  final String employeeId;
  final String employeeName;
  final String department;
  final String designation;
  final int month;
  final int year;
  final String salaryType; // MONTHLY, DAILY, HOURLY
  final double baseSalary;
  final double overtimeHours;
  final double overtimePay;
  final double bonusAmount;
  final double grossSalary;
  final double unpaidLeaveDeduction;
  final double lateDeduction;
  final double advanceDeduction;
  final double otherDeductions;
  final double totalDeductions;
  final double netSalary;
  final int totalWorkingDays;
  final int daysPresent;
  final int paidLeavesCount;
  final int unpaidLeavesCount;
  final String status; // DRAFT, FINALIZED, PAID
  final DateTime createdAt;
  final DateTime? finalizedAt;
  final DateTime? paidAt;

  PayslipModel({
    required this.payslipId,
    required this.businessId,
    required this.employeeId,
    required this.employeeName,
    required this.department,
    required this.designation,
    required this.month,
    required this.year,
    required this.salaryType,
    required this.baseSalary,
    this.overtimeHours = 0.0,
    this.overtimePay = 0.0,
    this.bonusAmount = 0.0,
    required this.grossSalary,
    this.unpaidLeaveDeduction = 0.0,
    this.lateDeduction = 0.0,
    this.advanceDeduction = 0.0,
    this.otherDeductions = 0.0,
    required this.totalDeductions,
    required this.netSalary,
    required this.totalWorkingDays,
    required this.daysPresent,
    required this.paidLeavesCount,
    required this.unpaidLeavesCount,
    this.status = 'DRAFT',
    required this.createdAt,
    this.finalizedAt,
    this.paidAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'payslipId': payslipId,
      'businessId': businessId,
      'employeeId': employeeId,
      'employeeName': employeeName,
      'department': department,
      'designation': designation,
      'month': month,
      'year': year,
      'salaryType': salaryType,
      'baseSalary': baseSalary,
      'overtimeHours': overtimeHours,
      'overtimePay': overtimePay,
      'bonusAmount': bonusAmount,
      'grossSalary': grossSalary,
      'unpaidLeaveDeduction': unpaidLeaveDeduction,
      'lateDeduction': lateDeduction,
      'advanceDeduction': advanceDeduction,
      'otherDeductions': otherDeductions,
      'totalDeductions': totalDeductions,
      'netSalary': netSalary,
      'totalWorkingDays': totalWorkingDays,
      'daysPresent': daysPresent,
      'paidLeavesCount': paidLeavesCount,
      'unpaidLeavesCount': unpaidLeavesCount,
      'status': status,
      'createdAt': createdAt.toIso8601String(),
      'finalizedAt': finalizedAt?.toIso8601String(),
      'paidAt': paidAt?.toIso8601String(),
    };
  }

  factory PayslipModel.fromMap(Map<String, dynamic> map) {
    return PayslipModel(
      payslipId: map['payslipId'] ?? '',
      businessId: map['businessId'] ?? '',
      employeeId: map['employeeId'] ?? '',
      employeeName: map['employeeName'] ?? '',
      department: map['department'] ?? 'General',
      designation: map['designation'] ?? 'Staff',
      month: map['month'] ?? DateTime.now().month,
      year: map['year'] ?? DateTime.now().year,
      salaryType: map['salaryType'] ?? 'MONTHLY',
      baseSalary: (map['baseSalary'] ?? 0.0).toDouble(),
      overtimeHours: (map['overtimeHours'] ?? 0.0).toDouble(),
      overtimePay: (map['overtimePay'] ?? 0.0).toDouble(),
      bonusAmount: (map['bonusAmount'] ?? 0.0).toDouble(),
      grossSalary: (map['grossSalary'] ?? 0.0).toDouble(),
      unpaidLeaveDeduction: (map['unpaidLeaveDeduction'] ?? 0.0).toDouble(),
      lateDeduction: (map['lateDeduction'] ?? 0.0).toDouble(),
      advanceDeduction: (map['advanceDeduction'] ?? 0.0).toDouble(),
      otherDeductions: (map['otherDeductions'] ?? 0.0).toDouble(),
      totalDeductions: (map['totalDeductions'] ?? 0.0).toDouble(),
      netSalary: (map['netSalary'] ?? 0.0).toDouble(),
      totalWorkingDays: map['totalWorkingDays'] ?? 0,
      daysPresent: map['daysPresent'] ?? 0,
      paidLeavesCount: map['paidLeavesCount'] ?? 0,
      unpaidLeavesCount: map['unpaidLeavesCount'] ?? 0,
      status: map['status'] ?? 'DRAFT',
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'])
          : DateTime.now(),
      finalizedAt: map['finalizedAt'] != null
          ? DateTime.parse(map['finalizedAt'])
          : null,
      paidAt: map['paidAt'] != null ? DateTime.parse(map['paidAt']) : null,
    );
  }
}
