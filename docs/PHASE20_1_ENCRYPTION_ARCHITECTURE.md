# KELASAGARA V20.1: ZERO-PLAINTEXT BIOMETRIC VAULT
## PHASE 20.1 TECHNICAL REPORT 1: CRYPTOGRAPHIC ENVELOPE ARCHITECTURE

**Author:** Principal Cryptography Engineer & Biometric Security Architect  
**Project:** Kelasagara Major Project  
**Phase:** 20.1 — Zero-Plaintext Biometric Vault  
**Working Branch:** `security/phase20.1-biometric-vault-encryption`  
**Baseline Release:** V19.2.3 (`f210f95`, tag `v19.2.3-release`)  
**Status:** Certified & Production-Hardened  

---

### 1. EXECUTIVE SUMMARY & THREAT MODEL

Prior to Phase 20.1, the Kelasagara Face Biometric engine persisted normalized 128-dimensional floating-point embeddings extracted by the SFace neural network as JSON numerical arrays (`canonicalEmbedding` and `sfaceEmbedding128`) directly in Firestore documents under `/biometric_vault/{enrollmentId}`.

While Firestore security rules and backend authorization prevented direct client reads of the vault collection, persisting raw, unencrypted biometric feature vectors introduced significant residual security risks:
1. **Insider Threat / Database Snapshot Exfiltration:** Any administrative access, compromised service account credential, database export, or cloud backup leak would expose plaintext biometric vectors across the entire workforce.
2. **Irrevocable Biometric Compromise:** Unlike passwords or cryptographic keys, a person's biological facial geometry cannot be revoked or replaced if raw feature representations are stolen.
3. **Cross-Tenant & Cross-User Spoofing:** Plaintext vectors could potentially be transplanted across user records or environments if not cryptographically bound to the identity context.

Phase 20.1 completely eliminates plaintext biometric persistence across the entire lifecycle by implementing an **Envelope Encryption Architecture** using **AES-256-GCM** with **Google Cloud Key Management Service (Cloud KMS)** and **Length-Prefixed Canonical Authenticated Additional Data (AAD)** context binding.

```
+--------------------------------------------------------------------------------------------------+
|                                    KELASAGARA ENVELOPE ENCRYPTION HIERARCHY                     |
+--------------------------------------------------------------------------------------------------+
|                                                                                                  |
|   Google Cloud KMS (Key Encryption Key - KEK)                                                    |
|   Resource: projects/kelasagara-f127a/locations/global/keyRings/biometric-security-ring/         |
|             cryptoKeys/biometric-vault-kek-v1/cryptoKeyVersions/1                                |
|   Algorithm: GOOGLE_SYMMETRIC_ENCRYPTION (256-bit AES-GCM / Hardware Security Module)          |
|                                         |                                                        |
|                   kms.encrypt(DEK, AAD) | kms.decrypt(wrappedDEK, AAD)                           |
|                                         v                                                        |
|   Ephemeral Data Encryption Key (DEK)                                                            |
|   Generated per enrollment: 256-bit CSPRNG (crypto.randomBytes(32))                              |
|   In-memory lifetime: < 5 milliseconds (zeroed immediately in finally block)                    |
|                                         |                                                        |
|                     AES-256-GCM Encrypt | AES-256-GCM Decrypt                                    |
|                     + 96-bit Random IV  | + 128-bit Auth Tag Check                               |
|                     + Canonical AAD     | + Canonical AAD Check                                  |
|                                         v                                                        |
|   Serialized Biometric Feature Vector (FLOAT32_LE_V1)                                            |
|   Payload: 128 x Float32 (Little-Endian binary buffer, exactly 512 bytes)                         |
|   Invariant: Unit L2 norm ||v||_2 = 1.0000 +/- 1e-3, non-null, finite values                     |
|                                         |                                                        |
|                                         v                                                        |
|   Firestore Storage: /biometric_vault/{templateId}                                               |
|   Stored fields: schemaVersion: 2, biometricEnvelope (Base64 fields), metadata                   |
|   STRICT ZERO-PLAINTEXT INVARIANT: canonicalEmbedding, sfaceEmbedding128, and embedding are NIL  |
+--------------------------------------------------------------------------------------------------+
```

