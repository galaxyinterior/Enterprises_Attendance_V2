# MASTER_PROVISIONING_TEST_REPORT.md — Master Panel & Provisioning Test Report

## 1. Executive Summary

This report documents the verification, registration review history, provisioning state machine, shop control (active/paused/suspended), device terminal binding, and master audit logging for the **Master Panel & Trusted Provisioning System**, conforming strictly to the **Master Implementation Rules**.

---

## 2. Master Registration & Review Workflow

```
┌───────────────────────────┐     ┌────────────────────────────┐     ┌────────────────────────────┐
│ Incoming Registration     │ ──► │ Master Review Panel        │ ──► │ Approve / Reject Choice    │
│ Application Form           │     │ (View Details & History)   │     │ (Document Reason if Reject)│
└───────────────────────────┘     └────────────────────────────┘     └────────────────────────────┘
                                                                                    │
┌───────────────────────────┐     ┌────────────────────────────┐                    ▼
│ Retained Application      │ ◄── │ Provisioning State Machine │ ◄──────────────────┘
│ Record (`status:APPROVED`)│     │ (IN_PROGRESS -> COMPLETED) │
└───────────────────────────┘     └────────────────────────────┘
```

* **No Immediate Deletion**: Approved and rejected registration documents are retained in `shop_registrations` with updated status (`APPROVED` / `REJECTED`), `rejectionReason`, `reviewedAt`, and `reviewedBy = 'MASTER'`.

---

## 3. Provisioning State Machine

Provisioning executes with strict state tracking:

```
[NOT_STARTED] ──► [IN_PROGRESS] ──► (Create Admin Auth & Kiosk Auth)
                                       │
                ┌──────────────────────┴──────────────────────┐
                ▼                                             ▼
          [COMPLETED]                                [PARTIAL_FAILURE / FAILED]
   (All Accounts & Claims Ready)               (Tracked Error & Recovery Path)
```

| Provisioning State | Description |
| --- | --- |
| **`NOT_STARTED`** | Application submitted; awaiting Master Admin review. |
| **`IN_PROGRESS`** | Provisioning process initiated; Firebase Auth accounts being created. |
| **`COMPLETED`** | Admin & Kiosk accounts created, Firestore profiles written, credentials email dispatched. |
| **`PARTIAL_FAILURE`** | One account created successfully, secondary account encountered exception. |
| **`FAILED`** | Provisioning aborted due to duplicate Shop ID or system error; error recorded. |

---

## 4. Shop Control & Status Management

Master Admin can update business status across three operational states:

1. **`active`**: Full operational state. Admin console, kiosk scanning, and background sync active.
2. **`paused`**: Kiosk displays `"Shop Paused"` banner. New face recognition attendance check-ins are blocked; pending offline SQLite records are safely retained.
3. **`suspended`**: Business access suspended due to account expiration or administrative action.

---

## 5. Kiosk Device Terminal Binding & Unpairing

* **Device Binding Schema**: `businesses/{businessId}/devices/{deviceId}`
* **Attributes**: `deviceId`, `businessId`, `pairingCode`, `status` (`PAIRED` / `UNPAIRED`), `lastSeen`, `lastSync`, `appVersion`.
* **Revocation / Unpairing**: Master Admin or Shop Admin can trigger `unpairDevice(businessId, deviceId)`, setting device status to `UNPAIRED` and logging an audit event.

---

## 6. Master Audit Logging

All privileged operations write immutable audit records to `master_audit_logs`:
* `PROVISION_SHOP`: Logged when a new shop application is approved and provisioned.
* `REJECT_REGISTRATION`: Logged with application ID and rejection reason.
* `UPDATE_SHOP_STATUS`: Logged when shop state changes between `active`, `paused`, `suspended`.
* `UNPAIR_DEVICE`: Logged when a kiosk terminal authorization is revoked.

---

## 7. Automated Test Suite Results (`test/master_provisioning_test.dart`)

```
00:00 +3: All tests passed!

✓ 1. Provisioning State Machine Transitions
✓ 2. Shop Status Control Transitions (active / paused / suspended)
✓ 3. Device Terminal Status Transitions (PAIRED / UNPAIRED)
```
