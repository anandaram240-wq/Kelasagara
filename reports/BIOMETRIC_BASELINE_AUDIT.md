# KELASAGARA BIOMETRIC ENGINE
## Forensic Baseline Audit & Repository Inventory

**Audit Date:** October 23, 2026  
**Auditor:** Principal Biometric Systems Engineer & Lead Security Architect  
**Repository Branch:** `ui/polish-v1`  
**Current HEAD Commit:** `0477f6f` (Clean Working Tree)  
**Release Artifact:** `kelasagara_latest.apk` (137,363,456 bytes, SHA-256: `57479da7a32e19afc17653f32a8816c437b61bd7a5cf63e0275be5a384c1d945`)  

---

## 1. Environment & Stack Inventory

| Component | Technical Specification | Location in Repository |
| :--- | :--- | :--- |
| **Mobile Application** | Flutter 3.24+ / Dart 3.5+ (Android SDK 34, minSdk 24) | `kelasagaara_v17/` |
| **Backend Service** | Node.js v20 LTS / TypeScript 5.4 / Express 4.19 | `kelasagaara_v17/backend/` |
| **Inference Engine** | ONNX Runtime (`onnxruntime-node` v1.17+) | `backend/src/services/face_inference.ts` |
| **Datastore** | Google Cloud Firestore (Standard Edition) | `firestore.rules` |
| **Authentication** | Firebase Authentication (Phone Auth + Custom Token Exchange) | Flutter Firebase Auth SDK |
| **Key Management** | Envelope Encryption AES-256-GCM / Google Cloud KMS | `backend/src/services/kms_envelope_encryption.ts` |

---

## 2. On-Disk Model Asset Integrity

| Model Identifier | Relative File Path | Size (Bytes) | Verified SHA-256 Checksum | License | Verified Role |
| :--- | :--- | :---: | :---: | :---: | :--- |
| **SFace 2021dec** | `backend/models/face_recognition_sface_2021dec.onnx` | 38,696,353 | `0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79` | Apache 2.0 | **Sole Authoritative Feature Extractor** (1:1 & 1:N) |
| **YuNet 2023mar** | `backend/models/face_detection_yunet_2023mar.onnx` | 232,589 | `8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4` | MIT | Server-side face localization & 5-point alignment |
| **IndicFace128 INT8** | `backend/models/indicface128_int8_qdq.onnx` | 1,172,885 | `cde3799f041eca6a6a99bfac53d9e97eb81ff34ac450d519aa41a9c99bef7d7c` | Apache 2.0 | Standalone offline mobile fallback model |
| **ML Kit Face** | Dynamic AAR (`google_mlkit_face_detection: ^0.13.0`) | Dynamic | N/A | Apache 2.0 | Mobile client capture, quality & 133-point landmarks |

---

## 3. End-to-End Execution Trace

### 3.1 Enrollment & Registration Flow
```
[ 1. Mobile Camera2 Stream (30 FPS) ]
      │
      ▼
[ 2. AdvancedLandmarkAnalyzer (ML Kit, 133 Landmarks) ]
      ├── ISO 29794-5 Quality Check: IPD ≥ 90px, |yaw| ≤ 5°, |pitch| ≤ 5°, |roll| ≤ 8°
      ├── Discrete 2D Laplacian Sharpness: σ²L ≥ 110 (print attack filter), σ²L ≤ 1850 (moiré screen filter)
      └── Kinematic Blink Validation: 5 consecutive open frames (EAR ≥ 0.58) + 2 closed frames (EAR ≤ 0.28)
      │
      ▼
[ 3. Packaging & Cryptographic Binding ]
      ├── Capture Frame JPEG Crop (112×112)
      ├── Compute WADH = SHA-256(UID || Nonce || FrameDigest || σ²L || BlinkVerdict || IPD)
      └── Native RAM Cleanup: Raw pixel buffers zeroed immediately per DPDPA 2023 §8(3)
      │
      ▼ TLS 1.3 / HTTP POST /api/biometrics/enroll
[ 4. Backend Gateway & Security Enforcement ]
      ├── Authenticate Firebase ID Token (Bearer Token)
      ├── checkForbiddenVectorFields: Rejects any probeVector/embedding with HTTP 400 Bad Request
      ├── Invalidate single-use challenge nonce (Replay defense, 120s TTL)
      └── Validate WADH cryptographic request hash
      │
      ▼
[ 5. Authoritative Recognition Engine ]
      ├── Umeyama Canonical 5-Point Affine Alignment to 112×112 RGB
      ├── ONNX Runtime Inference: SFace 2021dec (MobileFaceNet + Sigmoid Hypersphere Loss)
      └── L2 Normalization: ||v||₂ = 1.0 on S¹²⁷
      │
      ▼
[ 6. 1:N Duplicate Screening ]
      ├── Scan InMemoryBiometricIndex across all existing accounts (excluding caller UID)
      ├── If max similarity s ≥ 0.90: HARD BLOCK (HTTP 200, status: 'duplicate', isHardBlock: true)
      ├── If 0.74 ≤ s < 0.90: FLAG DUPLICATE (HTTP 200, status: 'duplicate', isHardBlock: false)
      └── If s < 0.74: UNIQUE CANDIDATE (Proceed to vault commitment)
      │
      ▼
[ 7. Biometric Vault Persistence ]
      ├── Envelope Encryption: AES-256-GCM with Cloud KMS Key Provider
      ├── Length-Prefixed Binary Canonical AAD Binding (Tenant + UID)
      ├── Admin SDK Write to `biometric_vault/{uid}` (Client direct write DENIED by rules)
      ├── Append-Only Cryptographic Hash-Chained Audit Ledger
      └── Synchronize InMemoryBiometricIndex in RAM
      │
      ▼
[ 8. Client UI State Transition ]
      ├── If unique: Refresh profile, display onboarding success, transition to HomeShell
      └── If duplicate: Display DuplicateDetectedSheet with masked ID (KLS-xK9***wXy-7890) and recovery instructions
```

