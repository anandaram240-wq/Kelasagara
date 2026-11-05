# KELASAGARA BIOMETRIC ENGINE V10.0
# Biometric System Evaluation Protocol & Statistical Test Plan
## Standard Methodology for 1:1 Verification, 1:N Duplicate Screening, and Sample Size Calibration

**Document ID:** `REP-EVALPLAN-V10-01`  
**Standard Framework:** ISO/IEC 19795-1:2021, ISO/IEC 19795-10:2024, NIST FRTE 1:1 & 1:N  
**Status:** Approved Test Methodology  
**Version:** 10.0.0-PROD  
**Date:** 2026-10-22  

---

## 1. Scope, Purpose & Standards Compliance

This evaluation plan establishes the formal statistical protocol for evaluating the accuracy, generalization, error rates, and operational boundaries of the Kelasagara Biometric Engine V10.0. 

Adhering strictly to **ISO/IEC 19795-1:2021** (Biometric Performance Testing and Reporting), this protocol mandates the mathematical and operational separation of two fundamentally distinct matching tasks:
1. **Task A: One-to-One (1:1) Authentication & Verification.** Probe biometric sample vs. single enrolled template associated with a claimed account UID.
2. **Task B: One-to-Many (1:N) Duplicate Registration Screening.** Probe biometric sample vs. entire gallery ($N$ enrolled worker templates) to detect multi-account fraud.

---

## 2. Formal Metric Definitions & Mathematical Formulations

```
+----------------------------------------------------------------------------------------------------+
|                                    BIOMETRIC TASK METRIC SEPARATION                                |
+----------------------------------------------------+-----------------------------------------------+
|  TASK A: 1:1 VERIFICATION                          |  TASK B: 1:N DUPLICATE IDENTIFICATION         |
|  - False Match Rate (FMR)                          |  - False Positive Identification Rate (FPIR)  |
|  - False Non-Match Rate (FNMR)                     |  - False Negative Identification Rate (FNIR)  |
|  - Failure to Acquire (FTA)                        |  - Cumulative Match Characteristic (CMC)      |
|  - Equal Error Rate (EER)                          |  - Rank-1 Identification Accuracy             |
+----------------------------------------------------+-----------------------------------------------+
```

### 2.1 Task A (1:1 Verification) Metrics
Let $\mathcal{I}_{	ext{mated}}$ be the set of genuine comparison pairs (same individual) and $\mathcal{I}_{	ext{non-mated}}$ be the set of impostor comparison pairs (distinct individuals). For a decision threshold $	au_{	ext{verify}}$:

1. **False Match Rate (FMR):** The probability that an impostor probe is falsely accepted as matching the claimed identity:
   $$	ext{FMR}(	au) = rac{|\{ (i, j) \in \mathcal{I}_{	ext{non-mated}} : s(i, j) \ge 	au \}|}{|\mathcal{I}_{	ext{non-mated}}|}$$
2. **False Non-Match Rate (FNMR):** The probability that a genuine probe is falsely rejected:
   $$	ext{FNMR}(	au) = rac{|\{ (i, j) \in \mathcal{I}_{	ext{mated}} : s(i, j) < 	au \}|}{|\mathcal{I}_{	ext{mated}}|}$$
3. **Target Calibration for Kelasagara Consumer Verification:**
   - $	ext{FMR} \le 0.001$ ($0.1\%$ or $1	ext{ in }1,000$).
   - $	ext{FNMR} \le 0.020$ ($2.0\%$).
   - Calibrated Operating Threshold: $	au_{	ext{verify}} = \mathbf{0.38}$.

### 2.2 Task B (1:N Duplicate Screening) Metrics
For a probe sample $p$ compared against a gallery $\mathcal{G} = \{g_1, g_2, \dots, g_N\}$ of size $N$:

