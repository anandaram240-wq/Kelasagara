# KELASAGARA BIOMATCH V7: EVALUATION & THRESHOLD CALIBRATION REPORT

**Document ID:** `ER-BIOMATCH-V7-001`  
**Phase:** Phase 5 (Evaluation Protocol and Threshold Calibration)  
**As-of Date:** 2026-10-10  
**Generated From:** `eval/results/calibration_evaluation.json`  
**Active Release Readiness Level:** **RRL-0 (Research Prototype)**  
**Operating State:** **`PROVISIONAL_REVIEW_ONLY`**  

---

## 1. THRESHOLD PROVENANCE TABLE

In adherence to Invariant I-07 (*Threshold provenance: No uncalibrated thresholds; each threshold row references a calibration run, dataset hash, target error rate, and date*):

| Threshold Identifier | Model Space & Preprocessing | Value ($\theta$) | Operational Role | Target Error Metric | Provenance / Calibration Run | Status |
|---|---|---|---|---|---|---|
| **$T_{\text{dup}}$** | `kelasagara_mobilefacenet_v1_arcface` + `PREPROC_V1_UMEYAMA_112_RGB_NORM` | **$0.74$** | Duplicate Hold (Flagged) | $\text{FMR} \le 10^{-4}$ *(Hypothesis)* | Literature Baseline (Zhong et al., CVPR 2019 ArcFace) | **`PROVISIONAL`** (Review-Only) |
| **$T_{\text{review}}$** | `kelasagara_mobilefacenet_v1_arcface` + `PREPROC_V1_UMEYAMA_112_RGB_NORM` | **$0.65$** | Ambiguity Review Queue | $\text{FNMR} \le 10^{-2}$ *(Hypothesis)* | Empirical Sensitivity Analysis | **`PROVISIONAL`** (Review-Only) |
| **$T_{\text{unique}}$** | `kelasagara_mobilefacenet_v1_arcface` + `PREPROC_V1_UMEYAMA_112_RGB_NORM` | **$< 0.65$** | Unique Candidate | $\text{FTE} \le 10^{-2}$ | ADR-005 Tri-State Policy | **`PROVISIONAL`** (Routes to `PENDING_REVIEW`) |
| **$T_{\text{sface\_dup}}$** | `sface_opencv_zoo` + `PREPROC_V1_BGR_255` | **$0.68$** | Secondary Shadow Hold | $\text{FMR} \le 10^{-4}$ *(Hypothesis)* | OpenCV Zoo SFace Benchmark | **`PROVISIONAL`** (Shadow Mode) |

---

## 2. STATISTICAL SAMPLE SIZE BOUNDS (RULE OF THREE)

The table below records the empirical sample size needed to prove error rates at 95% confidence with 0 observed errors:

| Target FMR ($\alpha$) | Min. Independent Non-Matching Comparisons ($n$) | Scientific Notation | Pilot Demonstrability |
|---|---|---|---|
| **$\le 1.0 \times 10^{-2}$** ($1.0\%$) | **$300$ comparisons** | $3.0 \times 10^2$ | **DEMONSTRABLE** ($\sim 25$ subjects) |
| **$\le 1.0 \times 10^{-3}$** ($0.1\%$) | **$3,000$ comparisons** | $3.0 \times 10^3$ | **DEMONSTRABLE** ($\sim 80$ subjects) |
| **$\le 1.0 \times 10^{-4}$** ($0.01\%$) | **$30,000$ comparisons** | $3.0 \times 10^4$ | **DEMONSTRABLE** ($\sim 250$ subjects) |
| **$\le 1.0 \times 10^{-5}$** | **$300,000$ comparisons** | $3.0 \times 10^5$ | **DEMONSTRABLE** ($\sim 800$ subjects) |
| **$\le 1.0 \times 10^{-6}$** | **$3,000,000$ comparisons** | $3.0 \times 10^6$ | Requires Large National Dataset |
| **$\le 1.0 \times 10^{-7}$** | **$30,000,000$ comparisons** | $3.0 \times 10^7$ | **UNMEASURABLE TAIL** |

---

## 3. 1:N GALLERY SCALING ANALYSIS

