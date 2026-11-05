# KELASAGARA BIOMATCH — STAGE S9.5 CLOUD KMS IMPLEMENTATION & ARCHITECTURE REPORT
**Document ID:** `S9_KMS_IMPLEMENTATION_REPORT.md`  
**Classification:** Key Management Architecture & Applied Cryptography Assurance  
**Evaluation Date:** October 11, 2026 (UTC: 2026-10-11T05:09:30Z)  
**Git Commit:** `6a2a1482fe90d41050fc61ac83cc8777291a4a06` (tag: `s8-final`)  
**Evidence Artifacts:** `evidence/s9/kms_unit_tests.json`, `evidence/s9/kms_failure_matrix.json`  

---

## 1. CURRENT KEY PROVIDER INSPECTION

The biometric key management subsystem is implemented in `backend/src/services/kms_key_provider.ts`. It provides an explicit abstraction separating local developer execution from production Google Cloud KMS operations:

```typescript
export interface KeyProvider {
  readonly providerType: "local" | "cloud_kms";
  readonly defaultKeyResourceName: string;
  wrapDek(dek: Buffer, context: Buffer): Promise<WrappedDekResult>;
  unwrapDek(wrappedDek: Buffer, context: Buffer, keyResourceName?: string): Promise<Buffer>;
}
```

### 1.1 Provider Implementations
1. **`LocalDevKeyProvider`:**
   - Designed for hermetic local testing, sandboxed CI, and offline unit verification.
   - Enforces an explicit production safety guard:
     ```typescript
     if (isProduction && !options?.allowInProduction) {
       throw new Error("[LocalDevKeyProvider] SECURITY VIOLATION: LocalDevKeyProvider is strictly forbidden in production.");
     }
     ```
   - Wraps DEKs using AES-256-GCM under a local master KEK with AAD context binding.
   - Wire format of wrapped DEK: 60 bytes `[IV(12) | AuthTag(16) | Ciphertext(32)]`.
2. **`CloudKmsKeyProvider`:**
   - Targets Google Cloud KMS REST and gRPC endpoints.
   - Resource path:
     `projects/{projectId}/locations/{locationId}/keyRings/{keyRingId}/cryptoKeys/{keyId}`
   - Default configuration: `projects/kelasagara-f127a/locations/asia-south1/keyRings/biomatch-ring/cryptoKeys/template-kek`.
   - Fail-closed behavior: When `GOOGLE_APPLICATION_CREDENTIALS` is unset, throws explicit `KMS_UNAVAILABLE_ERROR (UNVERIFIED-LIVE)` rather than falling back to unencrypted storage.

### 1.2 Callers & Integration Trace
- **`backend/src/services/template_privacy.ts`:**
  - `encryptTemplateEnvelope()`: Generates fresh 32-byte CSPRNG DEK $\to$ calls `keyProvider.wrapDek(dek, canonicalAad)` $\to$ encrypts 512-float vector with DEK $\to$ executes `dek.fill(0)` to zeroize plaintext key in RAM.
  - `decryptTemplateEnvelope()`: Calls `keyProvider.unwrapDek(envelope.wrappedDek, canonicalAad, envelope.kmsKeyResourceName)` $\to$ decrypts ciphertext $\to$ zeroizes DEK $\to$ returns reconstructed vector.
- **`backend/src/services/template_migration.ts`:**
  - `TemplateMigrationService.migrateRecord()`: Reads legacy `v1` or `v2` record $\to$ decrypts $\to$ invokes `encryptTemplateEnvelope()` with `v3_kms_gcm` and `CloudKmsKeyProvider` or `LocalDevKeyProvider` $\to$ verifies vector fidelity $\to$ commits to Firestore.
- **`backend/src/services/firestore_biometric_repository.ts`:**
  - Writes only the completed `v3_kms_gcm` envelope to `users/{uid}/biometricVault/default`.

---

## 2. ENVELOPE ENCRYPTION ARCHITECTURE & SPECIFICATION

Per Invariants **SEC-05** and **SEC-07**, the system implements a two-tier envelope encryption architecture:

