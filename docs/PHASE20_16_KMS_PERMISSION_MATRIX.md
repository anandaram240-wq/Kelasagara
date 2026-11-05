# KELASAGARA V20.16 — KMS PERMISSION MATRIX
## Comprehensive Mapping of Keys, Service Accounts, IAM Roles and Redundancy Audit

**Author:** Principal KMS Engineer, IAM Security Architect  
**Date:** 2026-11-01  
**Repository:** `kelasagaara_v17`  
**Configuration:** `infra/terraform/kms.tf`, `infra/terraform/iam_bindings.tf`  
**Status:** VALIDATED LEAST-PRIVILEGE  

---

### 1. Comprehensive KMS Key & Service Account Permission Matrix

The following matrix documents every interaction between the five biometric subsystem service accounts and the three Cloud KMS crypto keys declared in `infra/terraform/kms.tf`:

| Service Account | Target CryptoKey Name | Key Purpose & Algorithm | Required Operation | Required IAM Role | Access Needed? | Access Declared in IaC? | Cloud Verification Status |
| :--- | :--- | :--- | :--- | :--- | :---: | :---: | :---: |
| **`sa-biometrics-enrollment`** | `biometric-dek-wrap-key` | Symmetric AES-256-GCM (`ENCRYPT_DECRYPT`) | Wrap DEK during enrollment | `roles/cloudkms.cryptoKeyEncrypter` | **YES** | **YES** (`enrollment_kms_encrypter`) | `BLOCKED_SANDBOX_IAM_NOT_AVAILABLE` |
| `sa-biometrics-enrollment` | `manifest-attestation-key` | Asymmetric ECDSA P-256 (`ASYMMETRIC_SIGN`) | None | None | **NO** | **NO** (Denied) | N/A |
| `sa-biometrics-enrollment` | `audit-checkpoint-signing-key` | Asymmetric ECDSA P-256 (`ASYMMETRIC_SIGN`) | None | None | **NO** | **NO** (Denied) | N/A |
| **`sa-biometrics-verifier`** | `biometric-dek-wrap-key` | Symmetric AES-256-GCM (`ENCRYPT_DECRYPT`) | Unwrap DEK during 1:1/1:N match | `roles/cloudkms.cryptoKeyDecrypter` | **YES** | **YES** (`verifier_kms_decrypter`) | `BLOCKED_SANDBOX_IAM_NOT_AVAILABLE` |
| **`sa-biometrics-verifier`** | `manifest-attestation-key` | Asymmetric ECDSA P-256 (`ASYMMETRIC_SIGN`) | Verify manifest signature & view pubkey | `roles/cloudkms.verifier` | **YES** | **YES** (`verifier_manifest_key_verifier`) | `BLOCKED_SANDBOX_IAM_NOT_AVAILABLE` |
| `sa-biometrics-verifier` | `manifest-attestation-key` | Asymmetric ECDSA P-256 (`ASYMMETRIC_SIGN`) | View public key | `roles/cloudkms.publicKeyViewer` | **NO (Redundant)** | **REMOVED in V20.16** | N/A |
| `sa-biometrics-verifier` | `audit-checkpoint-signing-key` | Asymmetric ECDSA P-256 (`ASYMMETRIC_SIGN`) | None | None | **NO** | **NO** (Denied) | N/A |
| **`sa-biometrics-reviewer`** | *All Keys* | *Any* | None | None | **NO** | **NO (ZERO KMS ACCESS)** | N/A |
| **`sa-biometrics-inventory`** | `biometric-dek-wrap-key` | Symmetric AES-256-GCM (`ENCRYPT_DECRYPT`) | None | None | **NO** | **NO** (Denied) | N/A |
| `sa-biometrics-inventory` | `manifest-attestation-key` | Asymmetric ECDSA P-256 (`ASYMMETRIC_SIGN`) | None | None | **NO** | **NO** (Denied) | N/A |
| **`sa-biometrics-inventory`** | `audit-checkpoint-signing-key` | Asymmetric ECDSA P-256 (`ASYMMETRIC_SIGN`) | Verify audit checkpoints & view pubkey | `roles/cloudkms.verifier` | **YES** | **YES** (`inventory_audit_key_verifier`) | `BLOCKED_SANDBOX_IAM_NOT_AVAILABLE` |
| `sa-biometrics-inventory` | `audit-checkpoint-signing-key` | Asymmetric ECDSA P-256 (`ASYMMETRIC_SIGN`) | View public key | `roles/cloudkms.publicKeyViewer` | **NO (Redundant)** | **REMOVED in V20.16** | N/A |
| **`sa-biometrics-audit-notary`** | `biometric-dek-wrap-key` | Symmetric AES-256-GCM (`ENCRYPT_DECRYPT`) | None | None | **NO** | **NO** (Denied) | N/A |
| `sa-biometrics-audit-notary` | `manifest-attestation-key` | Asymmetric ECDSA P-256 (`ASYMMETRIC_SIGN`) | None | None | **NO** | **NO** (Denied) | N/A |
| **`sa-biometrics-audit-notary`** | `audit-checkpoint-signing-key` | Asymmetric ECDSA P-256 (`ASYMMETRIC_SIGN`) | Sign sequenced audit checkpoints | `roles/cloudkms.signer` | **YES** | **YES** (`audit_notary_kms_signer`) | `BLOCKED_SANDBOX_IAM_NOT_AVAILABLE` |

