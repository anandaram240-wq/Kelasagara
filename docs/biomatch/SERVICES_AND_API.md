# KELASAGARA BIOMATCH V7: SERVICES & API SPECIFICATION

**Document ID:** `SPEC-BIOMATCH-V7-009`  
**Phase:** Phase 9 (Services and API)  
**As-of Date:** 2026-10-10  
**Current Branch:** `biomatch/v7-hardening`  
**Active Release Readiness Level:** **RRL-0 (Research Prototype)**  
**Target Platform:** Firebase Spark Plan (Free Tier) | Backend: Standalone Node.js Tier 0 Prototype | Sole Store: Cloud Firestore  

---

## 1. ARCHITECTURAL ROLE & RUNTIME CONTEXT

Under **Part 4.3 (Tier Ladder)** and **ADR-001 (Store Decision)**:
- The standalone Express/Node.js service operates strictly as **Tier 0 (Dev/Shadow Prototype Only, Non-Authoritative)**.
- It provides authoritative local computation (M4 Mac during dev, self-hosted container in staging) to bypass Cloud Functions paid Blaze requirements.
- **Sole Persistent Database:** All template vectors and audit ledgers persist exclusively in **Cloud Firestore** (`asia-south1` Mumbai). No local SQLite or external vector engines are used.
- **Client Security:** Mobile clients never write to `biometric_vault` or mutate `users.faceVerified` directly (Invariants I-02, I-14). All mutations route through this backend via verified Firebase Auth tokens.

---

## 2. UNIFORM API CONTRACT & ORACLE DEFENSE

To defeat API oracle probing and timing side-channel attacks (Invariants I-08, I-23):
1. **Uniform Envelope (`UniformBiometricApiResponse<T>`):** All endpoints return identical JSON envelope keys (`success`, `status`, `data`, `error`, `serverTimestamp`).
2. **Constant-Time Latency Bucketing:** All verification and enrollment operations enforce a minimum latency floor ($\ge 150\text{ms}$). Fast exits (e.g. 404 un-enrolled, immediate duplicate hit) are artificially padded with micro-sleeps. This prevents an adversary from determining whether a probe face matched an early index candidate based on network round-trip time.
3. **Per-IP Rate Limiting:** An in-process sliding window limits requests to **60 req/min per IP** with HTTP 429 backoff, protecting free-tier Spark read quotas against automated parameter scanners.

```typescript
interface UniformBiometricApiResponse<T = any> {
  success: boolean;
  status: string;
  data?: T;
  error?: {
    code: string;
    message: string;
  };
  serverTimestamp: string;
}
```

---

## 3. ENDPOINT DEFINITIONS

### 3.1 GET `/api/biometrics/health`
Public telemetry and operational health probe.

- **Auth:** None (Public).
- **Response (200 OK):**
```json
{
  "success": true,
  "status": "healthy",
  "data": {
    "service": "kelasagara-biomatch-backend",
    "modelVersion": "kelasagara_mobilefacenet_v1_arcface",
    "tier": "RESEARCH_ONLY",
    "duplicateThreshold": 0.74,
    "database": "Cloud Firestore Asia-South1 Only"
  },
  "serverTimestamp": "2026-10-10T03:30:00.000Z"
}
```

---

### 3.2 POST `/api/biometrics/challenge`
Issues a single-use cryptographic challenge nonce bound to the caller's verified UID and intended action (Invariants I-04, I-05).

- **Auth:** Required (`Bearer <FirebaseIdToken>`).
- **Request Body:**
```json
{
  "action": "ENROLLMENT" // or "VERIFICATION"
}
```
- **Response (200 OK):**
```json
{
  "success": true,
  "status": "challenge_issued",
  "data": {
    "challengeNonce": "chal_4f92...:e81b...",
    "expiresAt": 1791598260000,
    "action": "ENROLLMENT",
    "ttlSeconds": 60,
    "serverTimestamp": "2026-10-10T03:30:00.000Z"
  },
  "serverTimestamp": "2026-10-10T03:30:00.000Z"
}
```
- **Security Guarantees:** 60-second TTL; strictly bound to `uid` and `action`; single-use only.

---

### 3.3 POST `/api/biometrics/enroll`
Authoritative face template enrollment and 1:N duplicate screening.

