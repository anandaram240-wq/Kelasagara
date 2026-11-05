# PHASE 20.8: MULTI-TIER DETERMINISTIC ROLLBACK PLAN
**System:** Kelasagara Biometric Identity & Authentication Platform  
**Phase:** 20.8 (PAD Signal Extraction and Optical Evidence Engine)  
**Parent Release:** V19.2.3 (`f210f95`)  
**Parent Phase:** Phase 20.7 (`ed141af`)  
**Lead SRE & Cryptography Architect:** Site Reliability Engineering Lead  
**Date:** November 2026  
**Status:** VALIDATED & READY FOR DEPLOYMENT EMERGENCIES

---

## 1. Overview & Non-Destructive Invariants

Phase 20.8 introduces zero production database migrations, zero Firestore rule alterations, and zero breaking API changes. The `OpticalDisplayFeatureExtractor` and redesigned `CandidatePadHardenedEngine` are strictly non-disruptive modules.

In the event of an operational anomaly or integration conflict, the platform can be deterministically rolled back to prior validated baselines.

---

## 2. Multi-Tier Rollback Targets

```
+--------------------------------------------------------------------------------------------------+
| LEVEL 1: IMMEDIATE ROLLBACK TO PHASE 20.7 (Commit ed141af)                                       |
|  - Reverts Phase 20.8 optical extractor & fusion modules                                         |
|  - Restores Phase 20.7 candidate PAD baseline                                                    |
|  - Verification: npm test (771 tests pass)                                                       |
+--------------------------------------------------------------------------------------------------+
                                                 |
                                                 v
+--------------------------------------------------------------------------------------------------+
| LEVEL 2: ROLLBACK TO PHASE 20.6 (Commit 28c5a25)                                                 |
|  - Restores Phase 20.6 evidence integrity baseline                                               |
|  - Verification: npm test (765 tests pass)                                                       |
+--------------------------------------------------------------------------------------------------+
                                                 |
                                                 v
+--------------------------------------------------------------------------------------------------+
| LEVEL 3: EMERGENCY RECOVERY TO V19.2.3 PRODUCTION RELEASE (Commit f210f95)                       |
|  - Hard reset to the immutable production release tag `v19.2.3-release`                          |
|  - Binary SHA-256: 739f85746df3cd1fb6c315590147907918a3829976d0381b8eae358c743176ce             |
|  - Complete legacy operational baseline preserved                                                |
+--------------------------------------------------------------------------------------------------+
```

---

## 3. Step-by-Step Rollback Execution

### 3.1. Level 1: Rollback to Phase 20.7 (`ed141af`)
```bash
# 1. Stash and hard reset working tree to Phase 20.7 commit
cd kelasagaara_v17
git reset --hard ed141af

# 2. Verify commit hash
git rev-parse HEAD
# Output must be: ed141af...

# 3. Rebuild and test backend
cd backend
rm -rf dist
npm run build
npm test

# 4. Verify Flutter client
cd ..
flutter test test/biometric*
```

---

### 3.2. Level 2: Rollback to Phase 20.6 (`28c5a25`)
```bash
cd kelasagaara_v17
git reset --hard 28c5a25
cd backend && npm run build && npm test
```

---

### 3.3. Level 3: Emergency Recovery to V19.2.3 (`f210f95`)
```bash
cd kelasagaara_v17
git checkout -f tags/v19.2.3-release

# Verify protected APK checksum
shasum -a 256 ../Kelasagara-v19.2.3-release.apk
# Must output: 739f85746df3cd1fb6c315590147907918a3829976d0381b8eae358c743176ce

# Verify ONNX model checksums
shasum -a 256 backend/models/face_recognition_sface_2021dec.onnx
# Must output: 0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79

shasum -a 256 backend/models/face_detection_yunet_2023mar.onnx
# Must output: 8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4

cd backend
npm install && npm run build && npm test
```

---

## 4. Post-Rollback Verification Checklist

- [ ] `git status` reports working tree clean.
- [ ] Backend test suite passes 100% of applicable tests.
- [ ] Flutter biometric tests pass 100% of tests.
- [ ] Native Android Gradle builds successfully (`compileDebugKotlin`).
- [ ] Protected release APK SHA-256 verified identical.
