# V19 Gallery Consistency and Scale Report

## 1. Gallery Architecture & In-Memory Index
To avoid paying runtime Firestore read costs on every candidate probe and to eliminate network jitter during matching, the backend maintains `InMemoryBiometricIndex`:
- **Representation:** 128-dimensional Float32Array on $\mathbb{S}^{127}$.
- **Metric:** Unit-norm Dot Product (mathematically equivalent to Cosine Similarity).
- **Correctness Parity:** **100.0% Exact Match** with brute-force ground truth.
- **Query Latency:** **0.472 ms** for 1,000 candidates (sub-millisecond search).
- **Runtime Search Reads:** **0 Firestore reads** during 1:N screening.

## 2. Firestore Vector Search Constraints
The system accounts for documented Firestore Vector Search platform limitations:
1. **Dimension Limit:** Maximum 2,048 dimensions (SFace 128-D complies easily).
2. **Top-K Limit:** Maximum 1,000 nearest-neighbor results in Firestore Standard Edition.
3. **No Real-Time Listeners:** Vector search queries do not support real-time snapshot listeners.
4. **Transaction Decoupling:** Nearest-neighbor queries cannot be executed inside a retriable write transaction callback.

## 3. Concurrency, Epoch CAS & Multi-Instance Consistency
To prevent race conditions where two identical faces register simultaneously on different backend instances:
1. **Epoch Versioning (`GalleryConsistencyServiceV3`):** Every template write increments a global gallery `epochId`.
2. **Check-After-Search Protocol:**
   $$\text{Pre-Search Epoch} = E_1 \quad \longrightarrow \quad \text{Execute 1:N Scan} \quad \longrightarrow \quad \text{Verify Post-Search Epoch} = E_1$$
   If $E_2 \neq E_1$, an intervening enrollment occurred. The transaction aborts and retries the 1:N screening.
3. **Multi-Instance Edge Cases:** In distributed deployments, if a candidate similarity falls into the ambiguous window $[0.74, 0.90)$, the submission is routed to `biometric_review_queue` rather than auto-approved, preventing split-brain registrations.
