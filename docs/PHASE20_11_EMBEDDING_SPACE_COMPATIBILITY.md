# PHASE 20.11: EMBEDDING SPACE COMPATIBILITY SPECIFICATION
**Role:** Principal Biometric Architect & Computer Vision Engineer  
**System:** Kelasagara Multi-Factor Biometric Identity Platform  
**Branch:** `security/phase20.11-legacy-template-isolation`  
**Date:** November 1, 2026  

---

## 1. CANONICAL V2 EMBEDDING SPACE SPECIFICATION

The authoritative embedding space for all current and future biometric enrollments and deduplication queries is defined as:

```typescript
export const CANONICAL_EMBEDDING_SPACE_V2 = {
  embeddingSpaceId: 'SFACE_128_YUNET_2023MAR_UMEYAMA_CANONICAL112_V2',
  modelIdentifier: 'sface_opencv_zoo_v1_primary',
  modelSha256: '0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79',
  detectorIdentifier: 'yunet_opencv_zoo_2023mar_primary',
  detectorSha256: '8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4',
  alignmentAlgorithm: 'umeyama_5point_similarity',
  canonicalTargetGeometry: '112x112_canonical_sface_5landmarks',
  colorSpace: 'BGR',
  normalization: 'L2_UNIT_HYPERSPHERE_S127',
  dimension: 128,
} as const;
```

---

## 2. MATHEMATICAL SPECIFICATION & PARAMETERS

1. **Neural Detector (Stage 1):**
   - **Model:** YuNet (`face_detection_yunet_2023mar.onnx`)
   - **Input Dimensions:** $640 \times 640 \times 3$ BGR, float32, letterbox padded.
   - **Strides:** 8, 16, 32.
   - **Outputs:** Bounding box $[x, y, w, h]$, confidence score, and 5 facial keypoints:
     $p_1 = \text{Right Eye}$, $p_2 = \text{Left Eye}$, $p_3 = \text{Nose Tip}$, $p_4 = \text{Right Mouth Corner}$, $p_5 = \text{Left Mouth Corner}$.

2. **Similarity Transform (Stage 2 - Umeyama):**
   - **Reference Target Landmark Geometry (112x112):**
     - $T_{\text{left\_eye}} = [38.2946, 51.6963]$
     - $T_{\text{right\_eye}} = [73.5318, 51.6963]$
     - $T_{\text{nose}} = [56.0252, 71.7366]$
     - $T_{\text{left\_mouth}} = [41.5493, 92.3655]$
     - $T_{\text{right\_mouth}} = [70.7299, 92.2041]$
   - **Transformation Model:** Orthogonal Procrustes / Umeyama similarity transform solving:
     $$S^*, R^*, t^* = \arg\min_{s, R, t} \sum_{i=1}^5 \| T_i - (s R P_i + t) \|^2$$
   - **Interpolation:** Bilinear sampling with out-of-bounds reflection / clamp.

3. **Feature Extraction (Stage 3 - SFace):**
   - **Model:** SFace (`face_recognition_sface_2021dec.onnx`)
   - **Input Tensor:** $1 \times 3 \times 112 \times 112$, NCHW BGR in $[0.0, 255.0]$.
   - **Feature Space:** 128-dimensional hyperspherical vector $\vec{v} \in \mathbb{R}^{128}$.
   - **Normalization:** Explicit $L_2$ unit normalization:
     $$\hat{v} = \frac{\vec{v}}{\|\vec{v}\|_2}, \quad \|\hat{v}\|_2 \equiv 1.0 \pm 10^{-6}$$

---

## 3. COMPARISON SPACE COMPATIBILITY MATRIX

| Query Probe Space | Gallery Candidate Space | Comparison Permitted? | Decision Rule | Reason |
| :--- | :--- | :--- | :--- | :--- |
| `CANONICAL_V2` | `CANONICAL_V2` | **YES** | Cosine similarity against $[0.3630, 0.7200]$ thresholds | Mathematically identical latent representation |
| `CANONICAL_V2` | `DEFECTIVE_FULL_PHOTO_SFACE_V10` | **NO** | `NEVER_COMPARE` (Candidate skipped) | Pre-hotfix full scene unaligned crop corrupts cosine similarity |
| `CANONICAL_V2` | `LEGACY_LANDMARK_SPACE` | **NO** | `NEVER_COMPARE` (Candidate skipped) | Geometric landmark distances cannot be projected into neural latent space |
| `CANONICAL_V2` | `LEGACY_TEMPLATE_UNKNOWN` | **NO** | `NEVER_COMPARE` (Candidate skipped) | Unverified preprocessing provenance fails closed |
| `LEGACY_LANDMARK_SPACE` | `LEGACY_LANDMARK_SPACE` | **YES** | Cosine similarity against $[0.8000, 0.8800]$ thresholds | Legacy-to-legacy geometric verification only |

---

## 4. INCOMPATIBLE_EMBEDDING_SPACE = NEVER_COMPARE ENFORCEMENT

The gallery indexing and matching engine enforces space isolation at the query execution level (`FirestoreCompatibleGalleryIndex.searchTopKCompatible`). Cross-space comparisons are physically prevented from computing similarity scores, completely immunizing new worker enrollments against false duplicate matches triggered by historical legacy artifacts.
