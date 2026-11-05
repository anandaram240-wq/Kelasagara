# PRESENTATION ATTACK DETECTION (PAD) EVALUATION REPORT
**Standard:** ISO/IEC 30107-3 Compliance & Stage S2 Dry Run (Ticket E-04)  
**Date:** 10 October 2026  
**Evaluator:** Kelasagara Biometric Engineering & Hardening Team  
**Evaluation Scope:** 6 Adversarial Attack Species across 300 Synthetic Presentation Attacks  

---

## 1. Executive Summary & Metrics

| Metric | Target Standard | Kelasagara Stage S2 Measured | Status |
|:---|:---:|:---:|:---:|
| **APCER (Attack Presentation Classification Error Rate)** | < 1.0% | **0.00%** (0 / 300 bypassed) | ✅ PASS |
| **BPCER (Bona Fide Presentation Classification Error Rate)** | < 3.0% | **1.20%** (Genuine user compliance) | ✅ PASS |
| **Primary Physical Defense** | Spatial-Temporal Variance | **Invariant I-30** (< 0.5px motion threshold) | ✅ ENFORCED |
| **Interactive Handshake Defense** | Multi-Action Randomized Gestures | **Invariant I-29** (Blink, Smile, Turn Left/Right) | ✅ ENFORCED |

---

## 2. Species Breakdown (ISO/IEC 30107-3)

| Species ID | Species Name | Category | Trials | Blocked | Bypassed | APCER | Core Defense Mechanism |
|:---:|:---|:---:|:---:|:---:|:---:|:---:|:---|
| **PAD-01** | 2D Color Paper Printout (Photo) | PRESENTATION_ATTACK | 50 | 50 | 0 | 0.00% | Temporal Landmark Variance Threshold (< 0.5px) + Invariant I-30 |
| **PAD-02** | Smartphone Display Replay | PRESENTATION_ATTACK | 50 | 50 | 0 | 0.00% | Randomized Multi-Action Gesture Challenge + Invariant I-29 |
| **PAD-03** | Tablet Display Replay | PRESENTATION_ATTACK | 50 | 50 | 0 | 0.00% | Dynamic Challenge Coordination + Invariant I-29 / I-30 |
| **PAD-04** | Laptop Fullscreen Video Playback | PRESENTATION_ATTACK | 50 | 50 | 0 | 0.00% | Server-Side Gesture Sequence Verification + Invariant I-29 |
| **PAD-05** | Paper Mask / Eye Cutout | PRESENTATION_ATTACK | 50 | 50 | 0 | 0.00% | Rigid Surface Variance & Action Order Check + Invariant I-30 |
| **PAD-06** | Pre-recorded Single Gesture (Blink Loop) | PRESENTATION_ATTACK | 50 | 50 | 0 | 0.00% | Dynamic Randomized Multi-Action Handshake + Invariant I-29 |

---

## 3. Findings & Mitigation Audit

1. **Static 2D Paper Prints (PAD-01):** Intercepted via temporal landmark variance calculated over a 3-frame burst. Static prints generate < 0.1px motion and are flagged as `STATIC_2D_PHOTO`.
2. **Replay Video Screens (PAD-02, PAD-03, PAD-04):** Phone, tablet, and laptop screen replay attacks fail because the pre-recorded video cannot adapt dynamically to the server's randomized gesture sequence.
3. **Paper Mask Cutouts (PAD-05):** Rigid surface motionlessness intercepts cutouts even when eye blinks occur behind eye-holes.
4. **Pre-recorded Blink Loops (PAD-06):** Passive repetitive actions fail the server-mandated action ordering (e.g. SMILE followed by TURN_LEFT).
