# PHASE 20.19: COMPLETE PLAN INPUT ATTESTATION, VARIABLE PRECEDENCE & ARTIFACT PROTECTION

## 1. Threat Model & Architectural Integrity

### 1.1 Complete Configuration and Variable Scope
In standard Terraform / OpenTofu workflows, plan generation must capture every configuration element that influences the planned resource actions:
1. Root module configuration files (`.tf`, `.tf.json`, `.tofu`, `.tofu.json`)
2. All local module source trees (`modules/*`)
3. All downloaded remote module source trees (`.terraform/modules/*`) and exact version / immutable commit references
4. Actual backend configuration (`backend.tf`, `backend.tofu`, etc.) and all `-backend-config` files and settings
5. OpenTofu dependency lock file (`.terraform.lock.hcl`) and provider checksums
6. Variable definitions files (`terraform.tfvars`, `terraform.tfvars.json`, `*.auto.tfvars`, `*.auto.tfvars.json`, `*.tfvars`, `*.tfvars.json`)
7. CLI `-var` and `-var-file` options in actual command-line invocation order
8. Approved environment variables (`TF_VAR_*`)
9. OpenTofu toolchain binary identity (executable path, version, and SHA-256 binary hash)
10. Workspace identity and state lineage / serial version

> [!CAUTION]
> **Operating System Process Argument Exposure:**
> Passing secrets directly as command-line arguments (e.g. `-var="secret=supersecret"`) exposes plaintext secrets in the operating system process table (`/proc/<pid>/cmdline`, `ps aux`), readable by any local process with the same UID or root.
> While `TrustedPlanWrapperV19` redacts sensitive keys in the audit manifest (`[REDACTED_SECRET]`), **manifest sanitization does not eliminate OS-level command-line argument exposure**.
> Therefore, sensitive credentials must never be passed via process command-line arguments; they must be referenced exclusively via immutable Secret Manager resource URIs (`projects/.../secrets/.../versions/<num>`).

### 1.2 Prohibited Environment Variables & Unapproved Argument Injection
OpenTofu and Terraform support environment variables that can silently inject arguments, override workspaces, or alter execution paths outside command-line view. `TrustedPlanWrapperV19` explicitly audits, blocks, and rejects the following environment variables:
- `TF_CLI_ARGS` / `TOFU_CLI_ARGS`: Silently injects global CLI flags into all subcommands.
- `TF_CLI_ARGS_plan` / `TOFU_CLI_ARGS_plan`: Silently injects CLI flags into `plan` executions.
- `TF_CLI_ARGS_apply` / `TOFU_CLI_ARGS_apply`: Silently injects CLI flags into `apply` executions (e.g. attempting to inject `-auto-approve`).
- `TF_WORKSPACE` / `TOFU_WORKSPACE`: Silently switches workspaces behind the wrapper's back.
- `TF_CLI_CONFIG_FILE` / `TOFU_CLI_CONFIG_FILE`: Specifies an alternate CLI configuration file with unvetted provider registries or credentials.
- `TF_DATA_DIR` / `TOFU_DATA_DIR`: Overrides the data directory where plugins and state caches reside.
- `TF_ENCRYPTION` / `TOFU_ENCRYPTION`: Injects unvetted external state encryption configuration.

Any execution attempting to pass these prohibited variables fails closed immediately with `ERR_PROHIBITED_TF_ENV_VAR`.
Furthermore, all non-allowlisted environment variables are stripped via `APPROVED_ENV_ALLOWLIST`, ensuring an approved manifest cannot be reused in a modified execution environment.

---

## 2. Phase 20.19 Implementation: Comprehensive Input Coverage

`TrustedPlanWrapperV19` (`backend/src/services/trusted_plan_wrapper_v19.ts`) comprehensively hashes, binds, and evaluates all execution inputs:

### 2.1 Complete Configuration Files Coverage
- Root configurations matching `.tf`, `.tf.json`, `.tofu`, `.tofu.json` are hashed lexicographically into `configFilesDigest`.
- Temporary state files, backup files, and `.tfplan` binaries are explicitly excluded.

