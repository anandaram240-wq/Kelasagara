# KELASAGARA V20.15 — FIRESTORE NAMED DATABASE ISOLATION
## Multi-Database Architecture, Application Routing and Cross-Boundary Protection

**Author:** Principal Cloud Infrastructure Security Architect, Database Integrity Auditor  
**Date:** 2026-11-01  
**Repository:** `kelasagaara_v17`  
**Configuration:** `infra/terraform/firestore.tf`, `backend/src/services/firestore_database_router_v15.ts`  
**Status:** IMPLEMENTED AND VERIFIED  

---

### 1. Problem Statement: The Limits of Single-Database IAM

In Google Cloud Firestore, IAM roles and security rules declared at the project level default to the single database named `(default)`. Under a single-database design:
- Biometric facial templates, applicant profiles, job posts, chat logs, and audit trails reside in the same physical database.
- A service account granted read or write permissions to Firestore can potentially query or traverse collections across unrelated domains unless elaborate rules are maintained.
- Any transaction or batch write can atomically mix operational app changes with sensitive biometric vault records.

Google Cloud Firestore supports **Multiple Databases per Project** (Named Databases). Each database is an isolated storage and transactional boundary:
`projects/{project}/databases/{database}`

---

### 2. Multi-Database Topography in `infra/terraform/firestore.tf`

Phase 20.15 establishes three dedicated databases:
1. `(default)`: General application data (jobs, profiles, reviews, bookings).
2. `biometric-vault-db`: Isolated biometric templates, face embeddings, enrollment state.
3. `audit-ledger-db`: Cryptographic checkpoints, verification audit trail, immutable logs.

```hcl
# Dedicated Named Database for Biometric Templates
resource "google_firestore_database" "biometric_vault_db" {
  project                 = var.sandbox_project_id
  name                    = "biometric-vault-db"
  location_id             = var.region
  type                    = "FIRESTORE_NATIVE"
  delete_protection_state = "DELETE_PROTECTION_ENABLED"
  point_in_time_recovery_enablement = "POINT_IN_TIME_RECOVERY_ENABLED"
}

# Dedicated Named Database for Cryptographic Audit Ledger
resource "google_firestore_database" "audit_ledger_db" {
  project                 = var.sandbox_project_id
  name                    = "audit-ledger-db"
  location_id             = var.region
  type                    = "FIRESTORE_NATIVE"
  delete_protection_state = "DELETE_PROTECTION_ENABLED"
  point_in_time_recovery_enablement = "POINT_IN_TIME_RECOVERY_ENABLED"
}
```

Both named databases declare `delete_protection_state = "DELETE_PROTECTION_ENABLED"` and point-in-time recovery enabled.

---

### 3. Application-Layer Router: `firestore_database_router_v15.ts`

To ensure that the backend application never silently falls back to the `(default)` database when connecting to Firestore, Phase 20.15 introduces `FirestoreDatabaseRouter`:

```typescript
export enum BiometricServiceRole {
  BIOMETRIC_ENROLLMENT = 'BIOMETRIC_ENROLLMENT',
  BIOMETRIC_VERIFIER   = 'BIOMETRIC_VERIFIER',
  AUDIT_NOTARY         = 'AUDIT_NOTARY',
  VAULT_INVENTORY      = 'VAULT_INVENTORY',
  GENERAL_APP          = 'GENERAL_APP'
}

export const APPROVED_FIRESTORE_DATABASES = {
  BIOMETRIC_VAULT: 'biometric-vault-db',
  AUDIT_LEDGER:    'audit-ledger-db',
  DEFAULT_APP:     '(default)'
} as const;
```

#### Core Security Invariants of the Router:
1. **Explicit Routing:** Service roles are deterministically mapped:
   - `BIOMETRIC_ENROLLMENT`, `BIOMETRIC_VERIFIER`, `VAULT_INVENTORY` -> `biometric-vault-db`
   - `AUDIT_NOTARY` -> `audit-ledger-db`
   - `GENERAL_APP` -> `(default)`
2. **Fail-Closed Unknown Database Defense:** If any component requests an unapproved database ID, the router throws `ERR_UNKNOWN_FIRESTORE_DATABASE`.
3. **No Implicit Fallback to `(default)`:** If a privileged service account attempts to initialize without specifying its designated named database, or attempts to access `(default)`, the router blocks execution with `ERR_IMPLICIT_DEFAULT_DATABASE_FALLBACK` and emits a structured `DatabaseSecurityEvent`.
4. **Cross-Database Transaction Prohibition:** A transaction initiated on `biometric-vault-db` cannot span into `audit-ledger-db` or `(default)`. Attempts throw `ERR_CROSS_DATABASE_TRANSACTION_PROHIBITED`.

---

### 4. Automated Adversarial Tests

In `phase20_15_infrastructure_assurance.test.ts`:
- **Test 19:** Validates deterministic routing for all 5 roles.
- **Test 20:** Tests request for `unapproved-vault-db` -> throws `ERR_UNKNOWN_FIRESTORE_DATABASE`.
- **Test 21:** Simulates privileged service trying to fall back to `(default)` -> throws `ERR_IMPLICIT_DEFAULT_DATABASE_FALLBACK` and verifies structured audit event emission.
- **Test 22:** Simulates cross-database transaction -> throws `ERR_CROSS_DATABASE_TRANSACTION_PROHIBITED`.

### 5. Conclusion

Named database isolation enforces cryptographic and administrative separation. Even if an attacker gains read access to the general application database `(default)`, zero biometric templates or audit records can be read or tampered with.
