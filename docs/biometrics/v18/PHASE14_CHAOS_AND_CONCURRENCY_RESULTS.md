# KELASAGARA BIOMETRIC ENGINE V18 — PHASE 14
# MULTI-NODE CHAOS, CONCURRENCY & SPLIT-BRAIN VALIDATION RESULTS

**Author:** Principal Distributed Systems Reliability Engineer  
**Date:** October 29, 2026  
**Cluster Architecture:** 3-Node Active-Active Replica Cluster (Node A, Node B, Node C)  
**Evaluated Artifacts:** `TransactionalGalleryCoordinatorV18`, `FirestoreBiometricTransactionAdapterV18`  
**Test Suite:** `backend/src/tests/phase14_multi_node_chaos.test.ts` (18 Scenarios, 100% Passing)  

---

## 1. Executive Summary

This report documents the results of executing an 18-scenario chaos test harness against a simulated multi-node Kelasagara V18 biometric cluster. The mission was to attempt to induce split-brain conditions, race conditions, silent data corruption, or duplicate fraud bypass across concurrently operating replica nodes.

All 18 chaos scenarios were executed successfully with zero split-brain occurrences and zero duplicate bypasses.

---

## 2. Cluster Architecture & Protocol Invariants

```
                             +----------------------------------------+
                             |  Google Cloud Firestore / Datastore    |
                             |  - biometric_vault/{uid}               |
                             |  - biometric_cluster_meta/global_state |
                             |  - biometric_wal_outbox/{walSeq}       |
                             +----------------------------------------+
                                    ^                     ^
                         OCC Commits|                     |OCC Commits
                                    v                     v
+-----------------------------------+     +-----------------------------------+
|              Node A               |     |              Node B               |
|  - HighSpeedBiometricIndexV3      |     |  - HighSpeedBiometricIndexV3      |
|  - localWatermarkEpoch: 1         |     |  - localWatermarkEpoch: 2         |
|  - WAL Consumer (Tail Replay)     |     |  - WAL Consumer (Tail Replay)     |
+-----------------------------------+     +-----------------------------------+
```

### The Search-then-CAS Invariant:
1. Every candidate face is screened at `localWatermarkEpoch`.
2. When the Firestore CAS transaction runs, it asserts that `global_state.globalEpoch === localWatermarkEpoch`.
3. If any node committed another enrollment in the interim, the transaction returns `RECHECK_REQUIRED_EPOCH_DRIFT` without mutating state.
4. The coordinator automatically catches up missing WAL deltas, re-evaluates 1:N duplicates against the newly committed face, and retries.

---

## 3. Results Across All 18 Chaos Failure Scenarios

