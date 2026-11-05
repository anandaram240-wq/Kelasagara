# KELASAGARA V20.9: ROLLBACK PLAN
## Procedures for Clean Reversion to Phase 20.8 Commit 32b928b

**Document Ref:** `docs/PHASE20_9_ROLLBACK_PLAN.md`  
**Phase:** 20.9  
**Auditor:** Principal Cryptography & Release Operations Engineer  
**Date:** November 1, 2026

---

### 1. Rollback Trigger Conditions

A rollback to Phase 20.8 (`32b928b`) is mandated if any of the following occur:
1. `Yuv420PlaneReader.kt` causes Kotlin compilation failure or runtime crash in native Android camera pipelines.
2. `CameraCaptureIntegrity.ts` produces non-deterministic SHA-256 frame hashes on identical inputs.
3. Any of the 791 existing backend regression tests fail.
4. Protected APK `Kelasagara-v19.2.3-release.apk` hash deviates from `739f85746df3cd1fb6c315590147907918a3829976d0381b8eae358c743176ce`.

---

### 2. Step-by-Step Rollback Execution

If rollback is triggered, execute the following commands from repository root:

```bash
# 1. Ensure working directory is clean
cd "/Users/ananda/KELASAGARA MAJOR PROJECT/kelasagaara_v17"

# 2. Hard reset to Phase 20.8 commit
git reset --hard 32b928b4b6480e27cf03d07981cde852559941b4

# 3. Clean untracked build artifacts
cd backend && npm run build
npm test

# 4. Verify compilation on clean working tree
cd ../android && ./gradlew compileDebugKotlin
```

---

### 3. Verification Post-Rollback

- Verify git commit: `git rev-parse HEAD` returns `32b928b4b6480e27cf03d07981cde852559941b4`.
- Verify backend test count: 791 tests passing.
- Verify Flutter tests: 113 tests passing.
