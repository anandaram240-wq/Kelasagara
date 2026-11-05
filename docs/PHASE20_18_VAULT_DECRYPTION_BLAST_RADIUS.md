# KELASAGARA V20.18 — VAULT DECRYPTION BLAST RADIUS & ARCHITECTURE SELECTION
## Comparative Analysis of Option A, Option B, and Option C for Controlled Biometric Pilot

**Author:** Principal Security Architect, Cryptographic Systems Engineer  
**Date:** 2026-11-01  
**Repository:** `kelasagaara_v17`  
**Parent Commit:** `2233327` (`security/phase20.17-trusted-execution-provenance`)  
**Branch:** `security/phase20.18-pilot-readiness-corrections`  
**Status:** `ACTIVE_VERIFIED`  

---

### 1. The Core Architectural Problem

Because Google Cloud KMS permissions (`roles/cloudkms.cryptoKeyDecrypter`) operate at the CryptoKey level without row-level awareness, any service with decrypt permission on `dek_wrap` has the raw cryptographic ability to decrypt all DEKs wrapped under that key.

To address this blast radius for the upcoming controlled pilot, three architectures were rigorously evaluated:

---

### 2. Architectural Comparison Matrix

| Architectural Option | Architecture Description | Security Boundary & Isolation | Latency & Operational Complexity | Verdict |
| :--- | :--- | :--- | :--- | :---: |
| **Option A: Verifier-Owned Decryption with Hardened AAD & Pre-KMS Fencing** | `sa-biometrics-verifier` calls KMS directly, protected by pre-KMS lifecycle fencing (rejects superseded/revoked before KMS), session UID ownership checks, and dual-layer binary AAD. | Blast radius encompasses all records wrapped by `dek_wrap`, but application cryptographic binding prevents cross-user plaintext extraction. | **Lowest latency** (single network call to KMS, sub-20ms P99); minimal operational overhead. | **ACCEPTED FOR PILOT WORKLOADS** |
| **Option B: Dedicated Vault Decryption Microservice** | An isolated internal microservice (`sa-biometrics-vault-decryptor`) holds the KMS decrypt role. Verifier calls it via internal authenticated OIDC RPC. | Separates KMS decrypt privilege from the verifier service. However, if the verifier is compromised, it can still request decryption of records. | Adds 25–40ms RPC overhead per 1:1 match; introduces another service to deploy, monitor, and scale. | **FEASIBLE FOR FULL PRODUCTION EXPANSION** |
| **Option C: Pilot-Specific Cryptographic Isolation** | Enrolls pilot participants into a **completely separate named database** (`biometric-pilot-vault-db`) with a **dedicated pilot KMS CryptoKey** (`pilot_dek_wrap`). | **Absolute cryptographic isolation:** Compromise of pilot credentials cannot decrypt existing production templates, and production credentials cannot decrypt pilot data. | Minimal overhead (separate key and named DB); cleanly separates pilot evaluation from production state. | **MANDATORY PREREQUISITE FOR PILOT COMMENCEMENT** |

---

### 3. Blast-Radius Decision and Pilot Mandate

For the limited, controlled Kelasagara Biometric Pilot:
1. **Architectural Choice:** Implement **Option A + Option C**.
   - Use the hardened `VaultDecryptionGuardV18` pipeline (Option A) to keep verification latency sub-20ms with pre-KMS lifecycle gating and binary AAD.
   - Enforce **Option C (Pilot Cryptographic Isolation)**: The pilot must operate under a separate GCP KMS CryptoKey (`pilot_dek_wrap`) and dedicated Firestore database. Under no circumstances may pilot biometric records be mixed with production biometric vault records.
2. **Honest Cryptographic Disclosure:**
   A shared KMS key with a privileged decryption service must NEVER be described as "per-user cryptographic isolation". Per-user isolation requires distinct per-user keys or client-side private keys.
3. **No Live Cloud Key Migrations:**
   In accordance with the operational constraints, zero live KMS keys or production databases have been altered during this phase.
