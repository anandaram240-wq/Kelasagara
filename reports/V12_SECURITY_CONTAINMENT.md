# KELASAGARA BIOMETRIC ENGINE V12.0
## Security Containment Report: Biometric Vault Remediation

**Date:** October 23, 2026  
**Status:** CONTAINMENT IMPLEMENTED & VERIFIED  
**Severity:** CRITICAL (CVSS v3.1: 8.6 - High Confidentiality Impact)  
**Standard Compliance:** ISO/IEC 24745:2022 (Biometric Information Protection), DPDPA 2023 §8(3), Aadhaar Face RD Security Architecture  

---

## 1. Executive Summary

During the Phase Zero forensic audit of the Kelasagara codebase, an overbroad authorization vulnerability was identified in `firestore.rules`. Specifically, `biometric_vault/{uid}` allowed all authenticated users (`isSignedIn()`) to execute collection-wide `read` queries. 

Furthermore, `lib/services/biometric_service.dart` contained client-side fallback routines (`_directFirestoreEnroll` and `crossAccountCheck`) that explicitly issued `_db.collection('biometric_vault').limit(500).get()` directly from mobile client devices whenever backend endpoints failed or timed out.

This pattern violated the fundamental registered device and biometric isolation principles mandated by UIDAI Face RD, ISO/IEC 24745, and the Digital Personal Data Protection Act (DPDPA) 2023. 

Immediate containment has been enacted:
1. `firestore.rules` has been updated to permanently seal `biometric_vault/{uid}` with `allow read, write: if false;`.
2. All client-side direct reads and writes to `biometric_vault` in Flutter (`biometric_service.dart`) have been completely excised.
3. Fallback behavior has been converted to strict **fail-closed** (`technical_failure_retry`).

---

## 2. Vulnerability Analysis & Forensic Root Cause

### 2.1 The Vulnerable Firestore Rule

Prior to remediation, the rule in `firestore.rules` read:

```javascript
// VULNERABLE RULE (PRE-V12.0)
match /biometric_vault/{uid} {
  allow read: if isSignedIn();
  allow create, update: if isSignedIn() && (isOwner(uid) || isAdmin());
  allow delete: if isSignedIn() && (isOwner(uid) || isAdmin());
}
```

### 2.2 Attack Vector & Exposure Surface
1. **Direct Vault Enumeration:** Any authenticated user (hirer, worker, or malicious user registering with an anonymous or burner phone number) could issue a Firestore collection query:
   ```dart
   FirebaseFirestore.instance.collection('biometric_vault').get();
   ```
   This returned all enrolled users' 128-dimensional floating point embeddings, UIDs, and metadata.
2. **Client-Side Fallback Leakage:** In `lib/services/biometric_service.dart` (lines 1060–1160 prior to V12.0), when the server-side cross-account check threw an error (which occurred on every call due to Contract Mismatch C-05: `embeddingBase64` vs `imageBase64`), the mobile client systematically executed:
   ```dart
   final vaultSnap = await _db.collection('biometric_vault').limit(500).get();
   ```
   This downloaded hundreds of user biometric templates into mobile memory on every enrollment attempt.
3. **Cross-Account PII Leakage:** When a match was found client-side, the client code read the matched user's record from `users/{matchedUid}` to display their masked phone number and name.

### 2.3 Period of Vulnerability
- **Introduction:** Commit `1020693` introduced the client-side 1:N deduplication fallback to handle offline/disconnected worker enrollment.
- **Duration:** Active across all intermediate releases until V12.0 security containment.
- **Containment Timestamp:** 2026-10-23T08:31:39Z.

---

## 3. Remediation Implementation

### 3.1 Firestore Security Rules Remediation
`firestore.rules` was modified to enforce complete server-side isolation:

```javascript
// REMEDIATED RULE (V12.0 PART 3)
// ── BIOMETRIC VAULT (Server-Authoritative Only — ISO/IEC 24745 & DPDPA 2023) ──
// Biometric templates are strictly confidential and must never be exposed to clients.
// Client direct reads, listings, queries, and writes are DENIED.
// All 1:1 verification and 1:N duplicate screening execute strictly on the trusted backend
// using the Firebase Admin SDK (which bypasses security rules).
match /biometric_vault/{uid} {
  allow read, write: if false;
}
```

### 3.2 Client Code Remediation (`biometric_service.dart`)
1. **Elimination of `probeVector` from Client Requests:** Client vectors are strictly forbidden per ISO 24745 to prevent injection of synthetic embeddings. Only `imageBase64` is transmitted over TLS with replay challenge nonces.
2. **Elimination of Client Vault Queries:** Removed `_db.collection('biometric_vault')` from `crossAccountCheck` and removed `_directFirestoreEnroll`.
3. **Fail-Closed Policy:** When backend endpoints are unreachable, the client displays a retry message (`technical_failure_retry`) rather than falling back to unverified client-side operations.
4. **Removal of Unused Firestore Dependency:** The unused `FirebaseFirestore _db` instance and `cloud_firestore` import were removed from `biometric_service.dart`.

### 3.3 Backend API Verification
All cross-account deduplication is routed to `POST /api/biometrics/cross-account-check`. The endpoint:
- Validates Firebase ID Token (`authenticateFirebaseToken`).
- Runs server-side ONNX inference (`SFace`).
- Scans the encrypted/in-memory gallery (`InMemoryBiometricIndex` / `FirestoreBiometricRepository`).
- Masks all identifiers before returning (`maskUid`, `maskPhoneNumber`, `maskedDisplayId`).
- Records audit logs in `AuditService`.

---

## 4. Verification & Regression Analysis

| Test Case | Method | Expected Result | Verified Result | Status |
| :--- | :--- | :--- | :--- | :---: |
| Client read on `/biometric_vault/{uid}` | Firebase Rule Simulator / Direct SDK | Permission Denied (403) | Rule rejects `read` for all signed-in users | **PASS** |
| Client write on `/biometric_vault/{uid}` | Direct SDK | Permission Denied (403) | Rule rejects `write` for all signed-in users | **PASS** |
| Client collection query on `/biometric_vault` | Firestore Query | Permission Denied (403) | Queries rejected by security rules | **PASS** |
| Server Admin SDK vault operations | Node.js Backend Integration | Authorized | Admin SDK bypasses rules and accesses vault | **PASS** |
| Network disconnect during enrollment | Mobile Client Simulation | `technical_failure_retry` | Fail-closed message displayed to user; no leak | **PASS** |

---

## 5. Containment Sign-Off
- **Architectural Alignment:** Aadhaar Face RD principle achieved — mobile client acts as registered capture device only; identity repository (CIDR analog) is completely unreachable from client devices.
- **Privacy Compliance:** DPDPA 2023 §8(3) and ISO/IEC 24745:2022 template confidentiality guarantees restored.
