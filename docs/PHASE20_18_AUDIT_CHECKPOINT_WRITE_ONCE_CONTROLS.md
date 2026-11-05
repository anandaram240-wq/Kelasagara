# KELASAGARA V20.18 — AUDIT CHECKPOINT WRITE-ONCE CONTROLS
## Generation Preconditions, Storage IAM Boundary, and Immutability Disclosures

**Author:** Principal Cloud Infrastructure Architect, Storage Security Auditor  
**Date:** 2026-11-01  
**Repository:** `kelasagaara_v17`  
**Parent Commit:** `2233327` (`security/phase20.17-trusted-execution-provenance`)  
**Branch:** `security/phase20.18-pilot-readiness-corrections`  
**Status:** `ACTIVE_VERIFIED`  

---

### 1. Storage Permission Architecture: Create-Only vs Read-Only

To ensure tamper-evidence across audit ledgers, Phase 20.18 isolates Google Cloud Storage roles:

| Identity | Cloud IAM Role | Permitted Actions | Prohibited Actions |
| :--- | :--- | :--- | :--- |
| **Audit Notary** (`sa-biometrics-audit-notary`) | `roles/storage.objectCreator` | Write new checkpoint objects with `ifGenerationMatch=0`. | **Cannot read** checkpoint objects (`storage.objects.get` withheld); **cannot delete or overwrite** existing objects. |
| **Audit Reconciler** (`sa-biometrics-audit-reconciler`) | `roles/storage.objectViewer` | Read and verify checkpoint objects and Firestore chains. | **Cannot write, mutate, or sign** checkpoints (`storage.objects.create` withheld). |

---

### 2. Implementation: `ifGenerationMatch=0` Write-Once Insertion

In Google Cloud Storage, passing the query parameter `ifGenerationMatch=0` on an object upload instructs the storage engine to create the object **only if no object with that name currently exists**.

If an attacker or rogue notary process attempts to overwrite an existing checkpoint (e.g. `checkpoint-000040.json`):
```
HTTP 412 Precondition Failed
ErrorCode: ERR_PRECONDITION_FAILED_OBJECT_EXISTS
```
The storage engine rejects the write, preserving the original checkpoint intact.

---

### 3. Realistic Bucket Retention Disclosure

**Non-Negotiable Cloud Reality:**
1. In the current non-production configuration, the audit storage bucket operates under an **unlocked 90-day retention policy** (`is_locked = false`).
2. An unlocked retention policy is **NOT permanent hardware WORM**; an administrator with `roles/storage.admin` can modify the retention duration or delete the bucket.
3. **Irreversible Bucket Lock (`is_locked = true`) is strictly prohibited in sandbox/testing environments**, as it permanently prevents bucket deletion or project teardown.
4. Real bucket creation is blocked until separate sandbox cloud authorization is provided.

---

### 4. Verified Security Assertions (Tests 39–45)

- **Test 39:** Duplicate checkpoint name on write-once bucket rejected (`ERR_PRECONDITION_FAILED_OBJECT_EXISTS`).
- **Test 40:** Existing checkpoint overwrite rejected by notary service (`ERR_PRECONDITION_FAILED_OBJECT_EXISTS`).
- **Test 41:** Invalid cryptographic signature detected during reconciliation (`SIGNATURE_INVALID`).
- **Test 42:** Missing checkpoint detected in sequence (`CHAIN_DISCONTINUITY`).
- **Test 43:** Notary cannot read or delete checkpoint objects (`roles/storage.objectCreator` boundary).
- **Test 44:** Reconciler cannot write or sign checkpoints (`ERR_PERMISSION_DENIED_VIEWER_CANNOT_WRITE`).
- **Test 45:** Firestore ledger history mutations detected against signed checkpoints (`HISTORICAL_REWRITE_DETECTED`).
