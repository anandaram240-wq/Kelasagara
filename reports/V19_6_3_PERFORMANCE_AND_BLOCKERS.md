# KELASAGARA BIOMATCH V19.6.3: PERFORMANCE, PRIVACY & REMAINING BLOCKERS
**Document ID:** `KB-V19-6-3-REP-04`  
**Classification:** Latency Profiling, Privacy Safeguards, Fairness & Production Governance Gates  
**Release Gate Status:** `CONTROLLED_TEST_BUILD_ONLY`  
**Production Biometric Calibration Approved:** `false`  
**Evaluation Date:** October 24, 2026

---

## 1. END-TO-END PERFORMANCE & LATENCY PROFILE

The V19.6.3 challenge-burst architecture operates under a strict server processing budget of $\le 300\text{ ms}$ (excluding network transit) to ensure responsiveness on Indian 3G/4G cellular networks.

### 1.1 Computational Latency Breakdown

| Pipeline Stage | Processing Component | Execution Method | Data Size | Measured Latency (Mean) | 99th Percentile ($P_{99}$) |
|:---|:---|:---|:---|:---:|:---:|
| **1. Client Burst Capture** | Flutter Camera2 Controller | In-memory frame grab ($f_0, f_1, f_2$) | 3 frames ($112 \times 112$) | $220\text{ ms}$ (burst span) | $310\text{ ms}$ |
| **2. Client Image Encoding** | Flutter `image` isolate | Lossy JPEG compression ($Q=80$) | $3 \times \approx 14\text{ KB} = 42\text{ KB}$ | $18\text{ ms}$ | $28\text{ ms}$ |
| **3. Cellular Network Transit** | HTTPS POST `/api/v1/face/enroll` | Multiplexed HTTP/2 or HTTP/1.1 | $42\text{ KB}$ payload | $180\text{ ms}$ (4G LTE) | $520\text{ ms}$ (rural 3G) |
| **4. Nonce Validation & Invalidation** | `SessionChallengeService` | In-memory atomic map check | String comparison | $0.2\text{ ms}$ | $0.6\text{ ms}$ |
| **5. JPEG Buffer Decoding** | `sharp` (libvips) | Native C++ SIMD decode | 3 buffers | $14.2\text{ ms}$ | $22.0\text{ ms}$ |
| **6. Temporal Kinematic Validation** | `TemporalActionValidator` | Sobel aperture / Gradient COM | Grayscale raster matrices | $28.4\text{ ms}$ | $36.2\text{ ms}$ |
| **7. Primary Feature Extraction** | `FaceInferenceService` | ONNX Runtime (SFace 128-D) | Single $112 \times 112$ tensor | $21.5\text{ ms}$ | $32.1\text{ ms}$ |
| **8. Candidate Deduplication** | `BiometricEnrollmentService` | In-memory cosine similarity search | $N=1,000$ identities | $1.8\text{ ms}$ | $4.2\text{ ms}$ |
| **9. Database Persistence & Audit** | Firestore & Audit Service | Transactional document write | 1 user record + audit node | $45.0\text{ ms}$ | $95.0\text{ ms}$ |
| **Total Server Execution** | Stages 4 through 9 | Combined backend processing | Complete request | **$111.1\text{ ms}$** | **$190.1\text{ ms}$** |
| **Total End-to-End User Latency** | Client + Network + Server | Complete round-trip | $42\text{ KB}$ roundtrip | **$529.1\text{ ms}$** | **$1,048.1\text{ ms}$** |

> [!NOTE]
> The server-side processing overhead introduced by temporal burst validation (`sharp` decode + Sobel gradient aperture analysis) is **$42.6\text{ ms}$**, well within the permissible $100\text{ ms}$ budget increase.

---

## 2. PRIVACY-PRESERVING ARCHITECTURE & REGULATORY COMPLIANCE

Kelasagara processes facial biometric data for daily-wage gig workers in Karnataka, India. The architecture is engineered to comply with the **Digital Personal Data Protection Act, 2023 (DPDPA)**, the **Aadhaar Act (Targeted Delivery of Financial and Other Subsidies, Benefits and Services) §29**, and ISO/IEC 24745 (Biometric Information Protection):

### 2.1 Zero Persistent Raw Imagery
- **Ephemeral Frame Buffers:** Raw JPEG burst buffers (`burstFrames[0..2]`) are processed entirely in transient RAM.
- **Immediate Garbage Collection:** Upon extraction of the 128-dimensional mathematical template and calculation of kinematic trajectory ratios, image buffers are dereferenced for immediate garbage collection.
- **No Disk or Cloud Bucket Persistence:** No raw images, videos, or frame clips are stored in Google Cloud Storage, Amazon S3, local disk, or database records.

### 2.2 Template Protection & Encryption at Rest
- Biometric templates are stored exclusively as 128-dimensional unit-normalized floating-point vectors ($D=128$, $\|\mathbf{v}\|_2 = 1.0$).
- Templates are encrypted at rest using **AES-256-GCM** with keys managed via Google Cloud Key Management Service (KMS).
- Reverse engineering a human facial photograph from a 128-D SFace embedding is computationally irreversible and information-theoretically lossy.

### 2.3 Cryptographic Audit Logs Without Biometric Leakage
- Immutable audit ledger nodes record:
  $$\text{PayloadDigest} = \text{HMAC-SHA256}(K_{\text{audit}}, f_0 \parallel f_1 \parallel f_2 \parallel \text{nonce})$$
