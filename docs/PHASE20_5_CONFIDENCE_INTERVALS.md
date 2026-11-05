# PHASE 20.5 STATISTICAL CONFIDENCE INTERVALS
## Statistical Confidence, Sample Size Calculations, and Clustered Variance Analysis

**Project:** Kelasagara Major Project  
**System:** Worker Marketplace & Multi-Factor Biometric Identity Platform  
**Phase:** 20.5 (Advanced Biometric Scientific Validation Engine)  
**Parent Phase 20.4 Commit:** `41f95bf66bd09cda8ea63d3483e567b06ba6504e`  

---

## 1. MATHEMATICAL FORMULATION (CLOPPER-PEARSON)

For an observed $k$ errors across $N$ comparison trials, the exact two-sided $100(1 - \alpha)\%$ confidence interval $[p_L, p_U]$ is derived from the Beta distribution:

$$p_L = B\left(\frac{\alpha}{2}; k, N - k + 1\right)$$
$$p_U = B\left(1 - \frac{\alpha}{2}; k + 1, N - k\right)$$

### Rule of Three for Zero-Error Observations
When $k = 0$ errors are observed in $N$ independent trials:

$$p_L = 0$$
$$p_U = 1 - \left(\frac{\alpha}{2}\right)^{1/N} \approx 1 - 0.025^{1/N} \approx \frac{3.69}{N}$$
(Or for one-sided 95% bound, $p_U = 1 - 0.05^{1/N} \approx \frac{2.996}{N}$).

---

## 2. SAMPLE SIZE PLANNING FOR TARGET FMR $\le 10^{-4}$

To statistically demonstrate a target False Match Rate $\text{FMR} \le 10^{-4}$ (1 in 10,000) at 95% confidence with zero observed false matches:

$$N = \frac{\ln(0.05)}{\ln(1 - 0.0001)} \approx \frac{-2.99573}{-0.000100005} \approx \mathbf{29,956 \text{ independent comparisons}}$$

### Honest Statistical Assessment
- In the current university research cohort of 50 volunteers, $N_{\text{impostor}} = 300$ comparisons were executed in Partition C.
- With 0 false matches observed, the 95% confidence upper bound is:
  $$p_U = 1 - 0.025^{1/300} \approx \mathbf{0.0122 \ (1.22\%)}$$
- **Formal Scientific Conclusion**: The current empirical test demonstrates that $\text{FMR} \le 1.22\%$ at 95% confidence. Demonstrating an operational claim of $\text{FMR} \le 0.01\%$ (1 in 10,000) requires a future large-scale field deployment of at least 29,956 independent comparisons.

---

## 3. SUBJECT-CLUSTER VARIANCE ADJUSTMENT (ISO/IEC 19795-1 §9.3.2)

When pairwise comparisons share the same underlying human subjects, comparisons are not statistically independent. The design effect ($D_{\text{eff}}$) inflates variance:

$$D_{\text{eff}} = 1 + (m - 1)\rho$$

Where:
- $m$: Average cluster size (comparisons per subject).
- $\rho$: Intra-class correlation coefficient ($\approx 0.15$).

The effective sample size is adjusted:
$$N_{\text{eff}} = \frac{N}{D_{\text{eff}}}$$

The calculation engine in `ConfidenceIntervalCalculator.calculateClusterAdjusted()` automatically incorporates this inflation, preventing overconfident claims derived from correlated pairwise permutations.
