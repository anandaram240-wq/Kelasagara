# RECOGNITION PIPELINE & INFERENCE AUDIT (RECOGNITION_AUDIT.md)
**Subsystem:** Kelasagara BioMatch Stage S3 / Prompt 10-ADV (Track A)  
**Date:** 10 October 2026  
**Evaluator:** Kelasagara Biometric Engineering Taskforce  
**Environment:** macOS ARM64 / Node.js v24.14.0 / ONNXRuntime v1.20.1  

---

## 1. Authoritative Preprocessing Specification

| Parameter | Authoritative Specification | Invariant / Enforcement |
|:---|:---|:---:|
| **Preprocessing ID** | `PREPROC_V1_UMEYAMA_112_RGB_RAW255` | Invariant I-06 |
| **Input Tensor Layout** | NCHW: `[1, 3, 112, 112]` | OpenCV Zoo SFace Contract |
| **Color Space** | Raw Float RGB (`swapRB = false`) | Raw [0.0 .. 255.0] Float |
| **Normalization Scale** | `1.0` (No subtraction of 127.5, no [-1..1] division) | Zero Normalization Drift |
| **Landmark Alignment** | Pure TypeScript Umeyama 5-Point Closed-Form Transform | Invariant I-06 |
| **Interpolation** | Bilinear Interpolation with Border Clamping | Sub-pixel accuracy |
| **Alignment RMS Residual** | **0.000000 px** on canonical coordinates | Exact closed-form match |

---

## 2. Component Ablations (A-01)

### Wire Codec Quality Sweep (Flutter Camera Client)
Simulates client-side JPEG compression artifacts at varying quality quantization levels:
- **Quality 95%:** Cosine Stability = **1.0000**, FTA = **0.0%**
- **Quality 80% (Flutter Default):** Cosine Stability = **1.0000**, FTA = **0.0%**
- **Quality 65% (Bandwidth Saver):** Cosine Stability = **0.9917**, FTA = **0.0%**
- **Quality 40% (Degraded 2G):** Cosine Stability = **0.9997**, FTA = **0.0%**

---

## 3. Inference Engineering & Benchmarking (A-02)

| Configuration | Model Binary Size | Storage Savings | Cold Start Latency | Concurrency 1 (p50 / p95 / p99) | Concurrency 4 (p50 / p95 / p99) | Concurrency 16 (p50 / p95 / p99) |
|:---|:---:|:---:|:---:|:---:|:---:|:---:|
| **SFace FP32 (Primary)** | 36.9 MB | Baseline | 0 ms | 8.0 / 9.4 / 9.4 ms | 34.4 / 163.0 / 163.0 ms | 132.8 / 227.2 / 231.3 ms |
| **SFace INT8 (Fallback)** | 9.4 MB | **74.5%** | 44 ms | 7.5 / 8.7 / 8.7 ms | 38.0 / 56.7 / 56.7 ms | 95.8 / 164.1 / 173.6 ms |

### Quantization Parity Analysis
- **FP32 vs INT8 Cosine Parity:** **0.959557**
- **Primary Model Choice:** SFace FP32 selected as authoritative primary; INT8 deployed as fallback under high-concurrency throttling.