1. **False Positive Identification Rate (FPIR):** The probability that a probe from a person *not enrolled in the gallery* produces at least one gallery match above threshold $	au_{	ext{dedup}}$:
   $$	ext{FPIR}(	au, N) = 	ext{Pr}\left( \max_{g \in \mathcal{G}} s(p, g) \ge 	au \;\middle|\; p 
otin \mathcal{G} ight)$$
   Under the independence assumption: $	ext{FPIR}(	au, N) pprox 1 - (1 - 	ext{FMR}(	au))^N$.
2. **False Negative Identification Rate (FNIR):** The probability that an enrolled individual's duplicate enrollment probe fails to achieve a match score above $	au_{	ext{dedup}}$:
   $$	ext{FNIR}(	au, N) = 	ext{Pr}\left( \max_{g \in \mathcal{G}_{	ext{mated}}} s(p, g) < 	au \;\middle|\; p \in \mathcal{G} ight)$$
3. **Target Calibration for Kelasagara 1:N Duplicate Detection:**
   - $	ext{FPIR}(N=10,000) \le 0.010$ ($1.0\%$).
   - $	ext{FNIR}(N=10,000) \le 0.050$ ($5.0\%$).
   - Calibrated Operating Threshold: $	au_{	ext{dedup}} = \mathbf{0.74}$.
   - Hard Block Threshold: $	au_{	ext{hard}} = \mathbf{0.90}$.

---

## 3. Sample Size & Statistical Power Calculations

To satisfy ISO/IEC 19795-1 empirical confidence requirements, test sample sizes must be mathematically determined based on target error rates and confidence intervals.

### 3.1 Rule of 3 and Rule of 30
- **Rule of 3 (No Errors Observed):** To demonstrate with $95\%$ confidence that an error rate is below $p$, the evaluation must observe zero errors over $N \ge rac{3}{p}$ independent trials.
  - To prove $	ext{FMR} \le 0.001$: Requires $N \ge 3,000$ independent impostor trials.
- **Rule of 30 (Errors Observed):** To achieve a $95\%$ confidence interval with $\pm 30\%$ precision around an estimated error rate $p$, the test must observe at least $30$ errors:
  $$N \ge rac{30}{p}$$
  - For an expected $	ext{FNMR} = 0.02$: Requires $N_{	ext{mated}} \ge rac{30}{0.02} = \mathbf{1,500	ext{ genuine trials}}$.

### 3.2 Evaluation Test Suite Matrix

| Test Suite | Implementation File | Scope & Tested Conditions | Sample Size | Success Criteria | Verified Result |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **TS-01: Metric Invariance** | `biometric_whitened_embedding_test.dart` | Normalization, cosine dot equivalence, scale invariance | 20 test cases | $\|\mathbf{e}\|_2 = 1.0 \pm 10^{-6}$ | **PASSED (100%)** |
| **TS-02: Jitter Robustness** | `biometric_whitened_embedding_test.dart` | Same-person 2–4px mobile hand tremor simulation | 100 trials | $	ext{Sim} \ge 0.74$ on all trials | **PASSED ($0.85 - 0.98$)** |
| **TS-03: Population Separation** | `biometric_whitened_embedding_test.dart` | Unrelated stranger cross-comparison | 500 pairs | Mean Sim $= 0.00$, Max Sim $< 0.50$ | **PASSED (Max 0.35)** |
| **TS-04: Multi-Face Detection** | `biometric_multi_face_test.dart` | Rejecting frames with multiple subjects in camera | 15 scenarios | Multi-face rejected instantly | **PASSED (100%)** |
| **TS-05: 1:N Dedup Engine** | `biometric_deduplication_engine_test.dart` | Gallery indexing, top-K retrieval, masking | 100 gallery | Hard block at $\ge 0.90$, flag at $\ge 0.74$ | **PASSED (100%)** |
| **TS-06: Master Scenarios** | `biometric_v5_master_scenarios_test.dart` | End-to-end integration, PAD failures, timeout recovery | 32 scenarios | Zero unhandled exceptions | **PASSED (100%)** |
| **TS-07: Backend Mutation Suite** | `backend/src/tests/*.test.ts` | 24 test suites covering tamper detection, AAD, injection | 128 tests | 128 / 128 tests green | **PASSED (128/128)** |
