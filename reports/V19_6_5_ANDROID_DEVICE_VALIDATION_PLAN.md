# KELASAGARA BIOMATCH V19.6.5
## Android Physical Device Validation Plan & Execution Status

**Date:** 2026-10-24  
**Project:** Kelasagara BioMatch  
**Release Gate Status:** `CONTROLLED_TEST_BUILD_ONLY`  
**Biometric Calibration Approved:** `false`  
**Execution Environment:** macOS Developer Workstation with Android Toolchain & Node.js 20+ Runtime  
**Hardware Status:** **NO PHYSICAL DEVICE CONNECTED — HARDWARE VALIDATION MARKED PENDING**  

---

## 1. Physical Device Verification Statement

> [!IMPORTANT]
> Per the mandatory non-negotiable rules of V19.6.5, **no physical Android device was connected to this workstation during the execution turn**.
> All reported test passes are automated software unit tests and in-process Express route integration tests. Physical hardware verification is **PENDING** real-device execution according to the protocol defined below.

---

## 2. Test Execution Category Matrix

| Test ID | Evaluation Scenario | Category | Execution Status | Pass / Fail Criteria |
|---|---|---|---|---|
| **ENV-01** | 3-frame burst payload serialization & timing | Automated Software Test | **VERIFIED (PASS)** | Monotonic offsets, $40 \le dt \le 600\text{ ms}$, JPEG magic headers `0xFFD8` |
| **ENV-02** | Anti-freeze byte-equality check | Automated Software Test | **VERIFIED (PASS)** | Buffer equality rejected with `DUPLICATE_FRAME_REPLAY_DETECTED` |
| **ENV-03** | Express `/challenge` issuance & nonce binding | Automated Software Test | **VERIFIED (PASS)** | Nonce issued with 60s TTL, UID binding, action `BLINK` |
| **ENV-04** | Single-use nonce consumption & concurrency race | Automated Software Test | **VERIFIED (PASS)** | Second consumption returns `false`; 2 concurrent racers yield 1 win, 1 loss |
| **ENV-05** | DPDPA 2023 candidate PII masking | Automated Software Test | **VERIFIED (PASS)** | Full UID, phone, and vectors stripped; masked text returned |
| **ENV-06** | Camera permission request & denial flow | Physical Android Test | **PENDING HARDWARE** | Clear bilingual rationale shown on denial; no crash on permanent denial |
| **ENV-07** | Front-camera preview & sensor orientation (90°/270°) | Physical Android Test | **PENDING HARDWARE** | Upright preview without stretching, mirror inversion, or black borders |
| **ENV-08** | Real eyelid blink capture progression | Physical Android Test | **PENDING HARDWARE** | Eyes open -> Eyes closed -> Eyes open triggers verified state in $< 1.5\text{ s}$ |
| **ENV-09** | Display brightness restoration after exit/cancel | Physical Android Test | **PENDING HARDWARE** | System screen brightness restored to previous setting within $100\text{ ms}$ |
| **ENV-10** | Low-light indoor capture (5–15 lux) | Physical Android Test | **PENDING HARDWARE** | Adaptive illumination overlay activates; face remains detectable |
| **ENV-11** | High-contrast backlighting (window behind subject) | Physical Android Test | **PENDING HARDWARE** | Prompt instructs user to turn towards light if face underexposed |
| **ENV-12** | Eyeglass frame reflections & thick rims | Physical Android Test | **PENDING HARDWARE** | Eyelid closure detected without false rejection from frame shadows |
| **ENV-13** | Network latency & timeout recovery ($2\text{G}/3\text{G}$ edge) | Physical Android Test | **PENDING HARDWARE** | Request times out at 10s; retry prompts user cleanly without duplicate state |
| **ENV-14** | Field demographic False Match Rate study (N=500) | Research / Field Calibration | **PENDING ETHICAL PROTOCOL** | Requires signed consent, independent benchmark, demographic cohort parity |

---

## 3. Physical Device Test Protocol & Execution Steps

When an Android test device is connected via ADB (`adb devices`), execute the following manual test protocol:

```bash
# 1. Install debug APK
adb install -r build/app/outputs/flutter-apk/app-debug.apk

# 2. Monitor logcat for biometric telemetry
adb logcat -s FaceEnrollment BiometricService ISO39794 TemporalActionValidator
```

### Step-by-Step Manual Checklist

1. **Cold Launch & Navigation:**
   - Launch app, sign in with test worker credentials (`+91 98765 43210`).
   - Navigate to Face Enrollment Screen (`FaceEnrollmentScreen`).
   - *Observation:* Consent dialog is displayed in Kannada/English. Camera permission prompt appears.
2. **Camera Initialization:**
   - Accept camera permission.
   - *Observation:* Front-facing camera preview opens within 800 ms. Face oval is highlighted in Aadhaar red (`#EF4444`) with message *"ಮುಖವನ್ನು ವೃತ್ತದೊಳಗೆ ತನ್ನಿ"*.
3. **Face Alignment:**
   - Align face inside oval.
   - *Observation:* Oval turns Aadhaar green (`#10B981`) with message *"ಸ್ಥಿರವಾಗಿರಿ — ಕಣ್ಣು ಮಿಟಕಿಸಿ (Hold still — Please blink)"*. Challenge action indicator shows `BLINK`.
4. **Natural Blink Execution:**
   - Blink naturally once.
   - *Observation:*
     - Oval turns cyan (`#06B6D4`) with message *"ಕಣ್ಣು ಮಿಟುಕಿಸಲಾಗಿದೆ..."*.
     - Oval turns green with *"ಮುಖ ಸ್ಕ್ಯಾನ್ ಮಾಡಲಾಗುತ್ತಿದೆ..."*.
     - State transitions to *"ಬಯೋಮೆಟ್ರಿಕ್ ಪರಿಶೀಲಿಸಲಾಗುತ್ತಿದೆ... (Matching biometric template...)"*.
     - 3 frames are uploaded in $< 200\text{ ms}$.
5. **Server Verification & Advancement:**
   - *Observation:* SnackBar displays *"ಮುಖದ ನೋಂದಣಿ ಪೂರ್ಣಗೊಂಡಿದೆ! ಖಾತೆಯು ಆಡಳಿತಾತ್ಮಕ ಪರಿಶೀಲನೆಯಲ್ಲಿದೆ (RRL-0 Policy)"*.
   - Screen cleanly transitions to `HomeShell` with pending review badge.
6. **Hardware Resource Teardown:**
   - Check device brightness.
   - *Observation:* Screen brightness returns to user's system level. Camera indicator turns off immediately.

---

## 4. Latency Measurement Protocol (Client vs. Network vs. Server)

| Processing Stage | Target Component | Measurement Scope | Preliminary Automated / In-Process Benchmark | Physical Device Target |
|---|---|---|---|---|
| **Camera Init** | Mobile | `_camCtrl.initialize()` to first frame | N/A (Hardware camera pipeline) | $< 800\text{ ms}$ |
| **Burst Sampling** | Mobile | 3-frame crop & JPEG encoding | $3 \times 2.8\text{ ms} = \mathbf{8.4\text{ ms}}$ | $< 15\text{ ms}$ |
| **Network Upload** | Network | TLS payload upload ($15\text{ KB}$ JSON) | $0.2\text{ ms}$ (local loopback) | $150\text{--}350\text{ ms}$ ($4\text{G}$) |
| **Temporal PAD** | Backend | Sharp decode + Sobel vertical energy | Mean: $\mathbf{21.75\text{ ms}}$ \| p95: $\mathbf{25.91\text{ ms}}$ | $< 35\text{ ms}$ |
| **SFace Inference** | Backend | ONNX Runtime SFace forward pass ($112 \times 112$) | Mean: $\mathbf{6.51\text{ ms}}$ \| p95: $\mathbf{7.91\text{ ms}}$ | $< 12\text{ ms}$ |
| **1:N Search** | Backend | Cosine similarity across $1,000$ enrolled templates | Mean: $\mathbf{0.82\text{ ms}}$ \| p95: $\mathbf{1.14\text{ ms}}$ | $< 5\text{ ms}$ |
| **Total Turnaround** | End-to-End | Blink confirmation to UI result | N/A (requires device) | $< 850\text{ ms}$ |
