# KELASAGARA V20.18 — KMS AAD AND DEK CRYPTOGRAPHIC ISOLATION
## Independent Handling of KMS Context vs Application AES-256-GCM AAD

**Author:** Principal Cryptographic Architect, Biometric Systems Security Auditor  
**Date:** 2026-11-01  
**Repository:** `kelasagaara_v17`  
**Parent Commit:** `2233327` (`security/phase20.17-trusted-execution-provenance`)  
**Branch:** `security/phase20.18-pilot-readiness-corrections`  
**Status:** `ACTIVE_VERIFIED`  

---

### 1. Two-Tier Independent AAD Architecture

Envelope encryption requires two distinct layers of authenticated data:
1. **Tier 1: Cloud KMS Encryption Context (Wrapped-DEK AAD):**
   Passed to Google Cloud KMS during `kms.encrypt()` and `kms.decrypt()`. KMS cryptographically binds the ciphertext of the Data Encryption Key (DEK) to this context string.
2. **Tier 2: Application-Layer AES-256-GCM AAD:**
   Passed to the local Node.js decipher (`decipher.setAAD(...)`). Cryptographically binds the 128-dimensional biometric embedding ciphertext to the exact database record metadata.

These two AAD layers serve different purposes and must be constructed and validated independently.

---

### 2. Format Specifications and Trusted Construction

#### A. Cloud KMS Context AAD
Constructed strictly on the server:
```
kms:tenant=kelasagara:account=<accountUid>:template=<templateId>
```
If an attacker attempts to unwrap a DEK under an altered account UID or template ID, Cloud KMS immediately returns an unwrap failure.

#### B. Application AES-256-GCM Length-Prefixed Binary AAD (ISO/IEC 19772)
Constructed using big-endian 4-byte length prefixes to eliminate delimiter collisions:
```
[Len(accountUid)][accountUid]
|| [Len(templateId)][templateId]
|| [Len(vaultRecordVersion)][vaultRecordVersion]
|| [Len(encryptionSchemaVersion)][encryptionSchemaVersion]
|| [Len(embeddingSpaceId)][embeddingSpaceId]
|| [Len(approvedContext)][approvedContext]
```

**Non-Negotiable Rule:** The client NEVER supplies the AAD. AAD is reconstructed strictly from trusted backend database metadata and authenticated session context. A failed verification NEVER falls back to an empty AAD or an alternative record's context.

---

### 3. Substitution Defense Test Matrix

Every potential field substitution is covered by automated regression tests in `phase20_18_pilot_readiness_corrections.test.ts`:

| Substitution Target | Attack Scenario | Defensive Assertion | Test # |
| :--- | :--- | :--- | :---: |
| **Account UID** | Attacker substitutes User B's UID in User A's record | Fails KMS unwrap or AES-GCM tag verification | Test 21 |
| **Template ID** | Attacker swaps templates belonging to the same user | Fails tag verification | Test 22 |
| **Vault Version** | Attacker downgrades record version to bypass checks | Fails tag verification | Test 23 |
| **Embedding Space** | Attacker presents incompatible embedding space | Rejected before decryption (`EMBEDDING_SPACE_MISMATCH`) | Test 24 |
| **Wrapped DEK** | Attacker swaps DEK from an unrelated record | Fails KMS unwrap | Test 25 |
| **Ciphertext** | 1-bit alteration of ciphertext vector | Fails AES-GCM tag verification | Test 26 |
| **Auth Tag** | 1-bit alteration of 128-bit authentication tag | Fails AES-GCM tag verification | Test 27 |
| **Superseded Status** | Attacker requests decryption of archived template | Rejected prior to KMS call (`LIFECYCLE_GATE_REJECTED`) | Test 28 |
| **Revoked Status** | Attacker requests decryption of revoked template | Rejected prior to KMS call (`LIFECYCLE_GATE_REJECTED`) | Test 29 |
| **Session UID** | Impostor attempts to decrypt victim's record | Rejected prior to KMS call (`UNAUTHORIZED_RECORD_ACCESS`) | Test 30 |
