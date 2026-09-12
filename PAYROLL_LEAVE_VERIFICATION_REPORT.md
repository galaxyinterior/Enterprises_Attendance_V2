# PHASE 9 — LEAVE & PAYROLL ENGINE VERIFICATION REPORT

---

## 1. Executive Summary

Phase 9 completes the canonical **Leave & Payroll Engine** for the Enterprise Attendance App. All financial calculations follow deterministic mathematical formulas isolated inside `PayrollCalculationService`, guaranteeing that zero financial arithmetic depends on UI state or inconsistent widget-level logic. Leave management supports entitlements, balance tracking, approval/rejection workflows, and automatic weekly-off/holiday window exclusions.

---

## 2. Leave Management System Architecture

### 2.1 Leave Entitlement & Balance Schema
Employees possess dedicated annual leave entitlement balances tracked on their profile (`EmployeeModel`):
* `casualLeaveBalance` (Default: 12 days)
* `sickLeaveBalance` (Default: 6 days)
* `paidLeaveBalance` (Default: 15 days)

### 2.2 Holiday & Weekly Off Exclusion Logic
When a leave request spans multiple days, `LeaveManagementService.calculateWorkingDaysInLeaveWindow` dynamically evaluates each calendar date in the window:
* Excludes configured weekly off days (e.g. `SUNDAY`).
* Excludes official business holidays in `holidayDatesISO` format (`YYYY-MM-DD`).
* Only active working days deduct from employee leave balances or count towards leave duration.

### 2.3 Leave Request State Machine & Approval Workflow
```
┌─────────────────┐      Admin Review      ┌─────────────────┐
│ PENDING Request │ ─────────────────────► │ APPROVED Status │
└─────────────────┘                        └─────────────────┘
         │                                          │
         │ Rejection                                │ Deducts Leave Balance
         ▼                                          ▼
┌─────────────────┐                        ┌─────────────────┐
│ REJECTED Status │                        │ Updated Employee│
└─────────────────┘                        └─────────────────┘
```
If an employee's requested leave days exceed their remaining balance for a paid leave category, `LeaveManagementService` automatically converts the excess days to `UNPAID` leave, ensuring transparent auditability.

---

## 3. Deterministic Payroll Calculation Engine

`PayrollCalculationService` standardizes all salary, deduction, and payslip math across `MONTHLY`, `DAILY`, and `HOURLY` pay structures.

### 3.1 Payroll Formulas

#### Monthly Base Salary Formula
$$\text{Per Day Rate} = \frac{\text{Monthly Base Salary}}{\text{Total Working Days}}$$
$$\text{Hourly Rate} = \frac{\text{Per Day Rate}}{8.0}$$
$$\text{Unpaid Leave Deduction} = \text{Unpaid Leave Days} \times \text{Per Day Rate}$$

#### Overtime & Bonus Formula
$$\text{Overtime Pay} = \text{Overtime Hours} \times \text{Hourly Rate} \times \text{Overtime Multiplier (1.5x)}$$
$$\text{Gross Salary} = \text{Base Salary} + \text{Overtime Pay} + \text{Bonus/Commission}$$

#### Deductions & Net Salary Formula
$$\text{Total Deductions} = \text{Unpaid Leave Deduction} + \text{Late Fine Deduction} + \text{Advance Deduction} + \text{Other Deductions}$$
$$\text{Net Salary} = \max(0, \text{Gross Salary} - \text{Total Deductions})$$

All values are rounded using 2-decimal fixed precision (`.toStringAsFixed(2)`) to prevent cross-platform floating-point drift.

---

## 4. Verification & Automated Test Results

The test suite in [`test/payroll_engine_test.dart`](file:///j:/app%20dev/Attendance%20App/test/payroll_engine_test.dart) verifies all leave and salary combinations:

```
00:02 +12: J:/app dev/Attendance App/test/payroll_engine_test.dart: Payroll & Leave Engine Unit Tests 1. Monthly Base Salary - Full Attendance (Zero Absences)
00:02 +13: J:/app dev/Attendance App/test/payroll_engine_test.dart: Payroll & Leave Engine Unit Tests 2. Monthly Base Salary with Unpaid Leaves Deduction
00:02 +14: J:/app dev/Attendance App/test/payroll_engine_test.dart: Payroll & Leave Engine Unit Tests 3. Overtime Pay with Custom Rate Multiplier (1.5x)
00:02 +15: J:/app dev/Attendance App/test/payroll_engine_test.dart: Payroll & Leave Engine Unit Tests 4. Salary Advance & Late Arrival Fine Deductions
00:02 +16: J:/app dev/Attendance App/test/payroll_engine_test.dart: Payroll & Leave Engine Unit Tests 5. Daily & Hourly Employee Wage Calculations
00:02 +17: J:/app dev/Attendance App/test/payroll_engine_test.dart: Payroll & Leave Engine Unit Tests 6. Leave Window Calculation Excluding Weekly Offs & Holidays
00:02 +18: J:/app dev/Attendance App/test/payroll_engine_test.dart: Payroll & Leave Engine Unit Tests 7. Leave Approval & Entitlement Balance Decrement
00:04 +29: All tests passed!
```

---

## 5. System Integrity & Static Analysis

* **`flutter analyze`**: **0 issues found** (Ran in 11.3s cleanly).
* **`flutter test`**: **29/29 tests passed** across all project modules.
