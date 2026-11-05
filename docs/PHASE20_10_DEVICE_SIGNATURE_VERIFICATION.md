# KELASAGARA V20.10: DEVICE SIGNATURE VERIFICATION
## Android Keystore ECDSA P-256 Signing Semantics and Double-Hashing Avoidance

**System:** Kelasagara Major Project  
**Phase:** 20.10  
**Auditor:** Senior Android Security & Cryptography Engineer  
**Date:** November 1, 2026

---

### 1. Android Keystore Signing Semantics

In `DeviceKeyManager.kt`, the Android Keystore signing operation is configured as:
```kotlin
val signature = Signature.getInstance("SHA256withECDSA")
signature.initSign(privateKey)
signature.update(canonicalDataBytes)
val derSignature = signature.sign()
```

#### The Double-Hashing Trap
- `SHA256withECDSA` computes an internal SHA-256 hash over the supplied `data` before signing the resulting 32-byte digest with the ECDSA private key.
- If the application computes `digest = SHA-256(canonicalBytes)` and passes the 32-byte digest to `Signature.update(digest)`, the engine computes `SHA-256(SHA-256(canonicalBytes))` — a **double hash**!
- If the backend verifies against `crypto.verify('sha256', canonicalBytes, ...)`, verification fails because the backend only hashed once!

#### The V20.10 Standard
In Kelasagara V20.10, the client passes the **exact canonical binary bytes** directly into `DeviceKeyManager.signData(alias, canonicalBytes)`.
On the backend:
```typescript
const verified = crypto.verify('sha256', canonicalBytes, registeredPublicKeyPem, signatureBuffer);
```
Both sides hash the canonical bytes exactly once with SHA-256 before applying ECDSA math, eliminating double-hashing confusion entirely.

---

### 2. Supported Key Attributes

- **Key Algorithm:** `KeyProperties.KEY_ALGORITHM_EC` (Elliptic Curve).
- **Curve:** `secp256r1` (NIST P-256 / prime256v1).
- **Format:** ASN.1 DER-encoded sequence `(r, s)`.
- **Security Levels:** Backed by `KeyProperties.SECURITY_LEVEL_TRUSTED_ENVIRONMENT` (TEE) or `STRONGBOX`.
- **Attestation:** Key creation is bound to an initial attestation challenge signed by the Google Attestation Root.
