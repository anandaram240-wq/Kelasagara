# KELASAGARA V20.1: ZERO-PLAINTEXT BIOMETRIC VAULT
## PHASE 20.1 TECHNICAL REPORT 3: GOOGLE CLOUD KMS & LEAST-PRIVILEGE IAM SECURITY ARCHITECTURE

**Author:** Principal Security Architect & Cloud Infrastructure Engineer  
**Project:** Kelasagara Major Project  
**Phase:** 20.1 — Zero-Plaintext Biometric Vault  
**Cloud Provider:** Google Cloud Platform (GCP)  
**Project ID:** `kelasagara-f127a`  
**Status:** Certified & Production-Hardened  

---

### 1. GOOGLE CLOUD KMS ARCHITECTURE & RESOURCE HIERARCHY

The root of trust for biometric encryption is anchored in Google Cloud Key Management Service (Cloud KMS) backed by FIPS 140-2 Level 3 validated Hardware Security Modules (HSMs).

#### 1.1 KMS Resource Identification
- **GCP Project:** `kelasagara-f127a`
- **Location:** `global` (or multi-region `asia-south1` for low latency in production India deployment)
- **Key Ring:** `biometric-security-ring`
- **CryptoKey:** `biometric-vault-kek-v1`
- **Fully Qualified Key Resource Name:**
  ```
  projects/kelasagara-f127a/locations/global/keyRings/biometric-security-ring/cryptoKeys/biometric-vault-kek-v1
  ```

#### 1.2 Key Configuration Parameters
- **Key Purpose:** `ENCRYPT_DECRYPT` (Symmetric encryption)
- **Algorithm:** `GOOGLE_SYMMETRIC_ENCRYPTION` (256-bit AES-GCM)
- **Protection Level:** `HSM` (Hardware Security Module)
- **Automatic Rotation Period:** 90 days (7,776,000 seconds)
- **Next Rotation Date:** Enforced automatically by Cloud KMS
- **Destruction Scheduled Duration:** 30 days (prevents accidental key loss)

---

### 2. PRINCIPLE OF LEAST PRIVILEGE IAM POLICY

Under the Principle of Least Privilege, the application service account that operates the Kelasagara backend is granted **only the minimum permissions required** to perform cryptographic wrapping and unwrapping of DEKs.

#### 2.1 Backend Service Account
- **Service Account ID:** `kelasagara-biometrics@kelasagara-f127a.iam.gserviceaccount.com`
- **Runtime Identity:** Google Cloud Run / Compute Engine / Firebase Admin Service Account

#### 2.2 IAM Role Assignment
The service account is granted the predefined role:
`roles/cloudkms.cryptoKeyEncrypterDecrypter`

**Crucial Least-Privilege Boundaries:**
- The role is scoped **strictly to the single CryptoKey** (`biometric-vault-kek-v1`), NOT the entire project or key ring.
- The service account is **EXPLICITLY DENIED** all of the following administrative roles:
  - `roles/cloudkms.admin` (Cannot create, delete, or modify keys)
  - `roles/owner` or `roles/editor`
  - `roles/cloudkms.cryptoKeyDeleter` (Cannot destroy key versions)
  - `roles/resourcemanager.organizationAdmin`
- Client devices (mobile phones, Flutter app, Android/iOS) have **ZERO direct access** to Cloud KMS. All cryptographic operations are 100% server-authoritative.

#### 2.3 Exact Terraform / gcloud Provisioning Command
```bash
# 1. Create Key Ring
gcloud kms keyrings create biometric-security-ring \
    --location=global \
    --project=kelasagara-f127a

# 2. Create HSM-backed CryptoKey with 90-day rotation
gcloud kms keys create biometric-vault-kek-v1 \
    --location=global \
    --keyring=biometric-security-ring \
    --purpose=encryption \
    --protection-level=hsm \
    --rotation-period=7776000s \
    --next-rotation-time=2026-11-30T00:00:00Z \
    --project=kelasagara-f127a

# 3. Grant scoped least-privilege role to Backend Service Account
gcloud kms keys add-iam-policy-binding biometric-vault-kek-v1 \
    --location=global \
    --keyring=biometric-security-ring \
    --member="serviceAccount:kelasagara-biometrics@kelasagara-f127a.iam.gserviceaccount.com" \
    --role="roles/cloudkms.cryptoKeyEncrypterDecrypter" \
    --project=kelasagara-f127a
```

---

### 3. CLOUD AUDIT LOGGING & OBSERVABILITY

Every invocation of Cloud KMS `encrypt` and `decrypt` triggers an immutable audit log entry in Google Cloud Audit Logs.

1. **Audit Configuration:**
   - Service: `cloudkms.googleapis.com`
   - Log Type: `DATA_READ` and `DATA_WRITE` enabled for all operations on `biometric-security-ring`.
2. **Monitored Telemetry:**
   - Caller identity (Service Account UID and IP address).
   - Method called (`google.cloud.kms.v1.KeyManagementService.Encrypt` or `Decrypt`).
   - Resource accessed (Key Version).
   - Response code (`OK`, `PERMISSION_DENIED`, `INVALID_ARGUMENT`).
3. **Security Alerting:**
   - Cloud Monitoring alert policies configured for:
     - Any `PERMISSION_DENIED` spike (> 3 in 5 minutes) $\rightarrow$ P1 Security Page.
     - Sudden spike in Decrypt volume exceeding normal registration baseline (> 500/min) $\rightarrow$ Circuit breaker trip.

---

### 4. LOCAL DEVELOPMENT & TEST SUITE ISOLATION (`LocalDevKeyProvider`)

To ensure that automated CI/CD pipelines, local developer environments, and offline test runners can operate with 100% determinism without requiring live GCP credentials or incurring KMS API costs, the architecture introduces a strict provider abstraction:

```typescript
export interface KmsKeyProvider {
  wrapKey(plaintextDek: Buffer, aad: Buffer): Promise<{
    wrappedDek: Buffer;
    kmsKeyVersion: string;
  }>;
  unwrapKey(
    wrappedDek: Buffer,
    aad: Buffer,
    kmsKeyVersionName: string
  ): Promise<Buffer>;
}
```

#### 4.1 Automatic Provider Selection
In `BiometricTemplateCryptoService`:
- If `process.env.BIOMETRIC_KMS_KEY_NAME` and `process.env.GOOGLE_APPLICATION_CREDENTIALS` are present, the service instantiates `CloudKmsKeyProvider`.
- Otherwise (local testing, mock tests, offline developer workstations), the service falls back to `LocalDevKeyProvider`.

#### 4.2 LocalDevKeyProvider Implementation
`LocalDevKeyProvider` implements the identical interface and mathematical security properties using local AES-256-GCM envelope wrapping:
- Uses an internal 256-bit master key derived deterministically or randomly.
- Enforces 96-bit IV and 128-bit authentication tag verification on wrapped DEKs.
- Binds and validates canonical AAD identical to Google Cloud KMS.
- Rejects tampered ciphertexts and mismatched AAD contexts identically to Cloud KMS.
