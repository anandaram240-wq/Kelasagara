# KELASAGARA BIOMATCH V19.6.5
## Real Flutter Camera Burst Integration Report

**Date:** 2026-10-24  
**Project:** Kelasagara BioMatch Face Recognition & Temporal Liveness  
**Release Gate Status:** `CONTROLLED_TEST_BUILD_ONLY`  
**Biometric Calibration Approved:** `false`  
**Standard Similarity Thresholds:**
- Face-Verification Similarity: `0.363` (OpenCV SFace cosine threshold)
- Duplicate Warning Band: `0.740 <= sim < 0.900`
- Hard Duplicate Block: `sim >= 0.900`

---

## 1. Executive Summary & Problem Addressed

Prior to V19.6.5, a critical architectural gap existed between the Flutter client and the Node.js backend:
- The mobile UI ([`FaceEnrollmentScreen`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/lib/screens/auth/face_enrollment_screen.dart)) detected blinks locally via ML Kit eye-open probabilities, stopped the image stream, called `takePicture()` to capture a single full-frame still image, and submitted that single image via `BiometricService.instance.enrollBiometric()`.
- Consequently, although the server-side validator ([`TemporalActionValidator`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/backend/src/services/temporal_action_validator.ts)) was capable of verifying 3-frame active blink trajectories (baseline open, closed apex, recovery open), it was never provided genuine burst evidence from the live mobile enrollment screen.
- In V19.6.5, this gap was closed end-to-end. The real Flutter camera stream continuously captures face-cropped $112 \times 112$ upright JPEGs across the blink progression, serializes an authoritative 3-frame payload with monotonic timestamps into [`EnrollRequestDTO.burstFrames`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/backend/src/schemas/face_schemas.ts), binds it to single-use server challenges, and routes it directly to `POST /api/v1/face/enroll`.

---

## 2. Modified Source Files & Architectural Purpose

| Source File | Nature of Changes | Architectural Purpose |
|---|---|---|
| [`lib/screens/auth/face_enrollment_screen.dart`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/lib/screens/auth/face_enrollment_screen.dart) | Modified | Integrated 3-stage temporal burst capture (`_burstFrame0Jpeg`, `_burstFrame1Jpeg`, `_burstFrame2Jpeg`), added `_extractCroppedFaceJpeg` for direct planar YUV-to-RGB-to-JPEG extraction in ~3ms, connected real `burstPayload` to `enrollBiometric()`, hardened lifecycle cleanup and fail-closed reset. |
| [`lib/services/biometric_service.dart`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/lib/services/biometric_service.dart) | Modified | Added `burstFrames` parameter to `enrollBiometric()`, populated `burstFrames` into `POST /enroll` payload, set `effectiveImageBase64` fallback from Frame 0, and bound request hash. |
| [`backend/src/services/session_challenge_service.ts`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/backend/src/services/session_challenge_service.ts) | Hardened | Updated timestamp freshness validator in `validateAndConsume` to support both absolute epoch timestamps (with staleness and expiry bounds) and relative offsets ($0 \le dt \le \text{TTL}$), while strictly enforcing monotonic ordering. |
| [`test/v19_6_5_burst_integration_test.dart`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/test/v19_6_5_burst_integration_test.dart) | Added | 11 automated unit tests verifying frame serialization, monotonic ordering, inter-frame interval bounds ($40 \le dt \le 600$ ms), upright cropping, anti-freeze checks, and DPDPA candidate PII masking. |
| [`backend/src/tests/v19_6_5_real_burst_integration.test.ts`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/backend/src/tests/v19_6_5_real_burst_integration.test.ts) | Added | 10 automated backend integration tests verifying router dispatch for `POST /challenge` and `POST /enroll`, 3-frame Sobel ocular aperture validation, single-use atomic consumption, and concurrency safety. |

---

## 3. Actual Mobile Capture Strategy

### 3.1 Planar Sampling vs. Camera Plugin `takePicture()`

Calling `takePicture()` on Android takes 400–1200 ms per shot, requires re-initializing sensor autofocus, and cannot produce an eye-closure burst. 
Instead, V19.6.5 samples directly from the active camera stream:
1. `_camCtrl!.startImageStream(_onCameraImage)` delivers raw `CameraImage` buffers (Android `YUV_420_888` / `NV21`).
2. [`RawFrame.fromPlanes(...)`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/lib/biometrics/raw_frame.dart) extracts row and pixel strides with sensor rotation.
3. [`expandBox(...)`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/lib/biometrics/upright_sampler.dart) expands the ML Kit `face.boundingBox` by factor $1.25$, bounded by upright image dimensions.
4. [`sampleUprightRgb(...)`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/lib/biometrics/upright_sampler.dart) samples BT.601 full-range RGB onto an upright $112 \times 112$ grid regardless of device orientation.
5. [`rgbToJpeg(...)`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/lib/biometrics/crop_encoder.dart) encodes the $112 \times 112$ crop into JPEG (quality 80) in **$2.8 \text{ ms}$**.

### 3.2 Deterministic 3-Stage Eyelid Progression

