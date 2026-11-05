# PHASE 20.13: MANIFEST ATTESTATION, SIGNATURES & RUNTIME PROVENANCE
## Architectural Separation of Manifest Fingerprint, Asymmetric Signature, and Execution Runtime Verification

**Date:** November 2026  
**System:** Kelasagara Biometric Identity Service  
**Author:** Principal Biometric Systems Engineer & Cryptographic Architect  
**Status:** APPROVED & AUDITED  
**Repository:** `kelasagaara_v17`  
**Classification:** SOURCE_VERIFIED & ARCHITECTURALLY_ENFORCED  

---

### 1. Conceptual Distinction: Three Pillars of Pipeline Trust

Prior systems often conflated configuration identifiers with runtime integrity. Phase 20.13 establishes an unambiguous tripartite boundary for biometric trustworthiness:

```
+-----------------------------------------------------------------------------------+
| 1. MANIFEST FINGERPRINT (Static Digest)                                           |
|    JCS SHA-256 digest of CANONICAL_PREPROCESSING_MANIFEST_V3.                    |
|    Proves WHAT the pipeline parameters are supposed to be.                       |
+-----------------------------------------------------------------------------------+
                                          |
                                          v
+-----------------------------------------------------------------------------------+
| 2. MANIFEST ATTESTATION SIGNATURE (Asymmetric Cryptographic Claim)                |
|    ECDSA P-256 / SHA-256 signature issued by Security Architect root key.         |
|    Proves WHO authorized this pipeline and that it has not been altered.          |
+-----------------------------------------------------------------------------------+
                                          |
                                          v
+-----------------------------------------------------------------------------------+
| 3. RUNTIME EXECUTION PROVENANCE (In-Memory Live Verification)                     |
|    Runtime check of actual active ONNX sessions, binary weights, and versions.   |
|    Proves that running memory MATCHES the signed manifest before inference.      |
+-----------------------------------------------------------------------------------+
```

---

### 2. Pillar 1: Manifest Fingerprint (`CANONICAL_MANIFEST_FINGERPRINT_V3`)

The manifest defines 18 critical parameters of the YuNet + SFace pipeline:
- `manifestVersion: '3.0.0'`
- `pipelineIdentifier: 'YUNET_2023MAR_SFACE_2021DEC_UMEYAMA_CANONICAL112_V3'`
- `detector`: Model ID, SHA-256 hash (`8f2383e4dd3...`), input size `[320, 320]`, BGR color, landmark convention `[re, le, nt, rc, lc]`.
- `aligner`: Algorithm `SIMILARITY_TRANSFORM_UMEYAMA`, version `1.0.0`, canonical coordinate anchors, output `112x112`, bilinear interpolation.
- `recognizer`: Model ID, SHA-256 hash (`0ba9fbfa01b...`), input size `[112, 112]`, normalization `mean=0.0, std=1.0`, output 128-D L2-normalized float32.
- `embeddingSpaceId`: `SFACE_128_YUNET_2023MAR_UMEYAMA_CANONICAL112_V2`
- `preprocessingSoftwareVersion`: `20.13.0`

Using RFC 8785 JCS, the entire object serializes deterministically, and `computeJcsSha256(YUNET_SFACE_CANONICAL_V3)` yields `CANONICAL_MANIFEST_FINGERPRINT_V3`.

---

### 3. Pillar 2: Asymmetric Attestation (`ManifestAttestationAuthority`)

A static fingerprint alone does not prove authorization. An unauthorized engineer could change a parameter, recompute the fingerprint, and claim it is valid.

To prevent unauthorized parameter changes, the manifest is enveloped in a signed attestation token:
```typescript
export interface SignedManifestEnvelope {
  manifest: CanonicalPreprocessingManifestV3;
  manifestFingerprint: string;
  signature: string; // Base64 ECDSA P-256 signature
  keyId: string;
  algorithm: 'ECDSA_P256_SHA256';
  signedAt: string;
  expiresAt: string;
}
```

The `ManifestAttestationAuthority` enforces:
1. **Signature Verification:** Verifies that `signature` is valid for `manifestFingerprint` using the trusted public key registered for `keyId`.
2. **Key Revocation Checks:** If a release signing key is compromised or revoked, `authority.revokeKey(keyId)` invalidates all signatures produced by that key.
3. **Temporal Validity:** Enforces `signedAt <= now <= expiresAt`.

---

### 4. Pillar 3: Runtime Execution Provenance (`verifyRuntimeExecutionProvenance`)

Even with a signed manifest, memory-injection attacks or configuration drifts could cause the inference engine to run against a different model file (e.g., an outdated, quantized, or unaligned model).

`verifyRuntimeExecutionProvenance()` audits the live in-memory execution environment immediately prior to running inferences:

```typescript
export function verifyRuntimeExecutionProvenance(
  activeDetectorModelSha256: string,
  activeRecognizerModelSha256: string,
  activeEmbeddingSpaceId: string
): { verified: boolean; error?: string } {
  const expectedDetector = YUNET_SFACE_CANONICAL_V3.detector.modelSha256;
  const expectedRecognizer = YUNET_SFACE_CANONICAL_V3.recognizer.modelSha256;
  const expectedEmbeddingSpace = YUNET_SFACE_CANONICAL_V3.embeddingSpaceId;

  if (activeDetectorModelSha256 !== expectedDetector) {
    return {
      verified: false,
      error: `ERR_DETECTOR_PROVENANCE_MISMATCH: Live detector hash ${activeDetectorModelSha256} != approved manifest ${expectedDetector}`,
    };
  }

  if (activeRecognizerModelSha256 !== expectedRecognizer) {
    return {
      verified: false,
      error: `ERR_RECOGNIZER_PROVENANCE_MISMATCH: Live recognizer hash ${activeRecognizerModelSha256} != approved manifest ${expectedRecognizer}`,
    };
  }

  if (activeEmbeddingSpaceId !== expectedEmbeddingSpace) {
    return {
      verified: false,
      error: `ERR_EMBEDDING_SPACE_MISMATCH: Active ${activeEmbeddingSpaceId} != approved ${expectedEmbeddingSpace}`,
    };
  }

  return { verified: true };
}
```

---

### 5. Automated Verification Results

In `src/tests/phase20_13_privileged_backend_security.test.ts`:
- **Test 13 (PASS):** Proves that changing even 1 character in the SFace hash produces an entirely distinct fingerprint.
- **Test 14 (PASS):** Rejects forged, truncated, or tampered signatures.
- **Test 15 (PASS):** Fails closed on unsupported manifest versions.
- **Test 17 (PASS):** Validates that `verifyRuntimeExecutionProvenance` halts execution if live model weights diverge from the approved manifest.
