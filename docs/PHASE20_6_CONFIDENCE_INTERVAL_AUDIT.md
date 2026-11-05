# PHASE 20.6 CONFIDENCE INTERVAL AUDIT
## Rigorous Statistical Uncertainty Analysis: Two-Sided vs One-Sided Bounds, Sample Size Planning, and Pairwise Clustering

**Project:** Kelasagara Major Project  
**System:** Worker Marketplace & Biometric Identity Platform  
**Phase:** 20.6 (Biometric Evidence Integrity & Controlled Pilot Readiness)  
**Standard:** ISO/IEC 19795-1:2021 (§9 Statistical Estimation)  
**Lead Auditor:** Independent Statistical Auditor  
**Date:** 2026-10-31  

---

## 1. THE MATHEMATICAL DISTINCTION: TWO-SIDED VS ONE-SIDED BOUNDS

In biometric error rate estimation, failure to distinguish between two-sided confidence intervals and one-sided upper confidence bounds introduces significant ambiguity.

When testing for false match or false non-match rates where $k = 0$ errors are observed in $N$ independent trials:

### A. Two-Sided 95% Confidence Interval (Clopper-Pearson Exact):
A two-sided $100(1 - \alpha)\%$ interval splits significance $\alpha = 0.05$ equally into two tails of $\alpha / 2 = 0.025$:
$$\text{Lower Bound} = 0.0$$
$$\text{Upper Bound} = 1.0 - \left(\frac{\alpha}{2}\right)^{1/N} = 1.0 - (0.025)^{1/N}$$

### B. One-Sided 95% Upper Confidence Bound:
In operational risk assessment, engineers are concerned exclusively with the *maximum possible error rate* (worst-case bound), placing the full $\alpha = 0.05$ probability into the upper tail:
$$\text{One-Sided Upper Bound} = 1.0 - (\alpha)^{1/N} = 1.0 - (0.05)^{1/N}$$

---

## 2. EXACT RECOMPUTATION FOR $N = 300$ COMPARISONS

For the $N = 300$ impostor comparisons evaluated in Phase 20.5 with $k = 0$ false matches:

| Metric | Exact Formula | IEEE-754 Computation | Rounded Percentage |
| :--- | :--- | :--- | :--- |
| **Point Estimate** | $k / N = 0 / 300$ | `0.00000000` | $0.000\%$ |
| **Two-Sided 95% CI** | $[0, 1 - 0.025^{1/300}]$ | `[0.00000000, 0.01222097]` | $[0.00\%, 1.222\%]$ |
| **One-Sided 95% Upper Bound** | $1 - 0.05^{1/300}$ | `0.00993608` | $\mathbf{0.994\%}$ |
| **Rule of Three (Approximation)** | $3 / N = 3 / 300$ | `0.01000000` | $1.000\%$ |

### Critical Statistical Finding:
- The two-sided 95% upper bound is **$1.22\%$**.
- The one-sided 95% upper bound is **$0.994\%$**.
- **Neither bound substantiates a $1:10,000$ ($0.01\%$) False Match Rate claim.**
- Observing zero false matches in 300 comparisons establishes only that the error rate is very likely below $\sim 1\%$. Claiming $1:10,000$ accuracy from 300 trials is a mathematical fallacy.

---

## 3. SAMPLE SIZE PLANNING FOR $10^{-4}$ (1:10,000) FMR VALIDATION

To empirically demonstrate that an operational system achieves $\text{FMR} \le 10^{-4}$ (1 in 10,000) at 95% confidence with zero observed false matches ($k = 0$), the required number of independent trials $N$ is derived from:
$$1.0 - (1.0 - \text{FMR}_{\text{target}})^N \ge 1.0 - \alpha$$
$$(1.0 - \text{FMR}_{\text{target}})^N \le \alpha$$
$$N \ge \frac{\ln(\alpha)}{\ln(1.0 - \text{FMR}_{\text{target}})}$$

Using Taylor expansion $\ln(1 - x) \approx -x$ for small $x$:
$$N \ge \frac{\ln(\alpha)}{-\text{FMR}_{\text{target}}} = \frac{-\ln(0.05)}{0.0001} = \frac{2.99573227}{0.0001} \approx \mathbf{29,956 \text{ independent trials}}$$

### Verification:
With $N = 29,956$ and $k = 0$:
$$\text{One-Sided Upper Bound} = 1.0 - (0.05)^{1/29956} = 1.0 - 0.99990000 = \mathbf{0.00010000} \le 10^{-4}$$

### Conclusion:
A sample of 50 human participants producing 300 comparisons is approximately **100 times too small** to scientifically demonstrate a 1:10,000 FMR claim.

---

## 4. PAIRWISE DEPENDENCE & SUBJECT-LEVEL CLUSTERING

A fundamental violation of classical binomial statistics occurs when multiple pairwise comparisons are formed from the same finite pool of subjects. If 25 subjects are compared all-against-all, the resulting $25 \times 24 / 2 = 300$ pairs are **not independent observations**—an unusual facial geometry in a single individual influences 24 separate pairs.

To correct for this, Kelasagara implements the ISO/IEC 19795-1 §9.3.2 Design Effect clustering adjustment:
$$\text{Deff} = 1.0 + (m - 1)\rho$$
where:
- $m = \frac{\text{Pairwise Comparisons}}{\text{Unique Subjects}} = \frac{300}{25} = 12$ comparisons per subject.
- $\rho \approx 0.15$ is the intraclass correlation coefficient for facial feature projections.
- $\text{Deff} = 1.0 + (12 - 1) \times 0.15 = 1.0 + 1.65 = \mathbf{2.65}$.

### Effective Sample Size:
$$N_{\text{eff}} = \frac{N}{\text{Deff}} = \frac{300}{2.65} \approx \mathbf{113 \text{ effective independent trials}}$$

### Cluster-Adjusted Upper Bound:
$$\text{Cluster-Adjusted One-Sided Upper Bound} = 1.0 - (0.05)^{1/113} \approx \mathbf{2.61\%}$$

When clustered dependencies are properly taken into account, 300 comparisons across 25 subjects provide statistical certainty only up to an upper bound of **$2.61\%$**, underscoring the absolute necessity of recruiting expanded cohorts during the Phase 20.6.10 pilot.
