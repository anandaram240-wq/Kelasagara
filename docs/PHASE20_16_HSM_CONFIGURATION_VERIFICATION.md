# KELASAGARA V20.16 — KMS HSM CONFIGURATION VERIFICATION
## Cryptographic Key Declarations, HSM Intent vs Real Cloud Provisioning, and Destruction Safeguards

**Author:** Principal KMS Cryptographic Engineer, Hardware Security Auditor  
**Date:** 2026-11-01  
**Repository:** `kelasagaara_v17`  
**Configuration:** `infra/terraform/kms.tf`, `infra/terraform/iam_bindings.tf`  
**Status:** STATIC INTENT VERIFIED; LIVE HSM PROVISIONING BLOCKED  

---

### 1. Distinction: Configured HSM Intent vs Live Cloud Resource Verification

An essential security distinction must be maintained between **Infrastructure-as-Code Declarations** and **Live Cloud Verification**:

1. **Configured HSM Intent (Verified in IaC):**
   - The Terraform configuration in `infra/terraform/kms.tf` explicitly specifies `protection_level = "HSM"` across all three crypto keys.
   - HCL syntax, provider schema, and Policy-as-Code rules confirm that the declared configuration requires FIPS 140-2 Level 3 Hardware Security Modules.
2. **Live Cloud Resource Verification (Blocked):**
   - Because no authorized Google Cloud project is available on this host, **no live Cloud KMS keys have been provisioned in GCP**.
   - Offline verification proves that *if* Terraform executes against GCP, it will request HSM keys. However, offline verification cannot prove that Google Cloud has actually allocated HSM hardware keys.
   - Live cloud verification remains formally classified as:
     `BLOCKED_SANDBOX_IAM_NOT_AVAILABLE`

---

### 2. Cryptographic Key Inventory & Technical Specifications

| CryptoKey Name | Algorithm Specification | Key Purpose | Protection Level | Rotation Policy | Lifecycle Protection |
| :--- | :--- | :--- | :---: | :---: | :---: |
| **`biometric-dek-wrap-key`** | `GOOGLE_SYMMETRIC_ENCRYPTION` (AES-256-GCM) | `ENCRYPT_DECRYPT` | `HSM` | 90 days (`7776000s`) | `prevent_destroy = true` |
| **`manifest-attestation-key`** | `EC_SIGN_P256_SHA256` (ECDSA P-256 SHA-256) | `ASYMMETRIC_SIGN` | `HSM` | Manual asymmetric | `prevent_destroy = true` |
| **`audit-checkpoint-signing-key`** | `EC_SIGN_P256_SHA256` (ECDSA P-256 SHA-256) | `ASYMMETRIC_SIGN` | `HSM` | Manual asymmetric | `prevent_destroy = true` |

Keyring: `biometric-identity-keyring-${var.environment}` in regional location `var.region` (`asia-south1` default for India data residency under DPDPA 2023).

---

### 3. Signing vs Verification Cryptographic Boundary

In asymmetric cryptography, granting verification authority must never leak signing authority:
- **`roles/cloudkms.signer`**: Holds `cloudkms.cryptoKeyVersions.useToSign`. Granted **exclusively** to `sa-biometrics-audit-notary`.
- **`roles/cloudkms.verifier`**: Holds `cloudkms.cryptoKeyVersions.useToVerify` and `cloudkms.cryptoKeyVersions.viewPublicKey`. Granted to `sa-biometrics-verifier` and `sa-biometrics-inventory`.
- Neither the verifier nor the inventory service account can forge signatures or notarize checkpoints.

---

### 4. Destruction Defenses and `prevent_destroy` Limitations

#### What `prevent_destroy = true` Protects:
- Declared inside `lifecycle { prevent_destroy = true }` on all crypto keys and the key ring.
- If `tofu destroy` or a plan attempting resource replacement is executed, Terraform client halts with an error before touching GCP APIs.

#### What Requires Controls Outside Terraform:
1. **Google Cloud KMS Inherent Protection:**
   - In Google Cloud KMS, key rings and crypto keys **cannot be permanently deleted immediately**.
   - Destroying a key version initiates a **24-hour scheduled destruction window** (`destroy_scheduled_duration`).
   - During this 24-hour window, the key version is in `DESTROY_SCHEDULED` state and can be restored using `gcloud kms keys versions restore`.
2. **Organization Policy Control:**
   - Enforce `constraints/cloudkms.allowedProtectionLevels` to restrict key creation to `HSM`.
3. **Cloud IAM Least Privilege:**
   - Exclude `roles/cloudkms.admin` from all runtime service accounts. Zero application identities have permissions to schedule key destruction.

---

### 5. Adversarial Test Evidence

In `phase20_16_cloud_runtime_authorization.test.ts`:
- **Test 9:** Confirms decrypt permission cannot be used for signing.
- **Test 10:** Confirms verifier cannot sign.
- **Test 13:** Confirms redundant `publicKeyViewer` role removed.
- **Test 14:** Confirms wrong CryptoKey bindings rejected.

### 6. Conclusion

The Cloud KMS configuration enforces enterprise hardware security standards. Live HSM provisioning remains properly classified as blocked until an authorized cloud project is configured.
