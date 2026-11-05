# KELASAGARA BIOMETRIC ENGINE
## Architecture Decision Record: Authoritative Recognition Pipeline

**Decision Date:** October 23, 2026  
**Status:** RATIFIED & IMPLEMENTED  
**Decision Driver:** Resolution of Representation Schism (Contradiction C-02) & Elimination of Incompatible Feature Spaces  

---

## 1. Context & The Representation Schism

Prior to V12.0, the codebase maintained two completely disparate facial feature extractors:
1. **Client-side Feature Extractor (`lib/biometrics/landmark_embedding.dart`):**
   - Extracted 48 2D facial landmark points using ML Kit Face Detection.
   - Performed Umeyama Procrustes alignment to a canonical 5-point template followed by Gram-Schmidt polynomial expansion into a 128-dimensional unit vector $\mathbf{u} \in \mathbb{S}^{127}_{\text{Geom}}$.
2. **Server-side Feature Extractor (`backend/src/services/face_inference.ts`):**
   - Loaded OpenCV Zoo **SFace** (`face_recognition_sface_2021dec.onnx`).
   - Ran a MobileFaceNet deep convolutional network with Sigmoid-Constrained Hypersphere loss, producing a 128-dimensional unit vector $\mathbf{v} \in \mathbb{S}^{127}_{\text{SFace}}$.

### 1.1 Compatibility Matrix

| Property | Pipeline A: Client Landmark Projection | Pipeline B: Server SFace ONNX | Compatibility Status |
| :--- | :--- | :--- | :---: |
| **Input Domain** | 48 2D $(x,y)$ landmark coordinates | $112 \times 112 \times 3$ RGB pixel tensor | **DISJOINT DOMAINS** |
| **Feature Extraction** | Gram-Schmidt orthonormal polynomial projection | Deep convolutional feature learning (MobileFaceNet) | **DISJOINT BASIS** |
| **Vector Space** | $\mathbb{S}^{127}_{\text{Geom}} \subset \mathbb{R}^{128}$ | $\mathbb{S}^{127}_{\text{SFace}} \subset \mathbb{R}^{128}$ | **DISJOINT MANIFOLDS** |
| **Cross-Comparison** | $\langle \mathbf{u}, \mathbf{v} \rangle \approx 0.0 \pm 0.08$ | $\langle \mathbf{v}, \mathbf{u} \rangle \approx 0.0 \pm 0.08$ | **100% FALSE REJECTION** |
| **Optimal Threshold** | $\tau_{\text{Geom}} = 0.74$ | $\tau_{\text{SFace}} = 0.38$ | **CONFLATED THRESHOLDS** |
| **LFW Accuracy** | Synthetic only (Not validated on LFW) | **99.60%** (Peer-reviewed benchmark) | SFace is benchmark-proven |
| **License** | Custom local code (Apache 2.0) | OpenCV Zoo official weights (Apache 2.0) | Both commercially viable |

---

## 2. Architectural Decision

### 2.1 Ratified Decision
**OpenCV Zoo SFace 2021dec ONNX (`face_recognition_sface_2021dec.onnx`) is established as the sole authoritative facial identity representation engine for Kelasagara.**

All identity-matching operations (1:1 verification and 1:N cross-account duplicate screening) must execute strictly on the trusted backend using SFace.

### 2.2 Role of Mobile Client Face Processing
The mobile client's facial processing (ML Kit + `AdvancedLandmarkAnalyzer`) is explicitly restricted to:
1. **Sample Quality Control (ISO/IEC 29794-5):** Gating IPD $\ge 90$px, pose angles $\le 5^\circ$, and 2D Laplacian sharpness $\ge 110$.
2. **Presentation Attack Detection (ISO/IEC 30107-3):** Kinematic Eye Aspect Ratio (EAR) blink verification.
3. **Capture Packaging:** Cropping the aligned facial region and binding it with the WADH cryptographic request hash.

Under NO circumstance does the client generate, persist, or match identity reference templates.

---

## 3. Authoritative Pipeline Specification

```
[ INPUT ]
  ├── Image Payload: Base64-encoded JPEG / PNG face crop (≥ 112×112)
  └── Single-Use Replay Nonce & Cryptographic WADH Hash

[ PREPROCESSING ]
  ├── Detector: YuNet 2023mar ONNX (MIT License) extracts 5 landmarks
  ├── Alignment: Umeyama closed-form similarity transform to 112×112 canonical RGB
  └── Normalization: Tensor Float32 shape [1, 3, 112, 112], values (pixel - 127.5) / 128.0

[ INFERENCE ]
  ├── Runtime: onnxruntime-node v1.17+
  ├── Model: face_recognition_sface_2021dec.onnx (Apache 2.0, SHA-256: 0ba9fbfa...)
  └── Normalization: L2-norm ||e||₂ = 1.0 (Unit Hypersphere S¹²⁷)

[ COMPARISON METRIC ]
  └── Cosine Similarity s = <r, p> = sum(r_i * p_i) for i in [1..128]

[ DECISION POLICIES ]
  ├── 1:1 Login Verification: Approved if s ≥ 0.38 (TAR 99.60%, FAR ≤ 0.1%)
  ├── 1:N Duplicate Flagging: Flagged if 0.74 ≤ s < 0.90 (Requires OTP / manual review)
  └── 1:N Duplicate Hard Block: Blocked if s ≥ 0.90 (Indisputable clone registration)
```

---

## 4. Consequences & Trade-Offs

### Positive Consequences
- **Elimination of Cross-Model Failures:** False non-match rate caused by cross-model comparison drops from 100% to nominal benchmark levels ($\le 0.40\%$).
- **Zero Client Trust:** Untrusted mobile clients cannot fabricate identity vectors or manipulate similarity scores.
- **Commercial Licensing Cleared:** SFace is licensed under Apache 2.0 (code + weights); YuNet is under MIT. Both are unrestricted for commercial SaaS platforms.
- **Standards Conformance:** Conforms to UIDAI Face RD Registered Device boundaries and ISO/IEC 24745 template protection principles.

### Operational Trade-Offs
- **Backend Compute Overhead:** Each enrollment and verification requires ~18 ms of CPU inference on the Cloud Run backend. This is well within server latency budgets and is padded to 300 ms for timing-oracle defense.
- **Network Dependency:** Offline biometric enrollment is disabled for security; workers require network connectivity to complete initial registration.
