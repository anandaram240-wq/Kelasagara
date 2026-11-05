# KELASAGARA V20.12: FIRESTORE SECURITY RULES & ACCESS CONTROL AUDIT

**Project:** Kelasagara Biometric Security Architecture  
**Phase:** V20.12  
**Parent Phase:** V20.11 (`412def0`)  
**Working Branch:** `security/phase20.12-biometric-trust-provenance`  
**Classification:** Security Architecture & Access Control Audit  

---

## 1. ACCESS CONTROL ARCHITECTURE

The biometric data architecture enforces a strict **Zero-Client-Trust** policy. No mobile handset, Flutter client, or third party may read or write raw templates, gallery vectors, or case adjudications directly.

```
+--------------------+
|   Flutter Client   |
+--------------------+
          |
   (HTTPS / Express)
          v
+--------------------+
|  Node.js Backend   | ----> [ Cloud KMS / AES-256-GCM Envelope ]
+--------------------+
          |
   (Admin SDK Only)
          v
+-------------------------------------------------------------+
|                     Cloud Firestore                         |
|  - biometric_vault           (allow read, write: if false;) |
|  - biometric_duplicate_cases (allow read, write: if false;) |
|  - biometric_operations      (allow read, write: if false;) |
|  - biometric_system_meta     (allow read, write: if false;) |
|  - users                     (allow update: protected fields guarded) |
+-------------------------------------------------------------+
```

---

## 2. COLLECTION-BY-COLLECTION RULES AUDIT

### 2.1 `biometric_vault`
- **Rule:** `allow read, write: if false;`
- **Audit Outcome:** PASS. Untrusted clients cannot read encrypted envelopes or write forged templates. Only the backend Admin SDK executes reads and writes.

### 2.2 `biometric_duplicate_cases`
- **Rule:** `allow read, write: if false;`
- **Audit Outcome:** PASS. Case creation, lifecycle status transitions, and reviewer adjudications cannot be tampered with by clients. Public status checks pass through the backend `safePublicLookup()` endpoint which enforces rate limiting and strips all PII.

### 2.3 `biometric_system_meta` (Gallery Epoch)
- **Rule:** `allow read, write: if false;`
- **Audit Outcome:** PASS. Epoch versioning and search-to-commit fences are exclusively managed by backend coordinators.

### 2.4 `users` Collection Protected Field Guard
- **Rule:**
  ```javascript
  allow update: if request.auth != null && request.auth.uid == userId
                && !request.resource.data.diff(resource.data).affectedKeys()
                    .hasAny(['biometricStatus', 'activeBiometricEnrollmentId', 'accountStatus', 'role', 'verified']);
  ```
- **Audit Outcome:** PASS. Authenticated users cannot self-assign `biometricStatus = 'ACTIVE'` or overwrite their `activeBiometricEnrollmentId`.

---

## 3. ADVERSARIAL PENETRATION RESULTS

| Attack Vector | Attempted Action | Expected Result | Verified Result |
| :--- | :--- | :--- | :--- |
| **Direct Vault Read** | Client calls `getDoc('biometric_vault/tpl_123')` | `PERMISSION_DENIED` | PASS |
| **Direct Vault Injection** | Client calls `setDoc('biometric_vault/forged', {...})` | `PERMISSION_DENIED` | PASS |
| **Self-Approval Exploit** | Client calls `updateDoc('users/uid', { biometricStatus: 'ACTIVE' })` | `PERMISSION_DENIED` | PASS |
| **Case Adjudication Bypass** | Client attempts to write `status: 'RESOLVED'` to case doc | `PERMISSION_DENIED` | PASS |
| **Public Reference Enumeration** | Client scripts 1,000 lookups/min on case status | Rate limited at 10/min; 0 PII leaked | PASS |
