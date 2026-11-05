# KELASAGARA BIOMETRIC ENGINE V12.0
## Implementation Changelog

**Release:** Kelasagara Biometric Engine V12.0 Production Candidate  
**Date:** October 23, 2026  
**Auditor:** Principal Biometric Systems Architect  

---

## 1. Security Containment & Firestore Rules
- **`firestore.rules`:**
  - Modified `match /biometric_vault/{uid}` rule: changed from `allow read: if isSignedIn();` to `allow read, write: if false;`.
  - Permanently blocked direct client queries, reads, and writes to `biometric_vault`.
  - Preserved Admin SDK server-side privileged access.

---

## 2. Flutter Mobile Application (`kelasagaara_v17`)
- **`lib/services/biometric_service.dart`:**
  - **Ticket T-01:** Removed `probeVector` from `enrollBiometric` payload; image data transmitted exclusively as `imageBase64`.
  - **Fail-Closed Conversion:** Removed fallback call to `_directFirestoreEnroll` on `DioException`; returns `BiometricCheckResult.technicalFailureRetry`.
  - **Deprecation of Direct Client Vault Writes:** Removed implementation of `_directFirestoreEnroll` to eliminate client-side vault modification.
  - **Removal of Direct Client Vault Reads:** Completely excised `_db.collection('biometric_vault').limit(500).get()` from `crossAccountCheck`.
  - **API Contract Repair:** Modified `crossAccountCheck` to accept `imageBase64: imageBase64` and post `{'imageBase64': imageBase64}` to `POST /api/biometrics/cross-account-check`.
  - **Dependency Cleanup:** Removed unused `FirebaseFirestore _db` field and `cloud_firestore` import.
- **`lib/screens/auth/face_enrollment_screen.dart`:**
  - **Post-Enrollment 1:N Check:** Wired `crossAccountCheck(imageBase64: imageBase64, probeEmbedding: probeForCrossCheck)` immediately following server enrollment success.
  - **DPDPA Memory Zero-Out Preservation:** Preserved transient embedding copy for cross-check before zeroing out native C++ buffer with `fillRange(0, length, 0.0)`.
  - **Duplicate Modal Routing:** Wired `DuplicateDetectedSheet` and `_showDuplicateFaceDialog` when `isDuplicate` or `isHardBlock` is returned.
  - **Blink Latency Tuning:** Calibrated `_eyeOpen` threshold to $0.58$, `_eyeClosed` to $0.28$, and `_minOpen` to $5$ frames (37% faster blink completion).
  - **Advanced Landmark Analyzer Integration:** Wired `AdvancedLandmarkAnalyzer.createHighFidelityDetector()` to extract 133 facial reference points during enrollment.
- **`lib/biometrics/iso30107_pad_controller.dart`:**
  - Synchronized kinematic blink thresholds (`avgEyeOpen >= 0.58`, `<= 0.28`, `consecutiveOpenFrames >= 5`).
  - Added research documentation citing ISO 29794-5 OFIQ sharpness and Pech-Pacheco Laplacian kernels.
- **`lib/biometrics/advanced_landmark_analyzer.dart` (New Module):**
  - Implemented ISO 39794-5 / ISO 29794-5 quality analysis from ML Kit contours and landmarks.
  - Computes IPD, eye symmetry, yaw, pitch, roll, mouth neutrality, and EAR.
- **`lib/widgets/duplicate_detected_sheet.dart` (New Module):**
  - DPDPA-compliant bottom sheet modal rendering masked UID (`KLS-xK9***wXy-7890`), masked phone number, and Kannada/English recovery guidance.
- **`lib/widgets/face_reenroll_tile.dart` (New Module):**
  - Settings and profile re-enrollment widget wired into `lib/screens/profile/profile_screen.dart` allowing workers to update facial templates.

---

## 3. Node.js / TypeScript Biometric Backend (`backend/`)
- **`src/routes/face_routes.ts`:**
  - Installed `checkForbiddenVectorFields` middleware across `/enroll` and `/verify-1to1`.
  - Added `POST /api/biometrics/cross-account-check` endpoint executing 1:N gallery scan excluding caller's UID.
  - Added `GET /api/biometrics/db-readiness` endpoint for ISO 19795-1 system availability and RAM index monitoring.
  - Enforced constant-time response bucketing ($\ge 300\text{ ms}$) on all verification paths.
- **`src/services/biometric_matching.ts`:**
  - Added DPDPA privacy masking utilities: `maskUid` and `maskedDisplayId`.
  - Standardized cosine similarity metric on unit hypersphere $\mathbb{S}^{127}$.
- **`src/services/biometric_enrollment.ts`:**
  - Added `warmUpBiometricIndex()` for server-boot gallery preloading.
  - Enhanced duplicate rejection payload with masked display ID and integer similarity percentages.
- **`src/services/kms_envelope_encryption.ts`:**
  - Enforced length-prefixed binary canonical AAD encoding to eliminate delimiter collisions (Stage S8).
- **`src/index.ts`:**
  - Bootstrapped `warmUpBiometricIndex()` during server initialization.
