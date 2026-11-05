# KELASAGARA V15.0: STAGING VERIFICATION RUNBOOK (FIRESTORE & CLOUD KMS)

**Project:** Kelasagara Worker Marketplace Biometric Subsystem  
**Date:** October 23, 2026  
**Auditor:** Principal Cloud Security Architect & DevOps Verification Engineer  
**Classification:** CONTROLLED TEST BUILD ONLY — PRE-DEPLOYMENT RUNBOOK  
**Target Environments:** Staging (`kelasagara-staging` / `asia-south1`) ONLY  

---

## 1. Executive Summary

This runbook establishes deterministic, verifiable procedures for validating Cloud Firestore security rules and Google Cloud KMS envelope encryption in an isolated staging environment. 

In accordance with V15 Non-Negotiable Rules, **no changes to production Firestore rules, IAM policies, or Cloud KMS keys were executed during this audit**. The current production deployment status remains formally documented as:
- **Deployed Firestore Biometric Vault Client-Block:** **NOT VERIFIED LIVE** (Verified in local source repository and emulator tests).
- **Live Google Cloud KMS Envelope Encryption:** **NOT VERIFIED LIVE** (Verified locally via `LocalDevKeyProvider`).

Execution of this runbook is a mandatory prerequisite before any staging canary release.

---

## 2. Work Package A: Cloud Firestore Staging Verification

### A. Pre-Deployment Configuration & Integrity Check
1. **Target Project:** `kelasagara-staging` (Verify via `firebase projects:list`).
2. **Authorized Role:** Operator must hold `roles/firebaserules.admin` or `roles/editor` on the staging project.
3. **Rules Diff Verification:**
   Execute local diff check to confirm `biometric_vault` denial:
   ```bash
   git diff HEAD~1..HEAD firestore.rules
   ```
   Confirm lines 718–720 contain the fail-closed client block:
   ```rules
   match /biometric_vault/{uid} {
     allow read, write: if false;
   }
   ```

### B. Hermetic Emulator Verification
Prior to cloud deployment, execute the security suite inside the Firebase Firestore Emulator:
```bash
cd "/Users/ananda/KELASAGARA MAJOR PROJECT/kelasagaara_v17"
firebase emulators:exec --only firestore "npm test --prefix backend"
```
**Acceptance Gate:** All 148 backend tests must pass with zero Firestore permission violations.

### C. Staging Deployment Execution
Deploy the verified rules to the staging project exclusively:
```bash
firebase deploy --only firestore:rules --project kelasagara-staging
```

### D. Post-Deployment Live Verification Protocol
1. **Live Rules Snapshot:**
   Retrieve and verify the active rule set directly from the Firebase Management API:
   ```bash
   firebase firestore:rules:get --project kelasagara-staging > /tmp/deployed_staging_rules.txt
   grep -A 3 "biometric_vault" /tmp/deployed_staging_rules.txt
   ```
2. **Adversarial Client Read Test (Penetration Verification):**
   Execute a client probe using an authenticated worker JWT token attempting to read `/biometric_vault/{targetUid}`:
   ```bash
   curl -s -X GET \
     "https://firestore.googleapis.com/v1/projects/kelasagara-staging/databases/(default)/documents/biometric_vault/target_user_uid" \
     -H "Authorization: Bearer $WORKER_ID_TOKEN"
   ```
   **Expected Response:** HTTP `403 Forbidden` (`PERMISSION_DENIED: Cloud Firestore Security Rules denied request`).
3. **Trusted Backend Write Test:**
   Execute a test enrollment via the standalone backend Admin SDK.
   **Expected Response:** HTTP `200 OK`. The Admin SDK successfully writes the encrypted template to `/biometric_vault`.

---

## 3. Work Package B: Google Cloud KMS Staging Verification

### A. IAM & Service Account Architecture
To eliminate long-lived service account JSON keys on disk, the Cloud Run backend service in staging must use Google Cloud Application Default Credentials (ADC) via its attached service identity.

1. **Service Identity:** `biomatch-staging-sa@kelasagara-staging.iam.gserviceaccount.com`
2. **Cloud KMS Key Resource:**
   ```
   projects/kelasagara-staging/locations/asia-south1/keyRings/biomatch-staging-ring/cryptoKeys/template-kek-v1
   ```
3. **Least Privilege IAM Grant:**
   ```bash
   gcloud kms keys add-iam-policy-binding template-kek-v1 \
     --project kelasagara-staging \
     --location asia-south1 \
     --keyring biomatch-staging-ring \
     --member "serviceAccount:biomatch-staging-sa@kelasagara-staging.iam.gserviceaccount.com" \
     --role "roles/cloudkms.cryptoKeyEncrypterDecrypter"
   ```

### B. Staging Integration Test Suite Execution
Set staging environment variables and execute the cryptographic test harness:
```bash
export NODE_ENV="staging"
export GCP_PROJECT_ID="kelasagara-staging"
export KMS_LOCATION="asia-south1"
export KMS_KEY_RING="biomatch-staging-ring"
export KMS_KEY_ID="template-kek-v1"
export GOOGLE_APPLICATION_CREDENTIALS="/tmp/staging-test-adc.json"

cd "/Users/ananda/KELASAGARA MAJOR PROJECT/kelasagaara_v17/backend"
npm run build
node --test dist/tests/aad_canonicalization.test.js
```

### C. Six Mandatory Staging Cryptographic Gates
Each of the following 6 test gates must be demonstrated with live Cloud KMS calls:

| Gate | Test Objective | Procedure | Acceptance Criteria |
|:---:|:---|:---|:---|
| **Gate 1** | **DEK Wrapping** | Call `wrapDek(raw256BitKey, canonicalAad)` via Cloud KMS | Returns 60-byte envelope with valid `keyVersion` |
| **Gate 2** | **DEK Unwrapping** | Call `unwrapDek(wrappedDek, canonicalAad)` | Returns exact original 32-byte key |
| **Gate 3** | **Context Tampering (AAD)** | Attempt unwrapping with altered UID: `v3_kms_gcm\|staging\|different_uid\|k1` | KMS rejects operation with `FAILED_PRECONDITION` or `INVALID_ARGUMENT` |
| **Gate 4** | **Key Rotation** | Rotate key to `template-kek-v1` version 2; unwrap ciphertext encrypted under version 1 | Seamless decryption succeeds without key re-encryption |
| **Gate 5** | **IAM Revocation** | Temporarily revoke `cryptoKeyEncrypterDecrypter` from test identity | Cloud KMS call immediately fails with `PERMISSION_DENIED` |
| **Gate 6** | **Zero Secret Log Leakage** | Scan backend stdout/stderr logs during 1,000 wrapping/unwrapping operations | Zero instances of plaintext DEKs, raw vectors, or KMS tokens in logs |

---

## 4. Rollback and Recovery Runbook

If any staging verification check fails:
1. **Firestore Rules Rollback:**
   ```bash
   firebase firestore:rules:release /tmp/previous_stable_rules.txt --project kelasagara-staging
   ```
2. **Backend Service Reversion:**
   ```bash
   gcloud run services update-traffic kelasagara-biomatch-backend \
     --project kelasagara-staging \
     --to-revisions PREVIOUS_STABLE_REVISION=100
   ```
3. **Incident Escalation:** File immediate blocker report in `reports/` and freeze all promotion pipelines.
