# KELASAGARA V20.3: PLAY INTEGRITY BINDING V2
## Forensic Correction & Camera Payload Digest Specification

**Project:** Kelasagara Major Project  
**System:** Worker Marketplace & Multi-Factor Biometric Identity Platform  
**Document Code:** KS-SEC-P20.3-06  
**Classification:** Core Security Engineering Specification

---

## 1. FORENSIC AUDIT OF V20.2 REQUEST BINDING DEFECT

In Phase 20.2, the Play Integrity request binding protocol was implemented using:
$$\text{payloadDigest} = \text{SHA256}(\text{Float32LE 128-D SFace embedding})$$

### The Architectural Defect Identified:
1. **The Server is Authoritative:** In Kelasagara's biometric architecture, face embeddings are extracted **exclusively on the trusted backend** using the OpenCV SFace ONNX engine (`CanonicalSFaceEngineV10`).
2. **Client Does Not Possess Embedding:** The Flutter mobile application transmits the raw captured face image bytes (via `imageBase64` or multipart stream). It does **not** run the OpenCV SFace model and therefore cannot compute an authoritative 128-D embedding prior to request transmission.
3. **Flawed Alternative:** Having the client generate a substitute client embedding would violate Phase 3C1 invariants ("Client-supplied biometric embeddings are strictly prohibited").

### The Phase 20.3 Mandated Correction: `PLAY_INTEGRITY_BINDING_V2`
In V20.3, the payload digest binding is transitioned to:
$$\text{payloadDigest} = \text{SHA256}(\text{exact submitted raw image bytes})$$

The mobile client computes the SHA-256 digest over the exact uncompressed camera frame buffer before transmission. The backend receives the image buffer and computes the identical SHA-256 digest **before** any backend preprocessing, cropping, resizing, or normalizations occur.

This guarantees:
1. Exact bit-for-bit parity between the mobile client and the backend server.
2. Complete tamper-detection: if an attacker modifies a single pixel of the face image in transit, the payload digest changes, the `requestHash` mismatches the Play Integrity token, and the device signature fails verification.
3. Full compliance with server-authoritative biometric feature extraction.

---

## 2. PLAY INTEGRITY TOKEN GENERATION WITH V2 BINDING

```
[Camera Sensor] ──> [Raw Capture Bytes]
                             │
                             ├───────────────┐
                             │               ▼
                             │      [Compute SHA256] ──> payloadDigestSha256
                             │                                 │
                             │                                 ▼
                             │     [Construct PlayIntegrityBindingParamsV2]
                             │     - protocolVersion: 'PLAY_INTEGRITY_BINDING_V2'
                             │     - packageName: 'com.kelasagaara.kelasagaara'
                             │     - appVersion: '1.0.0'
                             │     - authenticatedUid: callerUid
                             │     - deviceKeyId: activeDeviceKeyId
                             │     - challengeId & challengeNonce
                             │     - idempotencyKey
                             │     - httpMethod & route
                             │     - payloadDigestSha256
                             │                                 │
                             │                                 ▼
                             │     [serializeCanonicalBinding(params)]
                             │                                 │
                             ├─────────────────────────────────┤
                             │                                 │
                             ▼                                 ▼
              [Sign with Android Keystore]       [computePlayIntegrityRequestHash]
                             │                                 │
                             ▼                                 ▼
                    x-device-signature                    requestHash
                                                               │
                                                               ▼
                                              [StandardIntegrityTokenProvider.request()]
                                                               │
                                                               ▼
                                                      playIntegrityToken
```

Both the `playIntegrityToken` and `x-device-signature` are submitted in the HTTP headers of the biometric capture request.
