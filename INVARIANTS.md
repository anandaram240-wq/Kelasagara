# INVARIANTS MAPPING & SYSTEM HARDENING MATRIX
**Subsystem:** Kelasagara BioMatch V9 / Stage S2  
**Baseline Standard:** Aadhaar Face RD-Class Architectural Assurance  
**Version:** 2.0.0 (Post-V9 Hardening)

---

## 1. Executive Invariants Catalog (I-01 through I-24)

| Invariant ID | Name | Core Mandate | V7 Baseline Status | V9 / S2 Hardened Status | Verification Evidence |
|:---|:---|:---|:---:|:---:|:---|
| **I-01** | **Fail-Closed Principle** | System never approves face if any model, network, authorization, or pipeline step fails. | Partial (client fallback risks) | **ENFORCED** (routes to `technical_failure_retry` or `pending_review`) | `research_model_governance.test.ts` (Test 5), `api_routes_integration.test.ts` |
| **I-02** | **Zero Automated Approval** | 100% of unique enrollments resolve to `accountStatus: 'pending_review'`. Zero automated clearances under pilot models. | VIOLATED (Defect D2) | **ENFORCED** (Model registry asserts `clearedForAutomatedApproval: false`) | `research_model_governance.test.ts` (Test 4A, 4B) |
| **I-03** | **Zero Client Vector Trust** | Server strictly accepts raw `imageBase64`. Any client `embedding`, `probeVector`, or `landmarks` is rejected with HTTP 400. | VIOLATED (Defect D1) | **ENFORCED** (`checkForbiddenVectorFields` middleware + schema gating) | `api_routes_integration.test.ts` (Test 2B) |
| **I-04** | **Challenge Nonce Lifecycle** | Nonces bound to caller UID with 60-second sliding expiration. | Present | **ENFORCED** (`SessionChallengeService.issueChallenge`) | `api_routes_integration.test.ts` (Test 3) |
| **I-05** | **Nonce Replay & Theft Defense** | Nonce single-use consumption. Cross-action or cross-UID nonce theft strictly blocked (HTTP 403). | Present | **ENFORCED** (`SessionChallengeService.consumeChallenge`) | `api_routes_integration.test.ts` (Test 4) |
| **I-06** | **Authoritative Preprocessing Tag** | Templates permanently record `PREPROC_V1_UMEYAMA_112_RGB_RAW255`. Umeyama 5-point alignment with raw [0..255] float RGB. | VIOLATED (Defect D4, [-1..1] drift) | **ENFORCED** (OpenCV C++ Zoo contract matched, closed-form Umeyama) | `golden_vector_parity.test.ts`, `PREPROCESSING.md` |
| **I-07** | **Threshold Provenance** | No threshold activates automated clearing unless empirically calibrated on consented ground-truth dataset. | VIOLATED (Defect D3) | **ENFORCED** (`ScoreRecordPolicy`: advisory floor 0.363, top-3 candidates recorded) | `biometric_enrollment.ts`, `research_model_governance.test.ts` |
| **I-08** | **Timing Oracle Resistance** | Constant-time response bucketing and latency padding prevent inference timing side-channels. | Present | **ENFORCED** (Padding to >= 100ms on all biometric endpoints) | `api_routes_integration.test.ts` (Test 5) |
| **I-09** | **Dual-Model Isolation** | Cross-model comparisons between heterogeneous architectures or quantization tiers strictly throw an error. | Incomplete (Defect D4) | **ENFORCED** (Repository checks `modelId` & `preprocessVersion` on every comparison) | `firestore_biometric_repository.ts`, `inference_redundancy.test.ts` |
| **I-10** | **Tamper-Evident Audit Ledger** | Every biometric event is hash-chained with SHA-256 previous-hash and sequential indexing. | Present | **ENFORCED** (`tamper_evident_audit.ts`, `AuditService`) | `tamper_evident_audit.test.ts`, `api_routes_integration.test.ts` |
| **I-11** | **Zero PII in Audit Trail** | Audit logs contain only pseudonymous UIDs, model hashes, top-k score arrays, and chain links (zero raw phone/images). | Incomplete | **ENFORCED** (`sanitizeAuditMetadata` strips all image/vector/phone keys) | `audit_service.ts` |
| **I-12** | **Bilingual Notice & Consent V2** | Granular Kannada/English notice with distinct opt-ins for verification and optional research (DPDPA 2023). | Incomplete | **ENFORCED** (`BiometricConsentV2Doc`, Flutter pre-scan overlay with counsel notice) | `face_enrollment_screen.dart`, `dpdpa_privacy_compliance.test.ts` |
| **I-13** | **Formal State Machine** | Strict transition enforcement (`PENDING_FACE` -> `IN_PROGRESS` -> `PENDING_REVIEW` -> `ACTIVE`). | Present | **ENFORCED** (`EnrollmentStateMachine.validateTransition`) | `enrollment_state_machine.test.ts` |
| **I-14** | **Atomic Dual-Write Persistence** | Vault template and user profile updated in a single atomic Firestore batch transaction. | Present | **ENFORCED** (`batch.commit()` in `FirestoreBiometricRepository`) | `concurrency_vault_store.test.ts` |
| **I-15** | **Zero Orphaned Templates** | A template can never exist without an existing, validated `/users/{uid}` profile document. | Present | **ENFORCED** (Pre-check `userSnap.exists` inside transaction) | `firestore_biometric_repository.ts` |
| **I-16** | **Self-Healing Reconciliation** | Discrepancies between user verification state and vault records automatically fail closed. | Present | **ENFORCED** (`EnrollmentStateMachine.reconcileState`) | `dpdpa_privacy_compliance.test.ts` |
| **I-17** | **Append-Only Immutability** | Audit logs cannot be updated or deleted; tamper attempts invalidate cryptographic chain. | Present | **ENFORCED** (Append-only Firestore security rules) | `tamper_evident_audit.test.ts` |
| **I-18** | **Research Tier Guard** | Models marked `RESEARCH_ONLY` or `PILOT_SHADOW` cannot trigger account auto-activation. | Partial | **ENFORCED** (`ModelRegistry.assertClearedForAutomatedApproval`) | `research_model_governance.test.ts` |
| **I-19** | **Bounded Gallery Protection** | Flat gallery scans capped to protect Spark free-tier read limits. | Present | **ENFORCED** (`config.maxGalleryScanLimit = 500`) | `firestore_biometric_repository.ts` |
| **I-20** | **Non-Biometric Alternative** | Users declining biometric consent proceed via Document KYC without loss of platform functionality. | Present | **ENFORCED** (Document KYC button on consent overlay) | `face_enrollment_screen.dart`, `dpdpa_privacy_compliance.test.ts` |
| **I-21** | **Concurrency Lease Lock** | In-flight enrollment reservations prevent concurrent duplicate account submission races. | Present | **ENFORCED** (`biometric_enrollment_sessions` collection) | `concurrency_vault_store.test.ts`, `chaos_fault_injection.test.ts` |
| **I-22** | **Liveness Assessment** | Google ML Kit classification + eye-blink EAR threshold assessment verifies physical presence. | Present | **ENFORCED** (`face_enrollment_screen.dart` eye aspect ratio tracker) | Flutter biometric client |
| **I-23** | **Uniform Response Envelope** | Standardized JSON envelopes prevent leakage of internal state or biometric feature distributions. | Present | **ENFORCED** (`BiometricResponseEnvelope<T>`) | `api_routes_integration.test.ts` |
| **I-24** | **Crypto-Shredding Erasure** | DPDPA Section 12 Right to Erasure purges vault vector and envelope key instantly. | Present | **ENFORCED** (`deleteTemplate` batch delete) | `dpdpa_privacy_compliance.test.ts` |
| **I-25** | **Frame Provenance Cryptographic Binding** | Biometric frames must be cryptographically bound to session nonce, hardware timestamp, and device ID. | Missing (Finding F2) | **ENFORCED** (`DeviceAttestationService.verifyFrameProvenance`) | `phase_c_security_and_lifecycle.test.ts` (Test 1) |
| **I-26** | **Hardware Device Attestation** | Non-dev requests from un-attested devices or emulators are blocked before neural inference. | Missing (Finding F2) | **ENFORCED** (`DeviceAttestationService.verifyDeviceIntegrity`) | `phase_c_security_and_lifecycle.test.ts` (Test 1) |
| **I-27** | **Mandatory Shift Re-Verification** | Gig workers must pass 1:1 facial re-verification before starting shift (10-hour TTL). Defeats account renting. | Missing (Finding F4) | **ENFORCED** (`AccountLifecycleService.reVerifyWorker`, `/api/biometrics/re-verify`) | `phase_c_security_and_lifecycle.test.ts` (Test 2) |
| **I-28** | **Hardware Device Binding** | Accounts bound to verified device fingerprint; unexpected device switches trigger security step-up. | Missing (Finding F4) | **ENFORCED** (`AccountLifecycleService.reVerifyWorker`) | `phase_c_security_and_lifecycle.test.ts` (Test 2) |
| **I-29** | **Dynamic Multi-Action Liveness** | Randomized server-side multi-gesture challenge (blink, smile, head turn) with per-step timeouts. | Missing (Finding F3) | **ENFORCED** (`PresentationAttackDefenseService.issueChallenge`, `/liveness-challenge`) | `phase_c_security_and_lifecycle.test.ts` (Test 3) |
| **I-30** | **Static Presentation Rejection** | Frames with near-zero landmark temporal variance (< 0.5px) rejected as 2D photo prints. | Missing (Finding F3) | **ENFORCED** (`PresentationAttackDefenseService.verifyChallenge`) | `phase_c_security_and_lifecycle.test.ts` (Test 3) |
| **I-31** | **RAM Gallery Search Bounded Quota** | 1:N deduplication queries in-memory vector cache before Firestore scans to protect Spark 50k read limit. | Missing (Finding F8) | **ENFORCED** (`InMemoryBiometricIndex.findTopK`, `firestore_biometric_repository.ts`) | `phase_c_security_and_lifecycle.test.ts` (Test 4) |
| **I-32** | **Single-Access Lockbox Governance** | LOCKBOX partition touched once for final config only. Repeated evaluation throws tamper exception. | Missing (Finding F1) | **ENFORCED** (`DatasetPartitionManager.accessLockbox`, audit hash committed) | `ci_regression_guard.test.ts`, `stage_s3_mutation_suite.test.ts` |
| **I-33** | **Demographically Matched Impostor Evaluation** | Impostor pairs must be strictly demographically matched; cross-cohort impostors prohibited from diluting FMR. | Missing (Finding F5) | **ENFORCED** (`FairnessEvaluator.evaluateDemographicParity`) | `fairness_and_robustness.test.ts` |
| **I-34** | **Continuous Score Sanitization (Anti-Hill-Climbing)** | Zero raw scores, cosine distances, or LLR values returned to client. Discrete auth tickets only. | Missing (Finding F2) | **ENFORCED** (`IntraSessionLivenessBinding.sanitizeClientResponse`) | `calibration_decision_engine.test.ts`, `stage_s3_mutation_suite.test.ts` |
| **I-35** | **Intra-Session Identity Binding** | All frames in a single challenge session must meet pairwise cosine >= 0.70. Mid-session face swaps fail closed. | Missing (Finding F3) | **ENFORCED** (`IntraSessionLivenessBinding.verifyInterFrameConsistency`) | `calibration_decision_engine.test.ts`, `stage_s3_mutation_suite.test.ts` |
| **I-36** | **Multi-Sample Centroid Enrollment** | Enrollments require >= 5 frames with yaw diversity, outlier rejection, and L2-normalized centroid. | Missing (Finding F1) | **ENFORCED** (`MultiSampleEnrollmentService.enroll`) | `quality_and_template_privacy.test.ts` |

