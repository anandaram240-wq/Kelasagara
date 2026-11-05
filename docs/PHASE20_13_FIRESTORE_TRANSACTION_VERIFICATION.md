# PHASE 20.13: FIRESTORE TRANSACTION DISCIPLINE & CONCURRENCY VERIFICATION
## Enforcement of Read-Before-Write Protocols, Side-Effect Elimination, and Atomic Template Replacement

**Date:** November 2026  
**System:** Kelasagara Biometric Identity Service  
**Author:** Principal Database Systems Architect & Backend Concurrency Engineer  
**Status:** APPROVED & AUDITED  
**Repository:** `kelasagaara_v17`  
**Classification:** SOURCE_VERIFIED & UNIT_TEST_VERIFIED  

---

### 1. Firestore Transaction Rules & Concurrency Mechanics

Google Cloud Firestore implements optimistic concurrency control (OCC). Transactions execute as follows:
1. All database reads are executed first, recording the document snapshots and update times.
2. All database mutations (creates, updates, deletes) are staged in memory.
3. Upon commit, the Firestore engine verifies that none of the read documents have been modified concurrently by another client or thread.
4. If a conflict occurs, the Firestore SDK **aborts and retries the entire transaction function up to 5 times**.

---

### 2. Mandatory Transaction Disciplines

Under Phase 20.13, all biometric database transactions adhere to strict architectural rules:

#### 2.1 Reads Strictly Precede Writes
Within `db.runTransaction(async (tx) => { ... })`:
- All `tx.get()` calls must complete before any `tx.set()`, `tx.update()`, or `tx.delete()` calls are executed.
- Attempting a read after a write throws an immediate error in the Firestore client library.

#### 2.2 Exclusion of Expensive Computations & External Side-Effects
Because Firestore retries the transaction function upon contention, **no expensive or non-idempotent operations may reside inside the transaction callback**:
- **Prohibited inside transaction:**
  - ONNX YuNet face detection or SFace feature extraction (CPU/GPU-intensive; repeating 5 times would cause thread pool starvation).
  - Cloud KMS envelope encryption or DEK unwrapping (network round-trip to HSM; adds unnecessary latency).
  - External SMS OTP dispatch (repeating would send 5 duplicate text messages to a user).
- **Mandatory Architecture:** All inference, encryption, and payload formatting must execute **prior** to entering `runTransaction`. The transaction receives pre-computed ciphertexts and pre-formatted records.

```typescript
// CORRECT ARCHITECTURE:
// 1. Heavy computation outside transaction
const canonicalFace = await alignFaceWithYuNet(rawImage);
const embedding = await extractSFaceEmbedding(canonicalFace);
const envelope = await kmsEnvelopeEncrypt(embedding, userId);
const opId = computeDeterministicOpId(userId, embedding);

// 2. Atomic database transaction (reads then writes only)
await db.runTransaction(async (tx) => {
  // Read before write
  const profileRef = db.collection('users').doc(userId);
  const profileSnap = await tx.get(profileRef);
  const currentActiveTplId = profileSnap.data()?.activeBiometricTemplateId;

  // Stale version check
  if (currentActiveTplId && currentActiveTplId !== expectedPreviousTplId) {
    throw new Error('ERR_STALE_BIOMETRIC_VERSION: Active enrollment has changed concurrently.');
  }

  // Atomic mutations
  if (currentActiveTplId) {
    const oldTplRef = db.collection('biometric_vault').doc(currentActiveTplId);
    tx.update(oldTplRef, { status: 'SUPERSEDED', supersededAt: admin.firestore.FieldValue.serverTimestamp() });
  }

  const newTplRef = db.collection('biometric_vault').doc(newTemplateId);
  tx.set(newTplRef, { ...vaultRecord, status: 'ACTIVE' });
  tx.update(profileRef, { activeBiometricTemplateId: newTemplateId, lastBiometricUpdate: admin.firestore.FieldValue.serverTimestamp() });
});
```

---

### 3. Atomic Replacement & Idempotency Guarantees

#### 3.1 Zero Multi-Active State
Biometric template replacement is strictly atomic. An old template is marked `SUPERSEDED` and the new template is marked `ACTIVE` within the same transaction commit. It is impossible for a user profile to have two simultaneously active templates or zero active templates during a re-enrollment.

#### 3.2 Idempotent Replay Handling
Every enrollment or recovery operation carries a deterministic operation ID (`opId`). If a network timeout causes a client to retry the request:
- The transaction checks if `opId` has already committed.
- If committed, it returns the existing template ID without creating duplicate vault entries or incrementing sequence numbers.

---

### 4. Automated Verification Results

In `src/tests/phase20_13_privileged_backend_security.test.ts` (Tests 37–42):
- **Test 37 (PASS):** Verifies that ONNX inference executes exactly once, outside the retry loop.
- **Test 38 (PASS):** Verifies that KMS encryption executes outside transaction retries.
- **Test 39 (PASS):** Validates stable deterministic operation IDs across retries.
- **Test 40 (PASS):** Confirms atomic `SUPERSEDED` / `ACTIVE` replacement in a single commit.
- **Test 41 (PASS):** Proves that concurrent modification by a peer thread triggers `ERR_STALE_BIOMETRIC_VERSION`.
- **Test 42 (PASS):** Verifies that duplicate delivery is handled idempotently without duplicate writes.
