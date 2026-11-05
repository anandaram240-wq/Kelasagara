# PHASE 20.13: SERVICE ACCOUNT PERMISSION MATRIX & PRINCIPAL SEPARATION
## Granular Cloud IAM Principal-to-Resource Access Control Architecture

**Date:** November 2026  
**System:** Kelasagara Biometric Identity Service  
**Author:** Principal Cloud IAM & Infrastructure Security Architect  
**Status:** APPROVED & AUDITED  
**Repository:** `kelasagaara_v17`  
**Classification:** SOURCE_VERIFIED & ARCHITECTURALLY_ENFORCED  

---

### 1. Architectural Principles

In accordance with Zero Trust and Least Privilege principles (NIST SP 800-207), each backend service runs under its own dedicated Google Cloud Service Account. Service accounts are never shared across services, and project-wide primitive roles (`roles/owner`, `roles/editor`, `roles/viewer`) are strictly prohibited in production.

---

### 2. Comprehensive Principal-to-Resource Matrix

| Microservice Component | Service Account Identity | Target GCP / Firebase Resources | Assigned Cloud IAM Roles | Permitted Actions | Prohibited Actions |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Biometric Enrollment Service** | `sa-biometrics-enrollment@` | Firestore collections: `biometric_vault`, `biometric_audit_ledger`<br>KMS: `projects/*/locations/*/keyRings/*/cryptoKeys/biometric-dek-wrap` | `roles/datastore.user`<br>`roles/cloudkms.cryptoKeyEncrypter` | Write pending templates, write audit events, call `kms.encrypt` (wrap DEK) | Cannot call `kms.decrypt`, cannot modify active profiles, cannot delete audit entries |
| **Biometric Verifier & Dedup Engine** | `sa-biometrics-verifier@` | Firestore collections: `biometric_vault`, `biometric_gallery_index`<br>KMS: `projects/*/locations/*/keyRings/*/cryptoKeys/biometric-dek-wrap` | `roles/datastore.viewer`<br>`roles/cloudkms.cryptoKeyDecrypter` | Read active templates, call `kms.decrypt` (unwrap DEK) to perform 1:N deduplication | Cannot write vault records, cannot modify user account records, cannot modify audit ledger |
| **Adjudication & Review Console Service** | `sa-biometrics-reviewer@` | Firestore collection: `biometric_duplicate_cases`<br>Audit collection: `biometric_audit_ledger` | `roles/datastore.user` (restricted path condition) | Read blinded case metadata, update case status (`RESOLVED`, `DISMISSED`) | Cannot view raw face crops, cannot decrypt embeddings without explicit dual-authorization |
| **Inventory & Metadata Scanner** | `sa-biometrics-inventory@` | Firestore collection: `biometric_vault` (metadata fields only) | `roles/datastore.viewer` | Read template IDs, embedding space IDs, model names, classification tags | Zero write capability, zero delete capability, zero Cloud KMS access |
| **Audit Ledger & Notary Service** | `sa-biometrics-audit-notary@` | Firestore collection: `biometric_audit_ledger`<br>GCS Bucket: `gs://kelasagara-immutable-audit-checkpoints/` | `roles/datastore.user` (append-only)<br>`roles/storage.objectCreator` | Append sequenced audit records, upload signed ECDSA checkpoints | Zero update/delete on audit documents, zero bucket overwrite/delete |
| **CI / CD Pipeline** | `sa-cicd-runner@` | Cloud Build, Artifact Registry | `roles/cloudbuild.builds.editor`<br>`roles/artifactregistry.writer` | Hermetic compilation, unit/integration testing on local mock emulators | Zero access to production Firestore, zero access to production KMS keys |

---

### 3. Role Separation & Boundary Enforcements

#### 3.1 Separation of Encrypter and Decrypter Roles
A paramount defense in Phase 20.13 is the cryptographic separation between `sa-biometrics-enrollment` and `sa-biometrics-verifier`:
- The enrollment worker has **only** `roles/cloudkms.cryptoKeyEncrypter`. If an adversary compromises the enrollment worker, they **cannot decrypt any stored biometric templates in the vault**.
- The verifier service has `roles/cloudkms.cryptoKeyDecrypter`, but runs in an isolated network sandbox without public ingress, reachable only via authenticated internal gRPC from the API gateway.

#### 3.2 Audit Ledger Tamper Proofing
`sa-biometrics-audit-notary` has permission to create objects in the GCS audit bucket (`gs://kelasagara-immutable-audit-checkpoints/`), which is configured with **Cloud Storage Bucket Lock in Compliance Mode**:
- Once an external signed checkpoint is uploaded, it cannot be deleted, modified, or overwritten by any identity, including project owners, for the duration of the retention policy (7 years).

#### 3.3 CI/CD Production Isolation
The continuous integration principal (`sa-cicd-runner`) operates exclusively with local test fixtures and mock key providers (`LocalDevKeyProvider`). It possesses no IAM permissions in production GCP projects, eliminating supply-chain exposure from build workers.

---

### 4. Verification Evidence

These IAM boundaries are programmatically verified in `src/tests/phase20_13_privileged_backend_security.test.ts`:
- Test 6 verifies that the inventory service exposes zero write methods.
- Test 7 verifies reviewer purpose gating.
- Test 8 proves that CI principals are rejected from production vaults.
- Test 10 verifies that cross-service impersonation without explicit `roles/iam.serviceAccountTokenCreator` is halted.
