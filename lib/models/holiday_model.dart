class HolidayModel {
  final String id;
  final String businessId;
  final String date; // "YYYY-MM-DD"
  final String title;
  final DateTime createdAt;

  HolidayModel({
    required this.id,
    required this.businessId,
    required this.date,
    required this.title,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'businessId': businessId,
      'date': date,
      'title': title,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory HolidayModel.fromMap(Map<String, dynamic> map) {
    return HolidayModel(
      id: map['id'] ?? '',
      businessId: map['businessId'] ?? '',
      date: map['date'] ?? '',
      title: map['title'] ?? '',
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'])
          : DateTime.now(),
    );
  }
}
