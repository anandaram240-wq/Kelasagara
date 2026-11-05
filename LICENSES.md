# THIRD-PARTY INTELLECTUAL PROPERTY & MODEL LICENSES AUDIT
**Subsystem:** Kelasagara BioMatch V9 / Stage S2  
**Audit Date:** 10 October 2026  
**Auditor Persona:** Application Security Engineer & Intellectual Property Counsel  
**Compliance Standard:** Commercial Deployment Eligibility Audit

---

## 1. Executive Summary

This document establishes the authoritative licensing, training data provenance, and commercial usability audit for all neural network weights, geometric alignment routines, and software components utilized in the **Kelasagara BioMatch** biometric identity subsystem.

Commercial systems deployed in production must never incorporate models trained on research-only restricted datasets (e.g., standard non-commercial InsightFace MS1MV2 research releases) without commercial licenses. Kelasagara BioMatch adheres to Apache-2.0 and BSD-3-Clause licensed backbones.

---

## 2. Neural Network Model Weights Registry

| Model Artifact | Version / Digest | Architecture | Upstream Source | License | Commercial Usability |
|:---|:---|:---:|:---|:---:|:---:|
| `face_recognition_sface_2021dec.onnx` | `0ba9fbfa01b5...` | SFace FP32 (128-D) | [OpenCV Zoo](https://github.com/opencv/opencv_zoo) | **Apache-2.0** | **APPROVED** (Permissive Apache 2.0) |
| `face_recognition_sface_2021dec_int8.onnx` | `2b0e941e6f16...` | SFace INT8 (128-D) | [OpenCV Zoo](https://github.com/opencv/opencv_zoo) | **Apache-2.0** | **APPROVED** (Permissive Apache 2.0) |
| `face_detection_yunet_2023mar.onnx` | `8f2383e44c21...` | YuNet Detector | [OpenCV Zoo](https://github.com/opencv/opencv_zoo) | **Apache-2.0** | **APPROVED** (Permissive Apache 2.0) |
| `kelasagara_mobilefacenet.onnx` | `cde3799f041e...` | MobileFaceNet (128-D) | Local PyTorch uninitialized export | Internal Research | **RESEARCH ONLY** (Automated clearance denied) |

---

## 3. Detailed Component Audits

### 3.1 OpenCV Zoo SFace & YuNet
- **Upstream Repository:** `https://github.com/opencv/opencv_zoo`
- **Copyright:** (c) 2021-2026 OpenCV Foundation
- **License Terms:** Apache License, Version 2.0.
  - Grants perpetual, worldwide, non-exclusive, no-charge, royalty-free, irrevocable copyright license to reproduce, prepare derivative works of, publicly display, publicly perform, sublicense, and distribute the work and such derivative works in source or object form.
- **Commercial Assessment:** Cleared for production deployment. SFace serves as the authoritatively cleared backbone for Kelasagara BioMatch.

### 3.2 ISO/IEC 29794-5 Quality Assessment (OFIQ Standards)
- **Standard:** ISO/IEC 29794-5:2024 "Information technology — Biometric data interchange formats — Part 5: Face image data"
- **Reference Implementation:** NIST / BSI Open Source Face Image Quality (OFIQ)
- **License Terms:** BSD 3-Clause / NIST Public Domain.
- **Kelasagara Implementation:** Clean-room pure TypeScript implementation (`QualityGateService`), zero binary linkage to external proprietary libraries.

### 3.3 Umeyama Closed-Form Alignment
- **Mathematical Origin:** Shinji Umeyama, *"Least-squares estimation of transformation parameters between two point patterns"*, IEEE Transactions on Pattern Analysis and Machine Intelligence (PAMI), 1991.
- **License:** Mathematical algorithm in the public domain. Pure TypeScript implementation in `face_preprocessing.ts`.

### 3.4 MobileFaceNet (Research-Only Notice)
- **Status:** Restricted to `ml/research_only/` (Ticket T-16).
- **Governance:** ModelRegistry permanently assigns `tier: "RESEARCH_ONLY"` and `clearedForAutomatedApproval: false`. If loaded into the backend, any matching attempt strictly resolves to `pending_review` or `technical_failure_retry`.
