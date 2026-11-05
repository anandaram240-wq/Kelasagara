# KELASAGARA V20.18 — WORKLOAD TOKEN REPLAY ASSURANCE & DURABLE IDEMPOTENCY
## Multi-Request Token Legitimacy vs Durable Request-Level Replay Controls

**Author:** Principal Cloud IAM Architect, Application Security Engineer  
**Date:** 2026-11-01  
**Repository:** `kelasagaara_v17`  
**Parent Commit:** `2233327` (`security/phase20.17-trusted-execution-provenance`)  
**Branch:** `security/phase20.18-pilot-readiness-corrections`  
**Status:** `ACTIVE_VERIFIED`  

---

### 1. The Flaw of Token-Level JTI Replay Prevention

In standard Google Cloud IAM, a service account generates an OIDC ID token with a 1-hour expiration. Crucially:
1. Google Cloud Service Account ID tokens **frequently omit the `jti` claim**. Assuming `jti` is always present leads to false rejections or complete failure to enforce replay controls.
2. In production east-west architectures, a service account legitimately issues hundreds of distinct RPC requests over the 1-hour lifetime of a single valid OIDC token. Treating the entire token as single-use breaks legitimate microservice communication.
3. An in-memory cache loses all state upon process restart, allowing an attacker to replay requests against a restarted service or across multiple load-balanced container replicas.

---

### 2. Implementation: Durable Request-Level Idempotency (`InternalWorkloadIdentityServiceV18`)

Phase 20.18 replaces brittle in-memory token caching with **Durable Request-Level Idempotency**:

```mermaid
flowchart TD
    Caller[Calling Microservice\nsa-biometrics-verifier] -->|HTTPS + OIDC ID Token + Operation Nonce| Verifier[Target Microservice\nInternalWorkloadIdentityServiceV18]
    
    subgraph Step1 [Phase 1: Token Claims Verification]
        Verifier -->|1. Check Token Issuer| Iss{iss == accounts.google.com?}
        Verifier -->|2. Check Exact Aud| Aud{aud == targetServiceUrl?}
        Verifier -->|3. Check Exp & Iat| Exp{exp > now & iat <= now?}
        Verifier -->|4. Check Signature| Sig{Signature Valid?}
        Verifier -->|5. Check Identity| Email{email == expected SA?}
    end
    
    subgraph Step2 [Phase 2: Durable Request Fingerprint & Nonce Consumption]
        Verifier -->|Compute Canonical Fingerprint| FP[callerEmail | targetUrl | method | endpoint | targetUid | targetResource | bodyDigest | nonce | opId]
        Verifier -->|Atomic Check-and-Set| Store[(Distributed Durable Replay Store\nFirestore / Redis)]
        Store -->|Nonce Already Seen| Reject[Reject: ERR_DURABLE_REQUEST_REPLAY]
        Store -->|Nonce Fresh| Accept[Accept & Mark Consumed]
    end
```

---

### 3. Key Guarantees Verified

1. **JTI Claim Independence:**
   A valid Google Cloud SA token without a `jti` claim is accepted (Test 16).
2. **Legitimate Token Reuse:**
   A single valid OIDC token can authenticate multiple sequential requests provided each sensitive operation presents a unique server-issued `operationNonce` (Test 17).
3. **Atomic Replay Prevention:**
   Submitting the same operation nonce twice is permanently blocked (`ERR_DURABLE_REQUEST_REPLAY`, Test 18).
4. **Multi-Replica Consistency:**
   Two application instances connected to the shared durable store cannot process the same one-time operation concurrently (Test 19).
5. **Persistence Across Restart:**
   The consumed nonce ledger survives process restarts, preventing replay attacks after container restarts or redeployments (Test 20).
