# KELASAGARA BIOMETRIC ENGINE V18 / PHASE 13
## Security Remediation, Self-Healing Multi-Node Coordinator & Firestore Rules Report

**Author:** Principal Biometric Systems Architect & Application Security Engineer  
**Date:** October 29, 2026  
**Standards:** ISO/IEC 24745, ISO/IEC 19795-1, India DPDP Rules 2025, ACID Transactional Outbox  
**Release Posture:** `CONTROLLED_TEST_BUILD_ONLY` | `productionBiometricCalibrationApproved = false`  
**Status:** 🟢 **ALL 4 VULNERABILITIES REMEDIATED, COORDINATOR INTEGRATED, RULES LOCKED**  

---

## 1. Vulnerability Root-Cause & Production Fix Matrix

| Vulnerability in V12 Baseline | Exact Failure Mechanism | Production V18 / Phase 13 Architectural Fix |
| :--- | :--- | :--- |
| **1. Broken "Cancelable Hash" (`(v + 1.0) * 127.5` $\to$ `HMAC-SHA256`)** | Quantized floats fed into `HMAC-SHA256` trigger the cryptographic avalanche effect: a tiny `0.004` noise shift in one float flips ~50% of the output bits, completely destroying biometric distance preservation. | Replaced with **ISO/IEC 24745 Index-of-Maximum (IoM) Locality-Sensitive Hashing** (`computeIso24745IomCancelableCode`), which preserves angular distance on jitter ($\text{Sim} \ge 0.85$), while ensuring irreversibility and revocability on salt rotation ($\text{Sim} \approx 0.0625$). |
| **2. Delimiter-Collision in AAD (`${uid}:${faceId}:${modelVersion}:${keyId}`)** | Simple string concatenation using `:` allows boundary shifting / splicing attacks (e.g., `uid="a:b", faceId="c"` collides with `uid="a", faceId="b:c"`). | Enforced **Big-Endian 32-bit Length-Prefixed Canonical AAD Encoding** (`[u32BE len][utf8_bytes]`) for all KMS envelopes and snapshot frames (`encodeSnapshotCanonicalAad`). |
| **3. Plaintext Biometric Vectors in `KS12` Snapshots** | HMAC signing provides integrity but **zero confidentiality**. Variable-length JSON interleaved with vectors also violates memory alignment. | Upgraded to **`KS18` Encrypted & 8-Byte Aligned Snapshot** (`exportEncryptedAlignedSnapshotKs18`): encrypts the contiguous vector arena with **AES-256-GCM** bound to canonical AAD and pads headers to 8-byte boundaries. |
| **4. Split-Brain Race Between 1:N Search & WAL Append** | Concurrent nodes screening at the same epoch commit duplicate enrollments simultaneously because search epoch is detached from the commit transaction. | Implemented **Durable Firestore `runTransaction` Adapter with Search-to-Commit Epoch Fencing (`RECHECK_REQUIRED_EPOCH_DRIFT`)** and **Transactional WAL Outbox**. |

---

## 2. Phase 13.3 Self-Healing Coordinator & Cloud KMS Wrapping

### 2.1 Automated `RECHECK_REQUIRED_EPOCH_DRIFT` WAL Catch-Up Loop
In [`TransactionalGalleryCoordinatorV18`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/backend/src/services/transactional_gallery_coordinator_v18.ts), when Node B receives `RECHECK_REQUIRED_EPOCH_DRIFT` because Node A committed a new enrollment milliseconds earlier:
1. Node B single-flight fetches missing delta records from `biometric_wal_outbox` via `fetchIncrementalWalSince(localWatermarkEpoch)`.
2. Unseals the newly committed canonical SFace envelope(s) using `CloudKmsEnvelopeService.unsealTemplateV3`.
3. Performs a Copy-on-Write update to its local `HighSpeedBiometricIndexV3` arena.
4. **Re-screens 1:N duplicates against the freshly updated gallery.**
5. If the concurrent commit on Node A was the same fraudster ($\cos \ge 0.90$), Node B halts immediately with `HARD_DUPLICATE_BLOCKED` without touching Firestore.
6. If the concurrent commit was an unrelated worker, Node B retries the transaction at the new epoch and commits cleanly.

### 2.2 KMS Envelope Wrapped `KS18` Snapshots
`exportKmsWrappedSnapshotKs18` generates a fresh 256-bit ephemeral DEK, encrypts the contiguous 128-D arena with AES-256-GCM, binds it to canonical AAD, wraps the DEK using `KmsKeyProvider.wrapKey`, and returns a `KmsWrappedKs18SnapshotArtifact`. The plaintext DEK is immediately zeroized in RAM via `ephemeralDek.fill(0)`.

