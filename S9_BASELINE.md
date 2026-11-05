# KELASAGARA BIOMATCH — STAGE S9.5 BASELINE REPRODUCTION & SAFEGUARD REPORT
**Document ID:** `S9_BASELINE.md`  
**Classification:** Biometric Security Assurance & Independent Baseline Verification  
**Evaluation Date:** October 11, 2026 (UTC: 2026-10-11T05:06:00Z)  
**Starting Git HEAD:** `6a2a1482fe90d41050fc61ac83cc8777291a4a06` (tag: `s8-final`)  
**Active Working Branch:** `biomatch/s9-integration` (forked cleanly from `biomatch/s8-verification`)  
**Evidence Artifact:** `evidence/s9/baseline.json`  

---

## 1. REPOSITORY INTEGRITY & SAFEGUARDS

### 1.1 Git Working Tree & Reflog Audit
Prior to conducting any S9 modifications, the repository state was formally verified:
- **Repository Root:** `/Users/ananda/KELASAGARA MAJOR PROJECT/kelasagaara_v17`
- **Active Git Commit:** `6a2a1482fe90d41050fc61ac83cc8777291a4a06`
- **Baseline Git Tag:** `s8-final` (confirmed pointing directly to `6a2a148`)
- **Working Tree State:** Completely clean, zero uncommitted or untracked file modifications.
- **Worktree Audit:** Single active worktree verified. Historical worktree removal did not impact source files. Transient working-directory benchmark latency changes to `INDEX_REPORT.md` and `RECOGNITION_AUDIT.md` were restored to match the exact tagged baseline.

### 1.2 Evidence Manifest Verification (S8 Audit)
The S8 manifest file at `evidence/s8/MANIFEST.json` specifies 8 primary evidence files. Every single file was re-hashed using SHA-256 and compared against the recorded manifest digests:

| File Path | Recorded SHA-256 | Measured SHA-256 | Audit Verdict |
| :--- | :--- | :--- | :--- |
| `evidence/s8/recovery_assessment.json` | `8db79a70b8dbb50af98e1e5b292d2f03637c169ed96ba54c819b0bcc479c7480` | `8db79a70b8dbb50af98e1e5b292d2f03637c169ed96ba54c819b0bcc479c7480` | **MATCH (100%)** |
| `evidence/s8/baseline.json` | `be01070a7d0fc818dd70324a8406572b7b382ec9c181da0994c20a74b6778d63` | `be01070a7d0fc818dd70324a8406572b7b382ec9c181da0994c20a74b6778d63` | **MATCH (100%)** |
| `evidence/s8/test_manifest.json` | `d27d1c026599c907c7b902ec45a2c1059d040a1ef2f76fad6825c68f7d56c59f` | `d27d1c026599c907c7b902ec45a2c1059d040a1ef2f76fad6825c68f7d56c59f` | **MATCH (100%)** |
| `evidence/s8/aad_attack_regression.json` | `00dd1ade1f547d641c388c0e7087387bce2e2613cda8d3d9cf3a3305d3de8ef2` | `00dd1ade1f547d641c388c0e7087387bce2e2613cda8d3d9cf3a3305d3de8ef2` | **MATCH (100%)** |
| `evidence/s8/kms_unit_tests.json` | `329d88f5f441c2937e5376dc4d92c0e6b89ff4a40e34ac0d96fc32470ff9e776` | `329d88f5f441c2937e5376dc4d92c0e6b89ff4a40e34ac0d96fc32470ff9e776` | **MATCH (100%)** |
| `evidence/s8/attestation_unit_tests.json` | `65894edf3f56c7b2373be1f02a0d4157438d5157879e57b08913bfb350ad3b16` | `65894edf3f56c7b2373be1f02a0d4157438d5157879e57b08913bfb350ad3b16` | **MATCH (100%)** |
| `evidence/s8/cross_tenant_integration_results.json` | `9af04a8a8ac6e238b06cf0c55342cf350bdb9f600ccacf910f8ca76cb7c35eca` | `9af04a8a8ac6e238b06cf0c55342cf350bdb9f600ccacf910f8ca76cb7c35eca` | **MATCH (100%)** |
| `evidence/s8/test_run.json` | `d6de667b66fdb6e45a34ab626edfc5c69f4647b29d4d19cebf977e88be031cdb` | `d6de667b66fdb6e45a34ab626edfc5c69f4647b29d4d19cebf977e88be031cdb` | **MATCH (100%)** |

**Result:** S8 manifest integrity is **100.0% VERIFIED**.

---

## 2. PINNED MODEL ARTIFACT VERIFICATION

All neural network weights in `backend/models/` were independently hashed using SHA-256:

| Model Name | Physical Path | Measured SHA-256 Digest | Match Verdict |
| :--- | :--- | :--- | :--- |
| **SFace FP32 (Primary)** | `backend/models/face_recognition_sface_2021dec.onnx` | `0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79` | **PINNED MATCH** |
| **YuNet (Detector)** | `backend/models/face_detection_yunet_2023mar.onnx` | `8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4` | **PINNED MATCH** |
| **SFace INT8 (Quantized)** | `backend/models/face_recognition_sface_2021dec_int8.onnx` | `2b0e941e6f16cc048c20aee0c8e31f569118f65d702914540f7bfdc14048d78a` | **PINNED MATCH** |
| **MobileFaceNet (Legacy)** | `backend/models/kelasagara_mobilefacenet.onnx` | `cde3799f041eca6a6a99bfac53d9e97eb81ff34ac450d519aa41a9c99bef7d7c` | **PINNED MATCH** |

