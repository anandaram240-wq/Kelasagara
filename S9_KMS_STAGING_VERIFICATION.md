# KELASAGARA BIOMATCH — STAGE S9.5 CLOUD KMS STAGING VERIFICATION REPORT
**Document ID:** `S9_KMS_STAGING_VERIFICATION.md`  
**Classification:** Staging Environment Integration & External Dependency Audit  
**Evaluation Date:** October 11, 2026 (UTC: 2026-10-11T05:09:45Z)  
**Status Verdict:** `EXTERNALLY_BLOCKED` (Local Implementation Verified Hermetically)  
**Evidence Artifacts:** `evidence/s9/kms_unit_tests.json`, `evidence/s9/kms_live_results.json`  

---

## 1. STAGING EXECUTION ENVIRONMENT AUDIT

During Stage S9.5 execution, the environment was inspected for live Google Cloud Platform credentials:
- **`GOOGLE_APPLICATION_CREDENTIALS`:** `UNSET` (Null)
- **`GCP_PROJECT_ID`:** Defaults to `kelasagara-f127a`
- **Network Egress to `cloudkms.googleapis.com`:** Not reachable in sandboxed test environment
- **Configured Target Key:** `projects/kelasagara-f127a/locations/asia-south1/keyRings/biomatch-ring/cryptoKeys/template-kek`

### 1.1 Live Invocation Probe Results
An explicit probe of `CloudKmsKeyProvider.wrapDek()` and `CloudKmsKeyProvider.unwrapDek()` was conducted within the test runner (`aad_canonicalization.test.ts` TEST 9):
```typescript
const provider = new CloudKmsKeyProvider();
await assert.rejects(
  provider.wrapDek(dek, aad),
  /KMS_UNAVAILABLE_ERROR \(UNVERIFIED-LIVE\)/
);
```
- **Observed Result:** System caught the unconfigured credential state and immediately threw `KMS_UNAVAILABLE_ERROR (UNVERIFIED-LIVE)`.
- **Safety Invariant Verified:** The system **DID NOT** fall back to unencrypted storage, DID NOT store plaintext DEKs, and DID NOT issue a false positive PASS verdict.
- **Official Classification:** **`EXTERNALLY_BLOCKED`**.

---

## 2. HERMETIC LOCAL STAGING VERIFICATION (`LocalDevKeyProvider`)

While live cloud credentials remain externally blocked, the complete envelope encryption and wrapping workflow was verified through the hermetic `LocalDevKeyProvider` interface:

| Verification Step | Target Component | Measured Result | Audit Status |
| :--- | :--- | :--- | :--- |
| **DEK Generation** | `crypto.randomBytes(32)` | 256-bit CSPRNG key generated | **VERIFIED** |
| **Binary AAD Binding** | `template_privacy.ts` | Magic header `BIOMATCH_AAD_V1` + TLV tags | **VERIFIED** |
| **Local AES-256-GCM** | `template_privacy.ts` | 512-float vector encrypted with fresh IV | **VERIFIED** |
| **Envelope Wrapping** | `LocalDevKeyProvider` | 60-byte wrapped DEK buffer generated | **VERIFIED** |
| **In-Memory Zeroization** | `dek.fill(0)` | Plaintext DEK wiped from RAM | **VERIFIED** |
| **Unwrap & Context Check** | `LocalDevKeyProvider` | Unwraps DEK only when exact AAD matches | **VERIFIED** |
| **Vector Fidelity** | `template_migration.ts` | Decrypted vector matches original exactly ($\Delta = 0.0$) | **VERIFIED** |
| **Context Tampering Rejection** | `aad_canonicalization.test.ts` | Modifying tenant or UID fails unwrap | **VERIFIED** |

---

## 3. PREREQUISITES FOR LIVE CLOUD VALIDATION (PROD RUNBOOK)

To transition Gate 4 (`Live Cloud KMS`) from `EXTERNALLY_BLOCKED` to `LIVE_STAGING_VERIFIED`, the platform operator must execute the following staging verification protocol:

1. **Step 1 — Service Account Provisioning:**
   Ensure `biomatch-backend@kelasagara-f127a.iam.gserviceaccount.com` has `roles/cloudkms.cryptoKeyEncrypterDecrypter` on `template-kek`.
2. **Step 2 — Staging Credentials Ingress:**
   Inject staging service account key via environment variable:
   ```bash
   export GOOGLE_APPLICATION_CREDENTIALS="/etc/secrets/kms-staging-key.json"
   export GCP_PROJECT_ID="kelasagara-f127a"
   export KMS_LOCATION="asia-south1"
   export KMS_KEY_RING="biomatch-ring"
   export KMS_KEY_ID="template-kek"
   ```
3. **Step 3 — Run Live Staging Integration Probe:**
   Execute live wrap/unwrap verification script:
   ```bash
   node dist/tools/kms_live_probe.js
   ```
4. **Step 4 — Update Staging Evidence:**
   Verify generated response matches expected round-trip vector without exposing plaintext DEKs in persistent audit tables.

---
*Report generated and validated under Stage S9.5 Operating Contract.*
