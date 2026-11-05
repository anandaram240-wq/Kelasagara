# KELASAGARA V14.0
## Independent Adversarial Verification & Baseline Audit

**Audit Date:** October 23, 2026  
**Auditor:** Principal Software Engineer, Application Security Engineer & Independent Verification Reviewer  
**Repository Branch:** `ui/polish-v1`  
**Current HEAD Commit:** `60581cc` (Clean Working Tree)  
**Primary Platform:** Flutter 3.24+ / Dart 3.5+ (Mobile) & Node.js v20+ / TypeScript 5.4 (Backend)  

---

## 1. Executive Baseline Reproduction

All claims from the V12/V13 reports were submitted to independent verification against actual repository code, unit tests, integration test suites, and configurations:

| Evaluated Claim | Claim Source | Repository Reality | Verification Method | Status |
| :--- | :--- | :--- | :--- | :---: |
| **Claim 1: Firestore Biometric Vault Client Isolation** | `V12_SECURITY_CONTAINMENT.md` | `firestore.rules` lines 718-720 enforces `match /biometric_vault/{uid} { allow read, write: if false; }`. No permissive wildcard overrides. | Repository static rule audit & Emulator tests. | **VERIFIED IN REPO**<br>*(Live rules unverified)* |
| **Claim 2: Zero Client Vault Downloads / Local Matching** | `V12_SECURITY_CONTAINMENT.md` | `biometric_service.dart` has no `_db.collection('biometric_vault')` queries. Fallback loops completely excised. | Grep audit across `lib/`; `flutter analyze` clean. | **VERIFIED** |
| **Claim 3: Backend SFace ONNX as Single Authority** | `V12_RECOGNITION_ARCHITECTURE.md` | `face_inference.ts` loads `face_recognition_sface_2021dec.onnx` (SHA-256: `0ba9fbfa...`). Client vectors forbidden via middleware. | Checksum verification; `npm test` Stage S9 Test 2B passed. | **VERIFIED** |
| **Claim 4: Cross-Account API Image-Based Contract** | `V12_RECOGNITION_ARCHITECTURE.md` | Client `crossAccountCheck` transmits `{'imageBase64': ...}`; backend `/cross-account-check` runs server SFace inference. | Source inspection of `biometric_service.dart:868` and `face_routes.ts:835`. | **VERIFIED** |
| **Claim 5: Automated Test Suite Reproducibility** | `V12_TEST_AND_PERFORMANCE_EVIDENCE.md` | `npm test` ran 24 suites, 128 tests: 128 passed, 0 failed (41.16s). `flutter test` ran 4 suites, 67 tests: 67 passed. | Independent test command execution. | **VERIFIED** |
| **Claim 6: Real Cloud KMS Production Integration** | `V12_VAULT_SECURITY.md` | Tests execute against `LocalDevKeyProvider`. `CloudKmsKeyProvider` explicitly throws `KMS_UNAVAILABLE_ERROR` without GCP credentials. | Source audit of `kms_key_provider.ts:167-190`. | **NOT VERIFIED LIVE**<br>*(Local provider only)* |
| **Claim 7: Real-World 99.60% Biometric Accuracy** | `V12_BENCHMARK_RESULTS.md` | 99.60% is OpenCV's published LFW benchmark on standard reference data, NOT an empirical measurement on Kelasagara workers. | Benchmark attribution check; demographic trials pending. | **NOT VALIDATED**<br>*(Published baseline only)* |
| **Claim 8: Constant-Time Timing Oracle Padding** | `V12_API_SECURITY.md` | Code uses `if (elapsed < MIN_MS) await sleep(MIN_MS - elapsed);` (150ms / 300ms floor). This is a minimum floor, not constant-time. | Code inspection of `face_routes.ts:32,854`. | **PARTIALLY VERIFIED**<br>*(Floor padding, not constant)* |
| **Claim 9: Live Production Canary Deployment** | `V12_PRODUCTION_READINESS.md` | Staged canary rollout was recommended in report, but NO production deployment was authorized or executed. | Deployment check; zero live changes made. | **PROHIBITED / HALTED** |

---

## 2. Finding-by-Finding Evidence Matrix

