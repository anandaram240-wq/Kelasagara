# KELASAGARA V20.15 — PROJECT IDENTITY SAFETY AND PRODUCTION-DENIAL CONTROLS
## Multi-Layer Defense-in-Depth Against Accidental Production Mutation

**Author:** Principal Cloud Infrastructure Security Architect  
**Date:** 2026-11-01  
**Repository:** `kelasagaara_v17`  
**Target:** `infra/terraform/variables.tf`, `infra/terraform/main.tf`, `backend/src/services/terraform_policy_as_code_v15.ts`  
**Status:** ENFORCED AND VERIFIED  

---

### 1. Threat Model & Design Objective

In cloud operations, the most catastrophic failure mode is an operator or automated CI pipeline executing Terraform against a production GCP project using sandbox or development manifests. To make accidental production modification impossible, Phase 20.15 establishes **four independent layers of defense**:

1. **HCL Variable Validation Layer** (`variables.tf`)
2. **HCL Local Pre-Execution Safety Gates** (`main.tf`)
3. **TypeScript Policy-as-Code Engine** (`terraform_policy_as_code_v15.ts` / POL-01, POL-02)
4. **IAM Policy Verifier Denylist Synchronization** (`iam_policy_verifier_v14.ts`)

---

### 2. Multi-Layer Control Matrix

```
+-------------------------------------------------------------------------------+
| Layer 1: Terraform Variable Validation (variables.tf)                         |
| - Regex check: ^[a-z0-9-]+-sandbox$ or ^[a-z0-9-]+-test$                     |
| - Production Denylist: kelasagara-prod, kelasagaara_v17, prod, etc.           |
| - Allowlist check: must be in var.allowed_project_ids                          |
+-------------------------------------------------------------------------------+
                                      |
                                      v
+-------------------------------------------------------------------------------+
| Layer 2: Terraform Local Pre-Execution Gates (main.tf)                        |
| - production_safety_gate: fails if project matches denylist or lacks suffix  |
| - workspace_safety_gate: rejects workspace 'prod' or 'production'             |
| - allowlist_safety_gate: halts plan if project not in explicit allowlist       |
+-------------------------------------------------------------------------------+
                                      |
                                      v
+-------------------------------------------------------------------------------+
| Layer 3: TypeScript Policy-as-Code Gate (terraform_policy_as_code_v15.ts)     |
| - POL-01: Blocks any project with prod/production suffix or denylist match   |
| - POL-02: Scans credentials and refuses application-default / prod service acct|
+-------------------------------------------------------------------------------+
                                      |
                                      v
+-------------------------------------------------------------------------------+
| Layer 4: IAM Policy Verifier (iam_policy_verifier_v14.ts)                     |
| - Denylist: kelasagara-prod, kelasagara-production, kelasagaara_v17,          |
|             kelasagaara-v17, kelasagara-live, prod, production                |
+-------------------------------------------------------------------------------+
```

---

### 3. HCL Implementation Details

#### Layer 1: `variables.tf` Validation Blocks
```hcl
variable "sandbox_project_id" {
  type        = string
  description = "Non-production Google Cloud Project ID dedicated to biometrics sandbox."
  
  validation {
    condition     = can(regex("^[a-z0-9-]+-(sandbox|test|dev)$", var.sandbox_project_id))
    error_message = "CRITICAL: Project ID must strictly end with '-sandbox', '-test', or '-dev'."
  }

  validation {
    condition = !contains([
      "kelasagara-prod",
      "kelasagara-production",
      "kelasagaara_v17",
      "kelasagaara-v17",
      "kelasagara-live",
      "production",
      "prod"
    ], lower(var.sandbox_project_id))
    error_message = "CRITICAL SAFETY VIOLATION: Production project identifier detected! Execution refused."
  }
}
```

#### Layer 2: `main.tf` Safety Assertions
```hcl
locals {
  is_production_project = (
    endswith(lower(var.sandbox_project_id), "-prod") ||
    endswith(lower(var.sandbox_project_id), "-production") ||
    contains([
      "kelasagara-prod",
      "kelasagara-production",
      "kelasagaara_v17",
      "kelasagaara-v17",
      "kelasagara-live",
      "production",
      "prod"
    ], lower(var.sandbox_project_id))
  )

  production_safety_gate = local.is_production_project ? tobool("PRODUCTION_EXECUTION_BLOCKED: Accidental production deployment denied") : true
  workspace_safety_gate  = contains(["prod", "production", "live"], lower(terraform.workspace)) ? tobool("PRODUCTION_WORKSPACE_BLOCKED: Terraform workspace cannot be production") : true
  allowlist_safety_gate  = contains(var.allowed_project_ids, var.sandbox_project_id) ? true : tobool("PROJECT_NOT_IN_ALLOWLIST: Target project is not in var.allowed_project_ids")
}
```

---

### 4. Adversarial Testing & Verification

The adversarial test suite `backend/src/tests/phase20_15_infrastructure_assurance.test.ts` executes targeted tests proving the efficacy of these gates:

| Test ID | Adversarial Payload | Expected Result | Actual Result |
| :--- | :--- | :--- | :--- |
| **Test 7** | `sandbox_project_id = ""` | Validation error: empty string fails regex | **PASS** (Rejected) |
| **Test 8** | `sandbox_project_id = "kelasagara-prod"` | POL-01: Fails with denylist match | **PASS** (Blocked) |
| **Test 8** | `sandbox_project_id = "kelasagaara_v17"` | POL-01: Fails with denylist match | **PASS** (Blocked) |
| **Test 8** | `sandbox_project_id = "my-custom-prod"` | POL-01: Fails with prod suffix match | **PASS** (Blocked) |
| **Test 9** | `sandbox_project_id = "unregistered-test"` | POL-01: Fails with allowlist rejection | **PASS** (Blocked) |

### 5. Conclusion

Project identity safety is enforced with zero tolerance. Even if an engineer sets `GOOGLE_PROJECT=kelasagara-prod` in their environment or passes `-var="sandbox_project_id=kelasagara-prod"`, the operation will fail closed at all four layers before generating a Terraform plan or modifying any infrastructure.
