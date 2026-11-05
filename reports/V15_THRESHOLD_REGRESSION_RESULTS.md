# KELASAGARA V15.0: THRESHOLD REGRESSION RESULTS & BOUNDARY VERIFICATION

**Project:** Kelasagara Worker Marketplace Biometric Subsystem  
**Date:** October 23, 2026  
**Test Suite:** [`backend/src/tests/threshold_governance.test.ts`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/backend/src/tests/threshold_governance.test.ts)  
**Execution Environment:** Node.js v20.x, macOS Darwin, standalone backend test runner (`node --test`)  
**Overall Result:** **20/20 TESTS PASSED (100% SUCCESS, 0 REGRESSIONS)**

---

## 1. Executive Summary

To provide mathematical and empirical proof that the 1:1 verification decision boundary is correctly positioned, decoupled from 1:N duplicate detection, and protected against malformed configuration, a dedicated regression test suite was implemented in [`backend/src/tests/threshold_governance.test.ts`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/backend/src/tests/threshold_governance.test.ts).

The test suite systematically probes the mathematical boundary around the OpenCV SFace reference threshold ($\tau = 0.363$), tests representative genuine scores ($0.45 - 0.70$), verifies unmistakable non-match rejections, proves the mathematical separation of 1:1 and 1:N decision trees, tests runtime configuration validation edge cases, and demonstrates the successful remediation of the worker shift re-verification bug.

---

## 2. Granular Test Suite Results

