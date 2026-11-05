# KELASAGARA V18: Gate G-01 Dual-Subspace Biometric Calibration Report

- **Document ID:** `KLS-V18-G01-CALIBRATION`
- **Production Calibration Approved:** `false` (`PRODUCTION_BIOMETRIC_CALIBRATION_APPROVED = false`)
- **Application Gate Mode:** `CONTROLLED_TEST_BUILD_ONLY`
- **Population-Level Accuracy Validation Status:** `NOT VALIDATED` (Software-level harness verified; authorized real-human dataset manifest required for empirical population sign-off)

---

## 1. Representation Inspection & Technical Audit

### 1.1 Track A: Canonical SFace Baseline (`face_recognition_sface_2021dec`)
- **Representation:** 128-D L2-normalized deep convolutional appearance embedding ($\mathbf{e}_{\text{sface}} \in \mathbb{S}^{127}$).
- **Preprocessing:** 5-point similarity alignment to $112 \times 112$ BGR crop.
- **Canonical Thresholds:** $\tau_{\text{verify}} = 0.363$, $\tau_{\text{dup}} = 0.74$, $\tau_{\text{hard}} = 0.90$.
- **Role:** **Authoritative Identity-Recognition Baseline.**

### 1.2 Track B: `Dense500LandmarkEngineV3` (`kelasagara_biomatch_v3_dense512`)
- **Representation:** 512-D full topological vector ($\mathbf{e}_{\text{full}} \in \mathbb{S}^{511}$) and 256-D periocular vector ($\mathbf{e}_{\text{peri}} \in \mathbb{S}^{255}$).
- **Preprocessing:** 3D orthographic Procrustes alignment of 478 MediaPipe/ML Kit facial mesh vertices + 22 synthetic centroids, followed by analytic Z-score whitening and seeded random Haar projection.
- **Forensic Finding:** While mathematical whitening resolves the v1 "First-Orthant Cone" bug (centering random vectors near $0.0$), the underlying input features are purely geometric ratios derived from a 3D morphable surface mesh detector. Mesh detectors regularize vertex placements toward a low-dimensional statistical shape prior and discard high-entropy identity cues (skin pore micro-texture, iris patterns, brow hair distribution, and vascular pigment). Consequently, a landmark-derived vector is **not** equivalent to a learned deep metric-learning identity embedding.

### 1.3 Track C: Calibrated Logistic Log-Likelihood Ratio (LLR) Dual Fusion
- **Methodology:** Replaces arbitrary raw score addition with a supervised logistic regression LLR combiner trained strictly on the `CALIBRATION` partition:
  $$\text{logit } P(\text{Genuine}) = \beta_0 + w_1 s_{\text{sface}} + w_2 (1 - \alpha_{\text{occ}}) s_{\text{full}} + w_3 \alpha_{\text{occ}} s_{\text{peri}} + w_4 (s_{\text{sface}} \cdot s_{\text{peri}})$$
- **Threshold Selection Policy:** Operating thresholds ($\tau_{\text{verify}} < \tau_{\text{dup}} < \tau_{\text{hard}}$) are selected on the disjoint `VALIDATION` partition and evaluated on `HELD_OUT_EVAL`.

---

## 2. Evaluation Integrity & Statistical Uncertainty Protocol

1. **Subject & Session Disjointness:** `verifyPartitionDisjointness()` enforces zero overlap of `subjectId` and `sessionId` across `CALIBRATION`, `VALIDATION`, and `HELD_OUT_EVAL`.
2. **Clustered Uncertainty:** Every ROC/DET operating point reports both Wilson 95% confidence intervals and **Subject-Clustered Bootstrap 95% intervals ($B = 1000$)** to account for correlated pairwise comparisons sharing the same subject.
3. **Sample-Size Guardrail:** By the statistical Rule of Three, bounding $\text{FMR} \le 0.1\%$ ($10^{-3}$) at 95% confidence requires at least $N_{\text{impostor}} \ge 3,000$ independent impostor comparisons even when $0$ false matches are observed. Any run with fewer than $3,000$ impostor trials or synthetic vectors is automatically flagged as `INSUFFICIENT_SAMPLE_SIZE_FOR_0_1_PCT_FMR` or `SOFTWARE_HARNESS_VERIFIED_POPULATION_NOT_VALIDATED`.

---

## 3. Architectural Recommendation

1. **Retain SFace as the Sole Authoritative Identity Matcher:** Keep SFace (128-D ONNX) as the primary 1:1 and 1:N identity representation in production.
2. **Designate `Dense500LandmarkEngineV3` as an ISO/IEC 29794-5 Quality, Pose & ISO/IEC 30107-3 PAD Signal:** Use the 3D landmark mesh strictly for:
   - Pre-alignment quality gating (head roll/pitch/yaw bounds, interpupillary pixel density).
   - Anatomical zone occlusion estimation ($\alpha_{\text{occ}}$ for beard/turban detection).
   - 3D nasal-zygomatic perspective parallax liveness verification.
3. **Hold Dual-Subspace Score Fusion in Experimental Research Status:** Do not enable Track C score fusion in production until an authorized, de-identified field dataset of at least $300$ subjects ($3,000+$ impostor trials across varied beard/turban conditions) demonstrates a statistically significant improvement in Wilson/Bootstrap upper-bound FNMR at $\text{FMR} \le 10^{-4}$ over SFace alone.
