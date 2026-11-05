# KELASAGARA V20.18 — EFFECTIVE OPENTOFU EXECUTION ENVIRONMENT
## Environment Containment, Executable Integrity, and Injection Defense

**Author:** Principal Cloud Security Architect, DevSecOps Systems Auditor  
**Date:** 2026-11-01  
**Repository:** `kelasagaara_v17`  
**Parent Commit:** `2233327` (`security/phase20.17-trusted-execution-provenance`)  
**Branch:** `security/phase20.18-pilot-readiness-corrections`  
**Status:** `ACTIVE_VERIFIED`  

---

### 1. The Environment Injection Vulnerability in OpenTofu & Terraform

In earlier phases, the controlled plan wrapper inspected only the process command-line arguments array (`argv`). However, OpenTofu and Terraform can alter their runtime behavior through environment variables and local configuration files:

- `TF_CLI_ARGS`, `TF_CLI_ARGS_plan`, `TF_CLI_ARGS_apply`: Silently inject command flags (e.g. `-target=...`, `-destroy`) without appearing in `argv`.
- `TF_WORKSPACE`: Overrides the active workspace, potentially pointing an unapproved execution to `production`.
- `TF_CLI_CONFIG_FILE` / `.terraformrc`: Overrides provider mirrors and installations with untrusted local binaries.
- `TF_DATA_DIR`: Diverts state caching and provider download directories.
- Unapproved `TF_VAR_*`: Injects unverified variables bypassing CI parameter validation.

---

### 2. Implementation: `TrustedPlanWrapperV18` Environment Control

`TrustedPlanWrapperV18` (`backend/src/services/trusted_plan_wrapper_v18.ts`) implements strict environment sandboxing before spawning OpenTofu:

1. **Absolute Executable Path Without Shell:**
   The wrapper resolves the approved OpenTofu binary directly (`/Users/ananda/.gemini/antigravity/scratch/bin/tofu`) and invokes it using `child_process.spawnSync` with `shell: false`. This eliminates shell interpolation, globbing, and argument injection vulnerabilities.
2. **Binary Digest Attestation:**
   Before execution, the file hash is asserted against `APPROVED_TOFU_BINARY_HASH`:
   `4513cc044f02edb4f50a4cbe992f8c915309bade302447a67ef10fdc976f221c`.
   Any mismatch immediately aborts execution with `ERR_TOOLCHAIN_INTEGRITY_MISMATCH`.
3. **Explicit Environment Allowlist:**
   The wrapper strips all unapproved environment variables, permitting strictly:
   - `PATH` (sanitized safe paths only)
   - `HOME`
   - `TMPDIR`
   - `USER`
   - `LANG`, `LC_ALL`
   - `TF_VAR_sandbox_project_id` (explicitly approved variables only)
4. **Unconditional Rejection of Prohibited Variables:**
   If `TF_CLI_ARGS`, `TF_CLI_ARGS_plan`, `TF_CLI_ARGS_apply`, `TF_WORKSPACE`, `TF_CLI_CONFIG_FILE`, `TF_DATA_DIR`, or unapproved `TF_VAR_*` are present, execution is rejected immediately with `ERR_PROHIBITED_ENV_VAR` or `ERR_UNAPPROVED_TF_ENV_VAR`.
5. **Alternate Configuration File Detection:**
   The presence of `.terraformrc` or `terraform.rc` in the terraform directory aborts the plan with `ERR_ALTERNATE_CLI_CONFIG`.
6. **Workspace Fencing:**
   Only approved workspaces (`sandbox`, `default`) are permitted. Production workspace values (`prod`, `production`) are blocked with `ERR_UNAPPROVED_WORKSPACE`.

---

### 3. Verification Evidence

Verified in automated adversarial test suite:
- Test 1: Injected `TF_CLI_ARGS_plan` rejected (`ERR_PROHIBITED_ENV_VAR`).
- Test 2: Injected workspace (`prod`) rejected (`ERR_UNAPPROVED_WORKSPACE`).
- Test 3: Alternate `.terraformrc` config rejected (`ERR_ALTERNATE_CLI_CONFIG`).
- Test 4: Unexpected `TF_VAR_injected_admin_override` rejected (`ERR_UNAPPROVED_TF_ENV_VAR`).
- Test 5: Unapproved CLI flag (`-target`) rejected (`ERR_PROHIBITED_CLI_FLAG`).
- Test 8: Different executable digest rejected by apply gate (`ERR_TOOLCHAIN_MISMATCH`).
