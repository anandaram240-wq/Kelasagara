# KELASAGARA BIOMETRIC ENGINE V19.2.2: FORENSIC MODEL AUDIT

## 1. Executive Summary
This document provides an exhaustive mathematical and architectural audit of the face recognition pipeline deployed in Kelasagara V19.2.2. It traces the complete lifecycle from camera sensor ingestion to feature extraction, metric normalization, and duplicate identification.

---

## 2. Face Detection & 5-Point Alignment
### 2.1 Sensor Ingestion & Detection
The capture front-end utilizes Google ML Kit Face Detection operating on Android CameraX preview frames:
- **Image Format:** YUV_420_888 converted to 8-bit grayscale / RGB planes.
- **Bounding Box Bounds:** Required minimum face width of 160 pixels and Inter-Pupillary Distance (IPD) $\ge 45$ pixels.
- **5 Canonical Fiducial Landmarks:**
  1. Left Eye Center: $p_1 = (x_1, y_1)$
  2. Right Eye Center: $p_2 = (x_2, y_2)$
  3. Nose Tip: $p_3 = (x_3, y_3)$
  4. Mouth Left Corner: $p_4 = (x_4, y_4)$
  5. Mouth Right Corner: $p_5 = (x_5, y_5)$

### 2.2 Canonical Umeyama Similarity Transform
To normalize 2D in-plane rotation, scale, and translation across diverse camera aspects, the system applies the closed-form Umeyama algorithm. Let $X \in \mathbb{R}^{5 \times 2}$ denote the detected landmarks and $Y \in \mathbb{R}^{5 \times 2}$ represent the canonical ArcFace / SFace target reference template coordinates:
$$Y = \begin{bmatrix}
38.2946 & 51.6963 \\
73.5318 & 51.5014 \\
56.0252 & 71.7366 \\
41.5493 & 92.3655 \\
70.7299 & 92.2041
\end{bmatrix}$$

The similarity transform parameters $R \in SO(2)$, $s \in \mathbb{R}^+$, and $t \in \mathbb{R}^2$ minimize the objective:
$$\arg\min_{s, R, t} \sum_{i=1}^5 \| s R x_i + t - y_i \|_2^2$$

The image is resampled to $112 \times 112$ pixels using bilinear interpolation, yielding canonical facial geometry invariant to distance and head tilt.

---

## 3. Deep Neural Feature Extraction: OpenCV Zoo SFace
### 3.1 Neural Network Topology
- **Model Architecture:** SFace (SphereFace 2 / MobileFaceNet variant trained on CASIA-WebFace).
- **Execution Runtime:** ONNX Runtime v1.17+ with CPU execution provider.
- **Input Tensor Dimensions:** $[1, 3, 112, 112]$ in NCHW format.
- **Color Channel Order:** BGR color order with zero-mean normalization:
  $$I_{\text{norm}}(c, y, x) = \frac{I(c, y, x) - \mu_c}{\sigma_c}$$
- **Output Embedding:** 128-dimensional continuous vector $z \in \mathbb{R}^{128}$.

### 3.2 L2 Normalization onto the Unit Hypersphere
To ensure metric comparability via inner products, all extracted embeddings are unit-normalized:
$$\hat{z} = \frac{z}{\|z\|_2} = \frac{z}{\sqrt{\sum_{i=1}^{128} z_i^2}}$$
Thus, $\|\hat{z}\|_2 = 1.0$. The similarity between probe $\hat{u}$ and stored template $\hat{v}$ corresponds to their cosine similarity:
$$\text{Sim}_{\text{SFace}}(\hat{u}, \hat{v}) = \hat{u} \cdot \hat{v} = \sum_{k=1}^{128} \hat{u}_k \hat{v}_k \in [-1.0, 1.0]$$

---

## 4. Dense Landmark Geometric Representation (Legacy Space)
In legacy client versions, geometric features were generated via Fourier positional encodings of 68 face mesh coordinates:
- 128-dimensional dense landmark feature vector $\mathbf{g} \in \mathbb{R}^{128}$.
- L2-normalized: $\|\mathbf{g}\|_2 = 1.0$.
- Captures relative geometric distances (eye-to-nose, mouth aspect ratio, jawline curvature).
- **Fundamental Invariant:** The geometric feature space $\mathcal{S}_{\text{geo}}$ and the neural feature space $\mathcal{S}_{\text{SFace}}$ are orthogonal. Cross-space cosine dot products represent statistical noise and are strictly prohibited in V19.2.2.
