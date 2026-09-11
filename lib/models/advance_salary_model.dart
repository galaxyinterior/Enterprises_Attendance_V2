class AdvanceSalaryModel {
  final String advanceId;
  final String businessId;
  final String employeeId;
  final String employeeName;
  final double amount;
  final String reason;
  final DateTime requestDate;
  final String status; // PENDING, APPROVED, REJECTED, PAID

  AdvanceSalaryModel({
    required this.advanceId,
    required this.businessId,
    required this.employeeId,
    required this.employeeName,
    required this.amount,
    required this.reason,
    required this.requestDate,
    this.status = 'PENDING',
  });

  Map<String, dynamic> toMap() {
    return {
      'advanceId': advanceId,
      'businessId': businessId,
      'employeeId': employeeId,
      'employeeName': employeeName,
      'amount': amount,
      'reason': reason,
      'requestDate': requestDate.toIso8601String(),
      'status': status,
    };
  }

  factory AdvanceSalaryModel.fromMap(Map<String, dynamic> map) {
    return AdvanceSalaryModel(
      advanceId: map['advanceId'] ?? '',
      businessId: map['businessId'] ?? '',
      employeeId: map['employeeId'] ?? '',
      employeeName: map['employeeName'] ?? '',
      amount: (map['amount'] ?? 0.0).toDouble(),
      reason: map['reason'] ?? '',
      requestDate: map['requestDate'] != null ? DateTime.parse(map['requestDate']) : DateTime.now(),
      status: map['status'] ?? 'PENDING',
    );
  }
}
