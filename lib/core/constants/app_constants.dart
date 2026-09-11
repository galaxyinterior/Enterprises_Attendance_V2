class AppConstants {
  // App Info
  static const String appName = 'Smart Attendance Ecosystem';

  // User Roles
  static const String roleMaster = 'MASTER';
  static const String roleShopAdmin = 'SHOP_ADMIN';
  static const String roleKiosk = 'KIOSK';

  // Shop / Business Statuses
  static const String statusPending = 'PENDING';
  static const String statusUnderReview = 'UNDER_REVIEW';
  static const String statusApproved = 'APPROVED';
  static const String statusRejected = 'REJECTED';
  static const String statusActive = 'ACTIVE';
  static const String statusPaused = 'PAUSED';
  static const String statusSuspended = 'SUSPENDED';
  static const String statusDeactivated = 'DEACTIVATED';

  // Attendance Event Statuses
  static const String attendancePresent = 'PRESENT';
  static const String attendanceLate = 'LATE';
  static const String attendanceEarlyCheckout = 'EARLY_CHECKOUT';
  static const String attendanceAbsent = 'ABSENT';
  static const String attendanceHalfDay = 'HALF_DAY';

  // Sync Statuses
  static const String syncPending = 'PENDING';
  static const String syncCompleted = 'COMPLETED';
  static const String syncFailed = 'FAILED';

  // Face Matching Thresholds
  static const double faceMatchConfidenceThreshold = 0.58; // Cosine similarity threshold for MobileFaceNet
  static const int faceModelInputSize = 112; // MobileFaceNet tensor size

  // Firestore Collections
  static const String colRegistrationRequests = 'registrationRequests';
  static const String colBusinesses = 'businesses';
  static const String colUsers = 'users';
  static const String colEmployees = 'employees';
  static const String colShifts = 'shifts';
  static const String colAttendance = 'attendance';
  static const String colSalaryAdvances = 'salaryAdvances';
  static const String colAnnouncements = 'announcements';
  static const String colDevices = 'devices';
  static const String colMasterAuditLogs = 'masterAuditLogs';
}
