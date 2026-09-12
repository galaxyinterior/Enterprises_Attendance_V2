# SYSTEM_DOCUMENTATION.md — Enterprise Attendance System Master Documentation

This document consolidates the complete system audit, architecture specifications, data model, facial recognition pipeline, and security model for the Enterprise Attendance Flutter application.

---

# PART 1: SYSTEM AUDIT & DEPENDENCY MAP (Phase 0 Audit)

## 1.1 Architecture Overview
The project is built on Flutter 3.x using a layered feature-based architecture with offline-first local SQLite database caching and real-time Google Cloud Firestore synchronization.

```
                  ┌───────────────────────────────────────────┐
                  │            Flutter 3.x Frontend           │
                  │ (Material Design Dark, Google Fonts Inter)│
                  └─────────────────────┬─────────────────────┘
                                        │
        ┌───────────────────────────────┼───────────────────────────────┐
        ▼                               ▼                               ▼
 ┌──────────────┐              ┌─────────────────┐              ┌──────────────┐
 │ Master Panel │              │   Admin Panel   │              │  Kiosk Mode  │
 └──────┬───────┘              └────────┬────────┘              └──────┬───────┘
        │                               │                              │
        └───────────────────────────────┼──────────────────────────────┘
                                        │
                         ┌──────────────┴──────────────┐
                         ▼                             ▼
                 ┌───────────────┐             ┌───────────────┐
                 │ Cloud Storage │             │ Local SQLite  │
                 │  & Firestore  │ ◄─────────► │ Database Sync │
                 └───────────────┘  SyncEngine └───────────────┘
```

## 1.2 Dependency Map
- **Core Framework**: Flutter SDK (`dart:3.11.0`), `provider`, `google_fonts`
- **Biometrics & Machine Learning**: `google_mlkit_face_detection` (0.13.2), `tflite_flutter` (0.11.0 with MobileFaceNet), `image` (4.5.3)
- **Local Storage & Database**: `sqflite` (2.4.2+1), `path_provider`, `path`
- **Backend & Cloud**: `firebase_core`, `firebase_auth`, `cloud_firestore`, `firebase_storage`
- **Hardware & Peripherals**: `camera` (0.11.4), `flutter_tts`, `audioplayers`, `record`
- **Utilities & Communications**: `connectivity_plus`, `mailer`, `intl`, `uuid`, `shared_preferences`

## 1.3 Component Status Summary

| Component | Status | Details |
| --- | --- | --- |
| **Authentication & Roles** | 🟢 Complete | Role-based routing (`MASTER`, `SHOP_ADMIN`, `KIOSK`) via `AuthRoutingService`. |
| **Master Panel** | 🟢 Complete | Shop registration approval, provisioning, business status management. |
| **Admin Console** | 🟢 Complete | Staff directory, shift creation & rules, daily attendance logs, shift assignment. |
| **Biometric Face Enrollment** | 🟢 Complete | Single-step straight face enrollment, 10% safety margin crop padding, L2 normalization. |
| **Kiosk Auto-Scanner** | 🟢 Complete | Touchless camera scanning with `requireLivenessForRecognition` debug switch. |
| **Shift Engine & Rules** | 🟢 Complete | Evaluates check-in deadlines (e.g. 9:15 AM limit). Late arrivals flagged as `ABSENT (PENDING)`. |
| **Late Attendance Approvals** | 🟢 Complete | Admin calendar approval list for reviewing late check-ins and reason submissions. |
| **Shop Calendar Holidays** | 🟢 Complete | Admin can add shop holidays (`HolidayModel`). Highlighted on calendar grid. |
| **Holiday Bonus Approvals** | 🟢 Complete | Admin approves custom extra bonus amounts for staff attending on holidays. |
| **Payroll & Salary Advance (Udhaar)** | 🟢 Complete | Grant advance modal (`AdvanceSalaryModel`) + dynamic Net Payable Salary calculation. |
| **TTS & Voice Announcements** | 🟢 Complete | Custom voice audio recording broadcast live from Admin Console to Kiosks. |
| **SMTP Email Alerts** | 🟢 Complete | Automatic email notifications sent for Present and Late attendance check-ins. |
| **SQLite Offline Caching** | 🟢 Complete | Local SQLite tables (`local_employees`, `local_shifts`, `offline_attendance`). |
| **Background Sync Engine** | 🟢 Complete | `SyncEngine` auto-syncs queued SQLite attendance records to Cloud Firestore. |

