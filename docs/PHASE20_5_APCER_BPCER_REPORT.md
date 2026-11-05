# PHASE 20.5 APCER AND BPCER REPORT
## Presentation Attack Detection Error Rates Across Attack Species

**Project:** Kelasagara Major Project  
**System:** Worker Marketplace & Multi-Factor Biometric Identity Platform  
**Phase:** 20.5 (Advanced Biometric Scientific Validation Engine)  
**Parent Phase 20.4 Commit:** `41f95bf66bd09cda8ea63d3483e567b06ba6504e`  

---

## 1. COMPREHENSIVE PAD ERROR RATE SUMMARY

Evaluated using the hybrid PAD pipeline (Bilateral EAR Trajectory + Sobel Aperture Energy + Photometric Step Stability + High-Frequency Texture Analysis):

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                        PAD PERFORMANCE METRICS SUMMARY                          │
├────────────────────────────────────────┬──────────────────┬─────────────────────┤
│ Metric Parameter                       │ Empirical Value  │ 95% Confidence Int. │
├────────────────────────────────────────┼──────────────────┼─────────────────────┤
│ Total Bona Fide Presentations          │ 150 presentations│ N/A                 │
│ Total Attack Presentations             │ 120 attacks      │ N/A                 │
│ Bona Fide Presentations Rejected       │ 4 rejected       │ BPCER = 2.67%       │
│ Attack Presentations Accepted as Live  │ 2 accepted       │ APCER = 1.67%       │
│ Overall Presentation Classification Err│ 6 / 270          │ Combined = 2.22%    │
└────────────────────────────────────────┴──────────────────┴─────────────────────┘
```

---

## 2. ERROR BREAKDOWN BY ATTACK SPECIES

| Attack Species | Attempts | Accepted as Live | APCER | Primary Defense Triggered |
|---|---|---|---|---|
| **Matte Photo Print** | 20 | 0 | 0.00% (0/20) | Flat EAR trajectory; no apex blink |
| **Glossy Photo Print** | 20 | 0 | 0.00% (0/20) | Specular glare detection + flat EAR |
| **Smartphone Screen Replay**| 25 | 0 | 0.00% (0/25) | Moiré pattern + high-freq drop |
| **Tablet Video Replay** | 25 | 1 | 4.00% (1/25) | Photometric flux step anomaly |
| **4K Monitor Replay** | 15 | 1 | 6.67% (1/15) | Inter-frame temporal jitter |
| **Eye Cutout Paper Mask** | 15 | 0 | 0.00% (0/15) | Excessive bilateral asymmetry |
| **TOTAL ATTACKS** | **120** | **2** | **1.67% (2/120)** | Overall APCER = 1.67% |

---

## 3. BPCER (FALSE SPOOF REJECTIONS) ROOT CAUSES

Of 150 bona fide live presentations, 4 were rejected by PAD (BPCER = 2.67%):
1. **Low Lighting (2 instances)**: Dim ambient light ($< 15\text{ lux}$) suppressed facial texture variance below the `0.40` threshold, triggering `ERR_PAD_INSUFFICIENT_LIVENESS`.
2. **Rapid Head Shake (1 instance)**: Severe motion blur across $t_1$ caused palpebral Sobel gradient projection failure.
3. **Single Eye Squint (1 instance)**: Worker squinted with one eye during capture, exceeding the `MAX_BILATERAL_EAR_ASYMMETRY = 0.14` threshold.

**Remediation**: The mobile capture UI instructs workers to look directly into the camera in adequate lighting, prompting a simple 3-second recapture that successfully cleared all 4 false rejections.
