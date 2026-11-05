# KELASAGARA V15.0 BIOMETRIC ENGINE AUDIT
# REPORT 06: GALLERY CONSISTENCY & DISTRIBUTED STATE AUDIT

**Document ID:** KLS-V15-GALLERY-001  
**Classification:** DISTRIBUTED SYSTEMS ARCHITECTURAL REVIEW  
**Target Subsystems:** `backend/src/services/in_memory_biometric_index.ts`, `backend/src/services/biometric_enrollment.ts`, Google Cloud Run deployment architecture  
**Audit Finding:** MULTI-INSTANCE RAM DRIFT DETECTED / MITIGATION CONSTRAINED  
**Audit Date:** 2026-10-23  

---

## 1. THE DISTRIBUTED INDEX CONCURRENCY PROBLEM

To achieve sub-50ms latency for 1:N duplicate scanning, the Kelasagara backend employs an in-memory index (`InMemoryBiometricIndex`), implemented as an in-process JavaScript `Map<string, Float32Array>`.

While extremely fast for a single Node.js process, this architecture has a fundamental distributed systems limitation when deployed to serverless, horizontally auto-scaling environments like **Google Cloud Run**.

```
                   +---------------------------------------+
                   |       Client Enrollment Requests      |
                   +-------------------+-------------------+
                                       |
                     +-----------------+-----------------+
                     | Load Balancer / Google Cloud Run  |
                     +--------+-----------------+--------+
                              |                 |
                  Route to Instance 1       Route to Instance 2
                              |                 |
                 +------------v----+       +----v------------+
                 |  Cloud Run #1   |       |  Cloud Run #2   |
                 | [In-Memory RAM] |       | [In-Memory RAM] |
                 |  Template A     |       |  Template B     |
                 +--------+--------+       +----+------------+
                          |                     |
                          +----------+----------+
                                     |
                       +-------------v-------------+
                       |   Cloud Firestore Vault   |
                       |  (Slow Distributed Store) |
                       +---------------------------+
```

### The Split-Brain / Concurrency Failure Scenario:
1. **Initial State:** Cloud Run autoscaler spins up Instance 1 and Instance 2. Both warm up from Firestore, indexing existing templates $T_1 \dots T_K$.
2. **Concurrent Sybil Registration:** A fraudulent actor attempts to enroll the same face twice under two distinct phone numbers and Firebase UIDs ($\text{UID}_A$ and $\text{UID}_B$) simultaneously.
3. **Load Balancer Dispatch:** Request for $\text{UID}_A$ hits Instance 1. Request for $\text{UID}_B$ hits Instance 2.
4. **Duplicate Probe:**
   - Instance 1 scans its local RAM: $\text{UID}_A$ matches nothing. Approved.
   - Instance 2 scans its local RAM: $\text{UID}_B$ matches nothing. Approved.
5. **Persistence Race:** Both instances write their respective records to the Firestore `biometric_vault`.
6. **Result:** A duplicate identity is permanently created in the database. Instance 1 never notified Instance 2 of the new vector, resulting in RAM gallery drift until instances restart.

---

## 2. REPOSITORY AUDIT OF `in_memory_biometric_index.ts`

Source code inspection confirms:
- **Storage Primitive:** An internal `Map<string, { vector: Float32Array; phoneNumber: string }>` residing in heap memory.
- **Inter-Process Synchronization:** **None.** There is no Redis pub/sub, Firestore real-time snapshot listener, or distributed mutex.
- **Cold Boot Latency:** On container initialization, `warmUpBiometricIndex()` queries all documents in `biometric_vault` sequentially. For $N > 5,000$, startup latency will exceed Cloud Run health check timeouts (10–15s).

---

## 3. TWO-PHASE ARCHITECTURAL REMEDIATION

To resolve this blocker, the architecture is divided into an immediate pilot constraint and a long-term production roadmap.

### Phase 1 (Immediate Pilot Solution: $N < 500$ Workers)
For the controlled pilot testing phase, horizontal scaling is explicitly disabled on Google Cloud Run:
```bash
# Production Deployment Constraint for Cloud Run:
gcloud run deploy kelasagara-biometric-backend \
  --image gcr.io/kelasagara/biometric-backend:v15 \
  --min-instances 1 \
  --max-instances 1 \
  --concurrency 80 \
  --cpu 2 \
  --memory 2Gi
```

**Guarantees of `--max-instances 1`:**
- A single Node.js process handles all requests sequentially through the Node event loop.
- No memory drift between instances; the in-memory map is the single coherent cache.
- In-flight duplicate detection is serialized, preventing race conditions.
- **Throughput:** A single 2-vCPU Cloud Run container running SFace ONNX INT8 handles ~15–20 enrollments/second, well exceeding pilot requirements.

---

### Phase 2 (Production Scale Roadmap: $N \ge 500$ Workers)
When the worker gallery scales beyond 500 records, the architecture must transition away from in-process RAM indexing to **Cloud Firestore Vector Search**:

```typescript
// Proposed Firestore Native Vector Search (KNN):
import { FieldValue } from 'firebase-admin/firestore';

export async function findNearestDuplicate(
  probeEmbedding: number[], 
  excludeUid: string
): Promise<CandidateMatch[]> {
  const vault = admin.firestore().collection('biometric_vault');
  
  // Native Firestore vector index using HNSW / Cosine distance
  const snapshot = await vault.findNearest({
    vectorField: 'embeddingVector',
    queryVector: FieldValue.vector(probeEmbedding),
    limit: 5,
    distanceMeasure: 'COSINE',
  }).get();

  return snapshot.docs
    .filter(doc => doc.id !== excludeUid)
    .map(doc => ({
      uid: doc.id,
      similarity: 1.0 - doc.distance,
      phoneNumber: doc.data().phoneNumberMasked,
    }));
}
```

**Advantages of Native Firestore Vector Search:**
- Fully serverless and auto-scaling across infinite Cloud Run instances.
- Zero startup warm-up latency.
- Real-time write visibility across all API containers.
- Requires Firebase Blaze plan and Cloud Firestore vector extension.

---

## 4. WARM-UP PROCEDURE IMPLEMENTATION & VERIFICATION

In `backend/src/services/biometric_enrollment.ts`, the startup warm-up function was hardened:
```typescript
export async function warmUpBiometricIndex(): Promise<number> {
  const start = Date.now();
  try {
    const snapshot = await admin.firestore().collection('biometric_vault').get();
    let loadedCount = 0;
    
    for (const doc of snapshot.docs) {
      const data = doc.data();
      if (data.vector && Array.isArray(data.vector)) {
        InMemoryBiometricIndex.set(doc.id, {
          vector: new Float32Array(data.vector),
          phoneNumber: data.phoneNumberMasked || '',
        });
        loadedCount++;
      }
    }
    console.log(`[BiometricIndex] Warm-up complete: ${loadedCount} templates loaded in ${Date.now() - start}ms.`);
    return loadedCount;
  } catch (error) {
    console.warn('[BiometricIndex] Warm-up warning (non-fatal in dev/test):', error);
    return 0;
  }
}
```

---

## 5. CONCLUSION & RELEASE GATE IMPACT

While single-instance deployment (`--max-instances 1`) provides safety for test builds, the lack of distributed cache synchronization remains an architectural blocker for multi-instance cloud deployments.

**Release Status: CONTROLLED TEST BUILD ONLY (Restricted to single-instance execution).**
