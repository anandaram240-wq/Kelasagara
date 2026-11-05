# KELASAGARA V20.3: IAM REMEDIATION & ARCHITECTURAL TRUTH
## Google Cloud IAM Scoping Audit & Biometric Isolation Architecture

**Project:** Kelasagara Major Project  
**System:** Worker Marketplace & Multi-Factor Biometric Identity Platform  
**Document Code:** KS-SEC-P20.3-08  
**Classification:** Core Security Engineering Specification & Forensic Audit

---

## 1. FORENSIC CORRECTION: GCP IAM FIRESTORE SCOPING

### The Erroneous Claim in Prior Documentation:
Certain earlier phase documentation claimed that the Google Cloud IAM role `roles/datastore.user` could be granted to a backend service account and "strictly scoped at the IAM level exclusively to the `/biometric_vault` collection path".

### The Technical Reality in Google Cloud IAM:
1. **GCP IAM Granularity:** In Google Cloud Platform, IAM roles (including `roles/datastore.user`, `roles/datastore.viewer`, and `roles/datastore.owner`) operate at the **project** level or the **database** level (for multi-database Firestore configurations).
2. **No Collection-Level IAM:** GCP IAM does **not** support resource-level IAM policies on specific collection paths (e.g. `//firestore.googleapis.com/projects/PROJECT_ID/databases/(default)/documents/biometric_vault`). Granting `roles/datastore.user` grants read/write permissions to **all** collections in that Firestore database.
3. **Application Security Rules vs IAM:** Collection-level and document-level access rules are evaluated by **Firebase Security Rules** (`firestore.rules`) for requests authenticated via Firebase Auth (client SDKs). However, backend servers and Cloud Functions utilizing the **Firebase Admin SDK** or Google Cloud client libraries bypass Firebase Security Rules completely and operate with the full permissions of the underlying GCP IAM service account.

---

## 2. PRODUCTION ISOLATION ARCHITECTURES FOR BIOMETRIC VAULT

To achieve true, defense-in-depth isolation for biometric data where backend compromised services cannot access the biometric vault, one of the following two sanctioned production architectures must be deployed:

### Architecture Option A: Named Isolated Firestore Database (Recommended)
Firestore supports multiple databases per GCP project:
- `(default)`: Houses worker marketplace collections (`workers`, `hirers`, `jobs`, `bookings`, `telemetry`).
- `biometric-isolated-vault`: A dedicated named database containing only `/biometric_vault` and `/biometric_devices`.
- **IAM Scoping:** A dedicated Biometric Microservice Service Account (`sa-biometric-vault@kelasagara-prod.iam.gserviceaccount.com`) is granted `roles/datastore.user` condition-scoped strictly to the `biometric-isolated-vault` database resource name. General marketplace backend services possess access only to `(default)`.

### Architecture Option B: Multi-Project GCP Hard Isolation
- **Project 1:** `kelasagara-marketplace-prod` (Web/App hosting, marketplace database, storage).
- **Project 2:** `kelasagara-biometrics-secure-prod` (Dedicated project housing Cloud KMS KEKs and biometric template store).
- **Service-to-Service Trust:** Marketplace backend communicates with the Biometric Engine via mutual TLS (mTLS) or Cloud Endpoints with signed JWT tokens. The marketplace service account has zero direct access to Project 2.

---

## 3. PRINCIPLE OF LEAST PRIVILEGE SERVICE ACCOUNT AUDIT

| Service Account | Role Assigned | Justification |
| :--- | :--- | :--- |
| `sa-biometric-backend@` | `roles/cloudkms.cryptoKeyEncrypterDecrypter` | Restricted exclusively to `projects/.../cryptoKeys/sface-vault-kek-v1` |
| `sa-biometric-backend@` | `roles/playintegrity.verifier` (or API caller) | Restricted to invoking Google Play Integrity decoding RPC |
| `sa-biometric-backend@` | `roles/datastore.user` (scoped to vault DB) | Restricted to reading/writing encrypted envelopes in biometric vault |
| `sa-marketplace-api@` | `roles/datastore.user` (default DB only) | **Zero** access to Cloud KMS KEK; **Zero** access to biometric vault DB |
