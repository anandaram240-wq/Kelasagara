# KELASAGARA V20.16 — ADC AND WORKLOAD IDENTITY SECURITY
## Environment-Sensitive Credential Rules and Authentication Architecture

**Author:** Principal Cloud Security Architect, IAM Engineer  
**Date:** 2026-11-01  
**Repository:** `kelasagaara_v17`  
**Engine:** `backend/src/services/cloud_runtime_identity_verifier_v16.ts`  
**Status:** ENFORCED AND VERIFIED  

---

### 1. Defect Analysis: The Flaw in Blanket ADC Rejection

In Phase 20.15, rule `POL-02` evaluated Application Default Credentials (ADC) coarsely: it flagged unverified default credentials, but failed to distinguish between legitimate Google Cloud Workload Identity (which surfaces through the Google ADC SDK) and insecure developer user credentials or static JSON keys.

Categorically rejecting "ADC" breaks valid cloud-native deployments because Google Cloud Run, Google Kubernetes Engine (GKE), and Google Compute Engine (GCE) all deliver workload identity **through the ADC resolution chain via the instance metadata server**.

Phase 20.16 completely overhauls `POL-02` by introducing an environment-aware authentication verification engine (`CloudRuntimeIdentityVerifier`).

---

### 2. Taxonomy of the Five Credential Sources

| Credential Source Type | Underlying Mechanism | Security Profile | Production Policy | CI Policy | Local Dev Policy |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **1. `DOWNLOADED_SA_KEY_JSON`** | Static RSA private key JSON file (`type: "service_account"`). | **HIGH RISK.** Non-expiring secret; vulnerable to exfiltration and git leaks. | ❌ **STRICTLY PROHIBITED** | ❌ **STRICTLY PROHIBITED** | ⚠️ Restricted to mock sandbox |
| **2. `LOCAL_USER_ADC`** | Local OAuth user token via `gcloud auth application-default login` (`type: "authorized_user"`). | **MEDIUM RISK.** Tied to human identity; wide project permissions. | ❌ **STRICTLY PROHIBITED** | ❌ **STRICTLY PROHIBITED** | ✅ **PERMITTED** (with explicit sandbox authorization) |
| **3. `ATTACHED_WORKLOAD_IDENTITY`** | Metadata server token exchange (`http://metadata.google.internal/...`) on Cloud Run/GKE. | **BEST PRACTICE.** Ephemeral, non-exportable tokens bound to task instance. | ✅ **MANDATED** | N/A (Cloud runtime only) | N/A |
| **4. `WORKLOAD_IDENTITY_FEDERATION`** | OIDC token exchange (`type: "external_account"`) via GitHub Actions / GitLab CI. | **BEST PRACTICE.** Keyless authentication; short-lived cryptographically signed tokens. | ✅ **APPROVED** | ✅ **MANDATED** | N/A |
| **5. `AUTHORIZED_IMPERSONATION`** | Short-lived token generated via `roles/iam.serviceAccountTokenCreator`. | **CONTROLLED.** Ephemeral session token (< 1 hr); full audit trail. | ❌ **REJECTED in Prod Runtime** | ✅ **PERMITTED for Deployers** | ⚠️ Controlled |

---

### 3. Environment-Sensitive Enforcement Rules

#### A. Hosted Production Workloads (`PRODUCTION_HOSTED`)
1. **Keyless Mandate:** Static downloaded service-account JSON keys are strictly rejected with `ERR_STATIC_PRIVATE_KEY_PROHIBITED`.
2. **User ADC Rejection:** Developer user credentials cannot authenticate production workloads (`ERR_USER_CREDENTIALS_IN_PRODUCTION`).
3. **Identity Pinning:** The runtime identity must match the expected dedicated service account (e.g. `sa-biometrics-verifier`). Mismatches throw `ERR_RUNTIME_IDENTITY_MISMATCH`.
4. **No Runtime Impersonation:** Services must execute directly under their attached identity; impersonation is blocked with `ERR_UNAPPROVED_IMPERSONATION`.

#### B. Local Development Workloads (`LOCAL_DEVELOPMENT`)
1. **Controlled Developer User ADC:** Developers can use `LOCAL_USER_ADC` for local debugging **only if explicit sandbox authorization is configured** (e.g. approved sandbox project).
2. **Production Wall:** If a local environment attempts to resolve or target a production project, execution is halted with `ERR_PRODUCTION_CREDENTIAL_IN_LOCAL_DEV`.
3. **Approved Sandbox Identities:** Local mock credentials must match approved sandbox service identities.

#### C. CI Pipeline Workloads (`CI_PIPELINE`)
1. **Workload Identity Federation Only:** Automated build and test jobs must authenticate using short-lived OIDC tokens via WIF (`WORKLOAD_IDENTITY_FEDERATION`).
2. **No Static Keys in CI:** Storing long-lived service account JSON keys in CI secrets is blocked with `ERR_STATIC_PRIVATE_KEY_IN_CI`.
3. **Production Access Block:** CI test pipelines are prohibited from accessing production projects (`ERR_PRODUCTION_ACCESS_FROM_CI`).

---

### 4. Adversarial Test Evidence

The 6 identity tests in `phase20_16_cloud_runtime_authorization.test.ts` demonstrate 100% policy enforcement:
- **Test 1:** Approved attached service account accepted in hosted production -> **PASS**
- **Test 2:** Approved Workload Identity Federation (WIF) accepted in CI -> **PASS**
- **Test 3:** Downloaded SA JSON key rejected in hosted production -> **PASS** (`ERR_STATIC_PRIVATE_KEY_PROHIBITED`)
- **Test 4:** Developer user ADC rejected in hosted production -> **PASS** (`ERR_USER_CREDENTIALS_IN_PRODUCTION`)
- **Test 5:** Unauthorized impersonation rejected in production -> **PASS** (`ERR_UNAPPROVED_IMPERSONATION`)
- **Test 6:** Unapproved sandbox identity rejected in local development -> **PASS** (`ERR_UNAUTHORIZED_SANDBOX_IDENTITY`)

### 5. Conclusion

Application Default Credentials are now properly disambiguated. Secure, keyless Workload Identity is permitted and mandated in cloud runtimes, while dangerous long-lived static JSON keys and unauthorized developer tokens are fail-closed blocked.
