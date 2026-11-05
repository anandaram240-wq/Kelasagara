# PHASE 20.7 BASELINE PRESERVATION
## Verification of Git Baseline, Commit Ancestry, Model Hashes, and Protected Release V19.2.3

**Project:** Kelasagara Major Project  
**System:** Multi-Factor Biometric Identity and Authentication Platform  
**Phase:** 20.7 (Controlled Physical Biometric Validation & PAD Hardening)  
**Working Branch:** `research/phase20.7-physical-biometric-validation`  
**Parent Commit:** `28c5a25` (Phase 20.6 Biometric Evidence Integrity & Controlled Pilot Readiness)  
**Grandparent Commit:** `4d1d2b4` (Phase 20.5 Advanced Biometric Scientific Validation Engine)  
**Protected Release Tag:** `v19.2.3-release` (`f210f95943ced619f6cd27441d9f1d89e79c08e8`)  
**Protected Release Binary:** `/Users/ananda/KELASAGARA MAJOR PROJECT/Kelasagara-v19.2.3-release.apk`  
**Protected APK SHA-256:** `739f85746df3cd1fb6c315590147907918a3829976d0381b8eae358c743176ce`  
**Physical Acceptance Gate:** **BLOCKED** (0 physical devices attached via ADB)  

---

## 1. BASELINE REPOSITORY FORENSICS

Prior to any modifications in Phase 20.7, git status, commit ancestry, and cryptographic digests were independently verified:

```
[Git Commit Ancestry Hierarchy]
* 28c5a25 (research/phase20.6-evidence-integrity)
|   feat(v20.6): biometric evidence integrity & controlled pilot readiness
* 4d1d2b4 (research/phase20.5-biometric-validation)
|   feat(v20.5): advanced biometric scientific validation engine
* 41f95bf (security/phase20.4-attestation-validation)
|   feat(v20.4): independent device attestation & trust-chain validation engine
* 6f8a0c9 (security/phase20.3-device-bound-trust)
|   feat(v20.3): device-bound trust & authentication engine with Android Keystore ECDSA P-256
* f09cfc5 (security/phase20.2-play-integrity)
|   feat(v20.2): trusted Android application integrity engine with Google Play Standard Integrity API
* 457bdb5 (security/phase20.1-biometric-vault-encryption)
|   feat(v20.1): zero-plaintext biometric vault with AES-256-GCM envelope encryption
* 4892bb6 (tag: v19.2.3-docs)
|   docs: v19.2.3 release documentation freeze
* f210f95 (tag: v19.2.3-release)
    release: v19.2.3 final android submission release
```

### Forensic Verification Findings:
1. **Parent Commit Preservation:** Working branch `research/phase20.7-physical-biometric-validation` branches cleanly from commit `28c5a25` (Phase 20.6).
2. **Release Tag Preservation:** Tag `v19.2.3-release` points to commit `f210f95943ced619f6cd27441d9f1d89e79c08e8`. The tag object (`8634a1813c84fccc73b8944803b6bd541f5e2326`) is intact and unmodified.
3. **Protected Release Binary:** Standalone binary `Kelasagara-v19.2.3-release.apk` exhibits exact SHA-256 `739f85746df3cd1fb6c315590147907918a3829976d0381b8eae358c743176ce`. It remains the immutable baseline and rollback anchor.

---

## 2. NEURAL MODEL INTEGRITY VERIFICATION

Cryptographic SHA-256 hashes of the production ONNX neural models in `backend/models/`:

| Model File | Target Architecture | SHA-256 Digest | Status |
| :--- | :--- | :--- | :--- |
| `face_recognition_sface_2021dec.onnx` | SFace 128-D Unit Feature Extractor | `0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79` | **VERIFIED INTACT** |
| `face_detection_yunet_2023mar.onnx` | YuNet 5-Point Landmark Face Detector | `8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4` | **VERIFIED INTACT** |

---

## 3. HISTORICAL TEST SUITE BASELINE EXECUTION

The existing baseline test suites were executed before creating any Phase 20.7 modifications:
1. **Backend Tests:** `npm test` executed across 157 suites:
   - 753 tests passed, 0 failures, 0 skipped.
2. **Flutter Biometric Tests:** `flutter test test/biometric*`:
   - 110 tests passed (100%).
3. **Flutter Play Integrity Tests:** `flutter test test/play_integrity*`:
   - 3 tests passed (100%).
4. **Android Native Compilation:** `./gradlew compileDebugKotlin` in `android/`:
   - BUILD SUCCESSFUL in 4 seconds (262 actionable tasks).

The baseline system is stable, deterministic, and fully preserved.