---

### 2. CRYPTOGRAPHIC PRIMITIVES & ALGORITHMIC SPECIFICATIONS

| Component | Standard / Algorithm | Parameters / Configuration | Key / Nonce Size | Security Rationale |
| :--- | :--- | :--- | :--- | :--- |
| **KEK (Key Encryption Key)** | Google Cloud KMS Symmetric | AES-256-GCM, HSM-backed, rotation period: 90 days | 256 bits | Cloud root of trust; hardware-isolated, auditable access |
| **DEK (Data Encryption Key)** | Ephemeral Symmetric Key | Freshly generated via Node.js `crypto.randomBytes(32)` | 256 bits (32 bytes) | Every biometric template encrypted under a unique DEK |
| **Payload Cipher** | Authenticated Cipher | AES-256-GCM (`aes-256-gcm`) | 256-bit key, 96-bit IV, 128-bit Tag | Provides confidentiality, integrity, and authenticity |
| **Initialization Vector (IV)** | Cryptographic Nonce | `crypto.randomBytes(12)` per template encryption | 96 bits (12 bytes) | Prevents IV reuse across templates and re-encryptions |
| **Authentication Tag** | Galois Message Auth Tag | Extracted via `cipher.getAuthTag()` | 128 bits (16 bytes) | Detects any bit tampering in ciphertext or AAD |
| **Payload Encoding** | Binary Float32 Little-Endian | `FLOAT32_LE_V1` (512-byte contiguous binary buffer) | 512 bytes | Eliminates JSON serialization overhead, exact IEEE-754 |
| **Context Binding** | Length-prefixed Binary AAD | 8-field length-prefixed canonical binary buffer | Variable (150-250 bytes) | Prevents cross-user, cross-collection, cross-tenant theft |

---

### 3. VECTOR SERIALIZATION & DESERIALIZATION (FLOAT32_LE_V1)

Biometric vectors extracted by SFace consist of 128 IEEE-754 single-precision floating-point numbers. Storing them as JSON float arrays introduced parsing jitter, potential string-to-float precision loss, and ballooned storage size to over 2.5 KB per record.

#### 3.1 Serialization (`serializeVectorFloat32LE`)
The 128-D vector is validated for unit L2 norm ($|\|\mathbf{v}\|_2 - 1.0| \le 10^{-3}$) and written into an exact 512-byte little-endian binary buffer:
$$\text{Buffer Size} = 128 \times 4 \text{ bytes} = 512 \text{ bytes}$$
```typescript
const buf = Buffer.alloc(512);
for (let i = 0; i < 128; i++) {
  buf.writeFloatLE(embedding[i], i * 4);
}
```

#### 3.2 Deserialization & Invariant Validation (`deserializeVectorFloat32LE`)
During decryption, the 512-byte decrypted buffer is read back into a `Float32Array(128)` and rigorously checked:
1. Buffer size must be exactly 512 bytes (`Buffer.byteLength === 512`).
2. Every float component must be finite (rejects `NaN`, `+Infinity`, `-Infinity`).
3. The computed Euclidean L2 norm must equal $1.0 \pm 10^{-3}$. Any vector violating the unit norm is rejected with `INVALID_DECRYPTED_VECTOR_NORM`.

---

### 4. CANONICAL AUTHENTICATED ADDITIONAL DATA (AAD) CONTEXT BINDING

