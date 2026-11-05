# DEVICE ATTESTATION & FRAME PROVENANCE ARCHITECTURE SPECIFICATION
**Standard:** Kelasagara BioMatch Stage S2 / Prompt 9 (Ticket E-02)  
**Classification:** Sovereign Gig-Economy Identity Security  
**Date:** 10 October 2026  

---

## 1. Threat Model & Executive Summary

Biometric authentication in gig-economy and onboarding workflows faces two distinct classes of adversarial spoofing:
1. **Presentation Attacks (PAD):** Physical artifacts presented to a real camera sensor (printed photos, screens, 3D masks, silicone prosthetics).
2. **Injection Attacks (IAD):** Digital video streams injected directly into the operating system camera pipeline or framework layer (Android virtual camera apps, OBS virtual cameras, emulator webcam bridges, Frida/Xposed hooks on `android.hardware.camera2`).

A traditional challenge nonce (`challengeNonce`) defends against network replay of previous HTTP requests, but **provides zero defense against real-time synthetic injection attacks**. Similarly, device attestation tokens (Google Play Integrity API, Firebase App Check) prove that the calling application is authentic, untampered, and running on an authorized Android device, but **cannot by themselves prove that pixel data originated from physical photons hitting a physical CMOS/CCD sensor**.

Kelasagara implements a defense-in-depth architecture:
- **Layer 1: Device & App Integrity (Play Integrity / App Check):** Blocks emulators, rooted devices, and uncertified environments.
- **Layer 2: Hardware-Backed Keystore Key Attestation (Ticket E-07):** Signs frame hashes using an Android KeyStore EC key generated with `PURPOSE_SIGN` and `setAttestationChallenge`.
- **Layer 3: Cryptographic Frame Provenance Binding (Invariant I-25):** Binds the raw image SHA-256, active session nonce, device ID, and camera hardware capture timestamp.
- **Layer 4: Server-Side Landmark & Motion Inference (Ticket E-03):** Decodes raw frames server-side and extracts 3D motion/blinking dynamics, rejecting static 2D images regardless of client-reported metadata.

---

## 2. Attestation Token Guarantees vs. Sensor-Level Guarantees

| Capability / Risk Dimension | Play Integrity API | Firebase App Check | Hardware Keystore (Key Attestation) | Kelasagara Biometric Frame Provenance |
|:---|:---:|:---:|:---:|:---:|
| **App Binary Authenticity** | ✅ Guarantees licensed app package & signing cert | ✅ Guarantees app identity via SafetyNet/Play | ⚠️ N/A (validates key ownership) | ⚠️ N/A |
| **Physical Device Verification** | ✅ Distinguishes real device vs emulator (`MEETS_DEVICE_INTEGRITY`) | ⚠️ Partial (App Check token) | ✅ Hardware backed in TEE/StrongBox | ⚠️ Bound to hardware device ID |
| **Frida / Xposed Hook Detection** | ✅ Flags uncertified ROM / hook modified environment | ⚠️ Relies on underlying provider | ✅ Hardware key inaccessible to hook | ⚠️ N/A |
| **Photons-to-Sensor Provenance** | ❌ **NO** (Camera output is OS pipeline, not attestation scope) | ❌ **NO** | ❌ **NO** (Signs byte buffer, cannot verify CMOS origin) | ⚠️ Cryptographic hash binding prevents tampering post-capture |
| **Anti-Replay Freshness** | ⚠️ Sliding window | ⚠️ Sliding window | ✅ Nonce signed in payload | ✅ Challenge nonce + 60s capture timestamp skew |
| **Real-Time Liveness / Face Dynamics** | ❌ **NO** | ❌ **NO** | ❌ **NO** | ✅ **YES** (Server-side multi-gesture temporal variance) |

---

## 3. Sovereign Defense-in-Depth Implementation

```
[Mobile Device Camera]
       │ (Physical Photons)
       ▼
[Android Camera2 API (Native)]
       │
       ├─ Compute SHA-256(rawFrameBuffer)
       ├─ Read Active Session Nonce (from Server /api/biometrics/challenge)
       ├─ Sign with Android Keystore (KeyStore Hardware EC key)
       ├─ Collect Play Integrity JWE Token
       ▼
[HTTPS POST /api/biometrics/verify-1to1 | /re-verify | /enroll]
       │
       ▼
[Kelasagara Node.js / TypeScript Gateway]
       ├─ 1. Invariant I-01 / I-26: DeviceAttestationService.verifyDeviceIntegrity(token)
       │     └─ Reject emulators, hooking signatures, uncertified environments
       │     └─ Strictly forbid mock tokens in production (`NODE_ENV === 'production'`)
       ├─ 2. Invariant I-25: DeviceAttestationService.verifyFrameProvenance(buffer, provenance, nonce)
       │     ├─ Validate nonce matches active session
       │     ├─ Validate SHA-256(buffer) === provenance.frameSha256
       │     ├─ Validate captureTimestamp skew <= 60,000ms
       │     └─ Validate Keystore EC signature (Ticket E-07)
       ├─ 3. Invariant I-03 / I-30: ServerLandmarkExtractor.extractFromBuffer(buffer)
       │     └─ Server infers landmarks from pixels (Zero trust in client coordinates)
       └─ 4. Invariant I-09 / I-18: SFace ONNX Inference & RAM Gallery Cosine Match
```

---

## 4. Production Enforcement Guard

Under `backend/src/services/device_attestation.ts`:
- If `process.env.NODE_ENV === 'production'`:
  - `allowDevBypass` is **strictly forbidden**. Any attempt to bypass attestation fails closed with `EMULATOR_HOOKING_DETECTED`.
  - Tokens prefixed with `mock_` are **strictly rejected**.
  - All production clients must provide valid Google Play Integrity or Firebase App Check tokens evaluating to at least `MEETS_DEVICE_INTEGRITY`.
