# PHASE 20.14: TERRAFORM INFRASTRUCTURE-AS-CODE ARCHITECTURE
## Non-Production Sandbox IaC Modules, Safety Preconditions, and Least-Privilege Declarations

**Date:** November 2026  
**System:** Kelasagara Biometric Identity Service  
**Author:** Principal Cloud Infrastructure Security Architect  
**Status:** APPROVED & AUDITED  
**Repository:** `kelasagaara_v17`  
**Location:** `infra/terraform/`  
**Classification:** SOURCE_VERIFIED & PRODUCTION_PROTECTED  

---

### 1. Terraform Architecture Overview

Phase 20.14 introduces a fully codified, declarative Infrastructure-as-Code (IaC) suite under `infra/terraform/` designed to provision non-production Google Cloud environments (sandbox, staging, dev, test) with zero risk of accidental production application.

```
infra/terraform/
├── variables.tf              # Project allowlists, production denylists, environment bounds
├── main.tf                   # Provider configuration and compile-time safety preconditions
├── service_accounts.tf       # Dedicated service identities for enrollment, verifier, reviewer, inventory, notary
├── kms.tf                    # Cloud KMS keyrings, HSM DEK wrap key, asymmetric ECDSA signing keys
├── storage.tf                # Immutable audit checkpoint Cloud Storage bucket with Retention Policy
├── iam_bindings.tf           # Granular least-privilege IAM bindings and public-key viewers
└── terraform.tfvars.example  # Sanitized template configuration for sandbox execution
```

---

### 2. Multi-Layer Production Safety Gates

To fulfill Rule 10 ("Never assume the Google Cloud project or credentials are authorized simply because they exist on the development machine") and prevent production accidents, four independent barriers are codified:

#### Barrier 1: Naming Convention Regex Validation
```hcl
variable "sandbox_project_id" {
  type = string
  validation {
    condition     = can(regex("^(kelasagara|ks)-(sandbox|staging|dev|nonprod|test)-[a-z0-9]+$", var.sandbox_project_id))
    error_message = "ERROR: sandbox_project_id must match the non-production naming convention: 'kelasagara-(sandbox|staging|dev|nonprod|test)-<suffix>'."
  }
}
```

#### Barrier 2: Explicit Production Project Denylist
```hcl
  validation {
    condition     = !contains(["kelasagara-prod", "kelasagara-production", "kelasagaara_v17", "kelasagara-live"], var.sandbox_project_id)
    error_message = "CRITICAL SECURITY VIOLATION: Production project identifier detected in sandbox_project_id denylist! Deployment halted."
  }
```

#### Barrier 3: Environment Enum Restriction
```hcl
variable "environment" {
  type = string
  validation {
    condition     = contains(["sandbox", "staging", "dev", "test"], var.environment)
    error_message = "ERROR: environment must be one of: sandbox, staging, dev, test."
  }
}
```

#### Barrier 4: Null Resource Precondition Assertion
```hcl
resource "null_resource" "production_safety_gate" {
  lifecycle {
    precondition {
      condition     = !local.is_production_denied
      error_message = "CRITICAL SAFETY GATE: Production project deployment is strictly forbidden by KELASAGARA V20.14 policy."
    }
  }
}
```

---

### 3. Resource & Cryptographic Separation

#### 3.1 Cloud KMS Keyrings & CryptoKeys (`kms.tf`)
All cryptographic keys reside in a dedicated regional keyring (`biometric-identity-keyring-${var.environment}`) with `prevent_destroy = true`:
1. `biometric-dek-wrap-key`: Symmetric AES-256-GCM Hardware Security Module (HSM) key with 90-day automatic rotation.
2. `manifest-attestation-key`: Asymmetric ECDSA P-256 HSM key used by the Release Architect to sign canonical preprocessing manifests.
3. `audit-checkpoint-signing-key`: Asymmetric ECDSA P-256 HSM key used by `sa-biometrics-audit-notary` to sign external ledger checkpoints.

#### 3.2 Immutable Storage Bucket (`storage.tf`)
- Dedicated regional bucket `${var.sandbox_project_id}-biometric-audit-checkpoints`.
- Uniform bucket-level access enabled (`uniform_bucket_level_access = true`).
- Versioning enabled.
- Retention policy configured with `is_locked = false` in sandbox (to allow tear-down) and `is_locked = true` in production configurations.
- `prevent_destroy = true` lifecycle rule.

#### 3.3 IAM Role Bindings (`iam_bindings.tf`)
- **Enrollment (`sa-biometrics-enrollment`):** Granted `roles/cloudkms.cryptoKeyEncrypter` on DEK wrap key; **prohibited** from `roles/cloudkms.cryptoKeyDecrypter`.
- **Verifier (`sa-biometrics-verifier`):** Granted `roles/cloudkms.cryptoKeyDecrypter` on DEK wrap key; **prohibited** from `roles/cloudkms.cryptoKeyEncrypter` and write permissions.
- **Reviewer (`sa-biometrics-reviewer`):** Scoped to case updates; zero Cloud KMS permissions.
- **Inventory (`sa-biometrics-inventory`):** Read-only `roles/datastore.viewer`; zero write permissions, zero KMS access.
- **Audit Notary (`sa-biometrics-audit-notary`):** Granted `roles/storage.objectCreator` and `roles/cloudkms.signerVerifier`; **prohibited** from `storage.objects.delete`.

---

### 4. Verification Evidence

The static policy engine in `backend/src/services/iam_policy_verifier_v14.ts` and test suite `backend/src/tests/phase20_14_nonproduction_cloud_verification.test.ts` (Tests 11–13) verify that any attempt to pass a production project identifier or over-privileged role fails closed with explicit error messages.
