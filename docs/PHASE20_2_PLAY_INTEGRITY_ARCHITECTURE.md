# KELASAGARA V20.2: TRUSTED ANDROID APPLICATION INTEGRITY ENGINE
## PHASE 20.2 TECHNICAL REPORT 1: GOOGLE PLAY INTEGRITY ARCHITECTURE SPECIFICATION

**Author:** Principal Android Security Architect & Mobile Red-Team Engineer  
**Project:** Kelasagara Major Project  
**Phase:** 20.2 — Trusted Android Application Integrity Engine  
**Target Platform:** Android 14 / API 34+ (minSdk 24, compileSdk 36)  
**Package Identifier:** `com.kelasagaara.kelasagaara`  
**Signing Digest (SHA-256):** `a0425250004454e7fc63dba402351e439f975b0ff38f23cb2ca131edb037f7e5`  
**GCP Project Number:** `993968093461` (`kelasagara-f127a`)  
**Status:** Certified Architecture Specification  

---

### 1. MISSION & SCOPE OF PLAY INTEGRITY

The Google Play Integrity API protects sensitive Kelasagara operations by providing server-verifiable integrity verdicts regarding:
1. **Application Binary Integrity:** Verifies whether the running binary is the authentic, unmodified Kelasagara application signed by the approved developer certificate.
2. **Installation Authenticity:** Determines whether the application was installed by Google Play or recognized official distribution channels versus sideloaded or modified APKs.
3. **Device Health & Environment:** Detects rooted devices, unverified bootloaders, active emulators, aggressive hooking frameworks (e.g., Xposed, Frida), and known hostile environments.
4. **Transaction Binding:** Cryptographically binds an action-specific `requestHash` digest to the integrity token, preventing token replay and request payload tampering.

#### CRITICAL SECURITY BOUNDARIES:
- Play Integrity is **NOT** a biometric Presentation Attack Detection (PAD) tool.
- Play Integrity is **NOT** proof of human presence, liveliness, or biological identity.
- Play Integrity is **NOT** a replacement for server-side authorization, Firebase Auth, or AES-256-GCM biometric vault envelope encryption.
- Play Integrity provides an **additional, defense-in-depth security signal** guarding sensitive backend endpoints.

---

### 2. STANDARD INTEGRITY API vs CLASSIC INTEGRITY API

Kelasagara implements the modern **Google Play Standard Integrity API** rather than the legacy Classic API:

```
+----------------------------------------------------------------------------------------------------+
|                        STANDARD INTEGRITY API vs CLASSIC INTEGRITY API                             |
+----------------------------------------------------------------------------------------------------+
|  FEATURE                    |  STANDARD INTEGRITY API (V20.2)   |  CLASSIC INTEGRITY API (LEGACY)  |
+-----------------------------+-----------------------------------+----------------------------------+
|  Warmup Model               |  StandardIntegrityTokenProvider   |  No warmup                       |
|  Token Request Latency      |  Ultra-low (~10 - 50 ms)          |  High (~800 - 2,500 ms)          |
|  Network Behavior           |  Pre-warmed in background         |  Full network round-trip on call |
|  Transaction Binding        |  requestHash (SHA-256, base64url) |  nonce (raw byte array)          |
|  Decryption Method          |  Server decodeIntegrityToken      |  Server decodeIntegrityToken     |
|  Provider Lifecycle         |  Reusable per session / action    |  Single-shot                     |
|  Suitability for Face Auth  |  Ideal: zero capture latency lag  |  Poor: causes UI frame drops     |
+----------------------------------------------------------------------------------------------------+
```

---

### 3. COMPONENT INVENTORY & INTEGRATION ARCHITECTURE

