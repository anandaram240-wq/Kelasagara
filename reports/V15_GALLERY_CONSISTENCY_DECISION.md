# KELASAGARA V15.0: BIOMETRIC GALLERY CONSISTENCY & CONCURRENCY DECISION

**Project:** Kelasagara Worker Marketplace Biometric Subsystem  
**Date:** October 23, 2026  
**Auditor:** Principal Biometric Systems Architect & Distributed Systems Engineer  
**Classification:** CONTROLLED TEST BUILD ONLY — ARCHITECTURAL GOVERNANCE  
**Primary Files Evaluated:**
- [`backend/src/services/in_memory_biometric_index.ts`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/backend/src/services/in_memory_biometric_index.ts)
- [`backend/src/services/biometric_enrollment.ts`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/backend/src/services/biometric_enrollment.ts)
- [`backend/src/services/firestore_biometric_repository.ts`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/backend/src/services/firestore_biometric_repository.ts)
- [`backend/src/server.ts`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/backend/src/server.ts)

---

## 1. Executive Summary

To safeguard the Cloud Firestore Spark free tier (50,000 document reads/day), Kelasagara introduced an in-memory biometric index ([`InMemoryBiometricIndex`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/backend/src/services/in_memory_biometric_index.ts)), which caches enrolled 128-D vectors in RAM and executes 1:N candidate searches without triggering Firestore reads on every registration.

While this optimization succeeds in unit tests and single-process execution, **it creates critical distributed consistency and concurrency vulnerabilities when deployed to serverless multi-instance environments like Google Cloud Run**.

This report analyzes the failure modes of the current design, evaluates potential solutions (including Redis/Memorystore and Pub/Sub), establishes which datastore is authoritative, and defines the chosen architectural strategy.

---

## 2. Forensic Analysis of Current Implementation

### A. The Multi-Instance Cache Drift Problem
`InMemoryBiometricIndex` is implemented as an in-process JavaScript `Map<string, IndexedBiometricRecord>`:

```
                  ┌─────────────────────────────────────────┐
                  │          Google Cloud Run               │
                  │                                         │
                  │   ┌─────────────────────────────────┐   │
                  │   │ Container Instance A            │   │
                  │   │ RAM: [User1, User2, User3]      │   │
                  │   └─────────────────────────────────┘   │
                  │                                         │
                  │   ┌─────────────────────────────────┐   │
                  │   │ Container Instance B            │   │
                  │   │ RAM: [User1, User2] (Stale!)    │   │
                  │   └─────────────────────────────────┘   │
                  └─────────────────────────────────────────┘
```

