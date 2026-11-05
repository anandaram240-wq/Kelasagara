# KELASAGARA V20.12: PROVENANCE TRUST MODEL & MANIFEST ATTESTATION

**Project:** Kelasagara Biometric Security Architecture  
**Phase:** V20.12  
**Parent Phase:** V20.11 (`412def0`)  
**Working Branch:** `security/phase20.12-biometric-trust-provenance`  
**Classification:** Cryptographic Provenance & Preprocessing Manifest Specification  

---

## 1. PREPROCESSING MANIFEST SPECIFICATION

To guarantee reproducible, untampered preprocessing across all biometric enrollment and verification pipelines, Phase 20.12 freezes the **Canonical Preprocessing Manifest V2**.

```typescript
export const CANONICAL_PREPROCESSING_MANIFEST_V2 = {
  manifestVersion: 'v2.0.0-canonical-sface-yunet',
  embeddingSpaceId: 'SFACE_128_YUNET_2023MAR_UMEYAMA_CANONICAL112_V2',
  featureExtractor: {
    modelIdentifier: 'sface_opencv_zoo_v1_primary',
    modelSha256: '0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79',
    inputDimension: 112,
    colorOrder: 'BGR',
    normalization: 'L2_UNIT_SPHERE_S127',
  },
  detector: {
    modelIdentifier: 'yunet_opencv_zoo_2023mar_primary',
    modelSha256: '8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4',
    confidenceThreshold: 0.80,
    nmsThreshold: 0.30,
  },
  alignment: {
    algorithm: 'umeyama_5point_similarity',
    canonicalLandmarkGeometry: '112x112_canonical_sface_5landmarks',
    canonicalLandmarks: {
      rightEye: { x: 38.2946, y: 51.6963 },
      leftEye: { x: 73.5318, y: 51.5014 },
      noseTip: { x: 56.0252, y: 71.7366 },
      rightMouth: { x: 41.5493, y: 92.3655 },
      leftMouth: { x: 70.7299, y: 92.2041 },
    },
  },
} as const;
```

### Deterministic Manifest Digest
The SHA-256 hash of the canonical JSON string:
$$\text{CANONICAL\_MANIFEST\_HASH\_V2} = \text{createHash('sha256').update(JSON.stringify(CANONICAL\_PREPROCESSING\_MANIFEST\_V2)).digest('hex')}$$

---

## 2. SERVER-AUTHORITATIVE PROVENANCE BINDING

Untrusted clients are strictly prevented from specifying or modifying template metadata:
1. **No Client-Supplied Space ID:** The client enrollment request transmits raw verified camera frames and cryptographic proofs. The backend pipeline independently executes face detection, alignment, embedding extraction, and metadata stamping.
2. **Firestore Rule Rejection:** The `biometric_vault` collection is completely closed to direct client writes (`allow read, write: if false`). All updates occur via the Firebase Admin SDK inside authenticated backend transaction coordinators.
3. **Template Integrity Binding:** Every committed `biometric_vault` document binds:
   - `manifestVersion`: `'v2.0.0-canonical-sface-yunet'`
   - `manifestHash`: `CANONICAL_MANIFEST_HASH_V2`
   - `modelSha256`: SFace frozen SHA-256
   - `detectorSha256`: YuNet frozen SHA-256
   - `embeddingSpaceId`: `CANONICAL_EMBEDDING_SPACE_V2.embeddingSpaceId`
4. **Tamper Rejection:** If an internal administrative or corrupted document has mismatched hashes, `classifyBiometricTemplate()` flags it as `LEGACY_TEMPLATE_UNKNOWN` and immediately excludes it from matching.
