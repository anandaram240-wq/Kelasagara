# KELASAGARA V20.2: TRUSTED ANDROID APPLICATION INTEGRITY ENGINE
## PHASE 20.2 TECHNICAL REPORT 3: CANONICAL REQUEST-BINDING & ANTI-REPLAY PROTOCOL

**Author:** Principal Cryptography Engineer & Mobile Security Architect  
**Project:** Kelasagara Major Project  
**Phase:** 20.2 — Trusted Android Application Integrity Engine  
**TypeScript Service:** `backend/src/services/play_integrity_request_binding.ts`  
**Flutter Service:** `lib/services/play_integrity_request_binding.dart`  
**Protocol Identifier:** `PLAY_INTEGRITY_BINDING_V1`  
**Digest Specification:** SHA-256 binary digest encoded as Base64Url (RFC 4648 §5, unpadded)  
**Status:** Certified Cryptographic Specification  

---

### 1. PROTOCOL OBJECTIVE & THREAT MODEL

The central vulnerability of naive device attestation integrations is **token substitution and replay**:
- An attacker compromises an Android device (e.g. running an emulator or Frida instrumentation), obtains a valid integrity token for an innocent read-only action, and transplants that token into a sensitive biometric enrollment payload.
- Alternatively, a man-in-the-middle or malicious client replays an integrity token harvested from a previous session.

The Kelasagara **Canonical Request-Binding Protocol** prevents token substitution by cryptographically binding the integrity token to the specific transaction parameters via the Google Play Standard Integrity `requestHash` parameter.

```
+--------------------------------------------------------------------------------------------------+
|                               CANONICAL REQUEST-BINDING DATAFLOW                                 |
+--------------------------------------------------------------------------------------------------+
|                                                                                                  |
|   Transaction Parameters:                                                                        |
|   1. Protocol Version:       "PLAY_INTEGRITY_BINDING_V1"                                         |
|   2. Package Name:           "com.kelasagaara.kelasagaara"                                       |
|   3. Authenticated UID:      "usr_alice_12345" (from Firebase Auth)                              |
|   4. Challenge ID:           "chl_a9b8c7d6e5"                                                    |
|   5. Challenge Purpose:      "INITIAL_ENROLLMENT" | "AUTH_1TO1" | "RECOVERY_CLAIM"              |
|   6. Server Nonce SHA-256:   SHA-256 hex digest of 16-byte server nonce                          |
|   7. Idempotency Key:        "idem_tx_998877"                                                    |
|   8. HTTP Method:            "POST"                                                              |
|   9. API Route:              "/auth/biometrics/v10/enroll"                                       |
|  10. Payload SHA-256:        SHA-256 hex of Float32LE embedding buffer                          |
|                                         |                                                        |
|                                         v                                                        |
|   Length-Prefixed Binary Canonicalization:                                                       |
|   Bytes = Sum_i ( UInt32BE(len_i) || UTF8(field_i) )                                             |
|                                         |                                                        |
|                                         v                                                        |
|   requestHash = Base64UrlNoPadding( SHA256(Bytes) )                                              |
|                                         |                                                        |
|                                         v                                                        |
|   Google Play Integrity Token:                                                                   |
|   decodeIntegrityToken(token).requestDetails.requestHash == requestHash                          |
|   (Google server cryptographically certifies that the token was minted for THIS EXACT request)   |
+--------------------------------------------------------------------------------------------------+
```

---

### 2. CANONICAL BINARY FIELD SPECIFICATION

The canonical binding buffer is constructed by sequentially appending 10 fields, each prefixed by a 32-bit big-endian unsigned integer indicating its exact UTF-8 byte length:

$$\text{CanonicalBuffer} = \prod_{i=1}^{10} \Big( \text{UInt32BE}(\text{len}(F_i)) \,\|\, \text{UTF8}(F_i) \Big)$$

| Index | Field Identifier | Type / Constraints | Example Value | Description |
| :--- | :--- | :--- | :--- | :--- |
| **0** | `protocolVersion` | Literal string | `"PLAY_INTEGRITY_BINDING_V1"` | Protocol schema version |
| **1** | `packageName` | Standard Android ID | `"com.kelasagaara.kelasagaara"` | Target application package |
| **2** | `authenticatedUid` | Firebase UID | `"usr_alice_12345"` | Identity of the caller |
| **3** | `challengeId` | Server Ticket ID | `"chl_9876543210"` | Biometric challenge session |
| **4** | `challengePurpose` | Enum | `"INITIAL_ENROLLMENT"` | Protected operational purpose |
| **5** | `nonceHash` | 64-char Hex string | `SHA256(serverNonce)` | Cryptographic binding to server nonce |
| **6** | `idempotencyKey` | Unique UUID | `"idem_018f9c1d-2e3b"` | Transaction idempotency key |
| **7** | `httpMethod` | Uppercase string | `"POST"` | HTTP request method |
| **8** | `route` | Lowercase path | `"/auth/biometrics/v10/enroll"` | Target endpoint URI |
| **9** | `payloadDigest` | 64-char Hex string | `SHA256(vectorBuffer)` | Binary digest of face vector |

---

### 3. CROSS-PLATFORM PARITY (TYPESCRIPT & DART)

Cross-platform parity between Dart and TypeScript was verified mathematically:
1. **Integer Endianness:** Both implementations use 4-byte Big-Endian integers (`writeUInt32BE` in Node.js, `setUint32(..., Endian.big)` in Dart).
2. **String Encoding:** Both implementations encode strings strictly as UTF-8.
3. **Digest Serialization:** The output SHA-256 hash is encoded using URL-safe Base64 without trailing `=` padding characters (characters `+` $\rightarrow$ `-`, `/` $\rightarrow$ `_`, and stripped `=`):
   ```typescript
   hash.toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
   ```
4. **Length Restriction Compliance:** The resulting string is exactly 43 characters in length, well within Google Play's 500-character parameter limit for `requestHash`.

---

### 4. RELATIONSHIP WITH EXISTING SERVER CHALLENGE NONCE

The Play Integrity `requestHash` and Kelasagara's existing server challenge nonce serve distinct, complementary purposes:
1. **Server Nonce (16-byte CSPRNG):**
   - Issued by backend `/auth/biometrics/challenge/acquire`.
   - Has a strict 5-minute Time-To-Live (TTL).
   - Atomically consumed in a Firestore transaction (`singleUse == true`).
   - Guarantees server-side freshness and prevents replay against the database.
2. **Play Integrity `requestHash`:**
   - Cryptographically binds the client's device/app integrity verdict to that exact server nonce and payload.
   - Prevents an attacker from reusing an integrity token across different nonces or routes.

**Invariant:** The server nonce is **never** removed. The backend verifies the nonce in Firestore AND verifies that the integrity token's `requestHash` authenticates `SHA256(serverNonce)`.
