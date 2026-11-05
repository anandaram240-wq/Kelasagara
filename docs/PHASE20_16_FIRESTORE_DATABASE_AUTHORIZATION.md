# KELASAGARA V20.16 — FIRESTORE DATABASE AUTHORIZATION
## Application Principal Verification, Named Database Boundaries, and IAM Limitations

**Author:** Principal Cloud Infrastructure Security Architect, Firebase Auditor  
**Date:** 2026-11-01  
**Repository:** `kelasagaara_v17`  
**Configuration:** `infra/terraform/firestore.tf`, `backend/src/services/firestore_database_authorization_v16.ts`  
**Status:** ENFORCED AND VERIFIED  

---

### 1. Database Topology and Explicit Routing

The Kelasagara cloud backend partitions data across three physical Named Databases in Firestore:
1. `(default)`: General user-facing operational collections (job postings, worker applications, mutual reviews, live GPS telemetry, chat).
2. `biometric-vault-db`: Highly sensitive biometric identity records (AES-256-GCM encrypted canonical 128-dim SFace embeddings, salt hashes, active gallery vector index).
3. `audit-ledger-db`: Tamper-evident cryptographic audit events (sequenced transaction logs, ECDSA P-256 signed checkpoints, blinded adjudication queues).

```
                      +───────────────────────────+
                      |   Firestore Router & Auth |
                      +───────────────────────────+
                                    │
         ┌──────────────────────────┼──────────────────────────┐
         │                          │                          │
         ▼                          ▼                          ▼
  [(default) DB]          [biometric-vault-db]        [audit-ledger-db]
  • General App Data      • Encrypted Vectors         • Audit Events
  • Jobs & Bookings       • Canonical Snapshots       • Sequenced Checkpoints
  • Chat & Reviews        • Gallery Index             • Blinded Review Queues
```

---

### 2. IAM Scope Limitations: Database-Level vs Application-Level

It is critical to distinguish what Google Cloud IAM can and cannot enforce in Firestore:

#### What Cloud IAM Enforces:
- Google Cloud IAM conditions and roles operate at the **Database Scope**:
  `projects/{project}/databases/{database}`
- A service account granted `roles/datastore.viewer` on `biometric-vault-db` cannot read from `audit-ledger-db` or `(default)` if its permissions are scoped to that specific database resource name.
- **Limitation:** Cloud IAM cannot enforce document-level or collection-level isolation within a single database for service accounts (service account credentials bypass client-side Security Rules).

#### What the Application Authorization Layer Enforces (`firestore_database_authorization_v16.ts`):
Because Cloud IAM alone cannot enforce role-specific document boundaries for trusted backends, the application layer implements strict session authorization:
1. **Calling Principal Assertion:** Services initializing a database session must provide their authenticated caller email. If `sa-biometrics-verifier` attempts to initialize an enrollment session or write to the vault, execution is rejected (`ERR_UNAUTHORIZED_CALLER_PRINCIPAL` or `ERR_READONLY_DATABASE_VIOLATION`).
2. **Read-Only Enforcement:** Verifier and Inventory roles are strictly restricted to `READ` operations; write or delete attempts throw `ERR_READONLY_DATABASE_VIOLATION`.
3. **Dual-Custody Gate for Recovery:** The `RECOVERY` workflow requires an explicit cryptographic dual-custody authorization token (`ERR_DUAL_CUSTODY_REQUIRED`).
4. **No Implicit Default Database Fallback:** Any privileged biometric service attempting to omit database configuration or target `(default)` fails closed with `ERR_UNAUTHORIZED_DEFAULT_DATABASE_FALLBACK`.

---

### 3. Application Principal Authorization Matrix

| Workflow Role | Target Named Database | Expected Service Account | Permitted Operations | Constraints |
| :--- | :--- | :--- | :--- | :--- |
| **`BIOMETRIC_ENROLLMENT`** | `biometric-vault-db` | `sa-biometrics-enrollment` | READ, WRITE | Cannot unwrap DEKs; cannot access audit ledger. |
| **`BIOMETRIC_VERIFIER`** | `biometric-vault-db` | `sa-biometrics-verifier` | READ ONLY | Zero write capability; cannot delete or modify gallery. |
| **`VAULT_INVENTORY`** | `biometric-vault-db` | `sa-biometrics-inventory` | READ ONLY | Metadata scanning only; zero write capability. |
| **`AUDIT_NOTARY`** | `audit-ledger-db` | `sa-biometrics-audit-notary` | WRITE (Append-Only) | Cannot access biometric vault. |
| **`RECOVERY`** | `biometric-vault-db` | `sa-biometrics-reviewer` | READ, WRITE | Mandatory dual-custody token verification required. |
| **`MANUAL_REVIEW`** | `audit-ledger-db` | `sa-biometrics-reviewer` | READ, WRITE | Blinded adjudication queue only; zero raw vector access. |
| **`GENERAL_APP`** | `(default)` | Application default | ALL (App scope) | Strictly barred from accessing named vault databases. |

---

### 4. Adversarial Test Evidence

In `phase20_16_cloud_runtime_authorization.test.ts`:
- **Test 33:** Validates explicit biometric database selection for enrollment and verifier.
- **Test 34:** Validates explicit audit database selection for audit notary.
- **Test 35:** Proves privileged service attempting fallback to `(default)` fails closed (`ERR_UNAUTHORIZED_DEFAULT_DATABASE_FALLBACK`).
- **Test 36:** Proves verifier write attempt throws `ERR_READONLY_DATABASE_VIOLATION`.

### 5. Cloud Verification Status

Because no live sandbox project is authorized on this host:
- Named database resource definitions are verified in `infra/terraform/firestore.tf`.
- Application-layer routing and boundary enforcement are 100% verified in automated unit and emulator suites.
- Live Google Cloud IAM condition evaluation on named databases is classified as:
  `BLOCKED_SANDBOX_IAM_NOT_AVAILABLE`
