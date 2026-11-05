# PHASE 20.7 CAMERA QUALIFICATION
## Android CameraX Capture Validation, Lifecycle Management, and Sensor Pipeline Invariants

**Project:** Kelasagara Major Project  
**System:** Multi-Factor Biometric Identity and Authentication Platform  
**Phase:** 20.7 (Controlled Physical Biometric Validation & PAD Hardening)  
**Framework:** Flutter 3.29 + Android CameraX (`camera_android_camerax`)  
**Date:** 2026-11-01  

---

## 1. FIFTEEN MANDATORY CAMERA VALIDATION CHECKS

To ensure robust capture across low-cost and flagship Android smartphones without app crashes or memory leaks, the Flutter capture pipeline (`BiometricV11LivenessScanner` and `FaceEnrollmentExecutor`) enforces fifteen lifecycle and sensor validation checks:

```
┌────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                              FIFTEEN ANDROID CAMERA QUALIFICATION CHECKS                               │
├────┬─────────────────────────────┬────────────────────────────────────────────────────────────────────┤
│ #  │ Lifecycle & Sensor Check    │ Operational Verification Standard                                  │
├────┼─────────────────────────────┼────────────────────────────────────────────────────────────────────┤
│ 1  │ Camera Permission           │ Request via `permission_handler`; handle permanent denial gracefully│
│ 2  │ Front-Camera Initialization │ Probe CameraLensDirection.front; fallback if unavailable           │
│ 3  │ Camera Lifecycle Binding    │ Attach to Flutter WidgetsBindingObserver (AppLifecycleState)       │
│ 4  │ Camera Restart Cleanliness  │ Dispose CameraController cleanly before re-instantiating stream    │
│ 5  │ Camera Sensor Orientation   │ Compensate for 270° sensor orientation on Android front cameras    │
│ 6  │ Image EXIF Rotation         │ Auto-rotate bitmap to upright 0° prior to Umeyama face alignment   │
│ 7  │ Image Dimensions            │ Enforce minimum 720p (1280x720); prefer 1080p (1920x1080)          │
│ 8  │ Exposure Compensation       │ Auto-exposure lock during 3-frame burst to prevent artificial flux │
│ 9  │ White Balance Stability     │ Auto-white-balance locked during 3-frame temporal burst            │
│ 10 │ Frame Timing Cadence        │ Assert inter-frame interval dt in [40ms, 350ms]                    │
│ 11 │ Low-Light Screen Fill       │ Auto-trigger adaptive white screen-fill when lux < 20              │
│ 12 │ Motion Blur Gate (FIQA)     │ Compute Laplacian variance; reject frame if sigma^2 < 110.0        │
│ 13 │ Camera Closure              │ Dispose native camera session immediately after burst acquisition  │
│ 14 │ App Backgrounding           │ Pause stream instantly when AppLifecycleState = paused             │
│ 15 │ Process Termination Cleanup │ Release Android camera hardware lock; prevent camera service hang  │
└────┴─────────────────────────────┴────────────────────────────────────────────────────────────────────┘
```

---

## 2. CAMERA LIFECYCLE STATE MACHINE (FLUTTER / CAMERAX)

The Flutter UI widget `BiometricV11LivenessScanner` implements a leak-proof state machine ensuring that hardware resources are released whenever the user switches apps or closes the screen:

```
[Screen Mounted]
       │
       ▼
 [Initialize Front Camera] (ResolutionPreset.high, YUV_420_888)
       │
       ▼
 [Camera Active: Streaming Frames]
       │
       ├─────────────────────────────────────────┐
       │ (User Backgrounds App)                  │ (Burst Completed / Cancelled)
       ▼                                         ▼
 [AppLifecycleState.paused]                [Dispose CameraController]
       │                                         │
       ▼                                         ▼
 [Release Native CameraX Lock]             [Release Native Hardware Handle]
       │                                         │
       ▼                                         ▼
 [App Resumed: Re-initialize Controller]   [Zero Memory Buffers & Exit]
```

---

## 3. ZERO-RETENTION IN-MEMORY CAPTURE PIPELINE

To satisfy privacy mandates and prevent sensitive image accumulation:
1. **Zero Disk Caching:** Raw camera frame buffers are held strictly in temporary RAM (`Uint8List`). At no point are unencrypted `.jpg` or `.png` files saved to Android cache directories (`/data/user/0/com.kelasagara.../cache`).
2. **Ephemeral Memory Zero-Fill:** As soon as the base64 burst payload is constructed and signed with the Android Keystore key, the underlying image byte buffers are overwritten in memory:
   ```dart
   frameBuffer.fillRange(0, frameBuffer.length, 0);
   ```
3. **No Background Storage:** If the user exits the biometric scanner before completing the burst, all temporary buffers are discarded immediately.
