# KELASAGARA V20.3: ROLLBACK & DISASTER RECOVERY PLAN
## Safe Rollback Procedures & Protected Release Restoration

**Project:** Kelasagara Major Project  
**System:** Worker Marketplace & Multi-Factor Biometric Identity Platform  
**Document Code:** KS-SEC-P20.3-15  
**Classification:** Incident Response & Operational Safety Specification

---

## 1. PURPOSE & PROTECTION PRINCIPLES

This rollback document establishes verified, step-by-step instructions to return the Kelasagara repository and deployment infrastructure to prior certified release states in the event of an unforeseen hardware incompatibility or operational anomaly.

### Protected Releases & Checksums:
- **Protected University Submission Release:** V19.2.3
  - Release Tag: `v19.2.3-release`
  - Release Commit: `f210f95943ced619f6cd27441d9f1d89e79c08e8`
  - Protected APK Path: `/Users/ananda/KELASAGARA MAJOR PROJECT/Kelasagara-v19.2.3-release.apk`
  - Protected APK SHA-256: `739f85746df3cd1fb6c315590147907918a3829976d0381b8eae358c743176ce`
- **Protected Phase 20.2 Working Baseline:**
  - Commit: `f09cfc5d02cc933ef751dfc6983573b9e45966bb`
  - Branch: `security/phase20.2-play-integrity`
- **Current Phase 20.3 Working Branch:**
  - Branch: `security/phase20.3-device-bound-trust`

---

## 2. EMERGENCY ROLLBACK TO PHASE 20.2 (PLAY INTEGRITY ONLY)

If the Android Keystore hardware key attestation or device signature protocol requires deactivation while retaining Google Play Integrity:

```bash
# 1. Navigate to workspace
cd "/Users/ananda/KELASAGARA MAJOR PROJECT/kelasagaara_v17"

# 2. Checkout previous certified V20.2 commit
git checkout security/phase20.2-play-integrity

# 3. Rebuild backend
cd backend
npm run build
npm test

# 4. Restart backend server
pm2 restart kelasagara-backend || (kill $(lsof -t -i :5001) && npm start)
```

---

## 3. FULL ROLLBACK TO PROTECTED V19.2.3 (SUBMISSION BASELINE)

If complete rollback to the university submission release candidate is mandated:

```bash
# 1. Navigate to workspace
cd "/Users/ananda/KELASAGARA MAJOR PROJECT/kelasagaara_v17"

# 2. Hard reset to protected release tag
git checkout v19.2.3-release

# 3. Verify APK integrity
shasum -a 256 "/Users/ananda/KELASAGARA MAJOR PROJECT/Kelasagara-v19.2.3-release.apk"
# Expected output: 739f85746df3cd1fb6c315590147907918a3829976d0381b8eae358c743176ce

# 4. Verify clean build and test status
cd backend
npm test
cd ..
flutter test test/biometric*
```

---

## 4. DATABASE & REPOSITORY ROLLBACK IMPACT

1. **Zero Production Migration Risk:**
   Phase 20.3 did not execute any production Firestore database migrations or destructive batch scripts.
2. **Collection Isolation:**
   Device registration records reside in the isolated `/biometric_devices` collection. In the event of a rollback, existing records in `/biometric_vault` (Phase 20.1) and `/workers` remain completely unaffected and backward-compatible.
3. **No Tunnel Exposure:**
   All public tunnels remain inactive. Direct Anycast and local loopback connections ensure no lingering network ingress points.
