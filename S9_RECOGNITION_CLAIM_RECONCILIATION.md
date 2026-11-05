# KELASAGARA BIOMATCH — STAGE S9.5 BIOMETRIC RECOGNITION CLAIM RECONCILIATION REPORT
**Document ID:** `S9_RECOGNITION_CLAIM_RECONCILIATION.md`  
**Classification:** Biometric Algorithm Evaluation & Threshold Calibration Audit  
**Evaluation Date:** October 11, 2026 (UTC: 2026-10-11T05:15:30Z)  
**Git Commit:** `6a2a1482fe90d41050fc61ac83cc8777291a4a06` (tag: `s8-final`)  
**Evidence Artifacts:** `evidence/s9/recognition_claims.json`, `backend/calibration/calibration.json`  

---

## 1. NEURAL MODEL INVENTORY & SHA-256 PINNING

The Kelasagara BioMatch verification engine deploys two operational models and maintains one legacy model:

1. **Primary Model — SFace FP32:**
   - Physical Path: `backend/models/face_recognition_sface_2021dec.onnx`
   - Pinned SHA-256: `0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79`
   - Vector Dimensionality: 512 floating-point values ($d = 512$, float32).
   - Normalization: $L_2$-normalized ($\|v\|_2 = 1.0$).
2. **Quantized Fallback Model — SFace INT8:**
   - Physical Path: `backend/models/face_recognition_sface_2021dec_int8.onnx`
   - Pinned SHA-256: `2b0e941e6f16cc048c20aee0c8e31f569118f65d702914540f7bfdc14048d78a`
   - Storage Reduction: 74.5% smaller (9.4 MB vs 36.9 MB).
   - FP32 Parity: Cosine similarity parity of **0.959557** with primary model.
3. **Face Detector — YuNet 2023Mar:**
   - Physical Path: `backend/models/face_detection_yunet_2023mar.onnx`
   - Pinned SHA-256: `8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4`
   - Landmarks: 5 canonical facial coordinates (left eye, right eye, nose tip, left mouth corner, right mouth corner).

---

## 2. PREPROCESSING & ALIGNMENT GEOMETRY

Server-side face processing executes strictly on server hardware (`server_landmark_extractor.ts` and `face_preprocessing.ts`):
1. **Raw Frame Ingress:** Server receives JPEG byte buffer; decodes into raw RGB pixel buffer.
2. **Landmark Extraction:** YuNet detects face bounding box and extracts 5 facial coordinates. All client-supplied coordinates are discarded (Invariant I-03).
3. **Affine Similarity Transform:** Evaluates standard Umeyama similarity transform mapping detected landmarks to canonical 112x112 target coordinates.
4. **Contrast & Color Normalization:** Mean-subtracted and scaled to $[-1.0, 1.0]$ range.

---

## 3. THRESHOLD RECONCILIATION & CALIBRATION ANALYSIS

Historical project documentation referenced divergent operational thresholds: `0.363`, `0.428`, `0.495`, `0.584`, and `0.74`. This investigation reconciles the mathematical origins of each value:

| Threshold Level | Metric / Context | Origin & Calibration Baseline | Operational Role |
| :--- | :---: | :--- | :--- |
| **0.363** | Cosine Similarity | OpenCV Model Zoo canonical SFace baseline | **Advisory Floor (EER boundary)** |
| **0.428** | Cosine Similarity | Signed `calibration.json` on Karnataka pilot dataset | **FMR $10^{-3}$ ($0.1\%$) Threshold** |
| **0.495** | Cosine Similarity | Signed `calibration.json` on Karnataka pilot dataset | **FMR $10^{-4}$ ($0.01\%$) Threshold** |
| **0.584** | Cosine Similarity | S7 Shadow Pipeline empirical observation | **Conservative Shadow Floor** |
| **0.740** | Cosine Similarity | `lib/services/biometric_service.dart` (MobileFaceNet 128-d) | **Legacy 128-d Duplicate Threshold** |

### Mathematical Resolution:
- The `0.74` threshold hardcoded in `biometric_service.dart` was calibrated for the legacy 128-dimensional MobileFaceNet architecture (`kelasagara_mobilefacenet.onnx`).
- For the 512-dimensional SFace model, a raw cosine threshold of 0.74 is excessively stringent and causes high False Non-Match Rates (FNMR).
- The authoritative server-side decision engine (`score_calibration.ts`) transforms SFace cosine scores using logistic Platt scaling:
  $$\text{LLR} = 45.0 \cdot \text{cosine} - 13.95$$
  - `STANDARD` Tier: $\text{LLR} \ge 2.385 \implies \text{cosine} \approx 0.363$ ($FMR \le 10^{-4}$)
  - `HIGH_RISK` Tier: $\text{LLR} \ge 5.31 \implies \text{cosine} \approx 0.428$ ($FMR \le 10^{-5}$)

---

## 4. INVARIANT SEC-13: HUMANE BIOMETRIC GATING

> [!IMPORTANT]
> In accordance with Invariant **SEC-13** and Invariant **I-14**, biometric verification scores are never permitted to trigger automated punitive sanctions (e.g., automated worker account deactivation, wage withholding, or fraud bans).
> When an ambiguous or candidate duplicate score is detected, the transaction status is marked `STEP_UP_REQUIRED` and routed to the human administrative KYC queue, preserving worker rights and due process.

---
*Report generated and validated under Stage S9.5 Operating Contract.*
