# S8 TEMPLATE ENVELOPE VERSION MATRIX

**System:** Kelasagara BioMatch Envelope Schema Governance  
**Policy:** Strict Downgrade Protection (INV-04)  

---

## 1. Envelope Schema Progression

| Version Tag | Cryptographic Mechanism | AAD Scheme | Key Management | Status |
| :--- | :--- | :--- | :--- | :--- |
| **`v1_legacy`** | AES-256-GCM | None (Empty) | Static environment secret via PBKDF2 | **DEPRECATED** (Read-only during migration) |
| **`v2_aad_gcm`** | AES-256-GCM | Pipe-delimited string (`ver\|tenant\|uid\|kver`) | Static environment secret via PBKDF2 | **TRANSITIONAL** (Read-only during migration) |
| **`v3_kms_gcm`** | AES-256-GCM | Length-prefixed binary (`BIOMATCH_AAD_V1`) | Per-record 256-bit DEK wrapped via Cloud KMS KEK | **CURRENT PRODUCTION TARGET** |

---

## 2. Invariant & Downgrade Rules (INV-04)
1. **New Writes:** All new biometric enrollments generate `v3_kms_gcm` envelopes exclusively.
2. **Migration Window:** Legacy `v2_aad_gcm` records are readable by `decryptTemplate()` only when `minEnvelopeVersion` is not set to `v3_kms_gcm`.
3. **Strict Mode:** When `minEnvelopeVersion = "v3_kms_gcm"`, any receipt of `v1_legacy` or `v2_aad_gcm` ciphertext immediately throws `ENVELOPE_DOWNGRADE_REJECTED`.
4. **Context Re-verification:** On every read, the AAD is reconstructed using the authoritative database path parameters (`tenantId` and `uid`). If the ciphertext was transplanted from another tenant or account, AES-GCM tag verification throws `AUTHENTICATION_TAG_VERIFICATION_FAILED`.
