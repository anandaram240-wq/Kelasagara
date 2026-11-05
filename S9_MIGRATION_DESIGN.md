# KELASAGARA BIOMATCH — STAGE S9.5 ENVELOPE VERSIONING & DATA MIGRATION DESIGN
**Document ID:** `S9_MIGRATION_DESIGN.md`  
**Classification:** Cryptographic Schema Migration & Data Preservation Protocol  
**Evaluation Date:** October 11, 2026 (UTC: 2026-10-11T05:12:30Z)  
**Git Commit:** `6a2a1482fe90d41050fc61ac83cc8777291a4a06` (tag: `s8-final`)  
**Evidence Artifacts:** `evidence/s9/migration_state_transitions.json`, `evidence/s9/migration_fault_injection.json`  

---

## 1. INVENTORY OF TEMPLATE ENVELOPE FORMATS

The biometric database supports three generations of encrypted template envelopes:

### 1.1 Generation 1: `v1_plain_gcm` (Legacy)
- **Algorithm:** AES-256-GCM.
- **Key Source:** Static server master key (`LOCAL_MASTER_KEY_SECRET`).
- **AAD Mode:** None or unauthenticated.
- **Vulnerability:** Lacks tenant and user context binding; susceptible to cross-user template transplantation.
- **Lifecycle Status:** **DEPRECATED — READ-ONLY FOR MIGRATION**.

### 1.2 Generation 2: `v2_aad_gcm` (S7 Intermediate)
- **Algorithm:** AES-256-GCM.
- **Key Source:** Single master secret key.
- **AAD Mode:** String-concatenated pipe-delimited format: `${tenantId}|${uid}|${algo}|${keyVersion}|${timestamp}`.
- **Vulnerability:** Vulnerable to delimiter collision if tenant ID or user ID contains `|` character.
- **Lifecycle Status:** **DEPRECATED — READ-ONLY FOR MIGRATION**.

### 1.3 Generation 3: `v3_kms_gcm` (Current Production Standard)
- **Algorithm:** AES-256-GCM.
- **Key Architecture:** Envelope encryption with Cloud KMS (or `LocalDevKeyProvider`).
- **Data Encryption Key (DEK):** Fresh 256-bit CSPRNG key per write; zeroized immediately after use (`dek.fill(0)`).
- **Key Encryption Key (KEK):** Managed exclusively in Google Cloud KMS (`template-kek` in `asia-south1`).
- **AAD Mode:** Binary canonical length-prefixed encoding (`BIOMATCH_AAD_V1`) with TLV tags. Completely immune to delimiter shifting.
- **Lifecycle Status:** **ACTIVE WRITE STANDARD**.

---

## 2. THE 13-STAGE SAFE MIGRATION PROTOCOL

To ensure zero downtime, zero data corruption, and complete reversibility, data migration executes through a 13-stage atomic pipeline:

```
 1. DISCOVER     ──► Find candidate document where envelopeVersion != "v3_kms_gcm"
 2. VALIDATE     ──► Verify uid, tenantId, and ciphertext integrity fields exist
 3. ACQUIRE LEASE──► Acquire 60-second distributed lease lock in Firestore
 4. READ SOURCE  ──► Read source document under active lease
 5. DECRYPT      ──► Decrypt source vector using legacy reader (fail-closed if corrupt)
 6. CONVERT      ──► Validate 512-float dimensions and finite float values
 7. GENERATE DEK ──► crypto.randomBytes(32) fresh CSPRNG key
 8. WRAP DEK     ──► Wrap DEK with Cloud KMS KEK and canonical BIOMATCH_AAD_V1 context
 9. ENCRYPT DATA ──► AES-256-GCM encrypt vector with fresh 96-bit IV
10. PRE-COMMIT   ──► Test unwrap and decrypt candidate envelope; assert delta == 0.0
11. COMMIT       ──► Firestore transaction replaces envelope; sets version="v3_kms_gcm"
12. AUDIT LOG    ──► Write tamper-evident audit record (masking key & vector material)
13. RELEASE LEASE──► Clear lease lock; increment migration counter
```

---

## 3. MIGRATION INVARIANTS & INTEGRITY GUARDS

- **Invariant SEC-08 (Migration Atomicity):** If any stage (5 through 10) encounters an error, the migration halts immediately in state `FAILED`. The original source document in Firestore is **never modified or deleted**.
- **Invariant SEC-07 (Key Confidentiality):** Plaintext DEKs are never written to Firestore progress logs, audit logs, or temporary migration records. DEKs are erased from memory using `dek.fill(0)` in all execution branches.
- **Idempotency Guarantee:** If an already-migrated `v3_kms_gcm` record is processed by the migration worker, it is recognized immediately and skipped in $<1\text{ ms}$ without altering ciphertext or re-wrapping DEKs.
- **Dry-Run Capability:** The `TemplateMigrationService` supports `dryRun: true`, executing stages 1 through 10 without executing step 11 (commit), outputting candidate summaries for pre-flight verification.

---

## 4. ROLLBACK & RECOVERY PROCEDURE

If a staging or production migration batch encounters systemic failures (e.g. Cloud KMS quota exhaustion):
1. **Immediate Halt:** Terminate migration workers. In-flight leases expire cleanly within 60 seconds.
2. **Backward Compatibility:** All existing backend reading code retains legacy fallback support for `v1_plain_gcm` and `v2_aad_gcm` when `minEnvelopeVersion` is configured to `v1` or `v2`.
3. **No Irreversible Destruction:** Because source records are replaced only upon successful pre-commit decrypt drills, no data loss can occur during an interrupted migration.

---
*Report generated and validated under Stage S9.5 Operating Contract.*