---

## 2. Defect Resolution Audit (D1 to D8)

| Defect ID | Description | Root Cause | Ticket | Resolution & Evidence |
|:---:|:---|:---|:---:|:---|
| **D1** | Client Vector Injection Path | `EnrollRequestDTO` accepted `embedding` field | **T-01** | Removed `embedding` from client DTOs. Added `checkForbiddenVectorFields` middleware (HTTP 400). Raw frames only. |
| **D2** | Auto-Approval on Uncalibrated Weights | Pipeline committed `accountStatus: 'approved'` | **T-02** | Replaced `ModelTier` with `PILOT_SHADOW`. 100% of unique submissions resolve to `pending_review` with `isApproved: false`. |
| **D3** | Hard Decisions on Uncalibrated Scores | Hard thresholds (0.730 / 0.500) blocked users | **T-05** | Implemented `ScoreRecordPolicy`. Top-3 candidates stored with advisory floor `0.363`. Potential duplicates route to human review. |
| **D4** | Preprocessing Normalization Mismatch | `[-1.0, 1.0]` normalization caused FP32 vs INT8 divergence (0.56) | **T-03, T-04** | Matched OpenCV C++ Zoo raw `[0.0, 255.0]` RGB input. Pure TypeScript closed-form Umeyama alignment. Correlation raised to > 0.646. |
| **D5** | Unchecked Random Weights in Codebase | `export_mobilefacenet_onnx.py` exported uninitialized weights | **T-16** | Registry rejects random weights. `export_mobilefacenet_onnx.py` segregated to research-only with warning. |
| **D6** | Lack of Granular Multilingual Consent | Consent was implicit or single-checkbox | **T-07** | Implemented Consent V2 schema (`BiometricConsentV2Doc`) and Flutter bilingual pre-scan overlay with separate opt-ins. |
| **D7** | Raw PII in Audit Logs | Audit events logged masked phone and raw metadata | **T-06** | `sanitizeAuditMetadata` strips all image, vector, buffer, and phone keys. Audit trail contains only pseudonymous metrics. |
| **D8** | Cross-Model Vector Pollution Risk | No repository guard prevented comparing mismatched models | **T-08** | Enforced `modelId` and `preprocessVersion` checks in `findTopK` and `getEnrolledTemplate`. Mismatched comparisons throw error. |

---

## 3. Test Suite Execution & Verification

Run all test suites via unified execution:
```bash
cd backend
npm run build
node --test dist/tests/golden_vector_parity.test.js
node --test dist/tests/inference_redundancy.test.js
node --test dist/tests/research_model_governance.test.js
node --test dist/tests/api_routes_integration.test.js
node --test dist/tests/dpdpa_privacy_compliance.test.js
```
