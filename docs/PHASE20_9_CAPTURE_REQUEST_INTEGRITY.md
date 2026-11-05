# KELASAGARA V20.9: CAPTURE REQUEST INTEGRITY
## Cryptographic Payload Digest and Play Integrity Binding Parity

**Document Ref:** `docs/PHASE20_9_CAPTURE_REQUEST_INTEGRITY.md`  
**Phase:** 20.9  
**Auditor:** Principal Cryptography & Application Security Engineer  
**Date:** November 1, 2026

---

### 1. Cryptographic Binding Objective

To prevent proxy interception, synthetic image injection, and man-in-the-middle payload modification, the Kelasagara client binds the raw camera image bytes directly into:
1. The **Google Play Integrity** `requestHash` field (`PLAY_INTEGRITY_BINDING_V2`).
2. The **Android Keystore** hardware-backed ECDSA request signature (`DeviceRequestSignature`).

---

### 2. Canonical Digest Specification

The binding digest is computed deterministically across Android Kotlin client and Node.js TypeScript backend:

$$\text{Digest} = \text{SHA-256}\Big(\text{RawPayloadBytes} \;\big\|\; \text{UTF8}(\text{sessionNonce}) \;\big\|\; \text{BigEndianInt64}(\text{clientTimestampNs})\Big)$$

Where:
- `RawPayloadBytes`: The exact canonical I420 frame bytes or JPEG transport payload.
- `sessionNonce`: Server-issued cryptographically random 128-bit hex ticket (`KS_NONCE_...`).
- `clientTimestampNs`: 64-bit nanosecond hardware monotonic capture timestamp.

---

### 3. Adversarial Test Results

In `backend/src/tests/phase20_9_capture_pipeline.test.ts` Suite 5:
- **Test 5.1 (Determinism):** Kotlin-compatible digest calculation yields identical 64-character hex string on identical inputs.
- **Test 5.2 (1-bit Avalanche Effect):** Modifying a single bit in the 8-byte payload completely changes the resulting hash:
  - Original: `e62a5b...`
  - Flipped bit: `2d4c91...` (Zero correlation, passes cryptographic avalanche criterion).
- **Test 5.3 (Nonce Modification):** Tampering with the session nonce immediately invalidates the digest, failing the Play Integrity verification gate.