To defeat cryptographic transplant attacks (where an adversary copies an encrypted envelope from one user's document into another, or across environments), the encryption process binds the document context into the AES-GCM authentication tag and KMS key wrap.

#### 4.1 Vulnerability of Delimiter-Based AAD
Simple delimiter-based schemes (e.g. `tenant|user|template`) are vulnerable to delimiter injection collisions if user IDs or template IDs contain delimiters.

#### 4.2 Length-Prefixed Binary Canonical Format
Kelasagara Phase 20.1 implements length-prefixed binary canonical AAD serialization:
For each of the 8 context fields, the canonical serializer writes a 32-bit big-endian unsigned integer indicating byte length ($L_i$), followed immediately by the exact UTF-8 byte payload:
$$\text{AAD} = \prod_{i=1}^8 \Big( \text{UInt32BE}(L_i) \,\|\, \text{Payload}_i \Big)$$

The 8 bound context fields are:
1. `tenantId`: Tenant identifier (e.g., `'kelasagara-f127a'`).
2. `collection`: Always the literal `'biometric_vault'`.
3. `templateId`: The unique document ID (e.g., `'enr_...'`).
4. `ownerUid`: The owning Firebase Auth user UID (e.g., `'usr_...'`).
5. `modelId`: Biometric model identifier (e.g., `'face_recognition_sface_2021dec'`).
6. `modelVersion`: Model version string (e.g., `'sface_2021dec_128d_v1'`).
7. `schemaVersion`: Schema version integer (`2`).
8. `purpose`: Strict domain separator (`'BIOMETRIC_VAULT_ENVELOPE_V2'`).

#### 4.3 Double-Barrier Cryptographic Enforcement
The canonical AAD buffer is cryptographically verified at two independent layers:
1. **Layer 1 (KMS DEK Unwrapping):** Passed to Cloud KMS as `additionalAuthenticatedData` (or `setAAD` in `LocalDevKeyProvider`). If an attacker alters `ownerUid` or `templateId`, KMS unwrap fails immediately with `KMS_UNWRAPKEY_FAILURE`.
2. **Layer 2 (AES-256-GCM Payload Deciphering):** Passed to Node.js `decipher.setAAD(aadBuffer)`. Even if a DEK were somehow decrypted, AES-256-GCM verifies that the 128-bit authentication tag authenticates the exact same AAD. Any discrepancy throws `AUTHENTICATION_TAG_VERIFICATION_FAILED`.

---

### 5. ZERO-PLAINTEXT MEMORY SANITIZATION & FAILURE MODES

Biometric security requires strict in-memory hygiene. Plaintext DEKs and decrypted biometric buffers must not linger in the JavaScript V8 heap:

1. **Zeroization in `finally`:**
   ```typescript
   let plaintextDek: Buffer | null = null;
   let decryptedPayload: Buffer | null = null;
   try {
     // ... cryptographic operations ...
   } finally {
     if (plaintextDek) plaintextDek.fill(0);
     if (decryptedPayload) decryptedPayload.fill(0);
   }
   ```
2. **KMS Calls Outside Firestore Transactions:**
   Firestore transactions must remain fast, deterministic, and free of long-running network calls. The `BiometricLifecycleCoordinatorV10` encrypts the template and obtains the wrapped DEK **before** entering `db.runTransaction()`.
3. **Fail-Closed Policy:**
   If Cloud KMS is unreachable, times out, or returns an error, the system fails closed:
   - Returns HTTP 503 `KMS_UNAVAILABLE`.
   - The Firestore transaction is never initiated.
   - The user's biometric state is preserved (`pending_face` / `UNENROLLED`).
   - The gallery epoch is not incremented.

---

### 6. ARCHITECTURAL INVARIANTS VERIFIED

- **INV-01 (Ciphertext Tamper Resistance):** Any bit flip in ciphertext, IV, or authentication tag causes immediate decryption failure.
- **INV-02 (Identity Context Binding):** Moving an encrypted envelope to a different `ownerUid` or `templateId` causes immediate decryption rejection.
- **INV-03 (Lossless Precision):** Decryption reproduces the exact original 128-D Float32 vector with 0.00000000 numerical error.
- **INV-04 (Zero-Plaintext Storage):** Zero plaintext floating-point arrays exist in newly persisted `biometric_vault` documents.
- **INV-05 (Fail-Closed Availability):** Any KMS failure prevents enrollment without leaving dangling or corrupt documents.
