# Enterprises Attendance V2 — Comprehensive Task Checklist

Master tracking document for the Smart Attendance & Enterprise Management Ecosystem.

---

## 🚀 Phase 0 — Baseline Audit & Code Freeze
- [x] **Git Repository Migration**: Create new clean repository `https://github.com/galaxyinterior/Enterprises_Attendance_V2.git` and push `main` branch baseline.
- [x] **Legacy Supabase Prototype Purge**: Remove dead/unused directories (`mobile_app/`, `temp_migration/`, `master_panel/lib/screens/`, `master_panel/lib/utils/email_sender.dart`).
- [x] **Analyzer Audit**: Run `flutter analyze` across root app and `master_panel` — verify 0 errors.

---

## 🏗️ Phase 1 — Architecture Consolidation
- [x] **Canonical Firebase Backend**: Standardize on Firebase Auth, Cloud Firestore, and Firebase Storage.
- [x] **Role Consolidation**: Establish separation between Master Control Plane (`master_panel/`) and Shop App (`lib/`).
- [x] **Shared Domain Models**: Verify domain models (`Business`, `Employee`, `AttendanceRecord`, `RegistrationRequest`).

---

## 🔐 Phase 2 — Security & Authorization Rules
- [x] **Firestore Security Rules**: Create production [`firestore.rules`](file:///j:/app%20dev/Attendance%20App/firestore.rules) enforcing tenant isolation under `businesses/{businessId}/...`.
- [x] **Role-Based Access Control**: Standardize `MASTER`, `ADMIN`, `KIOSK` custom claims and document roles.
- [x] **Firebase Config Linkage**: Update [`firebase.json`](file:///j:/app%20dev/Attendance%20App/firebase.json) to reference `firestore.rules`.

---

## 👑 Phase 3 — Master Panel (Store Onboarding & Provisioning Workflow)
- [x] **Manual/Auto Shop ID Generator**: Support manual custom Shop ID input during approval with auto-fallback (`SHOP-XXXXXX`).
- [x] **Auto Password Generator with Refresh Button**: Add 🔄 generator for admin/kiosk passwords.
- [x] **Store Registration Request Approval**: Approve application, generate credentials, create `businesses/{businessId}` document.
- [x] **Automatic Email Credential Dispatch**: Send SMTP email with credentials to store owner upon approval.
- [x] **Auto-Cleanup On Approval**: Automatically delete processed request document from `registrationrequests` collection upon approval.
- [ ] **Device Management & Pairing**: View active Kiosks per business, remote pause/resume, unpair devices.
- [ ] **Master Audit Logs**: Track all provisioning actions, status changes, and admin activities.

---

## 🏢 Phase 4 — Admin Panel (Employee Management & Dedicated Enrollment)
- [x] **Dedicated Full-Page Add Employee Screen**: Replace dialogs with dedicated full-page screen for employee registration.
- [x] **Admin Camera Face Data Capture**: Capture face enrollment image directly from Admin Panel during employee setup.
- [x] **Real-time 128D Embedding Generation**: Extract 128D vector during admin enrollment and save to Firestore/SQLite.
- [x] **Employee Directory CRUD**: Real-time search by name/code/department, staff activation/deactivation toggle, and deletion.

---

## 🧠 Phase 5 — ML Kit + MobileFaceNet 128D Face Engine
- [x] **ML Kit Detector Integration**: Accurate face detection, landmark bounding box extraction (`google_mlkit_face_detection`).
- [x] **MobileFaceNet TFLite Model**: Bundled `assets/mobile_facenet.tflite` model execution via `tflite_flutter`.
- [x] **128D Cosine Similarity Matching**: L2 normalization and cosine similarity match against enrolled embeddings.
- [x] **Anti-Spoofing & Quality Checks**: Validation of face bounding box size, head rotation angles (yaw/roll), and eye openness probability.

---

## 📱 Phase 6 — Kiosk Mode & Entrance Experience
- [x] **Full-Screen Kiosk UI**: Entrance scanner overlay with camera preview.
- [x] **Voice Feedback (TTS)**: Personalized voice announcements ("Welcome Ravi Kumar, Attendance Marked").
- [x] **Remote Kill-Switch Listener**: Display "Service Temporarily Paused" screen when business is paused by Master.
- [x] **Kiosk Lock Mode**: PIN-protected security exit modal for authorized admins.

---

## ⚡ Phase 7 — Offline-First SQLite Sync Engine
- [x] **SQLite Database Schema (`attendance_offline.db`)**: Local storage for offline attendance logs and employee embeddings.
- [x] **Auto-Sync Worker**: Listen to connectivity changes and push queued logs when internet is restored.
- [x] **Conflict Resolution & Anti-Duplicate Safeguard**: Prevent duplicate check-ins for the same employee within configurable time window (e.g. 5 mins).

---

## 🇮🇳 Phase 8 — Indian SaaS Features (Shifts, Salary & Udhaar Ledger)
- [x] **Shift & Attendance Rules**: Morning/Evening/Night shifts, late thresholds, grace period.
- [x] **Staff Advance (Udhaar) Ledger**: Advance loan tracking and salary deduction calculation.
- [x] **Monthly Payslip Generator**: PDF report generator modal with gross salary, attendance, and Udhaar deduction breakdown.

---

## 📡 Phase 9 — Multi-Device Pairing & Heartbeat Monitoring
- [x] **Kiosk Device Registration**: Unique device ID pairing under `businesses/{businessId}/kiosks/{deviceId}`.
- [x] **Live Heartbeat Ping Service**: Periodic heartbeat service (`KioskHeartbeatService`) monitoring device online/offline status.

---

## 🎨 Phase 10 — UI Polish & Indian Palette Design System
- [x] **Unified Palette Tokens (`AppColors`)**:
  - Kesari Saffron (`#FF7722`)
  - Haldi Gold (`#F59E0B`)
  - Mayur Blue (`#0284C7`)
  - Panna Emerald (`#10B981`)
  - Sindoor Red (`#EF4444`)
  - Deep Midnight Slate (`#0B132B`)
- [x] **Typography & Responsive Design**: Google Fonts (Inter / Outfit) across all screens.

---

## 📦 Phase 11 — Release & CI/CD Pipeline
- [ ] **Production APK & Web Build Validation**: Execute `flutter build apk` and `flutter build web` for both projects.
- [ ] **GitHub Final Release Push**: Clean commit history and tagged version release.
