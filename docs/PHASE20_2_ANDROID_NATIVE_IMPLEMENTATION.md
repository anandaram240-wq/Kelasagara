# KELASAGARA V20.2: TRUSTED ANDROID APPLICATION INTEGRITY ENGINE
## PHASE 20.2 TECHNICAL REPORT 2: ANDROID NATIVE PLAY INTEGRITY IMPLEMENTATION

**Author:** Senior Kotlin Engineer & Android Security Architect  
**Project:** Kelasagara Major Project  
**Phase:** 20.2 — Trusted Android Application Integrity Engine  
**Native Source:** `android/app/src/main/kotlin/com/kelasagaara/kelasagaara/PlayIntegrityBridge.kt`  
**Flutter Channel:** `kelasagara/play_integrity`  
**API Specification:** Google Play Standard Integrity API (`com.google.android.play:integrity:1.4.0`)  
**Status:** Certified Native Implementation  

---

### 1. NATIVE LIFECYCLE & ASYNCHRONOUS WARMUP

The Standard Play Integrity API replaces legacy per-request token generation with a two-phase architecture:
1. **Asynchronous Warmup (`prepareIntegrityProvider`):** Pre-establishes a secure channel with the on-device Google Play Services daemon during non-critical application phases (e.g. app startup or screen navigation).
2. **Action-Bound Token Acquisition (`requestIntegrityToken`):** Rapidly requests an integrity verdict token bound to the action's `requestHash` ($< 50\text{ ms}$).

```
+--------------------------------------------------------------------------------------------------+
|                            STANDARD INTEGRITY NATIVE LIFECYCLE                                   |
+--------------------------------------------------------------------------------------------------+
|                                                                                                  |
|   App Launch / Idle:                                                                             |
|   Flutter -> prepareIntegrityProvider(cloudProjectNumber: 993968093461)                          |
|         |                                                                                        |
|         v                                                                                        |
|   StandardIntegrityManager.prepareIntegrityToken(request)                                        |
|         |                                                                                        |
|         +--> OnSuccess: Caches StandardIntegrityTokenProvider (isPreparing = false)              |
|         +--> OnFailure: Maps StandardIntegrityErrorCode -> Returns safe structured error code     |
|                                                                                                  |
|   Biometric Transaction Triggered (Enrollment / 1:1 Login):                                      |
|   Flutter -> requestIntegrityToken(requestHash: "sha256-digest-base64url")                       |
|         |                                                                                        |
|         v                                                                                        |
|   tokenProvider.request(StandardIntegrityTokenRequest(requestHash))                              |
|         |                                                                                        |
|         +--> OnSuccess: Returns raw token string to Flutter                                      |
|         +--> OnFailure: If INTEGRITY_TOKEN_PROVIDER_INVALID -> Auto-renews provider and retries  |
|                         Else -> Maps error and returns safe error to Flutter                     |
+--------------------------------------------------------------------------------------------------+
```

---

### 2. PLATFORM CHANNEL SPECIFICATION

Channel Identifier: `kelasagara/play_integrity`

#### 2.1 Supported Operations

| Operation Name | Inbound Arguments | Return Type | Description |
| :--- | :--- | :--- | :--- |
| `prepareIntegrityProvider` | `{ cloudProjectNumber?: number }` | `bool (true)` | Warms up provider asynchronously in background without blocking UI thread. |
| `requestIntegrityToken` | `{ requestHash: string }` | `string` | Requests standard integrity token bound to the provided SHA-256 base64url digest. |
| `refreshIntegrityProvider` | `{ cloudProjectNumber?: number }` | `bool (true)` | Invalidates existing provider and forces a fresh warmup cycle. |
| `disposeIntegrityProvider` | None | `bool (true)` | Releases references and cleans up native resources. |

---

### 3. STRUCTURED NATIVE ERROR MAPPING

To prevent exposing internal Google exception traces, Google Cloud credentials, or stack traces to application callers, the native bridge maps all exceptions into 8 strict, typed categories:

```kotlin
val code = when (exception.errorCode) {
    StandardIntegrityErrorCode.PLAY_SERVICES_NOT_FOUND,
    StandardIntegrityErrorCode.PLAY_SERVICES_VERSION_OUTDATED -> "PLAY_SERVICES_UNAVAILABLE"
    StandardIntegrityErrorCode.PLAY_STORE_NOT_FOUND,
    StandardIntegrityErrorCode.PLAY_STORE_ACCOUNT_NOT_FOUND -> "PLAY_STORE_UNAVAILABLE"
    StandardIntegrityErrorCode.NETWORK_ERROR -> "NETWORK_UNAVAILABLE"
    StandardIntegrityErrorCode.INTEGRITY_TOKEN_PROVIDER_INVALID -> "PROVIDER_EXPIRED"
    StandardIntegrityErrorCode.CLIENT_TRANSIENT_ERROR -> "INTEGRITY_REQUEST_FAILED"
    StandardIntegrityErrorCode.APP_NOT_INSTALLED -> "UNSUPPORTED_DEVICE"
    StandardIntegrityErrorCode.INTERNAL_ERROR -> "INTERNAL_NATIVE_ERROR"
    else -> "INTEGRITY_REQUEST_FAILED"
}
```

---

### 4. MEMORY & THREAD SAFETY GUARANTEES

1. **Thread-Safe Synchronization:** Provider caching and state transitions (`isPreparing`, `tokenProvider`) are guarded by `@Synchronized` blocks and `@Volatile` modifiers to prevent race conditions during rapid concurrent requests.
2. **Zero In-Memory Token Caching:** The native bridge **never caches integrity tokens**. Tokens are strictly single-use and generated per-action; only the `StandardIntegrityTokenProvider` object is maintained across requests.
3. **Automatic Provider Expiry Recovery:** If a token request fails due to `INTEGRITY_TOKEN_PROVIDER_INVALID` (which occurs when the provider's underlying session expires), the bridge automatically invalidates the stale provider, prepares a fresh provider, and retries the token request once before reporting failure.
