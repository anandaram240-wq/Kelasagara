# PHASE 20.5 ROLLBACK PLAN
## Deterministic Rollback Procedures to Phase 20.4 or Protected Baseline V19.2.3

**Project:** Kelasagara Major Project  
**System:** Worker Marketplace & Multi-Factor Biometric Identity Platform  
**Phase:** 20.5 (Advanced Biometric Scientific Validation Engine)  
**Parent Phase 20.4 Commit:** `41f95bf66bd09cda8ea63d3483e567b06ba6504e`  
**Protected Release Tag:** `v19.2.3-release` (`f210f95943ced619f6cd27441d9f1d89e79c08e8`)  

---

## 1. ROLLBACK TRIGGERS

A rollback must be executed if any of the following failure conditions manifest:
1. **Model Instability**: Unexpected ONNX runtime crashes or memory leaks during SFace inference.
2. **False Positive Spikes**: High-volume false duplicate alarms during worker registration.
3. **FIQA Excessive Failure**: Legitimate workers experiencing $> 20\%$ failure-to-acquire rates under normal indoor lighting.
4. **Data Corruption**: Inconsistent state in the in-memory or persisted biometric index.

---

## 2. STEP-BY-STEP ROLLBACK PROCEDURES

### Option A: Clean Rollback to Phase 20.4 (`41f95bf`)
To revert Phase 20.5 research modules while preserving Phase 20.4 device attestation validation:

```bash
cd "/Users/ananda/KELASAGARA MAJOR PROJECT/kelasagaara_v17"

# 1. Fetch current working status
git status

# 2. Checkout Phase 20.4 commit
git checkout security/phase20.4-attestation-validation
git reset --hard 41f95bf66bd09cda8ea63d3483e567b06ba6504e

# 3. Clean and rebuild backend
cd backend
npm run build
npm test

# 4. Verify clean status
git status
```

### Option B: Emergency Rollback to Protected University Release V19.2.3 (`f210f95`)
To restore the platform to the audited university submission baseline:

```bash
cd "/Users/ananda/KELASAGARA MAJOR PROJECT/kelasagaara_v17"

# 1. Checkout protected release tag
git checkout v19.2.3-release

# 2. Verify git HEAD matches commit f210f95
git rev-parse HEAD
# Expected output: f210f95943ced619f6cd27441d9f1d89e79c08e8

# 3. Verify protected release APK integrity
shasum -a 256 "/Users/ananda/KELASAGARA MAJOR PROJECT/Kelasagara-v19.2.3-release.apk"
# Expected output: 739f85746df3cd1fb6c315590147907918a3829976d0381b8eae358c743176ce

# 4. Rebuild backend on V19.2.3 baseline
cd backend
npm install
npm test
```

---

## 3. DATA AND STATE INTEGRITY DURING ROLLBACK
1. **Zero Database Modifications**: Phase 20.5 performed zero writes to production Firestore collections (`worker_profiles`, `worker_devices`, `biometric_vault`).
2. **KMS Envelope Compatibility**: All stored encrypted templates in `biometric_vault` remain completely backward-compatible.
3. **No Migration Rollback Required**: Because no schema changes were applied, rollback is instant and risk-free.
