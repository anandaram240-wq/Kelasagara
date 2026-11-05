# KELASAGARA V20.18 — PLAN AND CHECKPOINT ARTIFACT PRIVACY
## Minimizing Sensitive Data Disclosures Across CI/CD, Logs, and Manifests

**Author:** Principal Privacy Architect, Application Security Engineer  
**Date:** 2026-11-01  
**Repository:** `kelasagaara_v17`  
**Parent Commit:** `2233327` (`security/phase20.17-trusted-execution-provenance`)  
**Branch:** `security/phase20.18-pilot-readiness-corrections`  
**Status:** `ACTIVE_VERIFIED`  

---

### 1. Threat Model: Infrastructure State & Secret Disclosures

Terraform and OpenTofu plan files (`.tfplan`, `.binary`) and plan JSON outputs can contain:
- Unmasked plaintext credentials, initial admin passwords, and API keys.
- Internal IP topologies, subnet CIDRs, and service endpoint mappings.
- IAM policy bindings disclosing administrative email addresses.

If these artifacts are committed to Git repositories, retained indefinitely in CI artifact caches, or printed in CI execution logs, operational confidentiality is breached.

---

### 2. Concrete Privacy and Artifact Controls

Phase 20.18 establishes six concrete defenses:

1. **Restricted File Mode (POSIX `0600`):**
   When `TrustedPlanWrapperV18` writes the temporary plan binary (`tfplan-<timestamp>.binary`), it sets the file mode explicitly to `0o600` (read/write by owner only; zero access to other users or groups).
2. **Ephemeral JSON Lifecycle & Best-Effort Unlinking:**
   The rendered plan JSON used for Layer 2 policy evaluation is parsed in memory and **immediately unlinked** (`fs.unlinkSync()`) in an unconditional `finally` block.
   *(Note: The system honestly acknowledges that `unlinkSync()` deletes directory pointers and does not perform physical cryptographic wiping of underlying magnetic/flash media).*
3. **No Plaintext Secrets in Manifests:**
   The RFC 8785 execution provenance manifest references secrets strictly by their Cloud Secret Manager resource URI (`projects/.../secrets/...`). Plaintext variable values are never copied into the manifest.
4. **Log Redaction & Sanitization:**
   CI runners scrub stdout and stderr. Plan summaries output only high-level resource counts (`Plan: 3 to add, 0 to destroy`). Raw plan JSON is never streamed to build log storage.
5. **Git Exclusion Enforcement:**
   The repository `.gitignore` strictly blocks all `*.tfplan`, `*.plan`, `*.binary`, `*.tfstate`, and `.terraform/` paths.
6. **Immutable Audit Checkpoint Privacy:**
   Audit checkpoints in Cloud Storage contain SHA-256 event digests, sequence ranges, and timestamps. No raw biometric vectors, facial photographs, or unmasked PII are ever stored in audit checkpoints.
