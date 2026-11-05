# KELASAGARA V19.1 — ENDPOINT INVENTORY & ROUTE CONTRACT

**Audit Date:** 2026-10-31  
**Architecture:** Authoritative Standalone Express Backend + Cloud Gateway  
**Base URL:** `https://latest-antibodies-sides-studio.trycloudflare.com`  
**API Prefix:** `/api/biometrics/v10`

---

## 1. Verified Biometric Endpoint Inventory

| Operation | Flutter Caller | Backend Handler | HTTP Route | Auth Enforced | Deployed & Live Status |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **System Liveness Probe** | Health monitor / Sentry | `app.get('/health')` in `server.ts` | `GET /health` | None (Public Probe) | **Live 200 OK** |
| **System Readiness Probe** | Health monitor / Sentry | `app.get('/ready')` in `server.ts` | `GET /ready` | None (Public Probe) | **Live 200 OK** |
| **V10 Subsystem Health** | `BiometricService.checkHealth()` | `router.get('/health')` in `biometric_v10_routes.ts` | `GET /api/biometrics/v10/health` | None (Public Probe) | **Live 200 OK** |
| **Challenge Acquisition** | `BiometricService.acquireV10Challenge()` / `acquireActiveChallenge()` | `router.post('/challenge')` in `biometric_v10_routes.ts` | `POST /api/biometrics/v10/challenge` | Firebase ID Token (`Bearer`) | **Live 200 OK** |
| **Initial Face Enrollment** | `BiometricService.enrollBiometric()` in `face_enrollment_screen.dart` | `router.post('/enroll')` in `biometric_v10_routes.ts` | `POST /api/biometrics/v10/enroll` | Firebase ID Token (`Bearer`) | **Live 200 OK** |
| **1:N Duplicate Interception** | Triggered inside `POST /enroll` | `BiometricLifecycleCoordinatorV10.enrollInitial()` | Internal to `/enroll` | Firebase ID Token (`Bearer`) | **Live 409 Conflict (Intercepted)** |
| **1:1 Face Verification (eKYC)** | `BiometricService.verify1to1()` | `router.post('/verify-1to1')` in `face_routes.ts` | `POST /api/biometrics/verify-1to1` | Firebase ID Token (`Bearer`) | **Live 200 OK** |
| **Authorized Re-Enrollment** | `BiometricService.reEnroll()` | `router.post('/re-enroll')` in `biometric_v10_routes.ts` | `POST /api/biometrics/v10/re-enroll` | Firebase ID Token + Step-up Token | **Live 200 OK** |
| **Template Erasure (Right to Forget)** | `BiometricService.deleteBiometricRecord()` | `router.delete('/template')` in `face_routes.ts` | `DELETE /api/biometrics/template` | Firebase ID Token (`Bearer`) | **Live 200 OK** |

---

## 2. Complete Execution Path Traces

### Flow 1: Challenge Nonce Acquisition
```
Flutter Handset (Wi-Fi or 4G/5G)
   │
   ├─► POST https://latest-antibodies-sides-studio.trycloudflare.com/api/biometrics/v10/challenge
   │     Headers: Authorization: Bearer <Firebase_ID_Token>
   │     Body: { "purpose": "INITIAL_ENROLLMENT" }
   │
   ▼
Express Backend (backend/src/routes/biometric_v10_routes.ts)
   │
   ├─► authenticateFirebaseToken(req, res, next)
   │     Validates Firebase JWT via admin.auth().verifyIdToken()
   │
   ├─► Generates crypto-random challengeId & nonce (60-second TTL)
   ├─► Stores ticket in Cloud Firestore: biometric_challenges/{challengeId}
   │
   ▼
Response: 200 OK { challengeId, nonce, purpose, expiresAtMs }
```

### Flow 2: Face Enrollment & 1:N Deduplication (Fail-Closed, Zero PII Leakage)
```
Flutter Handset (Android CamX 112x112 Luma Buffer)
   │
   ├─► POST https://latest-antibodies-sides-studio.trycloudflare.com/api/biometrics/v10/enroll
   │     Headers: Authorization: Bearer <Firebase_ID_Token>
   │     Body: {
   │       challengeId: "...",
   │       nonce: "...",
   │       idempotencyKey: "idem_...",
   │       imageBase64: "<jpeg_base64>",
   │       role: "worker"
   │     }
   │
   ▼
Express Backend (backend/src/routes/biometric_v10_routes.ts)
   │
   ├─► 1. authenticateFirebaseToken(req) -> validates UID
   ├─► 2. checkForbiddenVectorFields(req) -> rejects client embeddings (Ticket T-01)
   ├─► 3. consumeChallenge() -> atomically marks challenge consumed in Firestore transaction
   ├─► 4. CanonicalSFaceEngineV10.extractCanonicalEmbeddingFromAligned112(imageBuffer)
   │        Executes OpenCV Zoo SFace ONNX neural model -> 128-D vector
   │        L2-normalizes to unit hypersphere S^127
   │
   ├─► 5. BiometricLifecycleCoordinatorV10.enrollInitial()
   │        Checks user doc in users/{uid} (Must exist, not locked/suspended)
   │        Executes 1:N KNN search against compatible SFace gallery
   │
   ├─► Decision Gate A: Unique Face (< 0.363 cosine similarity)
   │     Commits record to private biometric_vault/{enrollmentId} (AES-256-GCM encrypted)
   │     Atomically marks users/{uid}.faceVerified = true & accountStatus = 'approved'
   │     Returns: HTTP 200 COMMITTED { enrollmentId, status: 'approved' }
   │
   └─► Decision Gate B: Duplicate Detected (Cosine >= 0.74)
         Issues tamper-proof case reference: CASE-XXXXXXXX
         Persists incident log in private biometric_duplicate_cases/{caseId}
         Restores user account state safely (Fail-closed)
         Returns: HTTP 409 Conflict
           {
             code: 'FACE_ALREADY_LINKED',
             caseReference: 'CASE-XXXXXXXX',
             message: 'Face already registered under an existing account.'
           }
         * ZERO VICTIM PII LEAKED TO CLIENT (No name, no phone, no daily rate) *
```
