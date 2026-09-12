class AttendanceModel {
  final String attendanceId;
  final String businessId;
  final String employeeId;
  final String employeeName;
  final String date; // "YYYY-MM-DD"
  final String shiftId;
  final DateTime? checkInTime;
  final DateTime? checkOutTime;
  final String status; // PRESENT, LATE, ABSENT, HALF_DAY, EARLY_CHECKOUT
  final String? lateReason; // Reason submitted by employee if late
  final int? lateMinutes; // How many minutes late
  final String? approvalStatus; // PENDING, APPROVED, REJECTED
  final double confidence;
  final String syncStatus; // PENDING, COMPLETED
  final DateTime createdAt;
  final DateTime updatedAt;

  final bool isHolidayWork;
  final double holidayBonusAmount;
  final String? holidayBonusStatus; // PENDING, APPROVED, REJECTED

  AttendanceModel({
    required this.attendanceId,
    required this.businessId,
    required this.employeeId,
    required this.employeeName,
    required this.date,
    required this.shiftId,
    this.checkInTime,
    this.checkOutTime,
    required this.status,
    this.lateReason,
    this.lateMinutes,
    this.approvalStatus,
    this.confidence = 1.0,
    this.syncStatus = 'PENDING',
    this.isHolidayWork = false,
    this.holidayBonusAmount = 0.0,
    this.holidayBonusStatus,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'attendanceId': attendanceId,
      'businessId': businessId,
      'employeeId': employeeId,
      'employeeName': employeeName,
      'date': date,
      'shiftId': shiftId,
      'checkInTime': checkInTime?.toIso8601String(),
      'checkOutTime': checkOutTime?.toIso8601String(),
      'status': status,
      'lateReason': lateReason,
      'lateMinutes': lateMinutes,
      'approvalStatus': approvalStatus,
      'confidence': confidence,
      'syncStatus': syncStatus,
      'isHolidayWork': isHolidayWork,
      'holidayBonusAmount': holidayBonusAmount,
      'holidayBonusStatus': holidayBonusStatus,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
  Map<String, dynamic> toSqliteMap() {
    final map = toMap();
    map['isHolidayWork'] = isHolidayWork ? 1 : 0;
    return map;
  }

  factory AttendanceModel.fromMap(Map<String, dynamic> map) {
    return AttendanceModel(
      attendanceId: map['attendanceId'] ?? '',
      businessId: map['businessId'] ?? '',
      employeeId: map['employeeId'] ?? '',
      employeeName: map['employeeName'] ?? '',
      date: map['date'] ?? '',
      shiftId: map['shiftId'] ?? '',
      checkInTime: map['checkInTime'] != null ? DateTime.parse(map['checkInTime']) : null,
      checkOutTime: map['checkOutTime'] != null ? DateTime.parse(map['checkOutTime']) : null,
      status: map['status'] ?? 'PRESENT',
      lateReason: map['lateReason'],
      lateMinutes: map['lateMinutes'] != null ? (map['lateMinutes'] as num).toInt() : null,
      approvalStatus: map['approvalStatus'],
      confidence: (map['confidence'] ?? 1.0).toDouble(),
      syncStatus: map['syncStatus'] ?? 'PENDING',
      isHolidayWork: map['isHolidayWork'] == true || map['isHolidayWork'] == 1,
      holidayBonusAmount: (map['holidayBonusAmount'] ?? 0.0).toDouble(),
      holidayBonusStatus: map['holidayBonusStatus'],
      createdAt: map['createdAt'] != null ? DateTime.parse(map['createdAt']) : DateTime.now(),
      updatedAt: map['updatedAt'] != null ? DateTime.parse(map['updatedAt']) : DateTime.now(),
    );
  }
}
