# KELASAGARA V20.1: ZERO-PLAINTEXT BIOMETRIC VAULT
## PHASE 20.1 TECHNICAL REPORT 2: BIOMETRIC VAULT SCHEMA SPECIFICATION (V1 vs V2)

**Author:** Principal Security Architect & Senior Backend Engineer  
**Project:** Kelasagara Major Project  
**Phase:** 20.1 — Zero-Plaintext Biometric Vault  
**Collection:** `/biometric_vault/{enrollmentId}`  
**Status:** Canonical Release Specification  

---

### 1. OVERVIEW & SCHEMA EVOLUTION

In Phase 20.1, the document schema of the Firestore `biometric_vault` collection underwent a major structural upgrade from **Schema Version 1 (Legacy Plaintext)** to **Schema Version 2 (Authenticated Encrypted Envelope)**.

The transition adheres to the following core principles:
1. **Zero Plaintext Vectors in New Writes:** New enrollments and re-enrollments write strictly `schemaVersion: 2` envelopes. Plaintext fields (`canonicalEmbedding`, `sfaceEmbedding128`, `embedding`) are completely absent.
2. **Dual-Read Backward Compatibility:** During the transition window before full migration, backend readers (`BiometricLifecycleCoordinatorV10` and `FirestoreCompatibleGalleryIndex`) dynamically detect `schemaVersion: 2` (or the presence of `biometricEnvelope`) and decrypt it on the fly, while continuing to support unmigrated legacy V1 records.
3. **Atomic Migration:** Existing legacy documents are converted to Schema V2 via an atomic transaction that writes the encrypted envelope and executes `FieldValue.delete()` on all plaintext array fields.

---

### 2. DETAILED SCHEMA COMPARISON

```
+----------------------------------------------------------------------------------------------------+
|                                SCHEMA VERSION 1 vs SCHEMA VERSION 2                                |
+----------------------------------------------------------------------------------------------------+
|  FIELD NAME                  |  SCHEMA V1 (LEGACY)             |  SCHEMA V2 (PHASE 20.1 ZERO-PLAIN) |
+------------------------------+---------------------------------+------------------------------------+
|  enrollmentId                |  string ("enr_...")             |  string ("enr_...")                |
|  owningUid                   |  string ("usr_...")             |  string ("usr_...")                |
|  status                      |  "ACTIVE" | "SUPERSEDED"       |  "ACTIVE" | "SUPERSEDED"           |
|  schemaVersion               |  undefined (or 1)               |  2 (number, literal)               |
|  biometricEnvelope           |  undefined                      |  Map<string, any> (Encrypted Env)  |
|    .algorithm                |  N/A                            |  "AES-256-GCM"                     |
|    .encoding                 |  N/A                            |  "FLOAT32_LE_V1"                   |
|    .ciphertextBase64         |  N/A                            |  string (Base64, 512 bytes enc)    |
|    .ivBase64                 |  N/A                            |  string (Base64, 12 bytes IV)      |
|    .authTagBase64            |  N/A                            |  string (Base64, 16 bytes Tag)     |
|    .wrappedDekBase64         |  N/A                            |  string (Base64, wrapped DEK)      |
|    .kmsKeyVersion            |  N/A                            |  string (Cloud KMS Key Version)    |
|    .aadVersion               |  N/A                            |  1 (number)                        |
|    .envelopeVersion          |  N/A                            |  2 (number)                        |
|    .createdAtEpochMs         |  N/A                            |  number (timestamp)                |
|  metadata                    |  N/A                            |  Map<string, any>                  |
|    .modelId                  |  "face_recognition_sface_..."   |  "face_recognition_sface_..."      |
|    .modelVersion             |  "sface_2021dec_128d_v1"        |  "sface_2021dec_128d_v1"           |
|    .dimensions               |  128                            |  128 (number)                      |
|    .matchingSpace            |  "SFACE_NEURAL_SPACE"           |  "SFACE_NEURAL_SPACE"              |
|    .createdAtEpochMs         |  number                         |  number                            |
|  canonicalEmbedding          |  Array<number> (128 floats)     |  REMOVED (FieldValue.delete())     |
|  sfaceEmbedding128           |  Array<number> (128 floats)     |  REMOVED (FieldValue.delete())     |
|  embedding                   |  Array<number> (legacy)         |  REMOVED (FieldValue.delete())     |
+----------------------------------------------------------------------------------------------------+
```

---

### 3. CANONICAL V2 FIRESTORE DOCUMENT JSON EXAMPLE

