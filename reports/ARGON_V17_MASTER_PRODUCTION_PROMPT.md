# MASTER PRODUCTION HANDOVER DIRECTIVE FOR AGENT ARGON (V17.0 CANARY RELEASE)

**Executing Agent:** Agent Argon (Principal Biometric Systems Architect, Google Cloud Security Engineer & Production Release Commander)  
**Target Repository:** `/Users/ananda/KELASAGARA MAJOR PROJECT/kelasagaara_v17`  
**Git Branch:** `ui/polish-v1`  
**Base Commit Handover:** `f39bfbe` (All 175 backend tests passing, 24 Flutter biometric tests passing, 478-pt EAR + SFace stream recorder complete)  
**Target Posture:** Transition from `CONTROLLED_TEST_BUILD_ONLY` to full staging verification and production canary clearance upon closure of Gates G-01 through G-08.

---

## 0. MANDATORY ENGINEERING RULES & FORENSIC CANDOR (ZERO-FABRICATION PROTOCOL)

1. **Absolute Truth in Test & Hardware Execution:** Never fabricate terminal output, execution counts, latency percentiles, or empirical field benchmarks. If GCP credentials, physical biometric test devices, or real-world human face datasets are not attached to the environment, generate synthetic mock harnesses and document the exact physical blockers in `reports/V17_FINAL_RELEASE_READINESS.md`.
2. **Production Fail-Safe Enforced:** Under no circumstances set `productionBiometricCalibrationApproved: true` in `backend/src/config.ts` without signed calibration outputs from an empirical human dataset.
3. **No Direct Client Vector Ingestion (Invariant I-06):** The backend must strictly reject client-submitted embeddings (HTTP 400 `CLIENT_VECTORS_FORBIDDEN`). Only server-derived SFace embeddings extracted from raw JPEG/PNG image buffers are authoritative.
4. **Zero Unencrypted Biometric Vectors at Rest (Invariant I-03):** All vectors stored in Firestore `biometric_vault` must be wrapped using AES-256-GCM envelope encryption bound to the caller's UID and tenant ID via length-prefixed canonical AAD.

---

## WORK PACKAGE 0: REPOSITORY BASELINE VERIFICATION & DIGEST AUDITING

Create and execute `scripts/wp0_establish_baseline.sh` to lock the codebase at commit `f39bfbe` and compute SHA-256 digests for all authoritative ONNX models and cryptographic libraries.

```bash
#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

echo "=== WORK PACKAGE 0: BASELINE AUDIT & MODEL DIGEST RECORDING ==="
GIT_HEAD="$(git rev-parse HEAD)"
GIT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
echo "Current Branch: ${GIT_BRANCH}"
echo "Current HEAD Commit: ${GIT_HEAD}"

# Verify ONNX model digests
echo "Auditing Biometric Model Artifacts..."
sha256sum backend/models/face_recognition_sface_2021dec.onnx || true
sha256sum backend/models/face_detection_yunet_2023mar.onnx || true

# Verify clean compilation
cd backend
npm run build
npm test

cd ..
flutter test test/face_enrollment_burst_stream_test.dart test/biometric_contract_test.dart test/client_biometric_integration_test.dart

echo "=== BASELINE VERIFIED CLEAN: ALL TESTS PASSING ==="
```

---

## WORK PACKAGE 1: DEMOGRAPHIC CALIBRATION HARNESS (GATE G-01)

Implement `backend/src/scripts/calibration_harness.ts` and its test suite `backend/src/tests/calibration_harness.test.ts`. This harness provides statistical rigor (Wilson score 95% confidence intervals, ROC curves, FMR/FNMR calculations, and bootstrap resampling) to calibrate $\tau_{\text{verify}}$, $\tau_{\text{dup}}$, and $\tau_{\text{hard}}$ for Indian worker cohorts (evaluating varied lighting, outdoor melanin levels, and low-cost camera sensors).

