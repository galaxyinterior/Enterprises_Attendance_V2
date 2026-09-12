class AdvanceSalaryModel {
  final String id;
  final String businessId;
  final String employeeId;
  final String employeeName;
  final double amount;
  final String date; // "YYYY-MM-DD"
  final String reason;
  final String status; // PENDING, APPROVED, REJECTED
  final DateTime createdAt;

  AdvanceSalaryModel({
    required this.id,
    required this.businessId,
    required this.employeeId,
    required this.employeeName,
    required this.amount,
    required this.date,
    required this.reason,
    this.status = 'APPROVED',
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'businessId': businessId,
      'employeeId': employeeId,
      'employeeName': employeeName,
      'amount': amount,
      'date': date,
      'reason': reason,
      'status': status,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory AdvanceSalaryModel.fromMap(Map<String, dynamic> map) {
    return AdvanceSalaryModel(
      id: map['id'] ?? '',
      businessId: map['businessId'] ?? '',
      employeeId: map['employeeId'] ?? '',
      employeeName: map['employeeName'] ?? '',
      amount: (map['amount'] ?? 0.0).toDouble(),
      date: map['date'] ?? '',
      reason: map['reason'] ?? '',
      status: map['status'] ?? 'APPROVED',
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'])
          : DateTime.now(),
    );
  }
}
