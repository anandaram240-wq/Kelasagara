# KELASAGARA V20.0 — PHASE 20.0 BASELINE INVENTORY
## Forensic Architectural Audit, Baseline Integrity & Biometric Engine Analysis

- **System:** Kelasagara Major Project (Karnataka Informal Worker Job Marketplace)
- **Evaluation Date:** 31 October 2026
- **Auditor Role:** Principal Biometric Systems Architect, Senior Flutter Engineer, Senior TypeScript Backend Engineer & Independent Application Security Auditor
- **Phase Objective:** Phase 20.0 Forensic Discovery & Baseline Characterization
- **Working Tree Baseline:** Branch `ui/polish-v1`, HEAD commit `4892bb6338209c5fa1a8f94ec8b3fc90935e8739` (`4892bb6`)
- **Release Tag:** `v19.2.3-release` pointing to parent commit `f210f959828fa6935dd431b32d20117b43b67be3` (`f210f95`)
- **Release APK:** `Kelasagara-v19.2.3-release.apk` (138,547,923 bytes)
- **Release APK SHA-256:** `739f85746df3cd1fb6c315590147907918a3829976d0381b8eae358c743176ce`

---

## 1. Baseline Integrity & Artifact Verification

### 1.1 Git Working Tree & Commit Ancestry
- **Current HEAD:** Commit `4892bb6` (`docs(v19.2.3): real-world biometric acceptance testing, demonstration protocol, and final submission freeze`).
- **Release Anchor:** Commit `f210f95` (`feat(v19.2.3): enforce standard TLS CA-chain validation with direct Anycast connectionFactory, eliminate badCertificateCallback bypass, and certify final submission release`), tagged as `v19.2.3-release`.
- **Ancestry Verification:** Commit `4892bb6` is the direct descendant of `f210f95`, which descends from `eff4407` (`v19.2.2-release`).
- **Cryptographic Binary Match:** The physical APK file `Kelasagara-v19.2.3-release.apk` located in `/Users/ananda/KELASAGARA MAJOR PROJECT/` possesses the SHA-256 hash `739f85746df3cd1fb6c315590147907918a3829976d0381b8eae358c743176ce`, matching the verified release manifest.

---

## 2. In-Depth Research: 10 Core Biometric Dimensions

### 2.1 Current Enrollment Architecture
- **Client Side (`lib/screens/auth/face_enrollment_screen.dart`, `lib/services/biometric_service.dart`):**
  - Uses Camera2 via `camera: ^0.11.0+2` and `google_mlkit_face_detection: ^0.13.0`.
  - Captures 478-point facial mesh. `FaceEnrollmentExecutor` validates ISO/IEC 19794-5 / 29794-5 quality (IPD $\ge 60$px, yaw/pitch $\le 20^\circ$, roll $\le 15^\circ$, luminance $[28, 248]$).
  - Acquires challenge via `POST /api/biometrics/v10/challenge` (`acquireV10Challenge`).
  - Calls `POST /api/biometrics/v10/enroll` transmitting `challengeId`, `nonce`, `idempotencyKey`, `imageBase64`, and `probeVector`.
- **Backend Side (`backend/src/routes/biometric_v10_routes.ts`, `backend/src/services/biometric_lifecycle_coordinator_v10.ts`):**
  - Rejects client-supplied raw embedding vectors via `CLIENT_VECTOR_REJECTED` if submitted in untrusted payload fields (`embedding` or `vector`).
  - Executes authoritative feature extraction via `CanonicalSFaceEngineV10.extractCanonicalEmbeddingFromAligned112(imageBuffer)` using ONNX Runtime with `models/face_recognition_sface_2021dec.onnx`.
  - Enforces `BiometricLifecycleCoordinatorV10.enrollInitial`: verifies `users/{uid}` exists and is not suspended; sets `biometric_operations/{opId}` lease; executes 1:N deduplication; writes `biometric_vault/{enrollmentId}` and updates `users/{uid}` atomically.

