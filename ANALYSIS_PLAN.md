# KELASAGARA BIOMATCH · FROZEN ANALYSIS PLAN (ANALYSIS_PLAN.md)
**Pre-Registration Reference:** `PREREG-S6.md` (Gate GATE-S6-03, GATE-S6-04)  
**Date:** 2026-10-10  
**Status:** FROZEN BEFORE IN-DOMAIN DATA INGESTION  

---

## 1. Frozen Estimands

1. **End-to-End False Non-Match Rate ($FNMR_{E2E}$):**
   $$FNMR_{E2E} = FTA + (1 - FTA) \cdot FNMR_{matcher}$$
   Where $FTA$ is the Failure-to-Acquire rate (frames rejected by ISO quality gate, landmark stability, or presentation attack defense). Every candidate failure counts toward the total error rate.

2. **False Match Rate ($FMR$) and Upper Bound:**
   When zero false matches are observed in $M$ independent impostor comparisons, the point estimate is reported as $< 3/M$ (Rule of Three upper 95% confidence bound), never "0.0%".

3. **Log-Likelihood Ratio Cost ($C_{llr}$):**
   $$C_{llr} = \frac{1}{2} \left[ \frac{1}{N_{gen}} \sum_{i=1}^{N_{gen}} \log_2 (1 + e^{-s_i}) + \frac{1}{N_{imp}} \sum_{j=1}^{N_{imp}} \log_2 (1 + e^{s_j}) \right]$$
   Evaluates discrimination capability independent of operating threshold, along with calibrated $minC_{llr}$.

4. **Demographic Subgroup Disparity Ratio:**
   $$Disparity = \frac{\max_{g} FNMR_g}{\min_{g} FNMR_g}$$
   Evaluated across:
   - Fitzpatrick Skin Tone Types IV–VI (South Asian demographic baseline)
   - Gender (Male / Female)
   - Capture Environment (Outdoor harsh sunlight vs Indoor diffuse)
   - Device Hardware (Low-end Android sensor vs Flagship tier)

---

## 2. Statistical Methodology

1. **Two-Way Clustered Bootstrap:**
   - Identity-level and capture-session-level clustering (subject $\times$ session) with $B = 2000$ bootstrap replicates.
   - Prevents variance underestimation arising from multiple frames per enrollment session.

2. **Confidence Intervals:**
   - Exact Clopper-Pearson or Wilson score intervals for binomial proportions.
   - Studentized pivotal bootstrap for continuous score metrics.

3. **Multiplicity Correction:**
   - Pre-registered primary hypothesis family corrected via Holm-Bonferroni step-down procedure.
   - Pre-specified family-wise error rate $\alpha = 0.05$.

4. **Practical Significance Margin:**
   - Equivalence margin set to $\Delta_{margin} = \pm 0.5\%$ TAR.
   - Statistical significance without practical relevance does not trigger an algorithmic or threshold revision.

5. **Missing Data & Unusable Frames:**
   - Complete intention-to-authenticate protocol: dropped frames, quality failures, and network timeouts are classified as system rejections ($FTA$).
   - No post-hoc data pruning or cherry-picking.

---

## 3. Planted-Truth Verification Protocol (Ticket A-02)
- Synthetic planted truth generator must execute 1000 Monte Carlo runs and achieve nominal 95% coverage $\in [0.93, 0.97]$.
- Intentionally introduced data leakage between tune and test partitions must trigger an immediate exception.
- Negative controls with randomized labels must fail with $AUC \in [0.48, 0.52]$.
