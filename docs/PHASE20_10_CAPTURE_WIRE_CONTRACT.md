# KELASAGARA V20.10: CAPTURE WIRE CONTRACT SPECIFICATION
## Authoritative Versioned Wire Envelope and Request Payload Schema

**System:** Kelasagara Major Project  
**Phase:** 20.10  
**Auditor:** Principal Cryptography Engineer & Backend Systems Architect  
**Date:** November 1, 2026

---

### 1. The Unified Wire Representation

To eliminate discrepancies between native Android camera frames, transmitted network bytes, and server-side verification buffers, Kelasagara V20.10 establishes **`KS_CAPTURE_ENVELOPE_V1`** as the single authoritative wire representation.

---

### 2. Envelope Schema Specification

```typescript
export interface FrameDescriptorV1 {
  readonly index: number;                     // 0-based sequence index of accepted frame
  readonly byteLength: number;                // Exact byte length of transmitted frame
  readonly sha256Hex: string;                 // SHA-256 hex of exact transmitted frame bytes
  readonly width: number;                     // Width in pixels (px)
  readonly height: number;                    // Height in pixels (px)
  readonly mimeType: 'image/jpeg' | 'image/x-canonical-i420';
  readonly rotationDegrees: 0 | 90 | 180 | 270;
  readonly isFrontMirrored: boolean;
  readonly clientTimestampNs: number;         // Diagnostic camera sensor timestamp
}

export interface CaptureEnvelopeV1 {
  readonly protocolVersion: 'KS_CAPTURE_ENVELOPE_V1';
  readonly captureSessionId: string;          // Server-issued UUID
  readonly serverNonce: string;               // Server-issued single-use cryptographic nonce
  readonly deviceKeyId: string;               // Registered Android Keystore public key ID
  readonly authenticatedUid: string;          // Authenticated Firebase UID
  readonly appVersion: string;                // e.g. "20.10.0"
  readonly captureAlgorithmVersion: 'CAMERA_V20_10';
  readonly padExtractorVersion: 'OPTICAL_PAD_V20_8';
  readonly frameCount: number;                // Must equal frames.length
  readonly frames: FrameDescriptorV1[];
}

export interface CaptureWireRequestPayloadV1 {
  readonly envelope: CaptureEnvelopeV1;
  readonly framePayloadsBase64: string[];     // Exact bytes of each transmitted frame
  readonly deviceSignatureBase64: string;    // ECDSA SHA256withECDSA over canonical envelope bytes
  readonly playIntegrityToken?: string;      // Standard Play Integrity token
  readonly playIntegrityRequestHash?: string; // Base64Url SHA-256 of canonical envelope digest
}
```

---

### 3. Verification Invariants

1. **Independent Server-Side Digest Check:** The backend never trusts client `sha256Hex`. It decodes `framePayloadsBase64[i]`, computes `SHA-256(rawBytes)`, and strictly asserts:
   $$\text{computedSha256} == \text{envelope.frames}[i]\text{.sha256Hex}$$
   $$\text{rawBytes.length} == \text{envelope.frames}[i]\text{.byteLength}$$
2. **Replay Invariant:** The envelope's `serverNonce` is single-use and transitionally locked (`ISSUED -> PROCESSING -> CONSUMED`).
