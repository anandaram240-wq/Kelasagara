# PHASE 20.8: SEVEN-SIGNAL BIOMETRIC PAD FUSION ARCHITECTURE
**System:** Kelasagara Biometric Identity & Authentication Platform  
**Phase:** 20.8 (PAD Signal Extraction and Optical Evidence Engine)  
**Document Code:** ARCH-PAD-FUSION-2026-008  
**Author:** Principal Biometric Systems Architect & Senior TypeScript Engineer  
**Date:** November 2026  
**Status:** ARCHITECTURE RATIFIED & EXPERIMENTALLY VERIFIED

---

## 1. Executive Summary & Fusion Philosophy

Biometric Presentation Attack Detection (PAD) cannot depend on any single optical or temporal feature. A robust defense-in-depth architecture requires the **fusion of multiple orthogonal physical signals**, ranging from high-frequency spatial aliasing to cryptographic challenge compliance.

This document specifies the formal **Seven-Signal Fusion Engine** implemented in `CandidatePadHardenedEngine.fusePadSignals()`.

---

## 2. The Seven Orthogonal Sensing Signals

```
+------------------------------------------------------------------------------------------------------------------------------------+
| SIGNAL # | SIGNAL NAME              | EXTRACTION ALGORITHM               | NUMERICAL BOUND / THRESHOLD | DEFENSE OBJECTIVE         |
+------------------------------------------------------------------------------------------------------------------------------------+
| 1        | Face Image Quality (FIQA)| Laplacian variance & luma balance  | Sharpness >= 15.0           | Eliminates motion blur &  |
|          |                          |                                    | 40 <= Luma <= 220           | extreme underexposure.    |
|          |                          |                                    |                             |                           |
| 2        | Pose & Motion Continuity | YuNet landmark Euclidean trajectory| Yaw, Pitch delta <= 15 deg  | Prevents face-swap        |
|          |                          | across Frame 0 to Frame 2          |                             | presentation attacks.     |
|          |                          |                                    |                             |                           |
| 3        | Ocular Temporal Aperture | Vertical Sobel gradient projection | Apex Ratio <= 0.60          | Detects physiological eye |
|          |                          | around left & right eye landmarks  |                             | blink trajectory.         |
|          |                          |                                    |                             |                           |
| 4        | Spatial Moiré Grid Score | 2D DCT-II high-frequency energy &  | R_high >= 0.380 AND         | Detects periodic RGB      |
|          |                          | mean block spectral concentration  | C_spectral >= 0.200         | subpixel screen grids.    |
|          |                          |                                    |                             |                           |
| 5        | Specular Highlight Profile| 2D saturation area compactness    | S_specular >= 0.12          | Supports 2D reflection    |
|          |                          | (Image-derived heuristic)          | (Secondary supporting cue)  | profile assessment.       |
|          |                          |                                    |                             |                           |
| 6        | Frame Sequence Continuity| Hardware timestamp monotonicity &  | T0 < T1 < T2                | Intercepts video replay,  |
|          |                          | inter-frame interval check         | 40ms <= dt <= 350ms         | freeze & frame injection. |
|          |                          |                                    |                             |                           |
| 7        | Dynamic Challenge Match  | Action classifier vs server nonce  | Requested action completed  | Blocks pre-recorded       |
|          |                          | within expiration window           | before deadline (< 3500ms)  | looping video replays.    |
+------------------------------------------------------------------------------------------------------------------------------------+
```

---

## 3. Formal Classification Decision States

In accordance with ISO/IEC 30107-3:2017, the candidate fusion pipeline outputs one of six standardized, mutually exclusive operational states:

```
                                  MULTI-SIGNAL FUSION FLOW
                                             |
                                 [Check 1: Quality / FIQA]
                                     /               \
                                (Fail)               (Pass)
                                  v                     v
                    CAPTURE_QUALITY_INSUFFICIENT  [Check 2: Frame Continuity]
                                                      /               \
                                                 (Fail)               (Pass)
                                                   v                     v
                                           CHALLENGE_INVALID     [Check 3: Moiré & Aperture]
                                                                     /               \
                                                                (Attack)            (Pass)
                                                                   v                   v
                                                    PRESENTATION_ATTACK_SUSPECTED  [Check 4: Pose / Heuristics]
                                                                                       /               \
                                                                                  (Ambiguous)         (Clear)
                                                                                       v                 v
                                                                            MANUAL_REVIEW_REQUIRED  BONA_FIDE_CANDIDATE
```

### State Definitions:
1. **`BONA_FIDE_CANDIDATE`:** All seven signals pass within verified normal physiological bounds. Eligible for biometric 1:1 or 1:N recognition matching.
2. **`PRESENTATION_ATTACK_SUSPECTED`:** Affirmative physical spoof detected (periodic display grid detected, missing eye aperture trajectory, or identity discontinuity).
3. **`CAPTURE_QUALITY_INSUFFICIENT`:** Frame degraded by extreme motion blur, darkness, or lens smearing. User is prompted to re-attempt capture.
4. **`CHALLENGE_INVALID`:** Temporal sequence violated, timestamps non-monotonic, or user failed dynamic micro-gesture.
5. **`SIGNAL_UNAVAILABLE`:** An internal feature extractor failed due to memory or decoding errors. (Fail-closed; never authorizes authentication).
6. **`MANUAL_REVIEW_REQUIRED`:** Borderline optical measurements or ambiguous pose jitter. Enqueued for Compliance Officer audit (`CASE-XXXX`).

---

## 4. Production Isolation & Fail-Safe Invariants

1. **Non-Interference Invariant:** During Phase 20.8, the seven-signal fusion engine runs in **isolated experimental comparison mode**. The legacy production `TemporalPadValidator` remains authoritative for all production eKYC decisions.
2. **Fail-Closed Security Invariant:** If any optical extractor throws an uncaught exception, the fusion engine automatically returns `SIGNAL_UNAVAILABLE` with an immediate rejection.
