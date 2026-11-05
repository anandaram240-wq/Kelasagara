# KELASAGARA V20.16 — PRODUCTION DENIAL LIMITATIONS AUDIT
## Honest Assessment of Repository Policy Scope vs Google Cloud Organization Controls

**Author:** Principal Cloud Infrastructure Security Architect, IAM Auditor  
**Date:** 2026-11-01  
**Repository:** `kelasagaara_v17`  
**Status:** ARCHITECTURAL RISK ASSESSMENT COMPLETE  

---

### 1. The Core Principle: Repository Guards Are Client-Side Controls

The Phase 20.15 report documented four internal protection layers (HCL validation, compile-time assertions, Policy-as-Code, and verifier denylists). 

While these client-side controls prevent accidental execution within the standard repository workflow, **it is a dangerous security anti-pattern to claim that repository-level Terraform guards make production changes technically impossible**.

This report provides an honest, rigorous analysis of potential bypass vectors and delineates what is enforced by repository code versus what **mandatorily requires Google Cloud Organization Policies and Cloud IAM boundaries**.

---

### 2. Comprehensive Bypass Vector Analysis

| Attack / Bypass Vector | Can Client-Side Repository Policy Block It? | How It Can Bypass Repository Policy | Mandatory Cloud-Level Mitigation Required |
| :--- | :---: | :--- | :--- |
| **1. `terraform apply -target`** | **PARTIALLY** (Flagged in Layer 2 plan policy) | An operator running raw CLI locally can bypass `null_resource` preconditions if those preconditions are not in the targeted graph. | Cloud IAM: Enforce approval gate; restrict deployer permissions. |
| **2. `terraform destroy`** | **YES** (via `lifecycle { prevent_destroy = true }`) | `prevent_destroy` prevents Terraform from destroying the resource, but does NOT prevent destruction via Cloud Console or `gcloud`. | Cloud IAM: Deny `*.delete` and `*.destroy` permissions on service accounts. |
| **3. Workspace Switching** | **YES** (Layer 1 rejects `prod`/`production` workspaces) | An operator could name a workspace `sandbox-override` while configuring variables pointing to production. | Organization Policy: Strict project-level IAM boundary. |
| **4. Provider Aliases** | **YES** (Layer 2 plan policy validates all provider configs) | Multiple provider blocks declared in alternate files targeting production. | Layer 2 Plan Policy & CI Pipeline validation. |
| **5. Resource-Level Project Overrides** | **YES** (Layer 2 plan policy inspects every resource `project`) | A resource block defining `project = "kelasagara-prod"` while provider targets sandbox. | Layer 2 Plan Policy Engine. |
| **6. Alternate Configuration Directories** | ❌ **NO** | An operator runs Terraform from a separate unverified directory on their machine targeting production. | **Google Cloud IAM & VPC Service Controls**. |
| **7. Alternate State Backends** | **PARTIALLY** (Layer 1 & 2 reject prod state buckets) | Operator configures a local or external backend pointing to production resources. | Cloud KMS & GCS IAM: Dedicated production KMS key access denied to non-prod principals. |
| **8. Direct Cloud API / `gcloud` Calls** | ❌ **NO** (Completely outside Terraform scope) | An engineer runs `gcloud kms keys versions destroy` or `gcloud firestore databases delete`. | **GCP IAM Least-Privilege & Organization Policies**. |
| **9. Manual Cloud Console Mutations** | ❌ **NO** (Completely outside Terraform scope) | Operator logs into GCP Web Console and clicks "Delete" on database or bucket. | **GCP IAM Conditional Roles & Privileged Access Management (PAM)**. |
| **10. Source Code Policy Engine Modification** | ❌ **NO** (Locally) | A rogue developer modifies `terraform_plan_policy_v16.ts` locally to disable checks. | **GitHub Protected Branches & CI Server Branch Rules** (Enforces clean upstream policy). |

---

### 3. Clear Delineation: Repository Scope vs Organization Scope

```
+─────────────────────────────────────────────────────────────────────────────+
|                         REPOSITORY POLICY BOUNDARY                          |
| Enforced by: OpenTofu CLI, HCL Preconditions, TypeScript Policy Engine      |
| • Variable regex and denylist checking                                      |
| • Provider version pinning (5.20.0)                                         |
| • Plan JSON resource inspection (project override detection)               |
| • Prohibition of wildcards and owner/editor roles in IaC                    |
| • Rejection of Bucket Lock in sandbox configurations                        |
| • Automated blocking of CI PR merges on policy failure                      |
+─────────────────────────────────────────────────────────────────────────────+
                                       │
            CANNOT PREVENT OUT-OF-BAND ATTACKS WITHOUT:
                                       │
                                       ▼
+─────────────────────────────────────────────────────────────────────────────+
|                    GOOGLE CLOUD ORGANIZATION BOUNDARY                       |
| Enforced by: GCP Organization Policies, IAM Policies, VPC Service Controls |
| • constraints/iam.disableServiceAccountKeyCreation (Blocks JSON key creation)|
| • constraints/gcp.resourceLocations (Pins resources to in-region locations) |
| • Multi-party approval (PAM) for destructive IAM grants                    |
| • Dedicated GCP Project Isolation (Separate billing & organization folders) |
| • VPC Service Controls: Service perimeters blocking cross-project data egress|
+─────────────────────────────────────────────────────────────────────────────+
```

---

### 4. Mandatory Google Cloud Organization Policies Required for Production

Before any future production deployment, the Google Cloud Organization Administrator must enforce the following Organization Policy Constraints:

1. **`constraints/iam.disableServiceAccountKeyCreation`**: Enforced on the entire organization folder. Prevents any engineer from generating downloadable JSON private keys.
2. **`constraints/storage.uniformBucketLevelAccess`**: Enforced organization-wide. Prohibits fine-grained ACLs on all storage buckets.
3. **`constraints/storage.publicAccessPrevention`**: Enforced on all non-public folders. Prevents accidental public exposure of buckets.
4. **`constraints/cloudkms.allowedProtectionLevels`**: Restricts Cloud KMS key creation to `HSM` only.
5. **Separate GCP Projects**: Production (`kelasagara-prod`), Staging (`kelasagara-staging`), and Sandbox (`kelasagara-sandbox`) must reside in **separate Google Cloud projects under separate billing accounts and IAM permission boundaries**. A developer with editor access to sandbox must possess zero credentials in production.

### 5. Conclusion

Repository-level policy guards provide essential automated guardrails against developer mistakes and CI misconfigurations. However, genuine production isolation ultimately relies on Google Cloud Organization Policies, IAM role separation, and separate project perimeters.
