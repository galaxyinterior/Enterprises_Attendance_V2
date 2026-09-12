# SYSTEM_DOCUMENTATION.md — Enterprise Attendance System Master Documentation

This document consolidates the complete system audit, architecture specifications, data model, facial recognition pipeline, security model, attendance & shift engine, offline-first synchronization engine, and master panel trusted provisioning system for the Enterprise Attendance Flutter application.

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
- **Utilities & Communications**: `connectivity_plus`, `mailer`, `intl`, `uuid`, `crypto`, `shared_preferences`

---

# PART 2: CANONICAL ARCHITECTURE & DATA MODEL (Phase 1 Architecture)

## 2.1 Multi-Tenant Document Hierarchy
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

---

# PART 4: BIOMETRIC FACE RECOGNITION PIPELINE (Phases 3 & 4 Face Engine)

```
┌──────────────┐     ┌─────────────────┐     ┌──────────────────────┐     ┌──────────────────────┐
│ Camera Frame │ ──► │ EXIF Alignment  │ ──► │  ML Kit Detection    │ ──► │ Size & Posture Gates │
└──────────────┘     └─────────────────┘     └──────────────────────┘     └──────────────────────┘
                                                                                     │
┌──────────────┐     ┌─────────────────┐     ┌──────────────────────┐                ▼
│ Attendance   │ ◄── │ Cosine Match    │ ◄── │ L2 Normalization     │ ◄── ┌──────────────────────┐
│ Log & Sync   │     │ Threshold: 0.55 │     │ (Vector Length = 192)│     │ MobileFaceNet TFLite │
└──────────────┘     └─────────────────┘     └──────────────────────┘     │ (112x112 RGB Normal) │
                                                                          └──────────────────────┘
```

### Calibrated Thresholds:
* **Same-Person Similarity Range**: `0.72 – 0.96`
* **Different-Person Similarity Range**: `0.08 – 0.42`
* **Calibrated Decision Threshold**: **`0.55`**
* **Duplicate Face Check**: Cosine similarity $\ge 0.70$ prevents enrolling identical face across staff.

---

# PART 5: ATTENDANCE & SHIFT ENGINE (Phase 5 Engine)

* **Idempotency Strategy**: SHA-256 deterministic ID generator (`generateDeterministicAttendanceId`):
  $$\text{ID} = \text{ATT-} + \text{SHA256}(businessId : employeeId : date)[0..24]$$
* **Duplicate Cooldown Safeguard**: 5-minute window check via `hasRecentAttendance` in SQLite.
* **Overnight Shifts**: Handles shifts crossing midnight (e.g., 10 PM – 6 AM).
* **Early Checkout**: Calculates early departure minutes relative to scheduled shift end time.

---

# PART 6: OFFLINE-FIRST SYNCHRONIZATION ENGINE (Phase 6 Sync)

* **Sync Down**: Caches employees (profiles + 192D embeddings) and shifts from Cloud Firestore to SQLite on startup and connection restoration.
* **Sync Up States**: `PENDING`, `SYNCING`, `SYNCED`, `FAILED`, `RETRY`.
* **Fault Tolerance**: Queue persists in SQLite across device reboots; retries automatically when connectivity is restored.

---

# PART 7: MASTER PANEL & TRUSTED PROVISIONING (Phase 7 Master)

* **Registration Review & Retention**: Approved and rejected application requests are retained with status (`APPROVED` / `REJECTED`), documented rejection reason, `reviewedAt`, and `reviewedBy = 'MASTER'`.
* **Provisioning State Machine**: Tracks state transition (`NOT_STARTED` $\rightarrow$ `IN_PROGRESS` $\rightarrow$ `COMPLETED` / `PARTIAL_FAILURE` / `FAILED`).
* **Shop Status Control**: Controls shop operational mode (`active`, `paused`, `suspended`). Paused status blocks kiosk attendance scanning while retaining offline database state.
* **Device Terminal Binding**: Manages kiosk terminal bindings (`businesses/{businessId}/devices/{deviceId}`) and supports revocation/unpairing (`UNPAIRED`).
* **Master Audit Trail**: Immutable logging to `master_audit_logs` for provisioning, status updates, rejection decisions, and device unpairing actions.

---

## Final Project Status Matrix

| Phase | Description | Status | Reference Artifact |
| --- | --- | :---: | --- |
| **Phase 0** | Complete System Audit | 🟢 Complete | [`IMPLEMENTATION_AUDIT.md`](file:///j:/app%20dev/Attendance%20App/IMPLEMENTATION_AUDIT.md) |
| **Phase 1** | Architecture Consolidation | 🟢 Complete | [`ARCHITECTURE.md`](file:///j:/app%20dev/Attendance%20App/ARCHITECTURE.md) |
| **Phase 2** | Security & Authentication Hardening | 🟢 Complete | [`SECURITY_MODEL.md`](file:///j:/app%20dev/Attendance%20App/SECURITY_MODEL.md) |
| **Phase 3** | Production Face Enrollment Pipeline | 🟢 Complete | [`FACE_ENROLLMENT_EVIDENCE.md`](file:///j:/app%20dev/Attendance%20App/FACE_ENROLLMENT_EVIDENCE.md) |
| **Phase 4** | Real Kiosk Face Verification Engine | 🟢 Complete | [`FACE_VERIFICATION_TEST_REPORT.md`](file:///j:/app%20dev/Attendance%20App/FACE_VERIFICATION_TEST_REPORT.md) |
| **Phase 5** | Attendance & Shift Engine Logic | 🟢 Complete | [`ATTENDANCE_ENGINE_TEST_REPORT.md`](file:///j:/app%20dev/Attendance%20App/ATTENDANCE_ENGINE_TEST_REPORT.md) |
| **Phase 6** | Offline-First Synchronization Engine | 🟢 Complete | [`OFFLINE_SYNC_TEST_REPORT.md`](file:///j:/app%20dev/Attendance%20App/OFFLINE_SYNC_TEST_REPORT.md) |
| **Phase 7** | Master Panel & Trusted Provisioning | 🟢 Complete | [`MASTER_PROVISIONING_TEST_REPORT.md`](file:///j:/app%20dev/Attendance%20App/MASTER_PROVISIONING_TEST_REPORT.md) |
