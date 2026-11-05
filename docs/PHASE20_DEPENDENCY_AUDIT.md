# KELASAGARA V20.0 — PHASE 20.0 DEPENDENCY AUDIT
## Comprehensive Software Bill of Materials (SBOM), Model Asset Integrity & Supply Chain Audit

- **System:** Kelasagara Major Project
- **Audit Date:** 31 October 2026
- **Auditor Role:** Principal Biometric Systems Architect & Security Auditor
- **Compliance Constraint:** Zero dependency modifications permitted in Phase 20.0

---

## 1. Machine Learning Model Artifacts & Integrity Audit

Both the Flutter client (`assets/models/`) and the backend daemon (`backend/models/`) host pre-trained deep learning model binaries in Open Neural Network Exchange (ONNX) format.

### 1.1 Cryptographic Model Hash Verification

| Model Asset Name | Physical File Size | SHA-256 Cryptographic Hash | Architecture / Source | Licence |
|---|---|---|---|---|
| **SFace Primary (FP32)**<br>`sface.onnx` / `face_recognition_sface_2021dec.onnx` | 38,696,353 bytes (36.9 MB) | `0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79` | MobileFaceNet backbone + Sigmoid-Constrained Loss (OpenCV Zoo) | Apache 2.0 (Permissive) |
| **YuNet Face Detector**<br>`yunet.onnx` / `face_detection_yunet_2023mar.onnx` | 232,589 bytes (227 KB) | `8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4` | Ultra-lightweight anchor-free face detector with 5 landmarks | Apache 2.0 (Permissive) |
| **SFace INT8 Quantized**<br>`face_recognition_sface_2021dec_int8.onnx` | 9,896,933 bytes (9.4 MB) | `2b0e941e6f16cc048c20aee0c8e31f569118f65d702914540f7bfdc14048d78a` | Quantized INT8 SFace for low-memory CPU edge inference | Apache 2.0 (Permissive) |
| **MobileFaceNet Secondary**<br>`indicface128_int8_qdq.onnx` / `kelasagara_mobilefacenet.onnx` | 1,172,885 bytes (1.1 MB) | `cde3799f041eca6a6a99bfac53d9e97eb81ff34ac450d519aa41a9c99bef7d7c` | Lightweight 128-D embedding model | Apache 2.0 (Permissive) |
| **MiniFASNetV2 Anti-Spoofing**<br>`minifasnet_v2_se.onnx` | 265,906 bytes (260 KB) | `afd228b05f90b32789bd120682db208468b14532991387068aa8cfb4bb6ab319` | Squeeze-and-Excitation binary presentation attack detector | Apache 2.0 (Permissive) |

**Forensic Finding:** The SHA-256 hashes of client assets and backend models match bit-for-bit:
- Client `assets/models/sface.onnx` $\equiv$ Backend `backend/models/face_recognition_sface_2021dec.onnx`
- Client `assets/models/yunet.onnx` $\equiv$ Backend `backend/models/face_detection_yunet_2023mar.onnx`
- Client `assets/models/kelasagara_mobilefacenet.onnx` $\equiv$ Backend `backend/models/kelasagara_mobilefacenet.onnx`

---

## 2. Backend Node.js & TypeScript Dependencies (`backend/package.json`)

| Package Name | Specified Version | Resolved / Installed | Security / Operational Function | Risk Tier |
|---|---|---|---|---|
| `onnxruntime-node` | `^1.20.1` | `1.20.1` | Native C++ ONNX engine bindings for server-side SFace embedding extraction | Low |
| `firebase-admin` | `^12.0.0` | `12.0.0` | Server-side Firestore transactions, token authentication, and Admin SDK access | Low |
| `@google-cloud/kms` | `^6.3.0` | `6.3.0` | Google Cloud Key Management Service (KMS) hardware envelope encryption client | Low |
| `express` | `^4.21.2` | `4.21.2` | HTTP web server framework hosting biometric REST API endpoints | Low |
| `cors` | `^2.8.5` | `2.8.5` | Origin filtering middleware (configured with strict origin whitelist) | Low |
| `dotenv` | `^16.4.7` | `16.4.7` | Local environment variable hydration | Low |
| `sharp` | `^0.35.5` | `0.35.5` | High-performance Libvips image decoding and 112×112 face cropping | Low |
| `typescript` | `^5.3.3` | `5.3.3` | Static type compilation (`tsc`) | Low |

---

## 3. Flutter Client Dependencies (`pubspec.yaml`)

| Package Name | Specified Version | Function in Biometric Engine | Status |
|---|---|---|---|
| `google_mlkit_face_detection` | `^0.13.0` | On-device Camera2 frame analysis, 478-point facial contour tracking, and 12-point eyelid EAR calculation | Verified |
| `camera` | `^0.11.0+2` | Hardware CameraX/Camera2 front camera frame capture and streaming | Verified |
| `dio` | `^5.7.0` | Network client with custom `HttpClient.connectionFactory` for direct Anycast IP routing | Verified |
| `crypto` | `^3.0.3` | SHA-256 hashing for request fingerprints and Play Integrity hashes | Verified |
| `cryptography` | `^2.9.0` | High-performance cryptographic primitives | Verified |
| `screen_brightness` | `^2.1.11` | Automated white screen illumination stepping for low-light face capture | Verified |
| `ffi` | `^2.1.3` | Foreign Function Interface for optional native C++ inference acceleration | Verified |
| `image` | `^4.2.0` | Pure-Dart image manipulation, YUV420 to RGB conversion | Verified |

---

## 4. Supply Chain & Licence Compliance

All biometric and machine learning dependencies utilize permissive, open-source licences:
- **ONNX Runtime:** MIT Licence
- **OpenCV Zoo SFace / YuNet:** Apache Licence 2.0 (Permissive for commercial and research use)
- **Google ML Kit Face Detection:** Apache Licence 2.0
- **Flutter Framework & Plugins:** BSD-3-Clause / MIT

No copyleft (GPL / AGPL) libraries are linked, ensuring full intellectual property compliance for the major project submission.
