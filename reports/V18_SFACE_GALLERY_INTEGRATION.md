# KELASAGARA V18: Canonical SFace Gallery Integration & Consistency Report (Gate G-04)

- **Document ID:** `KLS-V18-G04-SFACE-INTEGRATION`
- **Release Status:** `CONTROLLED_TEST_BUILD_ONLY`
- **Production Biometric Calibration Approved:** `false` (`PRODUCTION_BIOMETRIC_CALIBRATION_APPROVED = false`)
- **Canonical Identity Model:** `face_recognition_sface_2021dec` (`sface_2021dec_128d_v1`, 128-D L2-normalized on $\mathbb{S}^{127}$)

---

## 1. Model & Representation Compatibility Matrix

| Subsystem / Artifact | Model Identifier | Version String | Dimension & Norm | Permitted Role in V18 | Compatible with Gallery V3? |
| :--- | :--- | :--- | :--- | :--- | :---: |
| **Canonical SFace Engine** | `face_recognition_sface_2021dec` | `sface_2021dec_128d_v1` | $128\text{-D}$ Float32, $\|\mathbf{e}\|_2 = 1.0$ | **Sole Authoritative 1:1 & 1:N Identity Matcher** | **YES** |
| **`Dense500LandmarkEngineV3`** | `mediapipe_facemesh_478` | `kelasagara_biomatch_v3_dense512` | $512\text{-D}$ & $256\text{-D}$ Float32 | **Auxiliary Capture Quality (ISO 29794-5) & 3D Parallax PAD (ISO 30107-3) Only** | **NO (Rejected by Dimension/Version Guard)** |
| **Legacy v2 Whitened** | `mlkit_133_whitened` | `kelasagara_biomatch_v2_whitened` | $128\text{-D}$ Geometric | Deprecated legacy fallback | **NO (Skipped on Vault Rebuild)** |
| **Legacy v1 Geometric** | `mlkit_133_raw` | `kelasagara_biomatch_v1_geometric` | $128\text{-D}$ First-Orthant | Deprecated faulty representation | **NO (Skipped on Vault Rebuild)** |

---

## 2. Cryptographic Storage & Search Architecture

1. **Zero Plaintext Vectors in Firestore:** Biometric embeddings are never stored in plaintext Firestore fields. Each 128-D SFace vector plus ISO quality and PAD scores is packed into a **520-byte Little-Endian binary frame** (`SFACE_V3_BINARY_PAYLOAD_BYTES = 520`), encrypted with a per-record 256-bit AES-GCM Data Encryption Key (DEK), and wrapped by **Google Cloud KMS HSM** (`CloudKmsKeyProvider`) bound to canonical length-prefixed AAD (`purpose`, `tenantId`, `uid`, `modelVersion`, `templateSchemaVersion`).
2. **Trusted Backend-Only Contiguous RAM Arena:** `GalleryConsistencyServiceV3` unseals compatible `sface_2021dec_128d_v1` envelopes strictly inside the trusted backend memory space (`HighSpeedBiometricIndexV3`).
3. **Client-Side Lockdown:** `assertNoClientSuppliedVectors()` rejects any request payload containing precomputed embeddings or verification flags. Direct client reads/writes to `biometric_vault` and `biometric_audit_queue` remain denied by Firestore security rules (Gate G-05).

---

## 3. Separate 1:1 and 1:N Decision Policies

| Operation | Policy Identifier | Thresholds Applied | Outcome Semantics |
| :--- | :--- | :--- | :--- |
| **1:1 Verification** (`verifyWorker1to1`) | `SFACE_1TO1_VERIFICATION_POLICY_V18` | $\tau_{1:1} = 0.363$ | Compares probe strictly against claimed account's enrolled 128-D SFace template. Returns `MATCH_CONFIRMED` ($\ge 0.363$) or `NON_MATCH_REJECTED` ($< 0.363$). |
| **1:N Duplicate Screening** (`screenForDuplicates1toN` / `enrollWithGlobalEpochBump`) | `SFACE_1TON_DUPLICATE_POLICY_V18` | $\tau_{\text{warn}} = 0.74$, $\tau_{\text{hard}} = 0.90$ | $< 0.74 \to$ `CLEAN_APPROVED`; $[0.74, 0.90) \to$ `DUPLICATE_WARNING_FLAGGED` (enrolls as `PENDING_AUDIT` + enqueues human review ticket); $\ge 0.90 \to$ `HARD_DUPLICATE_BLOCKED`. |

---

## 4. Verified vs. Unverified Gallery-Consistency Guarantees

- **Verified Within Single Backend Instance:**
  - Serialized mutation queue (`enqueueSerializedMutation`) prevents two concurrent enrollments on the same Node.js instance from passing 1:N duplicate checks simultaneously.
  - Lock-free Copy-on-Write (`cloneWithUpsert`, `cloneWithoutUid`) ensures concurrent 1:1 and 1:N readers never observe a partially mutated `Float32Array` arena.
  - Partial persistence failure rollback: if `incrementGlobalEpoch` fails after `saveVaultDocument`, the newly written vault document is deleted and the index marks itself unhealthy (`fail-closed`).
- **Remaining Multi-Instance Distributed Limitation (Release Blocker):**
  - Across multiple horizontally scaled Cloud Run / Cloud Functions instances, optimistic epoch compare-and-swap (`incrementGlobalEpoch(expectedCurrentEpoch)`) detects concurrent writes when backed by a Firestore transaction on the global metadata document, but full distributed mutual exclusion during the 1:N check-then-write window requires wrapping the epoch read, candidate check, and vault write inside a single Firestore transaction or routing enrollment mutations through a single-concurrency queue.

---

## 5. Remaining Release Blockers Before Production Approval

1. **Empirical Field Calibration (Gate G-01):** Thresholds (`0.363`, `0.74`, `0.90`) remain candidate values until validated via `calibration_harness.ts` on an authorized, de-identified multi-session dataset of at least $300$ subjects ($3,000+$ impostor trials).
2. **Physical PAD Level 1/2 Evaluation (Gate G-02):** Execution of `reports/PHYSICAL_PAD_EVALUATION_PROTOCOL.md` across physical print and 120Hz OLED replay targets.
3. **Distributed Enrollment Transaction Wiring:** Backing `BiometricVaultPersistenceAdapter.incrementGlobalEpoch(expectedEpoch)` with a production Firestore `runTransaction` precondition check.

