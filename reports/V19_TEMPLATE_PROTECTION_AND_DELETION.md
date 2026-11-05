# V19 Template Protection and Deletion Report

## 1. Envelope Encryption Architecture (KMS + AES-256-GCM)
Authoritative biometric templates stored in `biometric_vault/{uid}` are encrypted at the application layer using envelope encryption:
1. **Key Providers:**
   - `LocalDevKeyProvider`: Used for isolated local development and deterministic unit testing.
   - `CloudKmsKeyProvider`: Staging and production key management via Google Cloud KMS (`projects/.../locations/global/keyRings/.../cryptoKeys/...`).
2. **Binary Canonical AAD (Authenticated Additional Data):**
   - Eliminates delimiter collision vulnerabilities.
   - Binds `tenantId`, `uid`, `modelVersion`, and `templateGeneration` as length-prefixed binary buffers:
     $$\text{AAD} = \text{len}(T) \| T \| \text{len}(U) \| U \| \text{len}(M) \| M \| \text{generation}$$
   - Any modification to UID or tenant context renders the GCM authentication tag invalid, causing immediate decryption rejection.
3. **Nonce / IV Uniqueness:**
   - 12-byte cryptographically random IV generated via `crypto.randomBytes(12)`.
   - Verified across 1,000 successive encryptions with zero collisions.

## 2. Cancellable Biometrics & Research Caveats
- **ISO/IEC 24745:2022** requires template unlinkability, irreversibility, and renewability.
- **Index-of-Max (IoM) & BioHashing Evaluation:**
  * While pseudo-random projection maps embeddings into binary or discrete codes, published cryptanalysis demonstrates vulnerability to stolen-token and ARM (Affine Reconstruction Model) attacks.
  * In SFace, replacing cosine hypersphere comparisons with Hamming distance on projected codes degrades False Match Rate significantly.
  * **Policy Decision:** Cancelable projections remain strictly experimental. Canonical identity verification relies on KMS envelope-protected float vectors.

## 3. Right-to-Erasure Lifecycle & Cache Invalidation
When an authenticated worker exercises their right to erasure (DPDP Act / GDPR) via `/api/biometrics/template`:
1. **Vault Erasure:** `biometric_vault/{uid}` document is deleted from Firestore.
2. **In-Memory RAM Invalidation:** `InMemoryBiometricIndex.remove(uid)` purges the template from the 1:N screening cache immediately.
3. **Queue Cleanup:** Any pending submissions in `biometric_review_queue/{uid}` are scrubbed.
4. **Key Revocation:** For high-security deletions, the user-specific Data Encryption Key (DEK) is destroyed, rendering any cold backups mathematically unrecoverable.
5. **Auditing:** An immutable tombstone event `BIOMETRIC_TEMPLATE_DELETED` is appended to the audit log with timestamp, operator/user UID, and reason.