```json
{
  "schemaVersion": 2,
  "enrollmentId": "enr_a8f9c1d2e3b4a5c6d7e8f9a0b1c2d3e4",
  "owningUid": "usr_99xK8LmNpQrStUvWxYz1234567890",
  "status": "ACTIVE",
  "biometricEnvelope": {
    "algorithm": "AES-256-GCM",
    "encoding": "FLOAT32_LE_V1",
    "ciphertextBase64": "vA3xL5...[512 bytes encrypted]...Z8==",
    "ivBase64": "3mP9Lq81kPv4/2aQ",
    "authTagBase64": "9jK2lM3nP4qR5sT6uV7w==",
    "wrappedDekBase64": "CiQA9v...[KMS encrypted 256-bit DEK]...Ew==",
    "kmsKeyVersion": "projects/kelasagara-f127a/locations/global/keyRings/biometric-security-ring/cryptoKeys/biometric-vault-kek-v1/cryptoKeyVersions/1",
    "aadVersion": 1,
    "envelopeVersion": 2,
    "createdAtEpochMs": 1793460000000
  },
  "metadata": {
    "modelId": "face_recognition_sface_2021dec",
    "modelVersion": "sface_2021dec_128d_v1",
    "dimensions": 128,
    "matchingSpace": "SFACE_NEURAL_SPACE",
    "createdAtEpochMs": 1793460000000
  },
  "epochVersion": 22,
  "lastUpdated": 1793460000000
}
```

---

### 4. FIELD DEFINITIONS & STRICT CONSTRAINTS

#### 4.1 Root Document Fields
- **`schemaVersion` (number, required):** Value must be exactly `2`. Indicates that the template is governed by Phase 20.1 envelope encryption rules.
- **`enrollmentId` (string, required):** Globally unique template identifier prefixed with `'enr_'`. Immutable; bound into canonical AAD.
- **`owningUid` (string, required):** Firebase Authentication User UID prefixed with `'usr_'`. Immutable; bound into canonical AAD.
- **`status` (string, required):** Lifecycle status (`"ACTIVE"` or `"SUPERSEDED"`). Only active templates participate in 1:1 and 1:N deduplication matching.

#### 4.2 `biometricEnvelope` Sub-Fields
- **`algorithm` (string, required):** Fixed literal `"AES-256-GCM"`. Reject any other algorithm.
- **`encoding` (string, required):** Fixed literal `"FLOAT32_LE_V1"`. Specifies 512-byte little-endian IEEE-754 binary packing.
- **`ciphertextBase64` (string, required):** Base64-encoded encrypted binary payload. Decrypts to exactly 512 bytes.
- **`ivBase64` (string, required):** Base64-encoded 96-bit (12 bytes) CSPRNG nonce. Must never be reused.
- **`authTagBase64` (string, required):** Base64-encoded 128-bit (16 bytes) Galois message authentication tag.
- **`wrappedDekBase64` (string, required):** Base64-encoded DEK wrapped under Cloud KMS KEK with canonical AAD.
- **`kmsKeyVersion` (string, required):** Fully-qualified Cloud KMS key version identifier used during wrapping.
- **`aadVersion` (number, required):** Integer version of the AAD construction format (currently `1`).
- **`envelopeVersion` (number, required):** Envelope specification version (currently `2`).
- **`createdAtEpochMs` (number, required):** Monotonically increasing epoch timestamp of encryption.

#### 4.3 Forbidden Fields in V2
Under Phase 20.1 security invariants, the following fields are strictly prohibited from appearing in any newly written or migrated `biometric_vault` document:
- `canonicalEmbedding` (MUST BE NIL)
- `sfaceEmbedding128` (MUST BE NIL)
- `embedding` (MUST BE NIL)
- `rawVector` (MUST BE NIL)

---

### 5. DUAL-READ COMPATIBILITY LOGIC

To prevent service interruption during migration, reader components implement deterministic schema detection:

```typescript
const isSchemaV2 = 
  data.schemaVersion === 2 || 
  data.biometricEnvelope !== undefined;

if (isSchemaV2) {
  // Path A: Authenticated Decryption
  const decryptedVector = await cryptoService.decryptTemplate(
    data.biometricEnvelope,
    {
      tenantId: 'kelasagara-f127a',
      collection: 'biometric_vault',
      templateId: doc.id,
      ownerUid: data.owningUid,
      modelId: data.metadata?.modelId || 'face_recognition_sface_2021dec',
      modelVersion: data.metadata?.modelVersion || 'sface_2021dec_128d_v1',
      schemaVersion: 2,
      purpose: 'BIOMETRIC_VAULT_ENVELOPE_V2',
    }
  );
  // Use decryptedVector in matching
} else {
  // Path B: Backward-Compatible Legacy Read (Unmigrated V1)
  const legacyVector = data.canonicalEmbedding || data.sfaceEmbedding128;
  if (!legacyVector) throw new Error('MALFORMED_VAULT_RECORD');
  // Use legacyVector in matching
}
```
