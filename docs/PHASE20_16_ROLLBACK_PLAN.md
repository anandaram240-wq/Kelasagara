# KELASAGARA V20.16 — INFRASTRUCTURE ROLLBACK AND DISASTER RESTORATION PLAN
## Emergency Restoration Procedures to Parent Commit b111a24

**Author:** Principal DevSecOps Engineer, Site Reliability Engineer  
**Date:** 2026-11-01  
**Repository:** `kelasagaara_v17`  
**Parent Commit:** `b111a24bd0e290e5c929752e132efdba3c6a257a`  
**Target Branch:** `security/phase20.16-cloud-runtime-authorization`  
**Status:** VALIDATED PROCEDURES  

---

### 1. Purpose & Scope

This runbook defines the exact, fail-safe procedures required to revert any and all code changes introduced during Phase 20.16, returning the working tree and repository history to parent commit `b111a24` without data loss or pipeline interruption.

Because Phase 20.16 operated under strict operational restrictions (**zero cloud resources created, zero live IAM changes, zero production database writes**), rollback is purely a git working-tree and local artifact restoration. No live cloud resource teardown is required.

---

### 2. Immediate Git Restoration Protocol

To revert the local workspace completely to the Phase 20.15 baseline commit:

```bash
# 1. Navigate to the repository root
cd /Users/ananda/KELASAGARA\ MAJOR\ PROJECT/kelasagaara_v17

# 2. Verify current HEAD before restoration
git rev-parse HEAD
# Expected: Commit hash of Phase 20.16

# 3. Clean untracked and modified files
git reset --hard b111a24bd0e290e5c929752e132efdba3c6a257a
git clean -fd

# 4. Verify working tree is clean and identical to Phase 20.15
git status --short
# Expected: clean working tree (no modified or untracked Phase 20.16 files)

# 5. Verify HEAD is b111a24
git rev-parse HEAD
# Output must be: b111a24bd0e290e5c929752e132efdba3c6a257a
```

---

### 3. File Inventory Affected by Rollback

The following files created or modified in Phase 20.16 will be reverted to their Phase 20.15 state or removed:

1. **Terraform Configurations:**
   - `infra/terraform/iam_bindings.tf` (reverted to restore redundant `publicKeyViewer` resources if needed)

2. **Backend Application Services:**
   - `backend/src/services/cloud_runtime_identity_verifier_v16.ts` (removed)
   - `backend/src/services/terraform_plan_policy_v16.ts` (removed)
   - `backend/src/services/firestore_database_authorization_v16.ts` (removed)
   - `backend/src/tests/phase20_16_cloud_runtime_authorization.test.ts` (removed)

3. **Documentation:**
   - All 13 files matching `docs/PHASE20_16_*.md` (removed)

---

### 4. Post-Rollback Integrity Verification

Following a rollback to `b111a24`, execute the standard regression checklist:

1. **Verify Protected Artifact Hashes:**
   ```bash
   git rev-parse v19.2.3-release
   # Expected: 8634a1813c84fccc73b8944803b6bd541f5e2326

   shasum -a 256 build/app/outputs/flutter-apk/app-release.apk
   # Expected: 739f85746df3cd1fb6c315590147907918a3829976d0381b8eae358c743176ce

   shasum -a 256 backend/models/face_recognition_sface_2021dec.onnx
   # Expected: 0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79

   shasum -a 256 backend/models/face_detection_yunet_2023mar.onnx
   # Expected: 8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4
   ```

2. **Rebuild Backend & Run Test Suite:**
   ```bash
   cd backend
   npm run build
   npm test
   # Expected: All Phase 20.15 tests pass (1,062 passing tests).
   ```

3. **Run Flutter Tests:**
   ```bash
   cd ..
   flutter test test/biometric_v10_phase10_flutter_test.dart test/profile_biometric_isolation_test.dart
   # Expected: All 12 tests pass.
   ```

---

### 5. Conclusion

Because no live infrastructure was modified or provisioned in cloud environments, rolling back Phase 20.16 is immediate, zero-downtime, and completely safe.