### 2.2 Existing 1:N Duplicate Search
- **Class / Index:** `FirestoreCompatibleGalleryIndex` (`backend/src/services/firestore_compatible_gallery_index.ts`) and `InMemoryBiometricIndex` (`backend/src/services/in_memory_biometric_index.ts`).
- **Algorithm:** In-memory linear scan over normalized 128-D vectors ($u \cdot v \equiv \cos(\theta)$).
- **Multi-Metric Space Separation:**
  - `SFACE_NEURAL_SPACE`: Evaluated when gallery record has `canonicalEmbedding` or `sfaceEmbedding128`. Clean floor: $0.363$, duplicate threshold: $0.78$.
  - `LEGACY_LANDMARK_SPACE`: Evaluated when gallery record has legacy 128-D landmark vector. Clean floor: $0.80$, duplicate threshold: $0.88$.
  - Rejection of `Math.max()`: Prevents comparing scores across disparate metric spaces.
- **Top-K Ranking:** Filters candidates with `excludeOwningUid` and `excludeEnrollmentId`, sorting by descending cosine similarity.

### 2.3 Existing 1:1 Face Authentication
- **Endpoint:** `POST /api/biometrics/v10/verify-1to1`.
- **Coordinator Logic:** `BiometricLifecycleCoordinatorV10.verifyExistingAccount1to1`.
- **Decoupled Architecture:** Queries `users/{uid}.activeBiometricEnrollmentId` and reads ONLY the authenticated caller's own record in `biometric_vault/{enrollmentId}`.
- **Verification Criteria:**
  - Evaluates similarity against the user's enrolled template.
  - SFace threshold $\ge 0.78$ (or legacy landmark threshold $\ge 0.88$).
  - Returns HTTP 200 with code `AUTHENTICATED` on success; HTTP 401 with code `BIOMETRIC_MISMATCH` on failure.
  - Zero cross-user false rejects during daily sign-in since 1:N gallery is bypassed.

### 2.4 Existing PAD & Blink Challenges
- **Client Passive/Active PAD:**
  - `FaceEnrollmentExecutor.evaluateIso29794Quality`: Evaluates Laplacian blur variance, bilateral illumination symmetry, and mouth aspect ratio (MAR).
  - Dynamic Blink State Machine (`lib/widgets/biometric_v11_liveness_scanner.dart`): Tracks Eye Aspect Ratio (EAR) across 12 eyelid landmarks. Requires transition from open ($EAR \ge 0.30$) to closed apex ($EAR \le 0.18$) within $1.2$s, then reopening.
  - Photometric screen fill (`CaptureIlluminationService`): Screen brightness stepped up to 100% white fill for ambient compensation.
- **Backend PAD Audit:**
  - `backend/src/services/mediapipe_face_landmarker_onnx.ts`: Validates 478-point landmark topologies and 12-point eyelid EAR transitions on server-side burst frames.
  - `backend/src/biometrics/pad_liveness_fiqa_guard_v11.ts`: Quality and Presentation Attack Detection guard.

### 2.5 Existing Nonce & Cryptographic Verification
- **Challenge Nonce:** Generated as 16 cryptographic random bytes (`randomBytes(16).toString('base64url')`), saved in `biometric_challenges/{challengeId}` with `expiresAtMs` (5-minute TTL) and `purpose`.
- **Atomic Single-Use Consumption:** `consumeChallenge` helper runs a Firestore transaction checking `consumed === false`, `uid === callerUid`, `now <= expiresAtMs`, and marks `consumed: true`.
- **Operation Receipts:** `BiometricOperationReceiptService` (`backend/src/biometrics/identity_contract_v10.ts`) issues HMAC-SHA256 tokens binding `uid`, `operationId`, `enrollmentId`, `enrollmentVersion`, and `oneTimeRedemptionNonce`.
- **Receipt Redemption:** Handled by `POST /api/biometrics/v10/redeem-receipt`, checking `biometric_receipt_redemptions/{nonce}` atomically.

