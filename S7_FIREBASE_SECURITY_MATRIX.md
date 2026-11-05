# KELASAGARA BIOMATCH · STAGE S7 FIREBASE SECURITY MATRIX (S7_FIREBASE_SECURITY_MATRIX.md)

**Classification:** Cloud Firestore Access Control, Security Rules & Least-Privilege Policy  
**Stage:** S7  
**Date:** 2026-10-11  
**Target Configuration:** `firestore.rules` (rules_version = '2')

---

## 1. Access Control Policy by Collection

| Collection Path | Read Permission | Create Permission | Update Permission | Delete Permission | Security Rationale |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `biometric_vault/{uid}` | `allow read: if false;` | `allow create: if false;` | `allow update: if false;` | `allow delete: if false;` | **100% Client-Deny:** Accessible ONLY by Firebase Admin SDK on the server backend. Clients cannot read or write raw templates. |
| `biometric_review_queue/{uid}` | `allow read: if isAdmin();` | `allow create: if false;` | `allow update: if isAdmin();` | `allow delete: if false;` | Administrative manual review queue; inaccessible to standard workers. |
| `biometric_rate_limits/{uid}` | `allow read: if false;` | `allow create: if false;` | `allow update: if false;` | `allow delete: if false;` | Backend-managed quota counter; client tamper-proof. |
| `biometric_enrollment_sessions/{uid}` | `allow read: if false;` | `allow create: if false;` | `allow update: if false;` | `allow delete: if false;` | Concurrency lease locks; server-authoritative. |
| `users/{uid}` | `allow read: if isSignedIn();` | `allow create: if isSignedIn() && isOwner();` | Restricted branches | `allow delete: if isAdmin();` | Worker profile document; biometric status fields (`faceVerified`) are strictly server-write only. |
| `audit_logs/{logId}` | `allow read: if isAdmin();` | `allow create: if false;` | `allow update: if false;` | `allow delete: if false;` | Append-only tamper-evident audit ledger; client write prohibited. |

---

## 2. Mass Assignment and Privilege Escalation Defenses

### 2.1 Protection of Biometric Status Fields in `users/{uid}`
In `firestore.rules`, updates from the client are restricted using `.affectedKeys().hasOnly(...)`. The sensitive biometric fields:
- `faceVerified`
- `faceVerifiedAt`
- `verificationStatus`
- `biometricEnrollmentState`
- `biometricPendingReview`

are **excluded** from all client-permitted update branches. A client attempting to write `{faceVerified: true}` is rejected with `permission-denied`. Only the backend server (using privileged Admin SDK service credentials) can update these fields following successful verification.

---

## 3. Exit Gate S7-G08 Sign-Off

**Status:** `DONE-VERIFIED`  
**Evidence Artifact:** `evidence/s7/authorization_matrix.json`  
**Verification:** Default-deny posture verified on biometric collections. Zero client read/write access to `biometric_vault`.
