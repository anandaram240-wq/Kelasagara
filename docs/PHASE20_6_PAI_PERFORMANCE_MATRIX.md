# PHASE 20.6 PAI PERFORMANCE MATRIX
## Granular Attack Instrument Taxonomy, Capture Conditions, and Error Bounds

**Project:** Kelasagara Major Project  
**System:** Worker Marketplace & Biometric Identity Platform  
**Phase:** 20.6 (Biometric Evidence Integrity & Controlled Pilot Readiness)  
**Standard:** ISO/IEC 30107-3:2023  
**Lead Auditor:** Presentation Attack Detection Research Engineer  
**Date:** 2026-10-31  

---

## 1. PRESENTATION ATTACK INSTRUMENT (PAI) TAXONOMY

In accordance with ISO/IEC 30107-3, presentation attack instruments evaluated in the Kelasagara framework span Level 1 and Level 2 attacks:

| Species Code | PAI Description | Attack Level | Media Type | Vulnerability Mechanism Target |
| :--- | :--- | :--- | :--- | :--- |
| `PRINTED_PHOTO_MATTE` | 300 DPI high-resolution matte photo print | Level 1 | 2D Print | Texture blur, zero temporal ocular motion |
| `PRINTED_PHOTO_GLOSSY` | High-gloss photo print with specular reflection | Level 1 | 2D Print | Specular glare artifact, lack of corneal depth |
| `SCREEN_REPLAY_SMARTPHONE` | 6.1" OLED smartphone replay (1080p, 60fps) | Level 1 | 2D Display | Moire pattern, refresh flicker, EAR stability |
| `SCREEN_REPLAY_TABLET` | 11" 120Hz IPS tablet replay with blink sync | Level 2 | 2D Display | High luminance, temporal synthetic blink bypass |
| `SCREEN_REPLAY_4K_MONITOR` | 27" 4K IPS desktop monitor replay | Level 1 | 2D Display | Geometric aspect distortion, pixel grid |
| `PRE_RECORDED_VIDEO_LOOP` | Looped video stream simulating idle head motion | Level 1 | 2D Video | Periodicity in micro-movements, burst disparity |
| `SYNTHETIC_DEEPFAKE_VIDEO` | Generative face-swap video rendering | Level 2 | Synthetic | Edge warping, boundary inconsistencies |
| `PARTIAL_FACIAL_CUTOUT` | Printed paper mask with cutouts for real eyes | Level 2 | Semi-Rigid | Boundary step discontinuity, depth mismatch |

---

## 2. GRANULAR PAI PERFORMANCE MATRIX

Detailed record of all 120 presentation attack attempts across capture conditions:

| PAI Species Code | Total Attempts | Accepted (Bypasses) | Rejected | APCER | 95% Clopper-Pearson CI | Primary Lighting Regime | Camera Profile Tested | Test Session ID |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `PRINTED_PHOTO_MATTE` | 15 | 0 | 15 | **0.00%** | `[0.00%, 21.80%]` | `INDOOR_UNIFORM` | `MID_1080P_AUTOFOCUS` | `SESS-PAD-M01` |
| `PRINTED_PHOTO_GLOSSY` | 15 | 0 | 15 | **0.00%** | `[0.00%, 21.80%]` | `OUTDOOR_DIRECT_SUN`| `ENTRY_720P_FIXED` | `SESS-PAD-G01` |
| `SCREEN_REPLAY_SMARTPHONE`| 15 | 0 | 15 | **0.00%** | `[0.00%, 21.80%]` | `LOW_ILLUMINATION_NIGHT`| `FLAGSHIP_4K_SENSOR` | `SESS-PAD-S01` |
| `SCREEN_REPLAY_TABLET` | 15 | 2 | 13 | **13.33%** | `[1.66%, 40.46%]` | `DIFFUSE_FLUORESCENT`| `MID_1080P_AUTOFOCUS` | `SESS-PAD-T01` |
| `SCREEN_REPLAY_4K_MONITOR` | 15 | 0 | 15 | **0.00%** | `[0.00%, 21.80%]` | `INDOOR_UNIFORM` | `ENTRY_720P_FIXED` | `SESS-PAD-D01` |
| `PRE_RECORDED_VIDEO_LOOP` | 15 | 0 | 15 | **0.00%** | `[0.00%, 21.80%]` | `BACKLIT_STRONG_WINDOW`| `MID_1080P_AUTOFOCUS` | `SESS-PAD-L01` |
| `SYNTHETIC_DEEPFAKE_VIDEO`| 15 | 0 | 15 | **0.00%** | `[0.00%, 21.80%]` | `INDOOR_UNIFORM` | `FLAGSHIP_4K_SENSOR` | `SESS-PAD-F01` |
| `PARTIAL_FACIAL_CUTOUT` | 15 | 0 | 15 | **0.00%** | `[0.00%, 21.80%]` | `INDOOR_UNIFORM` | `MID_1080P_AUTOFOCUS` | `SESS-PAD-C01` |
| **TOTAL / OVERALL** | **120** | **2** | **118** | **1.67%** | `[0.20%, 5.89%]` | Diverse Regimes | Mixed Sensors | All Sessions |

---

## 3. ROOT CAUSE ANALYSIS OF THE TWO TABLET BYPASSES

The 2 accepted attack presentations occurred under species `SCREEN_REPLAY_TABLET` in session `SESS-PAD-T01`:

1. **Bypass 1 (`PAI-VID-BYPASS-0`):**
   - *Attack Setup:* An 11-inch Apple iPad Pro with Liquid Retina display set to 100% brightness (600 nits) was held 35 cm from an Android device front camera.
   - *Video Content:* A high-framerate (60 fps) video of the target subject closing their eyes on cue for exactly 180 ms.
   - *Mechanism:* The client-side burst capture recorded Frame 0 (open, $\text{EAR} = 0.32$), Frame 1 (closed, $\text{EAR} = 0.18$), and Frame 2 (open, $\text{EAR} = 0.31$). The ratio $\text{EAR}_1 / \text{EAR}_0 = 0.5625 \le 0.65$, which satisfied the temporal blink compression invariant.
   - *Aperture Failure:* The high pixel density (264 ppi) and anti-aliased video playback fooled the Sobel edge filter, producing an energy score of $0.35$ which passed the relaxed liveness floor.

2. **Bypass 2 (`PAI-VID-BYPASS-1`):**
   - *Attack Setup:* Similar tablet presentation conducted under low ambient lighting.
   - *Mechanism:* The screen emitted sufficient ambient diffuse illumination that the client-side adaptive screen-fill detector did not activate. The temporal frame-to-frame cosine similarity remained high ($0.85 \ge 0.80$), satisfying the burst identity stability check.

---

## 4. REMEDIATION RECOMMENDATION FOR PHASE 20.6.10 PILOT

1. **Active Challenge-Response Nonce Pairing:** Randomize the requested challenge motion (e.g. "Tilt head left", "Smile", "Blink twice") issued cryptographically in `BiometricChallengeTicket` rather than relying exclusively on unprompted blinks.
2. **Specular Reflection Probing:** Briefly pulse a saturated chromatic screen flash (e.g. 50ms cyan or amber fill) and measure the specular reflectance delta on the corneal surface. Genuine ocular globes reflect the pulse with corneal curvature; flat display screens reflect uniform specular wash.
3. **Audit Status:** Marked as **VERIFIED IN LAB HARNESS**; field performance remains unverified pending controlled physical pilot execution.
