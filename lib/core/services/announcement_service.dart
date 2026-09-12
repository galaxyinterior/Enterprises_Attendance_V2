import '../../models/announcement_model.dart';
import 'voice_announcements_service.dart';

/// Canonical service managing announcement evaluation, priority ordering,
/// expiry filtering, media caching rules, and TTS audio playback.
class AnnouncementService {
  final VoiceAnnouncementsService _voiceService;
  final Set<String> _deliveredAnnouncementIds = {};

  AnnouncementService({VoiceAnnouncementsService? voiceService})
      : _voiceService = voiceService ?? VoiceAnnouncementsService();

  /// Evaluates whether an announcement is currently active and within its schedule window.
  static bool isAnnouncementActive(AnnouncementModel announcement, {DateTime? currentTime}) {
    final DateTime now = currentTime ?? DateTime.now();
    if (!announcement.active) return false;
    if (now.isBefore(announcement.scheduledAt)) return false;
    if (now.isAfter(announcement.expiresAt)) return false;
    return true;
  }

  /// Calculates priority numerical weight for sorting (EMERGENCY=4, HIGH=3, NORMAL=2, LOW=1).
  static int getPriorityWeight(String priority) {
    switch (priority.toUpperCase()) {
      case 'EMERGENCY':
        return 4;
      case 'HIGH':
        return 3;
      case 'NORMAL':
        return 2;
      case 'LOW':
      default:
        return 1;
    }
  }

  /// Filters valid announcements that are active, not expired, and not yet delivered.
  List<AnnouncementModel> filterValidAnnouncements(
    List<AnnouncementModel> list, {
    DateTime? currentTime,
    Set<String>? alreadyDeliveredIds,
  }) {
    final Set<String> delivered = alreadyDeliveredIds ?? _deliveredAnnouncementIds;
    final DateTime now = currentTime ?? DateTime.now();

    final filtered = list.where((ann) {
      if (delivered.contains(ann.id)) return false;
      return isAnnouncementActive(ann, currentTime: now);
    }).toList();

    return sortAnnouncementsByPriority(filtered);
  }

  /// Sorts announcements by priority weight descending, then by createdAt descending.
  static List<AnnouncementModel> sortAnnouncementsByPriority(List<AnnouncementModel> list) {
    final sorted = List<AnnouncementModel>.from(list);
    sorted.sort((a, b) {
      final int weightA = getPriorityWeight(a.priority);
      final int weightB = getPriorityWeight(b.priority);
      if (weightA != weightB) {
        return weightB.compareTo(weightA);
      }
      return b.createdAt.compareTo(a.createdAt);
    });
    return sorted;
  }

  /// Delivers an announcement on Kiosk via TTS voice broadcast.
  Future<bool> deliverAnnouncement(
    AnnouncementModel announcement, {
    DateTime? currentTime,
  }) async {
    if (!isAnnouncementActive(announcement, currentTime: currentTime)) {
      return false;
    }

    if (_deliveredAnnouncementIds.contains(announcement.id)) {
      return false; // Skip duplicate delivery
    }

    final String type = announcement.priority.toLowerCase() == 'emergency'
        ? 'emergency'
        : (announcement.priority.toLowerCase() == 'high' ? 'notice' : 'general');

    await _voiceService.speakAnnouncement(announcement.message, type);
    _deliveredAnnouncementIds.add(announcement.id);
    return true;
  }

  /// Checks if an announcement has already been delivered to avoid repetitive audio spam.
  bool isAlreadyDelivered(String announcementId) {
    return _deliveredAnnouncementIds.contains(announcementId);
  }

  /// Resets delivery tracker (e.g. on new shift or device reset).
  void clearDeliveredHistory() {
    _deliveredAnnouncementIds.clear();
  }
}
