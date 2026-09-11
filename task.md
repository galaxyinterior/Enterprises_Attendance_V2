# Production Attendance Ecosystem Task Checklist

## Phase 0: Functional Audit & Model Tensor Inspection
- [x] TFLite Tensor Input/Output Shape Inspection (`[1, 112, 112, 3]` -> `[1, 128]`)
- [x] Preprocessing Float Normalization Audit `(pixel - 127.5) / 128.0`
- [x] SQLite Performance Indexing (`idx_emp_business`, `idx_att_sync`, `idx_att_dup`)
- [x] `flutter analyze` 0 errors / warnings check

## Phase 1: Real Face Enrollment (Admin Panel)
- [x] Real Face Vector extraction during employee registration in `AddEmployeeScreen`
- [x] Safe double-precision list conversion for Firestore (`faceEmbedding` 128D array)
- [x] Instant enrollment save to local SQLite DB (`local_employees`)
- [x] Face Enrollment Status Badge (`Enrolled` vs `Pending`) in Admin Staff List

## Phase 2: Production-Grade Kiosk Face Recognition Engine (100% Offline)
- [x] Eliminate mid-scan network blocking calls
- [x] Pre-load local SQLite embeddings into RAM cache on Kiosk boot
- [x] Frame throttling (1 frame / 800ms) for smooth continuous operation
- [x] Fast in-memory cosine similarity matching against local RAM cache

## Phase 3: Liveness & Anti-Spoofing Verification
- [x] Eye-blink transition detection (`leftEyeOpenProbability` / `rightEyeOpenProbability` dip < 0.35 -> open > 0.70)
- [x] Live head orientation / angle validation
- [x] Visual Eye-Blink instruction pill UI (`👁️ Position Face & Blink Eyes to Confirm`)

## Phase 4: Shift Engine & Attendance Rules Validation
- [x] Shift timing window validation (Morning / Evening / Night / General Shift)
- [x] Status classification (`PRESENT`, `LATE`, `EARLY_CHECKOUT`, `HALF_DAY`)
- [x] 5-minute duplicate check-in buffer safeguard

## Phase 5: Offline SQLite Queue & Background Idempotent Sync
- [x] Offline queue persistence in SQLite with `syncStatus: PENDING`
- [x] Background network listener for auto-syncing pending attendance to Cloud Firestore
- [x] Idempotent Firestore set using `attendanceId` UUID key

## Phase 6: Admin Panel Management & Real Data Integration
- [x] 100% Real Firestore Data Binding for Staff Directory CRUD
- [x] Daily Attendance Log Table with real-time updates
- [x] Payroll & Shift Assignment UI

## Phase 7: Master Panel Provisioning & Role-Based Security
- [x] Role authorization enforcement (`MASTER`, `SHOP_ADMIN`, `KIOSK`)
- [x] Kiosk Device Pairing with Security PIN (`1234`)
- [x] Master Panel Business Approval State Machine (`PENDING` -> `APPROVED` / `REJECTED` -> `ACTIVE` / `PAUSED`)

## Phase 8: Leave, Advance Salary & Voice Announcements Engine
- [x] Leave request approval workflow & Advance Salary logs
- [x] Voice Announcements (TTS) for Check-In, Late Arrival, Shift Alert, Emergency Panic

## Phase 9: Production Security Hardening & End-to-End Testing
- [x] Enforce Firestore Security Rules & Storage Rules
- [x] E2E Testing (Offline Kiosk -> Local Recognition -> SQLite Queue -> Auto Sync -> Admin View)
- [x] `flutter analyze` 0 errors verification

## Phase 10: Production Release & Deployment
- [ ] Build release APK (`flutter build apk`)
- [ ] Build web bundle (`flutter build web`)
