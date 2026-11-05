# KELASAGARA V20.17 — RUNTIME PRINCIPAL VERIFICATION
## Distinguishing Backend Service Accounts from End-User JWTs and Enforcing Calling Context

**Author:** Principal Cloud Security Architect, IAM Engineer  
**Date:** 2026-11-01  
**Repository:** `kelasagaara_v17`  
**Parent Commit:** `bd1d5f57ee4ad1921e83f382ab67d06274a3fb2c`  
**Branch:** `security/phase20.17-trusted-execution-provenance`  
**Status:** `ACTIVE_VERIFIED`  

---

### 1. The Vulnerability: End-User vs Workload Identity Conflation

A severe architectural vulnerability occurs when an application backend accepts any valid JWT signed by Google/Firebase without verifying the token's **issuer (`iss`)**, **audience (`aud`)**, and **subject type**:

- **Firebase Auth End-User JWTs:** Issued by `https://securetoken.google.com/<project-id>`, representing a human worker or employer.
- **Google Cloud Workload OIDC Tokens:** Issued by `https://accounts.google.com`, representing an authorized IAM service account.

If a backend service accepts an end-user JWT containing a custom claim such as `role: 'worker'` or `is_service: true` on an internal administrative or service-to-service endpoint, an attacker can bypass all internal workload isolation. Furthermore, untrusted client headers like `X-Principal`, `X-Forwarded-User`, or `X-Service-Account` can lead to identity spoofing if trusted naively.

---

### 2. Implementation: `InternalWorkloadIdentityServiceV17`

`backend/src/services/internal_workload_identity_v17.ts` implements strict runtime principal verification:

```typescript
export class InternalWorkloadIdentityServiceV17 {
  // Verifies that a request carries an authentic GCP Service Account OIDC token
  public static verifyWorkloadIdentity(
    rawAuthHeader: string,
    expectedAudience: string,
    allowedServiceAccounts: string[]
  ): WorkloadIdentityContext { ... }
}
```

---

### 3. Verification Rules and Assertions

#### A. Strict Issuer & Audience Enforcement
- **Issuer Validation:** Must equal `https://accounts.google.com` exactly. Tokens from `https://securetoken.google.com/...` are rejected immediately with `WORKLOAD_ERR_UNAUTHORIZED_ISSUER`.
- **Audience Validation:** Must match the exact URL of the receiving service (e.g. `https://vault-internal.service.internal`). Wildcards or missing audiences are rejected (`WORKLOAD_ERR_INVALID_AUDIENCE`).

#### B. Cryptographic Signature & Expiration
- Token signature is verified against Google's public JSON Web Key Set (`https://www.googleapis.com/oauth2/v3/certs`).
- Expiration (`exp`) is checked against current system time. Expired tokens are rejected (`WORKLOAD_ERR_EXPIRED_TOKEN`).

#### C. Absolute Rejection of Caller-Supplied Header Spoofing
- The service ignores and rejects any request containing client-supplied headers intended to override identity:
  - `x-principal`
  - `x-forwarded-user`
  - `x-service-account`
  - `x-authorized-identity`
- Identity is derived **exclusively** from the cryptographically verified JWT payload (`token.email`).

#### D. End-User Role Escalation Defense
- A Firebase user token with `{ uid: "attacker123", role: "worker", admin: true }` will fail issuer validation immediately because its issuer is `securetoken.google.com`.
- End-users can never call internal east-west microservice endpoints.

#### E. In-Memory JTI Replay Prevention
- Workload identity tokens include a unique token identifier (`jti`).
- The service maintains a high-performance in-memory cache of seen JTIs with TTLs matching token expiration.
- If a token with an identical JTI is presented within its validity window on a single-use internal transaction, it is rejected as a replay attack (`WORKLOAD_ERR_REPLAY_DETECTED`).

#### F. UID Substitution Gating
- When a service account performs an action on behalf of a user (e.g. `sa-biometrics-verifier` checking a 1:1 match for user `user_alice_456`), the service verifies that the calling session context matches the target UID.
- Arbitrary substitution of target UIDs by an unauthorized session is rejected (`WORKLOAD_ERR_UNAUTHORIZED_UID_SUBSTITUTION`).