### 2.6 Existing Biometric Template Encryption
- **Encryption Libraries:** Node.js `crypto` with `aes-256-gcm`.
- **Envelope Encryption Module:** `backend/src/biometrics/encrypted_hnsw_vault_v11.ts` and `backend/src/biometrics/cloud_kms_fail_closed_guard_v18.ts`.
- **AAD Context Binding:** Canonical length-prefixed Additional Authenticated Data (`v3_kms_gcm`) binds tenant and user UID context.
- **Current Storage State in V10 Coordinator:** `BiometricLifecycleCoordinatorV10` writes `canonicalEmbedding: Array.from(unitProbe)` directly as a Firestore float array in `biometric_vault/{newEnrollmentId}`. The data is access-controlled by Firestore security rules (`allow read, write: if false;`), but remains unencrypted at the document field level in V10.

### 2.7 Existing Recovery & Account Linking
- **Duplicate Interception Flow:** On HTTP 409 `FACE_ALREADY_LINKED`, client displays `DuplicateAccountResolutionSheet` (`lib/widgets/duplicate_account_resolution_sheet.dart`).
- **Privacy Enforcement (DPDP Act 2023 §8(3)):** Caller receives opaque `caseReference` (`CASE-XXXX`). The victim's phone number, name, and UID are withheld.
- **Authorized Replacement:** `POST /api/biometrics/v10/replace` requires a cryptographically verified single-use `stepUpProofToken` stored in `step_up_proofs/{token}`.
- **Role Linking:** `backend/src/routes/identity_routes.ts` permits linking secondary roles (HIRER/WORKER) via verified phone OTP or fresh sign-in proofs.

### 2.8 Existing Concurrency Controls
- **Epoch Fencing:** Collection `biometric_system_meta/gallery_epoch_v10` tracks integer `epochVersion`.
- **Search-to-Commit Optimistic Concurrency:** Search records `searchedGalleryEpoch`. Commit transaction verifies `currentEpoch === searchedGalleryEpoch`. If changed, commit aborts and retries up to 3 times (`MAX_CONCURRENT_EPOCH_RETRIES`).
- **Operation Leases:** `biometric_operations/{opId}` records `state: IN_PROGRESS` and `leaseExpiresAtMs: nowMs + 25000`. Stale leases (> 25s) can be reclaimed.

### 2.9 Existing Device Trust & Integrity Checks
- **Client Security Check:** `BiometricService.instance.checkDeviceSecurity()` detects root, jailbreak, and emulators.
- **Play Integrity Request Hash:** `FaceEnrollmentExecutor.computePlayIntegrityRequestHash` binds `serverNonce`, `uid`, and `captureDigestHex` via SHA-256.
- **Request Headers:** Transmits `X-Device-Integrity-Token` and client session IDs.

### 2.10 Existing Model Version & Threshold Management
- **Primary ONNX Model:** `models/face_recognition_sface_2021dec.onnx` (OpenCV Zoo Apache-2.0, MobileFaceNet backbone, 128-D output).
- **Model Version Identifiers:**
  - Backend: `sface_opencv_zoo_v1_primary` (preprocess: `aligned_112x112_rgb_norm_minus127.5_div128`).
  - Client Pure-Dart Fallback: `kelasagara_biomatch_v3_whitened`.
- **Calibrated Thresholds (`DEFAULT_CANDIDATE_THRESHOLDS_V10`):**
  - SFace clean floor: $0.363$
  - SFace duplicate ceiling: $0.780$
  - Legacy landmark clean floor: $0.800$
  - Legacy landmark duplicate ceiling: $0.880$

---

## 3. Systematic Architectural Classification

