# KELASAGARA BIOMATCH V19.6.3: ACTION-BOUND LIVENESS VALIDATION MATRIX
**Document ID:** `KB-V19-6-3-REP-01`  
**Classification:** Authoritative Challenge Routing & Action-Specific Kinematic Validation Audit  
**Release Gate Status:** `CONTROLLED_TEST_BUILD_ONLY`  
**Production Biometric Calibration Approved:** `false`  
**Target Environment:** Node.js/TypeScript Backend + Flutter Mobile Client  
**Evaluation Date:** October 24, 2026

---

## 1. ARCHITECTURAL AUDIT & FINDINGS: CHALLENGE ROUTING

In KELASAGARA BIOMATCH V19.6.2, the system introduced server-issued active challenges (`BLINK`, `TURN_HEAD_LEFT`, `TURN_HEAD_RIGHT`, `NOD_HEAD`). However, a thorough architectural audit across both client (`face_enrollment_screen.dart`) and server (`temporal_action_validator.ts`) revealed two critical limitations:

1. **Client Capture Loop Hardcoding:**
   - In `lib/screens/auth/face_enrollment_screen.dart`, while localized action prompts were displayed in the UI, the underlying camera processing pipeline (`_padKinematics.processFrame`) and state machine (`_processEyeState`) **only observed and reacted to eye blinks** (`avg < _eyeClosed`).
   - If the server issued `TURN_HEAD_LEFT`, a mobile user turning their head would experience a client soft-lock because `_captureAndSave()` was never triggered without a subsequent blink.
2. **Server-Side Validation Generalization:**
   - On the backend, `TemporalActionValidator` specifically validated ocular aperture compression for `BLINK`, but for all other actions (`TURN_HEAD_LEFT`, `TURN_HEAD_RIGHT`, `NOD_HEAD`), it merely evaluated `cosineSimilarity(emb0, emb1) < 0.985` (gross movement). It did **not** verify the direction of the turn (left vs right), pitch angle, or trajectory compliance.

### The V19.6.3 Solution
- **Action-Specific Directional Kinematic Validators:** Implemented in [`backend/src/services/temporal_action_validator.ts`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/backend/src/services/temporal_action_validator.ts). Each candidate action now has an authoritative server-side mathematical validator:
  - `BLINK`: Vertical ocular aperture compression ratio ($\le 0.65$).
  - `TURN_HEAD_LEFT`: Horizontal center-of-mass gradient displacement ($\Delta x \le -0.035$) returning to center ($|\Delta x_2| \le 0.030$).
  - `TURN_HEAD_RIGHT`: Horizontal center-of-mass gradient displacement ($\Delta x \ge +0.035$) returning to center.
  - `NOD_HEAD`: Vertical center-of-mass pitch displacement ($\Delta y \ge +0.035$) returning to center.
- **Controlled Issuance Governance Policy:** In [`backend/src/services/session_challenge_service.ts`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/backend/src/services/session_challenge_service.ts), default issuance is strictly restricted to `VERIFIED_CHALLENGE_ACTIONS = ["BLINK"]`. Experimental head-turn and nod actions can only be issued when explicitly forced in controlled test builds, guaranteeing that live users are never soft-locked by uncalibrated sensors.

---

## 2. MASTER ACTION-BOUND VALIDATION MATRIX

