# PHASE 20.7: MULTI-TIER DETERMINISTIC ROLLBACK PLAN
**System:** Kelasagara Biometric Identity & Authentication Platform  
**Phase:** 20.7 (Controlled Physical Biometric Validation & PAD Hardening)  
**Parent Release:** V19.2.3 (`f210f95`)  
**Parent Phase:** Phase 20.6 (`28c5a25`)  
**Lead Architect:** Principal Biometric Security Architect & Site Reliability Engineer  
**Date:** November 2026  
**Status:** VALIDATED & READY FOR DEPLOYMENT EMERGENCIES

---

## 1. Overview & Rollback Principles

In a high-assurance identity and financial transaction platform, any change—including research models and security hardening—must provide a verified, deterministic rollback path.

### Core Rollback Guarantees:
1. **Zero Database Schema Drift:** Phase 20.7 introduces zero destructive schema modifications or breaking changes to Firestore or Cloud KMS structures.
2. **Deterministic Target Commits:** Every rollback target is pinned to an immutable git commit hash and protected release tag.
3. **Continuous Data Integrity:** Reverting code changes does not affect active worker accounts or encrypted biometric vault templates.

---

## 2. Multi-Tier Rollback Targets

```
+--------------------------------------------------------------------------------------------------+
| LEVEL 1: IMMEDIATE ROLLBACK TO PHASE 20.6 (Commit 28c5a25)                                       |
|  - Removes candidate PAD hardening modules                                                       |
|  - Restores pure Phase 20.6 evidence integrity baseline                                          |
|  - Verification: npm test (765 tests pass)                                                       |
+--------------------------------------------------------------------------------------------------+
                                                 |
                                                 v
+--------------------------------------------------------------------------------------------------+
| LEVEL 2: ROLLBACK TO PHASE 20.5 SCIENTIFIC VALIDATION (Commit 4d1d2b4)                           |
|  - Reverts Phase 20.6 evidence audit harnesses                                                   |
|  - Restores Phase 20.5 scientific benchmark suite                                                |
|  - Verification: npm test (753 tests pass)                                                       |
+--------------------------------------------------------------------------------------------------+
                                                 |
                                                 v
+--------------------------------------------------------------------------------------------------+
| LEVEL 3: EMERGENCY RECOVERY TO V19.2.3 PRODUCTION RELEASE (Commit f210f95)                       |
|  - Hard reset to the immutable production release tag `v19.2.3-release`                          |
|  - Binary SHA-256: 739f85746df3cd1fb6c315590147907918a3829976d0381b8eae358c743176ce             |
|  - Full legacy operational baseline preserved                                                    |
+--------------------------------------------------------------------------------------------------+
```

---

## 3. Step-by-Step Execution Procedures

### 3.1. Level 1: Rollback to Phase 20.6 (`28c5a25`)
If the candidate PAD hardening engine causes unexpected unit test conflicts or compiler anomalies:
```bash
# 1. Stash or clean working directory
git reset --hard 28c5a25

# 2. Verify git HEAD
git rev-parse HEAD
# Output must be: 28c5a25039f3d1bcf5c50c18d407ffaa8705f4c5

# 3. Clean and rebuild backend
cd backend
rm -rf dist
npm run build
npm test

# 4. Verify Flutter client
cd ..
flutter test test/biometric*
```

---

### 3.2. Level 2: Rollback to Phase 20.5 (`4d1d2b4`)
```bash
# 1. Reset working branch to Phase 20.5 commit
git reset --hard 4d1d2b4

# 2. Verify git HEAD
git rev-parse HEAD
# Output must be: 4d1d2b4...

# 3. Rebuild and test backend
cd backend && npm run build && npm test
```

---

### 3.3. Level 3: Emergency Recovery to V19.2.3 (`f210f95`)
In the event of an unrecoverable catastrophic corruption across security modules:
```bash
# 1. Checkout protected production release tag
git checkout -f tags/v19.2.3-release

# 2. Verify protected APK hash
shasum -a 256 ../Kelasagara-v19.2.3-release.apk
# Must output: 739f85746df3cd1fb6c315590147907918a3829976d0381b8eae358c743176ce

# 3. Verify ONNX model hashes
shasum -a 256 backend/models/face_recognition_sface_2021dec.onnx
# Must output: 0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79

shasum -a 256 backend/models/face_detection_yunet_2023mar.onnx
# Must output: 8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4

# 4. Rebuild legacy backend
cd backend
npm install
npm run build
npm test
```

---

## 4. Post-Rollback Verification Checklist

Following any rollback execution, the following verification checklist must be completed by the Lead Architect before returning to service:
- [ ] Working tree clean (`git status` reports nothing to commit).
- [ ] Backend test suite passes 100% of applicable tests for the target commit.
- [ ] Mobile client Flutter test suite passes 100% of tests.
- [ ] Android Gradle builds clean (`./gradlew compileDebugKotlin`).
- [ ] Firestore rules emulator verifies zero permission leaks.
- [ ] Cloud KMS connectivity and encryption key access verified.
