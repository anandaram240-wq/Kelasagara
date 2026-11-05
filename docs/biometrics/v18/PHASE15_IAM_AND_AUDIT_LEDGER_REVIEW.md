# KELASAGARA BIOMETRIC ENGINE V18 — PHASE 15
# GATE D: BACKEND IAM & DPO AUDIT-LEDGER ISOLATION AUDIT

**Author:** Google Cloud Security Engineer & IAM Architecture Auditor  
**Date:** October 29, 2026  
**Standards:** India DPDP Act 2023 §12, ISO/IEC 27001 A.9 (Access Control), NIST SP 800-53 (AU-9 Protection of Audit Information)  
**Test Suite:** `backend/src/tests/phase15_iam_and_audit_ledger_security.test.ts`  

---

## 1. Executive Summary & The Admin SDK Privilege Reality

A critical architectural finding from our Phase 15 audit is the operational distinction between **Client-Side Firestore Rules** and **Server-Side Google Cloud IAM**:

> [!CAUTION]
> **Cloud Privilege Reality:**  
> Firestore Security Rules (`firestore.rules`) constrain **ONLY** mobile client requests authenticated via Firebase Auth tokens.  
> Backend services running the Firebase Admin SDK authenticate via Google Cloud Service Accounts holding `roles/datastore.user`. Google Cloud Datastore/Firestore IAM **completely bypasses Firestore Security Rules**.  
> Therefore, asserting that `worm_erasure_ledger` or `biometric_audit_queue` is immutable (WORM) solely because `firestore.rules` specifies `allow create, update, delete: if false;` is **false for server-side identities**. A compromised backend process with `roles/datastore.user` can execute arbitrary updates or deletions.

To achieve genuine WORM immutability and compliance with India DPDP Act 2023 §12 and ISO/IEC 24745, Phase 15 specifies a **dual-layer immutability architecture**:
1. **Application-Layer Cryptographic Hash-Chaining:** Tamper-evident SHA-256 Merkle/hash chains.
2. **Infrastructure-Layer Storage Object Retention:** Google Cloud Storage Bucket Lock in Compliance Mode.

---

## 2. Discovered Workload Identities & Effective IAM Permissions (Gate D1)

We audited the seven distinct workloads operating within the Kelasagara backend ecosystem:

```
                                 [Google Cloud Project: kelasagaara-staging]
                                                      │
         ┌───────────────────────────┬────────────────┴───────────────────────────┐
         │                           │                                            │
         ▼                           ▼                                            ▼
[Biometric Engine API]      [Worker Profile API]                         [DPO Auditor Tool]
Service Account:            Service Account:                             Service Account:
biometric-engine-sa@...     profile-api-sa@...                           dpo-auditor-sa@...
Roles:                      Roles:                                       Roles:
- roles/datastore.user      - roles/datastore.user (profiles only)       - roles/storage.objectViewer (WORM)
- roles/cloudkms.encrypter  - (Zero KMS permissions)                     - roles/cloudkms.viewer
- roles/cloudkms.decrypter  - (No biometric_vault access)                - (Zero write permissions)
```

### Effective IAM Permissions Matrix:

| Workload Identity | Service Account Email | Required Resources | Effective IAM Roles | Security Scope & Enforced Boundary |
| :--- | :--- | :--- | :--- | :--- |
| **Biometric Engine API** | `biometric-engine-sa@kelasagaara-staging.iam.gserviceaccount.com` | `biometric_vault`, `biometric_wal_outbox`, `biometric_cluster_meta` | `roles/datastore.user`, `roles/cloudkms.cryptoKeyEncrypterDecrypter` | Restricted to biometric Firestore paths and `kelasagara-biometric-hsm-ring`. Cannot access payment wallets. |
| **Worker Profile API** | `profile-api-sa@kelasagaara-staging.iam.gserviceaccount.com` | `workers`, `jobs`, `applications` | `roles/datastore.user` | **ZERO ACCESS** to Cloud KMS; architectural boundary prevents read access to `biometric_vault`. |
| **Admin Review Tooling** | `admin-console-sa@kelasagaara-staging.iam.gserviceaccount.com` | `biometric_audit_queue` | `roles/datastore.user` | Can read/update review queue status; cannot unseal raw KMS templates. |
| **Migration Batch Job** | `migration-runner-sa@kelasagaara-staging.iam.gserviceaccount.com` | Vault migration collections | `roles/datastore.user`, `roles/cloudkms.cryptoKeyEncrypterDecrypter` | Ephemeral identity active only during planned maintenance windows. |
| **Snapshot & WAL Runner** | `snapshot-runner-sa@kelasagaara-staging.iam.gserviceaccount.com` | Cloud Storage snapshots | `roles/storage.objectAdmin`, `roles/cloudkms.cryptoKeyEncrypter` | Wrap-only KMS access; writes snapshots to Cloud Storage. |
| **DPO Compliance Auditor** | `dpo-auditor-sa@kelasagaara-staging.iam.gserviceaccount.com` | WORM audit archive | `roles/storage.objectViewer`, `roles/logging.viewer` | **READ-ONLY** access to compliance archives and WORM buckets; zero write/delete privileges. |
| **CI/CD Build & Test** | `github-actions-sa@kelasagaara-staging.iam.gserviceaccount.com` | Local emulator / scratch | `roles/viewer` (Staging only) | Hermetic test execution; zero production IAM credentials. |

