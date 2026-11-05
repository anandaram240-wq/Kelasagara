# KELASAGARA V20.16 — BUCKET RETENTION SEMANTICS AUDIT
## Unlocked 90-Day Retention, Deletion Safeguards, and Bucket Lock Prohibition

**Author:** Principal Cloud Storage Architect, Data Governance Auditor  
**Date:** 2026-11-01  
**Repository:** `kelasagaara_v17`  
**Configuration:** `infra/terraform/storage.tf`, `infra/terraform/variables.tf`  
**Status:** VALIDATED FAIL-SAFE CONFIGURATION  

---

### 1. Classification: Unlocked Retention Policy vs Immutable WORM Storage

In previous drafts, retention policies were sometimes loosely described as "immutable storage." Under strict storage engineering standards, this terminology is technically inaccurate and dangerous.

**Formal Classification in Phase 20.16:**
The Cloud Storage bucket declared in `infra/terraform/storage.tf` implements an **Unlocked 90-Day Bucket Retention Policy**:
```hcl
retention_policy {
  is_locked        = false # Must remain false in non-production sandbox
  retention_period = var.audit_retention_days * 86400 # 90 days (7,776,000s)
}
```

#### Why it is NOT Immutable WORM Storage:
1. **Unlocked State (`is_locked = false`):**
   - Objects placed in the bucket cannot be overwritten or deleted while the retention policy is active.
   - **However**, an authorized storage administrator (`roles/storage.admin`) possesses the technical ability to **modify, shorten, or completely remove** the retention policy from the bucket.
   - True immutable WORM (Write Once, Read Many) requires an irreversible **Bucket Lock** (`is_locked = true`), which permanently removes all administrative capabilities to alter or delete the retention policy.
2. **Operational Safeguard:**
   - Unlocked retention is intentional and mandatory for non-production environments. Applying an irreversible Bucket Lock in testing would permanently prevent bucket deletion, resulting in permanent resource leaks and billing liabilities.

---

### 2. Comprehensive Storage Safeguards Matrix

| Safeguard Feature | Configuration in `storage.tf` | Technical Enforcement | Security Benefit |
| :--- | :--- | :--- | :--- |
| **Unlocked Retention Duration** | `retention_period = 7776000` (90 days) | Cloud Storage Object Retention | Prevents accidental object deletion during normal operations for 90 days. |
| **Bucket Lock Disabled** | `is_locked = false` | Cloud Storage Policy Setting | Prevents permanent irreversible lock in test/sandbox environments. |
| **Safety Variable Constraint** | `var.allow_bucket_lock == false` | Terraform Variable Validation | Rejects any attempt to set `allow_bucket_lock = true` in non-prod. |
| **Public Access Block** | `public_access_prevention = "enforced"` | Google Cloud IAM & GCS | Prevents accidental bucket exposure to `allUsers` or `allAuthenticatedUsers`. |
| **Uniform Bucket-Level Access** | `uniform_bucket_level_access = true` | Cloud Storage Access Model | Disables object-level ACLs; enforces unified IAM policies across all objects. |
| **Object Versioning** | `versioning { enabled = true }` | GCS Object Versioning | Retains historical versions of updated objects for recovery. |
| **Destruction Protection** | `lifecycle { prevent_destroy = true }` | Terraform Client-Side Precondition | Blocks `tofu destroy` from deleting the bucket resource. |
| **Restricted Bucket IAM** | `roles/storage.objectCreator` only for Notary | IAM Member Binding | Notary can append new checkpoints; cannot delete or overwrite existing objects. |

---

### 3. Permissions Governing Retention Policy Updates

To ensure defense-in-depth, permissions to modify retention policies must be strictly separated:
- **`storage.buckets.setIamPolicy` & `storage.buckets.update`:** Restricted strictly to dedicated infrastructure deployment principals (`sa-terraform-sandbox-deployer`).
- **Application Services (`sa-biometrics-audit-notary`):** Granted **only `roles/storage.objectCreator`**. The notary cannot modify the bucket's retention policy, cannot delete objects, and cannot alter bucket metadata.
- **Reviewer & Verifier Services:** Granted `roles/storage.objectViewer` or zero bucket access.

---

### 4. Mandatory Human-Approved Procedure for Future Bucket Locking

In the event that Kelasagara advances to a regulated production environment requiring irreversible legal WORM compliance (e.g. SEC Rule 17a-4 or HIPAA legal holds), the following **human-approved multi-party procedure** is required:

1. **Written Executive Sign-Off:** Written authorization from the Data Protection Officer (DPO) and Chief Information Security Officer (CISO) certifying retention duration.
2. **Dedicated Production Project Verification:** Confirm the target is the genuine production project and not a development, staging, or sandbox bucket.
3. **Dedicated Pipeline with Break-Glass Controls:** Execute a separate, isolated Terraform run setting `allow_bucket_lock = true` and `is_locked = true` with dual-custody hardware key approval.
4. **Under no circumstances should automated test pipelines enable `is_locked = true`.**

---

### 5. Adversarial Test Evidence

In `backend/src/tests/phase20_16_cloud_runtime_authorization.test.ts`:
- **Test 28:** Proves bucket retention policy is classified as `is_locked = false` and not immutable WORM.
- **Test 29:** Proves plan policy engine strictly blocks `is_locked = true`.
- **Test 30:** Validates `public_access_prevention = "enforced"` and `uniform_bucket_level_access = true`.
- **Test 31:** Confirms `lifecycle { prevent_destroy = true }`.
- **Test 32:** Validates 90-day retention duration (`7776000s`).

### 6. Conclusion

Storage retention semantics are accurately defined. The audit ledger bucket provides robust retention against accidental deletion while strictly prohibiting irreversible bucket locks in non-production environments.
