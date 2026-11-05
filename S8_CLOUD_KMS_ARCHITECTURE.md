# S8 CLOUD KMS ENVELOPE ENCRYPTION ARCHITECTURE

**System:** Kelasagara BioMatch Key Management Architecture  
**Remediation Target:** GAP-02 (Elimination of static `MASTER_KEY_SECRET` in production)  
**Standard Compliance:** NIST SP 800-57, NIST SP 800-38D, ISO/IEC 24745  

---

## 1. Envelope Encryption Key Hierarchy

```mermaid
flowchart TD
    subgraph GCP_KMS [Google Cloud KMS]
        KEK["Key Encryption Key (KEK)<br/>projects/.../cryptoKeys/template-kek"]
    end
    subgraph Host_Memory [Backend Ephemeral Memory]
        DEK["Data Encryption Key (DEK)<br/>256-bit CSPRNG (Zeroized after use)"]
        Raw_Vector["128-D FP32 Embedding<br/>(512 bytes)"]
        Ciphertext["AES-256-GCM Ciphertext<br/>(512 bytes)"]
    end
    subgraph Firestore_Vault [Firestore biometric_vault]
        Envelope["v3_kms_gcm Envelope<br/>(wrappedDek, ciphertext, IV, authTag, AAD)"]
    end

    KEK -->|wrapDek(dek, AAD)| Envelope
    DEK -->|encrypt(Raw_Vector, AAD)| Ciphertext
    Ciphertext --> Envelope
    Envelope -->|unwrapDek(wrappedDek, AAD)| DEK
```

### Components:
1. **Key Encryption Key (KEK):** Symmetric 256-bit AES key residing inside Google Cloud KMS HSM (`HSM` or `SOFTWARE` protection level). Never exported from KMS.
2. **Data Encryption Key (DEK):** Generated fresh per biometric record via `crypto.randomBytes(32)`. Ephemeral in memory; zeroized via `dek.fill(0)` immediately after encryption/decryption.
3. **Wrapped DEK:** Result of KMS wrapping. Wire format: `[IV (12B) | Tag (16B) | Ciphertext (32B)]` (60 bytes total).
4. **Additional Authenticated Data (AAD):** Length-prefixed binary context (`BIOMATCH_AAD_V1`) cryptographically binding `${envelopeVersion}`, `${tenantId}`, `${uid}`, `${keyVersion}`, and `${templatePurpose}`.

---

## 2. Interface Separation & Providers
- **`KeyProvider` Interface:** Defined in [`kms_key_provider.ts`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/backend/src/services/kms_key_provider.ts).
- **`LocalDevKeyProvider`:** Operates hermetically in development and test environments with isolated master key. Throws an invariant error if instantiated in production.
- **`CloudKmsKeyProvider`:** Connects to Google Cloud KMS. Requires GCP service account with role `roles/cloudkms.cryptoKeyEncrypterDecrypter`. Throws explicit `KMS_UNAVAILABLE_ERROR` (`UNVERIFIED-LIVE`) when credentials are missing.
