# KELASAGARA V20.15 — SERVICE ACCOUNT IAM MATRIX
## Granular Least-Privilege Role Assignment and Boundary Enforcement

**Author:** Principal Cloud IAM Engineer, Biometric Security Architect  
**Date:** 2026-11-01  
**Repository:** `kelasagaara_v17`  
**Configuration:** `infra/terraform/iam_bindings.tf`  
**Status:** VALIDATED LEAST-PRIVILEGE  

---

### 1. Identity & Role Architecture

In the Kelasagara biometric and audit infrastructure, no single monolithic service identity exists. Instead, identity is partitioned into **five distinct service accounts**, each restricted to a narrow, non-overlapping operational domain:

1. `sa-biometrics-enrollment`: Handles canonical face embedding extraction, encryption of biometric templates, and writing to the isolated biometric vault.
2. `sa-biometrics-verifier`: Performs 1:1 biometric authentication and 1:N deduplication candidate comparisons; reads encrypted templates and requests DEK unwrap.
3. `sa-biometrics-reviewer`: Dedicated compliance and manual adjudication interface for ambiguous matches; read-only access to audit logs and review queues.
4. `sa-biometrics-inventory`: Read-only maintenance worker for offline template hygiene and gallery integrity verification.
5. `sa-biometrics-audit-notary`: Dedicated cryptographic notary service that creates signed attestations, notarizes manifests, and appends to the immutable audit ledger.

---

### 2. Service Account Capability & Restriction Matrix

| Service Account | Permitted Roles & Resources | Mandatory Prohibitions & Denials |
| :--- | :--- | :--- |
| **`sa-biometrics-enrollment`** | • `roles/cloudkms.cryptoKeyEncrypter` on `biometrics-dek-wrap-key`<br>• `roles/datastore.user` on `biometric-vault-db` | ❌ Cannot decrypt/unwrap DEK (`roles/cloudkms.cryptoKeyDecrypter`)<br>❌ Cannot sign manifests (`roles/cloudkms.signer`)<br>❌ Cannot access `audit-ledger-db` or Cloud Storage |
| **`sa-biometrics-verifier`** | • `roles/cloudkms.cryptoKeyDecrypter` on `biometrics-dek-wrap-key`<br>• `roles/cloudkms.verifier` on `biometrics-manifest-signer-key`<br>• `roles/cloudkms.publicKeyViewer` on KMS keyring<br>• `roles/datastore.viewer` on `biometric-vault-db` | ❌ Cannot encrypt or create new biometric templates<br>❌ Cannot modify or delete templates in `biometric-vault-db`<br>❌ Cannot sign audit checkpoints or manifests<br>❌ Cannot write to audit bucket |
| **`sa-biometrics-reviewer`** | • `roles/datastore.viewer` on `audit-ledger-db` (review queues only)<br>• `roles/storage.objectViewer` on `biometric_audit_ledger` bucket | ❌ Cannot unwrap or decrypt biometric DEK<br>❌ Cannot read raw biometric vectors in `biometric-vault-db`<br>❌ Cannot sign or append records |
| **`sa-biometrics-inventory`** | • `roles/datastore.viewer` on `biometric-vault-db`<br>• `roles/cloudkms.publicKeyViewer` on KMS keyring | ❌ Cannot decrypt biometric data (no KMS decrypter)<br>❌ Cannot insert, update, or delete biometric records<br>❌ Cannot write to Cloud Storage or audit databases |
| **`sa-biometrics-audit-notary`**| • `roles/cloudkms.signer` on `audit-checkpoint-signer-key` and `biometrics-manifest-signer-key`<br>• `roles/storage.objectCreator` on `biometric_audit_ledger` bucket<br>• `roles/datastore.user` on `audit-ledger-db` | ❌ Cannot access `biometric-vault-db`<br>❌ Cannot encrypt or decrypt biometric templates<br>❌ Cannot read or overwrite existing objects in storage bucket (no `storage.objectAdmin` or delete permissions) |

---

### 3. Terraform Implementation in `iam_bindings.tf`

```hcl
# Enrollment: Encrypter only
resource "google_kms_crypto_key_iam_member" "enrollment_dek_encrypter" {
  crypto_key_id = google_kms_crypto_key.dek_wrap_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypter"
  member        = "serviceAccount:sa-biometrics-enrollment@${var.sandbox_project_id}.iam.gserviceaccount.com"
}

# Verifier: Decrypter only
resource "google_kms_crypto_key_iam_member" "verifier_dek_decrypter" {
  crypto_key_id = google_kms_crypto_key.dek_wrap_key.id
  role          = "roles/cloudkms.cryptoKeyDecrypter"
  member        = "serviceAccount:sa-biometrics-verifier@${var.sandbox_project_id}.iam.gserviceaccount.com"
}

# Audit Notary: Signer only (Separated from verifier!)
resource "google_kms_crypto_key_iam_member" "notary_checkpoint_signer" {
  crypto_key_id = google_kms_crypto_key.audit_checkpoint_signer_key.id
  role          = "roles/cloudkms.signer"
  member        = "serviceAccount:sa-biometrics-audit-notary@${var.sandbox_project_id}.iam.gserviceaccount.com"
}

# Verifier: KMS Verifier and Public Key Viewer only
resource "google_kms_crypto_key_iam_member" "verifier_manifest_verifier" {
  crypto_key_id = google_kms_crypto_key.manifest_signer_key.id
  role          = "roles/cloudkms.verifier"
  member        = "serviceAccount:sa-biometrics-verifier@${var.sandbox_project_id}.iam.gserviceaccount.com"
}

resource "google_kms_crypto_key_iam_member" "verifier_public_key_viewer" {
  crypto_key_id = google_kms_crypto_key.manifest_signer_key.id
  role          = "roles/cloudkms.publicKeyViewer"
  member        = "serviceAccount:sa-biometrics-verifier@${var.sandbox_project_id}.iam.gserviceaccount.com"
}

# Storage Bucket: Object Creator only for Notary (Append-only)
resource "google_storage_bucket_iam_member" "notary_bucket_writer" {
  bucket = google_storage_bucket.biometric_audit_ledger.name
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:sa-biometrics-audit-notary@${var.sandbox_project_id}.iam.gserviceaccount.com"
}
```

---

### 4. Adversarial Test Evidence

The tests in `phase20_15_infrastructure_assurance.test.ts` systematically prove least-privilege enforcement:
- **Test 14:** Asserts notary has `roles/cloudkms.signer` and rejects `roles/cloudkms.signerVerifier`.
- **Test 15:** Asserts `sa-biometrics-reviewer` cannot unwrap DEK (`KMS unwrap DEK is denied`).
- **Test 16:** Asserts `sa-biometrics-verifier` cannot create/modify entities in Firestore (`datastore entity create/update denied`).
- **Test 17:** Asserts `sa-biometrics-inventory` has read-only access and cannot write/delete (`datastore entity create/delete denied`).
- **Test 18:** Asserts `sa-biometrics-audit-notary` cannot access the biometric vault database (`datastore entity creation on biometric vault denied`).

### 5. Conclusion

Every service account is cryptographically and logically isolated. Compromise of the verifier identity cannot leak the signing key; compromise of the notary identity cannot decrypt biometric templates; compromise of the reviewer cannot mutate audit logs.
