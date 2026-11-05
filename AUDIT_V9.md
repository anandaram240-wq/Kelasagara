# AUDIT_V9: Verification of BioMatch Snapshot & Defect Register
**Execution Date:** 2026-10-10  
**Repository:** `kelasagaara_v17`  
**Branch:** `biomatch/v7-hardening`  
**Host Workstation:** Apple M4 macOS  
**Inspector:** Staff ML Systems & Security Engineer (Antigravity)

---

## 1. FILE & COMPONENT VERIFICATION SNAPSHOT

| Component / File | Expected Path | Status | Verification Detail / Command Evidence |
| :--- | :--- | :--- | :--- |
| **Primary Model** | `backend/models/face_recognition_sface_2021dec.onnx` | **VERIFIED** | SHA-256: `0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79` (36.9 MB) |
| **Fallback Model** | `backend/models/face_recognition_sface_2021dec_int8.onnx` | **VERIFIED** | SHA-256: `2b0e941e6f16cc048c20aee0c8e31f569118f65d702914540f7bfdc14048d78a` (9.4 MB) |
| **Detector Model** | `backend/models/face_detection_yunet_2023mar.onnx` | **VERIFIED** | SHA-256: `8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4` (227 KB) |
| **Legacy Model** | `backend/models/kelasagara_mobilefacenet.onnx` | **VERIFIED** | SHA-256: `cde3799f041eca6a6a99bfac53d9e97eb81ff34ac450d519aa41a9c99bef7d7c` (1.17 MB) |
| **Model Registry** | `backend/src/services/model_registry.ts` | **VERIFIED** | File exists, pins SHA-256 hashes, defines tiers `PRODUCTION_CLEARED` and `RESEARCH_ONLY`. |
| **Redundancy Service**| `backend/src/services/inference_redundancy_service.ts` | **VERIFIED** | Implements parallel FP32/INT8 forward passes, failover catch block, dual template return. |
| **Face Inference** | `backend/src/services/face_inference.ts` | **VERIFIED** | Wraps ONNX Runtime Node session, verifies SHA-256 integrity (I-18), dynamic I/O tensor resolution. |
| **Challenge Nonce** | `backend/src/services/session_challenge_service.ts` | **VERIFIED** | 60s TTL nonce store, atomic single-use consumption, action & UID binding. |
| **Repository** | `backend/src/services/firestore_biometric_repository.ts` | **VERIFIED** | Dual-template writes to `biometric_vault`, rate limits, concurrency reservations. |
| **Audit Service** | `backend/src/services/audit_service.ts` | **VERIFIED** | Append-only event logging, SHA-256 hash chaining. |
| **Server** | `backend/src/server.ts` | **VERIFIED** | Express app, strict security headers, CORS origin isolation, 5 MB payload limit. |
| **Client UI** | `lib/screens/auth/face_enrollment_screen.dart` | **VERIFIED** | ML Kit eye-blink state machine, camera still capture, base64 forwarding. |
| **Client Proxy** | `lib/services/biometric_service.dart` | **VERIFIED** | Thin client proxy via Dio, nonces, challenge handshake, 1:1 and 1:N endpoints. |
| **Legacy Exporter** | `ml/export_mobilefacenet_onnx.py` | **VERIFIED** | PyTorch random weights export script; confirms random uninitialized weights in old model. |

---

## 2. TEST SUITE EXECUTION COUNTS

### 2.1 Backend Node.js Test Suites (`node --test dist/tests/*.test.js`)
All 11 suites executed and passed cleanly:
1. `dist/tests/api_routes_integration.test.js`: **1/1 passed** (Full route dispatch)
2. `dist/tests/biometric_backend.test.js`: **6/6 assertions passed** (L2 norm, cosine similarity, metric distance, phone masking, threshold classification, forward pass)
3. `dist/tests/chaos_fault_injection.test.js`: **1/1 suite passed** (Corrupted payload, session drop, database timeout, bad dimensions)
4. `dist/tests/concurrency_vault_store.test.js`: **4/4 passed** (Flat vector scan, pending race intercept, single ACTIVE status, stale session reclamation)
5. `dist/tests/data_architecture_state_machine.test.js`: **1/1 suite passed** (Atomic state transitions INITIAL -> PENDING_FACE -> ACTIVE)
6. `dist/tests/dpdpa_privacy_compliance.test.js`: **1/1 suite passed** (Right to erasure, crypto-shredding, unconsented storage denial)
7. `dist/tests/golden_vector_parity.test.js`: **4/4 passed** (Preprocessing ID, quality gating, numerical vector bounds, repeatability)
8. `dist/tests/inference_redundancy.test.js`: **7/7 passed** (FP32 inference, INT8 inference, dual redundancy, crash failover, dual templates, fail-closed safety, template alignment)
9. `dist/tests/research_model_governance.test.js`: **5/5 passed** (Metadata tagging, golden checksums, approval assertions, RRL-0 policy, technical failure fail-closed)
10. `dist/tests/security_hardening.test.js`: **5/5 passed** (Security headers, CORS whitelist, unauthenticated 401 fail-closed, payload cap, rate limiter)
11. `dist/tests/test_liveness_injection_bypass.test.js`: **5/5 passed** (Challenge generation, replay block, identity theft block, cross-action block, tampered nonce block)

