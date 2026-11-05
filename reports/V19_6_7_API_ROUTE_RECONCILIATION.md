# KELASAGARA BIOMATCH V19.6.7
## API Route Reconciliation & Client/Server Contract Audit Report

**Milestone:** V19.6.7 — Evidence Integrity & Scientific Audit  
**Date:** 2026-10-24  
**Release Gate Status:** `CONTROLLED_TEST_BUILD_ONLY`  
**Production Calibration Approved:** `false`  
**Target:** Reconcile Client/Server Route Discrepancy (`POST /api/v1/face/enroll` vs `POST /api/biometrics/enroll`)  

---

### 1. Executive Summary & Defect Categorization

In earlier milestone reports (V19.6.3 and V19.6.5), the enrollment endpoint was referenced in documentation prose as `POST /api/v1/face/enroll`. In contrast, the V19.6.6 release report referenced `POST /api/biometrics/enroll`.

Following an exhaustive audit of both the Flutter client codebase and the Node.js/Express server router mounting:

```
================================================================================
                    ROOT CAUSE DETERMINATION: DOCUMENTATION DEFECT               
================================================================================
1. The discrepancy is a DOCUMENTATION-ONLY DEFECT in earlier markdown reports.
2. The actual code in Flutter (lib/services/biometric_service.dart) has always
   requested: $_backendBaseUrl/enroll -> https://api.kelasagara.com/api/biometrics/enroll
3. The actual code in Express (backend/src/server.ts) mounts faceRouter at:
   app.use("/api/biometrics", faceRouter) with faceRouter.post("/enroll", ...)
   which produces: POST /api/biometrics/enroll
4. The path /api/v1/face/enroll is NOT registered anywhere in Express and
   correctly returns 404 Not Found (verified by automated integration tests).
================================================================================
```

---

### 2. Trace of Effective Client Request Path

#### Flutter Client Source Inspection
- **Source File:** [`lib/services/biometric_service.dart`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/lib/services/biometric_service.dart)
- **Base URL Configuration (Lines 539–544):**
  ```dart
  static const String kProductionBackendUrl = 'https://api.kelasagara.com/api/biometrics';
  static const String kEmulatorBackendUrl   = 'http://10.0.2.2:5001/api/biometrics';
  static const String kLocalhostBackendUrl  = 'http://localhost:5001/api/biometrics';
  ```
- **Endpoint Appending in `enrollBiometric()` (Line 1070):**
  ```dart
  final response = await _client.post(
    '$_backendBaseUrl/enroll',
    headers: headers,
    body: jsonEncode(payload),
  );
  ```
- **Effective Client Request URL:**  
  $$\text{Effective Client URL} = \texttt{https://api.kelasagara.com/api/biometrics/enroll}$$

#### Client Authentication & Header Construction
- Header: `Authorization: Bearer <firebaseIdToken>`
- Content-Type: `application/json`
- Payload: Contains `role`, `imageBase64`, `burstFrames` (3 frames with timestamps), `challengeNonce`, `requestHash`, and `livenessAudit`.
- Invariant: Zero client embeddings or vectors are accepted or trusted.

---

### 3. Server Route Registration & Middleware Chain

#### Server Mounting Inspection
- **Server Entry Point:** [`backend/src/server.ts`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/backend/src/server.ts)
  ```typescript
  // Line 52
  app.use("/api/biometrics", faceRouter);
  ```
- **Router Declaration:** [`backend/src/routes/face_routes.ts`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/backend/src/routes/face_routes.ts)
  ```typescript
  // Line 221
  faceRouter.post(
    "/enroll",
    authenticateFirebaseToken,
    checkForbiddenVectorFields,
    async (req: AuthenticatedRequest, res: Response): Promise<void> => { ... }
  );
  ```
- **Effective Server Path:**  
  $$\text{Effective Server Route} = \texttt{POST /api/biometrics/enroll}$$

#### Complete Ingestion Middleware Chain
1. `cors(corsOptions)`: Restricts origin headers.
2. `express.json({ limit: "5mb" })`: Payload ceiling protection against memory exhaustion attacks.
3. `authenticateFirebaseToken`: Enforces valid Bearer JWT. Unauthenticated requests are rejected immediately with `401 Unauthorized` (`error: "unauthenticated"`).
4. `checkForbiddenVectorFields`: Inspects payload for forbidden client vector keys (`probeVector`, `embedding`). Client vector injections are strictly rejected with `400 Bad Request` (`code: "CLIENT_VECTORS_FORBIDDEN"`).
5. `BiometricEnrollmentService.processEnrollment`: Authoritative server-side feature extraction (OpenCV SFace 128-D), atomic challenge validation, and 1:N duplicate screening.
6. Constant-Time Latency Padding (`MIN_ENROLL_LATENCY_MS = 150`): Eliminates timing side-channel oracles.

---

### 4. Automated Contract Regression Test Evidence

An Express-mounted end-to-end integration test was established in [`backend/src/tests/v19_6_7_api_contract_reconciliation.test.ts`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/backend/src/tests/v19_6_7_api_contract_reconciliation.test.ts):

```
> node --test dist/tests/v19_6_7_api_contract_reconciliation.test.js

▶ V19.6.7 API Route Reconciliation & Express Application Mounting
  ✔ 1. Registered route POST /api/biometrics/enroll strictly enforces authentication (401 without token) (15.6ms)
  ✔ 2. Registered route POST /api/biometrics/enroll requires valid imageBase64 or burstFrames (44.9ms)
  ✔ 3. Registered route POST /api/biometrics/enroll rejects client-supplied vector payloads (Ticket T-01) (1.2ms)
  ✔ 4. Non-existent documentation-artifact route POST /api/v1/face/enroll returns 404 Not Found (1.3ms)
  ✔ 5. Registered route POST /api/biometrics/challenge issues valid challenge bound to caller UID (6982.3ms)
  ✔ 6. Reconciled Contract: Effective client path matches mounted Express path (0.1ms)
✔ V19.6.7 API Route Reconciliation & Express Application Mounting (7045.9ms)
ℹ tests 6
ℹ suites 1
ℹ pass 6
ℹ fail 0
```

---

### 5. Conclusion & Action Taken

1. **Reconciliation Verdict:** The authoritative contract is confirmed as `POST /api/biometrics/enroll`.
2. **Backdoor Prevention:** The path `/api/v1/face/enroll` does not exist on the server, cannot bypass middleware, and returns `404 Not Found`.
3. **Documentation Alignment:** All V19.6.7 reports use `POST /api/biometrics/enroll`. Prior references in historical reports are annotated as documentation-only artifacts.
