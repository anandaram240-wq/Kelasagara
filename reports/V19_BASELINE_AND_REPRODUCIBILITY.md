# V19 Baseline and Reproducibility Report

## 1. Environment & Working Tree Baseline
- **Repository Location:** `/Users/ananda/KELASAGARA MAJOR PROJECT/kelasagaara_v17`
- **Active Git Branch:** `ui/polish-v1`
- **Head Commit:** `51522ae` (`feat(biometrics): integrate requestBiometricChallenge Callable Cloud Function with 60s Firestore transaction & Flutter fallback`)
- **Release Status:** `CONTROLLED_TEST_BUILD_ONLY`
- **Biometric Identity Gate:** `productionBiometricCalibrationApproved = false`

## 2. Verified Subsystems & Execution Trace
| Subsystem | Verified Tool / Command | Real Exit Code | Actual Result | Status |
|:---|:---|:---:|:---|:---:|
| **Cloud Functions (TS)** | `cd functions && npx tsc --noEmit` | `0` | Clean compilation, 0 errors | **EXECUTED** |
| **Cloud Functions (Tests)**| `cd functions && npx jest test/request_biometric_challenge.test.ts` | `0` | 3/3 tests passed (3.04s) | **EXECUTED** |
| **Backend Express (TS/Node)**| `cd backend && npm test` | `0` | 230/230 tests passed (42.5s, 44 suites) | **EXECUTED** |
| **Flutter Mobile Analysis**| `flutter analyze lib/services/ lib/screens/auth/` | `0` | Clean analysis, 0 errors | **EXECUTED** |
| **Flutter Mobile Build**| `flutter build apk --release` | `0` | `app-release.apk` (137.9MB) assembled in 60.4s | **EXECUTED** |
| **Release Artifact Delivery**| `cp build/app/outputs/flutter-apk/app-release.apk ../kelasagara_latest.apk` | `0` | 132MB APK available at `/Users/ananda/KELASAGARA MAJOR PROJECT/kelasagara_latest.apk` | **EXECUTED** |

## 3. Discovered Model & Preprocessing Invariants
1. **Primary Model Weights:** `models/face_recognition_sface_2021dec.onnx`
   - **Sha256:** `fc969cd1032df4971c262bf6a995db0112999e2e` (OpenCV Zoo Apache 2.0)
   - **Output Vector:** 128-dimensional Float32Array on unit hypersphere $\mathbb{S}^{127}$ ($||v||_2 = 1.0$)
   - **Canonical Preprocessing:** $112 \times 112$ BGR crop, aligned via 5-point similarity transform, scaled $(x - 127.5)/128.0$.
2. **Quality & PAD Gating:** Performed strictly upstream of SFace inference.
   - Dense mesh landmarks from ML Kit are used exclusively for pose, bounding box, and temporal ocular compression.
   - Zero client-supplied identity vectors are accepted by backend routes (`assertNoClientSuppliedVectors` strictly rejects `probeVector`).
