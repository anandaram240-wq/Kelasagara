# PHASE 20.5 BASELINE CONFIGURATION
## Immutable Scientific Baseline and System Configuration Manifest

**Project:** Kelasagara Major Project  
**System:** Worker Marketplace & Multi-Factor Biometric Identity Platform  
**Phase:** 20.5 (Advanced Biometric Scientific Validation Engine)  
**Parent Phase 20.4 Commit:** `41f95bf66bd09cda8ea63d3483e567b06ba6504e`  
**Working Branch:** `research/phase20.5-biometric-validation`  
**Protected Release Tag:** `v19.2.3-release` (`f210f95943ced619f6cd27441d9f1d89e79c08e8`)  
**Protected Release APK SHA-256:** `739f85746df3cd1fb6c315590147907918a3829976d0381b8eae358c743176ce`  

---

## 1. FROZEN PIPELINE ARCHITECTURE

The biometric processing pipeline evaluated in Phase 20.5 is preserved without alteration from the production baseline:

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                    IMMUTABLE SFACE BIOMETRIC PIPELINE                           │
├─────────────────────────────────────────────────────────────────────────────────┤
│ 1. Mobile Capture: Burst acquisition of 3 sequential JPEG frames (t0, t1, t2)   │
│ 2. Face Detection: YuNet (640x640 input, 5 facial landmarks, score >= 0.80)     │
│ 3. Umeyama Alignment: 5-point similarity transform to 112x112 canonical space   │
│ 4. Quality Assessment: Laplacian sharpness (>= 110), IPD (>= 75px), Euler pose  │
│ 5. Liveness / PAD: Palpebral aperture height + EAR blink compression (<= 0.65x) │
│ 6. Neural Extraction: ONNX SFace 2021dec (sface_opencv_zoo_v1_primary)          │
│ 7. Representation: 128-dimensional floating-point vector                        │
│ 8. Normalization: L2 unit-norm projection (||v||_2 = 1.0) on hypersphere        │
│ 9. Comparison Metric: Cosine similarity: (a · b) / (||a|| ||b||) = a · b        │
│ 10. Vault Encryption: AES-256-GCM envelope encryption with Cloud KMS AAD binding │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. ARTIFACT & PROVENANCE FREEZE

| Component | Identifier | Artifact Path | SHA-256 Checksum |
|---|---|---|---|
| **SFace ONNX Model** | `sface_opencv_zoo_v1_primary` | `backend/models/face_recognition_sface_2021dec.onnx` | `0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79` |
| **YuNet Detector** | `yunet_2023mar` | Mobile / Native isolate | Standard OpenCV Zoo YuNet |
| **Umeyama Aligner** | `umeyama_aligner_v11` | `backend/src/biometrics/umeyama_aligner_v11.ts` | Source-verified deterministic transform |
| **Vault Cryptography** | `aes_256_gcm_kms_v3` | `backend/src/services/biometric_template_crypto.ts` | Authenticated envelope encryption |

---

## 3. GOVERNANCE INVARIANTS
1. **Zero Model Replacement**: SFace (128-D) and YuNet remain the sole authoritative facial processing engines.
2. **Threshold Immutability**: All baseline evaluations use existing thresholds (0.363 verify, 0.74 warning, 0.78 / 0.90 block).
3. **No HNSW Introduction**: Linear scan and Firestore compatibility indices are preserved.
4. **No Production Database Mutations**: All evaluation runs operate in-memory or on designated research partitions without touching `worker_profiles` or `biometric_vault`.
