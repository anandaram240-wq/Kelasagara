# KELASAGARA CANONICAL SFACE PIPELINE SPECIFICATION
## MATHEMATICAL SPECIFICATION, NEURAL DETECTION, ALIGNMENT & INFERENCE CONTRACT

**Phase:** Biometric Enrollment Hotfix  
**Branch:** `security/hotfix-canonical-face-preprocessing`  
**Classification:** Computer Vision & Cryptographic Biometric Contract  
**Date:** November 1, 2026  
**Auditors:** Senior Computer Vision Engineer, Principal Biometric Systems Architect

---

## 1. PIPELINE OVERVIEW

```
Original Image (JPEG / PNG / WebP, 64px - 4096px)
   │
   ▼
[Step 1: Safe Decode & Format Verification]
   ├── Magic bytes & decompression bomb bounds (<= 15MB)
   └── Decodes to uncompressed RGB raster (W x H x 3)
   │
   ▼
[Step 2: YuNet Multi-Scale Neural Face Detection]
   ├── Letterbox resize to 640x640 BGR float32 tensor [1, 3, 640, 640]
   ├── Strides 8, 16, 32 feature maps decoding (8400 total anchors)
   ├── Non-Maximum Suppression (IoU <= 0.3)
   └── Outputs bounding box (x, y, w, h) + 5 facial keypoints
   │
   ▼
[Step 3: Quality Gates Assessment]
   ├── Face count = 1 (rejects NO_FACE or MULTIPLE_FACES)
   ├── Resolution: min 60x60 px (FACE_TOO_SMALL)
   ├── Boundaries: min 85% in-frame (FACE_OUT_OF_BOUNDS)
   ├── Head pose: yaw ratio <= 0.45 (EXTREME_POSE)
   └── Sharpness: Laplacian variance >= 12.0 (EXCESSIVE_BLUR)
   │
   ▼
[Step 4: Umeyama 5-Point Similarity Alignment]
   ├── Maps source keypoints to canonical SFace landmarks
   └── Computes optimal similarity transform T = { scale, theta, tx, ty }
   │
   ▼
[Step 5: Bilinear Affine Warping]
   ├── Inverse mapping with bilinear interpolation
   └── Yields strictly typed CanonicalAlignedFace112 (112 x 112 x 3 RGB, 37,632 bytes)
   │
   ▼
[Step 6: SFace Neural Feature Extraction]
   ├── Converts 112x112 to BGR float32 tensor [1, 3, 112, 112]
   ├── Forward pass through face_recognition_sface_2021dec.onnx
   ├── L2 unit normalization on unit hypersphere S^127
   └── Returns validated SFaceEmbedding128 (Float32Array[128])
```

---

## 2. MATHEMATICAL FORMULATION

### A. YuNet Multi-Scale Anchor Decoding
The YuNet model operates on fixed input dimensions of $640 \times 640 \times 3$ with three feature map strides: $s \in \{8, 16, 32\}$.
- Stride 8: $80 \times 80 = 6,400$ cells
- Stride 16: $40 \times 40 = 1,600$ cells
- Stride 32: $20 \times 20 = 400$ cells
- Total anchors evaluated: $8,400$

For feature cell $(c, r)$ at stride $s$ with index $\text{idx} = r \times \text{cols} + c$:
1. **Confidence Score Fusion:**
   $$\text{score} = \sqrt{\text{clamp}(\text{cls}[\text{idx}], 0, 1) \times \text{clamp}(\text{obj}[\text{idx}], 0, 1)}$$
   Candidate retained if $\text{score} \ge \text{minScore}$ (default $0.60$).

2. **Bounding Box Decoding:**
   $$c_x = (c + \text{bbox}[\text{idx} \times 4 + 0]) \times s$$
   $$c_y = (r + \text{bbox}[\text{idx} \times 4 + 1]) \times s$$
   $$w = \exp(\text{bbox}[\text{idx} \times 4 + 2]) \times s$$
   $$h = \exp(\text{bbox}[\text{idx} \times 4 + 3]) \times s$$
   $$x = c_x - \frac{w}{2}, \quad y = c_y - \frac{h}{2}$$

3. **Facial Keypoints Decoding ($k \in \{0, 1, 2, 3, 4\}$):**
   $$k_{x, k} = (c + \text{kps}[\text{idx} \times 10 + 2k + 0]) \times s$$
   $$k_{y, k} = (r + \text{kps}[\text{idx} \times 10 + 2k + 1]) \times s$$
   Landmark sequence: Right Eye, Left Eye, Nose Tip, Right Mouth Corner, Left Mouth Corner.