- **Auth:** Required (`Bearer <FirebaseIdToken>`).
- **Request Body:**
```json
{
  "role": "worker",
  "imageBase64": "<base64_encoded_face_crop>",
  "challengeNonce": "chal_4f92...:e81b...",
  "clientSessionId": "sess_worker_999",
  "livenessAudit": {
    "blinkVerified": true,
    "headEulerYaw": 2.1,
    "headEulerRoll": -1.4,
    "method": "mlkit_ear"
  }
}
```
- **Response (200 OK - Under RESEARCH_ONLY Model):**
```json
{
  "success": true,
  "status": "pending_review",
  "data": {
    "status": "pending_review",
    "isApproved": false,
    "isDuplicate": false,
    "similarity": 0.321,
    "threshold": 0.74,
    "accountStatus": "pending_review",
    "message": "Biometric template captured under RESEARCH_ONLY model (uncalibrated weights). Automated clearance is disabled; submission routed to manual administrative review."
  },
  "serverTimestamp": "2026-10-10T03:30:00.165Z"
}
```
- **Response (200 OK - Duplicate Intercepted):**
```json
{
  "success": false,
  "status": "duplicate",
  "data": {
    "status": "duplicate",
    "isApproved": false,
    "isDuplicate": true,
    "matchedUid": "existing_user_abc",
    "maskedPhone": "+91 ******1234",
    "similarity": 0.884,
    "threshold": 0.74,
    "message": "Your face may already be associated with a Kelasagara account (+91 ******1234). Duplicate accounts violate platform security policies."
  },
  "serverTimestamp": "2026-10-10T03:30:00.180Z"
}
```

---

### 3.4 POST `/api/biometrics/verify-1to1` (Alias: `/verify-login`)
1:1 biometric probe verification against user's own enrolled template in `/biometric_vault/{uid}`.

- **Auth:** Required (`Bearer <FirebaseIdToken>`).
- **Request Body:**
```json
{
  "imageBase64": "<base64_encoded_face_crop>",
  "challengeNonce": "chal_77a1...:31c9...",
  "role": "worker"
}
```
- **Response (200 OK - Verified):**
```json
{
  "success": true,
  "status": "verified",
  "data": {
    "isMatch": true,
    "similarity": 0.942,
    "threshold": 0.74,
    "message": "Facial identity verified successfully."
  },
  "serverTimestamp": "2026-10-10T03:30:00.155Z"
}
```
- **Response (404 Not Found - Not Enrolled):**
```json
{
  "success": false,
  "status": "not_enrolled",
  "error": {
    "code": "NOT_ENROLLED",
    "message": "No biometric template enrolled for this user account."
  },
  "serverTimestamp": "2026-10-10T03:30:00.152Z"
}
```

---

### 3.5 DELETE `/api/biometrics/template`
Fulfills Right-to-Erasure under Section 12 of the Digital Personal Data Protection Act (DPDPA 2023).

- **Auth:** Required (`Bearer <FirebaseIdToken>`).
- **Query Parameter:** `targetUid` (Optional; defaults to caller UID. Admins may delete arbitrary UIDs).
- **Response (200 OK):**
```json
{
  "success": true,
  "status": "deleted",
  "data": {
    "message": "Biometric template and associated cryptographic salts permanently deleted.",
    "targetUid": "worker_uid_123"
  },
  "serverTimestamp": "2026-10-10T03:30:00.000Z"
}
```
- **Security Control:** Caller attempting to delete a different UID without admin claims receives `403 FORBIDDEN` (Invariant I-24).

---

## 4. INTEGRATION & VERIFICATION EVIDENCE

The complete API layer was tested in `backend/src/tests/api_routes_integration.test.ts`.  
All 7/7 test suites passed cleanly:
1. Health probe uniform response verified.
2. Unauthenticated request rejected (401) and invalid action rejected (400).
3. Challenge nonce issued with 60s TTL (Invariant I-04).
4. Nonce cross-action reuse strictly rejected (Invariant I-05).
5. Constant-time latency bucketing verified ($\ge 150\text{ms}$ padding, Invariants I-08, I-23).
6. 1:1 facial verification match flow executed cleanly.
7. DPDPA cross-user template deletion rejected (403); own deletion authorized (200).
