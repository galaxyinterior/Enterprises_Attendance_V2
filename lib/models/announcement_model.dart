class AnnouncementModel {
  final String id;
  final String businessId;
  final String title;
  final String message;
  final String? audioUrl;
  final String? localAudioPath;
  final String priority; // LOW, NORMAL, HIGH, EMERGENCY
  final DateTime scheduledAt;
  final DateTime expiresAt;
  final bool active;
  final bool playOnKioskCheckIn;
  final String deliveryState; // PENDING, DELIVERED, EXPIRED
  final DateTime createdAt;
  final DateTime updatedAt;

  AnnouncementModel({
    required this.id,
    required this.businessId,
    required this.title,
    required this.message,
    this.audioUrl,
    this.localAudioPath,
    this.priority = 'NORMAL',
    required this.scheduledAt,
    required this.expiresAt,
    this.active = true,
    this.playOnKioskCheckIn = false,
    this.deliveryState = 'PENDING',
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'businessId': businessId,
      'title': title,
      'message': message,
      'audioUrl': audioUrl,
      'localAudioPath': localAudioPath,
      'priority': priority,
      'scheduledAt': scheduledAt.toIso8601String(),
      'expiresAt': expiresAt.toIso8601String(),
      'active': active,
      'playOnKioskCheckIn': playOnKioskCheckIn,
      'deliveryState': deliveryState,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory AnnouncementModel.fromMap(Map<String, dynamic> map) {
    return AnnouncementModel(
      id: map['id'] ?? '',
      businessId: map['businessId'] ?? '',
      title: map['title'] ?? '',
      message: map['message'] ?? '',
      audioUrl: map['audioUrl'],
      localAudioPath: map['localAudioPath'],
      priority: map['priority'] ?? 'NORMAL',
      scheduledAt: map['scheduledAt'] != null
          ? DateTime.parse(map['scheduledAt'])
          : DateTime.now(),
      expiresAt: map['expiresAt'] != null
          ? DateTime.parse(map['expiresAt'])
          : DateTime.now().add(const Duration(days: 1)),
      active: map['active'] ?? true,
      playOnKioskCheckIn: map['playOnKioskCheckIn'] ?? false,
      deliveryState: map['deliveryState'] ?? 'PENDING',
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'])
          : DateTime.now(),
      updatedAt: map['updatedAt'] != null
          ? DateTime.parse(map['updatedAt'])
          : DateTime.now(),
    );
  }

  AnnouncementModel copyWith({
    String? localAudioPath,
    String? deliveryState,
    bool? active,
  }) {
    return AnnouncementModel(
      id: id,
      businessId: businessId,
      title: title,
      message: message,
      audioUrl: audioUrl,
      localAudioPath: localAudioPath ?? this.localAudioPath,
      priority: priority,
      scheduledAt: scheduledAt,
      expiresAt: expiresAt,
      active: active ?? this.active,
      playOnKioskCheckIn: playOnKioskCheckIn,
      deliveryState: deliveryState ?? this.deliveryState,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}
