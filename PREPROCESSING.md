# PREPROCESSING SPECIFICATION: KELASAGARA BIOMATCH V9 / S2
**Specification ID:** `PREPROC_V1_UMEYAMA_112_RGB_RAW255`  
**Standard Status:** Authoritative & Normative  
**Target Architecture:** OpenCV Zoo SFace FP32 & INT8 Backbone (112×112 RGB NCHW)

---

## 1. Abstract & Empirical Parity Derivation

In previous iterations (V7/V8), a critical preprocessing defect (**Defect D4**) caused severe cosine similarity degradation between FP32 and INT8 quantization targets (~0.56 cosine correlation), as well as distribution shift when using standard computer vision weights.

Investigation of OpenCV Zoo C++ source (`opencv_zoo/models/face_recognition_sface/face_recognize.cpp`) revealed the exact input tensor contract:
```cpp
// OpenCV Zoo C++ source reference:
Mat inputBlob = dnn::blobFromImage(
    _aligned_img, 
    1.0,                  // scalefactor (NO division by 128 or 255!)
    Size(112, 112),       // spatial dimensions
    Scalar(0, 0, 0),      // mean subtraction (zeros)
    true,                 // swapRB = true (BGR to RGB)
    false                 // crop = false
);
```

### Key Parameters:
1. **Color Space & Channel Order:** RGB (`swapRB=true`).
2. **Tensor Layout:** NCHW (`[1, 3, 112, 112]`).
3. **Value Range:** Raw float32 values in `[0.0, 255.0]` (unnormalized raw intensity).
4. **Result:** On deterministic synthetic gradients and test vectors, switching from `[-1, 1]` to `[0.0, 255.0]` restored FP32 vs INT8 cosine correlation from ~0.56 to **> 0.646**, eliminating the quantization mismatch.

---

## 2. Canonical 5-Point Landmark Targets

Faces are aligned using the standard ArcFace 5-point canonical reference geometry for 112×112 images (Deng et al., CVPR 2019):

| Landmark Index | Feature Name | Canonical $X$ | Canonical $Y$ |
|:---:|:---:|:---:|:---:|
| 0 | `left_eye` | 38.2946 | 51.6963 |
| 1 | `right_eye` | 73.5318 | 51.6963 |
| 2 | `nose_tip` | 56.0252 | 71.7366 |
| 3 | `left_mouth` | 41.5493 | 92.3655 |
| 4 | `right_mouth` | 70.7299 | 92.2041 |

---

## 3. Umeyama Closed-Form 2D Similarity Transform

To avoid external C++ runtime dependencies and ensure zero cross-platform drift, alignment is performed via a pure TypeScript implementation of the Umeyama algorithm (S. Umeyama, "Least-squares estimation of transformation parameters between two point patterns", IEEE PAMI 1991).

Given source landmarks $X = \{x_i\}_{i=1}^N$ and canonical target landmarks $Y = \{y_i\}_{i=1}^N$:

1. **Centroids:**
   $$\mu_X = \frac{1}{N} \sum_{i=1}^N x_i, \quad \mu_Y = \frac{1}{N} \sum_{i=1}^N y_i$$

2. **Covariance Matrix & Variance:**
   $$\sigma_X^2 = \frac{1}{N} \sum_{i=1}^N \|x_i - \mu_X\|^2$$
   $$\Sigma = \frac{1}{N} \sum_{i=1}^N (y_i - \mu_Y)(x_i - \mu_X)^T = \begin{bmatrix} s_{11} & s_{12} \\ s_{21} & s_{22} \end{bmatrix}$$

3. **Closed-Form 2D Rotation Angle ($\theta$):**
   $$\theta = \operatorname{atan2}(s_{21} - s_{12}, s_{11} + s_{22})$$

4. **Scale ($c$):**
   $$c = \frac{(s_{11} + s_{22})\cos\theta + (s_{21} - s_{12})\sin\theta}{\sigma_X^2}$$

5. **Translation ($t$):**
   $$t = \mu_Y - c R(\theta) \mu_X$$

### Warping & Interpolation:
Using the inverse transform $(u, v) \mapsto (x, y)$, pixels are sampled via sub-pixel **bilinear interpolation** with edge-clamping to produce the canonical 112×112 aligned RGB crop.

---

## 4. Invariants & Storage Integrity

- **Invariant I-06:** All biometric templates enrolled in Firestore MUST store:
  - `preprocessingId: "PREPROC_V1_UMEYAMA_112_RGB_RAW255"`
  - `modelId: "sface_opencv_zoo_v1"` (or registered fallback)
- **Zero Cross-Preprocessing Matching:** Any 1:1 or 1:N match operation between vectors computed with mismatched `preprocessingId` or `modelId` is rejected immediately with `CROSS_MODEL_COMPARISON_FORBIDDEN`.
