# KELASAGARA V20.2: TRUSTED ANDROID APPLICATION INTEGRITY ENGINE
## PHASE 20.2 TECHNICAL REPORT 5: CENTRALIZED SECURITY DECISION ENGINE & ENVIRONMENT TIERS

**Author:** Principal Security Architect & Distributed Systems Engineer  
**Project:** Kelasagara Major Project  
**Phase:** 20.2 — Trusted Android Application Integrity Engine  
**Policy Engine:** `backend/src/services/play_integrity_policy.ts`  
**Classification System:** Internal 6-State Outcome Model  
**Status:** Certified Policy Specification  

---

### 1. CLASSIFICATION OUTCOMES

The Kelasagara Security Decision Engine maps raw Google Play Integrity signals into 6 internal, actionable decision states:

```
+----------------------------------------------------------------------------------------------------+
|                                    INTERNAL INTEGRITY DECISION STATES                              |
+----------------------------------------------------------------------------------------------------+
|  OUTCOME                    |  HTTP   |  TRIGGER CONDITIONS                           |  ACTION    |
+-----------------------------+---------+-----------------------------------------------+------------+
|  INTEGRITY_ACCEPTED         |  200    |  App recognized, device verified, hash match  |  PROCEED   |
|  INTEGRITY_RETRY            |  401    |  Token expired (> 300s age)                   |  RETRY     |
|  INTEGRITY_STEP_UP          |  403    |  Basic integrity present, hardware missing    |  STEP_UP   |
|  INTEGRITY_RESTRICTED       |  403    |  Device integrity completely missing / unk    |  RESTRICT  |
|  INTEGRITY_REJECTED         |  403    |  Compromised binary, bad cert, tamper hash    |  BLOCK     |
|  INTEGRITY_UNAVAILABLE      |  503    |  Google API timeout, network drop             |  FAIL-CLOSE|
+----------------------------------------------------------------------------------------------------+
```

---

### 2. ENVIRONMENT ISOLATION TIERS

To ensure development agility without compromising production defenses, policy rules are partitioned across 3 strict tiers:

#### 2.1 LOCAL Environment (`APP_ENV=LOCAL`)
- Uses `MockPlayIntegrityGoogleClient`.
- Validates canonical `requestHash` calculation, format, and parameter binding.
- Rejects forged tokens, tampered parameters, and mismatched package names.
- Permits rapid, deterministic offline unit and adversarial test execution without GCP billing or quotas.

#### 2.2 STAGING Environment (`APP_ENV=STAGING`)
- Uses real Google Play Integrity API via staging Google Cloud credentials.
- Permits internal test track distribution and approved sideloaded APK installations where `certificateSha256Digest` matches developer signing keys.
- Requires minimum `MEETS_BASIC_INTEGRITY` or `MEETS_DEVICE_INTEGRITY`.
- Triggers `INTEGRITY_STEP_UP` if running on sideloaded hardware.

#### 2.3 PRODUCTION Environment (`APP_ENV=PRODUCTION`)
- Strictly enforces `PLAY_RECOGNIZED` from Google Play Store.
- Strictly requires `MEETS_DEVICE_INTEGRITY` (hardware-backed or OEM-certified Play Protect device).
- Zero tolerance for `UNAPPROVED_SIGNING_CERTIFICATE` or `UNRECOGNIZED_VERSION`.
- **CRITICAL SECURITY INVARIANT:** There is NO bypass flag. Setting `REQUIRE_PLAY_INTEGRITY=false` in production has NO effect; the middleware strictly evaluates and enforces the policy.
