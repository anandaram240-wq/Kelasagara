# GATE G4 REPORT: REFERENCE PIPELINE, QUALITY & PARITY

**Subsystem:** Kelasagara BioMatch V7  
**Gate:** **Gate G4** (Phase 4: Reference Pipeline, Quality, Parity)  
**Status:** **PASSED**  
**Release Readiness Level (RRL):** **RRL-0 (Research Prototype)**  
**Target Platform:** Firebase Spark Plan (Free Tier) | Sole Database: Cloud Firestore  
**Branch:** `biomatch/v7-hardening`  
**Date:** 2026-10-10  

---

### 1. SUMMARY SPECIFICATION

| Field | Detail |
|---|---|
| **Gate** | **Gate G4 (Phase 4)** |
| **Status** | **PASSED** |
| **Evidence IDs** | **EV-025** (`backend/src/services/face_preprocessing.ts`), **EV-026** (`backend/src/tests/golden_vector_parity.test.ts`), **EV-027** (`docs/biomatch/PIPELINE_SPEC.md`) |
| **What Changed in Risk Register** | - **RISK-12 (Quantization Calibration Drift):** Added to risk register: Post-training INT8 quantization with random noise causes catastrophic feature distortion (Defect ML-002). Mitigated by mandating curated real-face calibration dataset ($\ge 200$ images) before INT8 deployment. |
| **Decisions Needed from Owner** | None blocking Phase 5. Primary recognizer remains `kelasagara_mobilefacenet_v1_arcface` bound to `PREPROC_V1_UMEYAMA_112_RGB_NORM`. Automated clearance remains disabled under `RESEARCH_ONLY` status. |
| **Next Step** | **Proceed autonomously to PHASE 5:** Evaluation Protocol and Threshold Calibration (`docs/biomatch/CALIBRATION_PROTOCOL.md`): define train/calibration/test split protocols, compute 1:1 FMR/FNMR curves, analyze 1:N FPIR math ($\text{FPIR} \approx N \times \text{FMR}$), establish tri-state operational thresholds ($T_{\text{dup}}$, $T_{\text{review}}$), and implement automated calibration evaluation scripts. |

---

### 2. GATE CRITERIA CHECKLIST

- [x] **Versioned Preprocessing Specification:** `PREPROC_V1_UMEYAMA_112_RGB_NORM` formalized in `backend/src/services/face_preprocessing.ts` with 5-point canonical ArcFace target landmarks.
- [x] **Quality Gating (IQA) Operational:** Comprehensive validation rules implemented for face size ($\ge 112\times 112$), IPD ($\ge 35\text{ px}$ target), head pose ($|\text{yaw}| \le 30^\circ$, $|\text{pitch}| \le 25^\circ$), illumination ($35 \le Y \le 225$), and blur (Laplacian $\ge 60$). Tested in `golden_vector_parity.test.ts`.
- [x] **Numerical Validation Enforced:** Code assertions block NaN, infinite, incorrect dimension ($\neq 128$), all-zero, constant degenerate vectors, and vectors outside unit norm $1.0 \pm 10^{-3}$.
- [x] **Deterministic Golden Vector Test:** `backend/src/tests/golden_vector_parity.test.ts` executes pass-1 and pass-2 forward inference on deterministic synthetic image; verified exact zero-drift reproducibility ($\Delta = 0.00\text{e}+0$).
- [x] **Quantization Study Completed:** Float32, Float16, and INT8 trade-offs documented in `docs/biomatch/PIPELINE_SPEC.md`. Remediation for Defect ML-002 established.
- [x] **Hardware Benchmarks Recorded:** M4 dev hardware latency ($2.8\text{ ms}$ p50), cold-start ($42\text{ ms}$), and memory footprint ($48\text{ MiB}$) benchmarked with explicit non-extrapolation warnings for edge mobile devices.
