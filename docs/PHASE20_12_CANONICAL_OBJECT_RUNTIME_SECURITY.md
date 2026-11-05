# KELASAGARA V20.12: RUNTIME CANONICAL FACE OBJECT SECURITY & PROVENANCE BOUNDARY

**Project:** Kelasagara Biometric Security Architecture  
**Phase:** V20.12  
**Parent Phase:** V20.11 (`412def0`)  
**Working Branch:** `security/phase20.12-biometric-trust-provenance`  
**Classification:** Runtime Memory Security & Computer Vision Pipeline Guard  

---

## 1. THE DEFECT IN PURE STRUCTURAL VALIDATION

Prior to Phase 20.12, `CanonicalAlignedFace112Factory.validateBuffer()` verified:
- `Buffer.isBuffer(buf) === true`
- `buf.length === 112 * 112 * 3` ($37,632$ bytes)
- Non-degenerate pixel range ($min \ne 0 \lor max \ne 0$, $min \ne 255 \lor max \ne 255$)
- Minimum pixel variance ($\text{var} > \text{threshold}$)

### Forensic Vulnerability:
While necessary, structural checks and pixel variance **cannot prove that an image represents an aligned human face**. An attacker or buggy client could supply:
- A raw, unaligned photo cropped to $112 \times 112$
- Random Gaussian or uniform high-variance noise
- Synthetic geometric patterns or scenic textures
- An unsafe TypeScript cast (`rawBuffer as CanonicalAlignedFace112`)

If such buffers enter `extractCanonicalEmbeddingFromAligned112()`, SFace produces high-dimensional embeddings that corrupt the gallery index and trigger false duplicate matches or false non-matches.

---

## 2. MODULE-PRIVATE RUNTIME PROVENANCE TRACKING

Phase 20.12 introduces an internal cryptographic provenance boundary:

```typescript
const PIPELINE_PROVENANCE_KEY = randomBytes(32);
const TRUSTED_CANONICAL_PROVENANCE = new WeakMap<Buffer, CanonicalAlignedFace112Provenance>();

function computeBufferHmac(buf: Buffer): string {
  return createHmac('sha256', PIPELINE_PROVENANCE_KEY).update(buf).digest('hex');
}
```

### 2.1 The Two-Gate Invariant
To reach `extractCanonicalEmbeddingFromAligned112()`, a buffer must satisfy:
1. **Gate 1 (Authoritative Generation):**
   The buffer must be produced by `CanonicalSFaceEngineV10.alignFaceToCanonical112()`. Upon successful Umeyama affine warp, the engine computes an HMAC of the pixel bytes using the ephemeral process key and registers it in the module-private `WeakMap`.
2. **Gate 2 (Zero-Tampering Verification):**
   When `extractCanonicalEmbeddingFromAligned112()` receives a buffer, it retrieves the provenance metadata from the `WeakMap` and verifies:
   $$\text{computeBufferHmac}(buf) == \text{provenance.hmacSignature}$$
   If the buffer was never registered, or was mutated after registration, execution fails closed with:
   `BiometricPreprocessingError('CANONICAL_EMBEDDING_FAILED', 'UNAUTHORIZED_CANONICAL_FACE_OBJECT')`

---

## 3. ADVERSARIAL PENETRATION RESULTS

| Test Fixture | Input Condition | Expected Result | Verified Result |
| :--- | :--- | :--- | :--- |
| **Arbitrary Buffer** | `Buffer.alloc(100)` | Rejected by length guard (`INVALID_BYTE_LENGTH`) | PASS |
| **Valid-Length Noise** | `randomBytes(37632)` | Rejected (`UNAUTHORIZED_CANONICAL_FACE_OBJECT`) | PASS |
| **Fabricated Nominal Cast** | `Buffer.alloc(37632) as CanonicalAlignedFace112` | Rejected (`UNREGISTERED_BUFFER`) | PASS |
| **Post-Registration Mutation** | Byte at offset 500 modified after alignment | Rejected (`TAMPERED_BUFFER`) | PASS |
| **Authoritative Aligned Face** | Produced by `alignFaceToCanonical112` | Accepted; produces unit vector on $S^{127}$ | PASS |
