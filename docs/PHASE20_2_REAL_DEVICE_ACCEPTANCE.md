# KELASAGARA V20.2: TRUSTED ANDROID APPLICATION INTEGRITY ENGINE
## PHASE 20.2 TECHNICAL REPORT 9: REAL GOOGLE PLAY & DEVICE ACCEPTANCE SPECIFICATION

**Author:** Senior Kotlin Engineer & Android Security Architect  
**Project:** Kelasagara Major Project  
**Phase:** 20.2 — Trusted Android Application Integrity Engine  
**Target Hardware:** Physical Android Devices (ARM64-v8a)  
**Distribution Channel:** Google Play Internal Testing & Production Track  
**Status:** Certified Device Protocol  

---

### 1. SEPARATION OF TEST ENVIRONMENTS & EVIDENCE

To prevent deceptive reporting, Kelasagara enforces strict environmental demarcation:

```
+----------------------------------------------------------------------------------------------------+
|                                    ENVIRONMENT CLASSIFICATION MATRIX                               |
+----------------------------------------------------------------------------------------------------+
|  TEST LEVEL                 |  RUNNER / INFRASTRUCTURE            |  INTEGRITY SIGNAL / VERDICT    |
+-----------------------------+-------------------------------------+--------------------------------+
|  Unit & Mock Suite          |  Node.js runner / Mock client       |  Deterministic synthetic token |
|  Cross-Runtime Parity       |  Flutter test (Dart VM)             |  Exact length-prefixed parity  |
|  Android Native Build       |  Gradle 9 / Kotlin 2.4 compiler     |  Google Play Integrity v1.4.0  |
|  Local Sideloaded APK       |  Physical device via ADB install    |  UNRECOGNIZED_VERSION          |
|  Google Play Closed Test    |  Play Store internal testing track  |  PLAY_RECOGNIZED               |
+----------------------------------------------------------------------------------------------------+
```

#### STRICT AUDIT RULES:
1. **Never conflate an emulator result with physical hardware integrity:** Emulators typically return `MEETS_VIRTUAL_INTEGRITY` or empty device verdicts.
2. **Never describe a sideloaded local APK as Play-Recognized:** Direct ADB installations return `UNRECOGNIZED_VERSION` because they lack the Google Play cryptographic installation receipt.
3. **Internal Testing vs Production:** For full `PLAY_RECOGNIZED` verification, the APK must be uploaded to the Google Play Console under Internal or Closed Testing and installed via the Play Store link.

---

### 2. REAL DEVICE TEST PROTOCOL (GOOGLE PLAY TESTING TRACK)

When executing physical validation on certified Android hardware:
1. **Device Setup:**
   - Physical Android 14+ device with Google Play Services enabled and updated.
   - Device enrolled in Google Play Internal Testing track for `com.kelasagaara.kelasagaara`.
2. **Execution Steps:**
   - Install app from Google Play Store internal test link.
   - Launch application; verify that `prepareIntegrityProvider()` completes in background ($< 250\text{ ms}$).
   - Initiate Face Enrollment (`FaceEnrollmentScreen`).
   - App computes `requestHash` from challenge session and vector digest.
   - `PlayIntegrityBridge` requests token via `tokenProvider.request(requestHash)`.
   - Token submitted with enrollment payload to `/auth/biometrics/v10/enroll`.
   - Backend decodes token via Google Play Developer API.
3. **Expected Verification Claims:**
   - `requestPackageName`: `"com.kelasagaara.kelasagaara"`
   - `appRecognitionVerdict`: `"PLAY_RECOGNIZED"`
   - `deviceRecognitionVerdict`: `["MEETS_DEVICE_INTEGRITY", "MEETS_BASIC_INTEGRITY"]`
   - `requestHash`: Exact match to canonical transaction digest.
   - Result: HTTP 200 `INTEGRITY_ACCEPTED`.
