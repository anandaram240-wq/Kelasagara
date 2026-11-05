# KELASAGARA V15.0 BIOMETRIC ENGINE AUDIT
# REPORT 09: PRESENTATION ATTACK DETECTION (PAD) & LIVENESS EVIDENCE AUDIT

**Document ID:** KLS-V15-PAD-001  
**Classification:** BIOMETRIC SECURITY ARCHITECTURE AUDIT  
**Standards Conformance:** ISO/IEC 30107-3:2023 (Presentation Attack Detection Testing and Reporting)  
**Audit Finding:** PHYSICAL PAD UNTESTED / SINGLE-FRAME BACKEND LIMITATION CONFIRMED  
**Audit Date:** 2026-10-23  

---

## 1. DEVICE INTEGRITY VS. BIOMETRIC PHYSICAL LIVENESS

A pervasive source of confusion in mobile biometric systems is the conflation of **device and app integrity** with **biometric physical liveness**.

Kelasagara integrates the **Google Play Integrity API** in `FaceEnrollmentExecutor` to verify:
- The calling application package is untampered (`APP_LICENSED`).
- The Android operating system is authentic and unrooted (`MEETS_DEVICE_INTEGRITY`).
- The request payload has not been modified in transit (cryptographic binding of server nonce and request hash).

### The Critical Security Distinction:
- **Play Integrity verifies the phone:** It proves that an official, unrooted Android device is communicating with the server.
- **Biometrics must verify the human:** It must prove that physical optical photons emitted from genuine living human skin and tissue entered the camera lens, rather than photons from a 4K tablet screen, a printed photograph, or a 3D latex mask.

**Play Integrity does NOT protect against presentation attacks (spoofs) presented in front of an authentic device camera.**

---

## 2. THE SINGLE-FRAME STATIC JPEG ARCHITECTURAL GAP

Forensic inspection of the Flutter-to-Backend data flow reveals an architectural vulnerability:

```
[Flutter Mobile Client]                                    [Node.js Backend Microservice]
-----------------------                                    ------------------------------
1. Stream camera frames to ML Kit.
2. Track eye aspect ratio (EAR).
3. Detect eye blink sequence:
   (Open >= 0.58 -> Closed <= 0.28 -> Open >= 0.58).
4. Blink Verified locally!
5. Call camera.takePicture() ----------------------------> POST /api/biometrics/verify-1to1
   (Captures SINGLE static JPEG image)                     Payload: { imageBase64: "..." }
                                                           
                                                           Backend Execution:
                                                           1. Decode Base64 to Buffer.
                                                           2. YuNet detects face crop.
                                                           3. SFace extracts 128-D vector.
                                                           4. Compute cosine similarity.
                                                           5. Return: { isMatch: true }
```

### Vulnerability Analysis:
1. **Zero Server-Side Temporal Validation:** The backend receives only **one static 2D image**. It has no visibility into whether motion occurred, whether the eye blinked, or how the facial texture varied across time.
2. **Replay & Injection Attacks:** If an attacker uses a rooted device, an Android Virtual Camera hook (e.g., Magisk with CameraV2 mock modules), or modifies the client APK, they can execute the blink check against a live face (or bypass the conditional statement) and transmit a stolen high-resolution photograph of the target victim to the backend.
3. **No Passive Liveness on Backend:** The backend SFace inference pipeline does not execute passive spoof classification (e.g., MiniFASNet, Silent-Face-Anti-Spoofing, or Fourier frequency analysis).

---

## 3. AUDIT OF ISO 30107-3 EVIDENCE CLAIMS

Historical reports claimed compliance with **ISO/IEC 30107-3** with metrics such as "APCER < 1.2%, BPCER < 1.8%".

### Audit Findings:
1. **Origin of Metrics:**  
   The reported metrics were copied from published research papers for the `MiniFASNetV2-SE` neural network on the academic CelebA-Spoof benchmark.
2. **Implementation Status in Repository:**  
   While `lib/biometrics/pad_inference.dart` and `iso30107_pad_controller.dart` exist in the client repository, they act as wrappers and lack on-device quantized model binaries in production builds.
3. **Physical Presentation Testing Reality:**  
   **No physical presentation attack testing has ever been performed on the Kelasagara system.**  
   The application has not been tested against:
   - High-resolution matte photo printouts (Print Attack).
   - High-definition smartphone/tablet video replays (Replay Attack).
   - Cut-out eye photo masks (2D Mask Attack).
   - 3D silicone or latex mannequin masks (3D Mask Attack).

---

## 4. PROPOSED MULTI-FRAME SHORT BURST ARCHITECTURE

To bridge the architectural gap between client blink detection and server verification, the following multi-frame burst pipeline is recommended for future development:

```
+-----------------------------------------------------------------------------+
|                     PROPOSED MULTI-FRAME BURST PIPELINE                     |
+-----------------------------------------------------------------------------+
1. Upon blink trigger, client captures a rapid 3-frame burst (Δt = 100ms):     |
   - Frame 1: Eyes open (pre-blink)                                           |
   - Frame 2: Eyes closed (blink apex)                                        |
   - Frame 3: Eyes open (post-blink)                                          |
2. Client transmits all 3 frames in a single multipart POST payload.          |
3. Backend executes:                                                          |
   a. Photometric consistency check across all 3 frames (ambient light flux). |
   b. YuNet landmark tracking to confirm ocular closure in Frame 2.           |
   c. SFace identity vector extraction on Frame 1 and Frame 3.                |
   d. Cosine similarity between Frame 1 and Frame 3 must exceed 0.85          |
      (proves the same physical head remained in front of the lens).          |
+-----------------------------------------------------------------------------+
```

---

## 5. CONCLUSION & RELEASE GATE IMPACT

Because the server-side pipeline processes only static single frames and physical presentation attack resistance has never been empirically evaluated, the biometric engine **fails Production Gate G-02**.

**Release Status: CONTROLLED TEST BUILD ONLY (Physical Presentation Attack Resistance Unvalidated).**
