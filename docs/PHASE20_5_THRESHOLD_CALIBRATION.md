# PHASE 20.5 THRESHOLD CALIBRATION
## Calibration Experiments on Partition B and Proposed Operating Windows

**Project:** Kelasagara Major Project  
**System:** Worker Marketplace & Multi-Factor Biometric Identity Platform  
**Phase:** 20.5 (Advanced Biometric Scientific Validation Engine)  
**Parent Phase 20.4 Commit:** `41f95bf66bd09cda8ea63d3483e567b06ba6504e`  
**Dataset Evaluated:** Dataset Partition B (Calibration - 15 Subjects, 135 Samples)  

---

## 1. CALIBRATION OBJECTIVE

Evaluate whether tuning the historical OpenCV SFace threshold ($\theta = 0.363$) yields measurable improvements in False Match Rate (FMR) without increasing False Non-Match Rate (FNMR):
- **Partition B Isolation**: Calibration experiments were conducted strictly on Partition B. Partition C (Holdout) remained untouched.
- **Production Baseline Preservation**: Baseline operating thresholds remained frozen during all tests.

---

## 2. PARTITION B SWEEP RESULTS

| Threshold ($\theta$) | Calibration FMR | Calibration FNMR | Tradeoff Assessment |
|---|---|---|---|
| **0.300** | 0.0050 (1/200) | 0.0000 (0/80) | Too permissive; allows edge impostors |
| **0.363 (Current Baseline)**| **0.0000 (0/200)** | **0.0000 (0/80)** | **Optimal zero-error operating point** |
| **0.420** | 0.0000 (0/200) | 0.0000 (0/80) | Increased security margin against impostors |
| **0.480** | 0.0000 (0/200) | 0.0000 (0/80) | Conservative verification floor |
| **0.550** | 0.0000 (0/200) | 0.0125 (1/80) | First genuine rejection observed (Low light) |
| **0.650** | 0.0000 (0/200) | 0.0500 (4/80) | Unacceptable FNMR for 1:1 eKYC |

---

## 3. CALIBRATION INSIGHTS

1. **Current 0.363 Baseline is Robust**: The OpenCV reference threshold of 0.363 exhibits zero false non-matches and zero false matches on both Partition A (Development) and Partition B (Calibration).
2. **Potential Future Hardening**: While $\theta = 0.420$ provides an additional security buffer, elevating the baseline threshold in production without large-scale field data poses an unverified risk of increased FNMR under extreme lighting conditions.
3. **Recommendation**: Retain $\theta = 0.363$ as the primary production baseline.
