# KELASAGARA V15.0 BIOMETRIC ENGINE AUDIT
# REPORT 08: CLOUD KMS CRYPTOGRAPHIC ENVELOPE AUDIT & STAGING CHECKLIST

**Document ID:** KLS-V15-KMS-001  
**Classification:** CRYPTOGRAPHIC ARCHITECTURE AUDIT & RUNBOOK  
**Target Subsystem:** `backend/src/services/kms_key_provider.ts`, `backend/src/services/vault_crypto.ts`  
**Audit Finding:** ENVELOPE LOGIC VERIFIED IN CODE / LIVE KMS UNVERIFIED LIVE  
**Audit Date:** 2026-10-23  

---

## 1. ENVELOPE ENCRYPTION ARCHITECTURE

To protect biometric templates stored at rest in Cloud Firestore, the system specifies a **two-tier envelope encryption architecture**:

```
+-----------------------------------------------------------------------------+
|                               GOOGLE CLOUD KMS                              |
|  Key Encryption Key (KEK): projects/kelasagara/locations/asia-south1/...    |
|  HSM-backed AES-256 (Never leaves Google Cloud hardware boundary)           |
+----------------------+-------------------------------+----------------------+
                       | Wrap (Encrypt DEK)            | Unwrap (Decrypt DEK)
                       v                               v
+-----------------------------------------------------------------------------+
|                          KELASAGARA BACKEND MEMORY                          |
|  Data Encryption Key (DEK): 256-bit random cryptographically secure key     |
|  Cipher: AES-256-GCM with 96-bit random IV and 128-bit authentication tag   |
+----------------------+-------------------------------+----------------------+
                       | Encrypt Template              | Decrypt Template
                       v                               v
+-----------------------------------------------------------------------------+
|                            CLOUD FIRESTORE VAULT                            |
|  Doc ID: {workerUid}                                                        |
|  Ciphertext: Base64(Encrypted 128-D vector)                                 |
|  EncryptedDEK: Base64(Wrapped DEK from Cloud KMS)                           |
|  IV: Base64(96-bit AES-GCM IV)                                              |
|  AuthTag: Base64(128-bit GCM Tag)                                           |
+-----------------------------------------------------------------------------+
```

### Advantages of Envelope Encryption:
1. **Zero Raw Template Exposure:** If the Firestore database is ever dumped or compromised, attackers obtain only AES-256-GCM ciphertexts.
2. **Granular Revocation:** Biometric data can be instantly cryptographically shredded by revoking or disabling the KEK in Cloud KMS, without needing to delete Firestore documents individually.
3. **Auditability:** Every single decryption of an enrolled template generates an unalterable audit log entry in Google Cloud Audit Logs.

---

## 2. REPOSITORY CODE AUDIT: `kms_key_provider.ts`

Source code inspection of `backend/src/services/kms_key_provider.ts` revealed two distinct implementations of the `KeyProvider` interface:

### 2.1 `LocalDevKeyProvider` (Used in Dev/Test)
```typescript
export class LocalDevKeyProvider implements KeyProvider {
  private localMasterKey: Buffer = crypto.scryptSync('dev_secret_kelasagara_2026', 'salt', 32);

  async wrapKey(dek: Buffer): Promise<Buffer> {
    // Encrypts DEK using local master key with AES-256-GCM
    return localAesEncrypt(dek, this.localMasterKey);
  }

  async unwrapKey(wrappedDek: Buffer): Promise<Buffer> {
    return localAesDecrypt(wrappedDek, this.localMasterKey);
  }
}
```

### 2.2 `CloudKmsKeyProvider` (Production Target)
```typescript
export class CloudKmsKeyProvider implements KeyProvider {
  private client: KeyManagementServiceClient;

  constructor(private keyResourceName: string) {
    if (!process.env.GOOGLE_APPLICATION_CREDENTIALS && !process.env.KMS_KEY_NAME) {
      throw new Error(
        'KMS_UNAVAILABLE_ERROR (UNVERIFIED-LIVE): GCP credentials or KMS_KEY_NAME are not configured. Cannot initialize CloudKmsKeyProvider.'
      );
    }
    this.client = new KeyManagementServiceClient();
  }

  async wrapKey(dek: Buffer): Promise<Buffer> { ... }
  async unwrapKey(wrappedDek: Buffer): Promise<Buffer> { ... }
}
```

---

## 3. REALITY: LIVE KMS IS UNVERIFIED

- **Dev/Test Suites Pass:** All 148 backend tests and encryption unit tests execute against `LocalDevKeyProvider`.
- **Live KMS Unverified:** In the local audit environment, Google Application Default Credentials (ADC) and live GCP Cloud KMS resources are not provisioned.
- **Auditor Finding:** Cryptographic code paths are mathematically and syntactically sound, but **live production KMS integration is UNVERIFIED LIVE**.

---

## 4. STAGING KMS PROVISIONING RUNBOOK

To promote KMS encryption to verified staging, the cloud operations team must execute the following Google Cloud CLI steps.

### Step 1: Create Staging Key Ring and CryptoKey
```bash
# Set project and region (Mumbai asia-south1 recommended for Indian residency)
gcloud config set project kelasagara-staging
LOCATION="asia-south1"
KEYRING="kelasagara-biometric-keyring"
KEY_NAME="biometric-kek-v1"

# Create KeyRing
gcloud kms keyrings create $KEYRING \
  --location=$LOCATION

# Create Key Encryption Key (KEK) with HSM protection
gcloud kms keys create $KEY_NAME \
  --location=$LOCATION \
  --keyring=$KEYRING \
  --purpose=encryption \
  --protection-level=hsm \
  --rotation-period=90d \
  --next-rotation-time=$(date -u -v+90d +"%Y-%m-%dT00:00:00Z")
```

### Step 2: Grant Service Account IAM Roles
```bash
SERVICE_ACCOUNT="biometric-backend-sa@kelasagara-staging.iam.gserviceaccount.com"

# Grant encrypter/decrypter role to Cloud Run service account
gcloud kms keys add-iam-policy-binding $KEY_NAME \
  --location=$LOCATION \
  --keyring=$KEYRING \
  --member="serviceAccount:$SERVICE_ACCOUNT" \
  --role="roles/cloudkms.cryptoKeyEncrypterDecrypter"
```

### Step 3: Configure Cloud Run Environment Variables
```bash
gcloud run services update kelasagara-biometric-backend \
  --set-env-vars="USE_CLOUD_KMS=true,KMS_KEY_NAME=projects/kelasagara-staging/locations/$LOCATION/keyrings/$KEYRING/cryptoKeys/$KEY_NAME"
```

### Step 4: Verification Smoke Test
Send a synthetic enrollment request to `/api/biometrics/enroll-biometric`. Inspect the Firestore document created in `biometric_vault`. Verify that `wrappedDek` contains a KMS ciphertext header and that Google Cloud Audit Logs register a `Encrypt` and `Decrypt` event for `biometric-backend-sa`.

---

## 5. CONCLUSION & RELEASE GATE IMPACT

Until live Cloud KMS envelope encryption is validated in a deployed GCP staging environment, the system **fails Production Gate G-03**. The engine must remain in **CONTROLLED TEST BUILD ONLY** mode.
