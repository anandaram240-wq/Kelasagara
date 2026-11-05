# PHASE 20.5 MODEL MANIFEST
## Reproducible Provenance and Mathematical Specification of SFace & YuNet Models

**Project:** Kelasagara Major Project  
**System:** Worker Marketplace & Multi-Factor Biometric Identity Platform  
**Phase:** 20.5 (Advanced Biometric Scientific Validation Engine)  
**Parent Phase 20.4 Commit:** `41f95bf66bd09cda8ea63d3483e567b06ba6504e`  

---

## 1. PRIMARY NEURAL NETWORK MANIFEST (SFACE)

- **Model Identifier**: `sface_opencv_zoo_v1_primary`
- **Model Architecture**: SFace (SphereFace 2 based lightweight CNN with cosine angular margin loss)
- **Model Provenance**: OpenCV Zoo official release (December 2021)
- **Local Artifact Path**: `backend/models/face_recognition_sface_2021dec.onnx`
- **File Size**: 36,945,862 bytes (~35.2 MB)
- **SHA-256 Checksum**:
  `0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79`
- **Input Tensor Dimensions**: `[1, 3, 112, 112]` (Batch size 1, 3 color channels, 112 height, 112 width)
- **Input Color Space**: BGR (Floating point 32-bit)
- **Input Normalization**:
  $$\text{Pixel}_{\text{norm}} = (\text{Pixel}_{\text{raw}} - 0.0) / 1.0$$ (Raw BGR in range $[0.0, 255.0]$)
- **Output Tensor Name**: `fc1`
- **Output Tensor Dimensions**: `[1, 128]` (128-dimensional continuous vector)
- **Post-Processing**: L2 Hypersphere Normalization:
  $$v_{\text{unit}} = \frac{v}{\|v\|_2} \implies \|v_{\text{unit}}\|_2 \equiv 1.0$$
- **Similarity Metric**: Cosine similarity $= \langle v_1, v_2 \rangle$

---

## 2. FACE DETECTOR MANIFEST (YUNET)

- **Model Identifier**: `yunet_2023mar`
- **Architecture**: Lightweight anchor-free object detector optimized for mobile edge CPU
- **Input Resolution**: `[1, 3, 640, 640]`
- **Outputs**:
  - Bounding box coordinates: $[x, y, w, h]$
  - 5 Facial Landmarks: Right eye, Left eye, Nose tip, Right mouth corner, Left mouth corner
  - Confidence score: $p_{\text{face}} \in [0.0, 1.0]$ (Detection threshold: $\ge 0.80$)

---

## 3. CANONICAL FIVE-POINT ALIGNMENT TARGETS

Umeyama similarity transform maps the 5 detected landmarks onto the standard SFace 112x112 target coordinates:

```typescript
export const CANONICAL_SFACE_5_LANDMARKS: readonly Landmark2D[] = [
  { x: 38.2946, y: 51.6963 }, // left eye
  { x: 73.5318, y: 51.6963 }, // right eye
  { x: 56.0252, y: 71.7366 }, // nose tip
  { x: 41.5493, y: 92.3655 }, // left mouth corner
  { x: 70.7299, y: 92.2041 }, // right mouth corner
];
```