### 3.2 1:1 Identity Verification Flow (Login & Shift Check-In)
```
[ 1. Mobile Camera Capture & Quality Gating ] (Same ISO 29794-5 gates)
      │
      ▼ TLS 1.3 / HTTP POST /api/biometrics/verify-1to1
[ 2. Backend Gateway ]
      ├── Authenticate Firebase ID Token
      ├── Replay defense (Single-use challenge nonce)
      └── Extract SFace 128-d probe vector p from imageBase64
      │
      ▼
[ 3. 1:1 Vault Matching ]
      ├── Fetch enrolled reference template r from `biometric_vault/{caller_uid}`
      ├── Compute Cosine Similarity s = <r, p>
      ├── Constant-Time Latency Bucketing: Padded to ≥ 300ms (Timing attack resistance)
      └── Decision Rule: If s ≥ 0.38 → APPROVED; Else → REJECTED
```

---

## 4. Forensic Evidence Matrix: Baseline Findings

| Finding ID | Source File & Line | Severity | Verified Root Cause | Implemented Correction | Status |
| :--- | :--- | :---: | :--- | :--- | :---: |
| **SEC-01** | `firestore.rules:716` | **CRITICAL** | `allow read: if isSignedIn();` allowed any authenticated client to query collection `biometric_vault`. | Sealed rule: `allow read, write: if false;`. Exclusively Admin SDK accessible. | **VERIFIED FIXED** |
| **SEC-02** | `biometric_service.dart:1060-1160` | **CRITICAL** | Mobile client systematically downloaded 500 vault records on backend error and matched locally. | Removed client-side query loop; enforced server-side routing and fail-closed retry. | **VERIFIED FIXED** |
| **ARC-01** | `face_routes.ts` vs `face_enrollment_screen.dart` | **HIGH** | Client submitted `probeVector` while server forbade client vectors via middleware (HTTP 400). | Removed `probeVector` from client POST payload; server extracts vector from `imageBase64`. | **VERIFIED FIXED** |
| **ARC-02** | `biometric_service.dart:1038` | **HIGH** | Client crossAccountCheck sent `embeddingBase64`; backend expected `imageBase64` (HTTP 400). | Updated client contract to send `imageBase64`; server performs authoritative 1:N scan. | **VERIFIED FIXED** |
| **ALG-01** | `landmark_embedding.dart` vs `face_inference.ts` | **HIGH** | Disjoint feature representations: 48-D landmark projection vs SFace CNN ($s \approx 0$). | Standardized on SFace ONNX as single source of truth; retired client geometric vector matching. | **VERIFIED FIXED** |
| **STAT-01**| `biometric_config.ts` | **MEDIUM** | 1:1 threshold ($0.38$) conflated with landmark geometry ($0.74$). | Formally decoupled 1:1 verification ($\tau = 0.38$) from 1:N deduplication ($\tau \ge 0.74$). | **VERIFIED FIXED** |
| **CRYP-01**| `kms_envelope_encryption.ts` | **HIGH** | Pipe-delimited AAD vulnerable to delimiter injection collisions. | Implemented length-prefixed binary canonical AAD serialization (Stage S8 Test 2). | **VERIFIED FIXED** |
