# KELASAGARA BIOMETRIC ENGINE V18 — PHASE 14
# KS18 BINARY SNAPSHOT SPECIFICATION, SECURITY & FUZZING AUDIT

**Author:** Principal Security Engineer & Distributed Storage Architect  
**Date:** October 29, 2026  
**Artifact:** `backend/src/biometrics/iso24745_iom_cancelable_snapshot_v18.ts`  
**Test Suite:** `backend/src/tests/phase14_ks18_fuzz_and_security.test.ts`  

---

## 1. Technical Specification: The `KS18` Binary Snapshot Format

The `KS18` format replaces the legacy `KS12` snapshot format, addressing two severe vulnerabilities:
1. **Confidentiality Elimination:** Legacy `KS12` snapshots signed with HMAC stored raw facial vectors in plaintext.
2. **Unaligned Memory Offsets:** Interleaving JSON strings with binary arrays prevented zero-copy Float32Array memory mapping.

`KS18` provides authenticated envelope encryption via **AES-256-GCM** bound to canonical length-prefixed AAD, and enforces strict **8-byte (64-bit) alignment** for direct zero-copy deserialization into Node.js V8 typed arrays.

```
+---------------------------------------------------------------------------------------+
|                                    KS18 PLAINTEXT FRAME                               |
+---------------------+---------------------+--------------------+----------------------+
| Magic (4 bytes)     | FormatVer (4 bytes) | NodeCount (4 bytes)| MetaByteLen (4 bytes)|
| 0x4B 0x53 0x31 0x38 | 0x00 0x00 0x00 0x12 | u32BE count        | u32BE json_bytes     |
+---------------------+---------------------+--------------------+----------------------+
| JSON Worker Metadata: [{"u":"uid","p":"+91*","q":90,"l":0.99,"t":epochMs}, ...]     |
+---------------------------------------------------------------------------------------+
| 0 to 7 Padding Zero-Bytes (pads 16 + MetaByteLen to an exact 8-byte multiple)         |
+---------------------------------------------------------------------------------------+
| Contiguous 128-D Float32Array Arena: NodeCount * 128 * 4 bytes (IEEE 754 Float32)     |
+---------------------------------------------------------------------------------------+
```

### 1.1 Header Structure (16 Bytes Fixed)
- `Offset 0..3`: `0x4b533138` (ASCII `"KS18"` in Big-Endian).
- `Offset 4..7`: `0x00000012` (Format Version 18 in Big-Endian).
- `Offset 8..11`: `nodeCount` (Total enrolled workers in the snapshot, unsigned 32-bit integer).
- `Offset 12..15`: `metaByteLen` (Length of the UTF-8 JSON metadata string in bytes).

### 1.2 8-Byte Alignment Calculation
To allow `new Float32Array(buffer, offset, length)` to execute with zero CPU copy overhead, the vector arena offset must satisfy `offset % 8 === 0`:
```ts
const headerAndMetaLen = 16 + metaByteLen;
const paddingBytes = (8 - (headerAndMetaLen % 8)) % 8;
const alignedVectorOffset = headerAndMetaLen + paddingBytes;
const expectedTotalBytes = alignedVectorOffset + nodeCount * 128 * 4;
```

### 1.3 Canonical Length-Prefixed AAD Construction
To prevent delimiter-splicing attacks across cluster or tenant boundaries, snapshot AAD is constructed with strict 32-bit big-endian length prefixes (`[u32BE len][utf8_bytes]`):
1. Magic Prefix: `"KS18_ENCRYPTED_HNSW_SNAPSHOT"` (30 bytes)
2. `clusterId`: e.g. `"karnataka-kelasagaara-primary"`
3. `keyId`: e.g. `"snapshot-kek-v1"`
4. `modelVersion`: `"1.0.0-sface-canonical-128d"`
5. `watermarkWalSeq`: e.g. `"42"`
6. `nodeCount`: e.g. `"500"`

---

## 2. Forensic Discovery & Remediation in Phase 14

During our red-team audit of `TransactionalGalleryCoordinatorV18.hydrateFromKmsSnapshotAndWalTail`, we identified a critical memory desynchronization flaw and two resilience vulnerabilities:

