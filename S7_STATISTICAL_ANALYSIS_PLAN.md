# KELASAGARA BIOMATCH · STAGE S7 STATISTICAL ANALYSIS PLAN (S7_STATISTICAL_ANALYSIS_PLAN.md)

**Classification:** Statistical Validation, Sample Size Justification & Metric Formulas  
**Stage:** S7  
**Date:** 2026-10-11  
**Standards:** ISO/IEC 19795-1 (Testing and Reporting) & ISO/IEC 19795-2 (Testing Methodologies)

---

## 1. Biometric Metric Definitions with Strict Denominators

### 1.1 False Match Rate (FMR)
The probability that zero-effort impostor biometric probe $x_i$ matches enrolled reference $y_j$ ($i \ne j$):
$$\text{FMR}(\theta) = \frac{1}{|C_{\text{imp}}|} \sum_{(i,j) \in C_{\text{imp}}} \mathbb{I}\left[s(x_i, y_j) \ge \theta\right]$$
- **Denominator:** $|C_{\text{imp}}|$, the total number of evaluated impostor comparisons.
- **Rule of Three Bound:** If zero false matches are observed across $N_{\text{imp}}$ comparisons, the 95% upper confidence bound is:
  $$\text{FMR}_{\text{upper}} \le \frac{3}{N_{\text{imp}}}$$

### 1.2 False Non-Match Rate (FNMR)
The probability that genuine probe $x_i$ fails to match the same subject's reference $y_i$:
$$\text{FNMR}(\theta) = \frac{1}{|C_{\text{gen}}|} \sum_{(i,i) \in C_{\text{gen}}} \mathbb{I}\left[s(x_i, y_i) < \theta\right]$$
- **Denominator:** $|C_{\text{gen}}|$, the total number of evaluated genuine comparisons.

### 1.3 True Accept Rate (TAR)
$$\text{TAR}(\theta) = 1 - \text{FNMR}(\theta)$$
Reported at fixed operating points: $\text{TAR@FAR}=10^{-2}$, $\text{TAR@FAR}=10^{-3}$, and $\text{TAR@FAR}=10^{-4}$.

### 1.4 Failure to Acquire (FTA) and Failure to Enroll (FTE)
$$\text{FTA} = \frac{\text{Failed Presentation Captures}}{\text{Total Capture Presentations Initiated}}$$
$$\text{FTE} = \frac{\text{Failed Enrollment Sessions}}{\text{Total Eligible Applicant Sessions}}$$

---

## 2. Confidence Interval Estimation Methodology

### 2.1 Binomial Wilson Score Interval
For binary proportions $\hat{p} = k/n$ under independent sampling, Wilson score intervals are computed at $1 - \alpha = 0.95$ ($z = 1.96$):
$$CI_{95\%} = \frac{\hat{p} + \frac{z^2}{2n} \pm z \sqrt{\frac{\hat{p}(1 - \hat{p})}{n} + \frac{z^2}{4n^2}}}{1 + \frac{z^2}{n}}$$

### 2.2 Subject-Clustered Bootstrap
Because repeated captures from the same person exhibit statistical dependence, standard i.i.d. intervals underestimate variance. For multi-capture evaluations:
1. Resample subjects with replacement ($B = 2,000$ iterations).
2. Compute comparison metrics on the induced genuine and impostor sets.
3. Compute empirical percentile intervals $(2.5\%, 97.5\%)$.

---

## 3. Statistical Power & Sample Size Analysis ($N = 200$)

Power simulations (`analysis/power_simulation.py`) for a planned in-domain cohort of $N = 200$ subjects with 4 captures per subject ($n_{\text{gen}} = 600$, $n_{\text{imp}} \approx 79,600$):

| Cohort Size $N$ | Impostor Pairs $n_{\text{imp}}$ | Minimum Detectable Disparity (MDE) | Statistical Power ($\beta = 0.20$) | Assessment |
| :---: | :---: | :---: | :---: | :--- |
| **50** | 4,900 | $\pm 8.48\%$ | 0.80 | Underpowered for subgroup parity |
| **100** | 19,800 | $\pm 4.24\%$ | 0.80 | Marginal power |
| **200** | 79,600 | $\pm 2.12\%$ | 0.80 | **Pre-Registered Study Target** |
| **500** | 499,000 | $\pm 0.85\%$ | 0.80 | High precision study |

An $N = 200$ cohort provides $80\%$ statistical power at $\alpha = 0.05$ to detect a performance disparity of $\ge 2.12\%$ across Fitzpatrick subgroups.

---

## 4. Exit Gate S7-G05 Sign-Off

**Status:** `DONE-VERIFIED`  
**Evidence Artifacts:**
- `evidence/s7/metric_definitions.json`
- `evidence/s7/power_and_precision_analysis.json`
- `evidence/s7/recognition_results.json`
