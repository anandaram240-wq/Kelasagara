# KELASAGARA V20.16 — TOOLCHAIN IDENTITY AUDIT
## Disambiguation of OpenTofu v1.13.2 vs HashiCorp Terraform and Verification Run

**Author:** Principal Cloud Infrastructure Security Architect, Tooling Auditor  
**Date:** 2026-11-01  
**Repository:** `kelasagaara_v17`  
**Host Architecture:** `darwin_arm64` (Apple Silicon Mac)  
**Status:** EXHAUSTIVELY AUDITED & VERIFIED  

---

### 1. Executive Summary: Disambiguation of `terraform` vs `tofu`

The Phase 20.15 report referenced both OpenTofu v1.13.2 and `terraform`. A forensic binary audit of the host environment was conducted to resolve this ambiguity and determine the exact toolchain executing configuration commands.

**Forensic Finding:**
On this host, `/opt/homebrew/bin/terraform` is **not a distinct HashiCorp Terraform binary**. It is an explicit symbolic link pointing directly to OpenTofu v1.13.2:
```text
/opt/homebrew/bin/terraform -> /opt/homebrew/bin/tofu
/opt/homebrew/bin/tofu -> ../Cellar/opentofu/1.13.2/bin/tofu
```

HashiCorp Terraform (BSL/commercial binary) is not separately installed on this system. **OpenTofu v1.13.2** is the officially installed, supported, and validated tool for this repository. Both `tofu` and `terraform` invoke the identical underlying OpenTofu binary.

---

### 2. Binary Inventory & Cryptographic Checksums

| Invocation Command | Target Path | Symlink Resolution | Physical Executable Path | SHA-256 Checksum |
| :--- | :--- | :--- | :--- | :--- |
| `terraform` | `/opt/homebrew/bin/terraform` | `-> /opt/homebrew/bin/tofu` | `/opt/homebrew/Cellar/opentofu/1.13.2/bin/tofu` | `4513cc044f02edb4f50a4cbe992f8c915309bade302447a67ef10fdc976f221c` |
| `tofu` | `/opt/homebrew/bin/tofu` | `-> ../Cellar/opentofu/1.13.2/bin/tofu` | `/opt/homebrew/Cellar/opentofu/1.13.2/bin/tofu` | `4513cc044f02edb4f50a4cbe992f8c915309bade302447a67ef10fdc976f221c` |

#### Version Outputs:
```bash
$ terraform version
OpenTofu v1.13.2
on darwin_arm64

$ tofu version
OpenTofu v1.13.2
on darwin_arm64
```

---

### 3. Provider Lockfile Integrity (`infra/terraform/.terraform.lock.hcl`)

The dependency lock file pins both providers with official developer-signed checksums:
- **`hashicorp/google`:** Pinned to exact version `5.20.0`
- **`hashicorp/null`:** Pinned to version `3.3.2`

Both OpenTofu and HashiCorp Terraform use the identical lockfile format and HCL schema specifications for `hashicorp/google v5.20.0`.

---

### 4. Canonical Verification Execution Using Direct `tofu` Binary

To establish baseline determinism without relying on the symlink, all verification commands were re-executed using the explicit `tofu` binary:

#### A. Formatting Check (`tofu fmt -check -recursive`)
```bash
$ cd /Users/ananda/KELASAGARA\ MAJOR\ PROJECT/kelasagaara_v17/infra/terraform
$ tofu fmt -check -recursive
```
- **Exit Code:** `0`
- **Standard Output:** (Empty — all files are canonical HCL)
- **Status:** PASS

#### B. Initialization with Backend Disabled (`tofu init -backend=false`)
```bash
$ tofu init -backend=false
```
- **Exit Code:** `0`
- **Standard Output:**
  ```text
  Initializing provider plugins...
  - Reusing previous version of hashicorp/null from the dependency lock file
  - Reusing previous version of hashicorp/google from the dependency lock file
  - Using previously-installed hashicorp/null v3.3.2
  - Using previously-installed hashicorp/google v5.20.0

  OpenTofu has been successfully initialized!
  ```
- **Status:** PASS

#### C. Configuration Validation (`tofu validate`)
```bash
$ tofu validate
```
- **Exit Code:** `0`
- **Standard Output:** `Success! The configuration is valid.`
- **Status:** PASS

---

### 5. Repository Policy Decision

**Decision:** OpenTofu v1.13.2 is officially designated as the supported IaC execution engine for `kelasagaara_v17`. The symlink `/opt/homebrew/bin/terraform -> /opt/homebrew/bin/tofu` is retained for compatibility with automated scripts or IDE plugins that expect the `terraform` CLI name, but all documentation and CI configurations must record OpenTofu as the underlying engine.
