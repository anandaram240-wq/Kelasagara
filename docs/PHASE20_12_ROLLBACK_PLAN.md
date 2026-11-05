# KELASAGARA V20.12: ROLLBACK & INCIDENT CONTINGENCY PLAN

**Project:** Kelasagara Biometric Security Architecture  
**Phase:** V20.12  
**Parent Phase:** V20.11 (`412def0`)  
**Working Branch:** `security/phase20.12-biometric-trust-provenance`  
**Classification:** Operational Resilience & Disaster Recovery Protocol  

---

## 1. ROLLBACK TRIGGERS

A rollback from Phase 20.12 to Phase 20.11 baseline (`412def0`) is immediately initiated if:
1. `CanonicalSFaceEngineV10` fails to initialize ONNX Runtime sessions for YuNet or SFace on target ARM64/x64 server instances.
2. In-memory `WeakMap` provenance tracking causes memory leaks under continuous high-volume stress testing.
3. Case reference generation encounters repeated collisions under high concurrency.
4. Transaction retries in `replaceAuthorizedEnrollment` exceed configured limits during simultaneous high contention.

---

## 2. ATOMIC ROLLBACK PROCEDURE

### Step 1: Git Reversion to Parent Baseline
```bash
git checkout security/phase20.11-legacy-template-isolation
git checkout 412def00e4d1cbb2037af72f6a6fb5390bd77d2d
```

### Step 2: Clean Build Verification
```bash
cd backend
rm -rf dist
npm run build
npm test
```
Verify that all 913 baseline tests pass.

### Step 3: Database & Production State
Because Phase 20.12 executed **zero database migrations, zero schema mutations, and zero cloud deployments**, no database rollbacks, document rollbacks, or KMS key rotations are required. The operational state of Firebase Firestore is completely untouched.

---

## 3. RESILIENCE INVARIANTS

- **Zero-Downtime Reversibility:** Pure software changes without schema locks.
- **Fail-Closed Biometrics:** If provenance verification fails or is reverted, unverified templates are treated as `LEGACY_TEMPLATE_UNKNOWN` and never corrupt production deduplication.
- **Audit Preservation:** All case references created under V20.12 (`CASE-` + 32 hex chars) can still be inspected by standard support workflows even if the codebase is temporarily rolled back.
