class EmployeeModel {
  final String employeeId;
  final String businessId;
  final String employeeCode;
  final String fullName;
  final String phone;
  final String? email;
  final String? profilePhotoUrl;
  final List<double>? faceEmbedding; // 128D MobileFaceNet feature vector
  final bool faceEnrollmentStatus;
  final String department;
  final String designation;
  final String assignedShiftId;
  final DateTime joiningDate;
  final String salaryType; // MONTHLY, DAILY, HOURLY
  final double monthlySalary;
  final double dailySalary;
  final double hourlyRate;
  final int casualLeaveBalance;
  final int sickLeaveBalance;
  final int paidLeaveBalance;
  final bool active;
  final DateTime createdAt;
  final DateTime updatedAt;

  EmployeeModel({
    required this.employeeId,
    required this.businessId,
    required this.employeeCode,
    required this.fullName,
    required this.phone,
    this.email,
    this.profilePhotoUrl,
    this.faceEmbedding,
    this.faceEnrollmentStatus = false,
    required this.department,
    required this.designation,
    required this.assignedShiftId,
    required this.joiningDate,
    this.salaryType = 'MONTHLY',
    this.monthlySalary = 0.0,
    this.dailySalary = 0.0,
    this.hourlyRate = 0.0,
    this.casualLeaveBalance = 12,
    this.sickLeaveBalance = 6,
    this.paidLeaveBalance = 15,
    this.active = true,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'employeeId': employeeId,
      'businessId': businessId,
      'employeeCode': employeeCode,
      'fullName': fullName,
      'phone': phone,
      'email': email,
      'profilePhotoUrl': profilePhotoUrl,
      'faceEmbedding': faceEmbedding,
      'faceEnrollmentStatus': faceEnrollmentStatus,
      'department': department,
      'designation': designation,
      'assignedShiftId': assignedShiftId,
      'joiningDate': joiningDate.toIso8601String(),
      'salaryType': salaryType,
      'monthlySalary': monthlySalary,
      'dailySalary': dailySalary,
      'hourlyRate': hourlyRate,
      'casualLeaveBalance': casualLeaveBalance,
      'sickLeaveBalance': sickLeaveBalance,
      'paidLeaveBalance': paidLeaveBalance,
      'active': active,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory EmployeeModel.fromMap(Map<String, dynamic> map) {
    return EmployeeModel(
      employeeId: map['employeeId'] ?? '',
      businessId: map['businessId'] ?? '',
      employeeCode: map['employeeCode'] ?? '',
      fullName: map['fullName'] ?? '',
      phone: map['phone'] ?? '',
      email: map['email'],
      profilePhotoUrl: map['profilePhotoUrl'],
      faceEmbedding: map['faceEmbedding'] != null
          ? List<double>.from(map['faceEmbedding'].map((x) => (x as num).toDouble()))
          : null,
      faceEnrollmentStatus: map['faceEnrollmentStatus'] ?? false,
      department: map['department'] ?? 'General',
      designation: map['designation'] ?? 'Staff',
      assignedShiftId: map['assignedShiftId'] ?? '',
      joiningDate: map['joiningDate'] != null
          ? DateTime.parse(map['joiningDate'])
          : DateTime.now(),
      salaryType: map['salaryType'] ?? 'MONTHLY',
      monthlySalary: (map['monthlySalary'] ?? 0.0).toDouble(),
      dailySalary: (map['dailySalary'] ?? 0.0).toDouble(),
      hourlyRate: (map['hourlyRate'] ?? 0.0).toDouble(),
      casualLeaveBalance: map['casualLeaveBalance'] ?? 12,
      sickLeaveBalance: map['sickLeaveBalance'] ?? 6,
      paidLeaveBalance: map['paidLeaveBalance'] ?? 15,
      active: map['active'] ?? true,
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'])
          : DateTime.now(),
      updatedAt: map['updatedAt'] != null
          ? DateTime.parse(map['updatedAt'])
          : DateTime.now(),
    );
  }
}