---

# PART 2: CANONICAL SYSTEM ARCHITECTURE (Phase 1 Architecture)

## 2.1 Application & Role Boundaries

### Application Boundaries
- **Main Application (`lib/`)**: Canonical Flutter codebase hosting all application modules and target modes.
  - **Master Panel (`lib/features/master`)**: System-wide administration module. Responsible for shop registration approval, provisioning, shop status management (active/suspended), and system audit logging.
  - **Shop Admin Panel (`lib/features/admin`)**: Business administration module. Responsible for employee enrollment, shift configuration, attendance log monitoring, late approval workflow, shop holiday setup, holiday bonus allocation, salary advance (udhaar) management, and live audio broadcast dispatches.
  - **Kiosk App (`lib/features/kiosk`)**: Device scanner mode. Touchless camera-based face recognition for employee check-in/check-out with real-time TTS feedback, offline SQLite logging, and automatic sync.
- **Legacy Master App (`master_panel/`)**: Standalone web app directory maintained for historical reference. All core master functionalities have been fully consolidated into the canonical application (`lib/features/master/master_dashboard_screen.dart`).

## 2.2 Production Backend Services
The single canonical production backend consists of:
1. **Firebase Authentication**: User identity and role verification.
2. **Cloud Firestore**: Multi-tenant document database for business operations, attendance logs, and configuration.
3. **Firebase Storage**: Cloud storage for employee profile images, face crop reference samples, and recorded voice announcement audio files.
4. **Cloud Functions / Serverless Backend**: Serverless API proxy for privileged operations, including automated email dispatches (SMTP notifications) and secure administrative tasks.

## 2.3 Multi-Tenant Data Architecture
All business-owned data is strictly scoped under tenant-specific document paths to guarantee complete data isolation:

```
businesses/
  └── {businessId}/                      (Business / Shop Document)
        ├── employees/
        │     └── {employeeId}           (Employee Profile & Biometric Embeddings)
        ├── shifts/
        │     └── {shiftId}              (Shift Schedules & Grace Period Rules)
        ├── attendance/
        │     └── {attendanceId}         (Daily Attendance Check-in Logs)
        ├── holidays/
        │     └── {holidayId}            (Shop Calendar Holiday Configurations)
        ├── advances/
        │     └── {advanceId}            (Salary Advance / Udhaar Ledger)
        ├── announcements/
        │     └── {announcementId}       (Voice & Text Audio Broadcasts)
        ├── devices/
        │     └── {deviceId}             (Kiosk Terminal Registrations)
        └── audit_logs/
              └── {logId}                (Tenant Security & Operation Audit Logs)

master_audit_logs/
  └── {logId}                            (System-wide Master Operation Logs)
```

## 2.4 Biometric Face Pipeline Architecture

```
┌──────────────┐     ┌─────────────────┐     ┌──────────────────────┐     ┌──────────────────────┐
│ Camera Frame │ ──► │ EXIF Alignment  │ ──► │  ML Kit Detection    │ ──► │ 10% Safety Margin    │
└──────────────┘     └─────────────────┘     └──────────────────────┘     └──────────────────────┘
                                                                                     │
┌──────────────┐     ┌─────────────────┐     ┌──────────────────────┐                ▼
│ Shift Rules  │ ◄── │ Cosine Match    │ ◄── │ L2 Normalization     │ ◄── ┌──────────────────────┐
│ & Check-in   │     │ Threshold: 0.55 │     │  (Length = 1.0)      │     │ MobileFaceNet TFLite │
└──────────────┘     └─────────────────┘     └──────────────────────┘     │ (112x112 RGB Normal) │
                                                                          └──────────────────────┘
```

