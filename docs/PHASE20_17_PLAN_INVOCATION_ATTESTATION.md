# KELASAGARA V20.17 — PLAN INVOCATION ATTESTATION & CONTROLLED WRAPPER
## Architectural Defense Against Partial, Unrefreshed, and Destructive Infrastructure Changes

**Author:** Principal Cloud Security Architect, Terraform Security Auditor  
**Date:** 2026-11-01  
**Repository:** `kelasagaara_v17`  
**Parent Commit:** `bd1d5f57ee4ad1921e83f382ab67d06274a3fb2c`  
**Branch:** `security/phase20.17-trusted-execution-provenance`  
**Status:** `ACTIVE_VERIFIED`  

---

### 1. Executive Summary

In Terraform and OpenTofu environments, security policy evaluation typically happens on the output of `tofu show -json <planfile>`. However, a fundamental architectural vulnerability exists in this workflow: **the plan JSON format does not record the command-line invocation flags used to generate the plan**.

Specifically:
- An engineer or CI step can invoke `tofu plan -target=module.compute` or `tofu plan -exclude=module.iam`. The resulting plan file contains valid changes for the selected resources, but omits modifications or drift across all other resources.
- An invocation with `-refresh=false` prevents OpenTofu from querying live cloud APIs, producing a plan based on stale state that can overwrite out-of-band security configurations.
- An invocation with `-destroy` schedules wholesale resource deletion, which could bypass naive review if wrapped in complex change sets.
- An invocation with `-lock=false` bypasses state locking, risking concurrent apply race conditions and state corruption.

Phase 20.17 resolves this gap by implementing `TrustedPlanWrapperV17` (`backend/src/services/trusted_plan_wrapper_v17.ts`), a strictly controlled execution wrapper that intercepts and audits the physical CLI invocation parameters before spawning the OpenTofu binary.

---

### 2. The Command-Line Flag Blind Spot

OpenTofu's plan JSON schema (`resource_changes`, `configuration`, and `prior_state`) focuses exclusively on planned state transitions. It does not provide metadata regarding the execution context flags:

```json
{
  "format_version": "1.2",
  "terraform_version": "1.13.2",
  "resource_changes": [ ... ]
  // NOTICE: No record of whether -target, -exclude, or -refresh=false was supplied!
}
```

Because of this blind spot, a downstream CI/CD apply gate inspecting only the plan JSON cannot determine whether the plan represents a comprehensive, holistic evaluation of the infrastructure or a dangerously scoped partial execution.

---

### 3. Prohibited Command-Line Parameters

`TrustedPlanWrapperV17` evaluates the argument vector (`argv`) before process launch. The following flags are unconditionally rejected:

| Prohibited Argument | Security Rationale | Enforcement Code |
| :--- | :--- | :--- |
| `-target=<addr>` | Generates partial plans, leaving interdependent IAM or security controls unapplied. | `PLAN_ERR_TARGET_PROHIBITED` |
| `-target-file=<path>` | File-based targeting equivalent to `-target`. | `PLAN_ERR_TARGET_FILE_PROHIBITED` |
| `-exclude=<addr>` | Selectively excludes security monitoring, auditing, or IAM resources. | `PLAN_ERR_EXCLUDE_PROHIBITED` |
| `-exclude-file=<path>` | File-based exclusion equivalent to `-exclude`. | `PLAN_ERR_EXCLUDE_FILE_PROHIBITED` |
| `-destroy` | Wholesale destruction of infrastructure must never be initiated via standard plan workflows. | `PLAN_ERR_DESTROY_PROHIBITED` |
| `-refresh=false` | Disables cloud state reconciliation, risking silent overwrite of out-of-band fixes. | `PLAN_ERR_REFRESH_FALSE_PROHIBITED` |
| `-lock=false` | Disables state locking, allowing concurrent conflicting pipeline execution. | `PLAN_ERR_LOCK_FALSE_PROHIBITED` |
| `-replace=<addr>` | Ad-hoc resource recreation outside of declarative code changes. | `PLAN_ERR_REPLACE_PROHIBITED` |

---

### 4. Toolchain and Configuration Integrity Verification

Before invoking the plan command, the wrapper validates the cryptographic identity of the execution environment:

1. **Pinned Binary Identity:**
   - Physical binary path: `/Users/ananda/.gemini/antigravity/scratch/bin/tofu` (or symlinked `terraform`).
   - Binary SHA-256 Digest: `4513cc044f02edb4f50a4cbe992f8c915309bade302447a67ef10fdc976f221c`.
   - Toolchain Version: OpenTofu `v1.13.2`.
   - Any mismatch between the expected binary digest and the running executable halts execution immediately (`PLAN_ERR_ENGINE_INTEGRITY_MISMATCH`).

2. **Source Configuration Digest:**
   - Computes a deterministic SHA-256 digest over all `.tf` files in the working directory in lexicographical order.
   - Binds the plan to the exact HCL source tree.

3. **Dependency Lockfile Digest:**
   - Computes SHA-256 digest over `.terraform.lock.hcl`.
   - Ensures provider checksums have not drifted or been tampered with.

4. **Git Commit SHA:**
   - Extracts HEAD commit from git (`git rev-parse HEAD`).
   - Ensures plans generated from uncommitted or dirty branches cannot be applied in protected environments.

---

### 5. Plan Generation & Cryptographic Binding

When all preconditions are satisfied, `TrustedPlanWrapperV17.generateTrustedPlan()` executes:

```bash
tofu plan -out=<secure_ephemeral_path> -input=false -lock=true -refresh=true
```

Upon successful creation of the binary plan file:
1. The binary plan's exact SHA-256 digest (`savedBinaryPlanSha256`) is computed directly from disk.
2. The wrapper converts the plan to JSON via `tofu show -json <secure_ephemeral_path>` and computes `planJsonSha256`.
3. The Layer 2 `TerraformPlanPolicyEngine` evaluates the plan against organizational security rules.
4. An RFC 8785 execution provenance manifest is assembled, binding `savedBinaryPlanSha256`, the HCL digest, the lockfile digest, the commit SHA, and policy engine approval.
5. The manifest is signed with ECDSA P-256 / SHA-256 by the CI Plan Notary.

---

### 6. Apply Gate Verification (`verifyPlanForApply`)

During the deployment/apply phase, the CI apply worker invokes `TrustedPlanWrapperV17.verifyPlanForApply()`. The gate strictly enforces:
- The binary plan file matches `savedBinaryPlanSha256` bit-for-bit.
- The manifest signature is cryptographically valid against the trusted CI notary public key.
- The current git commit matches `gitCommitSha`.
- The current `.terraform.lock.hcl` matches `lockfileDigest`.
- The manifest has not exceeded its 2-hour maximum Time-To-Live (TTL).
- The embedded Layer 2 policy verdict is `APPROVED`.

Any failure rejects the apply operation before OpenTofu is invoked, guaranteeing that only authentic, fully-analyzed, and un-targeted plans can ever modify infrastructure.