### 3.1 Verified Implementation
1. **Server-Side Authoritative SFace Inference:** ONNX Runtime session pool executes `face_recognition_sface_2021dec.onnx`, extracting 128-D unit hypersphere vectors.
2. **Multi-Space Deduplication Separation:** `SFACE_NEURAL_SPACE` and `LEGACY_LANDMARK_SPACE` match candidates using distinct thresholds and never mix similarity values.
3. **Decoupled 1:1 Authentication:** 1:1 eKYC queries solely the caller's enrolled template in `biometric_vault`.
4. **Single-Use Challenge-Response:** Nonces are stored with 5-minute TTL and atomically consumed via Firestore transactions.
5. **Anti-Enumeration Privacy:** Duplicate interception returns opaque `caseReference` (`CASE-XXXX`) without disclosing victim credentials.
6. **Epoch-Fenced CAS Concurrency:** Search-to-commit atomic transactions prevent race conditions during concurrent enrollments.
7. **Firestore Rules Lockdown:** `biometric_vault`, `biometric_challenges`, `step_up_proofs`, and `person_identities` enforce `allow read, write: if false;`.
8. **Direct Anycast IP Networking:** Dart `HttpClient.connectionFactory` routes TCP traffic directly to `104.16.230.132:443`, bypassing carrier DNS poisoning while verifying system TLS CA certificates.

### 3.2 Partially Implemented Functionality
1. **Client-Side ONNX Inference:** `lib/biometrics/sface_inference.dart` has scaffolding for on-device SFace ONNX inference, but currently returns null and falls back to pure-Dart landmark embeddings or server-side ArcFace/SFace.
2. **KMS Envelope Encryption Integration:** `encrypted_hnsw_vault_v11.ts` and `cloud_kms_fail_closed_guard_v18.ts` implement full AES-256-GCM envelope encryption, but the primary V10 coordinator (`biometric_lifecycle_coordinator_v10.ts`) stores unencrypted float arrays in Firestore `biometric_vault`.
3. **Device Play Integrity Attestation:** Client computes `computePlayIntegrityRequestHash`, but backend `biometric_v10_routes.ts` does not call Google Play Integrity API to verify the cryptographic attestation token.

### 3.3 Missing Functionality
1. **Automated Continuous Re-Indexing:** HNSW vector index (`hnsw_biometric_matcher_v3.ts`) is implemented in standalone modules, but V10 coordinator relies on in-memory array scanning.
2. **Hardware KeyStore Backing for Client Nonces:** Challenge nonces are held in memory rather than hardware Android Keystore (StrongBox / TEE).
3. **Automated Demographic Drift Alerting in V10:** `fairness_drift_monitor_v12.ts` exists in V12, but is not hooked into V10 operational metrics.

### 3.4 Security Weaknesses & Technical Debt
1. **Dual Route Trees:** Multiple biometric router trees exist in `server.ts` (`/api/biometrics`, `/api/biometrics/v10`, `/api/v10/biometrics`, `/api/v11/biometrics`, `/api/v12/biometrics`, `/api/v18/biometrics`). This creates maintenance overhead and potential configuration divergence.
2. **Unencrypted Firestore Embeddings in V10:** While Firestore rules prevent client access, storing raw float embeddings in Firestore documents without envelope encryption increases risk in case of backend service account credential leakage.
3. **Mock/Static Fallbacks in Client Native Bridge:** `biomatch_ffi_bridge.dart` falls back to `_dartFallbackOutput` when native C++ `.so` is not found.

### 3.5 Untested Assumptions
1. **Large-Scale Gallery Performance ($N > 100,000$):** In-memory array linear scan scales at $\mathcal{O}(N)$. Verified up to 5,000 synthetic templates; production scaling to 100,000+ requires HNSW indexing.
2. **Extreme Facial Aging Drift:** SFace embedding stability across $\ge 5$ years without re-enrollment has not been empirically quantified on Indian rural demographic cohorts.
