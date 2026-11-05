# KELASAGARA V20.3: KEY ATTESTATION ARCHITECTURE
## Hardware-Backed Key Attestation & Chain of Trust Specification

**Project:** Kelasagara Major Project  
**System:** Worker Marketplace & Multi-Factor Biometric Identity Platform  
**Document Code:** KS-SEC-P20.3-02  
**Classification:** Core Security Engineering Specification

---

## 1. PURPOSE & PRINCIPLES

Android Key Attestation is a security mechanism provided by modern Android hardware (API 24+) that allows a remote verifier (the Kelasagara backend) to determine with cryptographic certainty whether an asymmetric key pair:
1. Was generated inside secure hardware (Trusted Execution Environment or StrongBox KeyMint).
2. Cannot be exported from the secure enclave.
3. Is constrained to specific algorithms, digests, and purposes (ECDSA P-256, SHA-256, Sign).
4. Was generated in response to a specific server challenge (preventing replay of old or fabricated keys).
5. Belongs to the authentic Kelasagara Android package (`com.kelasagaara.kelasagaara`) signed by the verified release certificate.

### Client-Side Trust Invariant
The Flutter client application **never** decides whether its own key attestation is valid. The client's role is strictly limited to obtaining the certificate chain from Android Keystore and transmitting it to the server. Verification is conducted **exclusively** on the trusted backend.

---

## 2. ANDROID KEYSTORE IMPLEMENTATION (`DeviceKeyManager.kt`)

Key generation is handled by `DeviceKeyManager.kt` inside `com.kelasagaara.kelasagaara.security`:

```kotlin
val builder = KeyGenParameterSpec.Builder(
    alias,
    KeyProperties.PURPOSE_SIGN
).apply {
    setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
    setDigests(KeyProperties.DIGEST_SHA256)
    setAttestationChallenge(challenge)
    setUserAuthenticationRequired(false) // Transport key; biometric liveness verified via server SFace
}

// StrongBox evaluation (API 28+) with automatic TEE fallback
if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && useStrongBox) {
    builder.setIsStrongBoxBacked(true)
}
```

### StrongBox Evaluation Protocol
- On Android 9 (API 28) and higher, `DeviceKeyManager` first attempts key generation with `setIsStrongBoxBacked(true)` (dedicated tamper-resistant security chip with independent CPU, RAM, and flash).
- If `StrongBoxUnavailableException` is thrown, the manager logs a warning and retries with `setIsStrongBoxBacked(false)`, generating the key inside the SoC Trusted Execution Environment (TEE).
- This ensures maximum security on devices equipped with StrongBox (e.g. Google Pixel Titan M, Samsung Knox Vault) while maintaining complete operational compatibility on standard TEE hardware.

---

## 3. KEY ATTESTATION EXTENSION STRUCTURE (OID `1.3.6.1.4.1.11129.2.1.17`)

The leaf certificate of the attestation chain contains a custom X.509 extension with OID `1.3.6.1.4.1.11129.2.1.17`. The extension value is an ASN.1 OCTET STRING encapsulating a `KeyDescription` sequence:

```asn1
KeyDescription ::= SEQUENCE {
    attestationVersion         INTEGER,         -- Version of attestation format (e.g. 1..4, 100..300)
    attestationSecurityLevel   SecurityLevel,   -- 0: Software, 1: TEE, 2: StrongBox
    keymintVersion             INTEGER,         -- Version of Keymaster/KeyMint HAL
    keymintSecurityLevel       SecurityLevel,   -- Security level of the key storage
    attestationChallenge       OCTET STRING,    -- Exact challenge bytes passed during generation
    uniqueId                   OCTET STRING,    -- Device identifier (if requested/authorized)
    softwareEnforced           AuthorizationList, -- Claims enforced by Android OS
    hardwareEnforced           AuthorizationList  -- Claims enforced by TEE / StrongBox
}

SecurityLevel ::= ENUMERATED {
    Software                   (0),
    TrustedEnvironment         (1),
    StrongBox                  (2)
}
```

---

## 4. CHAIN OF TRUST ANCHORING

The certificate chain exported by Android Keystore comprises 3 or 4 X.509 certificates:
1. **Leaf Certificate:** Contains the newly generated public key and the `KeyDescription` extension.
2. **Intermediate Certificate(s):** Issued by Google to the device SoC manufacturer (e.g. Qualcomm, Samsung, MediaTek, Google Titan).
3. **Root Certificate:** The Google Hardware Attestation Root CA certificate.

In production environments, the backend verifies that the chain roots to Google's published Hardware Attestation Root CA certificates (SHA-256 fingerprints `e63283ca233f2d24...`, `aba4197e009d2550...`, or `4a242c75a40a8cf5...`).
