# KELASAGARA BIOMATCH V7: MODEL CARDS

**Document ID:** `MC-BIOMATCH-V7-001`  
**Phase:** Phase 3 (Model, Data and License Selection)  
**As-of Date:** 2026-10-10  
**Standard:** Adheres to Mitchell et al. (FAT* 2019) *Model Cards for Model Reporting*.  

---

## MODEL CARD 1: `kelasagara_mobilefacenet_v1_arcface`

### 1.1 Model Details
- **Model Name:** Kelasagara MobileFaceNet ArcFace Backbone
- **Identifier:** `kelasagara_mobilefacenet_v1_arcface`
- **Model Version:** `v1.0.0-research`
- **Release Date:** 2026-10-10
- **Model Type:** Deep Convolutional Neural Network (Depthwise Separable Convolutions + Global Depthwise Convolution) with Additive Angular Margin Loss (ArcFace).
- **Framework & Format:** PyTorch 2.x $\rightarrow$ ONNX Runtime (Opset 14).
- **Artifact Path:** `backend/models/kelasagara_mobilefacenet.onnx`
- **Artifact SHA-256 Checksum:** `cde3799f041eca6a6a99bfac53d9e97eb81ff34ac450d519aa41a9c99bef7d7c`
- **Code License:** Apache 2.0
- **Weight License:** Apache 2.0 (Kelasagara Project Internal Artifact)
- **Status in Registry:** **`RESEARCH_ONLY`** (`clearedForAutomatedApproval: false`).

### 1.2 Intended Use
- **Primary Intended Use:** Pipeline integration testing, latency benchmarking, and software harness validation for the Kelasagara BioMatch subsystem.
- **Out-of-Scope & Prohibited Uses:**
  - Automated production user approval or account verification.
  - Legal identity verification or criminal forensic comparison.
  - Commercial production deployment without retraining on consented data.

### 1.3 Technical Architecture & Inputs
- **Input Tensor:** `[Batch, 3, 112, 112]` (Float32, RGB, values normalized to $[-1.0, 1.0]$).
- **Output Tensor:** `[Batch, 128]` (Float32, L2-normalized unit vector residing on unit hypersphere $S^{127}$, $\|v\|_2 = 1.0$).
- **Parameter Count:** 990,368 parameters (< 1M parameters).
- **Runtime Dependencies:** `onnxruntime-node` (Backend) / `tflite_flutter` (Edge mobile).

### 1.4 Training Data & Provenance
- **Training Dataset:** **None / Randomly Initialized**. The current weight artifact was generated via PyTorch random parameter initialization (`torch.randn`).
- **Proven Defect:** The model has zero identity discrimination capability in real-world deployment. Unique enrollments resolve strictly to `PENDING_REVIEW` under Invariants I-01, I-07, and I-18.

---

## MODEL CARD 2: `sface_opencv_zoo`

### 2.1 Model Details
- **Model Name:** SFace: Sigmoid-Constrained Hypersphere Facial Recognition
- **Identifier:** `sface_opencv_zoo`
- **Model Version:** `2021dec`
- **Source:** OpenCV Model Zoo (`opencv/opencv_zoo`) based on Zhong et al., IEEE T-BIOM 2021.
- **Model Type:** Deep Convolutional Neural Network with Sigmoid-constrained ArcFace loss.
- **Format:** ONNX Float32 (`face_recognition_sface_2021dec.onnx`).
- **Code License:** Apache 2.0 (OpenCV Zoo)
- **Weight License:** Apache 2.0 (OpenCV Zoo Distribution)
- **Training Data Provenance:** CASIA-WebFace (Chinese Academy of Sciences).
- **Status in Registry:** **`RESEARCH_ONLY` / `EVALUATION_ONLY`** (`clearedForAutomatedApproval: false`).

### 2.2 Intended Use
- **Primary Intended Use:** Secondary shadow model and evaluation benchmark for cross-model independence experiments.
- **Out-of-Scope & Commercial Warning:** Upstream training dataset (CASIA-WebFace) was compiled under academic non-commercial terms and has been retracted. Lacks commercial warranty/indemnity; restricted to non-commercial research harness evaluation.

### 2.3 Technical Architecture & Inputs
- **Input Tensor:** `[1, 3, 112, 112]` (Float32, BGR format, pixel range $[0.0, 255.0]$).
- **Output Tensor:** `[1, 128]` (Float32, L2-normalized feature vector).
- **Parameter Count:** $\sim 4.1\text{M}$ parameters.
- **Input Alignment Requirement:** 5-point similarity transformation alignment targeting canonical eye, nose, and mouth corner coordinates.

### 2.4 Ethical & Demographic Considerations
- **Demographic Bias:** Trained primarily on celebrity datasets with known bias toward Caucasian and East Asian skin tones. Performance on Indian rural demographics, varying facial hair, turbans, and outdoor lighting conditions has not been independently calibrated.
- **Mitigation:** ADR-005 tri-state policy and mandatory human review for borderline cases ($0.65 \le \text{sim} \le 0.74$).
