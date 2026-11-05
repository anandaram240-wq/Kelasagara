# KELASAGARA V15.0: BIOMETRIC RECOGNITION & EVALUATION STATUS

**Project:** Kelasagara Worker Marketplace Biometric Subsystem  
**Date:** October 23, 2026  
**Auditor:** Principal Biometric Systems Architect & Scientific Evaluator  
**Classification:** CONTROLLED TEST BUILD ONLY — SCIENTIFIC REVALIDATION  
**Primary Files Evaluated:**
- [`backend/src/evaluation/evaluation_harness.ts`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/backend/src/evaluation/evaluation_harness.ts)
- [`backend/src/evaluation/dedup_calculator.ts`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/backend/src/evaluation/dedup_calculator.ts)
- [`backend/src/evaluation/fairness_evaluator.ts`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/backend/src/evaluation/fairness_evaluator.ts)
- [`backend/src/services/face_inference.ts`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/backend/src/services/face_inference.ts)

---

## 1. Executive Summary & Core Scientific Finding

A rigorous scientific review of the recognition engine reveals that **no empirical biometric accuracy or duplicate identification performance has been validated on the representative target demographic** (Indian informal economy workers using low-cost Android smartphones in unconstrained ambient environments).

The reported accuracy numbers (99.60% LFW, 92.80% IJB-C TAR @ FAR 1e-4) represent published academic benchmark results achieved by OpenCV and the original SFace authors (Zhong et al., IEEE T-BIOM 2021) on curated, high-quality, predominantly Western/East Asian benchmark datasets. 

Under real-world field conditions in Karnataka (harsh sunlight, fluorescent indoor light, motion blur, lens smudges, diverse skin tones, beards, turbans, facial scarring, aging, and fatigue), error rates will diverge significantly from academic figures.

Therefore, the current biometric status is formally classified as:
- **Comparator & Pipeline Software Behavior:** **VERIFIED (HERMETIC TESTS PASS)**
- **1:1 Verification Field Performance:** **NOT VALIDATED**
- **1:N Duplicate Screening Performance:** **NOT VALIDATED**
- **Physical Presentation Attack Resistance:** **NOT VALIDATED**

---

## 2. Complete Technical Pipeline Specification

The authoritative neural recognition pipeline is hosted exclusively on the trusted backend:

```
[Raw Camera Frame (JPEG)] 
           │
           ▼
[Format Validation & Base64 Decode] (backend/src/routes/face_routes.ts)
           │
           ▼
[YuNet 5-Point Landmark Detection] (Left Eye, Right Eye, Nose Tip, Mouth Left, Mouth Right)
           │
           ▼
[Umeyama 2D Similarity Transformation] (Canonical Alignment to 112×112 Hypersphere Coordinates)
           │
           ▼
[Input Tensor Normalization] (CHW RGB, (pixel - 127.5) / 128.0)
           │
           ▼
[SFace ONNX Neural Inference] (face_recognition_sface_2021dec.onnx, MobileFaceNet + Sigmoid Loss)
           │
           ▼
[Raw 128-D Feature Extraction]
           │
           ▼
[L2 Unit Hypersphere Normalization] (||v||₂ = 1.0)
           │
           ▼
[1:1 Cosine Comparison / 1:N Gallery Search] (s = probe · template)
```

### Artifact & Configuration Invariants
- **Primary Model Artifact:** `models/face_recognition_sface_2021dec.onnx`
- **Model Architecture:** MobileFaceNet backbone with Sigmoid-Constrained Hypersphere Loss
- **Licensing:** Apache 2.0 (Permissive commercial use without copyleft or proprietary encumbrances)
- **Output Dimensionality:** 128-element Float32 vector on $\mathbb{S}^{127}$
- **Preprocessing Identifier:** `PREPROC_V1_UMEYAMA_112_RGB_RAW255`
- **Fallback Redundancy:** INT8 quantized SFace (`face_recognition_sface_2021dec_int8.onnx`) with cross-model divergence monitoring (Invariant I-06).

---

## 3. Evaluation Harness Audit

