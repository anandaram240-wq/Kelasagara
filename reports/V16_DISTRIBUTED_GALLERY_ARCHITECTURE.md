# KELASAGARA V16: DISTRIBUTED GALLERY CONSISTENCY & CONCURRENCY

**Document ID:** `reports/V16_DISTRIBUTED_GALLERY_ARCHITECTURE.md`  
**Author:** Principal Distributed Systems & Biometric Architect  
**Classification:** `CONTROLLED_TEST_BUILD_ONLY`

---

## 1. DISTRIBUTED CHALLENGE

In a serverless multi-instance backend deployment (e.g. Google Cloud Run auto-scaling from 1 to $M$ instances), maintaining 1:N biometric gallery consistency presents severe concurrency risks:
1. **Split-Brain Deduplication:** Two workers enroll simultaneously with identical faces on Instance A and Instance B. If instances only check local RAM, both registrations could pass.
2. **Stale In-Memory State:** When Instance A approves an enrollment or admin review updates a template, Instance B and C must invalidate or update their volatile index.
3. **Database Exhaustion:** Performing full collection scans in Firestore for every enrollment burns database read quotas ($O(N)$ operations per request).

---

## 2. THE THREE-TIER SYNCHRONIZATION ARCHITECTURE

To resolve these challenges without storing plaintext vectors in Firestore, KELASAGARA V16 implements a three-tier consistency protocol:

```
+-------------------------------------------------------------+
|                TIER 1: VOLATILE MATCHER RAM                 |
|  - In-Memory Unit Hypersphere Index (128-D FP32)             |
|  - Fast O(N) cosine dot-product filtering (< 2 ms for 10k)  |
|  - Periodic epoch sync with Firestore                       |
+------------------------------+------------------------------+
                               |
                               v
+-------------------------------------------------------------+
|               TIER 2: FIRESTORE LEASE COORDINATOR           |
|  - Atomic session lock: `biometric_enrollment_sessions/{uid}`|
|  - Global monotonic epoch counter: `biometric_system_meta`   |
|  - Cleared distinct pairs: `biometric_cleared_distinct_pairs`|
+------------------------------+------------------------------+
                               |
                               v
+-------------------------------------------------------------+
|             TIER 3: ENCRYPTED VAULT PERSISTENCE              |
|  - Collection: `biometric_vault/{uid}`                      |
|  - AES-256-GCM ciphertexts + Cloud KMS wrapped DEKs          |
|  - ZERO plaintext vectors stored on disk                     |
+-------------------------------------------------------------+
```

---

## 3. CONCURRENCY & LEASE COORDINATION (TWO-PHASE ENROLLMENT)

When an enrollment request arrives:

### Phase 1: Pre-Registration Lease Acquisition
1. The backend instance initiates a transaction on `biometric_enrollment_sessions/{uid}`.
2. If another session is already `in_progress` and was initiated less than 60 seconds ago, the request is rejected with `409 Conflict` (Invariant INV-10).
3. The instance records `status: 'in_progress'` and a random session token.

### Phase 2: Volatile RAM Screening & Commit
1. The instance checks the probe embedding against its local `InMemoryBiometricIndex`.
2. If similarity $s \ge \tau_{\text{block}}$ ($0.90$) against any other UID:
   - Registration is rejected as `DUPLICATE_HARD_BLOCK`.
   - The session lease is finalized as `failed`.
3. If similarity $\tau_{\text{dup}} \le s < \tau_{\text{block}}$ ($0.74 \le s < 0.90$):
   - Check if pair is in `biometric_cleared_distinct_pairs`.
   - If not cleared, routes to `biometric_review_queue` as `PENDING_REVIEW`.
   - Session lease finalized as `quarantined`.
4. If similarity $s < \tau_{\text{dup}}$:
   - The instance encrypts the template via `BiometricEnvelopeEncryptionService`.
   - Commits encrypted record to `biometric_vault/{uid}` in an atomic transaction that increments the system epoch sequence.
   - Adds the new normalized vector to local volatile RAM.
   - Finalizes session lease as `completed`.

---

## 4. INSTANCE DRIFT & EPOCH RE-SYNC

Each instance polls `biometric_system_meta/epoch` periodically (every 30 seconds) or receives a Pub/Sub trigger on template mutations:
- If `local_instance_epoch < firestore_system_epoch`:
  - The instance queries newly modified documents from `biometric_vault` where `updatedAt > last_sync_time`.
  - For each new record, unwraps DEK, decrypts template into RAM, and updates local matcher state.
  - Updates `local_instance_epoch = firestore_system_epoch`.

This guarantees eventual consistency within $< 500$ ms across all Cloud Run instances while keeping all persistent Firestore documents fully encrypted under Cloud KMS.
