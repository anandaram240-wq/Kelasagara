# V19 Camera and Challenge UX Report

## 1. Hardware-First Camera Startup
Previous iterations blocked camera initialization on an HTTP POST request to `/api/biometrics/challenge`. If the device had cellular connectivity issues or could not reach the local development LAN, the camera preview was completely blocked.

### The Fix in V19:
1. `_startCameraHardwarePipeline()` runs immediately upon screen mount.
2. `Permission.camera.request()` is invoked prior to device querying.
3. Front camera preview initializes in under **200 ms** using `ImageFormatGroup.nv21`.
4. `_initializeEndpointAndAcquireChallengeAsync()` executes as an independent background future, updating the challenge ticket once received without interfering with the live video stream.

## 2. Explicit State Machine (21 States)
The UI avoids conflicting boolean flags by maintaining an explicit state enumeration:
- `checkingPermission`, `permissionDenied`, `permissionPermanentlyDenied`
- `cameraInitializing`, `cameraReadyChallengePending`, `cameraReadyChallengeAvailable`
- `searchingForFace`, `alignFaceInOval`, `faceTooFar`, `faceTooClose`, `headTurned`, `headTilted`
- `lightingImbalance`, `readyForBlink`, `blinkDetectedWaitingOpen`, `burstCaptured`
- `submittingPayload`, `verificationSuccess`, `duplicateBlocked`, `networkErrorRetryable`, `sessionExpired`

## 3. Bilingual Indian Worker Guidance (Kannada + English)
- **Aadhaar-Calibrated Oval:** Renders dynamic color and icon state:
  * Red: Searching for face.
  * Amber: Face detected but out of alignment / poor lighting.
  * Green: Bona fide alignment, ready for blink action.
  * Blue: Burst capture underway.
- **Dynamic Lighting Guidance:**
  * Real-time luma analysis checks left vs right facial illumination.
  * Banner text: `⚠️ ಬೆಳಕು ಮುಖದ ಮೇಲೆ ಸಮನಾಗಿರಲಿ / Ensure even lighting across your face`.
- **Actionable Steps:**
  * `ಮುಖವನ್ನು ವೃತ್ತದೊಳಗೆ ಇರಿಸಿ / Place face inside the oval`
  * `ಕಣ್ಣು ಮಿಟುಕಿಸಿ / Blink your eyes`

## 4. Dual-Path Network Resilience
1. **Primary HTTP Path:** Connects to the configured backend URL (with 1-tap switcher presets for LAN, Emulator, Localhost, and HTTPS Cloud).
2. **Callable Fallback Path:** If primary HTTP times out (4 seconds), `BiometricService` transparently routes the request to the `requestBiometricChallenge` v2 Callable Function in `asia-south1`.
3. **No Offline Bogus Challenges:** The client never fabricates a self-signed challenge. If all network paths fail, the camera stays open with a bilingual retry prompt, preserving security invariants.
