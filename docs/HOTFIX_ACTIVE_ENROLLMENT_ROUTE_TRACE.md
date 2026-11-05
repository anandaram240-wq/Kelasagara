# KELASAGARA ACTIVE ENROLLMENT ROUTE TRACE
## ARCHITECTURAL AUDIT OF CLIENT-SERVER ENDPOINTS & ROUTING

**Phase:** Biometric Enrollment Hotfix  
**Branch:** `security/hotfix-canonical-face-preprocessing`  
**Classification:** P0 Route Lineage & Controller Governance  
**Date:** November 1, 2026  
**Auditors:** Senior TypeScript Backend Engineer, Flutter Systems Engineer

---

## 1. OBJECTIVE

Prove conclusively from source code inspection and runtime execution which endpoint is the authoritative production enrollment route invoked by the Flutter application, and trace the relationship between all biometric route controllers in `kelasagaara_v17`.

---

## 2. PRODUCTION CALL TRACE: FLUTTER TO BACKEND

### Step 1: Flutter Client Trigger
- **Source File:** `lib/screens/auth/face_enrollment_screen.dart:885`
- **Method:** `FaceEnrollmentScreenState._captureAndSave()`
- **Capture Execution:**
  ```dart
  final XFile rawFile = await _camCtrl!.takePicture();
  final Uint8List rawBytes = await rawFile.readAsBytes();
  final String imageBase64 = base64Encode(rawBytes);
  ```
- **Service Delegation:**
  ```dart
  final bioResult = await BiometricService.instance.enrollBiometric(
    role: isHirer ? 'hirer' : 'worker',
    isReEnrollment: widget.isReEnrollment,
    imageBase64: imageBase64,
    ...
  );
  ```

### Step 2: BiometricService Transport
- **Source File:** `lib/services/biometric_service.dart:1415`
- **Method:** `BiometricService.enrollBiometric()`
- **Network Request:**
  ```dart
  final response = await _dio.post(
    '$_backendBaseUrl/enroll',
    data: {
      'challengeId': activeTicket.challengeId,
      'nonce': challengeNonce,
      'idempotencyKey': idempotencyKey,
      'imageBase64': imageBase64,
      'isReEnrollment': isReEnrollment,
    },
    ...
  );
  ```
- **URL Base:**
  In `lib/services/biometric_service.dart:58`:
  `_backendBaseUrl = 'https://api.kelasagara.com/api/biometrics/v10'` (or `http://localhost:5001/.../api/biometrics/v10`).
  Therefore, the actual HTTP URL is:
  $$\mathbf{POST\quad /api/biometrics/v10/enroll}$$

### Step 3: Express Server Routing
- **Source File:** `backend/src/server.ts:104-112`
- **Mount Configuration:**
  ```typescript
  app.use(
    "/api/biometrics/v10",
    createBiometricV10Router({
      db,
      coordinator: coordinatorV10,
      engine: canonicalEngineV10,
      receiptService: receiptServiceV10,
    })
  );
  ```
- **Controller File:** `backend/src/routes/biometric_v10_routes.ts:340`
  - Defines `router.post('/enroll', ...)`
  - Authenticates Firebase Token (`authenticateFirebaseToken`)
  - Validates Play Integrity (`requirePlayIntegrity`)
  - Validates Device Signature (`requireDeviceSignature`)
  - Consumes single-use cryptographic challenge (`consumeChallenge`)
  - Performs authoritative server-side facial feature extraction:
    ```typescript
    const { embedding: validatedSFaceEmbedding128 } =
      await deps.engine.extractCanonicalEmbeddingFromOriginalImage(imageBuffer);
    ```
  - Invokes `deps.coordinator.enrollInitial(...)`.

---

## 3. COMPARISON OF BIOMETRIC CONTROLLERS IN REPOSITORY

| Controller File | Mount Path | Purpose | Status |
|---|---|---|---|
| `backend/src/routes/biometric_v10_routes.ts` | `/api/biometrics/v10` | **Active Production Controller** for all mobile app enrollments, 1:1 verifications, and authorized replacements. Uses `BiometricLifecycleCoordinatorV10`. | **PRIMARY PRODUCTION** |
| `backend/src/routes/face_v10_pilot_routes.ts` | `/api/v10/biometrics` | **Phase 9 Research Pilot Controller** used for offline evaluation and synthetic benchmarking. In-memory pilot gallery. | **RESEARCH / PILOT** |
| `backend/src/routes/face_routes.ts` | `/api/biometrics` | **Legacy V18/V19 Controller** with `/cross-account-check` and legacy `/enroll`. Maintained for backward compatibility. | **LEGACY COMPATIBILITY** |
| `backend/src/routes/face_v18_routes.ts` | `/api/biometrics/v18` | **Phase 13/14 KS18 Pipeline Controller** for zero-copy WAL and snapshot tests. | **TEST / INTEGRATION** |

---

## 4. INVARIANTS ENFORCED ON THE ACTIVE ROUTE

1. **Zero Client Vector Trust (Invariant I-03):** Client-submitted vectors (`embedding`, `vector`) are strictly rejected with HTTP 400 `CLIENT_VECTOR_REJECTED`. The server is 100% authoritative for feature extraction.
2. **Canonical Preprocessing Mandatory:** Raw image rasters MUST pass through `extractCanonicalEmbeddingFromOriginalImage` which enforces YuNet detection and Umeyama alignment before SFace inference.
3. **Hardware-Bound Cryptographic Signatures:** Mobile requests must present valid device-bound ECDSA signatures and Play Integrity tokens.
4. **Challenge Single-Use:** Challenge nonces are marked consumed atomically before biometric inference begins.
5. **Zero PII Disclosure on Duplicate Rejection:** When `BiometricLifecycleCoordinatorV10` returns `FACE_ALREADY_LINKED` (409) or `AMBIGUOUS_MATCH` (202), only an opaque `caseReference` (`CASE-XXXXXXXX`) is returned. No personal data is leaked.
