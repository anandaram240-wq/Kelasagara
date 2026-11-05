# Kelasagara Real-Time Private Messaging Security Architecture
**Document Version:** 1.0.0 (Hardened)  
**Security Classification:** High Security / Cryptographic Specification

---

## 1. Executive Summary & Terminology
This document specifies the applied cryptographic architecture of the Kelasagara Private Messaging Subsystem. The implementation utilizes a **Signal-protocol-inspired asynchronous Double Ratchet architecture**, employing vetted cryptographic standards:
- **X25519** (RFC 7748) for Diffie-Hellman Key Agreement.
- **HKDF-SHA256** (RFC 5869) for Hash-based Key Derivation.
- **ChaCha20-Poly1305** (RFC 8439) for Authenticated Encryption with Associated Data (AEAD).

*Note: Per strict project guidelines, this protocol is accurately designated as "Signal-protocol-inspired end-to-end encrypted messaging" utilizing vetted cryptographic primitives.*

---

## 2. Threat Model (Phases 120-121)

| Threat | Description | Status | Mitigation Mechanism |
|---|---|---|---|
| **Malicious Firebase Admin** | Compromised backend or rogue admin inspecting Firestore | **Mitigated** | Server is blind. Stores only base64 ciphertext and AEAD authentication tags. No plaintext or private keys exist on Firestore. |
| **Database Read Leak** | Attacker downloads Firestore database dump | **Mitigated** | Without the peer device's private identity and ratchet state keys, all message content is mathematically indistinguishable from random bytes. |
| **Network Interception (MITM)** | Attacker intercepts TLS or Wi-Fi packets | **Mitigated** | Application-layer AEAD encryption sits on top of TLS. TLS termination reveals zero message content. |
| **Plaintext FCM Interception** | Attacker intercepts push notifications | **Mitigated** | Push notifications contain only a generic encrypted ping/wakeup. Message bodies are NEVER delivered in FCM payloads. |
| **Message Tampering** | Attacker alters ciphertext, sender ID, or IV in Firestore | **Mitigated** | Poly1305 AEAD MAC authenticates both ciphertext and Associated Data (`conversationId + clientMessageId + senderDeviceId + sequenceNum`). Tampered messages trigger authentication failure and are dropped. |
| **Message Replay** | Attacker copies and re-inserts a valid message envelope | **Mitigated** | Deterministic `clientMessageId` doc IDs prevent document duplication; Double Ratchet sequence numbers prevent ratchet state replay. |
| **Out-of-Order Delivery** | Network drops or reorders packets | **Mitigated** | Skipped message keys are derived and cached up to a finite window ($M=50$) allowing decrypting delayed messages without compromising prior forward secrecy. |
| **Forward Secrecy Loss** | Attacker compromises device at time $T$ | **Mitigated** | Sending and receiving chains ratchet forward on every message. Prior message keys are destroyed immediately upon use. Compromise at $T$ does not compromise messages prior to $T$. |
| **Device Compromise (Current/Future)** | Physical extraction of active keys from device | **Accepted Residual Risk** | Handled via device Keystore/secure local storage. Forward secrecy protects past messages; future messages compromised until session renegotiation. |

---

## 3. Cryptographic State Machine

### 3.1 Device Identity & Prekey Bundle
Each device generates:
1. **Identity Keypair ($IK$):** Long-term X25519 keypair.
2. **Signed Prekey ($SPK$):** Medium-term X25519 keypair signed by $IK$.
3. **One-Time Prekeys ($OPK_1 \dots OPK_N$):** Ephemeral X25519 keypairs.

Public keys are published to Firestore collection `user_keys/{uid}/devices/{deviceId}`:
```json
{
  "deviceId": "dev_a1b2c3d4",
  "identityKey": "base64(IK_public)",
  "signedPrekey": "base64(SPK_public)",
  "oneTimePrekeys": ["base64(OPK_1_public)", "base64(OPK_2_public)"],
  "updatedAt": "2026-10-03T08:00:00Z"
}
```

### 3.2 Asynchronous Session Establishment (X3DH-Inspired)
When Alice initiates a session with Bob:
1. Alice fetches Bob's public key bundle from `user_keys/{bobUid}/devices/{bobDeviceId}`.
2. Alice generates an ephemeral keypair $EK_A$.
3. Alice computes Diffie-Hellman outputs:
   - $DH_1 = \text{ECDH}(IK_A, SPK_B)$
   - $DH_2 = \text{ECDH}(EK_A, IK_B)$
   - $DH_3 = \text{ECDH}(EK_A, SPK_B)$
   - Optional: $DH_4 = \text{ECDH}(EK_A, OPK_B)$
4. Alice computes Master Key via HKDF-SHA256:
   $$SK = \text{HKDF}(DH_1 \parallel DH_2 \parallel DH_3 \parallel DH_4)$$
5. This $SK$ initializes the **Double Ratchet** Root Chain.

### 3.3 The Double Ratchet Algorithm
The session maintains three cryptographic chains:
1. **Root Chain:** Advanced whenever a new Diffie-Hellman ratchet public key is exchanged between Alice and Bob.
2. **Sending Chain:** Symmetric KDF ratchet advanced for each outgoing message. Outputs a unique, single-use 32-byte Message Encryption Key ($MK$).
3. **Receiving Chain:** Symmetric KDF ratchet advanced for each incoming message. Derives matching $MK$.

$$\text{ChainKey}_{i+1}, MK_i = \text{HMAC-SHA256}(\text{ChainKey}_i, \text{"MessageKey"})$$

### 3.4 Message Encryption & Authentication (AEAD)
For message payload $P$:
1. $MK$ is derived from the sending chain.
2. A unique 12-byte nonce $N$ is generated from secure random bytes.
3. Associated Data ($AAD$) is constructed:
   $$AAD = \text{utf8}(\text{convId} + ":" + \text{clientMessageId} + ":" + \text{senderDeviceId} + ":" + \text{seq})$$
4. Payload is encrypted with **ChaCha20-Poly1305**:
   $$C, T = \text{ChaCha20-Poly1305-Encrypt}(MK, N, P, AAD)$$
5. $MK$ is immediately zeroed in memory.

---

## 4. Fail-Closed Guarantees & Privacy Safeguards
1. **Zero Plaintext Fallback:** If a session cannot be established or decryption fails, the system NEVER falls back to unencrypted transmission. An explicit, user-friendly error state (`[Decryption Error: Session Desynchronized]`) is shown.
2. **Key Storage:** Device private keys and ratchet state are persisted locally using private, sandboxed app storage.
3. **Zero Secrets in Logs:** All logging masks message contents, nonces, and cryptographic keys. Only `clientMessageId`, sequence numbers, and status transitions are logged.
