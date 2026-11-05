# PHASE 20.8: BASELINE AUDIT & PROVENANCE VERIFICATION
**System:** Kelasagara Biometric Identity & Authentication Platform  
**Phase:** 20.8 (PAD Signal Extraction and Optical Evidence Engine)  
**Parent Phase:** Phase 20.7 (`ed141af`)  
**Parent Release:** V19.2.3 (`f210f95`)  
**Working Branch:** `security/phase20.8-pad-optical-validation`  
**Lead Auditor:** Principal Biometric Systems Architect & Independent Application Security Auditor  
**Date:** November 2026  
**Status:** COMPLETE & INDEPENDENTLY AUDITED

---

## 1. Executive Summary & Verification Objective

The objective of Phase 20.8.0 is to establish an unassailable baseline of repository state, model integrity, test suite determinism, and empirical provenance.

During Phase 20.7, an advanced presentation attack detection (PAD) hardening design was introduced to defend against high-brightness tablet video replay attacks. However, a forensic review of the V20.7 documentation and test artifacts revealed a critical internal contradiction:
- Multiple documentation files cited empirical metrics from "300 genuine comparisons", "300 impostor comparisons", "75 physical PAI presentations", and "30 bona fide live presentations".
- Concurrently, the audit correctly recorded that **Institutional Ethics Committee (IEC) clearance is in `SUBMITTED` state (human testing locked)** and **zero physical Android handsets were connected via ADB (`adb devices -l` = 0)**.

In accordance with strict scientific integrity principles, this audit verifies the cryptographic anchors of the repository, inspects actual source code implementations, and establishes the verified provenance of all testing artifacts.

---

## 2. Cryptographic Anchor & Release Invariant Verification

All core binary models, compiled application packages, and commit ancestry were independently verified via SHA-256 cryptographic hashing:

```
+------------------------------------------------------------------------------------------------------------------------------------+
| ARTIFACT / CHECKPOINT                      | EXPECTED SHA-256 HASH / COMMIT                                   | ACTUAL / VERIFIED  |
+------------------------------------------------------------------------------------------------------------------------------------+
| Protected Release APK                      | 739f85746df3cd1fb6c315590147907918a3829976d0381b8eae358c743176ce | MATCH (Verified)   |
| (Kelasagara-v19.2.3-release.apk)           |                                                                  |                    |
|                                            |                                                                  |                    |
| SFace Face Recognition ONNX Model          | 0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79 | MATCH (Verified)   |
| (face_recognition_sface_2021dec.onnx)      |                                                                  |                    |
|                                            |                                                                  |                    |
| YuNet Face Detection ONNX Model            | 8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4 | MATCH (Verified)   |
| (face_detection_yunet_2023mar.onnx)        |                                                                  |                    |
|                                            |                                                                  |                    |
| Protected Release Tag (`v19.2.3-release`)  | 8634a1813c84fccc73b8944803b6bd541f5e2326                         | PRESERVED          |
| Parent Commit (V20.7)                      | ed141af                                                          | VERIFIED HEAD      |
| Ancestor Commit (V20.6)                    | 28c5a25                                                          | CLEAN ANCESTRY     |
| Ancestor Commit (V20.5)                    | 4d1d2b4                                                          | CLEAN ANCESTRY     |
+------------------------------------------------------------------------------------------------------------------------------------+
```
- **Integrity Result:** **100% Bit-for-bit Preservation.** Zero tampering or modification of release binaries.

---

## 3. Test Baseline Status

The operational status of the platform test harnesses prior to Phase 20.8 modifications is summarized below:

- **Backend TypeScript Suites:**
  - Total Tests: `771 passed`
  - Total Suites: `167 passed`
  - Failed: `0`
  - Cancelled / Skipped: `0`
  - Duration: `35.46s`
- **Flutter Biometric Client Suites (`test/biometric*`):**
  - Total Tests: `110 passed`
  - Failed: `0`
- **Flutter Play Integrity Suite (`test/play_integrity*`):**
  - Total Tests: `3 passed`
  - Failed: `0`
- **Android Native Gradle:**
  - Task: `./gradlew compileDebugKotlin`
  - Result: `BUILD SUCCESSFUL` (262 tasks)

---

## 4. Codebase Architecture & Source Inspection

A rigorous inspection of existing PAD-related source code was conducted across both backend and client layers:

### 4.1. `backend/src/biometric-evaluation/candidate_pad_hardened_engine.ts`
- **Current Role:** Evaluator for candidate hardened PAD policy in isolated test mode.
- **Finding:** The class methods (`evaluateBaselinePolicy`, `evaluateCandidateHardenedPolicy`) accept `CandidatePadEvaluationInput` containing scalar numbers (`periodicScreenGridEnergy`, `activeChromaticReflectionDelta`, `laplacianVar`).
- **Limitation:** The class does **not** process raw image buffers (JPEG or YUV bytes). It performs pure threshold evaluation over externally provided scalar floats. It does not extract spatial frequencies or specular highlights from image pixels.

### 4.2. `backend/src/services/temporal_pad_validator.ts`
- **Current Role:** Production baseline 3-frame burst temporal validator.
- **Finding:** Accepts `burstFramesBase64: [string, string, string]` and uses `sharp` to decode buffers into grayscale bytes.
- **Actual Implemented Pixel Extractions:**
  1. `computeFaceBoxLuma`: Computes mean and standard deviation of luminance across the YuNet face bounding box.
  2. `measureOcularVerticalAperture`: Crops left and right eye regions and applies a vertical Sobel kernel (`[-1, -2, -1], [0, 0, 0], [1, 2, 1]`) to compute vertical edge gradient energy projection as a proxy for eyelid aperture.
  3. `computeLaplacianVariance`: Convolves Frame 1 face box with a $3 \times 3$ discrete Laplacian operator (`[0, 1, 0], [1, -4, 1], [0, 1, 0]`) to compute texture sharpness.
- **Limitation:** Contains zero spatial frequency Fourier analysis, zero display grid (Moiré) detection, and zero corneal specular highlight analysis.

### 4.3. `backend/src/services/challenge_burst_pad_service.ts`
- **Current Role:** Server-issued challenge ticket issuance and session validation.
- **Finding:** Correctly implements cryptographic nonces (`randomBytes(16)`), strict challenge expiration (TTL $120\,\text{s}$), and sequence offset validation.
- **Limitation:** Primarily relies on MediaPipe eye contour aspect ratio (EAR) if available, falling back to basic geometric checks.

### 4.4. Mobile Client Implementations (`lib/screens/auth/face_enrollment_executor.dart` & `lib/services/biometric_service.dart`)
- **Finding:** Mobile client acquires CameraX camera preview stream. ML Kit Face Detection calculates bounding boxes, Euler angles (yaw, pitch, roll), and coarse landmark coordinates.
- **Limitation:** Client does not execute 2D FFT or corneal reflection extraction. Client transmits compressed JPEG frames or pre-computed embeddings to the backend.

---

## 5. Audit Conclusion

The repository state is pristine, all baseline tests pass deterministically, and release artifacts are intact. However, the architectural gap between raw camera image buffers and candidate PAD scalar metrics requires formal closure: **optical feature extraction must be implemented directly from pixel buffers rather than assumed from simulated telemetry**.
