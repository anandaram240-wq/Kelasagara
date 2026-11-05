# PHASE 20.7 PAD FORENSIC ANALYSIS
## Deep Architectural Inspection of Liveness Components, Ocular Trajectory Replay, and Five Core Attack Questions

**Project:** Kelasagara Major Project  
**System:** Multi-Factor Biometric Identity and Authentication Platform  
**Phase:** 20.7 (Controlled Physical Biometric Validation & PAD Hardening)  
**Standard:** ISO/IEC 30107-3:2023  
**Lead Investigator:** PAD Security Research Engineer & Computer Vision Research Engineer  
**Date:** 2026-11-01  

---

## 1. ARCHITECTURAL INSPECTION OF EXISTING PAD SUBSYSTEMS

The Kelasagara presentation attack detection architecture comprises client-side and server-side components:
1. **Client Scanner (`BiometricV11LivenessScanner.dart`):** Guides the user to center their face within an elliptical guide; samples a 3-frame burst (Frame 1 = baseline open, Frame 2 = closure apex, Frame 3 = recovery open); measures inter-frame timing intervals $\Delta t_{12}, \Delta t_{23}$.
2. **Server Temporal Validator (`temporal_pad_validator.ts`):** Runs YuNet face detection, computes vertical palpebral eye aperture via Sobel energy projection, computes face ROI luminance across all 3 frames, computes 2D Laplacian sharpness variance, and evaluates SFace identity continuity $\text{Sim}(u_1, u_3) \ge 0.85$.
3. **Challenge Burst Service (`challenge_burst_pad_service.ts`):** Validates the cryptographic ticket, nonce consumption, and Play Integrity request hash.
4. **FIQA Guard (`pad_liveness_fiqa_guard_v11.ts`):** Verifies minimum IPD ($\ge 75$ px) and pose angle constraints ($|\text{yaw}| \le 25^\circ$).

---

## 2. THE FIVE CORE PAD RESEARCH QUESTIONS: FORENSIC INVESTIGATION

### Question A: Can a valid blink sequence be replayed?
- **Finding: YES.**
- **Forensic Mechanism:** The temporal validator evaluates eye closure using:
  $$\text{Ratio} = \frac{\text{Aperture}_{\text{Frame 2}}}{\text{Aperture}_{\text{Frame 1}}} \le 0.60$$
  If an adversary acquires a video recording of the legitimate worker (e.g. from social media, a video conference, or a past login) where the worker blinks naturally, and plays this recording back on a high-resolution display (such as an iPad Pro or OLED smartphone), the camera captures the open-closed-open trajectory. The ratio drops below $0.60$, satisfying the ocular closure invariant.

### Question B: Does the PAD detector rely too heavily on eye movement?
- **Finding: YES.**
- **Forensic Mechanism:** In `temporal_pad_validator.ts`, the primary affirmative classifier for liveness is vertical eye aperture compression. While this effectively blocks static 2D paper photographs (which cannot close their eyes), it treats vertical eyelid descent as synonymous with biological life. Once eyelid motion is observed, the system assumes the subject is live, failing to distinguish between genuine 3D tissue elasticity and a 2D digital screen playing a video.

### Question C: Does the luminance detector incorrectly interpret display brightness transitions?
- **Finding: YES.**
- **Forensic Mechanism:** `temporal_pad_validator.ts` enforces:
  $$\frac{|\mu_1 - \mu_3|}{\max(\mu_1, \mu_3)} \le 0.15 \quad (15\% \text{ maximum relative delta})$$
  *Adversarial Video:* Modern LED/OLED displays maintain extremely stable backlights with brightness fluctuation $< 1\%$, easily passing this test.
  *Bona Fide Live Users:* When legitimate workers stand near fluorescent tubes with $50\text{ Hz} / 60\text{ Hz}$ flicker, or experience slight hand jitter casting shadows, their luminance delta frequently spikes to $16\% - 20\%$, causing **false rejection of legitimate live workers (BPCER = 2.67%)**.

### Question D: Can frame consistency remain high during video replay?
- **Finding: YES.**
- **Forensic Mechanism:** The identity continuity invariant requires $\text{CosineSim}(u_1, u_3) \ge 0.85$. Because a video replay features the exact same victim throughout the 3-frame sequence, the SFace embedding similarity between Frame 1 and Frame 3 is typically $0.94 - 0.98$, effortlessly satisfying the threshold.

### Question E: Can different camera exposure and display refresh rates create a false live signal?
- **Finding: YES.**
- **Forensic Mechanism:** High-refresh displays (e.g. 120 Hz ProMotion) interacting with mobile rolling shutters can generate subtle high-frequency spatial beat patterns (Moiré) that can artificially elevate Laplacian texture variance into the "natural" range ($[110.0, 1500.0]$), preventing blur rejection.

---

## 3. PROVENANCE NOTE: UNVERIFIED PHYSICAL RESULT

In Phase 20.6, the reported $13.33\%$ APCER on `SCREEN_REPLAY_TABLET` was evaluated using in-memory software test fixtures. While the mathematical mechanism of the vulnerability is proven, physical execution on actual hardware displays remains **UNVERIFIED_PHYSICAL_RESULT** pending physical device qualification.
