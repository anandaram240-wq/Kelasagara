# KELASAGARA V16: BIOMETRIC ARCHITECTURE DECISION RECORD

**Document ID:** `reports/V16_BIOMETRIC_ARCHITECTURE_DECISION.md`  
**Execution Phase:** Architecture Consolidation & Cryptographic Hardening  
**Author:** Principal Biometric Systems Architect  
**Classification:** `CONTROLLED_TEST_BUILD_ONLY`

---

## 1. CONTEXT & PROBLEM STATEMENT

Kelasagara operates a high-trust informal worker marketplace where worker identity, anti-spoofing, and cross-account duplication prevention are vital. However, prior architectures exhibited severe tensions between:
1. Cloud KMS envelope encryption guarantees vs. Firestore native vector search requirements.
2. OpenCV YuNet 5-point landmark limitations vs. vertical eyelid aperture anti-spoofing requirements.
3. Automated fraud rejection vs. worker human rights under DPDPA 2023.

This Architecture Decision Record (ADR) codifies the definitive technical decisions resolving these tensions.

---

## 2. DECISION 1: SEPARATION OF ENCRYPTED VAULT AND VOLATILE MATCHER STATE

### The Conflict
Storing plaintext float vectors directly in `biometric_vault` documents enabled Firestore's native `findNearest` KNN queries, but directly violated Invariant INV-03 and ISO/IEC 24745 (confidentiality at rest). Conversely, storing only AES-256-GCM ciphertexts prevented scalable 1:N KNN queries.

### The Decision (Option B Architecture)
1. **Application-Encrypted Vault (`biometric_vault`):** Authoritative storage contains **only** AES-256-GCM ciphertexts, CSPRNG IVs, 128-bit authentication tags, and Cloud KMS wrapped DEKs. Plaintext float vectors are **never** persisted to Firestore.
2. **Volatile Matcher State (`InMemoryBiometricIndex`):** During runtime, instances maintain an in-memory index of unit hypersphere embeddings. The index is synchronized with Firestore version epochs and lease coordinators.
3. **Multi-Instance Deduplication Leases:** For cross-worker duplicate screening, the node holding the deduplication transaction acquires an atomic Firestore lease (`biometric_enrollment_sessions`), verifies against volatile RAM, and commits to the encrypted vault.

---

## 3. DECISION 2: AUTHORITATIVE PAD & 6-POINT OCULAR CONTOURS

### The Conflict
OpenCV YuNet outputs bounding boxes and 5 facial keypoints:
- Right eye center
- Left eye center
- Nose tip
- Right mouth corner
- Left mouth corner

Computing vertical palpebral fissure aperture ($\text{EyeHeight}_2 < 0.6 \times \text{EyeHeight}_1$) from 5 keypoints without eyelid contour points is geometrically impossible and mathematically invalid.

### The Decision
1. **Strict Contour Requirement:** `ChallengeBurstPadService` mandates 6-point eyelid contours (e.g., Soukupová & Čech formula via MediaPipe 478-point mesh) or a validated dedicated ONNX eye-state classifier.
2. **Fail-Closed Fallback:** If the client camera detector provides only 5-point landmarks, the server returns `PAD_INCONCLUSIVE`. It **never** fabricates fake aperture metrics or pretends 5 points can measure eyelid aperture.
3. **Passive Texture & Temporal Luma Verification:** In addition to active blink kinematics, server-side temporal PAD enforces:
   - Max 15% frame-to-frame luma jump (intercepting screen glare and replay flares).
   - Cross-frame SFace identity continuity ($\ge 0.80$ similarity across burst frames).
   - Byte-identical frame replay rejection.

---

## 4. DECISION 3: NON-DESTRUCTIVE QUARANTINE & ALTERNATE KYC ELIGIBILITY

### The Conflict
Previous implementations permanently deleted or shredded biometric templates when an admin rejected a duplicate match, destroying legal audit trails and permanently locking workers out of the platform.

### The Decision
1. **`QUARANTINED_DUPLICATE_SUSPICION`:** When review officers or automated thresholds flag a duplicate without whitelisting, the account enters `quarantined_duplicate_suspicion`.
2. **Preservation of Forensic Evidence:** Ciphertexts, wrapped DEKs, and audit logs are retained in quarantine for legal compliance under DPDPA 2023 §8(3).
3. **Alternate KYC Fallback:** The worker is flagged with `alternateVerificationEligible: true`, allowing manual document review, phone verification, or in-person KYC at platform hubs without requiring biometric bypass.

---

## 5. DECISION 4: KMS ENVELOPE ENCRYPTION & KEY ROTATION

### Architecture
- **Algorithm:** AES-256-GCM.
- **Key Hierarchy:** Google Cloud KMS HSM Root KEK wraps ephemeral 256-bit DEKs.
- **AAD Binding:**
  - Payload AAD: `kelasagara-biometric-v16|uid:${uid}|purpose:${purpose}|tenant:${tenantId}`
  - DEK AAD: `kelasagara-biometric-v16|uid:${uid}|purpose:${purpose}|ver:${keyVersion}`
- **Zero-Downtime Re-wrapping:** `rewrapTemplateDek` unwraps the DEK using the old KEK version and re-wraps it with the new KEK version, updating Firestore without needing to decrypt or re-encrypt the biometric vector.
