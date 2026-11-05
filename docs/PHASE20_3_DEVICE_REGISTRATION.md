# KELASAGARA V20.3: DEVICE REGISTRATION & IDENTITY BINDING
## Worker Device Ledger & Cryptographic Registration Specification

**Project:** Kelasagara Major Project  
**System:** Worker Marketplace & Multi-Factor Biometric Identity Platform  
**Document Code:** KS-SEC-P20.3-04  
**Classification:** Core Security Engineering Specification

---

## 1. OBJECTIVE & REGISTRATION PROTOCOL

The device registration protocol establishes a permanent, auditable cryptographic association between a verified Firebase worker account and their physical mobile device.

```
Worker Client (Flutter)                       Kelasagara Backend (Node.js)
       │                                                    │
       │ 1. POST /request-device-registration-challenge     │
       ├───────────────────────────────────────────────────>│
       │                                                    │ (Generates single-use
       │                                                    │  challengeNonce, TTL 5m)
       │ 2. Returns { challengeId, challengeNonce }         │
       │<───────────────────────────────────────────────────┤
       │                                                    │
(Native Android Keystore generates                          │
 ECDSA P-256 key pair with                                  │
 setAttestationChallenge(challengeNonce))                   │
       │                                                    │
       │ 3. POST /register-device                           │
       │    { challengeId, challengeNonce, certChain }      │
       ├───────────────────────────────────────────────────>│
       │                                                    │ (1. Consumes challenge)
       │                                                    │ (2. Verifies attestation)
       │                                                    │ (3. Checks device quota <= 2)
       │                                                    │ (4. Stores public key in
       │                                                    │     /biometric_devices)
       │ 4. Returns { deviceKeyId, attestationLevel }       │
       │<───────────────────────────────────────────────────┤
```

---

## 2. FIRESTORE SCHEMA: `/biometric_devices/{deviceKeyId}`

Device records are stored in a dedicated, isolated collection:

```json
{
  "deviceKeyId": "devkey_7a8b9c0d1e2f3a4b_99f8e7d6c5b4a321",
  "owningUid": "usr_ramesh_kamat_9845",
  "publicKeyPem": "-----BEGIN PUBLIC KEY-----\nMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE...",
  "keyAlgorithm": "ECDSA_P256",
  "keyVersion": 1,
  "attestationLevel": "DEVICE_KEY_STRONGBOX",
  "attestationStatus": "VERIFIED",
  "applicationPackage": "com.kelasagaara.kelasagaara",
  "applicationCertificateDigest": "a1b2c3d4e5f6...",
  "registeredAt": "2026-10-31T17:00:00.000Z",
  "lastAuthenticatedAt": "2026-10-31T17:25:00.000Z",
  "revokedAt": null,
  "revocationReason": null,
  "lifecycleStatus": "ACTIVE",
  "metadata": {
    "deviceModel": "Pixel 8 Pro",
    "osVersion": "Android 15 (API 35)",
    "chainLength": 3
  }
}
```

### Invariants Enforced by `DeviceRegistrationService`
1. **Never Store Private Keys:** Only the SPKI PEM-encoded public key is stored on the server.
2. **Opaque Identifier:** The `deviceKeyId` is derived from `devkey_${sha256(publicKey).substring(0,16)}_${randomBytes(8).hex}`, preventing any PII or hardware serial leakage.
3. **Active Device Quota:** Each worker account is limited to a maximum of 2 active devices (`MAX_ACTIVE_DEVICES_PER_WORKER = 2`). If a worker attempts to register a 3rd device, the registration is rejected with `MAX_ACTIVE_DEVICES_EXCEEDED` until an older device is explicitly revoked.
4. **Single-Use Challenge:** Challenges are consumed atomically within a database transaction. Replay attempts immediately return `CHALLENGE_REPLAYED`.