| Challenge ID | Server Selection Policy | Client Prompt (EN / KN) | Submitted Data Payload | Server-Side Measurement Method | Acceptance & Rejection Conditions | Retry & Expiry Invariants | Genuinely Validated vs Client Declared | Test Suite Reference |
|:---|:---|:---|:---|:---|:---|:---|:---:|:---|
| **`BLINK`** | **Default Active (Verified)**: Randomly issued in production & staging. | `"Please blink your eyes naturally"`<br>`"ದಯವಿಟ್ಟು ನಿಮ್ಮ ಕಣ್ಣುಗಳನ್ನು ನೈಸರ್ಗಿಕವಾಗಿ ಮಿಟುಕಿಸಿ"` | 3-frame burst `[f0, f1, f2]` with monotonic timestamps ($40 \le \Delta t \le 600\text{ms}$). | `measureEyeAperture`: Central palpebral fissure vertical Sobel gradient energy $E(f)$ across $y \in [35, 65]$. | **Accept:** $\text{ApexRatio} = \frac{E(f_1)}{\max(E(f_0), E(f_2))} \le 0.65$.<br>**Reject:** $\text{ApexRatio} > 0.65$ (`BLINK_TRAJECTORY_NOT_SATISFIED`). | 60s TTL; single-use atomic consumption; failed capture leaves state `PENDING_FACE`. | **GENUINELY VALIDATED** (Server-Side) | `v19_6_3_adversarial_protocol.test.ts` (Scenarios 1, 2, 15) |
| **`TURN_HEAD_LEFT`** | **Controlled / Experimental**: Issued only when `forcedAction` or experimental flag is set. | `"Slowly turn your head slightly to the left"`<br>`"ನಿಮ್ಮ ತಲೆಯನ್ನು ನಿಧಾನವಾಗಿ ಎಡಕ್ಕೆ ತಿರುಗಿಸಿ"` | 3-frame burst `[f0, f1, f2]` with monotonic timestamps. | `computeKinematicCenterOfMass`: Normalized horizontal gradient COM $\bar{x} = \frac{\sum x \cdot G}{\sum G}$. | **Accept:** $\Delta x_{01} \le -0.035$ (left shift) and $|\Delta x_{02}| < |\Delta x_{01}|$.<br>**Reject:** $\Delta x_{01} > -0.035$ (turned right, stayed frontal, or blink) (`HEAD_TURN_LEFT_TRAJECTORY_NOT_SATISFIED`). | 60s TTL; single-use token; failure allows retry from `PENDING_FACE`. | **GENUINELY VALIDATED** (Server-Side) | `v19_6_3_adversarial_protocol.test.ts` (Scenario 3) |
| **`TURN_HEAD_RIGHT`** | **Controlled / Experimental**: Issued only when `forcedAction` or experimental flag is set. | `"Slowly turn your head slightly to the right"`<br>`"ನಿಮ್ಮ ತಲೆಯನ್ನು ನಿಧಾನವಾಗಿ ಬಲಕ್ಕೆ ತಿರುಗಿಸಿ"` | 3-frame burst `[f0, f1, f2]` with monotonic timestamps. | `computeKinematicCenterOfMass`: Normalized horizontal gradient COM $\bar{x} = \frac{\sum x \cdot G}{\sum G}$. | **Accept:** $\Delta x_{01} \ge +0.035$ (right shift) and $|\Delta x_{02}| < |\Delta x_{01}|$.<br>**Reject:** $\Delta x_{01} < +0.035$ (turned left, stayed frontal, or blink) (`HEAD_TURN_RIGHT_TRAJECTORY_NOT_SATISFIED`). | 60s TTL; single-use token; failure allows retry from `PENDING_FACE`. | **GENUINELY VALIDATED** (Server-Side) | `v19_6_3_adversarial_protocol.test.ts` (Scenario 4) |
| **`NOD_HEAD`** | **Controlled / Experimental**: Issued only when `forcedAction` or experimental flag is set. | `"Slowly nod your head down and up"`<br>`"ನಿಮ್ಮ ತಲೆಯನ್ನು ನಿಧಾನವಾಗಿ ಮೇಲಕ್ಕೆ ಮತ್ತು ಕೆಳಕ್ಕೆ ಅಲ್ಲಾಡಿಸಿ"` | 3-frame burst `[f0, f1, f2]` with monotonic timestamps. | `computeKinematicCenterOfMass`: Normalized vertical gradient COM $\bar{y} = \frac{\sum y \cdot G}{\sum G}$. | **Accept:** $\Delta y_{01} \ge +0.035$ (downward pitch shift) and $|\Delta y_{02}| < |\Delta y_{01}|$.<br>**Reject:** $\Delta y_{01} < +0.035$ (flat trajectory, stayed frontal, or blink) (`NOD_HEAD_TRAJECTORY_NOT_SATISFIED`). | 60s TTL; single-use token; failure allows retry from `PENDING_FACE`. | **GENUINELY VALIDATED** (Server-Side) | `v19_6_3_adversarial_protocol.test.ts` (Scenario 5) |

---

## 3. AUDIT OF CLIENT DECLARATION VS SERVER VALIDATION

| Security Property | Client Behavior | Server Enforcement | Security Verdict |
|:---|:---|:---|:---:|
| `blinkVerified: true` flag | Client ML Kit detector emits boolean | **Ignored**. Backend recomputes aperture compression on raw frames. | `VERIFIED` (Zero-Trust) |
| `challengePassed: true` flag | Client may assert challenge passed | **Ignored**. Backend enforces single-use nonce & trajectory. | `VERIFIED` (Zero-Trust) |
| Action Type Matching | Client submits `observedAction` | **Strict Match**: Throws `Liveness action mismatch` if different from challenge. | `VERIFIED` |
| Monotonic Timestamps | Client sends `capturedOffsetMs` | **Strict Order**: Throws `Out of order frame sequence` if $t_i \le t_{i-1}$. | `VERIFIED` |
| Monotonic Indices | Client sends `sequenceIndex` | **Strict Indexing**: Must be strictly $[0, 1, 2]$. | `VERIFIED` |
| Anti-Freeze Detection | Client transmits 3 JPEG frames | **Buffer Equals**: Checks byte equality; rejects identical frames. | `VERIFIED` |
| Identity Continuity | Client transmits 3 JPEG frames | **SFace Cosine**: Extracts embeddings on $f_0, f_2$; requires $\text{sim} \ge 0.80$. | `VERIFIED` |
| Photometric Stability | Ambient scene lighting | **Luma Delta**: Rejects sudden relative jumps $> 18\%$. | `VERIFIED` |

---

## 4. GOVERNANCE DECISION & PRODUCTION STATUS

In accordance with Phase 2 instructions:
> *"If a reliable validator cannot be supported by the available data or model, disable that challenge and use only a verified action. Do not issue actions whose results are not validated."*

**Authoritative Governance Rule:**
1. In production, `SessionChallengeService` is configured to issue **only `BLINK`** (`VERIFIED_CHALLENGE_ACTIONS`).
2. `TURN_HEAD_LEFT`, `TURN_HEAD_RIGHT`, and `NOD_HEAD` are classified as `EXPERIMENTAL_CHALLENGE_ACTIONS`. They are supported by server-side kinematic COM validators in `TemporalActionValidator`, but disabled from default randomized issuance until client-side active tracking in `FaceEnrollmentScreen` is calibrated across multi-ethnic Indian field datasets.
3. Neither `releaseGateStatus` nor biometric thresholds are altered:
   - `releaseGateStatus = CONTROLLED_TEST_BUILD_ONLY`
   - `productionBiometricCalibrationApproved = false`
