# KELASAGARA BIOMETRIC ENGINE V12.0
## Gallery Consistency & Multi-Version Lifecycle Management

**Date:** October 23, 2026  
**Status:** ENFORCED & SYNCHRONIZED  
**Standard Compliance:** ISO/IEC 19794-5, ISO/IEC 24745 §7.3  

---

## 1. The Cross-Model Gallery Corruption Hazard

In biometric systems with multi-year lifecycles, migrating from an older representation space to a modern deep CNN introduces gallery heterogeneity. 

If templates from different models coexist in the same searchable gallery without strict version gating:
- Cross-version dot products produce mathematically invalid scores ($s \approx 0.0$), causing false rejection of legitimate workers.
- Alternatively, disparate vector norms can cause unintended false collisions during 1:N deduplication.

### 1.1 Strict Model Segregation Invariant (Invariant I-02 & I-18)
Every template stored in `biometric_vault` must carry an immutable `modelVersion` tag.
In Kelasagara V12.0:
$$\text{Authoritative Model ID} = \texttt{"sface\_opencv\_zoo\_v1\_primary"}$$

During 1:1 verification and 1:N screening:
- The backend matches the probe exclusively against templates where $\texttt{doc.modelVersion} == \texttt{config.modelVersion}$.
- Legacy geometric templates ($\texttt{kelasagara\_biomatch\_v1}$ through $\texttt{v5}$) are flagged as `MIGRATION_REQUIRED` and excluded from the live SFace search index.

---

## 2. In-Memory Index Synchronization (`InMemoryBiometricIndex`)

To perform low-latency 1:N duplicate screening across thousands of workers without incurring Firestore read latency on every request, the backend maintains a high-performance in-memory index:

```typescript
// backend/src/services/in_memory_biometric_index.ts
export class InMemoryBiometricIndex {
  private static index: Map<string, { embedding: Float32Array; phoneNumber?: string }> = new Map();

  // O(1) Insertion upon authorized server enrollment
  static add(uid: string, embedding: Float32Array, phoneNumber?: string): void {
    this.index.set(uid, { embedding, phoneNumber });
  }

  // O(1) Deletion upon DPDPA erasure request
  static remove(uid: string): void {
    this.index.delete(uid);
  }

  // Linear SIMD-accelerated dot product search across N templates
  static search(probe: Float32Array, topK: number = 3, excludeUid?: string): Array<{ uid: string; similarity: number }> {
    // ...
  }
}
```

### 2.1 Server Warm-Up Lifecycle (`warmUpBiometricIndex`)
When the Express server boots:
1. Queries `biometric_vault` via the Firebase Admin SDK.
2. Filters documents for `modelVersion === 'sface_opencv_zoo_v1_primary'`.
3. Populates `InMemoryBiometricIndex`.
4. Exposes system readiness via `GET /api/biometrics/db-readiness`:
   ```json
   {
     "status": "db_ready",
     "data": {
       "enrolledTemplates": 142,
       "ramIndexSize": 142,
       "isRamIndexWarm": true,
       "modelVersion": "sface_opencv_zoo_v1_primary"
     }
   }
   ```

---

## 3. Worker Re-Enrollment & Migration Workflow

### 3.1 On-Demand Profile Re-Enrollment (`FaceReEnrollTile`)
Workers with legacy templates or physical changes (new eyeglasses, weight change, aging) can seamlessly upgrade their biometric record:
1. Navigate to Profile Screen $\to$ **ಮುಖ ಮರು-ನೋಂದಣಿ (Re-enroll Face ID)**.
2. Complete liveness blink verification to authenticate ownership.
3. Capture new high-fidelity ISO 29794-5 aligned face.
4. Backend executes 1:N duplicate screening against all *other* accounts to prevent account takeovers.
5. Overwrites vault record with updated SFace vector and bumps `enrolledAt` timestamp.
