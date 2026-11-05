# PHASE 20.4 ROLLBACK PLAN
## Deterministic Rollback Procedures to Phase 20.3 or Protected Release V19.2.3

**Project:** Kelasagara Major Project  
**System:** Worker Marketplace & Multi-Factor Biometric Identity Platform  
**Target Release:** Phase 20.4 (Independent Device Attestation & Trust-Chain Validation Engine)  
**Parent Phase 20.3 Commit:** `6f8a0c91e509d26ce7fab26bfe554cc902cc599f`  
**Protected Release Tag:** `v19.2.3-release` (`f210f95943ced619f6cd27441d9f1d89e79c08e8`)  

---

## 1. ROLLBACK TRIGGERS

A rollback must be initiated if any of the following critical failure conditions emerge:
1. **Google Root Incompatibility**: Valid enrolled devices fail attestation validation due to unseen intermediate certificate authorities.
2. **Revocation Service Outage**: Google attestation status endpoint remains unreachable past the fail-closed grace period, preventing legitimate worker registrations.
3. **Severe Device Latency**: Device registration verification exceeds acceptable operational thresholds (> 500ms).
4. **Data Corruption**: Corrupted device records in Firestore `worker_devices` collection.

---

## 2. PROCEDURES FOR IMMEDIATE ROLLBACK

### Option A: Clean Rollback to Phase 20.3 (`6f8a0c91`)
To revert the attestation verifier and revocation service changes while keeping V20.3 device-bound trust operational:

```bash
cd "/Users/ananda/KELASAGARA MAJOR PROJECT/kelasagaara_v17"

# 1. Fetch current status
git status

# 2. Checkout Phase 20.3 commit or branch
git checkout security/phase20.3-device-bound-trust
git reset --hard 6f8a0c91e509d26ce7fab26bfe554cc902cc599f

# 3. Clean and re-build backend
cd backend
npm run build
npm test

# 4. Verify clean status
git status
```

### Option B: Complete Emergency Rollback to Protected Release V19.2.3 (`f210f95`)
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

## 3. DATA RECOVERY AND ROLLBACK VERIFICATION
1. **Firestore Collections**: Device registrations created in Phase 20.4 reside in the `worker_devices` collection with schema version `20.4`. In the event of rollback, existing biometric templates in `biometric_vault` are completely untouched and unaffected.
2. **Zero Plaintext Integrity**: Envelope encryption keys in Google Cloud KMS remain fully backward-compatible.
3. **No Migration Needed**: Rollback requires zero database migration scripts or schema alterations.