### Mathematical Requirements:
- **Wilson Score Interval (95% CI):**
  $$\hat{p} \pm \frac{z}{1 + \frac{z^2}{n}} \sqrt{\frac{\hat{p}(1-\hat{p})}{n} + \frac{z^2}{4n^2}} \quad (z = 1.95996)$$
- **Cluster Bootstrap:** Resample at the subject ID level (1,000 iterations) rather than pair level to prevent intra-subject correlation bias.
- **Monotonic Separation Guard:** Enforce $\tau_{\text{verify}} < \tau_{\text{dup}} < \tau_{\text{hard}}$ with a minimum separation buffer ($\Delta \ge 0.15$).

---

## WORK PACKAGE 2: PRESENTATION ATTACK DEFENSE (PAD) SOFTWARE ADVERSARIAL SUITE & PHYSICAL PROTOCOL (GATE G-02)

1. Implement `backend/src/tests/pad_software_adversarial.test.ts` to test challenge replay attacks, synthetic morphing, temporal jitter, photometric tampering, and eyelid aspect ratio anomalies.
2. Compile `reports/PHYSICAL_PAD_EVALUATION_PROTOCOL.md` and `reports/physical_pad_trials_schema.json` specifying ISO/IEC 30107-3 Level 1 physical testing requirements (2D printed photo attacks, iPad 120Hz screen replays, silicon mask penetration tests).

---

## WORK PACKAGE 3: PRODUCTION CLOUD KMS ENVELOPE ENCRYPTION & TERRAFORM (GATE G-03)

1. Implement `deploy/terraform/kms_biometric_vault.tf` declaring the Google Cloud KMS KeyRing and CryptoKey with HSM protection, 90-day rotation, and IAM Least Privilege.
2. Implement `backend/src/crypto/cloud_kms_envelope.ts` providing the live `@google-cloud/kms` adapter implementing `KeyManagementProvider` with fallback to `LocalDevKeyProvider` when running in disconnected test environments.

---

## WORK PACKAGE 4: END-TO-END STAGING SMOKE & TRANSACTION BOUNDARY SUITE (GATE G-06)

Implement `backend/src/tests/e2e_staging_smoke.test.ts` exercising the complete transaction pipeline:
1. `POST /api/biometrics/challenge` $\to$ Acquires 120s nonce.
2. `POST /api/biometrics/enroll-biometric` $\to$ Validates 3-frame burst, extracts 128-d SFace embedding, encrypts via KMS envelope, commits to `biometric_vault`.
3. `POST /api/biometrics/verify-1to1` $\to$ Verifies worker identity against enrolled KMS ciphertext.
4. `POST /api/biometrics/cross-account-check` $\to$ Ensures no duplicate identity across accounts.
5. `POST /api/biometrics/compliance/erasure` $\to$ DPDPA §12 cryptographic erasure.

---

## WORK PACKAGE 5: FIRESTORE SECURITY RULES & PENETRATION VERIFICATION (GATE G-05)

Implement `backend/src/scripts/verify_firestore_rules.ts` using `@firebase/rules-unit-testing` to prove that direct client read/write attempts to `biometric_vault`, `biometric_audit_log`, and `biometric_challenges` are denied unconditionally.

---

## WORK PACKAGE 6: DISTRIBUTED MULTI-INSTANCE GALLERY CONSISTENCY (GATE G-04)

Implement `backend/src/services/gallery_consistency_service.ts`:
- Solves Cloud Run multi-instance gallery drift (TOCTOU) when scaling across multiple server instances.
- Maintains a distributed version epoch in Firestore (`_metadata/gallery_version`).
- Triggers automatic cache invalidation and atomic re-sync across all active container instances.

---

## WORK PACKAGE 7 & 8: FINAL PRODUCTION READINESS COMPILATION & CANARY RELEASE GATING

Compile `reports/V17_FINAL_RELEASE_READINESS.md` containing the exhaustive 14-point readiness checklist, residual risk analysis, and canary rollout plan.
