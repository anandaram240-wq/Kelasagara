# KELASAGARA BIOMATCH · STAGE S7 BASELINE REPRODUCTION (S7_BASELINE_REPRODUCTION.md)

**Classification:** Clean-Room Baseline Reproduction & Test Integrity Report  
**Stage:** S7  
**Execution Timestamp:** 2026-10-11T00:43:10Z  
**Starting Commit:** `215c44501b178422da8fc9233f4f10329d16b76a`  
**Host:** Darwin arm64 (Apple Silicon M4)  

---

## 1. Reproduction Methodology and Scope

In accordance with Stage S7 Part 1.4, a clean-room baseline reproduction was conducted across all automated validation and execution suites in the repository before applying any code modifications.

Commands were executed directly in the project environment, recording exact tool versions, exit codes, passed/failed test counts, duration, and test smells.

---

## 2. Command Execution Ledger

| Command | Working Directory | Exit Code | Wall Duration | Status | Primary Finding |
| :--- | :--- | :---: | :---: | :---: | :--- |
| `python3 tools/test_integrity.py` | `.` | 0 | 1.8s | `PASS` | 85 files, 810 tests, 2,225 assertions scanned. 9 zero-assertion tests, 2 skipped, 2 swallowed exceptions cataloged. |
| `python3 tools/secret_scan.py` | `.` | 0 | 1.2s | `PASS` | 580 files scanned. 0 API secrets, 0 private keys, 0 unregistered images detected. |
| `python3 tools/spec_drift_watch.py` | `.` | 0 | 0.9s | `PASS` | 7 international standards verified. Hash digest tracking active. |
| `python3 analysis/runner.py` | `.` | 0 | 3.4s | `PASS` | Frozen analysis code SHA-256 (`3dfc09361e...`) verified against committed hash guard. |
| `cd backend && npm run build && node --test --test-concurrency=1 dist/tests/*.test.js` | `backend/` | 0 | 37.2s | `PASS` | 18 test suites executed sequentially. 88/88 tests passed cleanly. 0 failures. |
| `python3 scripts/render_report.py && python3 scripts/no_orphan_numbers.py` | `.` | 0 | 1.1s | `PASS` | 0 orphan numbers detected in rendered markdown reports. |

---

## 3. Test-Integrity Investigation (Part 1.5)

The automated test-integrity scanner (`tools/test_integrity.py`) audited 85 test files across Flutter client tests, backend integration tests, and analytical verification scripts:

### 3.1 Catalog of Smells
- **Total Tests Scanned:** 810
- **Total Assertions Scanned:** 2,225
- **Tests with Zero Assertions:** 9
  - `test/registration_security_contract_test.dart`: 2 setup lifecycle stubs.
  - `test/voice_assistant_test.dart`: 4 audio recording mock wrappers where assertions were handled by mocked stream callbacks rather than explicit `expect()` blocks.
  - `backend/src/tests/attack_dry_run.test.ts`: 3 logging probes without assertions.
- **Skipped Tests:** 2
  - `test/auth_biometric_device_test.dart`: Skipped on non-Android host environments (requires Android KeyMint hardware).
- **Swallowed Exceptions:** 2
  - `backend/src/services/audit_service.ts`: Fallback handling when GCP default credentials are not detected in local dev environment.

### 3.2 Test Mutation Validation
Targeted mutation drills in `backend/src/tests/stage_s3_mutation_suite.test.ts` confirmed that the test suite detects critical security defects:
- Mutant 1 (Threshold off-by-one): KILLED.
- Mutant 2 (Unregistered model ID): KILLED.
- Mutant 3 (Flip-TTA silent bypass): KILLED.
- Mutant 4 (Quality gate bypass): KILLED.
- Mutant 5 (Cross-user template substitution): KILLED.
- Mutant 6 (Continuous score leakage): KILLED.
- Mutant 7 (Intra-session face swap bypass): KILLED.
- Mutant 8 (Inverted calibration slope): KILLED.
- Mutant 9 (Unverified model substitution): KILLED.
- Mutant 10 (Repeated lockbox access): KILLED.

All 10/10 mutants were successfully intercepted and killed by the test suite.

---

## 4. Exit Gate S7-G01 Verdict

| Gate Identifier | Title | Requirement | Status | Evidence Artifact |
| :--- | :--- | :--- | :---: | :--- |
| **S7-G01** | Repository Forensics & Baseline Reproduction | Full reproduction of baseline execution, zero secrets, and catalog of test integrity smells. | `DONE-VERIFIED` | `evidence/s7/baseline_results.json` |

---

## 5. Prioritized Action for S7 Remediation

With baseline reproduction established, the engineering team proceeds directly to **Priority 2 (Cryptographic Engineering & Template Protection)**:
1. Fix Additional Authenticated Data (AAD) omission in `TemplatePrivacyService` to defeat cross-tenant template splicing.
2. Upgrade envelope format to versioned schema `v2_aad_gcm` with explicit key versions.
3. Add full suite of cryptographic negative tests (bit flips, corrupted auth tags, swapped AAD, wrong keys).