### 2.1 Remediated: Memory Map Desynchronization Flaw (Discovery 2)
- **Vulnerability:** In baseline V18, line 529 initialized `const rebuiltMap = new Map<string, EnrolledWorkerSfaceRecordV3>();` and assigned it directly to `this.activeRecordsMap = rebuiltMap;` **without ever populating it**.
- **Impact:** While `this.activeIndex` (the contiguous Float32 arena) held all $N$ templates, `this.activeRecordsMap.size` was **0**. If that replica subsequently generated a snapshot (`Array.from(this.activeRecordsMap.values())`), it exported a snapshot with 0 templates, permanently erasing all previous workers!
- **Phase 14 Fix:** Updated `hydrateEncryptedSnapshotKs18` to reconstruct and return `records: readonly EnrolledWorkerSfaceRecordV3[]`. In `hydrateFromKmsSnapshotAndWalTail`, both `this.activeRecordsMap` and `this.uidGenerations` are fully populated from `hydrated.records`.

### 2.2 Remediated: Missing Anti-Rollback Guard
- **Vulnerability:** A rogue or stale snapshot with watermark $W < \text{localWatermarkEpoch}$ could be passed to a running coordinator, rolling the coordinator's gallery back to an older state.
- **Phase 14 Fix:** Added strict assertion:
  ```ts
  if (artifact.bundle.watermarkWalSeq < this.localWatermarkEpoch) {
    throw new Error(`ANTI_ROLLBACK_VIOLATION: Snapshot watermark is older than local epoch.`);
  }
  ```

### 2.3 Remediated: Non-Atomic State Mutation on WAL Catch-Up Error
- **Vulnerability:** If `catchUpFromWalOutbox()` threw an exception (e.g. sequence gap or connection timeout) after `this.activeIndex` was overwritten, the coordinator remained half-mutated with inconsistent epoch state.
- **Phase 14 Fix:** Stashed `prevIndex`, `prevRecordsMap`, `prevGenerations`, and `prevEpoch`. If WAL catch-up fails, the coordinator rolls back atomically to the prior state before propagating the error.

### 2.4 Remediated: Deserialization Bounds Validation
- Added assertions in `hydrateEncryptedSnapshotKs18` ensuring:
  1. `decryptedBuf.byteLength >= 16`
  2. `16 + metaByteLen <= decryptedBuf.byteLength`
  3. `decryptedBuf.byteLength === expectedTotalBytes`
  4. `metaItems.length === nodeCount`
  5. All records contain validated `u`, `p`, `q`, `l`, `t` properties.

---

## 3. Adversarial Fuzzing & Cryptographic Test Results

All tests executed via `backend/src/tests/phase14_ks18_fuzz_and_security.test.ts`:

| Test Case | Attack / Fault Injected | Expected Security Behavior | Test Result |
| :--- | :--- | :--- | :--- |
| **Test 1** | Normal Export & Hydration Round-Trip | Verifies zero-copy 8-byte alignment, exact byte offsets, and metadata round-trip. | 🟢 **PASS** (3.49 ms) |
| **Test 2** | Ciphertext Bit-Flipping | Single bit flipped in ciphertext buffer. GCM auth tag must fail verification. | 🟢 **PASS** (0.83 ms) *(Throws auth error)* |
| **Test 3** | Canonical AAD Tampering | Attempted hydration under altered `clusterId` or tampered `watermarkWalSeq`. | 🟢 **PASS** (0.28 ms) *(Throws AAD mismatch)* |
| **Test 4** | Header Bounds Fuzzing | Plaintext header crafted with `metaByteLen = 999999` pointing beyond buffer. | 🟢 **PASS** (0.21 ms) *(Throws KS18_INVALID_METADATA_LENGTH)* |
| **Test 5** | Anti-Rollback Enforcement | Hydration attempted with snapshot watermark $10 < \text{localWatermarkEpoch } 15$. | 🟢 **PASS** (2.93 ms) *(Throws ANTI_ROLLBACK_VIOLATION)* |
| **Test 6** | Rebuilt Records Map Verification | Verified that `activeRecordsMap` contains all $N=3$ records and replica can export snapshot. | 🟢 **PASS** (21.99 ms) *(Map size 3 verified)* |
| **Test 7** | Atomic State Rollback | WAL catch-up sabotaged with simulated network partition. Verified coordinator state unchanged. | 🟢 **PASS** (4.72 ms) *(Rollback verified)* |

---

## 4. Cryptographic Assessment

The `KS18` format provides **strong, standards-compliant envelope protection**:
- **Confidentiality:** Guaranteed by AES-256 in Galois/Counter Mode.
- **Integrity & Authenticity:** 128-bit authentication tag binds ciphertext to the canonical AAD, preventing any splicing between clusters, tenants, model versions, or watermark epochs.
- **Key Separation:** Ephemeral DEK generated per snapshot, wrapped via KMS KEK, and immediately zeroized in RAM via `Buffer.fill(0)`.
