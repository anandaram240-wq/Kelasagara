# PHASE 20.14: IAM FORENSIC STATUS & SERVICE IDENTITY CATEGORIZATION
## Rigorous Classification of Service Identities, Workload Identity Architecture, and Key Prevention

**Date:** November 2026  
**System:** Kelasagara Biometric Identity Service  
**Author:** Principal Cloud Security Architect & IAM Auditor  
**Status:** APPROVED & AUDITED  
**Repository:** `kelasagaara_v17`  
**Classification:** SOURCE_VERIFIED & IAC_DECLARED  

---

### 1. Forensic Status of the Five Proposed Service Identities

In KELASAGARA V20.13, five dedicated service identities were formulated to enforce the Principle of Least Privilege across the biometric subsystem:
1. `sa-biometrics-enrollment`
2. `sa-biometrics-verifier`
3. `sa-biometrics-reviewer`
4. `sa-biometrics-inventory`
5. `sa-biometrics-audit-notary`

To maintain absolute audit integrity, this investigation establishes their exact technical reality and prevents conflation between design and deployment:

| Service Identity | Architectural Specification | Terraform IaC Declaration | Existing Live GCP Identity | Verified in Live Cloud Project | Active Runtime Identity |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `sa-biometrics-enrollment` | **YES** (V20.13 Matrix) | **YES** (`infra/terraform/service_accounts.tf`) | **NO** (Not provisioned in live project) | **NO** (`BLOCKED_SANDBOX_IAM_NOT_AVAILABLE`) | **NO** (Local test harnesses only) |
| `sa-biometrics-verifier` | **YES** (V20.13 Matrix) | **YES** (`infra/terraform/service_accounts.tf`) | **NO** (Not provisioned in live project) | **NO** (`BLOCKED_SANDBOX_IAM_NOT_AVAILABLE`) | **NO** (Local test harnesses only) |
| `sa-biometrics-reviewer` | **YES** (V20.13 Matrix) | **YES** (`infra/terraform/service_accounts.tf`) | **NO** (Not provisioned in live project) | **NO** (`BLOCKED_SANDBOX_IAM_NOT_AVAILABLE`) | **NO** (Local test harnesses only) |
| `sa-biometrics-inventory` | **YES** (V20.13 Matrix) | **YES** (`infra/terraform/service_accounts.tf`) | **NO** (Not provisioned in live project) | **NO** (`BLOCKED_SANDBOX_IAM_NOT_AVAILABLE`) | **NO** (Local test harnesses only) |
| `sa-biometrics-audit-notary` | **YES** (V20.13 Matrix) | **YES** (`infra/terraform/service_accounts.tf`) | **NO** (Not provisioned in live project) | **NO** (`BLOCKED_SANDBOX_IAM_NOT_AVAILABLE`) | **NO** (Local test harnesses only) |

**Conclusion:** The identities are **authoritative source-level specifications and fully formulated Terraform Infrastructure-as-Code resources**. They are not yet live Google Cloud principals because no authorized sandbox cloud project is configured, and production deployment is strictly prohibited.

---

### 2. Responsibilities and Capabilities Matrix

| Service Principal | Required Responsibilities | Explicitly Prohibited Capabilities |
| :--- | :--- | :--- |
| **`sa-biometrics-enrollment`** | Ingest canonical face templates, invoke Cloud KMS DEK encryption (`cloudkms.cryptoKeyEncrypter`), write pending vault records, append enrollment audit log | Unwrapping DEKs (`cloudkms.cryptoKeyDecrypter`), signing audit checkpoints (`cloudkms.signerVerifier`), modifying active user profiles directly |
| **`sa-biometrics-verifier`** | Read active gallery index, unwrap DEK under approved 1:N deduplication context (`cloudkms.cryptoKeyDecrypter`), compute cosine distance | Creating or writing template records, modifying user accounts, changing case adjudication decisions, deleting audit records |
| **`sa-biometrics-reviewer`** | Read blinded duplicate adjudication cases, record review resolution (`RESOLVED`, `DISMISSED`) | Unwrapping DEKs, viewing raw face embeddings, viewing unmasked PII, modifying template status |
| **`sa-biometrics-inventory`** | Strictly read-only scanning of template classifications, metadata flags, and counts | Any database create, update, set, or delete; any Cloud KMS cryptographic operations; modifying audit records |
| **`sa-biometrics-audit-notary`** | Append sequenced audit ledger events, sign periodic checkpoints with ECDSA P-256 (`cloudkms.signerVerifier`), upload checkpoints to Cloud Storage | Deleting or overwriting Cloud Storage audit objects (`storage.objects.delete`), modifying biometric vault records |

---

### 3. Cloud IAM Security Vectors & Threat Mitigation

#### 3.1 Eliminating Long-Lived Service Account Keys
Long-lived service account JSON keys represent the single most common cause of credential leakage and supply chain compromise in cloud environments.
- **Enforcement:** The platform enforces the Google Cloud Organization Policy constraint `constraints/iam.disableServiceAccountKeyCreation`.
- **Prohibition:** Neither developers nor CI/CD runners may invoke `iam.serviceAccountKeys.create`.
- **Mechanism:** Authentication is performed exclusively via **Workload Identity Federation**:
  - GKE workloads authenticate via Kubernetes Service Account (KSA) to Google Service Account (GSA) binding.
  - Cloud Run workloads assume the service account identity directly via the runtime environment metadata server.
  - GitHub Actions CI/CD workflows authenticate via OpenID Connect (OIDC) token exchange, exchanging a short-lived GitHub token for a Google federated token.

#### 3.2 Impersonation & Token Creation Safeguards
Privilege escalation via service account impersonation (`iam.serviceAccounts.actAs`) or token minting (`roles/iam.serviceAccountTokenCreator`) is strictly controlled:
- Service accounts are not granted `roles/iam.serviceAccountTokenCreator` on each other.
- Cross-service impersonation is blocked by default; microservices cannot mint credentials for peer services.

#### 3.3 Cryptographic Key Separation (Cloud KMS)
- `sa-biometrics-enrollment` is granted **only** `roles/cloudkms.cryptoKeyEncrypter` on `biometric-dek-wrap-key`. If the enrollment service is compromised, it cannot decrypt any existing biometric vault templates.
- `sa-biometrics-verifier` is granted **only** `roles/cloudkms.cryptoKeyDecrypter` on `biometric-dek-wrap-key`.
- `sa-biometrics-audit-notary` is granted `roles/cloudkms.signerVerifier` on `audit-checkpoint-signing-key`.
- Public verification keys are made accessible via `roles/cloudkms.publicKeyViewer` without granting signing rights.
