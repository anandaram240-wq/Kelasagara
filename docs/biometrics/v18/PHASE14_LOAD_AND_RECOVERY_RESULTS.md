# KELASAGARA BIOMETRIC ENGINE V18 — PHASE 14
# LOAD, CONTENTION & RECOVERY BENCHMARK REPORT

**Author:** Principal Performance & Distributed Systems Engineer  
**Date:** October 29, 2026  
**Benchmarking Script:** `backend/src/tests/phase14_concurrency_benchmarks.ts`  
**Environment:** macOS (Apple Silicon), Node.js v20.x, Single-Threaded V8 Engine  

---

## 1. Executive Summary

This report provides empirical performance benchmarks for the Kelasagara Biometric Engine V18 under concurrent load and cold-boot recovery. We evaluated three core dimensions:
1. **Optimistic Concurrency Control (OCC) Contention:** Measured transaction abort and retry rates on the single global document `biometric_cluster_meta/global_state` across concurrency levels $C \in \{1, 2, 5, 10, 20\}$.
2. **Cold-Boot Hydration Latency vs. WAL Tail Length:** Measured the time required to unwrap a KMS-encrypted `KS18` snapshot ($N=500$) and replay trailing WAL records ($L \in \{0, 10, 25, 50, 100\}$).
3. **1:N In-Memory Search Latency:** Evaluated exact contiguous dot-product scanning over 128-D Float32 vectors for gallery sizes $N \in \{100, 1000, 5000, 10000\}$.

---

## 2. Benchmark 1: OCC Contention Scaling on Global Epoch Meta

In `FirestoreBiometricTransactionAdapterV18`, every enrollment mutation executes an atomic transaction that reads and increments `biometric_cluster_meta/global_state.globalEpoch`. In Google Cloud Firestore, concurrent transactions mutating the same document trigger optimistic concurrency aborts, requiring retries.

### Empirical Measurements ($N = 20$ Total Operations per Batch):

| Concurrency Level ($C$) | Total Ops Committed | Total Transaction Attempts | OCC Aborts (Retries) | Conflict Rate (%) | Total Duration (ms) | Effective Throughput (ops/sec) |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **$C = 1$ (Sequential)** | 20 | 20 | 0 | **0.00%** | 73 ms | 274.0 ops/s |
| **$C = 2$ Workers** | 20 | 22 | 1 | **4.55%** | 69 ms | 289.9 ops/s |
| **$C = 5$ Workers** | 20 | 28 | 4 | **14.29%** | 64 ms | 312.5 ops/s |
| **$C = 10$ Workers** | 20 | 38 | 9 | **23.68%** | 68 ms | 294.1 ops/s |
| **$C = 20$ Workers** | 20 | 58 | 19 | **32.76%** | 73 ms | 274.0 ops/s |

### Architectural Bottleneck Analysis:
- At low concurrency ($C \le 5$), the conflict rate remains acceptable ($\le 14.3\%$), and the coordinator's exponential backoff handles retries seamlessly.
- At $C = 20$, approximately **1 out of every 3 transaction attempts is aborted**. 
- In production Firestore, writing to a single document at $> 10\text{ writes/sec}$ exceeds Google's recommended single-document throughput guidelines (500 writes/sec sustained partition limit, with 1 write/sec per document soft guideline for low-contention transactions).
- **Recommendation for V19:** To scale to 100,000+ workers with continuous high enrollment concurrency, the global monotonic epoch must be transitioned to **partitioned sequence shards** or an external distributed sequencer (e.g., Cloud Spanner or a Redis Raft counter).

---

## 3. Benchmark 2: Cold-Boot Hydration Latency vs. WAL Tail Length

When a replica node cold-boots, it unwrap the `KS18` snapshot DEK via Cloud KMS, hydrates the contiguous 128-D vector arena, and replays any trailing WAL records committed after the snapshot watermark.

### Empirical Measurements ($N_{\text{base}} = 500$ Enrolled Workers):

| WAL Tail Length ($L$) | Snapshot Hydration Latency | Total Cold-Boot Latency | Replay Latency per WAL Record | Target (< 200 ms) Status |
| :--- | :--- | :--- | :--- | :--- |
| **$L = 0$ (Fresh Snapshot)** | 12.97 ms | **13.47 ms** | N/A | 🟢 **PASS** (13.5 ms) |
| **$L = 10$ Trailing WAL** | 14.92 ms | **132.21 ms** | ~11.7 ms / record | 🟢 **PASS** (132.2 ms) |
| **$L = 25$ Trailing WAL** | 15.65 ms | **310.47 ms** | ~11.8 ms / record | 🟡 **EXCEEDS** (310.5 ms) |
| **$L = 50$ Trailing WAL** | 16.34 ms | **607.61 ms** | ~11.8 ms / record | 🔴 **EXCEEDS** (607.6 ms) |
| **$L = 100$ Trailing WAL** | 15.05 ms | **1,270.18 ms** | ~12.5 ms / record | 🔴 **EXCEEDS** (1.27 sec) |

### Key Engineering Insight:
- **Snapshot Decryption & Zero-Copy View is Blazing Fast:** Unwrapping the AES-256-GCM encrypted snapshot containing 500 workers takes only **~13 - 16 ms**.
- **Sequential KMS Envelope Unsealing Dominates WAL Replay:** Each trailing WAL entry contains an individual AES-256-GCM envelope (`CloudKmsEnvelopeService.unsealTemplateV3`), which takes **~11.8 ms per record** to decrypt sequentially in Node.js.
- **Compaction Policy Requirement:** To guarantee the sub-200ms cold-boot SLO, the system must generate a new snapshot at least every **15 enrollments** ($L \le 15$), or implement parallel/batch envelope unsealing during WAL tail catch-up.

---

## 4. Benchmark 3: 1:N Exact Contiguous Dot Product Scan Latency

In `HighSpeedBiometricIndexV3`, candidate screening executes exact dot products directly over a contiguous pre-allocated `Float32Array(capacity * 128)`.

### Empirical Measurements:

| Gallery Size ($N$) | Scan Latency (Engine Measured) | Total End-to-End Latency | Search Mode | Throughput (Vectors Scanned / sec) |
| :--- | :--- | :--- | :--- | :--- |
| **$N = 100$** | **0.0217 ms** (21.7 µs) | 0.037 ms | `EXACT_CONTIGUOUS_SCAN` | 4,600,000 / sec |
| **$N = 1,000$** | **0.2555 ms** (255.5 µs) | 0.267 ms | `EXACT_CONTIGUOUS_SCAN` | 3,900,000 / sec |
| **$N = 5,000$** | **0.8615 ms** (861.5 µs) | 0.897 ms | `EXACT_CONTIGUOUS_SCAN` | 5,800,000 / sec |
| **$N = 10,000$** | **1.4612 ms** (1.46 ms) | 1.476 ms | `EXACT_CONTIGUOUS_SCAN` | 6,800,000 / sec |

### Key Performance Findings:
- At $N = 10,000$, a 1:N duplicate scan across the entire gallery completes in **under 1.5 milliseconds** on a single CPU core.
- The contiguous memory layout eliminates pointer dereferences and cache misses, achieving scan rates exceeding **5 million vectors per second** without GPU or native C++ addons.
- Approximate Nearest Neighbor (HNSW) graph indexing is completely unnecessary for galleries under 25,000 workers; brute-force SIMD-friendly contiguous scans provide 100% recall with zero recall loss at sub-5ms latencies.