---

## 3. INDEPENDENT S8 BASELINE REPRODUCTION

### 3.1 Backend Test Runner Execution
- **Command:** `npm test` (`node --test --test-concurrency=1 dist/tests/*.test.js`)
- **Working Directory:** `/Users/ananda/KELASAGARA MAJOR PROJECT/kelasagaara_v17/backend`
- **Execution Timestamp:** `2026-10-11T05:04:18Z` to `2026-10-11T05:05:01Z`
- **Runtime Environment:** Node.js `v20.17.0`, TypeScript `v5.3.3`, ONNX Runtime Node `v1.20.1`, macOS Darwin arm64
- **Exit Code:** `0`
- **Total Discovered Suites:** `23`
- **Total Discovered Tests:** `127`
- **Passed Tests:** `127`
- **Failed Tests:** `0`
- **Skipped / Cancelled Tests:** `0`
- **Duration:** `42,828.82 ms` (~42.8 seconds)

### 3.2 Breakdown of Critical Security Suites

1. **AAD Canonicalization (`dist/tests/aad_canonicalization.test.js`):**
   - 11 tests passed. Verifies length-prefixed binary canonical encoding (`BIOMATCH_AAD_V1`), domain separation magic header (`0x42 0x49 0x4F 0x4D 0x41 0x54 0x43 0x48 0x5F 0x41 0x41 0x44 0x5F 0x56 0x31`), strict TLV tag parsing, and full prevention of field-boundary delimiter attacks.
2. **Template Migration & KMS Interface (`dist/tests/template_migration.test.js`):**
   - 10 tests passed. Verifies local dev key wrapping, `v3_kms_gcm` envelope construction, 512-float vector roundtrip preservation, dry-run safety, and idempotent skipping of v3 envelopes.
3. **Play Integrity Attestation (`dist/tests/play_integrity_attestation.test.js`):**
   - 8 tests passed. Verifies SHA-256 canonical `requestHash` computation, client package validation, replay interception, and attestation tier gating.
4. **Cross-Tenant Isolation (`dist/tests/cross_tenant_isolation.test.js`):**
   - 6 tests passed. Verifies cross-tenant template substitution denial, envelope splicing prevention, wrapped DEK theft resistance, and distributed leased locking in enrollment sessions.
5. **Adversarial & Mutation Suite (`dist/tests/stage_s3_mutation_suite.test.js`):**
   - 10 mutants killed. Proves test suite sensitivity against intentional threshold alterations, quality bypasses, score leaks, and unauthorized model substitutions.

---

## 4. FLUTTER VALHALLA ROUTING PROBE INVESTIGATION

The 4 reported Flutter test failures in `test/v701_valhalla_provider_live_benchmark_test.dart` were inspected:
- **Test File:** `test/v701_valhalla_provider_live_benchmark_test.dart` (lines 11–15, 17–20, 41–44, 112–115)
- **Root Cause:** All four tests evaluate:
  ```dart
  if (configuredBaseUrl.isEmpty) {
    fail('Valhalla production endpoint is not configured. Provide VALHALLA_BASE_URL to run live benchmarks.');
  }
  ```
- **Relevance:** This test suite is a live network connectivity benchmark for an external map routing engine (Valhalla) for navigation services. It contains zero biometric logic, zero cryptographic operations, and zero security policy evaluation.
- **Action:** Per engineering directive, these tests remain unmodified and preserved.

---

## 5. INITIAL CAPABILITY STATUS CLASSIFICATION (MISSION 0.3)

Per the strict status vocabulary of the S9.5 directive:

| Security Capability | Implementation Component | Status | Justification |
| :--- | :--- | :--- | :--- |
| **AAD Canonicalization** | `template_privacy.ts` (`BIOMATCH_AAD_V1`) | `REPRODUCED` | Verified by 11 passing tests in `aad_canonicalization.test.js` |
| **Envelope Encryption (`v3`)** | `template_privacy.ts` (`v3_kms_gcm`) | `REPRODUCED` | Verified by 10 passing tests in `template_migration.test.js` |
| **Local Key Provider** | `kms_key_provider.ts` (`LocalDevKeyProvider`) | `REPRODUCED` | Unit tests verify AES-256-GCM wrapping with canonical AAD |
| **Cloud KMS Live Integration** | `kms_key_provider.ts` (`CloudKmsKeyProvider`) | `EXTERNALLY_BLOCKED` | `GOOGLE_APPLICATION_CREDENTIALS` unset; cannot execute live GCP API calls |
| **Play Integrity Unit Binding** | `device_attestation.ts` (`requestHash`) | `REPRODUCED` | Unit tests verify SHA-256 request binding |
| **Play Integrity Live Verification** | `device_attestation.ts` (`GooglePlayIntegrityVerifier`) | `EXTERNALLY_BLOCKED` | `PLAY_INTEGRITY_SERVICE_ACCOUNT_KEY` unset; cannot query Google API |
| **Cross-Tenant Isolation** | `template_privacy.ts`, `session_manager.ts` | `REPRODUCED` | 6 integration tests prove multi-tenant boundaries hold |
| **Leased Concurrency Lock** | `session_manager.ts` | `REPRODUCED` | 60-second distributed Firestore lease prevents race conditions |
| **Adversarial Mutation Suite** | `stage_s3_mutation_suite.test.ts` | `REPRODUCED` | 10 mutants killed; zero false passes |

---
*Report generated and validated under Stage S9.5 Operating Contract.*
