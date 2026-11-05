# KELASAGARA V20.10: CANONICAL SERIALIZATION SPECIFICATION
## Length-Prefixed Binary and RFC 8785 JSON Determinism

**System:** Kelasagara Major Project  
**Phase:** 20.10  
**Auditor:** Principal Cryptography Engineer  
**Date:** November 1, 2026

---

### 1. The Challenge of Cross-Platform Determinism

JSON serialization across languages (Kotlin on Android ART, Dart on Flutter, and TypeScript on Node.js V8) is inherently non-deterministic due to:
- Key reordering across hash maps.
- Floating-point formatting discrepancies (`0.0` vs `0`).
- Whitespace variations (`{"a":1}` vs `{"a": 1}`).
- Escape sequences for non-ASCII characters (`\u002F` vs `/`).

To guarantee 100% cryptographic determinism, Kelasagara V20.10 implements **Length-Prefixed Binary Canonical Serialization**.

---

### 2. Binary Encoding Grammar

Every field is serialized in strict, fixed sequence:

```
[Root Fields]
  protocolVersion:            UInt32BE Length + UTF-8 Bytes
  captureSessionId:           UInt32BE Length + UTF-8 Bytes
  serverNonce:                UInt32BE Length + UTF-8 Bytes
  deviceKeyId:                UInt32BE Length + UTF-8 Bytes
  authenticatedUid:           UInt32BE Length + UTF-8 Bytes
  appVersion:                 UInt32BE Length + UTF-8 Bytes
  captureAlgorithmVersion:    UInt32BE Length + UTF-8 Bytes
  padExtractorVersion:        UInt32BE Length + UTF-8 Bytes
  frameCount:                 UInt32BE (4 bytes)

[Per Frame (for i = 0 to frameCount - 1)]
  index:                      UInt32BE (4 bytes)
  byteLength:                 UInt32BE (4 bytes)
  sha256Hex:                  UInt32BE Length + UTF-8 Bytes (64 chars)
  width:                      UInt32BE (4 bytes)
  height:                     UInt32BE (4 bytes)
  mimeType:                   UInt32BE Length + UTF-8 Bytes
  rotationDegrees:            UInt32BE (4 bytes)
  isFrontMirrored:            UInt8 (1 byte: 0x01 or 0x00)
  clientTimestampNs:          UInt64BE (8 bytes)
```

---

### 3. Properties

1. **Unambiguous & Collision-Proof:** Length prefixes prevent delimiter collisions or field boundary shifts.
2. **Endianness:** Strictly Big-Endian (`BE`) network byte order for all integers.
3. **Digest Calculation:**
   $$\text{Digest} = \text{SHA-256}(\text{CanonicalBinaryBytes})$$
