# KELASAGARA V20.16 — TERRAFORM PLAN POLICY ENFORCEMENT
## Layer 2 Pre-Deployment Plan Inspection and Deterministic Security Gates

**Author:** Principal Terraform Security Engineer, DevSecOps Architect  
**Date:** 2026-11-01  
**Repository:** `kelasagaara_v17`  
**Engine:** `backend/src/services/terraform_plan_policy_v16.ts`  
**Status:** ENFORCED AND TESTED AGAINST DETERMINISTIC FIXTURES  

---

### 1. Defect Analysis: Why HCL Syntax Validation is Not Enough

Static HCL validation (`terraform validate` and Layer 1 AST checking) evaluates source code syntax and schema conformance. However, static HCL validation has critical limitations:
1. **Dynamic Expressions:** HCL allows dynamic variables (`var.environment`), ternary expressions, and provider overrides whose values are only evaluated during plan generation.
2. **Resource-Level Overrides:** A resource block can specify `project = "kelasagara-prod"` even when the default provider block targets a sandbox project.
3. **Destructive Replacements:** Changing an immutable attribute (e.g. key ring location or KMS protection level) causes Terraform to plan a destructive recreation (`["delete", "create"]`), which could destroy live keys or buckets.
4. **Targeted Bypass:** An operator can run `terraform apply -target=google_service_account.foo`, bypassing safety assertions declared on other resources or modules.

To close these gaps, Phase 20.16 introduces **Layer 2 Plan Policy Enforcement** (`TerraformPlanPolicyEngine`), which parses and validates the complete Terraform Plan JSON (`terraform show -json`).

---

### 2. Layer 2 Plan Policy Verification Rules

```
+─────────────────────────────────────────────────────────────────────────────+
|                         TERRAFORM PLAN JSON PARSER                          |
+─────────────────────────────────────────────────────────────────────────────+
                                       │
        ┌──────────────────────────────┼──────────────────────────────┐
        │                              │                              │
        ▼                              ▼                              ▼
 [Plan Variables]            [Provider Configs]              [Resource Changes]
 • Reject prod variables     • Verify all provider aliases   • Check resource project
 • Reject denylist IDs       • Reject prod project configs   • Detect replacements
                                                             • Detect deletions
                                                             • Inspect IAM bindings
                                                             • Inspect retention locks
```

#### Detailed Rule Breakdown:
1. **`PLAN-POL-TARGET-GATE`:** Detects if the plan was generated using `-target`. Targeted plans are flagged because partial plans can circumvent holistic safety gates.
2. **`PLAN-POL-PROD-PROVIDER`:** Inspects all provider configurations and provider aliases (`configuration.provider_config`) to ensure zero production project references.
3. **`PLAN-POL-PROD-VARIABLE`:** Inspects all input variable values in the plan, rejecting denylisted production names.
4. **`PLAN-POL-RESOURCE-PROD-OVERRIDE`:** Inspects every planned resource's `change.after.project` attribute. If an individual resource attempts to override its project to a production identifier (`kelasagara-prod`, `kelasagaara_v17`, etc.), execution is immediately blocked.
5. **`PLAN-POL-PROTECTED-RESOURCE-DESTROY`:** Detects planned actions containing `delete` or replacement (`["delete", "create"]`) on protected resources (`google_kms_crypto_key`, `google_kms_key_ring`, `google_storage_bucket`, `google_firestore_database`).
6. **`PLAN-POL-BUCKET-LOCK-PROHIBITED`:** Scans planned storage buckets. If `is_locked === true` is detected in `retention_policy`, plan approval fails closed.
7. **`PLAN-POL-BUCKET-PUBLIC-ACCESS`:** Rejects any bucket lacking `public_access_prevention = "enforced"`.
8. **`PLAN-POL-KMS-HSM-MANDATE`:** Enforces `protection_level = "HSM"` on all Cloud KMS crypto keys. Downgrades to `SOFTWARE` are rejected.
9. **`PLAN-POL-IAM-WILDCARD`:** Rejects any IAM binding granting roles to `allUsers`, `allAuthenticatedUsers`, or wildcard principals `*`.
10. **`PLAN-POL-IAM-ADMIN-ROLE`:** Rejects any IAM binding granting `roles/owner` or `roles/editor`.

---

### 3. Deterministic Test Fixtures & Empirical Evidence

In `backend/src/tests/phase20_16_cloud_runtime_authorization.test.ts`, the Layer 2 engine was tested against deterministic plan fixtures:

| Test # | Plan Scenario Injected | Expected Rule Triggered | Result |
| :---: | :--- | :--- | :---: |
| **Test 15** | Variable `sandbox_project_id = "kelasagara-prod"` | `PLAN-POL-PROD-VARIABLE` | **PASS** (Blocked) |
| **Test 17** | Provider alias `google.prod_alias` with project `kelasagara-production` | `PLAN-POL-PROD-PROVIDER` | **PASS** (Blocked) |
| **Test 18** | Plan generated with `-target` flag | `PLAN-POL-TARGET-GATE` | **PASS** (Flagged) |
| **Test 19** | Planned action `delete` on `google_kms_crypto_key.dek_wrap` | `PLAN-POL-PROTECTED-RESOURCE-DESTROY` | **PASS** (Blocked) |
| **Test 21** | Resource `override_bucket` overriding `project = "kelasagara-prod"` | `PLAN-POL-RESOURCE-PROD-OVERRIDE` | **PASS** (Blocked) |
| **Test 22** | Planned IAM member granting `roles/owner` | `PLAN-POL-IAM-ADMIN-ROLE` | **PASS** (Blocked) |
| **Test 29** | Planned bucket update enabling `is_locked = true` | `PLAN-POL-BUCKET-LOCK-PROHIBITED` | **PASS** (Blocked) |

---

### 4. Integration with CI/CD Workflow

The plan policy engine executes in CI immediately after `tofu plan -out=tfplan.binary`:
```bash
# 1. Convert plan binary to canonical JSON
tofu show -json tfplan.binary > tfplan.json

# 2. Run Layer 2 Policy Inspection
node -e "
  const { TerraformPlanPolicyEngine } = require('./dist/services/terraform_plan_policy_v16');
  const plan = JSON.parse(require('fs').readFileSync('tfplan.json', 'utf8'));
  const engine = new TerraformPlanPolicyEngine();
  const res = engine.evaluatePlan(plan);
  if (!res.allPassed) {
    console.error('PLAN POLICY VIOLATIONS:', res.violations);
    process.exit(1);
  }
"
```
If any violation is detected, the pipeline aborts before any human approval prompt or apply step.

### 5. Conclusion

Layer 2 Plan Policy enforcement provides comprehensive pre-apply verification. Accidental resource destruction, production project overrides, and unauthorized IAM grants are intercepted at the plan stage before interacting with Google Cloud APIs.
