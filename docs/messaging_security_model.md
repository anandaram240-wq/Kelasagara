# Kelasagara Messaging Security Architecture & Cryptographic Specification

## 1. Executive Summary

This document defines the cryptographic architecture, threat model, key lifecycle, and protocol mechanics for end-to-end encrypted (E2EE) messaging in the Kelasagara platform.

The system implements a client-side cryptographic protocol inspired by the Signal Protocol specifications (X3DH and Double Ratchet), executed entirely on endpoint devices using audited cryptographic primitives from `package:cryptography` (Apache-2.0). Cloud Firestore functions exclusively as a blind message transport and storage layer for ciphertext envelopes and delivery metadata; it never has access to plaintext message bodies or private cryptographic keys.

---

## 2. Cryptographic Primitives & Specifications

| Primitive Role | Algorithm / Standard | Implementation |
| :--- | :--- | :--- |
| **Identity & DH Key Agreement** | Curve25519 / RFC 7748 (X25519) | `cryptography.X25519()` |
| **Symmetric Ratchet KDF** | HMAC-SHA256 / RFC 2104 | `cryptography.Hmac.sha256()` |
| **Root Chain KDF** | HKDF-SHA256 / RFC 5869 | `cryptography.Hkdf(hmac: Hmac.sha256())` |
| **Authenticated Encryption** | ChaCha20-Poly1305 AEAD / RFC 8439 | `cryptography.Chacha20.poly1305Aead()` |
| **Associated Data (AAD)** | Cryptographic Binding | `"$convId:$clientMessageId:$senderDeviceId:$seq"` |
| **Safety Number Generation** | SHA-256 Digest / RFC 6234 | `crypto.sha256` formatted as 12 blocks of 5 digits |

---

## 3. Key Lifecycle & Provisioning

### 3.1 Device Identity Generation
Upon device onboarding, `DeviceIdentity.generate()` creates:
1. **Long-Term Identity KeyPair ($IK$):** Curve25519 private/public keypair representing the device identity.
2. **Signed Prekey Pair ($SPK$):** Medium-term Curve25519 prekey pair.
3. **One-Time Prekeys ($OPK_1 \dots OPK_{10}$):** Pool of 10 single-use Curve25519 prekey pairs.

### 3.2 Public Key Bundle Publishing
The client publishes strictly the public portions to Firestore:
- **Path:** `/user_keys/{userId}/devices/{deviceId}`
- **Payload:**
  - `deviceId`: Hardware installation token
  - `identityPublicKey`: Base64-encoded $IK_{pub}$
  - `signedPrekeyPublic`: Base64-encoded $SPK_{pub}$
  - `oneTimePrekeys`: List of `{ "keyId": "opk_i", "publicKey": "..." }`
  - `publishedAt`: ISO 8601 timestamp

**Critical Rule:** Private keys ($IK_{priv}, SPK_{priv}, OPK_{priv}$) **never leave the client device**.

---

## 4. Asynchronous Session Establishment (X3DH)

When Alice initiates a session with Bob:
1. Alice retrieves Bob's public key bundle from Firestore `/user_keys/{bobUid}/devices/{bobDeviceId}`.
2. Alice generates an ephemeral keypair ($EK_A$).
3. Alice computes three Diffie-Hellman operations:
   - $DH_1 = \text{X25519}(IK_A^{priv}, SPK_B^{pub})$
   - $DH_2 = \text{X25519}(EK_A^{priv}, IK_B^{pub})$
   - $DH_3 = \text{X25519}(EK_A^{priv}, SPK_B^{pub})$
4. Alice computes the Master Shared Secret via HKDF:
   $$\text{MasterSecret} = \text{HKDF-SHA256}(DH_1 \parallel DH_2 \parallel DH_3, \text{info} = \text{"Kelasagara-X3DH-MasterSecret-v1"})$$
