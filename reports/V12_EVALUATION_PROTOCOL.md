# KELASAGARA BIOMETRIC ENGINE V12.0
## Evaluation Protocol: ISO/IEC 19795-1 & NIST FRTE Standards

**Date:** October 23, 2026  
**Status:** PROTOCOL FORMALIZED & RATIFIED  
**Governing Standards:** ISO/IEC 19795-1:2021, ISO/IEC 19795-2:2015, ISO/IEC 30107-3:2023, NIST FRTE 1:1 & 1:N  

---

## 1. Truth in Testing: Synthetic Code Tests vs. Empirical Biometric Trials (Contradiction C-07)

### 1.1 The Critical Distinction
A rigorous forensic audit must distinguish between:
1. **Software Engineering Unit/Integration Tests:**
   - Verify that functions do not crash, vectors are $L_2$-normalized to $1.0$, nonces expire after 120 seconds, and malicious payloads are rejected with HTTP 400.
   - The test files in `test/` (e.g. `biometric_whitened_embedding_test.dart`, `biometric_v5_master_scenarios_test.dart`) test mathematical routines against synthetic geometric shapes and simulated Gaussian noise ($\sigma \in [0.01, 0.05]$).
   - Passing these tests proves **code correctness**, NOT operational zero-error biometric accuracy.
2. **Operational Biometric Evaluations (ISO/IEC 19795-1):**
   - Measure empirical biometric error rates across large-scale, demographically diverse human populations under real-world ambient conditions (outdoor glare, low lighting, motion blur, Indian facial morphology, turban/hijab/bindi occlusions, sensor variety).
   - In V12.0, we make NO unfounded claims of "0.00% False Match Rate" in production. All performance metrics must cite peer-reviewed benchmark datasets (LFW, IJB-C, CASIA-WebFace, OFIQ) and statistical confidence bounds.

---

## 2. ISO/IEC 19795-1:2021 Testing Methodology

The Kelasagara Biometric Engine evaluation protocol mandates measuring four standard operational metrics:

### 2.1 Primary Biometric Error Metrics
1. **False Non-Match Rate ($FNMR$):**
   $$FNMR(\tau) = \frac{\text{Number of genuine comparisons with score } < \tau}{\text{Total genuine comparisons}}$$
   Measures the probability that a legitimate registered worker is erroneously rejected during login or shift check-in.
   *Target: $FNMR \le 0.02$ ($2.0\%$) at $\tau = 0.38$.*

2. **False Match Rate ($FMR$):**
   $$FMR(\tau) = \frac{\text{Number of zero-effort impostor comparisons with score } \ge \tau}{\text{Total impostor comparisons}}$$
   Measures the probability that an impostor is erroneously verified as another worker.
   *Target: $FMR \le 10^{-3}$ ($0.1\%$) at $\tau = 0.38$.*

3. **Failure-to-Acquire Rate ($FTAR$):**
   $$FTAR = \frac{\text{Number of capture attempts failing ISO 29794-5 quality gates}}{\text{Total capture attempts}}$$
   Measures capture friction (e.g., poor lighting, motion blur, distance $> 1\text{m}$).
   *Target: $FTAR \le 0.03$ ($3.0\%$) with guidance feedback.*

4. **Failure-to-Enroll Rate ($FTER$):**
   Fraction of users who cannot complete the multi-frame registration workflow.
   *Target: $FTER \le 0.005$ ($0.5\%$).*

---

## 3. ISO/IEC 30107-3:2023 Presentation Attack Detection (PAD) Protocol

PAD efficacy must be evaluated across Presentation Attack Instruments (PAIs):

### 3.1 PAI Species Tested
- **Level 1 (Paper & Screen):**
  - High-resolution color photo printout (200 GSM glossy & matte paper).
  - Digital screen replay (1080p AMOLED smartphone, 4K iPad Pro, 60Hz/120Hz refresh).
  - Curved / wrapped print presentation (simulating facial curvature).
  - Print attack with eyeholes cut out (simulating natural blinks).
- **Level 2 (3D & Silicone):**
  - 3D curved mannequin and realistic latex mask.
  - Video deepfake playback with synthetic blink injection.

### 3.2 Standard PAD Metrics
1. **Attack Presentation Classification Error Rate ($APCER$):**
   $$APCER = \frac{\text{Number of attack presentations classified as bona fide}}{\text{Total attack presentations}}$$
   *Target: $APCER \le 5.0\%$ for Level 1 attacks.*

2. **Bona Fide Presentation Classification Error Rate ($BPCER$):**
   $$BPCER = \frac{\text{Number of bona fide (live human) presentations classified as attacks}}{\text{Total bona fide presentations}}$$
   *Target: $BPCER \le 2.0\%$.*

---

## 4. Benchmark Dataset Protocol

| Dataset | Sample Size | Primary Role | Demographics / Conditions |
| :--- | :---: | :--- | :--- |
| **LFW (Labeled Faces in the Wild)** | 13,233 images | Baseline 1:1 verification calibration | Standard unconstrained benchmark |
| **IJB-C (IARPA Janus Benchmark-C)** | 138,000 images | High-FAR calibration ($\text{TAR} @ \text{FAR}=10^{-4}$) | Extreme pose, lighting, resolution |
| **OFIQ (ISO/IEC 29794-5 Reference)** | 10,000 crops | Quality metrics calibration (IPD, sharpness) | Controlled ISO capture standards |
| **CelebA-Spoof / CASIA-SURF** | 625,000 frames | Level 1 & 2 Presentation Attack validation | Print, replay, paper cutouts, masks |
| **Kelasagara Indian Demographic Corpus** | 2,500 pairs | Regional validation (Karnataka worker baseline) | High melanin, outdoor sunlight, dust, headwear |

---

## 5. Statistical Rigor: Clopper-Pearson Confidence Intervals

Per ISO/IEC 19795-1 §9.3, all reported error rates must specify $95\%$ binomial confidence intervals:
$$\text{CI}_{95\%} = \left[ B\left(\frac{\alpha}{2}; k, n - k + 1\right), B\left(1 - \frac{\alpha}{2}; k + 1, n - k\right) \right]$$
No metric based on fewer than 30 independent impostor or genuine trials may be cited as definitive evidence.
