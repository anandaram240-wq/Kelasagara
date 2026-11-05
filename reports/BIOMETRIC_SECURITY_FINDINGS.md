# KELASAGARA BIOMETRIC ENGINE
## Biometric Security Findings & Access Control Remediation

**Audit Date:** October 23, 2026  
**Status:** ALL CRITICAL VULNERABILITIES REMEDIATED & VERIFIED  
**Governing Standards:** ISO/IEC 24745:2022 (Biometric Information Protection), DPDPA 2023 §8(3), NIST SP 800-63B  

---

## 1. Vulnerability SEC-01: Overbroad Biometric Vault Firestore Rules

### 1.1 Discovery & Root Cause
Prior to remediation, `firestore.rules` contained:
```javascript
// VULNERABLE RULE
match /biometric_vault/{uid} {
  allow read: if isSignedIn();
  allow create, update: if isSignedIn() && (isOwner(uid) || isAdmin());
  allow delete: if isSignedIn() && (isOwner(uid) || isAdmin());
}
```
**Impact (CVSS v3.1: 8.6 - High Confidentiality Impact):**
Any user authenticated via Firebase Authentication (including an attacker registering with a temporary burner SIM) could execute:
```dart
FirebaseFirestore.instance.collection('biometric_vault').get();
```
This leaked the entire biometric registry, including 128-dimensional floating-point vectors, enrolled timestamps, and linked account metadata.

### 1.2 Remediation
The rule was sealed with zero client permissions:
```javascript
// REMEDIATED RULE (Server-Authoritative Only)
match /biometric_vault/{uid} {
  allow read, write: if false;
}
```
- **Client Direct Reads:** Strictly DENIED (Permission Denied 403).
- **Client Direct Writes:** Strictly DENIED (Permission Denied 403).
- **Trusted Backend:** The Node.js service uses the privileged Firebase Admin SDK, which operates outside Firestore Security Rules and retains authorized access to `biometric_vault`.

---

## 2. Vulnerability SEC-02: Client-Side Biometric Gallery Download & Processing

### 2.1 Discovery & Root Cause
In `lib/services/biometric_service.dart` (lines 1060–1160 prior to V12.0), whenever the backend `/cross-account-check` endpoint returned an error or timed out, the client executed a fallback routine:
```dart
// INSECURE FALLBACK
final vaultSnap = await _db.collection('biometric_vault').limit(500).get();
```
The client downloaded hundreds of biometric records to mobile device memory, calculated cosine similarities locally on the phone's CPU, and queried `users/{matchedUid}` to inspect the matched individual's phone number and full name.

### 2.2 Remediation
1. **Complete Removal of Client Gallery Queries:** The `limit(500).get()` query and all client-side vault iteration loops were completely excised from `crossAccountCheck` and `_directFirestoreEnroll`.
2. **Fail-Closed Policy:** When backend endpoints are unreachable, the client displays an honest retry message (`technical_failure_retry`) rather than attempting local matching.
3. **Removal of Unused Firestore Client References:** The unused `_db` instance and `cloud_firestore` import were removed from `biometric_service.dart`.

---

## 3. Vulnerability SEC-03: Client Vector Injection (Ticket T-01)

### 3.1 Threat Scenario
If the backend accepts client-supplied feature vectors (e.g. `probeVector` or `embedding`), an attacker can bypass the camera, quality gates, and liveness checks entirely by sending pre-calculated or synthetic vectors directly via HTTP POST.

### 3.2 Remediation
1. **Client Payload Cleansing:** In `face_enrollment_screen.dart` and `biometric_service.dart`, `probeVector` was removed from the request payload. The mobile app transmits only raw image crops (`imageBase64`) with proof of liveness.
2. **Server Middleware Enforcement:** `checkForbiddenVectorFields` intercepts all incoming requests to `/enroll` and `/verify-1to1`. If any vector field (`probeVector`, `embedding`, `vector`, `features`, `embeddingBase64`) is present, the request is immediately rejected with HTTP 400 Bad Request (`CLIENT_VECTORS_FORBIDDEN`).

---

## 4. Vulnerability SEC-04: Nonce Replay & Cross-Action Attack Defenses

### 4.1 Threat Scenario
An attacker captures a valid challenge nonce issued for verification and attempts to:
- Replay it multiple times.
- Use it for an enrollment transaction.
- Steal a nonce issued to another user.

### 4.2 Remediation
- **Atomic Single-Use Invalidation:** Nonces are consumed atomically upon first evaluation; subsequent attempts are rejected (Invariant I-05).
- **UID Identity Binding:** Challenge nonces are cryptographically bound to the caller's Firebase UID upon generation; cross-user theft is blocked (Invariant I-04).
- **Action Type Binding:** Nonce issuance specifies the permissible action (`enroll` vs `verify`); cross-action reuse is blocked.
- **TTL Gating:** Nonces expire after 120 seconds.

---

## 5. Vulnerability SEC-05: Side-Channel Timing Oracle Attacks

### 5.1 Threat Scenario
By measuring nanosecond server response latency, an attacker can infer whether a user exists in the gallery or whether a candidate face produced a partial match.

### 5.2 Remediation (Invariants I-08 & I-23)
The backend enforces **constant-time response bucketing**. All verification transactions are padded to take at least 300 ms (`sleep(MIN_MS - elapsed)`), eliminating timing discrepancies between cache hits, cache misses, and database queries.

---

## 6. Privacy & PII Masking Verification (DPDPA §8(3))

When a duplicate registration is detected, the API returns strictly masked metadata:
- **Masked UID:** First 3 and last 4 characters (`xK9***wXy`).
- **Masked Phone Number:** Retains only last 4 digits (`+91 ******7890`).
- **Platform Display ID:** `KLS-xK9***wXy-7890`.
- **Zero Raw Embeddings:** Floating-point feature vectors are never transmitted to the client.

---

## 7. Security Verification Matrix

| Security Control | Test Suite / Execution | Result | Status |
| :--- | :--- | :---: | :---: |
| Client direct read on `biometric_vault` | Firestore Rules Simulator | Permission Denied (403) | **PASS** |
| Client direct write on `biometric_vault` | Firestore Rules Simulator | Permission Denied (403) | **PASS** |
| Client-supplied vector rejection | `npm test` Stage S9 Test 2B | HTTP 400 Bad Request | **PASS** |
| Challenge nonce replay prevention | `npm test` Redteam Test 2 | Replay Intercepted & Blocked | **PASS** |
| Cross-user challenge theft prevention | `npm test` Redteam Test 3 | Identity Binding Blocked | **PASS** |
| Cross-action challenge replay prevention | `npm test` Redteam Test 4 | Action Binding Blocked | **PASS** |
| Timing oracle latency padding | `npm test` Stage S9 Test 5 | Padded to $\ge 300\text{ ms}$ | **PASS** |
| Rate limiting (60 req/min) | `npm test` Stage S9 Test 11 | HTTP 429 Uniform Envelope | **PASS** |
| AAD length-prefixed canonical binding | `npm test` Stage S8 Test 2 | Boundary Shifting Defeated | **PASS** |
| DPDPA certified erasure (`DELETE /template`)| `npm test` Stage S9 Test 10 | Cryptographic Erasure Complete | **PASS** |