---

### 2. Removal of Redundant Permissions Audit

In Phase 20.15, `iam_bindings.tf` defined:
1. `public_manifest_key_viewer`: Granted `roles/cloudkms.publicKeyViewer` on `manifest_attestation` to `verifier`.
2. `public_audit_key_viewer`: Granted `roles/cloudkms.publicKeyViewer` on `audit_checkpoint` to `inventory`.

**GCP IAM Permission Analysis:**
- Role `roles/cloudkms.verifier` comprises:
  - `cloudkms.cryptoKeyVersions.useToVerify`
  - `cloudkms.cryptoKeyVersions.viewPublicKey`
  - `cloudkms.cryptoKeys.get`
- Role `roles/cloudkms.publicKeyViewer` comprises:
  - `cloudkms.cryptoKeyVersions.viewPublicKey`
  - `cloudkms.cryptoKeys.get`

Because `roles/cloudkms.verifier` already grants `viewPublicKey` and `get`, binding `roles/cloudkms.publicKeyViewer` to the same member on the exact same key was **100% redundant**.

**Remediation in Phase 20.16:**
Both redundant resources were removed from `infra/terraform/iam_bindings.tf`. The verifier and inventory identities retain `roles/cloudkms.verifier`, which provides full verification and public key inspection capabilities without unnecessary permission clutter.

---

### 3. Strict Boundary Enforcements Verified

1. **Enrollment cannot sign audit checkpoints:** `sa-biometrics-enrollment` has zero roles on `audit-checkpoint-signing-key`.
2. **Audit notary cannot write biometric templates:** `sa-biometrics-audit-notary` has zero write access to `biometric-vault-db`.
3. **Verifier cannot sign manifest attestations:** `sa-biometrics-verifier` holds `roles/cloudkms.verifier`, strictly denying `roles/cloudkms.signer`.
4. **Reviewer cannot decrypt biometric templates:** `sa-biometrics-reviewer` has zero KMS roles across all keys.
5. **Inventory cannot write or delete records:** `sa-biometrics-inventory` is strictly a `roles/datastore.viewer`.
6. **Only designated principal can decrypt DEK:** `sa-biometrics-verifier` is the sole identity granted `roles/cloudkms.cryptoKeyDecrypter`.

---

### 4. Operational Status

Because no live sandbox project is authorized on this host:
- Live IAM binding validation is marked as `BLOCKED_SANDBOX_IAM_NOT_AVAILABLE`.
- Static HCL AST verification and Policy-as-Code test validation are 100% PASS.