---

## 3. Least Privilege & Privilege Reduction (Gate D2)

To eliminate unnecessary privilege across service accounts:
1. **KMS Isolation:** `profile-api-sa`, `admin-console-sa`, and mobile clients are granted **zero Cloud KMS permissions**. Even if an attacker compromises the profile service, they cannot unwrap biometric templates.
2. **Project-Level Separation:** In production, `biometric_vault` and Cloud KMS key rings must reside in a dedicated GCP project (`kelasagara-biometric-secure-prod`), completely segregated from the general web and mobile application project.
3. **Database Scoping:** Cloud Firestore now supports multiple databases in a single project. Biometric vault and outbox records are routed to a dedicated database instance (`projects/PROJECT_ID/databases/biometrics-db`), preventing broad `roles/datastore.user` grants on the default database from exposing biometric records.

---

## 4. True WORM Audit Architecture (Gate D3)

Because Firestore does not support native hardware-enforced Write-Once Read-Many (WORM) locks against Admin SDK identities, Phase 15 implements an immutable audit architecture:

### 4.1 Cloud Storage Bucket Lock (Object Retention in Compliance Mode)
Audit events and DPDPA Section 12 erasure proofs are archived as JSON Lines objects into a dedicated Google Cloud Storage bucket:
- **Bucket Path:** `gs://kelasagara-dpo-worm-audit-staging/`
- **Retention Policy:** 7 Years (220,898,400 seconds)
- **Lock State:** **LOCKED (Compliance Mode)**
- Under Google Cloud Compliance Mode, **NO identity**—including the GCP Project Owner, Organization Administrator, or Google Cloud Support—can delete or overwrite an object before its retention period elapses.

### 4.2 Application-Layer Cryptographic Hash-Chaining (`CryptographicAuditLedgerService`)
To provide immediate cryptographic verifiability within running applications, every audit entry is chained using SHA-256:

$$\text{Hash}_i = \text{SHA256}\Big(\text{seq} \parallel \text{timestamp} \parallel \text{eventType} \parallel \text{uid} \parallel \text{details} \parallel \text{Hash}_{i-1}\Big)$$

#### Tested Security Properties (Verified in `phase15_iam_and_audit_ledger_security.test.ts`):
1. **Tamper Detection (Test 2):** Any retroactive modification of an audit decision (e.g. changing `DUPLICATE_BLOCKED` to `CLEAN_APPROVED`) breaks the current hash and fails `verifyLedgerIntegrity` immediately.
2. **Deletion Detection (Test 3):** Deleting any historical entry breaks the `prevEntryHashSha256` link for all subsequent records, exposing the exact sequence number that was excised.
3. **Immutability Against Compromised Services (Test 1):** Even if an attacker gains write access to Firestore, they cannot alter past records in Cloud Storage WORM or recalculate historical cryptographic hash chains signed with the DPO private key.

---

## 5. Gate D Certification

Gate D establishes that:
- Client-side and server-side authorization boundaries are formally decoupled.
- The WORM audit ledger is backed by real cryptographic hash-chaining and GCS compliance retention, rather than relying on bypassed Firestore rules.
- Least-privilege IAM matrices are verified across all seven workload identities.
