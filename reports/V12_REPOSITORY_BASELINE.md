# KELASAGARA BIOMETRIC ENGINE V12.0
# Full-System Forensic Repository Baseline & Release Verification

**Document ID:** `REP-V12-BASEAUDIT-01`  
**System:** Kelasagara Worker Marketplace Platform  
**Target Environment:** Flutter 3.47.1, Dart 3.13.1, Android SDK 34, Node.js 24.14.0, TypeScript 5.8, Cloud Firestore, Firebase Auth  
**Evaluated Revision (HEAD):** `407650221b1fe7e85a8cdd54fd826cb2b76ce7e1`  
**Working Branch:** `ui/polish-v1`  
**Auditor:** Principal Biometric Systems Architect & Independent Security Auditor  
**Date:** 2026-10-23  

---

## 1. Executive Summary & Repository Verification

This baseline audit establishes the ground truth of the Kelasagara codebase as of 23 October 2026. The evaluation was initiated following the submission of V10.0 reports that referenced multiple commits (`b091033`, `1020693`, `a6e9506`, `4076502`) and exhibited severe architectural and security contradictions.

### 1.1 Git Repository Verification Output
```bash
$ git rev-parse HEAD
407650221b1fe7e85a8cdd54fd826cb2b76ce7e1

$ git branch --show-current
ui/polish-v1

$ git status --short
(clean working tree)

$ git log -n 5 --oneline --decorate
4076502 (HEAD -> ui/polish-v1) chore: update benchmark latency timings in audit reports
a6e9506 docs: add comprehensive V10.0 research (65 papers) and production validation reports
1020693 fix(biometrics): resolve 1:N cross-account duplicate detection failure and restore masked account sheet
33e726d docs(biometrics): complete V8.0 50+ paper research program and 14 mandatory engineering artifacts
b091033 fix(biometrics): resolve false duplicate collisions via RFF RBF kernel embedding and fix duplicate sheet account details
```

### 1.2 Binary Release Artifact Verification
The evaluated release candidate APK was inspected on disk and decompressed to verify its cryptographic signature and bundled assets:
- **Primary APK Path:** `/Users/ananda/KELASAGARA MAJOR PROJECT/kelasagara_latest.apk`
- **Build APK Path:** `kelasagaara_v17/build/app/outputs/flutter-apk/app-release.apk`
- **File Size:** `137,363,456 bytes` (~131.0 MB)
- **SHA-256 Checksum:** `57479da7a32e19afc17653f32a8816c437b61bd7a5cf63e0275be5a384c1d945`
- **Key Bundled Assets Verified:**
  * `assets/flutter_assets/assets/models/sface.onnx` (38,696,353 bytes, SHA-256: `0ba9fbfa...`)
  * `assets/flutter_assets/assets/models/yunet.onnx` (232,589 bytes, SHA-256: `8f2383e4...`)
  * `assets/flutter_assets/assets/models/minifasnet_v2_se.onnx` (265,906 bytes, SHA-256: `afd228b0...`)
  * `assets/flutter_assets/assets/models/indicface128_int8_qdq.onnx` (1,172,885 bytes, SHA-256: `cde3799f...`)
  * Google ML Kit bundled models: `blazeface.tfl`, `contours.tfl`, `fssd_25_8bit_v2.tflite`

---

## 2. Active Biometric Execution Paths & Critical Contradictions

The forensic inspection revealed an acute **architectural schism** between the client application and the backend server:

