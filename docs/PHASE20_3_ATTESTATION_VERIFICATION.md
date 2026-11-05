# KELASAGARA V20.3: ATTESTATION VERIFICATION
## Server-Side Verification Protocol & ASN.1 Parsing Engine

**Project:** Kelasagara Major Project  
**System:** Worker Marketplace & Multi-Factor Biometric Identity Platform  
**Document Code:** KS-SEC-P20.3-03  
**Classification:** Core Security Engineering Specification

---

## 1. SERVER-SIDE VERIFICATION WORKFLOW

The backend `DeviceKeyAttestationVerifier` (`backend/src/services/device_key_attestation.ts`) executes a rigorous 8-stage verification pipeline upon receiving an attestation chain:

```
[Incoming Chain (Base64 X.509 DER)]
               │
               ▼
   [Stage 1: Chain Integrity & Format Validation]
   - Parse all certificates into crypto.X509Certificate
   - Verify chain length >= 1
               │
               ▼
   [Stage 2: Key Algorithm & Curve Verification]
   - Verify leaf certificate public key is EC (asymmetricKeyType === 'ec')
   - Export public key as SPKI PEM
               │
               ▼
   [Stage 3: Validity Period Audit]
   - For all certs: verify validFrom <= Date.now() <= validTo
               │
               ▼
   [Stage 4: Cryptographic Signature Chain Audit]
   - For i in 0..n-2: cert[i].verify(cert[i+1].publicKey) === true
               │
               ▼
   [Stage 5: Root CA Anchor Verification]
   - Verify root certificate signature (self-signed)
   - In PRODUCTION: verify root fingerprint in KNOWN_GOOGLE_ROOT_FINGERPRINTS
               │
               ▼
   [Stage 6: Android Keymaster OID Extension Extraction]
   - Search raw DER for OID 1.3.6.1.4.1.11129.2.1.17 (2b06010401d679020111)
   - Parse ASN.1 TLV sequence for KeyDescription fields
               │
               ▼
   [Stage 7: Challenge & Identity Binding Validation]
   - Byte-for-byte comparison of attestationChallenge against serverNonce
   - Verify applicationPackage === 'com.kelasagaara.kelasagaara'
               │
               ▼
   [Stage 8: Security Assurance Classification]
   - Map securityLevel: 2 -> DEVICE_KEY_STRONGBOX, 1 -> DEVICE_KEY_TEE, 0 -> DEVICE_KEY_SOFTWARE
   - Return typed DeviceKeyAttestationResult
```

---

## 2. ASN.1 TLV PARSING LOGIC

Because Node.js does not expose raw custom X.509 extensions through standard high-level APIs without external heavy dependencies, `device_key_attestation.ts` includes a high-performance, native zero-dependency ASN.1 parser:

```typescript
function readAsn1Tlv(buf: Buffer, offset: number) {
  if (offset >= buf.length) return null;
  const tag = buf[offset];
  let lenByte = buf[offset + 1];
  let length = 0;
  let lenBytesCount = 1;

  if (lenByte < 0x80) {
    length = lenByte;
  } else {
    const numBytes = lenByte & 0x7f;
    lenBytesCount = 1 + numBytes;
    length = 0;
    for (let i = 0; i < numBytes; i++) {
      length = (length << 8) | buf[offset + 2 + i];
    }
  }

  const valueOffset = offset + 1 + lenBytesCount;
  const value = buf.subarray(valueOffset, valueOffset + length);
  const totalLength = 1 + lenBytesCount + length;

  return { tag, length, value, totalLength };
}
```

This parser extracts:
- `attestationVersion` (INTEGER, Tag `0x02`)
- `attestationSecurityLevel` (INTEGER/ENUMERATED, Tag `0x02`/`0x0A`)
- `keymintVersion` (INTEGER, Tag `0x02`)
- `keymintSecurityLevel` (INTEGER/ENUMERATED, Tag `0x02`/`0x0A`)
- `attestationChallenge` (OCTET STRING, Tag `0x04`)
- `uniqueId` (OCTET STRING, Tag `0x04`)
- `softwareEnforced` & `hardwareEnforced` authorization lists

---

## 3. ATTESTATION STATUS CODES & DECISION MATRIX

| Attestation Status | Condition | Production Verdict | Local/Test Verdict |
| :--- | :--- | :--- | :--- |
| `VERIFIED` | Full chain valid, roots to Google Root CA, challenge matches, package matches | **ALLOWED** (`HTTP 200`) | **ALLOWED** (`HTTP 200`) |
| `SELF_ATTESTED` | Key valid EC P-256, but hardware attestation extension omitted (e.g. emulator) | **REJECTED** (`HTTP 403`) | **ALLOWED** (`HTTP 200`) |
| `CHALLENGE_MISMATCH` | Challenge in cert does not match server-issued registration challenge | **REJECTED** (`HTTP 400`) | **REJECTED** (`HTTP 400`) |
| `PACKAGE_MISMATCH` | Package name in cert is not `com.kelasagaara.kelasagaara` | **REJECTED** (`HTTP 403`) | **REJECTED** (`HTTP 403`) |
| `EXPIRED` | One or more certificates outside `validFrom` - `validTo` window | **REJECTED** (`HTTP 400`) | **REJECTED** (`HTTP 400`) |
| `INVALID_CHAIN` | Signature verification between parent and child certificate fails | **REJECTED** (`HTTP 400`) | **REJECTED** (`HTTP 400`) |
| `UNTRUSTED_ROOT` | Root certificate is not in `KNOWN_GOOGLE_ROOT_FINGERPRINTS` | **REJECTED** (`HTTP 403`) | **REJECTED** (`HTTP 403`) |
| `UNSUPPORTED_ALGORITHM` | Key is not ECDSA over P-256 | **REJECTED** (`HTTP 400`) | **REJECTED** (`HTTP 400`) |