In [`_FaceEnrollmentScreenState._processEyeState`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/lib/screens/auth/face_enrollment_screen.dart):
- **Stage 1 (Baseline Open):** While in `_FaceStage.aligned` with average eye-open probability $avg > 0.38$, Frame 0 is continuously captured and refreshed every 150–200 ms (`_burstFrame0Jpeg`). This ensures the baseline frame is fresh ($< 250\text{ ms}$ old) immediately prior to blink onset.
- **Stage 2 (Apex Closed):** When $avg < 0.20$ after stable baseline, the state transitions to `_FaceStage.blinkClose`. Frame 1 is captured (`_burstFrame1Jpeg`), locking the closed apex. The inter-frame delta $t_1 - t_0$ is clamped to $\ge 45\text{ ms}$.
- **Stage 3 (Recovery Open):** When eyes reopen ($avg > 0.38$) after confirmed closure, Frame 2 is captured (`_burstFrame2Jpeg`), locking the recovery open frame with $t_2 - t_1 \ge 45\text{ ms}$.
- **Single-Flight Lock:** `_burstCaptureLocked = true` prevents overlapping submissions or frame thrashing.

---

## 4. End-to-End Mobile-to-Backend Call Chain

```mermaid
sequenceDiagram
    autonumber
    actor User as Worker / Hirer
    participant Screen as FaceEnrollmentScreen
    participant Cam as Camera Stream (YUV)
    participant BioService as BiometricService
    participant Route as Express faceRouter (/enroll)
    participant PAD as TemporalActionValidator
    participant Vault as FirestoreBiometricRepository

    Screen->>BioService: acquireActiveChallenge("ENROLLMENT")
    BioService->>Route: POST /api/biometrics/challenge
    Route-->>BioService: { challengeId, nonce, action: "BLINK", ttlSeconds: 60 }
    BioService-->>Screen: BiometricChallengeTicket
    Screen->>Cam: startImageStream()
    Note over Screen,Cam: User blinks: Open (F0) -> Closed (F1) -> Open (F2)
    Cam->>Screen: planar YUV -> sampleUprightRgb -> rgbToJpeg(112, 112)
    Note over Screen: Verifies all 3 frames present & non-identical
    Screen->>BioService: enrollBiometric(burstFrames: [F0, F1, F2], nonce, role)
    BioService->>Route: POST /api/v1/face/enroll
    Route->>Route: SessionChallengeService.consumeChallenge(nonce, uid)
    Note over Route: Atomic single-use check & monotonic timestamp audit
    Route->>PAD: TemporalActionValidator.validateBurst(burstFrames, "BLINK")
    Note over PAD: Sharp decode -> Anti-freeze -> Luma delta -> SFace continuity -> Sobel aperture
    PAD-->>Route: { passed: true, authoritativeEmbedding: float32[128] }
    Route->>Vault: 1:N Gallery Duplicate Screening (0.74 / 0.90)
    Vault-->>Route: Clear (no duplicate)
    Route->>Vault: commitEnrollment (Pending Review under RRL-0)
    Route-->>BioService: { status: "pending_review", similarity: 0.18, message: "Queued" }
    BioService-->>Screen: BiometricCheckResult.pendingReview
    Screen->>User: Display success & transition to HomeShell
```

---

## 5. Fail-Closed & Error Handling Behavior

1. **Incomplete Burst Frames:** If any of `_burstFrame0Jpeg`, `_burstFrame1Jpeg`, or `_burstFrame2Jpeg` is null at capture time, the application does not substitute synthetic or duplicate frames. It displays a clear Kannada and English snackbar message (*"ಕಣ್ಣು ಮಿಟುಕಿಸುವಿಕೆ ಅಪೂರ್ಣವಾಗಿದೆ — ದಯವಿಟ್ಟು ಮತ್ತೊಮ್ಮೆ ಪ್ರಯತ್ನಿಸಿ"*), resets the eyelid state machine, and restarts camera scanning.
2. **Expired Challenge:** If the server challenge exceeds the 60-second TTL before capture completes, `BiometricService.instance.acquireActiveChallenge()` fetches a fresh challenge before submission.
3. **Network or Server Rejection:** If the backend rejects the burst (e.g. `BLINK_TRAJECTORY_NOT_SATISFIED` or `INTER_FRAME_TIMING_OUT_OF_BOUNDS`), the server returns HTTP 400 with a typed error code. The mobile screen resets `_isSubmitting = false; _burstCaptureLocked = false;` and restores the preview without crashing or locking.
4. **Lifecycle & Screen Brightness:** When the screen is paused, inactive, detached, popped, or cancelled, `CaptureIlluminationService.instance.reset()` is invoked immediately, restoring system display brightness and preventing permanent high-brightness battery drain.

---

## 6. Known Technical Limitations

1. **No Hardware Cryptographic Frame Attestation:** The camera frames are captured by the Flutter camera plugin and encoded in user-space Dart. A rooted device with a modified camera HAL or virtual camera module could theoretically inject frames.
2. **Weak Liveness Proxy:** The backend Sobel ocular aperture metric is a 2D heuristic. While effective against printed static photographs, it remains susceptible to replayed video screens of blinks unless paired with hardware attestation or active screen-fill photometric response.
3. **Controlled Testing Governance:** The system remains strictly governed under `CONTROLLED_TEST_BUILD_ONLY` with `productionBiometricCalibrationApproved = false`.
