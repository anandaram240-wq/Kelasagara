# KELASAGARA BIOMATCH V19.6: ADAPTIVE CAPTURE ILLUMINATION & BRIGHTNESS LIFECYCLE

**Version:** 19.6.0-advanced  
**Status:** IMPLEMENTED & VERIFIED (UI & Lifecycle) | NOT VERIFIED (Physical Device Photometry)  
**Date:** October 24, 2026  
**Module:** `lib/services/capture_illumination_service.dart`, `lib/screens/auth/face_enrollment_screen.dart`  
**Package:** `screen_brightness: ^2.1.11`  

---

## 1. Architectural Overview

Low-light facial capture on budget Android front cameras presents significant biometric failure modes: elevated sensor noise, motion blur from extended exposure times, landmark loss, and underexposed facial regions.

BioMatch V19.6 replaces static dark capture with **Adaptive Screen-Fill Illumination** (Softbox Mode). The system leverages the smartphone's display as an active forward-facing diffuse photon reflector without requiring hardware flash.

### Key Architectural Invariants:
1. **Application-Scoped Window Control:** Uses `ScreenBrightness.instance.setApplicationScreenBrightness(1.0)`. It affects only the foreground application window and does not alter the user's persistent system display settings or require `android.permission.WRITE_SETTINGS`.
2. **Transparent Face Optical Path:** The white reflective canvas surrounds the circular face alignment guide using an even-odd clipping path (`PathFillType.evenOdd`). It **never** renders an opaque white overlay over the camera preview or landmark alignment ticks.
3. **Mandatory Lifecycle Restoration:** Pre-existing application brightness is cached prior to elevation. The system guarantees restoration on normal exit, back navigation, cancellation, error, widget disposal, and OS-level lifecycle suspension (`paused`, `inactive`, `detached`).

---

## 2. Component Design & Implementation

### A. `CaptureIlluminationService` (`lib/services/capture_illumination_service.dart`)
- **Singleton Pattern:** Prevents competing sessions or concurrent widgets from corrupting brightness state.
- **`enableScreenFill()`:**
  - Queries `ScreenBrightness.instance.application` to store pre-existing level.
  - Sets application window brightness to `1.0`.
  - Catches `PlatformException` and `MissingPluginException` gracefully, failing soft without blocking enrollment.
- **`disableScreenFill()` & `reset()`:**
  - Restores cached brightness or calls `resetApplicationScreenBrightness()`.
  - Clears state flags idempotently.

### B. Softbox UI Layout (`lib/screens/auth/face_enrollment_screen.dart`)
- **Header Toggle:** User-controlled toggle button in header (`Icons.light_mode_outlined` $\leftrightarrow$ `Icons.light_mode`) with Kannada and English tooltip.
- **Canvas Reflector (`_OvalOverlayPainter`):**
  - **Normal Mode:** Paints subtle dark vignette (`Colors.black` at 65% opacity) outside the oval.
  - **Illumination Mode:** Paints high-diffuse neutral soft-white (`const Color(0xFFFAFAFA)`) outside the oval.
  - **Guide Contrast:** Inner oval guide ring dynamically transitions to sky blue (`#0284C7`) when illumination mode is active to ensure crisp visual contrast against the white softbox.
- **Status Indicator:** Displays active badge:  
  *ಸಾಫ್ಟ್‌ಬಾಕ್ಸ್ ಸಕ್ರಿಯವಾಗಿದೆ / Screen-Fill Illumination Active*.

---

## 3. Brightness Lifecycle Restoration Matrix

| Exit Path | Trigger Event | Restoration Mechanism | Verified Status |
| :--- | :--- | :--- | :--- |
| **Normal Completion** | Successful enrollment or submission | `CaptureIlluminationService.instance.disableScreenFill()` | **VERIFIED** |
| **User Cancellation** | Back button / Cancel tap | Back button handler calls `.reset()` before popping | **VERIFIED** |
| **Widget Disposal** | `FaceEnrollmentScreen.dispose()` | `dispose()` explicitly calls `.reset()` | **VERIFIED** |
| **App Backgrounding** | OS Home button / App switcher (`paused`) | `didChangeAppLifecycleState` detects pause and resets | **VERIFIED** |
| **App Inactive / Split** | Incoming call / Notification shade (`inactive`) | `didChangeAppLifecycleState` resets | **VERIFIED** |
| **App Termination** | OS process detach (`detached`) | `didChangeAppLifecycleState` resets | **VERIFIED** |
| **Plugin Channel Error** | Unsupported device / Platform exception | Fails soft, logs warning, allows capture to continue | **VERIFIED** |

---

## 4. Capture Quality Feedback & Lighting Boundaries

Quality metrics are strictly separated from recognition and liveness decisions:
- **Sharpness Bounds:** Laplacian variance $\sigma^2_L$ evaluated continuously. If $\sigma^2_L < 110.0$, the UI prompts for steadiness or illumination rather than lowering recognition thresholds.
- **Inter-Pupillary Distance (IPD):** Minimum IPD of 75 pixels enforced.
- **Exposure Stability:** Camera preview given warm-up frames to allow Automatic Exposure (AE) to stabilize before triggering burst capture.
- **Sensor Limit Disclaimer:** Screen-fill illumination cannot compensate for pitch-black environments ($\le 0.5$ lux) where CMOS front sensors exhibit extreme thermal noise. Users are directed to alternative Document KYC if lighting remains inadequate.

---

## 5. Physical Testing Protocol & Matrix

> [!IMPORTANT]
> Physical photometric performance is designated **NOT VERIFIED** until measured on physical hardware with calibrated lux meters across demographic cohorts. Unit, widget, and lifecycle tests are verified below.

### Planned Field Test Protocol:

```
[Target Environment Matrix]
1. Normal Indoor Office: 300 - 500 lux
2. Dim Domestic Evening: 15 - 50 lux
3. Difficult Low-Light: 2 - 10 lux (Target for Softbox Mode)
4. Extreme Darkness: < 1 lux (Expected Failure / KYC Alternative)
5. Backlit Window: 1000+ lux background, < 50 lux face
```

### Metrics to be Recorded on Android Test Fleet:
- Device Model & Camera Sensor (e.g. Samsung Galaxy M14, Redmi 12C).
- Measured ambient illuminance (lux) via calibrated meter.
- Face detection rate (% frames with 468 landmarks detected).
- Laplacian variance improvement with softbox ON vs OFF.
- SFace embedding cosine similarity stability across lighting shifts.
- Decision latency (ms) and battery temperature delta ($^\circ\text{C}$).

---

## 6. Verification Status

| Component | Test File | Result | Status |
| :--- | :--- | :--- | :--- |
| Lifecycle Initialization | `test/biometric_v19_6_test.dart` | Pass | **VERIFIED** |
| Idempotent Enable/Disable | `test/biometric_v19_6_test.dart` | Pass | **VERIFIED** |
| Softbox Reflector Rendering | `face_enrollment_screen.dart` | Analyzer 0 warnings | **VERIFIED** |
| Header Toggle Integration | `face_enrollment_screen.dart` | Analyzer 0 warnings | **VERIFIED** |
| Physical Photometric Efficacy | Physical Android Devices Fleet | Awaiting field testing | **NOT VERIFIED** |
