# KELASAGARA V20.12: AUTHORIZED REPLACEMENT TRANSACTION & CONCURRENCY SPECIFICATION

**Project:** Kelasagara Biometric Security Architecture  
**Phase:** V20.12  
**Parent Phase:** V20.11 (`412def0`)  
**Working Branch:** `security/phase20.12-biometric-trust-provenance`  
**Classification:** Concurrency Architecture & Transaction Integrity Specification  

---

## 1. TRANSACTION DESIGN: READS-BEFORE-WRITES

Firestore transactions require all document reads to execute **strictly before any document writes**. If a write occurs prior to a read, or if uncommitted side-effects occur inside the callback, concurrent retries cause fatal exceptions or duplicate states.

In Phase 20.12, the `replaceAuthorizedEnrollment` workflow enforces an atomic, retry-safe lifecycle:

```
[ OUTSIDE TRANSACTION ]
1. Authenticate Account Owner (authenticatedUid)
2. Verify Step-Up Auth Nonce & Expiry
3. Pre-process Image: YuNet Face Detection + Umeyama Alignment
4. SFace ONNX Inference: Extract 128-D Unit Vector
5. Cloud KMS Envelope Encryption: Generate AES-256-GCM Envelope
6. Screen Proposed Vector against Gallery (excluding authenticatedUid's own template)
                 |
                 v
[ INSIDE FIRESTORE runTransaction CALLBACK ]
Phase A (Reads):
   - tx.get(userRef)              -> Verify active account & current activeBiometricEnrollmentId
   - tx.get(oldVaultRef)          -> Verify old template exists, is ACTIVE, and owned by authenticatedUid
   - tx.get(metaRef / epochDoc)   -> Read current gallery epoch
   - tx.get(opRef)                -> Check idempotency lease

Phase B (Writes):
   - tx.update(oldVaultRef, { status: 'SUPERSEDED', supersededAtMs: nowMs })
   - tx.set(newVaultRef, { ...newTemplateData, status: 'ACTIVE' })
   - tx.update(userRef, { activeBiometricEnrollmentId: newEnrollmentId, updatedAtMs: nowMs })
   - tx.set(epochDoc, { epochVersion: currentEpoch + 1 })
   - tx.update(opRef, { state: 'COMMITTED' })
```

---

## 2. INVARIANT DEFENSE & RETRY INTEGRITY

### Invariant 1: Zero External RPCs in Transaction Callbacks
Heavy ONNX inference, YuNet alignment, and KMS envelope generation are completed **before** `db.runTransaction()`. The transaction callback contains only deterministic Firestore reads and writes.

### Invariant 2: Active Template Preservation on Failure
If duplicate screening fails, or if a concurrent modification halts the transaction:
- The previous template remains `ACTIVE` in `biometric_vault`.
- The user's `activeBiometricEnrollmentId` on `users/{uid}` remains unchanged.
- The user is never left in an unauthenticated or stranded state.

### Invariant 3: Idempotent Retries
If Firestore detects a concurrent modification and retries the transaction callback:
- The deterministic operation ID (`deterministicOpId`) prevents creating multiple active templates.
- If the old template was already superseded by a concurrent request, the read phase detects `oldSnap.data()?.status !== 'ACTIVE'` and safely fails closed with `ERR_STALE_BIOMETRIC_VERSION`.