### 2.2 Complete Module Source Tree Hashing
Rather than relying solely on `.terraform/modules/modules.json`:
- **Recursive Source Tree Hashing:** `getDirectoryTreeDigest()` walks every file in downloaded remote module directories (`.terraform/modules/<name>/...`) and local module directories (`modules/<name>/...`), hashing relative paths and file contents into `moduleSourceDigests`.
- **Exact Remote References:** Reads `.terraform/modules/modules.json` to bind exact module `Source` and `Version` / commit references.

### 2.3 Actual Backend Configuration & `-backend-config` Settings
- `parseBackendConfig()` discovers and hashes root backend definitions (`backend.tf`, `backend.tofu`, `backend.tf.json`, `backend.tofu.json`).
- Parses CLI `-backend-config` parameters: hashes external backend configuration files and records non-secret CLI settings into `backendConfigDigest`.

### 2.4 Exact OpenTofu Variable Precedence Engine
All variable sources are cataloged in `effectiveVariableSources` and evaluated via `resolveEffectiveVariables()` in the exact canonical OpenTofu order:
```text
1. TF_VAR environment variables.
2. terraform.tfvars.
3. terraform.tfvars.json.
4. *.auto.tfvars and *.auto.tfvars.json in lexical order.
5. All CLI -var and -var-file inputs in their actual invocation order.
```

> [!IMPORTANT]
> **CLI Invocation Order Rule:** OpenTofu does NOT assume that `-var` always overrides `-var-file`. All CLI `-var` and `-var-file` arguments are processed sequentially in their actual invocation order:
> - If `-var` precedes `-var-file`, the later `-var-file` overrides the `-var`.
> - If `-var-file` precedes `-var`, the later `-var` overrides the `-var-file`.
>
> `resolveEffectiveVariables()` implements this exact sequence and records granular layer provenance (`resolutionProvenance`) for every resolved variable.

### 2.5 Immutable Secret Manager Version Enforcement
To ensure secret inputs cannot be silently mutated between plan and apply:
- **Numeric Version Requirement:** Only explicit positive numeric versions (`projects/<proj>/secrets/<name>/versions/<1, 2, ...>`) are permitted.
- **Rejection of Mutable Aliases:** Any reference utilizing `latest` or mutable aliases (e.g., `active`, `staging`, `prod`) is strictly rejected with `ERR_MUTABLE_SECRET_VERSION`.
- **Rejection of Unversioned References:** Unversioned secret references (`projects/<proj>/secrets/<name>`) are rejected with `ERR_UNVERSIONED_SECRET_REFERENCE`.
- **Manifest Binding:** Validated numeric version bindings are recorded in `manifest.immutableSecretBindings` and bound cryptographically to the plan approval.

### 2.6 Secret Attestation Threat Model: Salted SHA-256 Review vs Protected Keyed HMAC
A rigorous cryptographic review of input secret attestation mechanisms was conducted to identify vulnerabilities in conventional salted hashing:

#### 2.6.1 Vulnerabilities of Unkeyed Salted SHA-256 Fingerprints
1. **Low-Entropy Guessing & Offline Brute-Force Attacks:**
   - If an input secret has moderate or low entropy (e.g. short API tokens, standard passphrases, numeric pins, database passwords), standard SHA-256 hashing—even with a salt—allows an adversary who gains access to the attestation manifest or commit log to mount high-speed offline dictionary or brute-force attacks using commodity GPU/ASIC hardware ($>10^{10}$ hashes/second).
2. **Equality Leakage Across Environments and Plans:**
   - If a static, global, or deterministic salt is used across environments (e.g. sandbox vs staging vs production) or across successive plans, identical secrets produce identical fingerprints. An attacker observing matching hashes immediately learns that different environments or services share identical credentials, violating environment isolation boundaries.
3. **Salt Exposure Risk:**
   - If the salt is stored in the publicly committed or shared attestation manifest alongside the hash, the cryptographic defense collapses to simple unkeyed hashing with zero secret protection. An attacker needs no privileges beyond reading the manifest.

