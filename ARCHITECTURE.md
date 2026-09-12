# ARCHITECTURE.md — Enterprise Attendance System Architecture

## 1. System Overview & Canonical Architecture

The Enterprise Attendance System is a multi-tenant, offline-first biometric attendance application built using Flutter 3.x. The production backend architecture is standardized strictly on **Google Firebase**.

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

---

## 2. Application & Role Boundaries

### 2.1 Application Boundaries

- **Main Application (`lib/`)**: Canonical Flutter codebase hosting all application modules and target modes.
  - **Master Panel (`lib/features/master`)**: System-wide administration module. Responsible for shop registration approval, provisioning, shop status management (active/suspended), and system audit logging.
  - **Shop Admin Panel (`lib/features/admin`)**: Business administration module. Responsible for employee enrollment, shift configuration, attendance log monitoring, late approval workflow, shop holiday setup, holiday bonus allocation, salary advance (udhaar) management, and live audio broadcast dispatches.
  - **Kiosk App (`lib/features/kiosk`)**: Device scanner mode. Touchless camera-based face recognition for employee check-in/check-out with real-time TTS feedback, offline SQLite logging, and automatic sync.
- **Legacy Master App (`master_panel/`)**: Standalone web app directory maintained for historical reference. All core master functionalities have been fully consolidated into the canonical application (`lib/features/master/master_dashboard_screen.dart`).

### 2.2 Role Boundaries & Authentication

Authentication is handled via **Firebase Authentication** (`FirebaseAuth`). Role routing is managed dynamically by `AuthRoutingService`:

| Role | Access Level | Description |
| --- | --- | --- |
| `MASTER` | Platform Admin | System owner with global oversight across all businesses, shop approvals, and platform audit logs. |
| `SHOP_ADMIN` | Tenant Admin | Business manager controlling employee management, shifts, approvals, payroll, and kiosk configuration. |
| `KIOSK` | Terminal Device | Dedicated attendance kiosk terminal limited strictly to camera scanning and offline queue syncing. |

---

## 3. Backend Architecture

The single canonical production backend consists of:

1. **Firebase Authentication**: User identity and role verification.
2. **Cloud Firestore**: Multi-tenant document database for business operations, attendance logs, and configuration.
3. **Firebase Storage**: Cloud storage for employee profile images, face crop reference samples, and recorded voice announcement audio files.
4. **Cloud Functions / Serverless Backend**: Serverless API proxy for privileged operations, including automated email dispatches (SMTP notifications) and secure administrative tasks.

---

## 4. Multi-Tenant Data Architecture

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

Every document across all sub-collections contains an explicit `businessId` field to preserve tenant identity and enable reliable querying across local and cloud storage layers.

---

## 5. Synchronization Architecture

The application implements an **offline-first** database design:

- **Local Storage**: `sqflite` SQLite database (`local_employees`, `local_shifts`, `offline_attendance`, `local_holidays`).
- **Sync Engine (`SyncEngine`)**: Listens to connectivity changes (`connectivity_plus`). When the kiosk is offline, check-in records are stored locally with `isSynced = 0`. Upon network restoration, `SyncEngine` automatically pushes pending records to Cloud Firestore and updates local sync status.

---

## 6. Biometric Face Pipeline Architecture

The facial recognition workflow runs on-device using ML Kit and TensorFlow Lite (MobileFaceNet):

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

### Key Components:
1. **Frame Capture & EXIF Rotation**: Rotates raw camera frames to match device orientation.
2. **ML Kit Detection**: Detects face bounding box and facial landmarks.
3. **Safety Margin Crop**: Expands bounding box by 10% on all sides to encompass full facial structure (forehead to chin).
4. **Preprocessing**: Resizes crop to $112 \times 112$ pixels and normalizes RGB channels to $[-1, 1]$.
5. **Embedding Inference**: MobileFaceNet TFLite model generates 192-dimensional vector.
6. **L2 Normalization**: Normalizes vector to unit length ($\sqrt{\sum v_i^2} = 1.0$).
7. **Local Embedding Matching**: Computes Cosine Similarity against local SQLite face cache using calibrated threshold of `0.55`.
8. **Liveness Debug Switch**: `requireLivenessForRecognition` flag controls whether eye blink verification is required before matching.

---

## 7. Environment & Security Boundaries

### 7.1 Environment Isolation
- **Development**: Local testing against Firebase Emulators or isolated dev project.
- **Staging**: Pre-release verification environment.
- **Production**: Live production Firebase deployment with strict security rules.

### 7.2 Security Boundaries & Secret Management
- **No Source Code Secrets**: Secrets, credentials, and API keys must NOT be committed to git. `.env` files and configuration assets are listed in `.gitignore`.
- **Kiosk Security Exit**: Kiosk exit dialog requires Shop Admin PIN verification to prevent unauthorized terminal escape.
- **Privileged Backend Operations**: Sensitive operations (e.g. SMTP email dispatches, shop approvals) execute through authenticated Cloud Functions/trusted backend endpoints.