### Suite 1: 1:1 Verification Decision Boundary (OpenCV SFace Reference = 0.363)
Tests verify the exact comparative boundary of [`evaluateVerification(s, 0.363)`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/backend/src/services/biometric_matching.ts#L95):

| Test Case | Probe Score ($s$) | Operating $\tau$ | Expected Outcome | Actual Outcome | Execution Duration | Verdict |
|:---|:---:|:---:|:---:|:---:|:---:|:---:|
| **Sub-threshold Boundary** | $0.362$ | $0.363$ | `isMatch = false` | `isMatch = false` | 0.52 ms | **PASS** |
| **Exact Threshold Equality** | $0.363$ | $0.363$ | `isMatch = true` | `isMatch = true` | 0.09 ms | **PASS** |
| **Supra-threshold Boundary** | $0.364$ | $0.363$ | `isMatch = true` | `isMatch = true` | 0.07 ms | **PASS** |
| **Mid-Range Genuine (Low)** | $0.450$ | $0.363$ | `isMatch = true` | `isMatch = true` | 0.09 ms | **PASS** |
| **Mid-Range Genuine (Mid)** | $0.550$ | $0.363$ | `isMatch = true` | `isMatch = true` | 0.09 ms | **PASS** |
| **Mid-Range Genuine (High)** | $0.650$ | $0.363$ | `isMatch = true` | `isMatch = true` | 0.09 ms | **PASS** |
| **Strong Genuine Match** | $0.850, 0.950$ | $0.363$ | `isMatch = true` | `isMatch = true` | 0.08 ms | **PASS** |
| **Unmistakable Non-Match** | $0.10, 0.0, -0.20$ | $0.363$ | `isMatch = false` | `isMatch = false` | 0.07 ms | **PASS** |
| **Vector Dimension Mismatch** | $128 \text{ vs } 120$ | $0.363$ | `similarity = 0.0` | `similarity = 0.0` | 0.11 ms | **PASS** |

### Suite 2: Separation Proof: 1:1 Verification vs 1:N Duplicate Screening
Demonstrates that 1:1 verification decisions and 1:N duplicate policies operate on completely independent decision boundaries:

| Scenario / Score ($s$) | 1:1 Verification Decision | 1:N Duplicate Decision | Sybil Hard-Block | Policy Applied | Verdict |
|:---|:---:|:---:|:---:|:---|:---:|
| **$s = 0.50$ (Genuine Match)** | `isMatch: true` | `isDuplicate: false` | `isHardBlock: false` | Normal 1:1 login allowed; enrollment unique | **PASS** |
| **$s = 0.68$ (Ambiguous Match)** | `isMatch: true` | `isDuplicate: false` | `isHardBlock: false` | Login allowed; enrollment routed to RRL-0 manual review | **PASS** |
| **$s = 0.75$ (Duplicate Warning)** | `isMatch: true` | `isDuplicate: true` | `isHardBlock: false` | Enrollment flagged as duplicate; routed to review | **PASS** |
| **$s = 0.92$ (Sybil Duplicate)** | `isMatch: true` | `isDuplicate: true` | `isHardBlock: true` | Hard block sybil defense; claimant prompted to log into original account | **PASS** |

### Suite 3: Configuration Validation & Fail-Safe Governance
Proves that [`parseThreshold()`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/backend/src/config.ts#L10) and [`validateThresholdGovernance()`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/backend/src/config.ts#L36) reject invalid, corrupted, or inverted configurations:

| Input / Configuration Condition | Expected System Behavior | Actual System Behavior | Verdict |
|:---|:---|:---|:---:|
| **Valid Float (`"0.45"`)** | Return `0.45` | Returned `0.45` | **PASS** |
| **Undefined Env Variable** | Return default value (`0.363`) | Returned `0.363` | **PASS** |
| **Empty String (`"   "`)** | Throws `cannot be an empty string` | Thrown matching error | **PASS** |
| **Non-numeric Text (`"abc"`, `"NaN"`)** | Throws `must be a valid finite number` | Thrown matching error | **PASS** |
| **Infinity (`"Infinity"`, `"-Infinity"`)** | Throws `must be a valid finite number` | Thrown matching error | **PASS** |
| **Out of Range Value (`"1.5"`, `"-1.2"`)** | Throws `must be between -1 and 1` | Thrown matching error | **PASS** |
| **Inverted Thresholds ($\tau_{\text{verify}} \ge \tau_{\text{dup}}$)** | Throws `must be strictly less than duplicateThreshold` | Thrown matching error | **PASS** |
| **Inverted Duplicate ($\tau_{\text{dup}} \ge \tau_{\text{hard}}$)** | Throws `must be strictly less than hardBlockThreshold` | Thrown matching error | **PASS** |
| **Production Mode with Unapproved Gating** | Throws `CRITICAL RELEASE BLOCKER: Biometric identity gating...` | Thrown matching error | **PASS** |
| **Production Mode with Gating Disabled** | Succeeds startup cleanly | Succeeded without error | **PASS** |

### Suite 4: Account Lifecycle Re-verification Bug Remediation Proof
Demonstrates that [`AccountLifecycleService.reVerifyWorker`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/backend/src/services/account_lifecycle.ts#L142) evaluates 1:1 similarity against `config.verificationThreshold` (`0.363`) instead of `duplicateThreshold` (`0.74`):

- **Synthetic Probe Vector:** Synthesized with angle $\theta = 60^\circ$ relative to enrolled template ($s = \cos(60^\circ) = 0.50$).
- **Test Result:**
  - Prior behavior: REJECTED (because $0.50 < 0.74$).
  - Current V15 behavior: **ACCEPTED (`res.success: true, res.isMatch: true, res.threshold: 0.363`)**. Shift activated for 10 hours.
- **Verdict:** **PASS**.

---

## 3. Full Backend Test Suite Evidence

Following the V15 code updates, the full backend regression suite was executed across all 25 test files:

```bash
> kelasagara-biomatch-backend@1.0.0 test
> node --test --test-concurrency=1 dist/tests/*.test.js

ℹ tests 148
ℹ suites 29
ℹ pass 148
ℹ fail 0
ℹ cancelled 0
ℹ skipped 0
ℹ todo 0
ℹ duration_ms 41031.740959
```

All 148 tests passed cleanly in 41.03 seconds.

---

## 4. Flutter Biometric Contract Tests

The client-side biometric test suites in Flutter were executed:

```bash
flutter test test/biometric_deduplication_engine_test.dart \
             test/biometric_multi_face_test.dart \
             test/biometric_v5_master_scenarios_test.dart \
             test/biometric_whitened_embedding_test.dart \
             test/dense_facial_marker_engine_test.dart \
             test/client_biometric_integration_test.dart
```

**Result:**
- Total tests: 89
- Passed: 89
- Failed: 0
- Static analysis (`flutter analyze`): 0 compile errors.

---

## 5. Critical Distinction: Comparator Correctness vs. Biometric Accuracy

> [!IMPORTANT]
> **Engineering Invariant:** A passing software regression suite demonstrates only that the comparator logic, mathematical formulas, and threshold conditional branching execute as programmed.
> 
> **It does NOT prove:**
> - That the model achieves 99.60% accuracy on Indian gig workers.
> - That the threshold `0.363` yields FMR $10^{-4}$ in unconstrained field lighting.
> - That physical Presentation Attacks (printed photos, screen replays) will be stopped.
> 
> Biometric accuracy and presentation-attack resistance can only be proven through empirical testing on representative datasets and physical spoofs.
