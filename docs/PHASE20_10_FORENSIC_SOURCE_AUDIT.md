# KELASAGARA V20.10: FORENSIC SOURCE AUDIT & CALL GRAPH
## Comprehensive Codebase Inspection from Camera Sensor to Backend Vault

**System:** Kelasagara Major Project  
**Phase:** 20.10  
**Parent Commit:** `af84761`  
**Working Branch:** `security/phase20.10-capture-wire-verification`  
**Auditor:** Principal Cryptography & Application Security Architect  
**Date:** November 1, 2026

---

### 1. Source-to-Source Call Graph Architecture

The forensic tracing of all capture, signing, binding, and verification components establishes the following end-to-end data flow:

```
[Camera Sensor: CMOS Hardware]
             │ (RAW Bayer Optical Capture)
             ▼
[Camera2 / HAL3 Android Driver]
             │ (Hardware YUV_420_888 Image Buffer)
             ▼
[CameraX ImageAnalysis: ImageProxy]
             │
             ├──► Native Yuv420PlaneReader.kt
             │      Input: android.media.Image (3 PlaneProxy instances: Y, U, V)
             │      Operations:
             │        - Row stride unpadding (skips alignment bytes: stride > width)
             │        - Semi-planar demuxing (handles pixelStride = 1 and 2)
             │        - Subsampled chroma 2x2 coordinate snapping (handles odd bounds)
             │        - Front-camera horizontal mirroring (isFrontMirrored)
             │        - Upright rotation normalization (0, 90, 180, 270 degrees)
             │      Output: CanonicalYuv420Frame (contiguous unpadded I420 byte array)
             │
             ├──► Local Preview & Landmark Alignment
             │      Input: Canonical Y-plane (8-bit grayscale luminance)
             │      Operation: ML Kit Face Detection (5-point canonical landmarks)
             │      Discard: Y-plane buffer released immediately after landmark inference
             │
             ▼
[Android Keystore Device Signing]
             │
             ├──► DeviceKeyManager.kt
             │      Key Type: Hardware-backed ECDSA SECP256R1 (TEE / StrongBox)
             │      Input: Canonical serialized envelope bytes
             │      Algorithm: SHA256withECDSA (ASN.1 DER format)
             │      Note: Canonical bytes are passed directly; double hashing avoided
             │      Output: Base64-encoded signature (deviceSignatureBase64)
             │
             ▼
[Play Integrity Hardware Binding]
             │
             ├──► PlayIntegrityBridge.kt & play_integrity_request_binding.ts
             │      Input: PlayIntegrityBindingParamsV2
             │      requestHash: Base64Url SHA-256 of canonical envelope digest
             │      Operation: Google Play Standard Integrity API token request
             │      Output: Encrypted Play Integrity token string
             │
             ▼
[HTTPS TLS 1.3 Transport]
             │ Transmits: CaptureWireRequestPayloadV1
             │   - envelope: CaptureEnvelopeV1
             │   - framePayloadsBase64: [JPEG byte streams]
             │   - deviceSignatureBase64: [ECDSA signature]
             │   - playIntegrityToken / playIntegrityRequestHash
             ▼
[Node.js Express Backend Entry Point]
             │
             ├──► CaptureWireContractEngine.verifyCaptureWirePayload()
             │      1. Protocol check: Assert KS_CAPTURE_ENVELOPE_V1
             │      2. Frame count parity: Assert frameCount == frames.length == payloads.length
             │      3. Frame sequence check: Assert frames[i].index == i
             │      4. Per-Frame Independent Hashing:
             │           Decodes framePayloadsBase64[i]
             │           Computes SHA-256(rawBytes)
             │           Asserts byteLength == descriptor.byteLength
             │           Asserts computedHash == descriptor.sha256Hex (Rejects client hash!)
             │      5. Challenge Nonce Lifecycle (ServerNonceLifecycleService):
             │           Checks state == ISSUED
             │           Atomically transitions ISSUED -> PROCESSING (Prevents concurrency race)
             │      6. Device Signature Verification:
             │           Reconstructs canonical binary bytes from envelope
             │           crypto.verify('sha256', canonicalBytes, publicKeyPem, sigBuffer)
             │      7. Play Integrity requestHash Check:
             │           Recomputes expected requestHash and verifies against token
             │      8. Challenge Finalization:
             │           Atomically transitions PROCESSING -> CONSUMED (Prevents replay)
             │
             ├──► Image Decoding & Optical Signal Inspection (Sharp / libvips)
             │      Input: Verified JPEG frame bytes
             │      Decode: sharp(buffer).raw().toBuffer() -> RGB24
             │      PAD Feature Extractor:
             │        - 2D DCT-II on 16x16 / 8x8 blocks
             │        - Checks Moiré spatial energy ratio and spectral concentration
             │
             ├──► SFace 128-D ONNX Session Pool
             │      Input: 112x112 aligned normalized face crop
             │      Output: 128-D unit vector (||v|| = 1.0)
             │
             ▼
[KMS-Protected Biometric Vault]
             │ Encrypts vector: AES-256-GCM envelope encryption (Cloud KMS)
             ▼
[Transient Memory Zeroization]
             Buffer arrays overwritten with zeros, garbage collected
```

---

### 2. Disconnected & Legacy Component Analysis

During forensic source inspection, the following components were audited:
- **`raw_frame.dart`:** Contains legacy Dart-level frame abstractions. It is retained for backward compatibility with existing Flutter tests but is bypassed by the new native `Yuv420PlaneReader.kt` capture wire flow.
- **`sfaceArena128`:** The in-memory flat vector arena in `canonical_sface_engine_v10.ts` remains active and operates strictly on post-verification 128-D embeddings.
- **Unconnected Artifacts:** No orphaned biometric routes were detected; all live routes mount through Express middleware enforcing authentication, Play Integrity, and Keystore attestation.
