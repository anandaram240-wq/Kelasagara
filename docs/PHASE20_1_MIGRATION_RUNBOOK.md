# KELASAGARA V20.1: ZERO-PLAINTEXT BIOMETRIC VAULT
## PHASE 20.1 TECHNICAL REPORT 4: VAULT MIGRATION OPERATOR RUNBOOK (STAGES A–F)

**Author:** Principal Operations Engineer & Senior Backend Engineer  
**Project:** Kelasagara Major Project  
**Phase:** 20.1 — Zero-Plaintext Biometric Vault  
**Executable Script:** `backend/src/scripts/migrate_biometric_vault_v1_to_v2.ts`  
**Target Collection:** `/biometric_vault`  
**Status:** Certified & Field-Tested (Synthetic Staging)  

---

### 1. OVERVIEW & RUNBOOK MANDATE

This runbook defines the exact operator protocol for executing the zero-downtime database migration of the Firestore `biometric_vault` collection from Schema Version 1 (legacy plaintext numerical arrays) to Schema Version 2 (KMS AES-256-GCM encrypted envelopes).

#### STRICT SAFETY RULES:
1. **Never run migration without Stage C Backup completed and verified.**
2. **Never run on live production users during a sprint without staging qualification.**
3. **Always execute Stages A (Discovery) and B (Dry-Run) before Stage D (Migration).**
4. **All batch operations are rate-limited with bounded concurrency to prevent Firestore quota exhaustion.**

---

### 2. STAGE-BY-STAGE MIGRATION PROTOCOL

```
+--------------------------------------------------------------------------------------------------+
|                                    STAGED MIGRATION TIMELINE                                     |
+--------------------------------------------------------------------------------------------------+
|                                                                                                  |
|   [STAGE A: DISCOVERY]                                                                           |
|   Read-only scan: Categorizes documents into (Plaintext V1, Encrypted V2, Malformed).            |
|                                         |                                                        |
|                                         v                                                        |
|   [STAGE B: DRY-RUN VALIDATION]                                                                  |
|   Validates 128-D dimensions and unit L2 norms without modifying any database records.          |
|                                         |                                                        |
|                                         v                                                        |
|   [STAGE C: VAULT BACKUP]                                                                        |
|   Creates point-in-time snapshot collection /biometric_vault_backup_pre_v2.                      |
|                                         |                                                        |
|                                         v                                                        |
|   [STAGE D: CONTROLLED ATOMIC MIGRATION]                                                         |
|   Batches of 50, Concurrency 5: Encrypts vector -> Writes envelope -> Deletes plaintext fields.  |
|                                         |                                                        |
|                                         v                                                        |
|   [STAGE E: INDEPENDENT VERIFICATION]                                                            |
|   Decrypts every migrated envelope with fresh DEK; checks unit L2 norm and AAD integrity.       |
|                                         |                                                        |
|                                         v                                                        |
|   [STAGE F: IDEMPOTENCY CONFIRMATION]                                                            |
|   Re-executes migration script; confirms 0 records require migration.                           |
+--------------------------------------------------------------------------------------------------+
```

---

### 3. EXECUTING THE STAGES

#### 3.1 Stage A: Discovery & Inventory
The operator runs the discovery command to establish exact record counts:
```bash
cd backend
npx ts-node src/scripts/migrate_biometric_vault_v1_to_v2.ts --action=discover
```
*Expected Output:*
```
[Stage A: Discovery] Scanning collection 'biometric_vault'...
Scan complete:
  Total Records: 48
  Legacy Plaintext (V1): 48
  Already Encrypted (V2): 0
  Malformed: 0
```

#### 3.2 Stage B: Dry-Run Validation
Validates that every legacy record contains a valid, finite 128-D floating-point vector with norm $\approx 1.0$:
```bash
npx ts-node src/scripts/migrate_biometric_vault_v1_to_v2.ts --action=dry-run
```
*Expected Output:*
```
[Stage B: Dry-Run] Validating records in 'biometric_vault'...
Dry-run complete:
  Valid Candidates: 48
  Invalid / Malformed: 0
Dry-run PASSED. Ready for migration.
```

#### 3.3 Stage C: Point-in-Time Vault Backup
Before executing writes, create a backup copy of the entire collection:
```bash
npx ts-node src/scripts/migrate_biometric_vault_v1_to_v2.ts --action=backup
```
*Action Performed:*
Copies every document in `biometric_vault` to `biometric_vault_backup_pre_v2` with original metadata and timestamp.

#### 3.4 Stage D: Controlled Atomic Migration
Executes the encryption and atomic transformation:
```bash
npx ts-node src/scripts/migrate_biometric_vault_v1_to_v2.ts \
    --action=migrate \
    --batch-size=50 \
    --concurrency=5
```
*Mechanism:*
1. Reads candidate documents where `status == 'ACTIVE'`.
2. Skips documents already having `schemaVersion == 2`.
3. Encrypts embedding via `BiometricTemplateCryptoService.encryptTemplate()`.
4. In a Firestore batch write:
   - Sets `schemaVersion: 2`.
   - Sets `biometricEnvelope: encryptedEnvelope`.
   - Sets `metadata: { modelId, modelVersion, dimensions: 128, matchingSpace: 'SFACE_NEURAL_SPACE' }`.
   - Sets `canonicalEmbedding: FieldValue.delete()`.
   - Sets `sfaceEmbedding128: FieldValue.delete()`.
   - Sets `embedding: FieldValue.delete()`.

#### 3.5 Stage E: Independent Decryption Verification
Verifies that all migrated envelopes can be successfully decrypted and that decrypted vectors retain mathematical identity:
```bash
npx ts-node src/scripts/migrate_biometric_vault_v1_to_v2.ts --action=verify
```
*Expected Output:*
```
[Stage E: Verification] Verifying encrypted envelopes in 'biometric_vault'...
Verification complete:
  Successfully Decrypted: 48
  Verification Failures: 0
Verification 100% SUCCESSFUL.
```

#### 3.6 Stage F: Idempotency Confirmation
The operator runs the migration command a second time:
```bash
npx ts-node src/scripts/migrate_biometric_vault_v1_to_v2.ts --action=migrate
```
*Expected Output:*
```
Found 0 active candidate records requiring encryption.
Migration finished: 0 records migrated, 0 errors.
```

---

### 4. OPERATIONAL MONITORING & ERROR CODES

| Error Code | Root Cause | Operator Action |
| :--- | :--- | :--- |
| `KMS_UNAVAILABLE` | KMS network timeout or service disruption | Migration halts safely. Check GCP IAM & quotas, then re-run. |
| `AUTHENTICATION_TAG_VERIFICATION_FAILED` | Bit corruption in envelope or mismatched AAD | Halt immediately. Inspect document ID and owner UID. Restore from backup. |
| `INVALID_DECRYPTED_VECTOR_NORM` | Numerical drift or vector was unnormalized before encryption | Flag record for compliance review. Do not delete backup. |
| `FIRESTORE_WRITE_REJECTED` | Firestore rules violation or permission error | Verify service account role `roles/datastore.user`. |
