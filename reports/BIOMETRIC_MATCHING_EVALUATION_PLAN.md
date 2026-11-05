# KELASAGARA BIOMETRIC ENGINE
## Biometric Matching Evaluation Plan & Statistical Protocol

**Document Date:** October 23, 2026  
**Status:** PROTOCOL RATIFIED — FIELD TRIALS PENDING  
**Governing Standards:** ISO/IEC 19795-1:2021, ISO/IEC 19795-2:2015, NIST FRTE (Face Recognition Technology Evaluation)  

---

## 1. Truth in Biometric Testing: Synthetic Tests vs. Empirical Human Trials

### 1.1 Integrity Disclosure (Contradiction C-07 Reconciled)
A foundational principle of KELASAGARA V12.0 is **absolute scientific honesty**:
- The test suites in `test/biometric_*.dart` and `backend/dist/tests/` verify **software engineering invariants**: vector normalization, bounds checking, threshold comparisons, Umeyama alignment on synthetic coordinates, replay prevention, and AES-GCM envelope encryption.
- Passing 100% of these tests confirms that the code operates without crashes and executes mathematical formulas correctly.
- **It does NOT prove 0.00% operational biometric error in the field.** Zero errors observed across 100 or 500 synthetic test runs cannot be extrapolated to zero real-world error. Per the statistical rule-of-three, zero errors in 500 independent trials provides an upper 95% confidence bound of $0.6\%$ error; zero in 100 provides an upper bound of $3.0\%$.
- Real-world human demographic accuracy across diverse Karnataka gig worker populations is formally classified as **NOT YET VALIDATED IN PRODUCTION**, requiring the controlled field evaluation protocol detailed below.

---

## 2. Statistical Definitions & Error Rate Formulas

Per ISO/IEC 19795-1:2021:

### 2.1 1:1 Identity Verification Metrics
1. **False Non-Match Rate ($FNMR$):**
   $$FNMR(\tau) = \frac{1}{|G|} \sum_{(\mathbf{r}, \mathbf{p}) \in G} \mathbb{I}\Big(\langle \mathbf{r}, \mathbf{p} \rangle < \tau\Big)$$
   Where $G$ is the set of genuine comparison pairs (same individual across distinct capture sessions).
   *Target: $FNMR \le 0.02$ ($2.0\%$) at $\tau = 0.38$.*

2. **False Match Rate ($FMR$):**
   $$FMR(\tau) = \frac{1}{|I|} \sum_{(\mathbf{r}, \mathbf{p}) \in I} \mathbb{I}\Big(\langle \mathbf{r}, \mathbf{p} \rangle \ge \tau\Big)$$
   Where $I$ is the set of zero-effort impostor comparison pairs (different individuals).
   *Target: $FMR \le 10^{-3}$ ($0.1\%$) at $\tau = 0.38$.*

3. **Failure-to-Acquire Rate ($FTAR$):**
   Fraction of capture attempts that fail ISO 29794-5 quality gates (e.g., poor focus, excessive yaw, low lighting).
   *Target: $FTAR \le 0.03$ ($3.0\%$).*

---

## 3. Cumulative Risk Analysis for 1:N Duplicate Screening

Let $FMR_1(\tau)$ be the false match rate for a single 1:1 comparison at threshold $\tau$.
When screening a new applicant against an enrolled gallery of size $N$, the probability of at least one false collision across the gallery is:
$$FMR_N(\tau) = 1 - \Big(1 - FMR_1(\tau)\Big)^N \approx N \times FMR_1(\tau)$$

### 3.1 Impact on Platform Scale

| Gallery Size ($N$) | Single Comparison $FMR_1(\tau = 0.38)$ | Gallery False Match Rate $FMR_N$ | Impact on Worker Onboarding |
| :---: | :---: | :---: | :---: |
| 10 | 0.001 (0.1%) | 1.0% | ~1 in 100 workers wrongly flagged |
| 100 | 0.001 (0.1%) | 9.5% | ~1 in 10 workers wrongly flagged |
| 500 | 0.001 (0.1%) | 39.4% | ~4 in 10 workers wrongly flagged |
| 1,000 | 0.001 (0.1%) | **63.2%** | **Majority of legitimate workers blocked!** |
| 10,000 | 0.001 (0.1%) | **99.99%** | **Total platform deadlock** |

**Conclusion:** The 1:1 threshold ($\tau = 0.38$) must NEVER be used for 1:N deduplication. The deduplication warning threshold is calibrated to $\tau = 0.74$, and the hard-block threshold is $\tau = 0.90$.

---

## 4. Empirical Field Evaluation Protocol (Indian Demographics)

### 4.1 Target Cohort Representation
To ensure equitable performance across Karnataka's gig workforce:
- **Demographic Diversity:** Gender balance (minimum 40% female participants); age distribution spanning 18 to 65 years.
- **Melanin & Skin Tone Variance:** Fitzpatrick scale IV through VI representation (South Asian baseline).
- **Physical Occlusions:** Natural occlusions common in field labor: turbans, hijabs, bindis, spectacles, facial hair variations, and dust.
- **Ambient Lighting:** Unconstrained field lighting: harsh direct sunlight ($> 80,000\text{ lux}$), dimly lit indoor corridors ($< 50\text{ lux}$), and fluorescent warehouse environments.

### 4.2 Statistical Confidence Bounds
Per ISO/IEC 19795-1 §9.3, all empirical evaluations must report **95% Clopper-Pearson binomial confidence intervals**:
$$\text{CI}_{95\%} = \left[ B\left(\frac{\alpha}{2}; k, n - k + 1\right), B\left(1 - \frac{\alpha}{2}; k + 1, n - k\right) \right]$$
No metric based on fewer than 30 independent impostor or genuine trials may be cited as definitive evidence.