### B. Umeyama 5-Point Similarity Transform
Given $N=5$ source points $\mathbf{x}_i$ and canonical destination points $\mathbf{y}_i$:
$$\mathbf{y}_i \in \text{CANONICAL\_SFACE\_5\_LANDMARKS} = \begin{pmatrix} (38.2946, 51.6963) & \text{Right Eye (image left)} \\ (73.5318, 51.6963) & \text{Left Eye (image right)} \\ (56.0252, 71.7366) & \text{Nose Tip} \\ (41.5493, 92.3655) & \text{Right Mouth} \\ (70.7299, 92.2041) & \text{Left Mouth} \end{pmatrix}$$

1. Compute point set centroids $\boldsymbol{\mu}_x = \frac{1}{N} \sum \mathbf{x}_i$, $\boldsymbol{\mu}_y = \frac{1}{N} \sum \mathbf{y}_i$.
2. Compute variance $\sigma_x^2 = \frac{1}{N} \sum \|\mathbf{x}_i - \boldsymbol{\mu}_x\|^2$.
3. Compute covariance matrix $\boldsymbol{\Sigma}_{xy} = \frac{1}{N} \sum (\mathbf{y}_i - \boldsymbol{\mu}_y)(\mathbf{x}_i - \boldsymbol{\mu}_x)^T = \begin{pmatrix} s_{11} & s_{12} \\ s_{21} & s_{22} \end{pmatrix}$.
4. Compute rotation angle:
   $$\theta = \text{atan2}(s_{21} - s_{12}, s_{11} + s_{22})$$
5. Compute optimal scale:
   $$c = \frac{(s_{11} + s_{22}) \cos\theta + (s_{21} - s_{12}) \sin\theta}{\sigma_x^2}$$
6. Compute translation vector:
   $$\mathbf{t} = \boldsymbol{\mu}_y - c \mathbf{R}(\theta) \boldsymbol{\mu}_x$$

### C. Bilinear Affine Warping
To avoid sampling gaps, warping is evaluated backwards from destination canonical coordinate $(u, v) \in [0, 111] \times [0, 111]$ to source space $(x, y)$:
$$\begin{pmatrix} x \\ y \end{pmatrix} = \frac{1}{c} \begin{pmatrix} \cos\theta & \sin\theta \\ -\sin\theta & \cos\theta \end{pmatrix} \begin{pmatrix} u - t_x \\ v - t_y \end{pmatrix}$$
Source pixels are interpolated using four-neighbor bilinear weighting:
$$I(u, v) = (1 - f_x)(1 - f_y) I(x_0, y_0) + f_x(1 - f_y) I(x_1, y_0) + (1 - f_x)f_y I(x_0, y_1) + f_x f_y I(x_1, y_1)$$

### D. SFace L2-Normalized Feature Extraction
The resulting $112 \times 112 \times 3$ RGB buffer is converted to BGR channel order in $[0.0, 255.0]$ and evaluated by SFace:
$$\mathbf{e}_{\text{raw}} = \text{SFace}(I_{\text{aligned}}), \quad \mathbf{e}_{\text{raw}} \in \mathbb{R}^{128}$$
$$\mathbf{e}_{\text{canonical}} = \frac{\mathbf{e}_{\text{raw}}}{\|\mathbf{e}_{\text{raw}}\|_2}, \quad \|\mathbf{e}_{\text{canonical}}\|_2 = 1.000000 \pm 10^{-6}$$

---

## 3. STRONGLY TYPED INTERFACES

```typescript
export type OriginalImageBytes = Buffer & { readonly __brand: unique symbol };
export type CanonicalAlignedFace112 = Buffer & { readonly __brand: unique symbol };
export type SFaceEmbedding128 = Float32Array & { readonly __brand: unique symbol };

export interface DetectedFace {
  box: { x: number; y: number; width: number; height: number };
  score: number;
  landmarks: LandmarkSet5;
}

export interface LandmarkSet5 {
  rightEye: Landmark2D;
  leftEye: Landmark2D;
  noseTip: Landmark2D;
  rightMouth: Landmark2D;
  leftMouth: Landmark2D;
}
```

The TypeScript compiler strictly prevents any unaligned image buffer from reaching `extractCanonicalEmbeddingFromAligned112()`, making scene-level squashing mathematically impossible.
