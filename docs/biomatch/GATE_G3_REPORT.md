# GATE G3 REPORT: MODEL, DATA & LICENSE SELECTION

**Subsystem:** Kelasagara BioMatch V7  
**Gate:** **Gate G3** (Phase 3: Model, Data and License Selection)  
**Status:** **PASSED**  
**Release Readiness Level (RRL):** **RRL-0 (Research Prototype)**  
**Target Platform:** Firebase Spark Plan (Free Tier) | Sole Database: Cloud Firestore  
**Branch:** `biomatch/v7-hardening`  
**Date:** 2026-10-10  

---

### 1. SUMMARY SPECIFICATION

| Field | Detail |
|---|---|
| **Gate** | **Gate G3 (Phase 3)** |
| **Status** | **PASSED** |
| **Evidence IDs** | **EV-021** (`docs/biomatch/LICENSE_MATRIX.md`), **EV-022** (`docs/biomatch/MODEL_SELECTION.md`), **EV-023** (`docs/biomatch/MODEL_CARDS.md`) |
| **What Changed in Risk Register** | - **RISK-03 (Uncalibrated / Untrained Model Weights):** Updated with Phase 3 code audit findings (Defect ML-001 in `train_mobilefacenet.py` confirmed root cause; Defect ML-002 random noise in INT8 calibration identified). Model locked to `RESEARCH_ONLY` in registry.<br/>- **RISK-11 (Upstream Training Data Copyright Contamination):** Added to risk register: SFace (CASIA-WebFace) and YuNet (WIDER FACE) training data licenses prohibit commercial usage without indemnity. |
| **Decisions Needed from Owner** | Owner decision on the Four Paths (P-A through P-D):<br/>- **Path P-B (Recommended):** Train Kelasagara's own MobileFaceNet using Microsoft DigiFace-1M synthetic dataset (1.2M images, CC-BY 4.0) + consented Indian pilot faces.<br/>- In the interim, confirm that all models remain strictly tagged as `RESEARCH_ONLY` under RRL-0. |
| **Next Step** | **Proceed autonomously to PHASE 4:** Reference Pipeline, Quality, Parity (`docs/biomatch/PIPELINE_SPEC.md`): implement standardized 5-point facial landmark similarity alignment (Umeyama algorithm), bounding box crop normalization, input tensor parity checks between Flutter Dart and Node.js ONNX runtime, and golden-vector verification tests. |

---

### 2. GATE CRITERIA CHECKLIST

- [x] **License Matrix Complete:** `docs/biomatch/LICENSE_MATRIX.md` catalogs every detector (ML Kit `CLEARED`, MediaPipe `CLEARED`, YuNet `UNCLEARED`), recognizer (MobileFaceNet `RESEARCH_ONLY`, SFace `UNCLEARED`, InsightFace `PROHIBITED`), PAD engine, quality scorer (OFIQ `CLEARED`), and dataset.
- [x] **Primary & Fallback Lineage Named:**
  - Primary: `kelasagara_mobilefacenet_v1_arcface` (128-D, `RESEARCH_ONLY`).
  - Fallback / Shadow: `sface_opencv_zoo` (128-D, `RESEARCH_ONLY`).
  - Model space isolation enforced by `ModelRegistry` (Invariant I-06).
- [x] **Path P-A..P-D Proposed:** Path P-B (Own training on DigiFace-1M synthetic data + consented pilot) proposed as the sole legally and ethically defensible path that preserves the zero-billing, own-model non-negotiable requirements.
- [x] **Custom Training Status Formally Decided:** Custom training execution is **`BLOCKED (Q5 Default Applied)`** until consented dataset and training compute are authorized. Unblock criteria documented.
- [x] **Training Code Audited:** Detailed analysis of `train_mobilefacenet.py`, `export_mobilefacenet_onnx.py`, and `export_tflite_int8.py` completed. Confirmed root cause of random weights (ML-001) and identified random noise INT8 calibration bug (ML-002).
- [x] **Model Cards Authored:** Formal FAT* model cards for MobileFaceNet and SFace completed in `docs/biomatch/MODEL_CARDS.md`.
