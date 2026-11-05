# KELASAGARA BIOMATCH · STAGE S7 MODEL AND PREPROCESSING SPECIFICATION (S7_MODEL_AND_PREPROCESSING_SPEC.md)

**Classification:** Neural Pipeline Specification, Preprocessing Contract & Tensor Interface  
**Stage:** S7  
**Date:** 2026-10-11  

---

## 1. Primary Model Architecture and Provenance

| Specification Field | Production Value | Verification Reference |
| :--- | :--- | :--- |
| **Model Name** | OpenCV Zoo SFace (2021Dec) | `backend/src/services/model_registry.ts` |
| **Model ID** | `sface_opencv_zoo_v1_primary` | Invariant I-02, I-18 |
| **License** | **Apache-2.0** (Permissive Commercial Use) | `LICENSES.md` |
| **Weight Artifact** | `backend/models/face_recognition_sface_2021dec.onnx` | Stored in-repo |
| **File Size** | 38,696,353 Bytes | Validated |
| **SHA-256 Digest** | `0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79` | Hardcoded integrity guard |
| **Execution Provider** | `CPUExecutionProvider` (Sequential concurrency) | `backend/src/services/face_inference.ts` |
| **Graph Optimization** | `ORT_ENABLE_ALL` | Enabled at session creation |

---

## 2. Input and Output Tensor Specifications

### 2.1 Input Tensor Contract
- **Name:** `data`
- **Shape:** `[1, 3, 112, 112]` (Batch size 1, 3 color channels, 112px height, 112px width).
- **Data Type:** `float32` (IEEE 754 single precision).
- **Color Channel Order:** **BGR** (OpenCV Zoo native convention).
- **Pixel Value Range:** `[0.0, 255.0]` (Raw unnormalized floating point values; mean subtraction and variance scaling are internalized in the first ONNX model batchnorm layer).
- **Layout:** NCHW (Planar contiguous).

### 2.2 Output Tensor Contract
- **Name:** `fc1`
- **Shape:** `[1, 128]`
- **Data Type:** `float32`
- **Post-Processing:** Server applies L2 unit hypersphere normalization:
  $$v_{\text{normalized}} = \frac{v}{\|v\|_2} \quad \text{such that} \quad \|v_{\text{normalized}}\|_2 = 1.0 \pm 10^{-5}$$

---

## 3. Preprocessing Specification: `PREPROC_V1_UMEYAMA_112_RGB_RAW255`

### 3.1 Landmark Detection
Face detection and landmark extraction are executed on the server using **YuNet (2023Mar)** (`face_detection_yunet_2023mar.onnx`, SHA-256: `8f2383e4dd3c...`). Five canonical 2D facial landmarks are located:
1. Left eye pupil center
2. Right eye pupil center
3. Nose tip
4. Left mouth corner
5. Right mouth corner

### 3.2 Canonical ArcFace Reference Coordinates (112 × 112)
Reference target coordinates in 112 × 112 pixel space:
- Left Eye: $(38.2946, 51.6963)$
- Right Eye: $(73.5318, 51.6963)$
- Nose Tip: $(56.0252, 71.7366)$
- Left Mouth: $(41.5493, 92.3655)$
- Right Mouth: $(70.7299, 92.2041)$

### 3.3 Closed-Form Umeyama Similarity Transform
The server computes a 2D similarity transform $(\text{scale } s, \text{rotation } \theta, \text{translation } [t_x, t_y])$ minimizing least-squares error between source landmarks and canonical landmarks via the closed-form Umeyama algorithm (1991). Pure TypeScript implementation in `backend/src/services/face_preprocessing.ts` ensures zero external C++ library dependency.

### 3.4 Image Warping & Quality Gating
- **Warping:** Bilinear interpolation with boundary pixel clamping.
- **Image Quality Assessment (IQA):**
  - Minimum cropped face size: $112 \times 112\text{ px}$.
  - Minimum Inter-Pupillary Distance (IPD): $\ge 35\text{ px}$.
  - Maximum Yaw / Pitch: $\le 30^\circ$.
  - Minimum Laplacian blur score: $\ge 60$.
  - Mean luminance range: $[40, 220]$.

---

## 4. Exit Gate S7-G04 Assessment

**Status:** `DONE-VERIFIED`  
**Evidence Artifact:** `evidence/s7/model_manifest.json`  
**Verification:** Model SHA-256, tensor layouts, and Umeyama mathematical alignment verified against live ONNX execution.
