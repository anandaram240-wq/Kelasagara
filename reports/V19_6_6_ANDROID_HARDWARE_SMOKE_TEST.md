# KELASAGARA BIOMATCH V19.6.6
## Android Hardware Smoke Test & Physical Device Discovery Report

**Milestone:** V19.6.6 — Advanced Android Hardware Validation  
**Date:** 2026-10-24  
**Release Gate Status:** `CONTROLLED_TEST_BUILD_ONLY`  
**Production Calibration Approved:** `false`  
**Audit Author:** Kelasagara Systems & Biometrics Engineering Team  
**Evaluation Target:** Real Android phone availability, ADB daemon state, camera hardware diagnostics  

---

### 1. Executive Summary & Hardware Availability Reality

In strict compliance with V19.6.6 guidelines requiring absolute fidelity to measured evidence, this audit reports the exact operational state of physical Android hardware attached to the engineering workstation.

**Hardware Status:** `BLOCKED_ON_PHYSICAL_DEVICE` / `PENDING`  
**Fabrication Guard:** Under no circumstances are simulated or hypothetical device results presented as physical hardware measurements.

#### Workstation Device Discovery Execution
```bash
$ pwd
/Users/ananda/KELASAGARA MAJOR PROJECT/kelasagaara_v17

$ adb devices -l
List of devices attached
# [EMPTY - 0 devices detected]

$ flutter devices
2 connected devices:
macOS (desktop) • macos  • darwin-arm64   • macOS 15.3.1 24D70 darwin-arm64
Chrome (web)    • chrome • web-javascript • Google Chrome 134.0.6998.88

$ flutter emulators
No emulators available. Run 'flutter emulators --create' to create one.
```

No physical Android device or running virtual Android emulator is currently attached over USB or ADB Wi-Fi on workstation port 5037. Consequently, physical on-device hardware benchmarks are marked `PENDING` and must be executed in accordance with the reproducible physical verification checklist in Section 4.

---

### 2. Instrumented Debug Diagnostics Architecture

To ensure immediate, reproducible, zero-friction telemetry collection the moment a physical handset is connected, V19.6.6 implements safe, debug-only hardware diagnostics in:
- [`lib/biometrics/debug_capture_diagnostics.dart`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/lib/biometrics/debug_capture_diagnostics.dart)
- Integrated into [`lib/screens/auth/face_enrollment_screen.dart`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/lib/screens/auth/face_enrollment_screen.dart)

#### Compliance & Safety Safeguards
1. **Zero Production Overhead:** All diagnostic methods evaluate `if (kReleaseMode) return;` at entry. In production release builds (`flutter build apk --release`), compiler tree-shaking and dead-code elimination remove diagnostic operations.
2. **ISO/IEC 24745:2022 & DPDPA 2023 Compliance:** Zero private biometric information (raw camera frames, facial crops, face coordinates, or 128-D embedding vectors) is recorded or exported. Only sanitized operational metadata is stored:
   - Camera initialization latency ($t_{init}$)
   - Camera stream FPS estimate
   - Frame planar layout geometry (plane count, row strides, pixel strides, dimensions)
   - Upright facial cropping and JPEG encoding latency ($t_{crop}$)
   - Monotonic burst intervals ($dt_{01}, dt_{12}$)
   - Compressed payload byte sizes
   - Network transmission duration ($t_{upload}$)
   - Final status code (`verified`, `rejected`, `failed`)

---

### 3. Automated Harness Verification Evidence

The diagnostic capture harness was rigorously validated via automated test suite [`test/v19_6_6_hardware_and_photometric_test.dart`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/test/v19_6_6_hardware_and_photometric_test.dart):

```
00:00 +0: V19.6.6 Debug Capture Diagnostics Telemetry 1. Session lifecycle initializes cleanly and generates unique session ID
00:00 +1: V19.6.6 Debug Capture Diagnostics Telemetry 2. Accurately estimates frame stream FPS over monotonic intervals
00:00 +2: V19.6.6 Debug Capture Diagnostics Telemetry 3. Captures camera plane layout metadata without PII or pixel data
00:00 +3: V19.6.6 Debug Capture Diagnostics Telemetry 4. Calculates monotonic burst intervals and tracks crop durations
00:00 +4: V19.6.6 Debug Capture Diagnostics Telemetry 5. toSafeJson satisfies ISO 24745 and DPDPA 2023 privacy invariants
```
*Result: 5/5 diagnostics tests passed in 0.8s.*

---

### 4. Reproducible Physical Handset Test Runbook

When a physical Android handset (e.g. Redmi 9A, Samsung Galaxy M12, OnePlus Nord, or Pixel 6a) is connected, engineers must execute the following protocol:

#### Step 1: Device Connectivity Check
```bash
adb devices -l
# Expected output: <device_serial> device usb:<port> product:<model> model:<model> device:<codename>
```

#### Step 2: Install and Launch V19.6.6 Debug Build
```bash
cd "/Users/ananda/KELASAGARA MAJOR PROJECT/kelasagaara_v17"
flutter run -d <device_serial> --debug
```

#### Step 3: Physical Capture Verification Checklist
1. **Camera Permission Grant:** Confirm Android runtime dialog displays `"Allow Kelasagara to take pictures and record video?"` and user tap succeeds.
2. **Preview Orientation & Aspect Ratio:** Confirm front camera preview displays upright without anamorphic distortion (vertical oval overlay aligned with natural eye height).
3. **Lighting & Oval Feedback:**
   - Under normal indoor light, verify oval turns green when face is centered.
   - In dim light ($< 15\text{ lux}$), verify screen brightness elevates smoothly without permission prompt.
4. **Action Liveness Interaction:**
   - User follows prompt: "ದಯವಿಟ್ಟು ನಿಮ್ಮ ಕಣ್ಣುಗಳನ್ನು ನಿಧಾನವಾಗಿ ಮಿಟುಕಿಸಿ (Please blink your eyes naturally)".
   - Confirm baseline open, blink close, and recovery open triggers capture within $150\text{--}400\text{ ms}$.
5. **Backend Ingestion & Logcat Review:**
```bash
adb logcat -s flutter:V FaceEnrollment:V
```
Verify log emits sanitized diagnostic session telemetry:
```json
{
  "sessionId": "diag_1729775400000_3a1b",
  "cameraInitDurationMs": 420,
  "streamFpsEstimate": 29.8,
  "planeLayout": {"planeCount": 2, "width": 1280, "height": 720, "rowStrides": [1280, 1280], "pixelStrides": [1, 2]},
  "cropAndEncodeDurationsMs": [14, 15, 13],
  "burstFrameIntervalsMs": [165, 172],
  "jpegByteSizes": [14250, 13980, 14420],
  "uploadDurationMs": 310,
  "outcomeStatus": "verified"
}
```

---

### 5. Conclusion & Operational Gate

Until a physical Android phone is connected and the runbook above is executed end-to-end, hardware-dependent milestone gates remain:
- **Android Physical Hardware Smoke Test:** `PENDING`
- **Release Gate Status:** `CONTROLLED_TEST_BUILD_ONLY`
- **Production Biometric Calibration:** `NOT_APPROVED`