When Cloud Run automatically scales to $M > 1$ container instances under traffic:
1. User 3 enrolls on **Instance A**. Instance A writes the template to Firestore and calls `InMemoryBiometricIndex.upsert(User3)`.
2. **Instance B has no knowledge of User 3.** Its local RAM index contains only User 1 and User 2.
3. If an attacker creates a second account (User 3') and the load balancer routes the request to **Instance B**, Instance B executes a 1:N scan against its local RAM index.
4. Because `InMemoryBiometricIndex.size() > 0` on Instance B, it **does not fall through to Firestore**. It scans only User 1 and User 2.
5. User 3' is declared **UNIQUE** and permitted to enroll, completely defeating duplicate account prevention!

### B. The Sybil Concurrent Registration Race Condition
The current concurrency lock in [`FirestoreBiometricRepository.reserveEnrollmentSession(uid)`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/backend/src/services/firestore_biometric_repository.ts#L61) locks the document `/biometric_enrollment_sessions/{uid}`:

- This locks **per-account** enrollment attempts. It prevents the same user from submitting two parallel requests on the **same UID**.
- However, when a malicious actor attempts a Sybil attack, they create **two distinct accounts** (`uid_A` and `uid_B`).
- If the attacker submits enrollments for `uid_A` and `uid_B` simultaneously:
  * Session A locks `/biometric_enrollment_sessions/uid_A`.
  * Session B locks `/biometric_enrollment_sessions/uid_B`.
  * Both sessions read the gallery simultaneously before either has committed to Firestore.
  * Neither session sees the other's face.
  * Both enrollments succeed, resulting in duplicate account creation.

### C. Asynchronous Cold-Start Race
In [`backend/src/server.ts`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/backend/src/server.ts#L112), `warmUpBiometricIndex()` is invoked asynchronously after `server.listen()`:
```typescript
warmUpBiometricIndex().then(() => {
  console.log('[BiometricIndex] Warm-up complete');
});
```
If an HTTP enrollment request arrives while the asynchronous warmup query is streaming documents from Firestore:
- `InMemoryBiometricIndex.size()` is non-zero (partially populated).
- The query executes against an incomplete gallery, leading to false-negative deduplication.

---

## 3. Evaluation of Candidate Architectures

### Candidate 1: Adding Redis / Google Cloud Memorystore
- **Concept:** Store all vectors in a shared Redis cluster; use Redis Pub/Sub for cross-instance invalidation.
- **Evaluation:**
  * **Cost:** Google Cloud Memorystore for Redis costs a minimum of ~$35–$45/month. For a student/startup project on Spark/Blaze, this introduces unnecessary infrastructure overhead.
  * **False Security:** Redis alone does **not** solve the concurrent Sybil race condition unless a distributed transactional mutex (Redlock) or atomic vector index is implemented.
  * **Network Latency:** Fetching 500+ vectors over TCP on every enrollment introduces network overhead and serialization latency.

### Candidate 2: Single-Instance Cloud Run Container (`max-instances = 1`)
- **Concept:** Constrain the Google Cloud Run service configuration to a single concurrent container instance:
  ```bash
  gcloud run deploy kelasagara-biomatch-backend \
    --max-instances 1 \
    --concurrency 80
  ```
- **Evaluation:**
  * **Consistency:** Eliminates cross-instance cache drift completely. All requests route to the single container whose RAM index is always 100% synchronized with all commits.
  * **Scale:** A single Node.js container with 1 vCPU and 1GB RAM easily handles 50–100 requests per minute with ONNX sub-15ms inference latency.
  * **Cost:** $0 additional infrastructure cost. Operates fully within Google Cloud free-tier limits.
  * **Limitation:** Container restarts or cold-starts still require synchronous warmup completion before serving requests.

### Candidate 3: Authoritative Database Vector Search (Blaze Plan Native KNN)
- **Concept:** Rely directly on Cloud Firestore's native `findNearest` vector index (COSINE distance, Euclidean hypersphere), eliminating application-layer RAM indexes entirely.
- **Evaluation:**
  * **Consistency:** Fully ACID compliant. All instances query the same authoritative Firestore vector index.
  * **Concurrency:** Supported natively by Firestore transactional write pipelines.
  * **Cost:** Requires Blaze plan (pay-as-you-go). At $0.06 per 100,000 vector reads, cost is minimal for pilot scale.

---

## 4. Formal Architectural Decision

1. **Authoritative Truth:**
   Cloud Firestore (`biometric_vault`) is the **sole authoritative source of truth**. `InMemoryBiometricIndex` is strictly a transient, read-only acceleration cache.
2. **Short-Term Policy (Controlled Test Build / Pilot Phase, $N < 500$):**
   - The backend service must be deployed with **`--max-instances 1`** on Google Cloud Run to guarantee process-level gallery coherency.
   - Warmup must block readiness probes: The server must not signal HTTP readiness to Cloud Run until `warmUpBiometricIndex()` has resolved completely.
   - Zero Automated Approvals (Invariant I-01): Because cross-account Sybil race conditions can theoretically occur if an attacker fires microsecond-level concurrent requests, **all unique enrollments route to `pending_review` (RRL-0 Policy)**. An administrative reviewer verifies the advisory top-3 matches before granting active worker status.
3. **Long-Term Production Gate ($N \ge 500$):**
   - Migrate to Cloud Firestore Native Vector Search (`findNearest`) on the Blaze plan.
   - Implement a global distributed enrollment reservation document in Firestore (`biometric_global_concurrency`) updated transactionally to serialize multi-account duplicate screening.
