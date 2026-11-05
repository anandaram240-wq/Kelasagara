# KELASAGARA V20.18 — PLAN MANIFEST TRUST BOUNDARY & CRYPTOGRAPHIC ATTESTATION
## Single-Plan Life Cycle, Manifest Binding, and Notary Key Security

**Author:** Principal Cryptographic Engineer, DevSecOps Architect  
**Date:** 2026-11-01  
**Repository:** `kelasagaara_v17`  
**Parent Commit:** `2233327` (`security/phase20.17-trusted-execution-provenance`)  
**Branch:** `security/phase20.18-pilot-readiness-corrections`  
**Status:** `ACTIVE_VERIFIED`  

---

### 1. The Single-Plan Integrity Guarantee

A frequent failure mode in infrastructure deployment is the "Plan-Regenerate-Apply" anti-pattern:
- A plan is generated in CI, reviewed, and approved.
- During the apply step, CI re-runs `tofu plan` or `tofu apply` without the exact binary plan file.
- Changes merged to Git, upstream cloud state drift, or altered dependency packages can cause the applied configuration to differ dangerously from what was approved.

Phase 20.18 enforces **Single-Plan Invariance**:
1. The approval stage and apply stage operate on the **exact same saved binary plan file**.
2. A plan is NEVER regenerated between approval and application.
3. The cryptographic provenance manifest binds the binary plan bit-for-bit via `savedBinaryPlanSha256`.

---

### 2. Comprehensive Manifest Cryptographic Envelope

The RFC 8785 Canonical JSON execution manifest binds:
- Actual process CLI arguments (`actualCliInvocationArgs`).
- Digest of sanitized environment configuration (`environmentConfigDigest`).
- Pinned OpenTofu version and binary digest (`tofuVersion`, `tofuBinaryDigest`).
- Absolute executable path (`tofuExecutablePath`).
- Git commit SHA (`gitCommitSha`).
- Source configuration files digest (`terraformConfigDigest`).
- Provider dependency lockfile digest (`providerLockDigest`).
- Variable inputs digest (`variableInputDigests`).
- Target workspace and Google Cloud project ID.
- Binary plan SHA-256 (`savedBinaryPlanSha256`).
- Layer 2 Policy Engine decision (`policyDecision: 'APPROVED'`).
- Manifest signing timestamp and 2-hour maximum TTL.

**Confidentiality Mandate:** Plaintext secret values are NEVER written to the manifest. Secrets are referenced strictly by their Cloud Secret Manager resource identifier (`projects/.../secrets/...`).

---

### 3. Separation of CI Manifest Notary Key

A local or test signing key cannot provide production-grade signing evidence:
1. **Key Isolation:**
   The CI Manifest Notary Key resides in Cloud KMS HSM (`projects/kelasagara-sandbox/locations/global/keyRings/ci-notary/cryptoKeys/manifest-signer`). Ordinary developers, build runners, and verifier workloads have zero access to the private signing key.
2. **Apply Gate Enforcement:**
   `TrustedPlanWrapperV18.verifyPlanForApply` imports the trusted notary public key and verifies:
   - The manifest signature is cryptographically valid (`SHA256withECDSA`).
   - The presented plan binary matches `savedBinaryPlanSha256` bit-for-bit.
   - The git commit matches expected HEAD.
   - The plan was approved by policy (`policyDecision === 'APPROVED'`).
   - The manifest has not expired.
