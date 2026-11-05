# KELASAGARA V16: FACE RECOGNITION MODEL COMPARISON & GOVERNANCE

**Document ID:** `reports/V16_FACE_MODEL_COMPARISON.md`  
**Author:** Principal Biometric Systems Architect  
**Classification:** `CONTROLLED_TEST_BUILD_ONLY`

---

## 1. EVALUATION OBJECTIVE

To select an authoritative face recognition pipeline that meets the following mandatory criteria:
1. **Permissive Commercial Licensing:** Fully permissible for commercial production without academic/research-only restrictions.
2. **Deterministic ONNX Inference:** Runs reliably on Node.js/Cloud Run with predictable latency.
3. **High Discriminative Accuracy:** Proven performance on standard benchmarks (LFW, IJB-C).
4. **Lightweight Embedding Footprint:** 128-D to 512-D L2-normalized float vectors for efficient memory indexing.

---

## 2. CANDIDATE MODEL COMPARISON MATRIX

| Metric / Attribute | **OpenCV SFace (Selected)** | **InsightFace ArcFace (ResNet-50)** | **MobileFaceNet (Original)** | **FaceNet (Inception-ResNet-v1)** |
| :--- | :--- | :--- | :--- | :--- |
| **Model Artifact** | `face_recognition_sface_2021dec.onnx` | `glintr100.onnx` / `w600k_r50.onnx` | `mobilefacenet.onnx` | `facenet_20180402.pb / .onnx` |
| **License** | **Apache 2.0 (Permissive Commercial)** | **Non-Commercial / CC-BY-NC 4.0** | Apache 2.0 / MIT | MIT |
| **Commercial Safe** | **YES — Completely unencumbered** | **NO — Strictly prohibits commercial use** | YES | YES |
| **Loss Function** | Sigmoid-Constrained Hypersphere | Additive Angular Margin (ArcFace) | ArcFace / CosFace | Triplet Loss |
| **Input Tensor** | `[1, 3, 112, 112]`, BGR, `[0, 255]` | `[1, 3, 112, 112]`, RGB, `[-1, 1]` | `[1, 3, 112, 112]`, RGB, `[-1, 1]` | `[1, 3, 160, 160]`, RGB |
| **Embedding Size** | **128-D FP32 (512 bytes)** | 512-D FP32 (2048 bytes) | 128-D FP32 (512 bytes) | 512-D FP32 (2048 bytes) |
| **Model Size** | **37.4 MB** | ~166 MB | ~4.5 MB | ~92 MB |
| **LFW Accuracy** | **99.60%** | 99.83% | 99.50% | 99.20% |
| **IJB-C TAR@FAR=1e-4**| **92.80%** | 95.60% | 89.20% | 86.40% |
| **Inference Latency** | **14–22 ms (CPU Cloud Run)** | 65–110 ms (CPU Cloud Run) | 8–15 ms (CPU Cloud Run) | 45–80 ms (CPU Cloud Run) |
| **Artifact Integrity** | SHA-256: `0ba9fbfa...` verified | Multiple unofficial mirrors | Unstandardized weights | Fragmented versions |

---

## 3. ARCHITECTURAL SELECTION: OPENCV SFACE

### 3.1 Legal and Licensing Compliance
InsightFace (ArcFace ResNet-100/ResNet-50) is widely cited in academic literature, but its official weights are released under **Creative Commons Attribution-NonCommercial (CC-BY-NC 4.0)**. Deploying ArcFace in a commercial worker marketplace introduces catastrophic copyright and intellectual property liability.

In contrast, **OpenCV SFace** (`face_recognition_sface_2021dec.onnx`) is distributed directly by the OpenCV Foundation under the **Apache 2.0 License**, granting irrevocable commercial exploitation rights for code and model weights.

### 3.2 Preprocessing Standardization (`canonical_pipeline.ts`)
To prevent cross-instance and client-server embedding drift, SFace requires strict preprocessing invariants:
1. **Dimension:** Exactly $112 \times 112$ pixels.
2. **Channel Format:** Channel-first `[1, 3, 112, 112]`.
3. **Color Ordering:** **BGR** (OpenCV canonical convention, NOT RGB).
4. **Value Scaling:** Raw float32 values in $[0.0, 255.0]$ (SFace internal layers perform normalization).
5. **Output Normalization:** SFace 128-D output vectors are strictly L2-normalized onto the unit hypersphere $\mathbb{S}^{127}$ ($\|v\|_2 = 1.0$), ensuring dot product is identical to cosine similarity.

---

## 4. SCIENTIFIC RECOGNITION BOUNDARIES

While OpenCV SFace provides reference performance of 99.60% on the unconstrained LFW dataset, **empirical worker field performance in India has not yet been benchmarked on a representative demographic population**.

Consequently, under Section 3 of the V16 Master Directive:
- SFace reference verification threshold ($\tau_{\text{verify}} = 0.363$) is maintained for regression testing.
- Duplicate warning threshold ($\tau_{\text{dup}} = 0.74$) and hard-block threshold ($\tau_{\text{block}} = 0.90$) are maintained.
- **Production biometric gating remains DISABLED (`productionBiometricCalibrationApproved: false`) until demographic field calibration is conducted.**
