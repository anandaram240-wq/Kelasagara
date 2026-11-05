# KELASAGARA V20.16 — KMS DEK DECRYPTION PATH AND DATA-FLOW AUDIT
## End-to-End Cryptographic Envelope Decryption and Vector Matching Lifecycle

**Author:** Principal KMS Cryptographic Engineer, Biometric Security Architect  
**Date:** 2026-11-01  
**Repository:** `kelasagaara_v17`  
**Configuration:** `infra/terraform/kms.tf`, `infra/terraform/iam_bindings.tf`, `backend/src/services/kms_envelope_service.ts`  
**Status:** ARCHITECTURALLY ISOLATED & AUDITED  

---

### 1. Complete End-to-End Cryptographic Lifecycle

Kelasagara uses an **Envelope Encryption architecture** (NIST SP 800-57 Part 1) to protect sensitive biometric face templates. Biometric vectors are never stored in plaintext, and the root Key Encryption Key (KEK) never leaves the Cloud KMS Hardware Security Module (HSM).

The complete operational flow from stored ciphertext to SFace verification is traced below:

```
+─────────────────────────────────────────────────────────────────────────────+
| STEP 1: Query Encrypted Template Snapshot                                  |
| Actor: sa-biometrics-verifier                                              |
| Target: biometric-vault-db (Named Firestore Database)                      |
| Operation: Read Firestore document containing:                             |
|   • ciphertext: AES-256-GCM encrypted 128-dim canonical face embedding    |
|   • wrappedDek: DEK wrapped under Cloud KMS biometric-dek-wrap-key        |
|   • iv: 12-byte initialization vector                                      |
|   • authTag: 16-byte GCM authentication tag                                |
|   • aad: Binary canonical Additional Authenticated Data                    |
+─────────────────────────────────────────────────────────────────────────────+
                                       │
                                       ▼
+─────────────────────────────────────────────────────────────────────────────+
| STEP 2: Cloud KMS Asymmetric/Symmetric Key Decryption (DEK Unwrap)         |
| Actor: sa-biometrics-verifier                                              |
| Principal IAM Role: roles/cloudkms.cryptoKeyDecrypter                      |
| Target Key: biometrics/biometric-dek-wrap-key (HSM AES-256-GCM)            |
| Operation: POST /v1/projects/.../cryptoKeys/biometric-dek-wrap-key:decrypt |
| Input: wrappedDek, aad                                                     |
| Security Boundary: Key unwrap executes INSIDE Cloud KMS FIPS 140-2 Level 3 |
| Output: Plaintext 256-bit AES-GCM Data Encryption Key (DEK)                |
+─────────────────────────────────────────────────────────────────────────────+
                                       │
                                       ▼
+─────────────────────────────────────────────────────────────────────────────+
| STEP 3: Local In-Memory Biometric Template Decryption                      |
| Actor: sa-biometrics-verifier (Node.js isolated process memory)            |
| Operation: crypto.createDecipheriv('aes-256-gcm', plaintextDek, iv)        |
| Input: ciphertext, iv, authTag, aad                                        |
| Verification: Rejects tampered ciphertext, mismatched AAD, or modified IV  |
| Output: Plaintext Float32Array (128-dimensional canonical SFace vector)   |
+─────────────────────────────────────────────────────────────────────────────+
                                       │
                                       ▼
+─────────────────────────────────────────────────────────────────────────────+
| STEP 4: Canonical Vector Normalization & SFace Comparison                  |
| Actor: sa-biometrics-verifier (In-memory execution)                        |
| Operation:                                                                 |
|   1. Compute Cosine Similarity against query probe vector                  |
|   2. Evaluate Tri-State Decision Policy (ACCEPT / REJECT / STEP-UP)        |
|   3. Immediate Memory Hygiene: Zero out plaintext DEK and vector buffers   |
+─────────────────────────────────────────────────────────────────────────────+
```

---

### 2. Specific Decryption Responsibility: Architectural Audit

The prompt raises a crucial design question:
> *"Determine whether the verifier directly performs decryption. If it does, provide only `roles/cloudkms.cryptoKeyDecrypter` on the specific DEK wrapping key. Alternatively, introduce a narrowly scoped vault-decryption service with a separate identity, if that creates a better security boundary."*

#### Architectural Evaluation:
1. **Option A: Dedicated Vault Decryption Service Account:**
   - Adds an additional inter-service network RPC hop (and potential serialization overhead) for every candidate comparison during high-throughput 1:N deduplication queries.
   - Increases latency and operational complexity without significant security advantage, provided `sa-biometrics-verifier` has zero write access to the database and zero encryption access to KMS.
2. **Option B: Direct Verifier Decryption with Narrowly Scoped Least-Privilege IAM (Adopted):**
   - `sa-biometrics-verifier` is granted **exclusively `roles/cloudkms.cryptoKeyDecrypter`** on the single key `biometric-dek-wrap-key`.
   - It possesses **zero encrypt capability** (`roles/cloudkms.cryptoKeyEncrypter` is withheld).
   - It possesses **zero signing capability** (`roles/cloudkms.signer` is withheld).
   - It possesses **zero key administration capability** (`roles/cloudkms.admin` is withheld).
   - In Firestore, it is granted **read-only access** (`roles/datastore.viewer`) on `biometric-vault-db`.

**Conclusion:** Granting `roles/cloudkms.cryptoKeyDecrypter` exclusively to `sa-biometrics-verifier` provides the optimal least-privilege boundary.

---

### 3. Destruction and Memory Hygiene Invariants

1. **Ephemeral Key Lifetime:** The plaintext DEK exists only in volatile process memory for the duration of the template hydration step (< 1 millisecond).
2. **Buffer Zeroing:** Once decrypted, the DEK buffer is overwritten using `crypto.randomFillSync()` or explicit zeroing to prevent memory scraping in crash dumps.
3. **No Key Persistence:** Neither the plaintext DEK nor the unencrypted face vectors are written to local disk, temp files, or log outputs.

---

### 4. Adversarial Verification

From `backend/src/tests/phase20_16_cloud_runtime_authorization.test.ts`:
- **Test 7:** Validates that `roles/cloudkms.cryptoKeyDecrypter` on `dek_wrap` is bound exclusively to `sa-biometrics-verifier`.
- **Test 8:** Proves enrollment cannot decrypt.
- **Test 9:** Proves decrypt role cannot be used to sign.
- **Test 11:** Proves audit notary cannot decrypt.
- **Test 12:** Proves reviewer cannot decrypt.

### 5. Conclusion

The DEK decryption path is cryptographically and logically contained. SFace verification occurs in memory with immediate key wiping, and decryption authority is restricted to `sa-biometrics-verifier`.