5. Alice initializes her `DoubleRatchetSession` as initiator, attaching `$IK_A^{pub}$` and `$EK_A^{pub}$` as cleartext headers to the first ciphertext envelope.
6. When Bob receives Alice's initial message, Bob performs symmetric DH operations using his local private keys ($SPK_B^{priv}, IK_B^{priv}$), derives the identical `MasterSecret`, and initializes his receiver ratchet.

---

## 5. Double Ratchet Protocol Mechanics

### 5.1 DH Ratchet & Symmetric Chains
- **Root Chain:** Advanced upon receipt of a new remote DH public key. Generates a new Root Key ($RK$) and Chain Key ($CK$) via HKDF-SHA256.
- **Sending Chain:** Ratchets on every outbound message via HMAC-SHA256:
  $$CK_{i+1} = \text{HMAC}(CK_i, \text{0x01})$$
  $$MK_i = \text{HMAC}(CK_i, \text{0x02})$$
  $MK_i$ is used once to encrypt the message body and immediately deleted.
- **Receiving Chain:** Ratchets identically upon receiving inbound messages.

### 5.2 Out-of-Order Delivery & Skipped Keys
If message $N+k$ arrives before message $N$, intermediate message keys are derived and cached in `skippedMessageKeys` (limited to 50 entries). When skipped messages arrive later, they are decrypted using the stored key, which is instantly erased.

---

## 6. Server Blindness & Transport Isolation

### 6.1 Firestore Document Contract
All messages are committed to `/conversations/{convId}/messages/{clientMessageId}`:
- **Ciphertext Only:**
  ```json
  {
    "clientMessageId": "msg_1728000000_123456",
    "conversationId": "conv_alice_bob",
    "senderId": "alice_uid",
    "senderDeviceId": "dev_12345",
    "recipientId": "bob_uid",
    "type": "text",
    "version": 1,
    "envelope": {
      "ciphertext": "<base64>",
      "nonce": "<base64>",
      "mac": "<base64>",
      "ephemeralPublicKey": "<base64>",
      "sequenceNumber": 0,
      "previousChainLength": 0
    },
    "sentAt": "SERVER_TIMESTAMP",
    "status": "sent",
    "seenBy": ["alice_uid"]
  }
  ```
- **Plaintext Forbidden:** Firestore security rules reject any creation request containing `'text'` or `'plaintext'`.

---

## 7. Delivery Semantics & State Machine

```
      +-------------+
      |  COMPOSING  |
      +-------------+
             | Tap Send
             v
      +-------------+
      |   QUEUED    |  (Optimistic local bubble in UI, <10ms)
      +-------------+
             | Key Check
     +-------+-------+
     |               |
     v (Missing Key) v (Key Available)
+--------------+  +-------------+
| WAITING_KEY  |  | ENCRYPTING  |
+--------------+  +-------------+
     | Retry (15s)   |
     +---------------+
             |
             v
      +-------------+
      |    SENT     |  (Single Tick ✓: Ciphertext committed to Firestore)
      +-------------+
             | Recipient snapshot listener decrypts
             v
      +-------------+
      |  DELIVERED  |  (Double Tick ✓✓: Receipt committed to Firestore)
      +-------------+
             | Recipient opens conversation viewport
             v
      +-------------+
      |    READ     |  (Blue Ticks ✓✓: readAt committed to Firestore)
      +-------------+
```

---

## 8. Threat Model & Security Properties

1. **Compromised Server:** An attacker with root access to Cloud Firestore sees only ciphertext envelopes, message IDs, timestamps, and participant IDs. Plaintext content and private keys remain uncompromised.
2. **Forward Secrecy:** Compromise of current keys does not compromise past messages (ratchet forward secrecy).
3. **Break-In Recovery:** Compromise of an active session state is healed as soon as an uncompromised DH exchange occurs.
4. **Replay & Injection Attacks:** Bound by AEAD Associated Authenticated Data (AAD) tying conversation ID, client message ID, device ID, and monotonic sequence counter to Poly1305 MAC verification.
