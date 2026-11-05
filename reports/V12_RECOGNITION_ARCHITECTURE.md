# KELASAGARA BIOMETRIC ENGINE V12.0
## Recognition Architecture: Single Source of Truth & Model Alignment

**Date:** October 23, 2026  
**Status:** RECONCILED & STANDARDIZED  
**Standard Compliance:** ISO/IEC 19794-5:2020 / ISO/IEC 39794-5:2024, ISO/IEC 24745:2022  
**Architecture Inspiration:** UIDAI Aadhaar Face RD (Registered Capture Device vs. Central Verification Boundary)  

---

## 1. The Core Representation Schism (Contradiction C-02 Reconciled)

### 1.1 Root Cause of Cross-Model Incompatibility
Prior to V12.0, the repository contained two completely disjoint feature extractors:
1. **Client-side Feature Extractor (`lib/biometrics/landmark_embedding.dart`):**
   - Derived a 128-dimensional embedding from 48 2D facial landmark coordinates.
   - Preprocessing: Umeyama similarity alignment to a canonical 5-point shape $\bar{\mathbf{p}}$, followed by Gram-Schmidt orthonormal polynomial projection.
   - Vector space: $\mathbb{S}^{127}_{\text{Geom}} \subset \mathbb{R}^{128}$ (Hypersphere of facial geometry).
2. **Server-side Feature Extractor (`backend/src/services/face_inference.ts`):**
   - Runs OpenCV Zoo **SFace** (`face_recognition_sface_2021dec.onnx`).
   - Architecture: Deep convolutional MobileFaceNet backbone with Sigmoid-Constrained Hypersphere loss.
   - Input: $112 \times 112 \times 3$ RGB aligned facial crop.
   - Vector space: $\mathbb{S}^{127}_{\text{SFace}} \subset \mathbb{R}^{128}$ (Deep convolutional feature manifold).

### 1.2 Mathematical Proof of Non-Interoperability
Let $\mathbf{u} \in \mathbb{S}^{127}_{\text{Geom}}$ and $\mathbf{v} \in \mathbb{S}^{127}_{\text{SFace}}$ be unit vectors produced by the two models for the same human face $H$.
Because the transformation matrices $\mathbf{W}_{\text{Geom}}$ and $\mathbf{W}_{\text{CNN}}$ are learned/defined on disjoint basis domains (coordinate topology vs pixel convolution kernels), the expected inner product between representations of the same subject across domains is:
$$\mathbb{E}_{H}[\langle \mathbf{u}(H), \mathbf{v}(H) \rangle] \approx 0.0$$
Consequently:
- Comparing a client geometric embedding against an SFace vault template yielded a cosine similarity score centered around zero ($\pm 0.08$), causing a 100% False Non-Match Rate (FNMR = 1.0).
- Conversely, comparing two landmark vectors using SFace's cosine threshold ($0.38$) caused massive false matches across different people.

---

## 2. Definitive V12.0 Architecture: Aadhaar-Inspired Separation

### 2.1 The Four Architectural Boundaries
Inspired by UIDAI Face RD, the Kelasagara system establishes four distinct, tamper-resistant layers:

```
[ LAYER 1: MOBILE CAPTURE DEVICE (Untrusted Environment) ]
  ├── Camera2 / AVFoundation Frame Stream (30 FPS)
  ├── ML Kit High-Fidelity Landmark Detection (133 reference points)
  ├── ISO 29794-5 Quality Assessment (IPD ≥ 90px, Yaw ≤ 5°, Sharpness σ² ≥ 110)
  ├── ISO 30107-3 Passive & Kinematic PAD (Blink frequency, texture variance)
  └── Packaging: JPEG Crop + WADH Binding + Challenge Nonce
                    │
                    ▼ TLS 1.3 (Signed Challenge Request)
[ LAYER 2: API GATEWAY & SECURITY ENFORCER ]
  ├── Device Attestation & Play Integrity Token Validation
  ├── Replay Attack Defense (Single-use challenge nonce with 120s TTL)
  ├── Forbidden Vector Middleware (Rejects any client-supplied vectors)
  └── Oracle-Resistant Latency Padding (Constant-time bucketing)
                    │
                    ▼ Internal VPC / Secure Process IPC
[ LAYER 3: AUTHORITATIVE RECOGNITION ENGINE (Trusted Backend) ]
  ├── Umeyama Canonical 5-Point Affine Alignment (112×112)
  ├── ONNX Runtime Inference: SFace 2021dec (Apache 2.0)
  ├── L2-Normalization: ||e||₂ = 1.0 on S¹²⁷
  ├── 1:1 Verification Policy: Cosine Score s ≥ 0.38 (LFW 99.60% calibration)
  └── 1:N Duplicate Screening Policy: s ≥ 0.74 (Zero-collision threshold)
                    │
                    ▼ Admin SDK / Google Cloud KMS
[ LAYER 4: BIOMETRIC VAULT & AUDIT LOG (CIDR Analog) ]
  ├── Sealed Storage: firestore.rules deny ALL client read/write
  ├── Envelope Encryption: AES-256-GCM with Cloud KMS Key Provider
  ├── Length-Prefixed Binary Canonical AAD (Tenant + UID binding)
  └── Append-Only Cryptographic Hash-Chained Audit Ledger
```

---

## 3. Authoritative Model Specification

| Parameter | Authoritative Specification |
| :--- | :--- |
| **Model Name** | SFace (OpenCV Zoo 2021dec release) |
| **File Path** | `backend/models/face_recognition_sface_2021dec.onnx` |
| **File Size** | 38,696,353 bytes |
| **SHA-256 Checksum** | `0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79` |
| **Backbone Architecture** | MobileFaceNet with Sigmoid-Constrained Hypersphere Loss |
| **Input Shape** | `[1, 3, 112, 112]` (Float32, CHW format, RGB) |
| **Input Normalization** | $\frac{\text{pixel} - 127.5}{128.0}$ |
| **Output Representation** | 128-dimensional floating point vector, L2-normalized ($\|\mathbf{e}\|_2 = 1.0$) |
| **License** | Apache 2.0 (Code and model weights — commercial use authorized) |
| **Reference Paper** | Zhong et al., *"SFace: Sigmoid-Constrained Hypersphere Loss for Robust Face Recognition"*, IEEE T-BIOM 2021 |

---

## 4. Elimination of Client-Side Recognition Fallback

### 4.1 Strict Policy
Mobile devices are client endpoints. Per ISO/IEC 24745 and Aadhaar Face RD specifications:
- The mobile app is NEVER authorized to extract reference biometric templates for enrollment.
- The mobile app is NEVER authorized to execute 1:N duplicate searches.
- The mobile app is NEVER authorized to store raw biometric templates or read from `biometric_vault`.

### 4.2 Handling Backend Unavailability
If the backend verification server is offline or unreachable:
- The mobile application immediately transitions to **fail-closed** mode.
- A user-facing message is rendered in Kannada and English:  
  *ಮುಖ ಪರಿಶೀಲನೆ ಸರ್ವರ್ ಲಭ್ಯವಿಲ್ಲ — Biometric server unreachable. Please check connection and try again.*
- Under NO circumstance does the client attempt local template comparison or write unverified identities to Firestore.
