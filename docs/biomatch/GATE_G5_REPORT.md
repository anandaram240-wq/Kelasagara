# GATE G5 REPORT: EVALUATION PROTOCOL & THRESHOLD CALIBRATION

**Subsystem:** Kelasagara BioMatch V7  
**Gate:** **Gate G5** (Phase 5: Evaluation Protocol and Threshold Calibration)  
**Status:** **PASSED**  
**Release Readiness Level (RRL):** **RRL-0 (Research Prototype)**  
**Target Platform:** Firebase Spark Plan (Free Tier) | Sole Database: Cloud Firestore  
**Branch:** `biomatch/v7-hardening`  
**Date:** 2026-10-10  

---

### 1. SUMMARY SPECIFICATION

| Field | Detail |
|---|---|
| **Gate** | **Gate G5 (Phase 5)** |
| **Status** | **PASSED** |
| **Evidence IDs** | **EV-028** (`eval/scripts/calibrate_thresholds.py`), **EV-029** (`eval/results/calibration_evaluation.json`), **EV-030** (`docs/biomatch/CALIBRATION_PROTOCOL.md`), **EV-031** (`docs/biomatch/EVAL_REPORT.md`) |
| **What Changed in Risk Register** | - **RISK-05 (Demographic Calibration Gap):** Formally grounded in statistical theory: Rule of Three bounds and 1:N open-set scaling ($\text{FPIR} \approx N \times \text{FMR}$) demonstrated. Proven that $\text{FPIR} \le 1\%$ at $N = 50,000$ represents an unmeasurable tail requiring $> 14\text{M}$ trials. Thresholds $T_{\text{dup}} = 0.74$ and $T_{\text{review}} = 0.65$ formalized as `PROVISIONAL`. System enforces **review-only** mode (Invariant I-01, I-07). |
| **Decisions Needed from Owner** | Owner approval to initiate pilot demographic field collection under the protocol defined in `docs/biomatch/CALIBRATION_PROTOCOL.md` (300 consented subjects, 3 device tiers, Karnataka region). In the interim, confirm review-only operational mode. |
| **Next Step** | **Proceed autonomously to PHASE 6:** Liveness, Presentation-Attack (PAD) and Injection-Attack (IAD) Defense (`docs/biomatch/PAD_IAD_DEFENSE.md`): evaluate ML Kit EAR blink dynamics, reflection challenge, App Check Play Integrity token binding, virtual camera detection, and client tampering resistance. |

---

### 2. GATE CRITERIA CHECKLIST

- [x] **Evaluation Protocol Defined:** Identity-disjoint splits ($60\%$ train, $20\%$ calibration, $20\%$ frozen test) specified in `docs/biomatch/CALIBRATION_PROTOCOL.md`.
- [x] **Indian Demographic Collection Protocol Authored:** Standards for $\ge 300$ subjects, 3 device tiers, lighting variations, glasses/turbans/beards, repeat sessions, and bilingual DPDP consent instruments documented.
- [x] **Rule of Three Sample Sizes Calculated:** Statistical bounds for FMR $\in [10^{-2}, 10^{-7}]$ computed in `eval/scripts/calibrate_thresholds.py` and output to `eval/results/calibration_evaluation.json`.
- [x] **1:N Gallery Scaling Evaluated:** Mathematically established that state-wide scaling ($N \ge 50,000$) requires per-comparison FMR $\le 2.01 \times 10^{-7}$ ($> 14.9\text{M}$ trials), formally designating large-scale accuracy claims as **HYPOTHESES**.
- [x] **Tri-State Provisional Mode Implemented:** Operational thresholds $T_{\text{dup}} = 0.74$ and $T_{\text{review}} = 0.65$ designated as `PROVISIONAL`. Automated hard denial is prohibited; all unique enrollments resolve to `PENDING_REVIEW` under RRL-0.
- [x] **Review Queue Workload Modeled:** Proved that at 100 enrollments/day, the review queue receives only $3.0$ to $5.0$ flags/day ($\text{PPV} = 32.4\% \text{ to } 59.5\%$), requiring $< 15$ minutes of reviewer time daily.
- [x] **Evaluation Report Authored:** Complete report with threshold provenance table and fusion study cataloged in `docs/biomatch/EVAL_REPORT.md`.