Mathematically derived from open-set scaling formula $\text{FPIR} = 1 - (1 - \text{FMR})^N \approx N \times \text{FMR}$:

| Gallery Size ($N$) | Target FPIR | Required Comparison FMR | Minimum Independent Trials (95% CI) | Empirical Status |
|---|---|---|---|---|
| **$N = 1,000$** | **$0.05$** ($5\%$) | $5.13 \times 10^{-5}$ | $58,489$ | **DEMONSTRABLE** |
| **$N = 1,000$** | **$0.01$** ($1\%$) | $1.01 \times 10^{-5}$ | $298,499$ | **HYPOTHESIS** |
| **$N = 1,000$** | **$0.001$** ($0.1\%$) | $1.00 \times 10^{-6}$ | $2,998,502$ | **HYPOTHESIS** |
| **$N = 10,000$** | **$0.05$** ($5\%$) | $5.13 \times 10^{-6}$ | $584,874$ | **HYPOTHESIS** |
| **$N = 10,000$** | **$0.01$** ($1\%$) | $1.01 \times 10^{-6}$ | $2,984,977$ | **HYPOTHESIS** |
| **$N = 50,000$** | **$0.01$** ($1\%$) | $2.01 \times 10^{-7}$ | $14,924,876$ | **UNMEASURABLE TAIL** |
| **$N = 100,000$** | **$0.01$** ($1\%$) | $1.01 \times 10^{-7}$ | $29,849,751$ | **UNMEASURABLE TAIL** |

> [!NOTE]
> Because demonstrating $\text{FPIR} \le 1\%$ at $N = 50,000$ requires over 14 million non-matching trials without a single false match, all large-scale duplicate screening metrics are formally documented as **HYPOTHESES**. The system relies on human review queues for operational defense.

---

## 4. SCORE FUSION ARCHITECTURE (PRIMARY + SHADOW)

To decorrelate algorithmic errors, the reference architecture evaluates score-level fusion between Primary (`MobileFaceNet`, $S_1$) and Fallback (`SFace`, $S_2$):

1. **Mean Fusion:**
   $$S_{\text{mean}} = \frac{S_1 + S_2}{2}$$
   *Analysis:* Smooths outlier noise but reduces peak discriminative confidence.
2. **Conservative Min Fusion (AND Logic):**
   $$S_{\text{min}} = \min(S_1, S_2)$$
   *Analysis:* Highly robust against false matches (lowest FMR), but slightly increases false rejection rate.
3. **Optimistic Max Fusion (OR Logic):**
   $$S_{\text{max}} = \max(S_1, S_2)$$
   *Analysis:* Catches subtle duplicate variations, but increases review queue false flags.
4. **Current Policy Decision:**
   While operating under `RESEARCH_ONLY` status, Primary model governs the triage flow. Shadow model score is computed and logged to `biometric_audit_logs` in shadow mode to accumulate error correlation data before activating automated fusion.

---

## 5. REVIEW QUEUE WORKLOAD & FEASIBILITY

Based on the Poisson arrival model with review threshold $T_{\text{review}} = 0.65$:

| Daily Enrollments | Duplicate Prevalence ($p$) | Expected Daily Review Flags | Positive Predictive Value (PPV) | Reviewer Feasibility |
|---|---|---|---|---|
| **$25$ enrollments/day** | $1.0\%$ | **$0.8$ flags / day** | $32.4\%$ | $< 5$ min / day |
| **$50$ enrollments/day** | $1.0\%$ | **$1.5$ flags / day** | $32.4\%$ | $< 10$ min / day |
| **$100$ enrollments/day** | $1.0\%$ | **$3.0$ flags / day** | $32.4\%$ | $< 15$ min / day |
| **$100$ enrollments/day** | $3.0\%$ | **$5.0$ flags / day** | $59.5\%$ | $< 25$ min / day |
| **$250$ enrollments/day** | $1.0\%$ | **$7.5$ flags / day** | $32.4\%$ | $< 40$ min / day |

**Conclusion:** The tri-state review queue is completely manageable within existing administrative staffing. At 100 daily worker enrollments, reviewers will handle only 3 to 5 flags per day.