```
+--------------------------------------------------------------------------------------------------+
|                              END-TO-END PLAY INTEGRITY DATAFLOW                                  |
+--------------------------------------------------------------------------------------------------+
|                                                                                                  |
|   [FLUTTER / DART LAYER]                                                                         |
|   1. App requests biometric challenge from backend (/auth/biometrics/challenge/acquire).        |
|   2. Receives challengeId + 16-byte server nonce.                                                |
|   3. Computes canonical request binding:                                                         |
|      requestHash = SHA256(canonicalPayload) -> Base64UrlSafe                                     |
|   4. Calls Platform Channel:                                                                     |
|      MethodChannel("kelasagara/play_integrity").invokeMethod("requestIntegrityToken", ...)       |
|                                         |                                                        |
|                                         v                                                        |
|   [ANDROID KOTLIN NATIVE LAYER]                                                                  |
|   5. PlayIntegrityBridge (Kotlin) invokes:                                                       |
|      tokenProvider.request(StandardIntegrityTokenRequest.builder()                               |
|        .setRequestHash(requestHash).build())                                                     |
|   6. Play Core communicates with Google Play Services on-device daemon.                          |
|   7. Obtains signed, encrypted integrity token from Google Play Services.                        |
|   8. Returns raw token string to Flutter via MethodChannel.                                      |
|                                         |                                                        |
|                                         v                                                        |
|   [BACKEND REST TRANSPORT]                                                                       |
|   9. Flutter sends HTTP POST with:                                                               |
|      Header: X-Play-Integrity-Token: <token> (or in body)                                        |
|      Body: { challengeId, nonce, requestHash, ...biometricPayload }                             |
|                                         |                                                        |
|                                         v                                                        |
|   [BACKEND VERIFICATION SERVICE]                                                                 |
|   10. Middleware requirePlayIntegrity intercepts request.                                        |
|   11. playIntegrityRequestBinding independently recomputes expected requestHash.                 |
|   12. playIntegrityGoogleClient calls Google Play Developer API:                                 |
|       playintegrity.v1.v1.decodeIntegrityToken(packageName, { integrityToken })                 |
|   13. Verifies:                                                                                  |
|       - requestPackageName == "com.kelasagaara.kelasagaara"                                      |
|       - requestHash == expectedRequestHash                                                       |
|       - timestampMillis freshness <= 5 minutes                                                   |
|       - certificateSha256Digest matches developer allowlist                                      |
|       - appRecognitionVerdict == "PLAY_RECOGNIZED"                                               |
|       - deviceRecognitionVerdict meets policy tier                                               |
|   14. playIntegrityPolicy evaluates verdict -> INTEGRITY_ACCEPTED                                |
|   15. Proceeds to biometric PAD, SFace inference, and V20.1 vault envelope encryption.          |
+--------------------------------------------------------------------------------------------------+
```

---

### 4. APPLICATION DISTRIBUTION CLASSIFICATION & VERDICT EXPECTATIONS

Because Kelasagara is currently distributed as an Android APK release artifact under physical demonstration and staging environments, the integrity policy must distinguish between distribution channels:

| Channel / Environment | Installation Mechanism | Expected App Integrity | Expected Device Integrity | Permitted Actions |
| :--- | :--- | :--- | :--- | :--- |
| **Google Play Production** | Google Play Store install | `PLAY_RECOGNIZED` | `MEETS_STRONG_INTEGRITY` / `MEETS_DEVICE_INTEGRITY` | Full biometric operations |
| **Google Play Closed Test** | Internal / Closed Testing track | `PLAY_RECOGNIZED` | `MEETS_DEVICE_INTEGRITY` / `MEETS_BASIC_INTEGRITY` | Full biometric operations |
| **Sideloaded Release APK** | Direct APK / ADB install | `UNRECOGNIZED_VERSION` | `MEETS_DEVICE_INTEGRITY` / `MEETS_BASIC_INTEGRITY` | Step-up / Staging allowed; Prod requires Play install |
| **Emulated / Rooted Device** | ADB on rooted device / Emulator | Any | `[]` (Empty / `UNKNOWN`) | **INTEGRITY_REJECTED** |

---

### 5. SECURITY RULES & ARCHITECTURAL INVARIANTS

1. **Zero Client Trust:** The backend never trusts client assertions regarding integrity. It always decodes and authenticates the token directly with Google.
2. **Request Binding Integrity:** The `requestHash` is verified on the backend against an independently computed canonical digest. Any modification to the payload, route, user ID, or server challenge invalidates the token.
3. **No Credential Exposure:** Service account credentials for the Google Play Developer API are stored strictly on the backend. No GCP JSON secrets exist in the Android APK or Flutter assets.
4. **Fail-Closed on Unavailability:** If Google Play Integrity decoding fails or times out, the backend fails closed (HTTP 503 `INTEGRITY_UNAVAILABLE`).
5. **No Universal Bypass:** No environment variable such as `REQUIRE_PLAY_INTEGRITY=false` is permitted to disable integrity checks in production.