```
┌────────────────────────────────────────────────────────┐
│                   TEMPLATE WRITE PATH                  │
├────────────────────────────────────────────────────────┤
│ 1. Generate fresh 256-bit DEK: crypto.randomBytes(32)  │
│ 2. Generate fresh 96-bit IV: crypto.randomBytes(12)    │
│ 3. Encode canonical binary AAD: BIOMATCH_AAD_V1 (TLV)  │
│ 4. Local AES-256-GCM Encrypt(vector, DEK, IV, AAD)     │
│ 5. Call KeyProvider.wrapDek(DEK, AAD)                  │
│    └─ Cloud KMS Encrypt(KEK, DEK, AAD)                 │
│ 6. Memory Zeroization: DEK.fill(0)                     │
│ 7. Store Envelope: [Ciphertext, Tag, IV, WrappedDEK]   │
└────────────────────────────────────────────────────────┘
```

### 2.1 Cryptographic Properties
- **Data Encryption Key (DEK):** Fresh CSPRNG 256-bit key per write operation. Plaintext DEK never touches persistent storage and is erased in process RAM immediately following encryption or decryption.
- **Key Encryption Key (KEK):** Managed exclusively inside Google Cloud KMS Hardware Security Modules (HSMs) or software keys. KEK is never exported into application address space.
- **Additional Authenticated Data (AAD):** Binary canonical format (`BIOMATCH_AAD_V1`) binding:
  - Domain separation magic header (15 bytes: `BIOMATCH_AAD_V1`)
  - `TAG_TENANT_ID` (0x01)
  - `TAG_USER_UID` (0x02)
  - `TAG_ALGORITHM_ID` (0x03, e.g. `sface_fp32`)
  - `TAG_KEY_VERSION` (0x04)
  - `TAG_TIMESTAMP_EPOCH` (0x05)
- **Zeroization Verification:** Verified in unit testing and code inspection that `dek.fill(0)` is executed in a `finally` block to protect against unhandled exception leaks.

---

## 3. PROVISIONING & LEAST-PRIVILEGE IAM CHECKLIST

For production deployment on Google Cloud Platform, the following configuration checklist is established:

1. **Google Cloud Project:** `kelasagara-f127a`
2. **KMS API Enablement:** `gcloud services enable cloudkms.googleapis.com --project=kelasagara-f127a`
3. **Dedicated Key Ring:**
   - Location: `asia-south1` (Mumbai, ensuring local Indian data residency)
   - Command: `gcloud kms keyrings create biomatch-ring --location=asia-south1 --project=kelasagara-f127a`
4. **CryptoKey Creation:**
   - Command:
     ```bash
     gcloud kms keys create template-kek \
       --location=asia-south1 \
       --keyring=biomatch-ring \
       --purpose=encryption \
       --rotation-period=90d \
       --next-rotation-time=2026-12-31T00:00:00Z \
       --project=kelasagara-f127a
     ```
5. **Runtime Identity & Least-Privilege IAM:**
   - Dedicated Service Account: `biomatch-backend@kelasagara-f127a.iam.gserviceaccount.com`
   - Grant Role: `roles/cloudkms.cryptoKeyEncrypterDecrypter`
   - Command:
     ```bash
     gcloud kms keys add-iam-policy-binding template-kek \
       --location=asia-south1 \
       --keyring=biomatch-ring \
       --member="serviceAccount:biomatch-backend@kelasagara-f127a.iam.gserviceaccount.com" \
       --role="roles/cloudkms.cryptoKeyEncrypterDecrypter" \
       --project=kelasagara-f127a
     ```
   - **Audit Policy:** Zero administrative permissions (`roles/cloudkms.admin` is strictly denied to backend service accounts).
   - **Workload Identity:** On Google Cloud Run or GKE, attach the service account directly via Workload Identity Federation rather than downloading static JSON service account keys.

---

## 4. OPERATIONAL RESILIENCE & FAILURE MODES

The resilience matrix (`evidence/s9/kms_failure_matrix.json`) defines system behavior across 11 edge cases:
- **Timeouts:** 5000ms deadline; fail-closed; bounded exponential backoff (3 retries).
- **IAM 403 / Precondition 400:** Non-retryable; instant security alert; zeroized DEK.
- **Network / Outage:** Max 3 retries; HTTP 503 fallback; no fallback to plaintext vectors.
- **Corrupted Ciphertext:** Non-retryable; original record preserved; administrative review triggered.

---
*Report generated and validated under Stage S9.5 Operating Contract.*
