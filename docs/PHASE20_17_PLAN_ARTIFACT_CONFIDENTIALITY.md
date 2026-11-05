# KELASAGARA V20.17 — TERRAFORM PLAN ARTIFACT CONFIDENTIALITY & LIFECYCLE
## Safeguarding Binary and JSON Plan Artifacts Across CI/CD and Developer Environments

**Author:** Principal Application Security Architect, DevSecOps Engineer  
**Date:** 2026-11-01  
**Repository:** `kelasagaara_v17`  
**Parent Commit:** `bd1d5f57ee4ad1921e83f382ab67d06274a3fb2c`  
**Branch:** `security/phase20.17-trusted-execution-provenance`  
**Status:** `ACTIVE_VERIFIED`  

---

### 1. The Threat of Terraform Plan Data Leakage

Terraform binary plan files (`tfplan.binary`) and rendered plan JSON files (`tfplan.json`) contain the complete state diff of the planned infrastructure. This includes:
- Plaintext configuration values.
- Sensitive resource arguments (e.g. initial administrator passwords, connection strings, private API keys, TLS private keys, IAM service account keys).
- Detailed infrastructure topologies and internal network CIDRs.

If these artifacts are committed to Git, stored in world-readable build caches, or printed in CI logs upon error, critical operational secrets become compromised.

---

### 2. Comprehensive Repository-Level Git Exclusion

The repository `.gitignore` has been hardened to ensure no plan artifacts, state files, or sensitive crash dumps can be accidentally tracked:

```gitignore
# Terraform & OpenTofu Plan and State Artifacts
*.tfplan
*.tfplan.*
*.plan
*.binary
tfplan*
plan.json
*.tfstate
*.tfstate.*
*.tfstate.backup
.terraform/
.terraform.tfstate.lock.info
crash.log
crash.*.log
```

Automated pre-commit hooks verify that no file matching these patterns is staged.

---

### 3. Ephemeral File Lifecycle & In-Memory Processing

`TrustedPlanWrapperV17` strictly controls the creation and lifecycle of temporary plan files:

1. **Restricted File Permissions:**
   Temporary files are created in isolated directories with POSIX permissions `0600` (read/write by owner only; zero group or world access).
2. **Ephemeral JSON Policy Evaluation:**
   When generating the plan JSON for policy evaluation (`tofu show -json <binary_path>`), the wrapper writes to a temporary file, computes `planJsonSha256`, executes policy analysis in memory, and **immediately unlinks the JSON file** (`fs.unlinkSync()`).
3. **Immediate Cleanup on Failure:**
   All execution paths (success, validation error, process exit, or unhandled rejection) are wrapped in `try ... finally` blocks that guarantee the deletion of ephemeral plan files.

```typescript
try {
  // Execute policy evaluation on ephemeral JSON
  const verdict = await policyEngine.evaluate(planJson);
  return { manifest, signature };
} finally {
  if (fs.existsSync(ephemeralJsonPath)) {
    fs.unlinkSync(ephemeralJsonPath);
  }
}
```

---

### 4. CI/CD Output Sanitization & Redaction

CI/CD runners executing `TrustedPlanWrapperV17` implement strict output filtering:
- **Environment Variable Masking:** All variables prefixed with `TF_VAR_`, `GCP_`, or `SECRET_` are automatically masked as `[REDACTED]` in CI logs.
- **Error Stack Sanitization:** If an OpenTofu command fails, stdout and stderr are scrubbed for sensitive patterns (passwords, tokens, wrapped keys) before being logged.
- **No Full Plan JSON in Logs:** CI logs report only the plan summary (e.g., `Plan: 3 to add, 1 to change, 0 to destroy`) and the cryptographic digests from the provenance manifest (`savedBinaryPlanSha256: 6a9e1e...`). The raw JSON is never streamed to build log storage.