| Scenario ID | Injected Fault / Failure Event | Expected Cluster Behavior | Observed Result | Status |
| :--- | :--- | :--- | :--- | :--- |
| **Scenario 1** | **Simultaneous Enrollments:** Node A commits genuine Face 1 while Node B is screening genuine Face 2 at Epoch 0. | Node B transaction returns `RECHECK_REQUIRED_EPOCH_DRIFT`. Node B pulls WAL entry 1, updates index, re-screens, and commits Face 2 at Epoch 2. | Both enrolled cleanly at Epoch 1 and Epoch 2. Final gallery size = 2. | 🟢 **PASS** |
| **Scenario 2** | **Duplicate Face Race:** Identical fraudster face submitted simultaneously to Node A and Node B. | Exactly one node commits. The other node catches up the winner's WAL delta, detects $\cos \ge 0.90$, and halts with `HARD_DUPLICATE_BLOCKED`. | Node A committed at Epoch 1; Node B detected duplicate and halted without touching Firestore. | 🟢 **PASS** |
| **Scenario 3** | **Deletion During Screening:** Record deleted via TOMBSTONE WAL while replica is screening. | Replica replays TOMBSTONE, clones arena without deleted UID, and permits re-registration of that face. | Template removed from arena; subsequent registration cleanly approved at Epoch 3. | 🟢 **PASS** |
| **Scenario 4** | **Node Offline / Partition:** Node C goes dormant for 5 epochs and wakes up to process an enrollment. | Node C detects local watermark 0 vs global 5, replays all 5 WAL deltas, and commits at Epoch 6. | Node C caught up all 5 templates; committed at Epoch 6. Gallery size = 6. | 🟢 **PASS** |
| **Scenario 5** | **Duplicate WAL Delivery:** WAL entry 1 is delivered twice to a replica. | Monotonic watermark guard (`walSeq <= highestSeq`) ignores duplicate entry idempotently. | Watermark remained 1; gallery size remained 1. Zero duplicate entries. | 🟢 **PASS** |
| **Scenario 6** | **Out-of-Order WAL Delivery:** WAL entries arrive out of sequence (`[3, 2]`). | `verifyContiguousWalSequence` rejects non-contiguous delivery fail-closed. | Throws `WAL_GAP_DETECTED_SNAPSHOT_REQUIRED`. | 🟢 **PASS** |
| **Scenario 7** | **WAL Sequence Gap:** Stale node requests entries after watermark 5, but entries 6..9 were pruned by compactor. | `verifyContiguousWalSequence` detects sequence gap ($5 \to 10$) and blocks catch-up. | Throws `WAL_GAP_DETECTED_SNAPSHOT_REQUIRED`. | 🟢 **PASS** |
| **Scenario 8** | **Corrupted WAL Payload:** GCM ciphertext in WAL entry is corrupted in transit. | Unsealing fails; catch-up aborts without updating active gallery arena. | Catch-up rejected; local epoch remained 0; gallery size remained 0. | 🟢 **PASS** |
| **Scenario 9** | **Network Partition During Commit:** Firestore RPC fails permanently during transaction commit. | Transaction aborts cleanly; zero partial state written to vault or outbox. | Error propagated; coordinator state remained consistent. | 🟢 **PASS** |
| **Scenario 10** | **Lost Commit Response:** Client retries commit with identical idempotency key and payload. | Adapter detects idempotency reservation and returns cached result with `idempotentReplay = true`. | Returned 200 `IDEMPOTENT_REPLAY` without advancing global epoch. | 🟢 **PASS** |
| **Scenario 11** | **Failed Consumer ACK:** Replica encounters transient RPC failure while fetching WAL tail. | Replica fails transaction, retries fetch on next pass, and successfully catches up. | Caught up cleanly on retry; final epoch = 1; gallery size = 1. | 🟢 **PASS** |
| **Scenario 12** | **Partial Commit Prevention:** Transactional atomicity between `biometric_vault` and `biometric_wal_outbox`. | Firestore transaction guarantees both vault and WAL entry are written atomically or both fail. | Verified `biometric_vault/uid` and `biometric_wal_outbox/000000000001` exist simultaneously. | 🟢 **PASS** |
| **Scenario 13** | **Idempotency Payload Tampering:** Attacker reuses existing idempotency key with a modified face vector. | Hash fingerprint mismatch detected; transaction rejects request fail-closed. | Threw `CONFLICT_IDEMPOTENCY_PAYLOAD_MISMATCH`. | 🟢 **PASS** |
| **Scenario 14** | **Key Rotation During Active Hydration:** Snapshot encrypted under previous KEK version. | KMS provider unwraps key using version name bound in artifact; hydration succeeds. | Hydrated successfully; gallery size = 1. | 🟢 **PASS** |
| **Scenario 15** | **Compactor Pruning Active Entries:** Compactor removes WAL entries while slow node attempts catch-up. | Slow node detects missing sequence and aborts catch-up to request full snapshot. | Threw `WAL_GAP_DETECTED_SNAPSHOT_REQUIRED`. | 🟢 **PASS** |
| **Scenario 16** | **Clock Skew / Timestamp Inversion:** Worker commits at $T=2000$, followed by worker at $T=1000$. | Ordering is strictly governed by monotonic integer `walSeq`, immune to wall-clock skew. | Both entries committed in monotonic sequence; epochs = 1, 2. | 🟢 **PASS** |
| **Scenario 17** | **Max Retry Exhaustion Under Contention:** Extreme concurrency causes repeated epoch drift beyond retry ceiling. | Coordinator aborts fail-closed after `maxEpochDriftRetries` to prevent infinite loops. | Threw `MAX_EPOCH_DRIFT_RETRIES_EXCEEDED` after exactly 2 retries. | 🟢 **PASS** |
| **Scenario 18** | **Generation Bump Race:** Concurrent re-enrollment advances `templateGeneration` during screening. | Generation fence detects mismatch (`currentGen !== expectedGen`) and aborts stale write. | Threw `CONFLICT_ALREADY_ENROLLED`. | 🟢 **PASS** |

---

## 4. Key Architectural Takeaways

1. **Split-Brain Elimination:**
   The Search-then-CAS protocol eliminates split-brain conditions without requiring distributed distributed locks (e.g. Redlock or ZooKeeper). Firestore's ACID transaction on `biometric_cluster_meta/global_state` acts as the single source of serialization truth.
2. **Idempotency Hardening:**
   Binding the SHA-256 fingerprint of the biometric vector directly into the idempotency reservation record prevents attackers from reusing intercepted idempotency tokens to overwrite existing accounts.
3. **Fail-Closed Compaction Safety:**
   Pruning WAL records never risks silent omission of templates because `verifyContiguousWalSequence` strictly enforces `walSeq === expectedSeq`.
