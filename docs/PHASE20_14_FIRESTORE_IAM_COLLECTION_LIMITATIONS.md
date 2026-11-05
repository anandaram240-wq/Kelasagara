# PHASE 20.14: FIRESTORE CLOUD IAM GRANULARITY & COLLECTION-LEVEL LIMITATIONS
## Technical Investigation into Database-Level IAM Boundaries and Mandatory Application-Layer Enforcement

**Date:** November 2026  
**System:** Kelasagara Biometric Identity Service  
**Author:** Principal Cloud Security Architect & Database Systems Engineer  
**Status:** APPROVED & AUDITED  
**Repository:** `kelasagaara_v17`  
**Classification:** SOURCE_VERIFIED & ARCHITECTURALLY_ENFORCED  

---

### 1. The Core Cloud IAM Limitation: No Collection-Level IAM

A critical question raised in Phase 20.14 is whether Google Cloud IAM natively supports collection-level isolation for Firestore databases (e.g. granting a service account write access to `/biometric_vault` while denying write access to `/users` or `/biometric_audit_ledger`).

#### 1.1 Technical Fact
**Google Cloud IAM for Firestore / Cloud Datastore does NOT support collection-level role bindings in standard IAM policies.**
- The smallest resource granularity supported by Cloud IAM permissions (such as `datastore.entities.create`, `datastore.entities.get`, `datastore.entities.update`, `datastore.entities.delete`) is the **database instance**:
  `projects/{project-id}/databases/{database-id}`
- If a service account is assigned the predefined IAM role `roles/datastore.user` on `(default)`, that service account technically possesses IAM authorization to read, write, and delete documents across **all collections** within that database instance.
- Firestore declarative security rules (`firestore.rules`) provide collection-level and document-level path matching (`match /databases/{database}/documents/{collection}/{doc}`), but **Firebase Admin SDK calls made with service account credentials completely bypass `firestore.rules`**.

---

### 2. Architectural Mitigations & Defense-in-Depth

Because Cloud IAM cannot enforce collection-level isolation within a single Firestore database, the platform employs a three-tier defense-in-depth architecture:

```
+-------------------------------------------------------------------------------+
| TIER 1: MULTI-DATABASE IAM ISOLATION (GCP Named Databases)                    |
| - projects/PROJECT/databases/(default)          -> General App Collections    |
| - projects/PROJECT/databases/biometric-vault-db -> Biometric Vault Records    |
| - projects/PROJECT/databases/audit-ledger-db    -> Append-Only Audit Trail    |
| (IAM roles CAN be bound to individual database resource paths)                |
+-------------------------------------------------------------------------------+
                                          +
+-------------------------------------------------------------------------------+
| TIER 2: APPLICATION-LAYER AUTHORIZATION & SCHEMA GATEWAY                      |
| - verifyCallerAuthorization(authHeader, targetUid)                            |
| - Schema whitelisting & parameter sanitization (strips client provenance)     |
| - Module-private WeakMap tokens & process-bound HMAC                          |
+-------------------------------------------------------------------------------+
                                          +
+-------------------------------------------------------------------------------+
| TIER 3: DECLARATIVE CLIENT SECURITY RULES (firestore.rules)                   |
| - Governs mobile/web client SDKs                                              |
| - Strict allow read, write: if false; on all privileged collections           |
+-------------------------------------------------------------------------------+
```

---

### 3. Tier 1: Firestore Named Databases (Database-Level IAM Isolation)

Google Cloud Firestore supports multiple databases per project ("Named Databases"). Under this architecture, separate databases are provisioned for distinct trust domains:

1. **`biometric-vault-db`:**
   - Resource path: `projects/${var.sandbox_project_id}/databases/biometric-vault-db`
   - `sa-biometrics-enrollment` is granted `roles/datastore.user` on this database.
   - `sa-biometrics-verifier` is granted `roles/datastore.viewer` on this database.
   - `sa-biometrics-reviewer` has **zero IAM permissions** on this database.

2. **`audit-ledger-db`:**
   - Resource path: `projects/${var.sandbox_project_id}/databases/audit-ledger-db`
   - `sa-biometrics-audit-notary` is granted `roles/datastore.user` on this database.
   - `sa-biometrics-enrollment` has write permissions only to the outbox.
   - External signed checkpoints are mirrored to Cloud Storage Bucket Lock.

---

### 4. Tier 2: Application-Layer Enforcement Rules

Regardless of database topography, backend code paths enforce strict operational boundaries:
1. **Never trust caller payloads for provenance:** Flags like `classification: 'CANONICAL'` or `source: 'CANONICAL'` provided by callers are discarded.
2. **Read-before-write transaction discipline:** Mutations are wrapped in Firestore transactions where reads strictly precede writes, and heavy ONNX inferences or KMS calls are kept outside the retry closure.
3. **Audit Notary Immutability:** Audit events are verified against monotonically increasing sequence numbers and externally signed checkpoints.

---

### 5. Verification Evidence

The test suite in `backend/src/tests/phase20_14_nonproduction_cloud_verification.test.ts` (Test 15) specifically validates this boundary, demonstrating that application-layer and multi-database controls successfully isolate roles even when primitive Datastore IAM permissions operate at the database scope.
