class ShiftModel {
  final String shiftId;
  final String businessId;
  final String shopId;
  final String shiftName;
  final String startTime; // "09:00 AM" or "09:00"
  final String endTime; // "06:00 PM" or "18:00"
  final String maxCheckInTime; // "09:15 AM" or "09:15" (Check-in Deadline)
  final String checkInWindowStart; // "08:30 AM"
  final String checkInWindowEnd; // "10:30 AM"
  final String checkOutWindowStart; // "05:30 PM"
  final String checkOutWindowEnd; // "07:30 PM"
  final int gracePeriodMinutes; // e.g. 15 minutes
  final bool allowLateAttendance;
  final bool isOvernight;
  final DateTime? createdAt;

  ShiftModel({
    required this.shiftId,
    required this.businessId,
    this.shopId = '',
    required this.shiftName,
    required this.startTime,
    required this.endTime,
    required this.maxCheckInTime,
    this.checkInWindowStart = '',
    this.checkInWindowEnd = '',
    this.checkOutWindowStart = '',
    this.checkOutWindowEnd = '',
    this.gracePeriodMinutes = 15,
    this.allowLateAttendance = true,
    this.isOvernight = false,
    this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'shiftId': shiftId,
      'businessId': businessId,
      'shopId': shopId,
      'shiftName': shiftName,
      'startTime': startTime,
      'endTime': endTime,
      'maxCheckInTime': maxCheckInTime,
      'checkInWindowStart': checkInWindowStart,
      'checkInWindowEnd': checkInWindowEnd,
      'checkOutWindowStart': checkOutWindowStart,
      'checkOutWindowEnd': checkOutWindowEnd,
      'gracePeriodMinutes': gracePeriodMinutes,
      'allowLateAttendance': allowLateAttendance,
      'isOvernight': isOvernight,
      'createdAt': createdAt?.toIso8601String(),
    };
  }

  factory ShiftModel.fromMap(Map<String, dynamic> map) {
    return ShiftModel(
      shiftId: map['shiftId'] ?? '',
      businessId: map['businessId'] ?? '',
      shopId: map['shopId'] ?? '',
      shiftName: map['shiftName'] ?? '',
      startTime: map['startTime'] ?? '09:00 AM',
      endTime: map['endTime'] ?? '06:00 PM',
      maxCheckInTime: map['maxCheckInTime'] ?? map['checkInWindowEnd'] ?? '09:15 AM',
      checkInWindowStart: map['checkInWindowStart'] ?? '',
      checkInWindowEnd: map['checkInWindowEnd'] ?? '',
      checkOutWindowStart: map['checkOutWindowStart'] ?? '',
      checkOutWindowEnd: map['checkOutWindowEnd'] ?? '',
      gracePeriodMinutes: map['gracePeriodMinutes'] ?? 15,
      allowLateAttendance: map['allowLateAttendance'] ?? true,
      isOvernight: map['isOvernight'] ?? false,
      createdAt: map['createdAt'] != null ? DateTime.tryParse(map['createdAt']) : null,
    );
  }
}
