# PHASE 20.13: ROLLBACK PLAN & EMERGENCY RESTORATION PROTOCOL
## Rapid Recovery Procedures and State Invariants for Phase 20.13

**Date:** November 2026  
**System:** Kelasagara Biometric Identity Service  
**Target Baseline Commit:** `2a8472790f47ac5096baf88a5b1f870bd73b3029` (Phase 20.12 HEAD)  
**Active Branch:** `security/phase20.13-privileged-backend-security`  
**Classification:** OPERATIONAL_SAFETY_VERIFIED  

---

### 1. Zero Production Impact Invariant

Phase 20.13 was executed under strict non-negotiable restrictions:
- No Cloud Run services, Cloud Functions, or App Engine services were deployed.
- No live Firebase database records, collections, or security rules were migrated or written.
- No Google Cloud IAM policies or Service Account keys were created or altered.
- All testing was conducted hermetically using Node.js internal test harnesses and mock providers.

Consequently, **no live production state was altered**, making rollback trivial and risk-free.

---

### 2. Git Level Rollback Procedure

If it becomes necessary to discard Phase 20.13 changes and return to the Phase 20.12 baseline commit `2a8472790f47ac5096baf88a5b1f870bd73b3029`:

#### Step 1: Check Working Tree & Switch Branch
```bash
cd /Users/ananda/KELASAGARA\ MAJOR\ PROJECT/kelasagaara_v17

# Check status
git status

# Revert to Phase 20.12 branch
git checkout security/phase20.12-biometric-trust-provenance
```

#### Step 2: Verify Baseline Ancestry
```bash
git rev-parse HEAD
# Must output: 2a8472790f47ac5096baf88a5b1f870bd73b3029
```

#### Step 3: Verify Integrity of Protected Release Artifacts
```bash
# Check protected release tag
git rev-parse v19.2.3-release
# Output: 8634a1813c84fccc73b8944803b6bd541f5e2326

# Check hashes
shasum -a 256 build/app/outputs/flutter-apk/app-release.apk
# Output: 739f85746df3cd1fb6c315590147907918a3829976d0381b8eae358c743176ce

shasum -a 256 backend/models/face_recognition_sface_2021dec.onnx
# Output: 0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79

shasum -a 256 backend/models/face_detection_yunet_2023mar.onnx
# Output: 8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4
```

---

### 3. Build & Test Baseline Verification

After restoring the working directory to Phase 20.12:
```bash
cd backend
npm run build
npm test
# Expected: 947 tests pass across 205 suites with 0 failures
```

---

### 4. Rollback Signoff Criteria

Rollback is certified complete when:
1. HEAD matches `2a8472790f47ac5096baf88a5b1f870bd73b3029`.
2. All 4 protected artifact checksums are verified identical.
3. 947 backend tests pass without errors.
4. No orphan background tasks or uncommitted temporary files remain.
