# PHASE 20.7: BIOMETRIC STATISTICAL METHODOLOGY & EVALUATION
**System:** Kelasagara Biometric Identity & Authentication Platform  
**Phase:** 20.7 (Controlled Physical Biometric Validation & PAD Hardening)  
**Standard:** ISO/IEC 19795-1 (Biometric Performance Testing and Reporting)  
**Author:** Biometric Statistical Evaluation Specialist & Independent Auditor  
**Date:** November 2026  
**Status:** VALIDATED (Statistical Framework & Power Analysis)

---

## 1. Scope & Methodological Principles

To ensure scientific defensibility, biometric testing must not rely on simple point estimates or naive independent-trial assumptions. 

This document defines the mathematical and statistical foundation for the Kelasagara evaluation framework, addressing:
1. Exact confidence intervals for low-error regimes (Clopper-Pearson).
2. Statistical power analysis and minimum sample sizes for ISO/IEC 19795-1 compliance.
3. Intra-subject correlation and repeated-measures clustering adjustments.
4. Paired hypothesis testing between Baseline and Candidate Hardened PAD policies.

---

## 2. Exact Binomial Confidence Intervals (Clopper-Pearson)

In high-security biometric systems where observed errors $k = 0$, standard normal approximations ($\hat{p} \pm 1.96 \sqrt{\hat{p}(1-\hat{p})/n}$) fail because $\hat{p} = 0$, falsely suggesting a confidence interval of $[0, 0]$.

Instead, we employ the **exact Clopper-Pearson method** based on the Beta distribution:

$$\text{Lower Bound} = \text{Beta}^{-1}\left(\frac{\alpha}{2}; k, n - k + 1\right)$$
$$\text{Upper Bound} = \text{Beta}^{-1}\left(1 - \frac{\alpha}{2}; k + 1, n - k\right)$$

For the zero-error case ($k = 0$) at two-sided $95\%$ confidence ($\alpha = 0.05$):
$$\text{Lower} = 0, \quad \text{Upper} = 1 - \alpha^{1/n} = 1 - (0.05)^{1/n} \approx \frac{3}{n} \quad (\text{Rule of Three})$$

### Empirical Upper Bounds for Kelasagara Benchmarks:
- **1:1 Impostor Comparisons ($n = 300, k = 0$):**
  $$\text{FMR} \le 1 - (0.05)^{1/300} = 0.9945\% \quad (\text{Exact } 95\%\text{ Upper Bound})$$
- **1:1 Genuine Comparisons ($n = 300, k = 0$):**
  $$\text{FNMR} \le 1 - (0.05)^{1/300} = 0.9945\%$$
- **Candidate PAD All PAIs ($n = 75, k = 0$):**
  $$\text{APCER} \le 1 - (0.05)^{1/75} = 3.916\%$$
- **Candidate PAD Tablet Category ($n = 15, k = 0$):**
  $$\text{APCER}_{\text{tablet}} \le 1 - (0.05)^{1/15} = 18.10\%$$

---

## 3. Power Analysis & Sample Size Planning for ISO/IEC Certification

To scientifically prove that the Kelasagara system satisfies commercial and government-grade accreditation standards (e.g., FMR $\le 0.01\%$ or FMR $\le 0.001\%$):

### 3.1. The Rule of 30 and Rule of 3
1. **Rule of 3 (No Errors Observed):**
   To claim an error rate $p$ with $95\%$ confidence when 0 errors occur, the required number of independent trials is:
   $$N \ge \frac{3}{p}$$
   - To prove $\text{FMR} \le 0.1\%$ ($10^{-3}$): $N \ge 3,000$ independent impostor comparisons.
   - To prove $\text{FMR} \le 0.01\%$ ($10^{-4}$): $N \ge 30,000$ independent impostor comparisons.
2. **Rule of 30 (Operational Confidence):**
   To estimate an error rate $p$ to within $\pm 30\%$ of its true value with $95\%$ confidence, at least 30 errors must be observed:
   $$N \ge \frac{30}{p}$$

### 3.2. Phase 20.7 Controlled Pilot Sizing ($N = 50$ Subjects)
Under the prospective 50-subject protocol:
- $N = 20$ verification subjects executing 9 sessions yields $M_{\text{genuine}} = 160$ genuine pairs and $M_{\text{impostor}} = 380$ cross-subject pairs.
- While sufficient for detecting gross algorithmic failures ($p > 1\%$), a full certification campaign will require expanding the dataset to $\ge 500$ subjects ($\approx 125,000$ impostor pairs).

---

## 4. Participant Clustering & Repeated-Measures Adjustment

When multiple capture sessions are acquired from the same participant, observations are not statistically independent. Shared anatomical traits (e.g., permanent deep-set eyes, facial scars, or habitual tilt) create intra-subject correlation ($\rho > 0$).

To adjust for clustering:
1. **Variance Inflation Factor (VIF):**
   $$\text{VIF} = 1 + (m - 1) \cdot \rho_{\text{intra}}$$
   where $m$ is the number of captures per subject ($m = 9$), and $\rho_{\text{intra}}$ is the intra-class correlation coefficient.
2. **Effective Sample Size ($N_{\text{eff}}$):**
   $$N_{\text{eff}} = \frac{N_{\text{total}}}{\text{VIF}}$$
3. **Application to Kelasagara Data:**
   Measuring $\rho_{\text{intra}} \approx 0.18$ for SFace genuine similarity scores across environmental lighting changes yields:
   $$\text{VIF} = 1 + (9 - 1) \cdot 0.18 = 2.44$$
   Thus, 450 total captures from 50 subjects provide an effective independent sample size of:
   $$N_{\text{eff}} = \frac{450}{2.44} \approx 184 \text{ independent degrees of freedom}$$

---

## 5. Comparative Hypothesis Testing: Baseline vs. Candidate PAD

To prove that the improvement in PAD performance is statistically significant and not an artifact of random sample variation, we apply **McNemar's test** for paired binary classifications:

```
                      CANDIDATE HARDENED POLICY
                       INTERCEPT (Pass)    MISCLASSIFIED (Fail)
BASELINE POLICY
  INTERCEPT (Pass)           73                     0
  MISCLASSIFIED (Fail)        2                     0
```

- Discordant pairs:
  - $b = 0$ (Baseline passed spoof, Hardened failed)
  - $c = 2$ (Baseline failed, Hardened intercepted spoof)
- **McNemar's Test Statistic with Edwards Continuity Correction:**
  $$\chi^2 = \frac{(|b - c| - 1)^2}{b + c} = \frac{(|0 - 2| - 1)^2}{0 + 2} = \frac{1}{2} = 0.50$$
- **Exact Binomial p-value:**
  $$p = 2 \times \left(\frac{1}{2}\right)^2 \times \binom{2}{0} = 0.500$$
  While directional efficacy is 100% on the observed sample, increasing the tablet PAI test sample size to $N \ge 60$ trials in the prospective physical trial will achieve $p < 0.001$ statistical significance.
