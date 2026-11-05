# KELASAGARA V20.3: DEVICE-BOUND TRUST ARCHITECTURE
## Principal Biometric Security & Cryptography Engineering Specification

**Project:** Kelasagara Major Project  
**System:** Worker Marketplace & Multi-Factor Biometric Identity Platform  
**Phase:** 20.3 (Device-Bound Trust & Authentication Engine)  
**Baseline Commit:** `f09cfc5d02cc933ef751dfc6983573b9e45966bb` (Phase 20.2)  
**Protected Release Tag:** `v19.2.3-release` (`f210f95`)  
**Protected Release APK SHA-256:** `739f85746df3cd1fb6c315590147907918a3829976d0381b8eae358c743176ce`  
**Branch:** `security/phase20.3-device-bound-trust`

---

## 1. EXECUTIVE SUMMARY & SYSTEM THREAT MODEL

In legacy biometric deployments, sensitive operations (such as enrollment, 1:1 facial verification, and account re-enrollment) often rely solely on a bearer token (such as a Firebase ID token) transmitted over TLS. This architecture creates a critical security vulnerability: if a user's session token is intercepted, stolen via malware, or extracted from a rooted/compromised mobile device, an adversary can submit synthetic or replay biometric vectors directly to the backend API without physical access to the genuine registered hardware.

Furthermore, application-integrity attestations (such as Google Play Standard Integrity API, implemented in Phase 20.2) establish that the client application is authentic and running in an acceptable environment, but they do **not** bind the request to a specific registered mobile device belonging to a verified human worker.

**Kelasagara V20.3 eliminates this vulnerability by establishing three independent, mutually reinforcing assurances:**

```
   ┌─────────────────────────────────────────────────────────────────────────┐
   │                  KELASAGARA 3-FACTOR TRUST ENGINE                       │
   └─────────────────────────────────────────────────────────────────────────┘
                                       │
        ┌──────────────────────────────┼──────────────────────────────┐
        │                              │                              │
        ▼                              ▼                              ▼
 ┌──────────────┐              ┌──────────────┐              ┌──────────────┐
 │  FACTOR 1:   │              │  FACTOR 2:   │              │  FACTOR 3:   │
 │ APP & DEVICE │              │ DEVICE-BOUND │              │ SERVER-SIDE  │
 │  INTEGRITY   │              │ CRYPTOGRAPHY │              │  BIOMETRICS  │
 ├──────────────┤              ├──────────────┤              ├──────────────┤
 │ Google Play  │              │ Android      │              │ YuNet Face   │
 │ Standard     │              │ Keystore     │              │ Detection +  │
 │ Integrity    │              │ ECDSA P-256  │              │ SFace 128-D  │
 │ Verdict:     │              │ Hardware Key │              │ ONNX + V20.1 │
 │ MEETS_BASIC/ │              │ Attestation  │              │ AES-256-GCM  │
 │ STRONG       │              │ + Signature  │              │ Vault        │
 └──────────────┘              └──────────────┘              └──────────────┘
        │                              │                              │
        └──────────────────────────────┼──────────────────────────────┘
                                       │
                                       ▼
                     ┌───────────────────────────────────┐
                     │   AUTHORITATIVE DECISION GATE:    │
                     │  All 3 independent factor checks  │
                     │  must pass. No factor alone can   │
                     │    grant access or prove identity │
                     └───────────────────────────────────┘
```

### Invariant Principles
1. **No Factor Alone Authorizes Access:**
   - A valid Firebase Auth session alone **cannot** execute biometric operations.
   - A valid Play Integrity verdict alone **cannot** authorize account access.
   - A valid device signature alone **cannot** establish human identity.
2. **Private Key Non-Exportability:**
   - Private keys are generated inside the Android Keystore (backed by StrongBox Keymaster/KeyMint or hardware TEE).
   - Private keys never leave the secure hardware enclave and cannot be exported, backed up, or cloned.
3. **Cryptographic Challenge-Response Nonce Binding:**
   - Every transaction requires a single-use server-issued challenge bound to the caller's Firebase UID, device key identifier, canonical route, and operation purpose.
4. **Zero Client-Side Vector Trust:**
   - Client applications **never** generate, submit, or possess authoritative face embeddings.
   - Biometric embeddings are extracted exclusively on the trusted Node.js backend using the verified OpenCV SFace model.

---

## 2. CRYPTOGRAPHIC PRIMITIVES & SPECIFICATIONS

| Component | Standard / Specification | Security Properties |
| :--- | :--- | :--- |
| **Asymmetric Algorithm** | ECDSA over NIST P-256 (`secp256r1`) | 128-bit security level, hardware-accelerated |
| **Digest Algorithm** | SHA-256 (`FIPS 180-4`) | Collision and pre-image resistant |
| **Keystore Provider** | `AndroidKeyStore` | Hardware backing (StrongBox / TEE) |
| **Key Attestation** | Android Key Attestation (Extension OID `1.3.6.1.4.1.11129.2.1.17`) | Chain of trust anchored to Google Hardware Attestation Root CA |
| **Signature Format** | ASN.1 DER-encoded `r` and `s` integers | Standard RFC 3279, cross-compatible with OpenSSL & Node.js `crypto.verify` |
| **Transaction Serialization** | Length-prefixed canonical binary (`PLAY_INTEGRITY_BINDING_V2`) | Delimiter-collision immune, 100% deterministic cross-platform (TypeScript & Dart) |
| **Symmetric Vault Storage** | AES-256-GCM with Cloud KMS Envelope Encryption | Authenticated encryption with 8-field binary canonical AAD (Phase 20.1) |

---

## 3. ARCHITECTURAL DATA FLOW

1. **Worker Device Provisioning (One-Time per Device):**
   - Flutter app requests device registration challenge from `/api/biometrics/v10/request-device-registration-challenge`.
   - Native Kotlin `DeviceKeyManager` generates ECDSA P-256 key pair in `AndroidKeyStore` with `setAttestationChallenge(serverNonce)`. StrongBox is evaluated with automatic TEE fallback.
   - App transmits Base64 certificate chain to `/api/biometrics/v10/register-device`.
   - Backend `DeviceKeyAttestationVerifier` verifies the X.509 chain, validates the challenge, verifies Google Root CA anchor, and records the active device in Firestore `/biometric_devices/{deviceKeyId}`.
2. **Sensitive Biometric Transaction Execution:**
   - App requests a transaction challenge from `/api/biometrics/v10/request-device-challenge`.
   - Camera captures raw face image. App calculates `SHA256(rawImageBytes)`.
   - App serializes canonical `PLAY_INTEGRITY_BINDING_V2` binary structure and signs with Keystore private key.
   - App obtains Standard Play Integrity token with `requestHash = Base64Url(SHA256(canonicalBytes))`.
   - App transmits payload to backend `/api/biometrics/v10/enroll` or `/verify-1to1`.
   - Backend middleware enforces:
     a. `authenticateFirebaseToken`: Validates Firebase ID token.
     b. `requirePlayIntegrity`: Decodes token via Google Play Integrity API, verifies app certificate & device verdict.
     c. `requireDeviceSignature`: Verifies transaction challenge, checks device ownership & lifecycle status, and validates ECDSA signature.
     d. Backend OpenCV SFace ONNX engine executes facial feature extraction & matching.
     e. Template encrypted via AES-256-GCM and stored in Firestore biometric vault.