#### 2.6.2 Protected Keyed Attestation Mechanism (HMAC-SHA256)
To eliminate these vulnerabilities, Phase 20.19 implements a protected, keyed attestation mechanism:
- **Keyed Cryptographic Boundary:** Fingerprints are computed using HMAC-SHA256 initialized with a 256-bit cryptographic secret key managed exclusively by `ProtectedHmacKeyManagerV19` (backed by Cloud KMS in non-production cloud environments).
- **Offline Attack Prevention:** Without access to the protected HMAC key, an adversary possessing the manifest cannot compute candidate hashes, mathematically precluding offline dictionary, rainbow table, and brute-force attacks ($2^{256}$ search space).
- **Zero Plaintext Persistence:** Plaintext secret values are processed strictly in transient volatile memory, never recorded in attestation manifests, never logged to stdout/stderr, and immediately garbage-collected. Only the keyed HMAC digest, bound key identifier, and key version are persisted.
- **Untrusted Override Defense:** Untrusted API callers cannot supply or override `secretFingerprintHmacKey`. Invocations attempting untrusted key override fail immediately with `ERR_UNTRUSTED_HMAC_KEY_OVERRIDE`.
- **Independent Key Management & Manifest Provenance:** `ProtectedHmacKeyManagerV19` maintains trusted key identifiers (`kms://projects/kelasagara-kms/cryptoKeys/plan-secret-hmac`), numeric versions, and historical keystores. Execution provenance manifests bind `hmacKeyIdentifier` and `hmacKeyVersion`.
- **Rotation Invalidation Policy:** Under the default `STRICT_ACTIVE_ONLY` policy, rotating the HMAC key immediately invalidates stale approvals (`ERR_HMAC_KEY_ROTATED_APPROVAL_INVALID`). Under `PERMIT_AUTHORIZED_HISTORICAL_VERSIONS`, only explicitly authorized, unrevoked historical versions are permitted. Stale or revoked keys are strictly blocked.

### 2.7 OpenTofu Plan Encryption At Rest & Storage Realities
- **Native Plan Encryption At Rest:** Plan binaries are never stored as plaintext on disk. `TrustedPlanWrapperV19` encrypts saved binary plans using authenticated AES-256-GCM under container format `KSEP_V19` managed by `PlanEncryptionKeyManagerV19`.
- **Zero Plaintext Persistence:** The file written to disk contains strictly the encrypted container with 96-bit IV, 128-bit authentication tag, and Base64 ciphertext. Plaintext configuration strings, secret variables, and resource attributes never hit disk.
- **Key Rotation with Historical Key Recovery:** `PlanEncryptionKeyManagerV19` maintains key version histories. When the active key is rotated to version 2, plans generated under version 1 can still be decrypted at the apply gate via authorized historical key recovery. Explicitly revoked keys fail closed.
- **Anti-Plaintext Enforcement:** Presenting an unencrypted plaintext plan binary to `verifyPlanForApply()` is caught fail-closed and rejected with `ERR_UNENCRYPTED_PLAN_AT_REST`.
- **Memory Hygiene in Finally Blocks:** Decrypted plan buffers in memory are wiped using `crypto.randomFillSync()` inside guaranteed `finally` execution blocks.
- **Restricted Filesystem Permissions:** Saved plan files are written with POSIX mode `0o600` (read/write by owner only; zero access to group/others) in directories secured with `0o700`.
- **Encrypted Transit Storage:** When plan artifacts leave the execution host (e.g. CI runners or external stores), `encryptPlanArtifactForTransit()` applies AES-256-GCM envelope encryption with unique 96-bit nonces and 128-bit authentication tags.
- **Git Commit Prevention:** Root and infrastructure `.gitignore` rules strictly exclude `*.tfplan`, `*.tfplan.*`, `*.binary`, and `tfplan-*` patterns.
- **Log Masking:** Plan JSON and variable payloads are never dumped in plaintext into ordinary logs or error messages; all sensitive values are masked (`[REDACTED_SECRET]`).
- **Controlled Cleanup & Storage Reality:** `controlledCleanupPlanArtifact()` wipes memory buffers using `crypto.randomFillSync()` and overwrites disk file blocks prior to `fs.unlinkSync()`.
  > [!CAUTION]
  > **Physical Storage Erasure Reality:** Overwriting file blocks and unlinking removes filesystem index references and logical block data, but **cannot guarantee physical erasure** on modern wear-leveled SSDs, NAND flash controllers, or copy-on-write filesystems (APFS, ZFS, ext4 journaling). Physical flash cells may retain remnants until wear-leveling and controller TRIM cycles occur. True physical data elimination requires cryptographic erasure (key destruction) or media shredding.

