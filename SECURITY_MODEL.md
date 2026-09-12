# SECURITY_MODEL.md — Enterprise Attendance System Security & Authentication Model

## 1. Authentication & Role-Based Access Control (RBAC)

The Enterprise Attendance System enforces strict role-based authorization driven by **Firebase Authentication**, **Cloud Firestore User Profiles (`users/{uid}`)**, and **Firebase Custom Auth Claims**.

### Trusted Roles:
- **`MASTER` (System Super Admin)**: Global administrator with full CRUD access across all business tenants, shop registration applications, and master audit logs.
- **`SHOP_ADMIN` (Business Tenant Manager)**: Tenant administrator limited strictly to their designated `businessId`. Manages employees, shift rules, late check-in approvals, holidays, salary advances, and terminal configurations.
- **`KIOSK` (Terminal Device Mode)**: Dedicated attendance kiosk instance scoped exclusively to its provisioned `businessId`. Authorized ONLY to read active employee/shift records and log raw attendance check-ins.

> [!IMPORTANT]
> **No Weak Authorization**: Role determination relies exclusively on verified Firestore user profile documents (`users/{uid}`) and Firebase Auth Custom Claims (`request.auth.token.role`). Email string parsing, domain suffix checks, client-side booleans, and hardcoded credentials are strictly prohibited.

---

## 2. Role Permissions Matrix

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

## 3. Production Cloud Firestore Security Rules (`firestore.rules`)

Tenant isolation and access control are enforced at the database layer via `firestore.rules`:

- **Tenant Isolation**: Non-master users are strictly constrained: `request.auth.token.businessId == businessId` or `getUserData().businessId == businessId`.
- **Attendance Rewrite Protection**: `KIOSK` accounts can `create` attendance records but cannot `update` or `delete` past attendance entries.
- **Self-Modification Block**: Employees cannot alter their own profile attributes or biometric vector data.
- **Application & Audit Security**: `shop_registrations` write/delete and `master_audit_logs` are restricted strictly to `MASTER`.

---

## 4. Production Cloud Storage Security Rules (`storage.rules`)

Cloud Storage assets are protected against unauthorized public access:

- **Employee Photos & Biometric Embeddings**: Path `/businesses/{businessId}/employees/*` is readable ONLY by authenticated users of that `businessId` or `MASTER`.
- **Media & Voice Broadcast Audio**: Path `/businesses/{businessId}/announcements/*` requires tenant authentication.
- **Public Deny-All Fallback**: All un-scoped paths default to `allow read, write: if false;`.

---

## 5. Secret Management & Credential Hygiene

### 5.1 Client Source Cleanliness
- **Zero Source Secrets**: No passwords, API keys, private keys, or SMTP app credentials may be committed to client `.dart` files.
- **Environment Injection**: Sensitive runtime values must be injected via build environment flags:
  ```bash
  flutter run --dart-define=SMTP_USER="user@domain.com" --dart-define=SMTP_PASSWORD="secret_app_password"
  ```
- **Git Protection**: Local configuration files (`.env`, `key.properties`, service account JSONs) are listed in `.gitignore`.

### 5.2 Exposed Credential Revocation Statement
- The legacy SMTP App Password (`zynz isfx bmhd smvw`) previously present in `email_notification_service.dart` has been removed from client code.
- **Action Required**: The Google Account App Password `zynz isfx bmhd smvw` must be immediately revoked in Google Account Security Settings and re-issued as an environment secret for production Cloud Functions.

---

## 6. Serverless Backend Operations

Privileged actions must execute through authenticated Cloud Functions or trusted serverless endpoints:
1. **Email Alert Proxy**: Sending registration confirmation, credentials, and late attendance notification emails.
2. **Shop Provisioning**: Creating Auth credentials for new Shop Admin and Kiosk accounts safely without exposing secondary admin privileges to the client.
