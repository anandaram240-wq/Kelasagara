# PHASE 20.19: PILOT CRYPTOGRAPHIC KEY & DATASET ISOLATION DESIGN

## 1. Multi-Tenant vs Dedicated Dataset Isolation

### 1.1 The Cross-Environment Blast Radius Threat
In biometric pilots, running pilot test records in a shared production database or wrapping pilot Data Encryption Keys (DEKs) using the production Key Encryption Key (KEK) exposes the entire system to critical risks:
- Accidental migration or corruption of real human identities.
- Key compromise: if a test harness or pilot verifier leaks a DEK, production templates could be decrypted if the KEK is shared.
- Environment confusion: code querying the wrong Firestore database might read or write pilot templates into production collections.

---

## 2. Phase 20.19 Implementation: Software-Level Isolation Enforcement

`PilotCryptographicIsolationEngineV19` (`backend/src/services/pilot_cryptographic_isolation_v19.ts`) implements fail-closed validation at both the database and cryptographic layers.

### 2.1 Isolation Classification: `COHORT_LEVEL_CRYPTOGRAPHIC_ISOLATION_WITH_PER_RECORD_AUTHORIZATION`
> [!IMPORTANT]
> The pilot cryptographic isolation architecture is formally classified as:
> **`COHORT_LEVEL_CRYPTOGRAPHIC_ISOLATION_WITH_PER_RECORD_AUTHORIZATION`**
>
> - A single shared pilot Key Encryption Key (`pilot_dek_wrap`) wraps DEKs for all participants in the pilot cohort.
> - While this guarantees that compromising the pilot wrapping key cannot decrypt production templates, **it is NOT per-user cryptographic key isolation**. Any principal possessing unwrap authority on `pilot_dek_wrap` can unwrap any pilot cohort member's DEK.
> - Per-user isolation at runtime is achieved through unique random DEKs per template, session UID ownership matching, and environment-scoped AAD binding, not through dedicated KMS keys per individual user.

### 2.2 Dedicated Named Database & Key IDs
The system enforces strict parameter boundaries:
- **Pilot Firestore Named Database:** `biometric-pilot-vault-db`
- **Pilot KMS Key ID:** `projects/kelasagara-sandbox/locations/global/keyRings/biometrics-pilot-ring/cryptoKeys/pilot_dek_wrap`
- **Production Named Database:** `(default)` (or `biometric-vault-db`)
- **Production KMS Key ID:** `projects/kelasagara-prod/locations/global/keyRings/biometrics-prod-ring/cryptoKeys/prod_dek_wrap`

### 2.3 Application-Defined Binary Canonical AAD (ISO/IEC 19772:2020)
In accordance with the authenticated associated data (AAD) binding principles of **ISO/IEC 19772:2020** (Information security — Authenticated encryption):
- The length-prefixed binary canonical encoding is an **application-defined Kelasagara format** designed to eliminate delimiter collision and field-shifting attacks when binding multiple context fields into the AES-GCM Associated Data (AD) parameter.
- The AAD strictly binds:
  `datasetScope=PILOT_NONPROD | tenant=kelasagara-pilot | accountUid=<uid> | templateId=<tpl>`
- Any attempt to alter `datasetScope`, `tenant`, or `accountUid` invalidates the AES-256-GCM authentication tag, failing decryption closed.

### 2.4 Separation of Software-Level Tests from Actual Cloud KMS Evidence
An exhaustive audit of `ProtectedHmacKeyManagerV19`, `PlanEncryptionKeyManagerV19`, and `PilotCryptographicIsolationEngineV19` establishes the exact provider utilized across all test suites:

| Component / Test Suite | Implementation Class | Exact Provider Type | Provider Execution Mechanism | Live Cloud KMS Verified? |
| :--- | :--- | :---: | :--- | :---: |
| **Track C: Pilot Isolation** | `MockKmsProviderV19` | **In-Memory Mock Provider** | Node.js `crypto.createCipheriv` / `createDecipheriv` simulating KMS envelope unwrap | ❌ **NO (Unverified)** |
| **Track G: HMAC Attestation** | `ProtectedHmacKeyManagerV19` | **In-Memory Software Provider** | 32-byte memory buffer initialized via SHA-256 root or `crypto.randomBytes(32)` | ❌ **NO (Unverified)** |
| **Track I: Plan Encryption** | `PlanEncryptionKeyManagerV19` | **In-Memory Software Provider** | Node.js AES-256-GCM cipher simulating storage encryption key | ❌ **NO (Unverified)** |
| **Track K: KMS Resource Mapping** | `getCanonicalCloudKmsHmacMapping` | **Static Specification Provider** | Static string interpolation of GCP resource path and IAM roles | ❌ **NO (Unverified)** |

> [!IMPORTANT]
> **Gate A vs Gate B Boundary on KMS and Pilot Isolation:**
> - **Gate A (Software & Security Readiness):** Confirms that software-level interface policies, fail-closed cross-environment guards, AAD canonical binding, and rotation state machines **passed 100% in local test environments**.
> - **Gate B (Real Non-Production Cloud Infrastructure):** Confirms live GCP Cloud KMS KeyRing provisioning, Cloud KMS IAM bindings, and dedicated named Firestore databases. **Because Gate B remains BLOCKED, live Cloud KMS integration and live cloud database isolation are strictly UNVERIFIED.**

### 2.5 HMAC Environment Domain Separation
To prevent cross-environment secret correlation:
- **Domain Separation Mechanism:** All HMAC secret digests are generated using an explicit domain prefix:
  $$\text{HMAC-SHA256}(K, \text{"KELASAGARA-ATTESTATION-v19.2:"} \parallel \text{environment} \parallel \text{":"} \parallel \text{secretValue})$$
- **Cross-Environment Collision Defense:** Even if an identical secret value is used in both `sandbox` and `staging`, and even if an identical key buffer were accidentally shared, the resulting public attestation digests differ deterministically.
- **Security Guarantee:** Recovering the secret value or finding cross-environment collisions is **computationally infeasible under standard cryptographic assumptions** (preimage resistance and pseudo-random function security of HMAC-SHA256, search space $2^{256}$). No claim of live Cloud KMS hardware protection is made.

---

## 3. Test Evidence

Track C of `phase20_19_pilot_gate_a_closure.test.ts` validates:
- **Test 19:** Pilot record queried via production DB throws `ERR_CROSS_ENVIRONMENT_ISOLATION_VIOLATION` (PASS).
- **Test 20:** Pilot record decrypted using production KMS key throws `ERR_CROSS_ENVIRONMENT_ISOLATION_VIOLATION` (PASS).
- **Test 21:** Altered AAD context triggers `AUTHENTICATION_TAG_VERIFICATION_FAILED` or `ERR_KMS_UNWRAP_FAILED` (PASS).
- **Test 22:** Caller session UID mismatch blocked before unwrapping (`UNAUTHORIZED_RECORD_ACCESS`) (PASS).
- **Test 23:** Valid pilot decryption succeeds and returns exact 128-dimensional Float32Array embedding (PASS).
