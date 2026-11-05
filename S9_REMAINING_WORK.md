# KELASAGARA BIOMATCH — STAGE S9.5 REMAINING ENGINEERING & GOVERNANCE WORK
**Document ID:** `S9_REMAINING_WORK.md`  
**Classification:** Outstanding Engineering Backlog & Deployment Roadmap  
**Evaluation Date:** October 11, 2026 (UTC: 2026-10-11T05:18:30Z)  
**Git Commit:** `6a2a1482fe90d41050fc61ac83cc8777291a4a06` (tag: `s8-final`)  

---

## 1. TECHNICAL INTEGRATION BACKLOG

The following technical tasks remain to bridge local hermetic verification and live production deployment:

### ENG-01: Live Google Cloud KMS Staging Probe
- **Target Component:** `backend/src/services/kms_key_provider.ts` (`CloudKmsKeyProvider`)
- **Action Required:**
  1. Deploy staging service account key to staging CI secrets or configure Workload Identity Federation on Cloud Run.
  2. Run `dist/tools/kms_live_probe.js` to execute live wrap/unwrap against `projects/kelasagara-f127a/locations/asia-south1/keyRings/biomatch-ring/cryptoKeys/template-kek`.
  3. Validate audit logs in Google Cloud Logging to confirm zero plaintext DEK leakage.
- **Estimated Effort:** 4 engineering hours.

### ENG-02: Live Google Play Integrity Staging Attestation
- **Target Component:** `backend/src/services/device_attestation.ts` (`GooglePlayIntegrityVerifier`)
- **Action Required:**
  1. Link Google Play Console project `321306352055` to Google Cloud Project `kelasagara-f127a`.
  2. Grant service account `play-integrity-backend@kelasagara-f127a.iam.gserviceaccount.com` read permissions.
  3. Generate staging release APK, install on physical Android test devices, and verify decrypted token claims end-to-end.
- **Estimated Effort:** 8 engineering hours.

### ENG-03: Staging Batch Data Migration Drill
- **Target Component:** `backend/src/services/template_migration.ts`
- **Action Required:**
  1. Create a staging clone of Firestore collection `users/*/biometricVault/*`.
  2. Execute `TemplateMigrationService.migrateBatch()` with `dryRun: true` and verify summary report.
  3. Execute live migration with bounded concurrency (batch size 50, lease TTL 60s).
  4. Perform post-migration verification drill verifying 100% vector fidelity across all records.
- **Estimated Effort:** 6 engineering hours.

---

## 2. GOVERNANCE & EXTERNAL ASSURANCE ROADMAP

| Phase | Governance Milestone | Estimated Duration | Required Sign-Off |
| :---: | :--- | :---: | :--- |
| **Phase 1** | Institutional Ethics Review (IRB protocol submission) | 3–4 weeks | Ethics Review Board |
| **Phase 2** | Consented Karnataka Field Trial (1,000 workers across 5 districts) | 4–6 weeks | Lead Biometrician / Field Ops |
| **Phase 3** | Independent Black-Box Mobile Penetration Testing | 2 weeks | External Security Auditor |
| **Phase 4** | DPDPA 2023 Privacy Compliance & Worker Rights Legal Review | 2 weeks | Corporate Legal Counsel |
| **Phase 5** | Executive Deployment Authorization | 1 day | Product Sponsor & CISO |

---
*Report generated and validated under Stage S9.5 Operating Contract.*
