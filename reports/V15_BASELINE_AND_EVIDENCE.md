# KELASAGARA V15.0 BIOMETRIC ENGINE AUDIT
# REPORT 01: BASELINE INVENTORY & EVIDENCE MATRIX

**Document ID:** KLS-V15-AUDIT-001  
**Classification:** CONTROLLED TEST BUILD AUDIT (NO LIVE RELEASE)  
**Target Repository:** `/Users/ananda/KELASAGARA MAJOR PROJECT/kelasagaara_v17`  
**Git Branch:** `ui/polish-v1`  
**Base Commit Verified:** `e59cda4` (`feat(biometrics): KELASAGARA V15.0 threshold governance, regression proof and release-blocker remediation`)  
**Audit Date:** 2026-10-23  
**Auditor:** Principal Biometric Systems Architect & Application Security Engineer  

---

## 1. EXECUTIVE SUMMARY & FORENSIC CONTEXT

The Kelasagara worker marketplace operates a biometric facial verification and deduplication subsystem designed to prevent identity fraud, credential sharing, and Sybil registrations across gig worker accounts. Historical documentation (V10.0–V14.0) contained both critical architectural breakthroughs and unsubstantiated claims regarding production readiness, cryptographic guarantees, and empirical accuracy.

The V15.0 Master Engineering Audit was executed to establish an incontrovertible, evidence-based baseline. Every claim regarding security, recognition accuracy, liveness detection, and data persistence was classified according to five strict evidentiary states:
- **VERIFIED:** Confirmed via direct source code inspection, reproducible automated tests, and configuration proof.
- **REPRODUCED:** Defect or behavior demonstrated and verified via targeted regression test suites.
- **FAILED:** An assertion proven mathematically, logically, or empirically false.
- **NOT TESTED:** Implementation exists in software but has not been subjected to empirical field evaluation or physical stress.
- **BLOCKED:** Live cloud integration or deployment requiring external credentials or operational authorization intentionally withheld.

---

## 2. ENVIRONMENT & TOOLCHAIN VERIFICATION

All tests, compilation steps, and inspections documented in this audit were executed within the verified local build environment:

| Component | Verified Version | Environment Details | Verification Status |
| :--- | :--- | :--- | :--- |
| **Node.js** | `v24.14.0` | Darwin arm64 (macOS) | VERIFIED |
| **npm** | `11.9.0` | Node package manager | VERIFIED |
| **TypeScript** | `5.9.3` | `backend/tsconfig.json` target ES2022 | VERIFIED (0 compile errors) |
| **Dart SDK** | `3.13.1` | Google Dart SDK | VERIFIED |
| **Flutter SDK** | `3.47.1` | Channel stable, engine `d6b998` | VERIFIED (0 compile errors) |
| **ONNX Runtime Node** | `1.24.4` | `onnxruntime-node` backend inference | VERIFIED |
| **Firebase Admin** | `^13.0.0` | Node.js Server SDK | VERIFIED |
| **Firebase Auth** | `firebase_auth: ^5.0.0` | Client Flutter SDK | VERIFIED |
| **Cloud Firestore** | `cloud_firestore: ^5.0.0` | Client Flutter SDK | VERIFIED |

---

## 3. MODEL ASSETS & CRYPTOGRAPHIC CHECKSUMS

The backend face recognition pipeline relies on pre-trained ONNX models stored in `backend/assets/models/`. Their SHA-256 cryptographic checksums were independently computed via `shasum -a 256` and matched against the official OpenCV Zoo release specifications and the backend `ModelRegistry`:

```
================================================================================
MODEL CHECKSUM VERIFICATION TABLE
================================================================================
File: face_recognition_sface_2021dec.onnx (SFace FP32, OpenCV Zoo)
Path: backend/assets/models/face_recognition_sface_2021dec.onnx
Expected SHA-256: 0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79
Actual SHA-256:   0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79
Status: MATCH VERIFIED (Apache 2.0 License, 128-D L2-normalized hypersphere output)

File: face_recognition_sface_2021dec_int8.onnx (SFace INT8 Quantized)
Path: backend/assets/models/face_recognition_sface_2021dec_int8.onnx
Expected SHA-256: 2b0e941e6f16cc048c20aee0c8e31f569118f65d702914540f7bfdc14048d78a
Actual SHA-256:   2b0e941e6f16cc048c20aee0c8e31f569118f65d702914540f7bfdc14048d78a
Status: MATCH VERIFIED (Apache 2.0 License, INT8 quantized for low latency)

File: face_detection_yunet_2023mar.onnx (YuNet Face Detector)
Path: backend/assets/models/face_detection_yunet_2023mar.onnx
Expected SHA-256: 8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4
Actual SHA-256:   8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4
Status: MATCH VERIFIED (Apache 2.0 License, 5-point landmark + bounding box)

File: kelasagara_mobilefacenet.onnx (Legacy Model - Deprecated)
Path: backend/assets/models/kelasagara_mobilefacenet.onnx
Expected SHA-256: cde3799f041eca6a6a99bfac53d9e97eb81ff34ac450d519aa41a9c99bef7d7c
Actual SHA-256:   cde3799f041eca6a6a99bfac53d9e97eb81ff34ac450d519aa41a9c99bef7d7c
Status: MATCH VERIFIED (Preserved for compatibility/migration unit tests)
================================================================================
```

---

## 4. BACKEND ENDPOINT CONTRACT & ROUTE INVENTORY

Inspection of `backend/src/routes/face_routes.ts` confirmed the following endpoint inventory:

| Method | Endpoint Path | Authentication | Request Payload | Core Functionality | Audit Status |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `POST` | `/api/biometrics/enroll-biometric` | Firebase Bearer Token | `{ imageBase64: string, playIntegrityToken?: string }` | Validates image, runs SFace inference, checks 1:N deduplication, encrypts DEK, writes to `biometric_vault`. | VERIFIED |
| `POST` | `/api/biometrics/verify-1to1` | Firebase Bearer Token | `{ imageBase64: string }` | Compares probe against caller's enrolled template using `config.verificationThreshold` (`0.363`). | VERIFIED |
| `POST` | `/api/biometrics/cross-account-check` | Firebase Bearer Token | `{ imageBase64: string }` | Compares probe against all other enrolled templates. Blocks at $\ge 0.90$, flags at $\ge 0.74$. | VERIFIED |
| `POST` | `/api/biometrics/reverify-shift` | Firebase Bearer Token | `{ imageBase64: string, shiftId: string }` | 1:1 on-shift re-verification via `AccountLifecycleService`. Threshold corrected to `0.363`. | VERIFIED |
| `GET` | `/api/biometrics/db-readiness` | Firebase Bearer Token | None | Probes Firestore latency, vault count, in-memory index size, and model version. | VERIFIED |
| `GET` | `/health` | Public | None | Returns server health, active model, and biometric release status (`CONTROLLED_TEST_BUILD`). | VERIFIED |

---

## 5. COMPREHENSIVE CLAIM VS. EVIDENCE MATRIX

| Claim / Subsystem | Historical Assertion (V10–V14) | V15.0 Forensic Audit Finding | Evidentiary Status | Supporting Evidence Reference |
| :--- | :--- | :--- | :--- | :--- |
| **Firestore Vault Client Access** | "Vault is secured in Firestore rules." | `firestore.rules` explicitly specifies `match /biometric_vault/{doc} { allow read, write: if false; }`. Direct client reads/writes are blocked. | **VERIFIED** | `firestore.rules` line 142; unit test suite `firestore_rules_security.test.ts`. |
| **Client Gallery Download** | "Flutter app no longer downloads all templates." | `biometric_service.dart` had all client-side gallery synchronization removed in V13. All 1:N probes query backend endpoints. | **VERIFIED** | Code inspection of `lib/services/biometric_service.dart`. |
| **Client Vector Rejection** | "Backend rejects client embeddings." | Endpoints `/enroll-biometric`, `/verify-1to1`, and `/cross-account-check` accept only `imageBase64`. Ingestion schema rejects raw vector arrays. | **VERIFIED** | `backend/src/routes/face_routes.ts` lines 45, 120, 280. |
| **1:1 Verification Threshold** | "Fixed in V14 to 0.363." | `/verify-1to1` uses `config.verificationThreshold` (`0.363`), but `AccountLifecycleService.reVerifyWorker` still used `duplicateThreshold` (`0.74`). Fixed in V15. | **REPRODUCED & FIXED** | `backend/src/services/account_lifecycle.ts` line 142; `threshold_governance.test.ts`. |
| **Threshold Range Validation** | "Thresholds configured via env vars." | System lacked strict monotonic validation and NaN/Infinity sanitization. `config.ts` remediated with `validateThresholdGovernance()`. | **REPRODUCED & FIXED** | `backend/src/config.ts`; `threshold_governance.test.ts` (20/20 passing). |
| **Gallery Multi-Instance Consistency** | "In-memory index scales with Cloud Run." | `InMemoryBiometricIndex` is a single-process JavaScript Map. Multiple Cloud Run instances will experience drift and race conditions. | **FAILED** (Architecture Limitation) | Documented in `reports/V15_GALLERY_CONSISTENCY.md`. |
| **Cloud KMS Integration** | "KMS envelope encryption is active." | `CloudKmsKeyProvider` throws `KMS_UNAVAILABLE_ERROR (UNVERIFIED-LIVE)` without GCP credentials. Tests run against `LocalDevKeyProvider`. | **BLOCKED (UNVERIFIED LIVE)** | `backend/src/services/kms_key_provider.ts`; `V15_CLOUD_KMS_VERIFICATION.md`. |
| **Biometric Accuracy Claim** | "System achieves 99.60% accuracy." | 99.60% is an academic score on LFW dataset from the OpenCV paper. No empirical evaluation has been performed on target demographic. | **NOT TESTED (UNVERIFIED FIELD)** | Evaluated in `reports/V15_BIOMETRIC_EVALUATION_RESULTS.md`. |
| **Presentation Attack Detection** | "ISO 30107-3 PAD certified." | Client executes ML Kit blink detection, but sends a single static JPEG to the backend. Physical spoof attacks remain completely unmitigated. | **NOT TESTED (UNVERIFIED PHYSICAL)** | Architectural analysis in `reports/V15_PAD_ARCHITECTURE_AND_EVIDENCE.md`. |
| **Release Authorization** | "Ready for production canary." | Unvalidated thresholds, physical PAD gaps, unverified live KMS, and RAM gallery drift strictly prohibit live deployment. | **CONTROLLED TEST BUILD ONLY** | Release scorecard in `reports/V15_RELEASE_GATE_MATRIX.md`. |

---

## 6. AUDIT CONCLUSION & NEXT STEPS

The baseline investigation establishes that while software-level comparator fixes, schema validation, and API contracts have reached high technical maturity, the system cannot be deployed to production identity gating. The repository is officially designated as a **CONTROLLED TEST BUILD ONLY**. Detailed technical remediations and evaluation plans follow in Reports 02 through 13.
