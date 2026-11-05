# S8 BASELINE RECONCILIATION REPORT

**Project:** Kelasagara BioMatch  
**Baseline Git Commit:** `00645aec249ac0b771ef0c9165216253672a2e9b`  
**Tag:** `s7-final`  
**Branch:** `biomatch/s8-verification`  
**Timestamp:** 2026-10-11T01:19:30Z  

---

## 1. Test Count Reconciliation
A comprehensive reconciliation was conducted to explain the relationship between:
1. **86 files / 820 tests** reported by static regex scanner (`tools/test_integrity.py`).
2. **27 files / 19 suites / 98 tests** executed by the Node.js test runner (`node --test`).
3. **59 files / 746 tests** executed by the Flutter test runner (`flutter test`).

### A. Architectural Explanation of Discrepancies
- **Static vs. Runner Measurement:**
  - `tools/test_integrity.py` uses lexical regex scanning across all TypeScript and Dart test files. It scanned 86 files (27 TS + 59 Dart) and parsed 820 test regex matches.
  - Runtime execution executes the actual test graph dynamically:
    - **Node.js Test Runner:** Discovers 27 `.test.js` files. 15 files use `describe()` blocks (totaling 19 test suites, e.g. `phase_c_security_and_lifecycle` has 5 sub-suites). 12 files use top-level `test()` without a `describe()` wrapper. The total number of individual test cases executed and passed is **98 tests**.
    - **Flutter Test Runner:** Discovers 59 `*_test.dart` files. 58 files pass completely (737 passed tests, 5 skipped). Exactly 1 file (`v701_valhalla_provider_live_benchmark_test.dart`) fails with 4 tests because it explicitly requires a live Valhalla routing server URL (`VALHALLA_BASE_URL`).
  - Total runner-executed tests: $98 \text{ (Node)} + 746 \text{ (Flutter)} = 844 \text{ tests}$.

### B. Per-File Backend Test Runner Matrix
Derived directly from runner output and recorded in [`evidence/s8/test_manifest.json`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/evidence/s8/test_manifest.json):

| File | Suites | Tests | Pass | Fail | Skip | Exit Code | Status |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| `api_routes_integration.test.js` | 0 | 1 | 1 | 0 | 0 | 0 | PASS |
| `attack_dry_run.test.js` | 1 | 1 | 1 | 0 | 0 | 0 | PASS |
| `biometric_backend.test.js` | 0 | 1 | 1 | 0 | 0 | 0 | PASS |
| `calibration_decision_engine.test.js` | 1 | 6 | 6 | 0 | 0 | 0 | PASS |
| `chaos_fault_injection.test.js` | 0 | 1 | 1 | 0 | 0 | 0 | PASS |
| `ci_regression_guard.test.js` | 1 | 5 | 5 | 0 | 0 | 0 | PASS |
| `concurrency_vault_store.test.js` | 0 | 1 | 1 | 0 | 0 | 0 | PASS |
| `cryptographic_assurance.test.js` | 1 | 10 | 10 | 0 | 0 | 0 | PASS |
| `data_architecture_state_machine.test.js` | 0 | 1 | 1 | 0 | 0 | 0 | PASS |
| `dpdpa_privacy_compliance.test.js` | 0 | 1 | 1 | 0 | 0 | 0 | PASS |
| `fairness_and_robustness.test.js` | 1 | 4 | 4 | 0 | 0 | 0 | PASS |
| `golden_vector_parity.test.js` | 0 | 1 | 1 | 0 | 0 | 0 | PASS |
| `in_memory_index_benchmark.test.js` | 1 | 1 | 1 | 0 | 0 | 0 | PASS |
| `inference_redundancy.test.js` | 0 | 1 | 1 | 0 | 0 | 0 | PASS |
| `invariant_registry_integrity.test.js` | 1 | 3 | 3 | 0 | 0 | 0 | PASS |
| `model_bakeoff_selection.test.js` | 1 | 4 | 4 | 0 | 0 | 0 | PASS |
| `mutation_integrity.test.js` | 1 | 12 | 12 | 0 | 0 | 0 | PASS |
| `phase_b_measurements.test.js` | 0 | 1 | 1 | 0 | 0 | 0 | PASS |
| `phase_c_security_and_lifecycle.test.js` | 5 | 17 | 17 | 0 | 0 | 0 | PASS |
| `pipeline_audit_ablations.test.js` | 1 | 3 | 3 | 0 | 0 | 0 | PASS |
| `quality_and_template_privacy.test.js` | 1 | 4 | 4 | 0 | 0 | 0 | PASS |
| `real_embedding_index_and_evasion.test.js` | 1 | 3 | 3 | 0 | 0 | 0 | PASS |
| `research_model_governance.test.js` | 0 | 1 | 1 | 0 | 0 | 0 | PASS |
| `security_hardening.test.js` | 0 | 1 | 1 | 0 | 0 | 0 | PASS |
| `server_landmark_liveness.test.js` | 1 | 3 | 3 | 0 | 0 | 0 | PASS |
| `stage_s3_mutation_suite.test.js` | 1 | 10 | 10 | 0 | 0 | 0 | PASS |
| `test_liveness_injection_bypass.test.js` | 0 | 1 | 1 | 0 | 0 | 0 | PASS |
| **TOTAL** | **19** | **98** | **98** | **0** | **0** | **0** | **100% PASS** |

---

## 2. Pinned Model Integrity Verification
- **SFace FP32 (`backend/models/face_recognition_sface_2021dec.onnx`):**  
  SHA-256: `0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79` (Matches prefix `0ba9fbfa`)
- **YuNet Detector (`backend/models/face_detection_yunet_2023mar.onnx`):**  
  SHA-256: `8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4` (Matches prefix `8f2383e4`)
- **Model Verification:** Verified via `crypto.createHash("sha256")` in `ModelRegistry.verifyArtifactIntegrity()`.