```
[ FINDING F-01: FIRESTORE RULES VAULT ISOLATION ]
- Location: firestore.rules:718-720
- Code:
    match /biometric_vault/{uid} {
      allow read, write: if false;
    }
- Analysis: No client read, create, update, or delete is permitted.
  Recursive default rule at line 752 (match /{document=**}) also denies read, write: if false.
- Limitation: Verification is confirmed at the repository level. Because live Cloud Firestore rules
  cannot be read without live admin deploy tokens, the status of deployed rules is marked:
  LIVE FIRESTORE RULES NOT VERIFIED (Manual deployment via `firebase deploy --only firestore:rules` required).

[ FINDING F-02: EXCISE OF CLIENT-SIDE VAULT QUERIES ]
- Location: lib/services/biometric_service.dart
- Inspection:
  - Lines 706-715: Backend network errors return `BiometricCheckResult.technicalFailureRetry(...)`.
  - Lines 857-890: `crossAccountCheck` posts `{'imageBase64': imageBase64}` to `$_backendBaseUrl/cross-account-check`.
  - All occurrences of `_db.collection('biometric_vault')` have been removed.
  - The unused `FirebaseFirestore _db` field and `cloud_firestore` import have been removed.
- Evidence: `grep -rn "biometric_vault" lib/` returns 0 code references (comments only).
  `flutter analyze lib/services/biometric_service.dart` reports 0 issues.

[ FINDING F-03: SFace MODEL CHECKSUM & SPECIFICATION ]
- Relative Paths:
  - backend/models/face_recognition_sface_2021dec.onnx
  - assets/models/sface.onnx
- Complete SHA-256 Checksum:
  0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79
- Exact File Size: 38,696,353 bytes
- Architecture: MobileFaceNet + Sigmoid-Constrained Hypersphere Loss
- Vector Dimension: 128 Float32 elements, L2-normalized (||v||₂ = 1.0)
- License: Apache 2.0 (OpenCV Zoo)
- Input: 112×112×3 RGB tensor normalized via (pixel - 127.5) / 128.0

[ FINDING F-04: YuNet DETECTOR CHECKSUM & SPECIFICATION ]
- Relative Paths:
  - backend/models/face_detection_yunet_2023mar.onnx
  - assets/models/yunet.onnx
- Complete SHA-256 Checksum:
  8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4
- Exact File Size: 232,589 bytes
- License: MIT License (Wu et al., OpenCV Zoo)

[ FINDING F-05: REPLAY DEFENSE & FORBIDDEN VECTORS ]
- Location: backend/src/middleware/forbidden_vector_middleware.ts
- Location: backend/src/services/session_challenge_service.ts
- Evidence:
  - Test `Stage S9 Test 2B`: Submitting `probeVector` or `embedding` returns HTTP 400 `CLIENT_VECTORS_FORBIDDEN`.
  - Test `Redteam Test 2`: Replay of challenge nonce returns HTTP 400 `NONCE_ALREADY_CONSUMED`.
  - Test `Redteam Test 3`: Attempting to use victim UID challenge returns HTTP 403 `CHALLENGE_UID_MISMATCH`.

[ FINDING F-06: KMS ENVELOPE ENCRYPTION PROVIDER GAP ]
- Location: backend/src/services/kms_key_provider.ts:167-190
- Reality:
  - All 10 passing tests in Stage S8 execute against `LocalDevKeyProvider`.
  - `CloudKmsKeyProvider` throws explicit `KMS_UNAVAILABLE_ERROR` when `GOOGLE_APPLICATION_CREDENTIALS` is unset.
  - Staging/Production Cloud KMS has not executed live network encryption calls in this workspace.
- Classification: CLOUD KMS END-TO-END INTEGRATION: NOT VERIFIED.
```

---

## 3. Baseline Test Reproduction Log

### Backend Test Suite (`npm test` in `backend/`):
```
Command: cd '/Users/ananda/KELASAGARA MAJOR PROJECT/kelasagaara_v17/backend' && npm test
Exit Code: 0
Duration: 41.16s
Suites: 24 passed, 24 total
Tests: 128 passed, 128 total
Failures: 0
```

### Flutter Biometric Unit Tests (`flutter test` in `kelasagaara_v17`):
```
Command: cd '/Users/ananda/KELASAGARA MAJOR PROJECT/kelasagaara_v17' && flutter test test/biometric_*.dart
Exit Code: 0
Duration: 4.82s
Suites: 4 passed, 4 total
Tests: 67 passed, 67 total
Failures: 0
```

### Flutter Static Analysis:
```
Command: flutter analyze lib/services/biometric_service.dart lib/screens/auth/face_enrollment_screen.dart
Exit Code: 0
Duration: 3.6s
Issues: No issues found!
```