---

## 3. Anti-Regeneration Gate Specification

At apply time, `verifyPlanForApply()` strictly enforces:
1. **Saved Binary Plan Reuse & Encryption Verification:** The exact approved binary plan (`savedBinaryPlanSha256`) must be provided inside an authorized `KSEP_V19` encrypted container. Unencrypted plans are rejected with `ERR_UNENCRYPTED_PLAN_AT_REST`. Plan regeneration at apply time is prohibited.
2. **Configuration Invariance:** Current digest of all `.tf`, `.tf.json`, `.tofu`, `.tofu.json` files must match `configFilesDigest` (`ERR_INPUT_CONFIG_MODIFIED_POST_APPROVAL`).
3. **Variable Invariance:** Current digest of all variable files must match `tfvarsFilesDigest` (`ERR_TFVARS_MODIFIED_OR_INTRODUCED`).
4. **CLI Varfile Invariance:** Current digest of each `-var-file` must match `cliVarFileDigests` (`ERR_CLI_VARFILE_MODIFIED_POST_APPROVAL`).
5. **Backend Invariance:** Backend files and `-backend-config` must match `backendConfigDigest` (`ERR_BACKEND_CONFIG_MODIFIED_POST_APPROVAL`).
6. **Module Source Tree Invariance:** Local and remote module source trees must match `moduleSourceDigests` (`ERR_MODULE_SOURCES_MODIFIED_POST_APPROVAL`).
7. **Lock File Invariance:** Current `.terraform.lock.hcl` must match `providerLockDigest` (`ERR_LOCKFILE_MODIFIED_POST_APPROVAL`).
8. **HMAC Key Rotation Invariance:** The HMAC key version must satisfy the active verification policy (`ERR_HMAC_KEY_ROTATED_APPROVAL_INVALID`).
9. **Secret Version Immutability & Enabled State:** Secret references must remain immutable numeric versions verified to be in `ENABLED` state via `ISecretManagerMetadataResolver`.

---

## 4. Test Evidence & Verification Tracks

The test suite `backend/src/tests/phase20_19_pilot_gate_a_closure.test.ts` executes **56 security verification tests** across 11 tracks:

- **Track A: Comprehensive Plan Input Provenance & Anti-Regeneration Gate (Tests 1–8)**
  - Tests 1–8: Comprehensive input hashing, .tf tampering detection, *.tfvars tampering detection, lockfile tampering detection, binary plan digest tampering, manifest signature tampering, prohibited CLI flags (`-destroy`), and unapproved environment variables (`TF_CLI_ARGS_apply`). (8/8 PASS)
- **Track B: Independent Registry Two-Person Recovery Authorization (Tests 9–18)**
  - Tests 9–18: Registry fail-closed, self-approval rejection, suspended/revoked officer rejection, IdP subject collusion rejection, MFA credential sharing rejection, request digest tampering, parameter tampering, valid two-person approval, and single-use replay prevention. (10/10 PASS)
- **Track C: Pilot-Specific Cryptographic & Dataset Isolation (Tests 19–23)**
  - Tests 19–23: Production database cross-query failure, production KMS key ID failure, AAD tampering failure, session UID mismatch rejection, and valid pilot scoped decryption. (5/5 PASS)
- **Track D: Plaintext DEK Memory Lifecycle & Exception Clearing (Tests 24–25)**
  - Tests 24–25: DEK zeroing on success path and guaranteed DEK clearing in `finally` blocks upon authentication tag verification failures. (2/2 PASS)
- **Track E: Exact OpenTofu Variable Precedence & Conflict Overrides (Tests 26–30)**
  - Test 26: Conflicting variable across all 5 layers resolves to CLI override (Layer 5 > 4 > 3 > 2 > 1). (PASS)
  - Test 27: Conflicting variable across Layers 1–4 resolves to Layer 4 (auto.tfvars in lexical order: `z_last.auto.tfvars` overrides `a_first.auto.tfvars`). (PASS)
  - Test 28: Conflicting variable across Layers 1–3 resolves to Layer 3 (`terraform.tfvars.json` overrides `terraform.tfvars`). (PASS)
  - Test 29: CLI argument order proof: `-var-file` following `-var` overrides the `-var` value. (PASS)
  - Test 30: CLI argument order proof: `-var` following `-var-file` overrides the `-var-file` value. (PASS)