### 2.2 Flutter Client Test Suites (`flutter test`)
37 tests executed across 2 test suites; all 37 passed:
- `test/biometric_deduplication_engine_test.dart` (21 tests)
- `test/client_biometric_integration_test.dart` (16 tests)

---

## 3. CODE PATHS SETTING `accountStatus`

A complete static audit of code paths altering `users/{uid}.accountStatus`:
1. `backend/src/services/firestore_biometric_repository.ts` (lines 258-270):
   ```typescript
   const targetStatus = isResearchOnly ? "pending_review" : role === "hirer" ? "approved" : "pending_review";
   batch.update(userRef, { accountStatus: targetStatus });
   ```
   *Defect D2 Confirmed:* `targetStatus` grants `"approved"` to `hirer` role if `isResearchOnly` is false.
2. `backend/src/services/biometric_enrollment.ts` (lines 131-136):
   ```typescript
   const finalStatus = isResearchOnly ? "pending_review" : requiresReview ? "ambiguity" : "approved";
   ```
   *Defect D2 Confirmed:* Sets `finalStatus = "approved"` when unique enrollment occurs under `PRODUCTION_CLEARED` model.
3. `lib/providers/auth_provider.dart`:
   - Line 119: Sets `pending_profile` on initial phone OTP registration.
   - Line 277: Sets `pending_face` when profile data (name, role, skills) is saved.
   - Line 406: Sets `pending_review` upon document submission or biometric pending status.
   - Line 439: Admin manual approval sets `approved`.
4. `lib/screens/admin/admin_dashboard.dart`:
   - Line 144: Administrative human reviewer manually approves profile (`accountStatus = 'approved'`).
   - Line 176: Administrative human reviewer manually rejects profile (`accountStatus = 'rejected'`).

---

## 4. REQUEST FIELDS ACCEPTED BY ENROLL & VERIFY HANDLERS

### 4.1 `/api/biometrics/enroll` (in `face_schemas.ts` and `face_routes.ts`)
Accepted fields in `EnrollRequestDTO`:
- `imageBase64?: string` (Base64 JPEG/PNG face image)
- `embedding?: number[]` (**DEFECT D1:** Accepts client probe vector)
- `role: "worker" | "hirer"`
- `challengeNonce?: string`
- `clientSessionId?: string`
- `livenessAudit?: object`

### 4.2 `/api/biometrics/verify-1to1` (in `face_schemas.ts` and `face_routes.ts`)
Accepted fields in `VerifyLoginRequestDTO`:
- `imageBase64?: string`
- `embedding?: number[]` (**DEFECT D1:** Accepts client probe vector)
- `role: "worker" | "hirer"`
- `challengeNonce?: string`

---

## 5. CONFIRMATION OF 8 AUDIT DEFECTS (D1–D8)

| Defect ID | Finding Description | Status | Evidence in Code |
| :--- | :--- | :--- | :--- |
| **D1** | Client-supplied embedding vectors accepted | **CONFIRMED** | `face_schemas.ts:26,58`, `face_routes.ts:257`, `biometric_enrollment.ts:66`. |
| **D2** | Model promoted to `PRODUCTION_CLEARED` with auto-approval below 0.65 | **CONFIRMED** | `model_registry.ts:25`, `biometric_enrollment.ts:135`, `firestore_biometric_repository.ts:261`. |
| **D3** | Thresholds 0.74 and 0.65 are uncalibrated placeholders | **CONFIRMED** | `config.ts:23-24` hardcodes 0.74 and 0.65. |
| **D4** | Server alignment missing / unverified; FP32 vs INT8 cosine 0.56 unexplained | **CONFIRMED** | `face_preprocessing.ts` does simple resize; no Umeyama affine warp implemented. |
| **D5** | Model training-data provenance undocumented | **CONFIRMED** | SFace weights in OpenCV Zoo lack explicit training dataset mapping in open issues. |
| **D6** | Liveness and injection gates overclaimed | **CONFIRMED** | EAR blink is computed entirely client-side on device; challenge nonce is replay protection only. |
| **D7** | Deployment claims unsupported | **CONFIRMED** | Backend running locally; Firestore and Firebase Auth use Google Cloud as external data processor. |
| **D8** | Invariant ID redefinitions and conflicting test counts | **CONFIRMED** | Test output shows 5 tests in some suites where 11 were claimed in prose summaries. |

**Verdict:** 0 facts contradicted. All files and defect locations precisely verified. Snapshot audit complete. Ready to proceed to Ticket T-01.
