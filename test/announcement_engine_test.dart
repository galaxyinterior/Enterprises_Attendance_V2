import 'package:flutter_test/flutter_test.dart';
import 'package:attendance_app/models/announcement_model.dart';
import 'package:attendance_app/core/services/announcement_service.dart';

void main() {
  group('Phase 10 — Announcement System Unit Tests', () {
    late DateTime now;
    late AnnouncementModel activeNormal;
    late AnnouncementModel activeEmergency;
    late AnnouncementModel expiredAnnouncement;
    late AnnouncementModel futureScheduled;

    setUp(() {
      now = DateTime(2026, 9, 12, 15, 0, 0);

      activeNormal = AnnouncementModel(
        id: 'ANN-001',
        businessId: 'BIZ-100',
        title: 'Team Meeting',
        message: 'All hands meeting at 4 PM in the main hall.',
        priority: 'NORMAL',
        scheduledAt: now.subtract(const Duration(hours: 1)),
        expiresAt: now.add(const Duration(hours: 5)),
        createdAt: now.subtract(const Duration(hours: 2)),
        updatedAt: now.subtract(const Duration(hours: 2)),
      );

      activeEmergency = AnnouncementModel(
        id: 'ANN-002',
        businessId: 'BIZ-100',
        title: 'Fire Drill Alert',
        message: 'Emergency fire drill scheduled in 10 minutes!',
        priority: 'EMERGENCY',
        scheduledAt: now.subtract(const Duration(minutes: 10)),
        expiresAt: now.add(const Duration(hours: 1)),
        createdAt: now.subtract(const Duration(minutes: 10)),
        updatedAt: now.subtract(const Duration(minutes: 10)),
      );

      expiredAnnouncement = AnnouncementModel(
        id: 'ANN-003',
        businessId: 'BIZ-100',
        title: 'Yesterday Notice',
        message: 'This notice expired yesterday.',
        priority: 'HIGH',
        scheduledAt: now.subtract(const Duration(days: 2)),
        expiresAt: now.subtract(const Duration(days: 1)),
        createdAt: now.subtract(const Duration(days: 2)),
        updatedAt: now.subtract(const Duration(days: 2)),
      );

      futureScheduled = AnnouncementModel(
        id: 'ANN-004',
        businessId: 'BIZ-100',
        title: 'Tomorrow Festival Off',
        message: 'Office will remain closed tomorrow for holiday.',
        priority: 'HIGH',
        scheduledAt: now.add(const Duration(days: 1)),
        expiresAt: now.add(const Duration(days: 2)),
        createdAt: now,
        updatedAt: now,
      );
    });

    test('1. Announcement Active Status Check', () {
      expect(AnnouncementService.isAnnouncementActive(activeNormal, currentTime: now), isTrue);
      expect(
          AnnouncementService.isAnnouncementActive(expiredAnnouncement, currentTime: now), isFalse);
      expect(AnnouncementService.isAnnouncementActive(futureScheduled, currentTime: now), isFalse);
    });

    test('2. Priority Weight Sorting (EMERGENCY > HIGH > NORMAL > LOW)', () {
      final list = [activeNormal, activeEmergency, futureScheduled];
      final sorted = AnnouncementService.sortAnnouncementsByPriority(list);

      expect(sorted.first.id, equals('ANN-002')); // EMERGENCY first
      expect(sorted[1].id, equals('ANN-004')); // HIGH second
      expect(sorted.last.id, equals('ANN-001')); // NORMAL last
    });

    test('3. Valid Announcement Filtering & Deduplication', () {
      final service = AnnouncementService();
      final allAnnouncements = [
        activeNormal,
        activeEmergency,
        expiredAnnouncement,
        futureScheduled
      ];

      // Initial filter: only activeNormal & activeEmergency should pass, with activeEmergency first due to priority
      final validFirstPass = service.filterValidAnnouncements(allAnnouncements, currentTime: now);
      expect(validFirstPass.length, equals(2));
      expect(validFirstPass.first.id, equals('ANN-002'));
      expect(validFirstPass.last.id, equals('ANN-001'));

      // Simulate delivering ANN-002 (Emergency)
      final Set<String> deliveredSet = {'ANN-002'};
      final validSecondPass = service.filterValidAnnouncements(
        allAnnouncements,
        currentTime: now,
        alreadyDeliveredIds: deliveredSet,
      );

      // Only ANN-001 should remain
      expect(validSecondPass.length, equals(1));
      expect(validSecondPass.first.id, equals('ANN-001'));
    });

    test('4. Multi-Tenant Scoped Collection Paths', () {
      const String businessId = 'TENANT-ALPHA';
      final announcementPath = "businesses/$businessId/announcements/${activeNormal.id}";
      expect(announcementPath, equals("businesses/TENANT-ALPHA/announcements/ANN-001"));
    });
  });
}
