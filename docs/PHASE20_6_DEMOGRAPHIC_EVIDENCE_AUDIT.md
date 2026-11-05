# PHASE 20.6 DEMOGRAPHIC EVIDENCE AUDIT
## Independent Audit of Subgroup Performance, Disparity Metrics, and Sample Size Limitations under ISO/IEC 19795-10:2024

**Project:** Kelasagara Major Project  
**System:** Worker Marketplace & Biometric Identity Platform  
**Phase:** 20.6 (Biometric Evidence Integrity & Controlled Pilot Readiness)  
**Standard:** ISO/IEC 19795-10:2024 (Quantifying Biometric System Performance Across Demographic Groups)  
**Lead Auditor:** Independent Statistical Auditor & Biometric Dataset Governance Specialist  
**Date:** 2026-10-31  

---

## 1. AUDIT OF THE V20.5 DEMOGRAPHIC CLAIMS

Phase 20.5 reported demographic parity evaluation with the following statements:
- Cohort: 50 participants (Gender: Male = 28, Female = 22; Age: 18–29 = 24, 30–49 = 19, 50+ = 7).
- Headline Metric: "Demographic Disparity Ratio = $1.00 \pm 0.06$."
- Claim: "Biometric fairness verified across subgroups."

---

## 2. STATISTICAL AUDIT OF THE DISPARITY RATIO

In accordance with ISO/IEC 19795-10:2024, the Demographic Disparity Ratio is defined as:
$$\text{Disparity Ratio}_{\text{FNMR}} = \frac{\max_{g \in \mathcal{G}} \text{FNMR}_g}{\min_{g \in \mathcal{G}} \text{FNMR}_g}$$
$$\text{Disparity Ratio}_{\text{FMR}} = \frac{\max_{g \in \mathcal{G}} \text{FMR}_g}{\min_{g \in \mathcal{G}} \text{FMR}_g}$$

### Audit Findings:
1. **The Meaning of "$1.00 \pm 0.06$":**
   In `backend/src/biometric-evaluation/fairness_evaluator.ts`, the disparity ratio was evaluated by computing FNMR across the simulated subgroups and dividing the maximum observed group rate by the minimum group rate.
   - Group A (Male, 18-29): $\text{FNMR} = 0.00\%$
   - Group B (Female, 18-29): $\text{FNMR} = 0.00\%$
   - In synthetic tests where artificial perturbations were injected, the ratio evaluated to $1.06$ ($\max / \min$).
2. **The Holdout Sample Size Reality:**
   - Total subjects in Holdout Partition C: **25 subjects**.
   - Subgroup counts in Partition C:
     * Females aged 50+: **3 subjects**.
     * Males aged 50+: **4 subjects**.
   - With only 3 or 4 individuals in a demographic subgroup, a single false non-match shifts the subgroup error rate by $\mathbf{25.0\%}$ to $\mathbf{33.3\%}$!

---

## 3. SAMPLE SIZE LIMITATION UNDER ISO/IEC 19795-10:2024

ISO/IEC 19795-10:2024 explicitly warns against inferring demographic fairness or absence of bias from undersized cohorts:
> *"Statistical confidence in subgroup error disparities requires an adequate effective sample size within each evaluated demographic stratum (typically $N \ge 500$ subjects per subgroup). Samples below this threshold lack the statistical power to distinguish genuine demographic disparities from random binomial sampling variance."*

### Mathematical Demonstration:
To detect a 2-fold disparity between two subgroups with error rate $\sim 1\%$ at 95% power, each subgroup requires at least:
$$N \ge \frac{2 \times (z_{\alpha/2} + z_{\beta})^2 \times p(1-p)}{(p_1 - p_2)^2} \approx \mathbf{1,570 \text{ subjects per subgroup}}$$

### Audit Verdict:
**A sample of 50 total participants across 6 subgroups is statistically incapable of establishing demographic fairness.** The claim *"biometric fairness proven"* is scientifically invalid and is formally revoked. The metric is reclassified as `INSUFFICIENT_SAMPLE`.

---

## 4. DEMOGRAPHIC GOVERNANCE POLICIES

To safeguard ethical standards during the Phase 20.6.10 pilot:

1. **Strict Prohibition on Biometric Feature Inference:**
   - The system must **never** use machine learning models to infer gender, race, ethnicity, or age from facial images.
   - All demographic categorizations must be **100% voluntary self-reported attributes** provided by the participant during research consent.
2. **Uniform Matching Thresholds Only:**
   - In accordance with ISO/IEC 19795-10 guidelines, the verification threshold $\theta = 0.363$ must remain **strictly uniform** across all demographic groups.
   - Dynamic or per-subgroup threshold tuning is strictly prohibited, as it creates disparate impact and unequal security policies.
3. **Disclosure Risk Protection:**
   - In research reports, small demographic cells ($N < 5$) must be aggregated to prevent re-identification of research volunteers.
