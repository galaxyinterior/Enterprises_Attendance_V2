class LeaveRequestModel {
  final String leaveId;
  final String businessId;
  final String employeeId;
  final String employeeName;
  final String leaveType; // CASUAL, SICK, PAID, UNPAID
  final DateTime startDate;
  final DateTime endDate;
  final String reason;
  final String status; // PENDING, APPROVED, REJECTED
  final DateTime createdAt;

  LeaveRequestModel({
    required this.leaveId,
    required this.businessId,
    required this.employeeId,
    required this.employeeName,
    required this.leaveType,
    required this.startDate,
    required this.endDate,
    required this.reason,
    this.status = 'PENDING',
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'leaveId': leaveId,
      'businessId': businessId,
      'employeeId': employeeId,
      'employeeName': employeeName,
      'leaveType': leaveType,
      'startDate': startDate.toIso8601String(),
      'endDate': endDate.toIso8601String(),
      'reason': reason,
      'status': status,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory LeaveRequestModel.fromMap(Map<String, dynamic> map) {
    return LeaveRequestModel(
      leaveId: map['leaveId'] ?? '',
      businessId: map['businessId'] ?? '',
      employeeId: map['employeeId'] ?? '',
      employeeName: map['employeeName'] ?? '',
      leaveType: map['leaveType'] ?? 'CASUAL',
      startDate: map['startDate'] != null ? DateTime.parse(map['startDate']) : DateTime.now(),
      endDate: map['endDate'] != null ? DateTime.parse(map['endDate']) : DateTime.now(),
      reason: map['reason'] ?? '',
      status: map['status'] ?? 'PENDING',
      createdAt: map['createdAt'] != null ? DateTime.parse(map['createdAt']) : DateTime.now(),
    );
  }
}