### A. 1:1 Verification Harness (`BiometricEvaluationHarness`)
[`backend/src/evaluation/evaluation_harness.ts`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/backend/src/evaluation/evaluation_harness.ts) implements statistical evaluation for 1:1 verification:
1. **Area Under Curve (AUC):** Computed via non-parametric Mann-Whitney $U$ statistic:
   $$U = R_G - \frac{n_G(n_G + 1)}{2}, \quad \text{AUC} = \frac{U}{n_G \cdot n_I}$$
2. **Detection Error Trade-off (DET):** Evaluates False Match Rate ($FMR$) and False Non-Match Rate ($FNMR$) across threshold range $\tau \in [0.0, 1.0]$ in increments of $0.005$.
3. **Operating Points:** Identifies empirical thresholds achieving $FMR \le 10^{-3}$ and $FMR \le 10^{-4}$.
4. **Uncertainty Quantification:** 500-iteration non-parametric bootstrap resampling computing 95% confidence intervals for AUC and FNMR.

**Limitation:** The harness is fully functional as software, but has only been executed against synthetic vectors and unit mocks. No empirical evaluation on a calibrated Indian dataset has been conducted.

### B. 1:N Duplicate Screening Harness (`DedupOperatingPointCalculator`)
[`backend/src/evaluation/dedup_calculator.ts`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/backend/src/evaluation/dedup_calculator.ts) models gallery false alarm scaling:
$$\text{FMR}_N = 1 - (1 - \text{FMR}_1)^N$$

**Critical Statistical Fallacy Identified:**
The formula $\text{FMR}_N = 1 - (1 - \text{FMR}_1)^N$ assumes that all $N$ comparisons against gallery templates are statistically independent events. In biometric systems, this assumption is **empirically false**:
- Comparisons share the identical probe image (and its sensor noise, lighting artifacts, and pose).
- Subjects in a demographic cohort share correlated facial structures and appearance distributions.
- Therefore, the true platform False Positive Identification Rate ($\text{FPIR}$) diverges from the theoretical binomial model.

Per ISO/IEC 19795-1:2021 and NIST FRTE 1:N standards, **1:N duplicate detection performance must be evaluated directly on the actual search algorithm and gallery**, measuring observed $\text{FPIR}(N, \tau)$ and False Negative Identification Rate $\text{FNIR}(N, \tau)$ as $N$ scales.

---

## 4. Dataset Licensing and Legal Compliance

1. **Prohibition of Unlawfully Sourced Face Datasets:**
   The project strictly forbids downloading or utilizing face datasets with restrictive licenses (e.g., non-commercial academic-only datasets like CASIA-WebFace or VGGFace2) or retracted datasets (e.g., MS-Celeb-1M, MegaFace).
2. **DPDPA 2023 Statutory Compliance (§6 & §8):**
   Biometric data is sensitive personal data. Collecting face images from workers for model training or benchmark calibration without specific, informed, and unconditional consent constitutes a statutory violation under the Digital Personal Data Protection Act, 2023.
3. **Current Test Fixture Policy:**
   Only synthetic unit fixtures, mathematically constructed hypersphere vectors, and permissible open-source reference samples are retained in the repository.

---

## 5. Prerequisites for Selecting a Production Threshold

Before any threshold ($\tau_{\text{verify}}$ or $\tau_{\text{dup}}$) can be approved for live production identity gating, the following rigorous evaluation gate must be fulfilled:

1. **Calibrated Target Dataset:**
   A dataset of at least 1,000 distinct individuals representative of the target Indian workforce demographic, with at least 3 capture sessions per individual across varying smartphone cameras, indoor/outdoor lighting, and intervals of $\ge 7$ days.
2. **Empirical Operating Point Verification:**
   - 1:1 Verification: Documented operating threshold achieving $\text{FMR} \le 0.1\%$ ($10^{-3}$) with $\text{FNMR} \le 2.0\%$ and tight 95% bootstrap confidence bounds.
   - 1:N Deduplication: Measured $\text{FPIR} \le 1.0\%$ at the designated gallery capacity ($N = 1,000$ or $N = 10,000$).
3. **Demographic Equity Assessment (ISO/IEC 19795-10:2024):**
   Verification that false non-match rates do not disproportionately penalize female workers, elderly workers, or darker Fitzpatrick skin types ($V_{\text{disp}} \le 1.25$).
4. **Signed Evaluation Manifest:**
   An immutable JSON evaluation report signed by the lead biometric systems architect and retained in the release audit repository.
