# KELASAGARA V20.9: CAMERA DATA FLOW MAP
## End-to-End Image Pipeline from CameraX Sensor to Biometric Embedding

**Document Ref:** `docs/PHASE20_9_CAMERA_DATA_FLOW_MAP.md`  
**Phase:** 20.9  
**Auditor:** Principal Android Camera & Biometric Security Engineer  
**Date:** November 1, 2026

---

### 1. High-Level Pipeline Architecture

The Kelasagara biometric capture architecture enforces a verified, deterministic, tamper-evident pipeline:

```
[Camera Sensor (Physical CMOS)]
             │
             ▼
[HAL3 / Camera2 Provider]
             │
             ▼
[CameraX ImageAnalysis ImageProxy (YUV_420_888)]
             │
             ├──► Native Yuv420PlaneReader.kt (Unpadding, NV12/NV21 Demux, Rotation)
             │          │
             │          ▼
             │    [Canonical I420 Memory Buffer]
             │          │
             │          ├──► Local Grayscale (Y-Plane) ──► ML Kit Face Detection / Landmarks
             │          │
             │          └──► SHA-256 Frame Digest Calculation
             │
             ▼
[Hardware Security Binding]
             │
             ├──► Play Integrity requestHash (PLAY_INTEGRITY_BINDING_V2)
             └──► Android Keystore Hardware Attestation ECDSA Signature
             │
             ▼
[Encrypted Transport (HTTPS TLS 1.3)]
             │
             ▼
[Node.js Express / Biometric Service]
             │
             ├──► Verify Client ECDSA Signature & Play Integrity Nonce Binding
             │
             ├──► CameraCaptureIntegrity.ts (Unpack / Canonicalize / Verify Frame Sequence)
             │
             ├──► Sharp Decode & Parity Check (PSNR > 32 dB)
             │
             ├──► Candidate PAD Optical Display Extractor (2D DCT-II Moiré & Spectral Energy)
             │
             ├──► YuNet 5-Point Landmark Face ROI Alignment
             │
             └──► SFace ONNX Inference Session Pool ──► 128-D Embedding
```

---

### 2. Stage-by-Stage Forensic Specifications

| Stage # | Component | Transformation / Operation | Invariant / Security Guarantee |
| :--- | :--- | :--- | :--- |
| **Stage 1** | CMOS Sensor & ISP | Photons converted to Bayer RAW, demosaiced to YUV_420_888. | No software tampering possible at HAL level. |
| **Stage 2** | CameraX `ImageProxy` | Delivers 3 distinct `PlaneProxy` buffers (Y, U, V). | Must handle arbitrary hardware rowStride (e.g. 704 on 640w). |
| **Stage 3** | `Yuv420PlaneReader.kt` | Unpads rows, handles NV12/NV21 pixel strides, applies 0/90/180/270 rotation. | Produces contiguous, deterministic I420 planar buffer. |
| **Stage 4** | Payload Hash Engine | Computes SHA-256 over contiguous I420 bytes. | Exact cryptographic binding anchor for requestHash. |
| **Stage 5** | Device Keystore | Signs SHA-256 payload digest via hardware-backed SECP256R1 private key. | Prevents replay and proxy injection attacks. |
| **Stage 6** | Transport Layer | Client sends JPEG or raw payload + signature + attestation token. | TLS 1.3 encryption prevents MITM eavesdropping. |
| **Stage 7** | Backend Reception | Reconstructs payload, verifies SHA-256 digest against client signature. | Fails closed on any 1-bit tampering or nonce mismatch. |
| **Stage 8** | Frame Monotonicity | Checks timestamps ($t_i > t_{i-1}$) and inter-frame variance ($MSE \ge 1.0$). | Detects non-monotonic timestamps, frame gaps, and frozen camera video. |
| **Stage 9** | Optical Feature Extractor | 2D DCT-II over $8\times 8$ blocks on normalized grayscale. | Computes high-frequency energy ratio and spectral concentration. |
| **Stage 10** | Face Recognition | YuNet alignment $\rightarrow$ SFace ONNX pool $\rightarrow$ 128-D vector. | Preserves canonical cosine similarity recognition decisions. |
