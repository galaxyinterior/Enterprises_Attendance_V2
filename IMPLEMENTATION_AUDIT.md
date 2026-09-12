# IMPLEMENTATION_AUDIT.md — Enterprise Attendance System Audit

## 1. System Architecture & Dependency Map

### 1.1 Architecture Overview
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

### 1.2 Dependency Map
- **Core Framework**: Flutter SDK (`dart:3.11.0`), `provider`, `google_fonts`
- **Biometrics & Machine Learning**: `google_mlkit_face_detection` (0.13.2), `tflite_flutter` (0.11.0 with MobileFaceNet), `image` (4.5.3)
- **Local Storage & Database**: `sqflite` (2.4.2+1), `path_provider`, `path`
- **Backend & Cloud**: `firebase_core`, `firebase_auth`, `cloud_firestore`, `firebase_storage`
- **Hardware & Peripherals**: `camera` (0.11.4), `flutter_tts`, `audioplayers`, `record`
- **Utilities & Communications**: `connectivity_plus`, `mailer`, `intl`, `uuid`, `shared_preferences`

---

## 2. Component Status Audit

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
| **Leave Management** | 🟡 Partial | `LeaveRequestModel` exists in `lib/models/`, but UI screen is pending. |
| **Kiosk Security Exit PIN** | 🟡 Hardcoded | PIN check accepts `1234` or any $\ge 4$-digit input. Should be shop-configurable. |

---

## 3. Detailed Face System Pipeline Audit

### Biometric Pipeline Trace:
$$\text{Camera} \longrightarrow \text{EXIF Orientation} \longrightarrow \text{ML Kit Face Detection} \longrightarrow \text{10\% Margin Crop} \longrightarrow \text{112x112 Preprocessing} \longrightarrow \text{MobileFaceNet TFLite} \longrightarrow \text{L2 Vector Normalization} \longrightarrow \text{SQLite Cache / Cosine Match (0.55)} \longrightarrow \text{Shift \& Attendance Evaluation}$$

1. **Camera Frame Capture**: Android CameraX / Camera Controller captures raw image frame.
2. **Orientation Alignment**: `img.bakeOrientation(decoded)` bakes EXIF rotation so image dimensions match ML Kit coordinate space.
3. **ML Kit Detection**: `FaceDetector` (accurate mode, landmarks & classification enabled) locates face bounding box.
4. **Safety Margin Cropping**: 10% padding (`padX = 0.10 * width`, `padY = 0.10 * height`) is added around bounding box to capture full face ROI (forehead & chin).
5. **Model Preprocessing**: Image resized to $112 \times 112$ pixels; RGB channels normalized to float $[-1, 1]$ via $(pixel - 127.5) / 128.0$.
6. **MobileFaceNet TFLite**: Interpreter runs inference to generate raw feature vector.
7. **L2 Normalization**: Output vector normalized ($\sqrt{\sum v_i^2} = 1.0$).
8. **Local Caching & Matching**: Vector matched against local SQLite cached embeddings using Cosine Similarity dot product with a calibrated threshold of `0.55`.
9. **Attendance Decision**: If matched, evaluates shift schedule & deadline; logs check-in event locally and queues for Firestore sync.

---

## 4. Identified Duplicate Architecture & Dead Code

- **Unused Model**: `SalaryAdvanceModel` in `lib/models/salary_advance_model.dart` is redundant and superseded by `AdvanceSalaryModel` (`lib/models/advance_salary_model.dart`).

---

## 5. Security & Authorization Audit

1. **Client-Side Secrets**: Email SMTP app password (`zynz isfx bmhd smvw`) is hardcoded in `email_notification_service.dart`.
   *Recommendation*: In future phases, move email alert dispatch to a Cloud Function / serverless API proxy.
2. **Kiosk Security Exit PIN**: Default PIN in `_showExitDialog()` accepts `1234`.
   *Recommendation*: Store encrypted Shop Admin PIN in Firestore/SQLite to prevent unauthorized kiosk exit.

---

## 6. Recommended Implementation Order for Subsequent Phases

1. **Phase 1 — Code Cleanup & Dead Code Removal**: Safely deprecate/remove `SalaryAdvanceModel`.
2. **Phase 2 — Configurable Kiosk Security PIN**: Store shop admin PIN securely in `BusinessModel` & local SQLite.
3. **Phase 3 — Leave Request Subsystem**: Implement Admin & Kiosk/Staff Leave Application screens using `LeaveRequestModel`.
4. **Phase 4 — Cloud Function Email Proxy Integration**: Move SMTP email alerts off client code into serverless backend.
