# KELASAGARA V20.2: TRUSTED ANDROID APPLICATION INTEGRITY ENGINE
## PHASE 20.2 TECHNICAL REPORT 4: BACKEND VERIFICATION SPECIFICATION & GOOGLE API INTEGRATION

**Author:** Senior TypeScript Security Engineer & Backend Architect  
**Project:** Kelasagara Major Project  
**Phase:** 20.2 — Trusted Android Application Integrity Engine  
**Verification Service:** `backend/src/services/play_integrity_verifier.ts`  
**API Endpoint:** `https://playintegrity.googleapis.com/v1/{packageName}:decodeIntegrityToken`  
**Google Scope:** `https://www.googleapis.com/auth/playintegrity`  
**Status:** Certified Backend Specification  

---

### 1. GOOGLE PLAY INTEGRITY SERVER-SIDE DECODING

Under the Google Play Standard Integrity API, integrity tokens issued to the Android application are signed, encrypted JWE/JWS blobs. The backend decodes and authenticates these tokens via an authenticated server-to-server call to Google Play Developer APIs:

```
+--------------------------------------------------------------------------------------------------+
|                            GOOGLE INTEGRITY SERVER DECODING FLOW                                 |
+--------------------------------------------------------------------------------------------------+
|                                                                                                  |
|   1. Backend receives incoming HTTPS request with X-Play-Integrity-Token.                         |
|   2. ProductionPlayIntegrityGoogleClient obtains Google OAuth2 access token via GoogleAuth       |
|      using backend service account credentials.                                                  |
|   3. Calls Google API:                                                                           |
|      POST https://playintegrity.googleapis.com/v1/com.kelasagaara.kelasagaara:decodeIntegrityToken |
|      Body: { "integrityToken": "<rawTokenString>" }                                              |
|   4. Google Play verifies token signature and cryptographic freshness.                           |
|   5. Returns JSON response containing tokenPayloadExternal.                                      |
|   6. PlayIntegrityVerifier runs 10 sequential security invariant checks.                         |
+--------------------------------------------------------------------------------------------------+
```

---

### 2. THE 10 SEQUENTIAL VERIFICATION INVARIANTS

Before any sensitive biometric operation is permitted to proceed, the `PlayIntegrityVerifier` enforces the following 10 verification gates in strict succession:

```
                                  [Incoming Request]
                                          |
                                          v
                         +---------------------------------+
                         | 1. Token Non-Empty Check        | --> Fail 400 MISSING_PLAY_INTEGRITY_TOKEN
                         +---------------------------------+
                                          |
                                          v
                         +---------------------------------+
                         | 2. Caller UID Context Match     | --> Fail 403 CROSS_USER_THEFT
                         +---------------------------------+
                                          |
                                          v
                         +---------------------------------+
                         | 3. Google API Token Decode      | --> Fail 403/503 INVALID_TOKEN / UNAVAILABLE
                         +---------------------------------+
                                          |
                                          v
                         +---------------------------------+
                         | 4. Package Name Invariant       | --> Fail 403 PACKAGE_NAME_MISMATCH
                         +---------------------------------+
                                          |
                                          v
                         +---------------------------------+
                         | 5. Canonical RequestHash Match  | --> Fail 403 REQUEST_HASH_MISMATCH
                         +---------------------------------+
                                          |
                                          v
                         +---------------------------------+
                         | 6. Freshness (Age <= 300s)      | --> Fail 401 INTEGRITY_TOKEN_EXPIRED
                         +---------------------------------+
                                          |
                                          v
                         +---------------------------------+
                         | 7. Clock Skew (Future <= 60s)   | --> Fail 403 TIMESTAMP_IN_FUTURE
                         +---------------------------------+
                                          |
                                          v
                         +---------------------------------+
                         | 8. Certificate Allowlist Check  | --> Fail 403 UNAPPROVED_SIGNING_CERTIFICATE
                         +---------------------------------+
                                          |
                                          v
                         +---------------------------------+
                         | 9. App Recognition Verdict      | --> Fail 403 APP_NOT_RECOGNIZED
                         +---------------------------------+
                                          |
                                          v
                         +---------------------------------+
                         | 10. Device Integrity Policy     | --> Fail 403 / STEP_UP / RESTRICTED
                         +---------------------------------+
                                          |
                                          v
                              [INTEGRITY_ACCEPTED (200)]
```

---

### 3. NEVER TRUST CLIENT VERDICTS

**Mandatory Security Rule:** The client application is **never** permitted to decode integrity tokens or send claims such as `{"deviceIntegrity": "PASS"}`. The backend communicates directly with `playintegrity.googleapis.com` and validates the cryptographically authenticated payload returned by Google's infrastructure.