1. **Frame Capture & EXIF Rotation**: Rotates raw camera frames to match device orientation.
2. **ML Kit Detection**: Detects face bounding box and facial landmarks.
3. **Safety Margin Crop**: Expands bounding box by 10% on all sides to encompass full facial structure (forehead to chin).
4. **Preprocessing**: Resizes crop to $112 \times 112$ pixels and normalizes RGB channels to $[-1, 1]$.
5. **Embedding Inference**: MobileFaceNet TFLite model generates 192-dimensional vector.
6. **L2 Normalization**: Normalizes vector to unit length ($\sqrt{\sum v_i^2} = 1.0$).
7. **Local Embedding Matching**: Computes Cosine Similarity against local SQLite face cache using calibrated threshold of `0.55`.

---

# PART 3: SECURITY & AUTHENTICATION MODEL (Phase 2 Security)

## 3.1 Role-Based Access Control (RBAC) Matrix

| Feature / Resource | MASTER | SHOP_ADMIN | KIOSK | Unauthenticated |
| --- | :---: | :---: | :---: | :---: |
| **Submit Registration Application** | ✅ | ✅ | ✅ | ✅ |
| **Approve / Provision Shop Applications** | ✅ | ❌ | ❌ | ❌ |
| **View Master Audit Logs** | ✅ | ❌ | ❌ | ❌ |
| **Manage Shop Details (`businesses/{bId}`)** | ✅ | 👁️ Read-Only | 👁️ Read-Only | ❌ |
| **Manage Employees & Face Embeddings** | ✅ | ✅ (Own Tenant) | 👁️ Read-Only | ❌ |
| **Configure Shifts & Grace Rules** | ✅ | ✅ (Own Tenant) | 👁️ Read-Only | ❌ |
| **Log Biometric Attendance Check-In** | ✅ | ✅ | ✅ (Create Only) | ❌ |
| **Approve / Modify Attendance Logs** | ✅ | ✅ (Own Tenant) | ❌ Cannot Rewrite | ❌ |
| **Manage Salary Advances (Udhaar)** | ✅ | ✅ (Own Tenant) | ❌ | ❌ |
| **Dispatch Voice / Text Announcements** | ✅ | ✅ (Own Tenant) | 👁️ Read-Only | ❌ |

## 3.2 Production Cloud Firestore Security Rules (`firestore.rules`)
- **Tenant Isolation**: Non-master users are strictly constrained: `request.auth.token.businessId == businessId` or `getUserData().businessId == businessId`.
- **Attendance Rewrite Protection**: `KIOSK` accounts can `create` attendance records but cannot `update` or `delete` past attendance entries.
- **Self-Modification Block**: Employees cannot alter their own profile attributes or biometric vector data.
- **Application & Audit Security**: `shop_registrations` write/delete and `master_audit_logs` are restricted strictly to `MASTER`.

## 3.3 Production Cloud Storage Security Rules (`storage.rules`)
- **Employee Photos & Biometric Embeddings**: Path `/businesses/{businessId}/employees/*` is readable ONLY by authenticated users of that `businessId` or `MASTER`.
- **Media & Voice Broadcast Audio**: Path `/businesses/{businessId}/announcements/*` requires tenant authentication.
- **Public Deny-All Fallback**: All un-scoped paths default to `allow read, write: if false;`.

## 3.4 Secret Management & Credential Hygiene
- **Zero Source Secrets**: No passwords, API keys, private keys, or SMTP app credentials may be committed to client `.dart` files.
- **Environment Injection**: Sensitive runtime values are injected via compile-time environment flags (`String.fromEnvironment('SMTP_PASSWORD')`).
- **Git Protection**: Local configuration files (`.env`, `key.properties`, service account JSONs) are listed in `.gitignore`.