```
[FLUTTER CLIENT: lib/]                                  [NODE.JS BACKEND: backend/]
Camera Preview (ML Kit)                                Express Router (face_routes.ts)
       │                                                         │
       ▼                                                         ▼
Extracts 133 Landmarks                                  checkForbiddenVectorFields
       │                                                [REJECTS 'probeVector' WITH 400]
       ▼                                                         │
landmark_embedding.dart                                          ▼
Whitened Procrustes Projection                           Decodes imageBase64
(48-D Geometry -> 128-D Vector)                                  │
       │                                                         ▼
       ▼                                                face_inference.ts
BiometricService.enrollBiometric                         ONNX Runtime (sface.onnx)
Sends: { probeVector, imageBase64 }                              │
       │                                                         ▼
       ├────────────────────────────────────────► 128-D SFace Deep Neural Embedding
       │                                                         │
   [HTTP 400 or Network Timeout]                                 ▼
       │                                                InMemoryBiometricIndex &
       ▼                                                Firestore biometric_vault
_directFirestoreEnroll Fallback
Downloads 200 vault docs to phone!
Runs client-side cosine similarity!
Writes 128-D GEOMETRIC vector to vault!
```

### 2.1 The Two Incompatible 128-D Vector Spaces
1. **Space 1: SFace Neural Hypersphere ($\mathbb{S}^{127}_{	ext{SFace}}$):** Extracted by `backend/src/services/face_inference.ts` using `face_recognition_sface_2021dec.onnx` (MobileFaceNet trained on face crops with Sigmoid Loss). Feature dimensions represent abstract convolutional visual semantic filters.
2. **Space 2: Whitened Procrustes Geometric Hypersphere ($\mathbb{S}^{127}_{	ext{Geom}}$):** Extracted by `lib/biometrics/landmark_embedding.dart` using Gram-Schmidt orthogonal projection of 48 normalized morphological landmark coordinates. Feature dimensions represent cranial and facial distance ratios.

**Catastrophic Consequence:** Both vectors have 128 dimensions and unit L2 norm, but they occupy completely disjoint geometric manifolds. Comparing an SFace vector with a Procrustes geometric vector produces an essentially random dot product ($s pprox 0.00 \pm 0.15$).

### 2.2 The Four Failure Modes Identified
1. **Vector Field Rejection:** The backend route `face_routes.ts` applies `checkForbiddenVectorFields` on `/enroll`, explicitly blocking `probeVector`. However, `face_enrollment_screen.dart` (line 569) passes `probeVector: nativeResult.embedding.toList()`. If called against the backend, the request is rejected with HTTP 400 `CLIENT_VECTORS_FORBIDDEN`.
2. **Client Fallback Data Exposure:** When the backend is unreachable or returns an error, `biometric_service.dart` immediately falls back to `_directFirestoreEnroll()`, querying and downloading up to 200 documents from `biometric_vault` directly to the mobile phone.
3. **Cross-Account Contract Mismatch:** In `crossAccountCheck()`, Flutter sends `{'embeddingBase64': base64img}`, but the backend route `/cross-account-check` requires `{'imageBase64': string}`. The backend returns HTTP 400 `MISSING_IMAGE`, triggering Flutter to fall back to downloading 500 documents from `biometric_vault`.
4. **Overbroad Firestore Security Rules:** To allow the above client fallbacks to function without throwing permission errors, commit `1020693` updated `firestore.rules` to `allow read: if isSignedIn();` on `biometric_vault/{uid}`, allowing any logged-in user to query and read every other user's biometric template.

---

## 3. Baseline Audit Summary & Gate 0 Verdict

| Audit Domain | Current State in Repository | Severity / Evaluation |
| :--- | :--- | :--- |
| **Git & Release Build** | Branch `ui/polish-v1`, commit `4076502`. Release APK verified. | **VERIFIED** |
| **Firestore Security** | `allow read: if isSignedIn();` permits cross-user vault reads. | **CRITICAL EXPOSURE** |
| **Matching Architecture** | Dual conflicting representations (SFace vs Geometric Procrustes). | **CRITICAL SCHISM** |
| **API Contract** | Payload naming mismatch (`imageBase64` vs `embeddingBase64`). | **DEFECT** |
| **Client Fallbacks** | Direct Firestore 1:N download to client device. | **PROHIBITED** |

**Gate 0 Decision:** **PASSED WITH ACTION ITEMS**. The baseline reality is established. Proceeding immediately to Security Containment (Part 3) and Architecture Reconciliation (Part 4).