- **Track F: Immutable Secret Manager Versions Enforcement (Tests 31–35)**
  - Test 31: Valid positive numeric version identifier accepted and bound. (PASS)
  - Test 32: Version alias `latest` strictly rejected with `ERR_MUTABLE_SECRET_VERSION`. (PASS)
  - Test 33: Mutable text aliases (e.g., `active`, `staging`) rejected with `ERR_MUTABLE_SECRET_VERSION`. (PASS)
  - Test 34: Unversioned secret reference rejected with `ERR_UNVERSIONED_SECRET_REFERENCE`. (PASS)
  - Test 35: Plan generation fails closed if any input secret reference is mutable or unversioned. (PASS)
- **Track G: HMAC Key Trust, Independent Management & Rotation (Tests 36–39)**
  - Test 36: Untrusted caller supplying `secretFingerprintHmacKey` rejected with `ERR_UNTRUSTED_HMAC_KEY_OVERRIDE`. (PASS)
  - Test 37: Bound HMAC key identifier and version in signed manifest. (PASS)
  - Test 38: Key rotation invalidates stale approvals under `STRICT_ACTIVE_ONLY`. (PASS)
  - Test 39: Key rotation permits authorized historical versions under `PERMIT_AUTHORIZED_HISTORICAL_VERSIONS`, but rejects revoked versions. (PASS)
- **Track H: Binary Plan Storage Protection, Permissions & Transit (Tests 40–43)**
  - Test 40: Plan binary is written with restricted `0o600` filesystem permissions. (PASS)
  - Test 41: AES-256-GCM authenticated encryption and decryption for transit plan artifacts. (PASS)
  - Test 42: Transit ciphertext or auth tag tampering fails decipher verification. (PASS)
  - Test 43: Controlled cleanup zeroes memory buffers, overwrites storage blocks, unlinks file, and documents physical storage erasure constraints. (PASS)
- **Track I: OpenTofu Plan Encryption At Rest (Tests 44–48)**
  - Test 44: Saved plan binary on disk starts with KSEP_V19 container magic and contains zero plaintext plan strings. (PASS)
  - Test 45: Authorized decryption of encrypted saved plan at apply gate succeeds and verifies SHA-256 integrity. (PASS)
  - Test 46: Tampered encrypted container ciphertext or auth tag fails decipher verification with `ERR_PLAN_DIGEST_MISMATCH`. (PASS)
  - Test 47: Unencrypted legacy plaintext plan buffer fails closed with `ERR_UNENCRYPTED_PLAN_AT_REST`. (PASS)
  - Test 48: Plan encryption key manager supports rotation with historical key recovery across multiple plan versions. (PASS)
- **Track J: Advanced Secret Manager Reference & Version State Resolution (Tests 49–53)**
  - Test 49: Valid hyphenated GCP project ID and numeric project number are recognized as distinct valid project types. (PASS)
  - Test 50: Project ID containing underscores is rejected with `ERR_INVALID_PROJECT_IDENTIFIER`. (PASS)
  - Test 51: Secret ID containing invalid characters rejected with `ERR_INVALID_SECRET_ID`. (PASS)
  - Test 52: InMemorySecretManagerMetadataResolver distinguishes ENABLED vs DISABLED/DESTROYED states. (PASS)
  - Test 53: Plan generation fails closed if any referenced secret version is DISABLED or DESTROYED. (PASS)
- **Track K: Cloud KMS HMAC Identity Mapping & Gate B Boundary (Tests 54–56)**
  - Test 54: Canonical Cloud KMS HMAC identity mapping resolves exact GCP resource path. (PASS)
  - Test 55: KMS identity mapping enforces least-privilege IAM separation between runner and apply gate. (PASS)
  - Test 56: Gate B operational boundary BLOCKED_SANDBOX_IAM_NOT_AVAILABLE strictly prevents live cloud KMS calls. (PASS)
