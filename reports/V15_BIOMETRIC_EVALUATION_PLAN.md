# KELASAGARA V15.0 BIOMETRIC ENGINE AUDIT
# REPORT 04: BIOMETRIC EVALUATION PROTOCOL & STATISTICAL METHODOLOGY

**Document ID:** KLS-V15-EVAL-PLAN-001  
**Classification:** SCIENTIFIC EVALUATION PROTOCOL  
**Standards Conformance:** ISO/IEC 19795-1:2021 (Biometric Performance Testing and Reporting), ISO/IEC 29794-5:2025 (Face Image Quality)  
**Author:** Principal Biometric Evaluator & Statistical Systems Architect  
**Date:** 2026-10-23  

---

## 1. OBJECTIVE & MOTIVATION

Prior project reports cited an accuracy metric of "99.60% on LFW" as justification for production identity gating. Such claims conflate laboratory benchmark scores on standardized academic datasets with real-world system accuracy on target user demographics.

The objective of this protocol is to define an empirical, statistically sound biometric evaluation plan designed specifically for the Kelasagara operating environment: Indian gig economy workers operating low-to-mid-tier Android smartphones under challenging ambient conditions.

---

## 2. RECOGNITION PIPELINE ARCHITECTURE

The authoritative face recognition pipeline consists of:
1. **Face Detection & Alignment:** YuNet (`face_detection_yunet_2023mar.onnx`), extracting bounding boxes and 5 facial landmarks (two eyes, nose tip, two mouth corners).
2. **Affine Normalization:** Similarity transform mapping detected landmarks to canonical coordinates ($112 \times 112$ RGB).
3. **Feature Extraction:** OpenCV SFace (`face_recognition_sface_2021dec.onnx`), outputting a 128-dimensional embedding vector $\vec{x} \in \mathbb{R}^{128}$.
4. **L2 Hyperspherical Projection:** $\vec{u} = \frac{\vec{x}}{\|\vec{x}\|_2}$, such that $\|\vec{u}\|_2 = 1.0$.
5. **Comparator:** Dot product $\text{Sim}(\vec{u}_1, \vec{u}_2) = \vec{u}_1 \cdot \vec{u}_2 \in [-1.0, 1.0]$.

---

## 3. STATISTICAL CRITIQUE: THE INDEPENDENCE FALLACY IN 1:N MATCHING

A common theoretical assumption in biometric literature models $1:N$ False Match Rate ($FMR_N$) as a function of the $1:1$ False Match Rate ($FMR_1$) assuming statistical independence across gallery templates:

$$FMR_N = 1 - (1 - FMR_1)^N \approx N \times FMR_1 \quad (\text{for small } FMR_1)$$

### Why this assumption fails in real-world deployments:
1. **Biometric Correlation (Doddington's Zoo):**  
   Human facial features are not uniformly distributed on $\mathbb{S}^{127}$. Certain individuals ("Lambs" and "Wolves") possess facial morphology that easily yields high false match scores against large subsets of the population.
2. **Demographic & Phenotypic Clustering:**  
   In a localized worker pool (e.g., South Asian / Indian gig workers in Karnataka), facial structure, skin pigmentation (Fitzpatrick IV–VI), epicanthic folds, and facial hair patterns exhibit shared feature density. Consequently, gallery samples are clustered rather than independently dispersed.
3. **Sensor & Acquisition Correlation:**  
   Images captured with low-cost CMOS sensors with high fixed-pattern noise (FPN), aggressive chromatic aberration, or similar focal distortion introduce systematic embedding shifts that correlate probe and gallery samples.
4. **Empirical Rule of Thumb:**  
   As demonstrated in NIST FRVT reports (NIST IR 8271), real-world $1:N$ error rates scale substantially worse than the theoretical independent model. Empirical evaluation on real gallery distributions is strictly required.

---

## 4. REPRESENTATIVE DATASET PROTOCOL

To establish valid operational thresholds, an evaluation trial must be conducted using a representative, consent-governed cohort.

### 4.1 Cohort Demographic Requirements
- **Sample Size:** Minimum $N = 500$ distinct subjects (providing $500$ genuine pairs and $124,750$ non-mate comparisons).
- **Demographics:** 100% representative of target Indian gig economy demographics:
  - Age distribution: 18–60 years.
  - Skin tones: Fitzpatrick skin phototypes IV, V, and VI.
  - Facial adornments: Turbans, bindis, spectacles, mustaches, and beards.

### 4.2 Acquisition Environmental Scenarios
Each participant must provide 5 distinct captures under varied operational conditions:
- **Condition A (Baseline):** Diffuse indoor lighting (300–500 lux), neutral expression.
- **Condition B (Harsh Outdoor Sunlight):** Direct direct sunlight (>10,000 lux) causing harsh facial shadows.
- **Condition C (Low-Light Night):** Evening ambient lighting (<50 lux), typical of night shifts.
- **Condition D (Atmospheric Particulate/Dust):** Simulated construction/logistics conditions, perspiration, or slight dust accumulation.
- **Condition E (Pose & Expression Variation):** $\pm 10^\circ$ yaw/pitch, smiling, or speaking expression.

### 4.3 Hardware Heterogeneity
Captures must be obtained across a stratified distribution of budget Android hardware:
- Tier 1 (Low Budget): 5MP–8MP front camera (e.g., Redmi A-series, Realme C-series, Samsung M-series).
- Tier 2 (Mid-range): 12MP–16MP front camera.

---

## 5. PERFORMANCE METRIC OBJECTIVES

The trial will evaluate the system against the following operational criteria per ISO/IEC 19795-1:

| Metric | Target Operational Ceiling | Scientific Justification |
| :--- | :--- | :--- |
| **False Match Rate (FMR / FAR)** | $\le 0.1\%$ ($1 \text{ in } 1,000$) | Prevents credential-sharing fraud between different workers. |
| **False Non-Match Rate (FNMR / FRR)** | $\le 3.0\%$ ($3 \text{ in } 100$) | Ensures legitimate workers are not repeatedly denied shift clock-in. |
| **Failure to Acquire (FTA)** | $\le 1.0\%$ | Quality filtering must not reject authentic workers with darker skin or low-end cameras. |
| **Duplicate Screen FMR ($N=500$)** | $\le 1.0\%$ | Limits manual review burden on platform compliance teams. |

---

## 6. CALIBRATION RUNBOOK

1. **Similarity Matrix Calculation:** Compute the complete $2,500 \times 2,500$ pairwise similarity matrix.
2. **Distribution Extraction:** Separate genuine similarity scores ($S_{\text{gen}}$) and impostor similarity scores ($S_{\text{imp}}$).
3. **ROC / DET Curve Generation:** Plot False Non-Match Rate versus False Match Rate across the threshold range $\tau \in [0.0, 1.0]$ in increments of $0.001$.
4. **Threshold Selection:**
   - Set $\tau_{\text{verify}}$ at the point where $\text{FMR} = 0.001$ ($0.1\%$). Verify that $\text{FNMR} \le 0.03$.
   - Set $\tau_{\text{dup}}$ where $1:N$ false alarm rate is $\le 1\%$ over gallery size $N$.
5. **Formal Approval:** Document calibrated thresholds, record empirical ROC graphs, and submit for security sign-off before enabling `PRODUCTION_BIOMETRIC_CALIBRATION_APPROVED`.