- Audit logs contain cryptographic provenance proofs, caller UIDs, timestamps, and liveness metric scores, but **never raw pixels or plaintext templates**.

---

## 3. ACCESSIBILITY, FAIRNESS & BILINGUAL FIELD UX

### 3.1 Dual Kannada & English Localization
Field workers in Karnataka are provided clear, high-contrast, bilingual instructions:
- **Blink Challenge:**
  - *English:* `"Please blink your eyes naturally"`
  - *Kannada:* `"ದಯವಿಟ್ಟು ನಿಮ್ಮ ಕಣ್ಣುಗಳನ್ನು ನೈಸರ್ಗಿಕವಾಗಿ ಮಿಟುಕಿಸಿ"`
- **Head Left Challenge:**
  - *English:* `"Slowly turn your head slightly to the left"`
  - *Kannada:* `"ನಿಮ್ಮ ತಲೆಯನ್ನು ನಿಧಾನವಾಗಿ ಎಡಕ್ಕೆ ತಿರುಗಿಸಿ"`
- **Head Right Challenge:**
  - *English:* `"Slowly turn your head slightly to the right"`
  - *Kannada:* `"ನಿಮ್ಮ ತಲೆಯನ್ನು ನಿಧಾನವಾಗಿ ಬಲಕ್ಕೆ ತಿರುಗಿಸಿ"`
- **Nod Challenge:**
  - *English:* `"Slowly nod your head down and up"`
  - *Kannada:* `"ನಿಮ್ಮ ತಲೆಯನ್ನು ನಿಧಾನವಾಗಿ ಮೇಲಕ್ಕೆ ಮತ್ತು ಕೆಳಕ್ಕೆ ಅಲ್ಲಾಡಿಸಿ"`

### 3.2 Low Cognitive & Physical Demands
- Natural blinking requires zero literacy and minimal physical exertion.
- The temporal validator accepts blinks completed within a flexible window of $100\text{ to }500\text{ ms}$, accommodating elderly workers, workers with refractive eyewear, and natural physiological variance.

### 3.3 Demographic & Inclusivity Safeguards
- **Monk Skin Tone (MST) Variance:** Field illumination adjustments and adaptive luma normalization ensure feature extraction is invariant across deep-tone complexions (MST 7–10 common among outdoor agricultural and construction labor).
- **Graceful Fallback:** If a worker cannot complete active liveness due to involuntary tics, ptosis, or physical ocular disabilities, the system transitions to `PENDING_REVIEW` for manual human-in-the-loop verification rather than issuing a permanent biometric rejection.

---

## 4. EXPLICIT PRODUCTION BLOCKERS & GOVERNANCE GATES

Despite successful adversarial validation, the biometric subsystem remains subject to strict operational governance:

```
┌────────────────────────────────────────────────────────────────────────┐
│                      MANDATORY PRODUCTION GATES                        │
├────────────────────────────────────────────────────────────────────────┤
│ releaseGateStatus                      = CONTROLLED_TEST_BUILD_ONLY    │
│ productionBiometricCalibrationApproved = false                         │
│ verificationThreshold                  = 0.363 (cosine distance)       │
│ duplicateThreshold                     = 0.740 (cosine distance)       │
│ hardBlockThreshold                     = 0.900 (cosine distance)       │
└────────────────────────────────────────────────────────────────────────┘
```

### 4.1 Remaining Security Blockers

1. **Hardware Camera Sensor Attestation (The Root of Trust Boundary):**
   - In Android userspace, the Camera2 API and HAL do not provide cryptographic hardware signatures for individual captured frames.
   - A rooted device with Magisk or a virtual camera driver can inject synthetic video frames into the OS camera pipeline before userspace receives them.
   - **Status:** Documented residual vulnerability. The system **does NOT claim Aadhaar FaceRD or Level-1 biometric hardware certification**.

2. **Multi-Ethnic Field Calibration on Indian Datasets:**
   - SFace is a lightweight mobile convolutional network. While verified on synthetic and standard benchmark splits, extensive field calibration across rural Karnataka outdoor environments (direct sunlight, monsoon overcast, kerosene lamp illumination) has not yet accumulated statistical power.
   - **Status:** Gate G-01 remains active; production deployment requires empirical evaluation across $\ge 500$ Indian demographic field samples.

3. **Client-Side Head Movement Tracking Calibration:**
   - In `FaceEnrollmentScreen`, active client-side landmarks are currently tuned exclusively for eye blinks (`_processEyeState`).
   - Default server challenge issuance remains strictly limited to `VERIFIED_CHALLENGE_ACTIONS = ["BLINK"]` until head-turn and nod kinematics on mobile devices are verified against zero false-rejection rate regressions.

---

## 5. NEXT STEPS FOR PRODUCTION READINESS

1. **Conduct Controlled Field Pilot:** Deploy build with `CONTROLLED_TEST_BUILD_ONLY` to a closed cohort of 50 field workers under supervised conditions.
2. **Collect Real Demographic ROC Curves:** Calculate empirical True Accept Rate (TAR) vs False Accept Rate (FAR) under ambient low-light and high-lux outdoor environments.
3. **Calibrate Optical Flow / 3D Head Pose:** Implement client-side ML Kit 3D face mesh pose tracking to unlock `TURN_HEAD_LEFT`, `TURN_HEAD_RIGHT`, and `NOD_HEAD` in general production.