### 2.3 Sub-200ms Cold-Boot with WAL Tail Replay
`hydrateFromKmsSnapshotAndWalTail` unwraps the snapshot DEK via Cloud KMS, hydrates the 8-byte aligned arena into `HighSpeedBiometricIndexV3`, and replays any trailing WAL records committed after the snapshot watermark—benchmarked at **< 30 ms** cold-boot initialization.

---

## 3. Gate G-05 Firestore Rules Lockdown

Authored and validated by the `firestore-rules-author` subagent in [`firestore.rules`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/firestore.rules):
```javascript
    // Gate G-05 & V18 Transactional Biometric Collections — Strictly Server-Only (Admin SDK)
    match /biometric_vault/{uid} {
      allow read, write: if false;
    }
    match /biometric_audit_queue/{ticketId} {
      allow read, write: if false;
    }
    match /biometric_cluster_meta/{docId} {
      allow read, write: if false;
    }
    match /biometric_idempotency/{idemKey} {
      allow read, write: if false;
    }
    match /biometric_wal_outbox/{walSeq} {
      allow read, write: if false;
    }
```
- Direct client access from mobile devices is strictly denied (`allow read, write: if false;`).
- Only authorized backend Cloud Functions and Cloud Run instances utilizing Firebase Admin SDK service account credentials can access or mutate biometric records.

---

## 4. Verification Test Evidence

### 4.1 V18 & Phase 13.3 Dedicated Test Suites
- **Command:** `node --test dist/tests/firestore_transaction_adapter_v18.test.js dist/tests/transactional_gallery_coordinator_v18.test.js`
- **Output:**
  ```text
  ▶ KELASAGARA V18 / PHASE 13 — Production Firestore Transaction & KS18 Suite
    ✔ 1. Enforces read-before-write transaction discipline, retries on contention, and commits WAL outbox (4.013041ms)
    ✔ 2. Detects Search-to-Commit Race across two instances and returns RECHECK_REQUIRED_EPOCH_DRIFT (0.80725ms)
    ✔ 3. Enforces idempotent replay on identical retries and blocks idempotency payload tampering (0.512666ms)
    ✔ 4. Enforces templateGeneration fencing across re-enrollment and DPDPA §12 erasure (1.054958ms)
    ✔ 5. Verifies ISO/IEC 24745 IoM Cancelable Code preserves similarity on jitter and unlinks on salt rotation (1.448375ms)
    ✔ 6. Verifies Encrypted 8-Byte Aligned KS18 Snapshot hydration and AAD/Ciphertext tamper rejection (9.491ms)
  ✔ KELASAGARA V18 / PHASE 13 — Production Firestore Transaction & KS18 Suite (18.14425ms)
  ▶ KELASAGARA V18 / PHASE 13.3 — TransactionalGalleryCoordinatorV18 Suite
    ✔ 1. Auto-recovers from RECHECK_REQUIRED_EPOCH_DRIFT via incremental WAL catch-up when two unrelated workers enroll concurrently (12.680666ms)
    ✔ 2. Blocks concurrent cross-node duplicate fraud when the same face is submitted simultaneously to Node A and Node B (10.6155ms)
    ✔ 3. Exports KMS-wrapped KS18 encrypted snapshot and cold-boots Node C with incremental WAL tail replay (25.703ms)
  ✔ KELASAGARA V18 / PHASE 13.3 — TransactionalGalleryCoordinatorV18 Suite (50.137042ms)
  ℹ tests 9
  ℹ suites 2
  ℹ pass 9
  ℹ fail 0
  ```

### 4.2 Full Backend Regression Suite
- **Command:** `node --test --test-concurrency=1 dist/tests/*.test.js`
- **Output:**
  ```text
  ℹ tests 580
  ℹ suites 109
  ℹ pass 580
  ℹ fail 0
  ℹ duration_ms 53337.222
  ```

### 4.3 Flutter Biometric Test Suite
- **Command:** `flutter test test/profile_biometric_isolation_test.dart test/biometric_v10_phase10_flutter_test.dart test/biometric_v10_client_flow_test.dart test/biometric_v11_flutter_guided_capture_test.dart test/biometric_v12_edge_isolate_test.dart`
- **Output:**
  ```text
  00:03 +22: All tests passed!
  ```
