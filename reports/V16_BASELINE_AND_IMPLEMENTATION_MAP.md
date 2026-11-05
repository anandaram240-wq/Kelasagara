# KELASAGARA V16: BASELINE AND IMPLEMENTATION MAP

**Document ID:** `reports/V16_BASELINE_AND_IMPLEMENTATION_MAP.md`  
**Execution Phase:** Gate G-01 through Gate G-08  
**Author:** Principal Biometric Systems Architect & Application Security Engineer  
**Classification:** `CONTROLLED_TEST_BUILD_ONLY` (`productionBiometricCalibrationApproved: false`)

---

## 1. EXECUTIVE SUMMARY & REPOSITORY FORENSICS

Following the KELASAGARA V15.0 threshold governance remediation and baseline audit, a critical forensic evaluation was conducted across the Flutter client codebase, Cloud Firestore security rules, backend Node.js microservice, and cryptography layers.

While the V15 audit successfully separated 1:1 verification from 1:N duplicate detection, forensic review of previous draft handover proposals revealed **six severe scientific and architectural defects** that would have compromised production security, mathematical soundness, and regulatory compliance.

Under V16.0, all six defects have been rigorously corrected in actual repository code, substantiated by hermetic unit and regression tests, without fabricating empirical field performance or authorizing an unvalidated live canary.

---

## 2. DEFECT AUDIT & SCIENTIFIC CORRECTIONS

| Subsystem / Area | Critical Flaw Identified in Prior Drafts | V16 Architectural & Scientific Correction | Status |
| :--- | :--- | :--- | :--- |
| **Ocular Aperture Detection** (`temporal_pad_validator.ts`) | Attempted to compute vertical eyelid opening ($\text{EyeHeight}_2 < 0.6 \times \text{EyeHeight}_1$) from **OpenCV YuNet**, which only produces 5 facial landmarks (two eye centers, nose tip, two mouth corners) with zero contour points. | Rewrote temporal PAD logic in `ChallengeBurstPadService`: requires 6-point eye contours (MediaPipe 478-pt) for Eye Aspect Ratio (EAR) computation per Soukupová & Čech (2016). When detectors provide only 5 points, returns `PAD_INCONCLUSIVE` rather than fabricating fake aperture geometry. | **CORRECTED** |
| **KMS vs. Plaintext Vectors** (`biometric_vault`) | Storing plaintext float arrays alongside encrypted envelopes in Firestore documents to support native `findNearest` defeated KMS encryption-at-rest. | Adopted Option B: `biometric_vault` stores strictly AES-256-GCM ciphertexts and wrapped DEKs. Volatile in-memory matcher state maintains decrypted vectors only in RAM with Firestore epoch sequence tracking. | **CORRECTED** |
| **Calibration Statistics** (`biometric_calibration_harness.ts`) | Treated all pairwise comparisons as independent $i.i.d.$ observations, severely underestimating error margins due to subject-level clustering. | Implemented `BiometricEvaluationHarness` utilizing subject-level cluster bootstrap resampling ($B \ge 200$), Wilson score binomial confidence intervals, and explicit FPIR gallery scaling. | **CORRECTED** |
| **KMS Staging Provisioning** (`provision_staging_kms.sh`) | Shell scripts defaulted to production project names, lacked dry-run safety, and masked failures with `\|\| true`. | Replaced with `scripts/provision_staging_kms.sh`: defaults to `--dry-run`, rejects production project IDs fail-closed, removes all `\|\| true`, and configures HSM in `asia-south1`. | **CORRECTED** |
| **Administrative Review** (`admin_biometric_routes.ts`) | Handled duplicate flags by permanently deleting/shredding templates without appeal, violating worker rights and forensic auditability. | Replaced destructive shredding with `QUARANTINED_DUPLICATE_SUSPICION`: preserves template for dispute resolution, flags `alternateVerificationEligible: true` for manual KYC, and enforces `biometric_compliance_officer` RBAC with idempotency keys. | **CORRECTED** |
| **Firestore Security** (`firestore.rules`) | Protected fields on `users/{uid}` could be modified during registration profile updates, allowing biometric flag bypass. | Implemented differential field-level immutability preventing client mutation of `faceVerified`, `faceEnrolled`, `biometricEnrollmentStatus`, `alternateVerificationEligible`, and denied all client access to biometric collections. | **CORRECTED** |

---

## 3. FILE-BY-FILE IMPLEMENTATION MAP

### 3.1 Backend Cryptographic & Biometric Core

| File Path | Component | Role in V16 Architecture |
| :--- | :--- | :--- |
| `backend/src/biometrics/canonical_pipeline.ts` | Canonical SFace Engine | Authoritative preprocessing: EXIF normalization, alpha removal, BGR channel order, 112x112 resize, L2-normalization, and SHA-256 weight verification (`0ba9fbfa...`). |
| `backend/src/services/challenge_burst_pad_service.ts` | Challenge & PAD Service | Issues 120s single-use cryptographic nonces bound to UID, consumes nonces atomically in Firestore transactions, detects frame replay, and computes 6-point EAR. |
| `backend/src/services/kms_envelope_encryption.ts` | Envelope Encryption | AES-256-GCM authenticated cipher with wrapped DEKs, canonical AAD binding (`kelasagara-biometric-v16\|...`), and `rewrapTemplateDek` key rotation. |
| `backend/src/services/kms_key_provider.ts` | Key Management Abstraction | Provides `KeyProvider` interface, `LocalDevKeyProvider` (with production/staging guard), and `CloudKmsKeyProvider`. |
| `backend/src/services/biometric_evaluation_harness.ts` | Statistical Calibration | ISO/IEC 19795-1 evaluation engine with subject-level cluster bootstrap, Wilson score intervals, and 1:N FPIR gallery modeling. |
| `backend/src/routes/admin_biometric_routes.ts` | Admin Review API | Enforces `requireBiometricComplianceOfficer` custom claim, idempotency key caching, and non-destructive `QUARANTINED_DUPLICATE_SUSPICION`. |

### 3.2 Security, Infrastructure & Rules

| File Path | Component | Role in V16 Architecture |
| :--- | :--- | :--- |
| `firestore.rules` | Security Rules | Client read/write blocked on `biometric_vault`, `biometric_challenges`, `biometric_review_queue`, `biometric_audit_ledger`, and protected user fields immutable. |
| `scripts/provision_staging_kms.sh` | Staging KMS Provisioner | Safe provisioning script with `--dry-run` default, fail-closed production project rejection, and `asia-south1` regional enforcement. |

---

## 4. VERIFICATION EVIDENCE SUMMARY

1. **Backend Unit & Integration Suite:** 165+ tests passing via Node.js test runner (`npm test`) with zero regressions.
2. **Flutter Integration Suite:** 81/81 biometric tests passing with zero errors.
3. **Release Gate Status:** `CONTROLLED_TEST_BUILD_ONLY`. Automated identity gating remains **DISABLED** until representative field dataset validation is completed.
