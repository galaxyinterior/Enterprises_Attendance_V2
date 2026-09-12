# ATTENDANCE_ENGINE_TEST_REPORT.md — Attendance & Shift Engine Test Report

## 1. Executive Summary

This report documents the verification, state machine safeguards, shift evaluation rules, idempotency strategy, and automated test suite results for the **Attendance & Shift Engine**, conforming strictly to the **Master Implementation Rules**.

---

## 2. Attendance & Shift Engine Architecture

```
┌─────────────────┐     ┌──────────────────────┐     ┌───────────────────────┐     ┌──────────────────────┐
│ Face Verified   │ ──► │ Fetch Employee Shift │ ──► │ Check 5-Min Cooldown  │ ──► │ Evaluate Shift Rules │
│ Embedding       │     │ & Local Custom Rules │     │ Safeguard (SQLite)    │     │ (Start, Grace, Max)  │
└─────────────────┘     └──────────────────────┘     └───────────────────────┘     └──────────────────────┘
                                                                                              │
┌─────────────────┐     ┌──────────────────────┐     ┌───────────────────────┐                ▼
│ Background Cloud│ ◄── │ Store SQLite DB      │ ◄── │ Generate SHA-256      │ ◄── ┌──────────────────────┐
│ Firestore Sync  │     │ (Offline First)      │     │ Deterministic ID      │     │ State Assignment     │
└─────────────────┘     └──────────────────────┘     └───────────────────────┘     │ (Present vs Late)    │
                                                                                   └──────────────────────┘
```

---

## 3. Core Shift Business Logic & State Machine

### 3.1 Idempotency & Unique Event ID Strategy
* Every attendance event generates a deterministic SHA-256 hash ID (`ShiftEngineService().generateDeterministicAttendanceId`):
  $$\text{ID} = \text{ATT-} + \text{SHA256}(businessId : employeeId : date)[0..24]$$
* **Duplicate Submission Prevention**: Retrying check-in or resending network payloads for the exact same employee on the same date produces the identical primary key, preventing duplicate document creation in SQLite or Cloud Firestore.

### 3.2 Duplicate Scan Safeguard
* **Cooldown Window**: `hasRecentAttendance` checks SQLite for recent logs within 5 minutes.
* If a scan occurs within 5 minutes of a successful check-in, the kiosk speaks:
  `"$name, your attendance was already logged recently."` and skips logging a duplicate entry.

### 3.3 Shift Deadline & Late Approval Workflow
* **On-Time Check-In**: Check-in on or before `maxCheckInTime` (e.g. 09:15 AM for a 09:00 AM shift) $\rightarrow$ Status: `PRESENT`, Approval: `APPROVED`.
* **Late Check-In**: Check-in after `maxCheckInTime` $\rightarrow$ Status: `ABSENT`, Approval: `PENDING`. Triggers interactive modal for employee reason submission and emails the admin.

### 3.4 Early Checkout & Overnight Shift Handling
* **Overnight Shifts**: Detects when `endTime < startTime` (e.g., 10:00 PM to 06:00 AM) and shifts the expected checkout boundary to day $+ 1$.
* **Early Checkout**: Calculates early departure minutes if check-out occurs prior to scheduled shift end time.

---

## 4. UTC Storage & Timezone Strategy

* **Storage Format**: ISO 8601 UTC strings (`DateTime.now().toUtc().toIso8601String()`) used for database serialization.
* **Display Format**: Localized 12-hour AM/PM formatting (`hh:mm a`) applied in the UI.
* **Clock Jump Safety**: Idempotency keys prevent duplicate database inserts even if the system clock rolls backward or forward during offline operation.

---

## 5. Automated Unit Test Results (`test/shift_engine_test.dart`)

```
00:01 +6: All tests passed!

✓ 1. Normal Check-In On Time (Present)
✓ 2. Late Check-In Past Deadline (Absent Pending Reason)
✓ 3. Custom Shift Evaluation with Grace Period
✓ 4. Early Checkout Calculation
✓ 5. Overnight Shift Detection and Checkout
✓ 6. Idempotent Deterministic Attendance ID Generation
```

| Test # | Test Description | Expected Behavior | Result | Status |
| --- | --- | --- | --- | :---: |
| **1** | **Normal Check-In On Time** | Status `PRESENT`, `isLate = false` | `isLate = false`, `lateMinutes = 0` | 🟢 PASS |
| **2** | **Late Check-In Past Deadline** | Status `ABSENT`, `isLate = true` | `isLate = true`, `lateMinutes = 45` | 🟢 PASS |
| **3** | **Custom Shift & Grace Period** | 30-min grace period respected | `resOnTime = PRESENT`, `resLate = ABSENT` | 🟢 PASS |
| **4** | **Early Checkout Calculation** | Detect 30 mins early departure | `isEarly = true`, `earlyMins = 30` | 🟢 PASS |
| **5** | **Overnight Shift Handling** | 10 PM – 6 AM shift detected | `isOvernight = true`, `isEarly = false` | 🟢 PASS |
| **6** | **Idempotent Deterministic ID** | Identical SHA-256 hash generated | `id1 == id2`, `id1 != idDifferentDate` | 🟢 PASS |
