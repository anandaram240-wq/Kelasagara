# KELASAGARA V20.10: PLAY INTEGRITY REQUEST BINDING
## Standard Play Integrity API Integration and Digest Parity

**System:** Kelasagara Major Project  
**Phase:** 20.10  
**Auditor:** Mobile Application Security Engineer  
**Date:** November 1, 2026

---

### 1. The Standard Integrity Request Binding Protocol

Kelasagara uses Google Play's Standard Integrity API to attest application authenticity and device integrity:
- **Cloud Project Number:** `993968093461L` (`kelasagara-f127a`).
- **Warmup Provider:** `StandardIntegrityTokenProvider` prepared at app startup.
- **Request Binding Field:** `requestHash`.

---

### 2. Computing the Standard `requestHash`

To cryptographically bind the biometric request payload to the Play Integrity token, the client and server compute:

$$\begin{aligned}
\text{BindingParams} &= \text{PlayIntegrityBindingParamsV2}( \\
&\quad \text{protocol} = \text{'PLAY\_INTEGRITY\_BINDING\_V2'}, \\
&\quad \text{pkg} = \text{'com.kelasagaara.kelasagaara'}, \\
&\quad \text{uid} = \text{authenticatedUid}, \\
&\quad \text{deviceKeyId} = \text{deviceKeyId}, \\
&\quad \text{challengeId} = \text{captureSessionId}, \\
&\quad \text{serverNonce} = \text{serverNonce}, \\
&\quad \text{payloadDigestSha256} = \text{SHA-256}(\text{CanonicalEnvelopeBytes}) \\
)
\end{aligned}$$

$$\text{requestHash} = \text{Base64Url}\Big(\text{SHA-256}\big(\text{serializeCanonicalBinding}(\text{BindingParams})\big)\Big)$$

---

### 3. Verification Steps on Backend

1. **Token Decryption:** Backend decodes the Play Integrity JWT token using Google Play Integrity API keys or GCP credentials.
2. **App Licensing & Package:** Confirms package name is `com.kelasagaara.kelasagaara` and app licensing is `LICENSED`.
3. **App Verdict:** Asserts `appRecognitionVerdict` is `PLAY_RECOGNIZED`.
4. **Device Verdict:** Asserts `deviceRecognitionVerdict` contains `MEETS_DEVICE_INTEGRITY`.
5. **Request Hash Parity:** Asserts the token's embedded `requestHash` strictly equals the server-recomputed `requestHash`.
6. **Freshness:** Asserts token timestamp is within a 3-minute permitted freshness window.
