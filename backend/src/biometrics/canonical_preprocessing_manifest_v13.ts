/**
 * KELASAGARA V20.13 - WORKSTREAM C: CANONICAL PREPROCESSING MANIFEST CRYPTOGRAPHIC SPECIFICATION
 *
 * Implements:
 * 1. Comprehensive Canonical Preprocessing Manifest V3 containing all CV parameters.
 * 2. RFC 8785 JSON Canonicalization Scheme (JCS) deterministic fingerprinting.
 * 3. Asymmetric Manifest Signing & Public-Key Verification.
 * 4. Explicit separation between:
 *    - Manifest Fingerprint (content identifier)
 *    - Manifest Signature (authority approval)
 *    - Runtime Execution Provenance (active environment & loaded weights)
 */

import { canonicalizeJson, computeJcsSha256 } from '../crypto/rfc8785_canonicalizer';
import crypto, { generateKeyPairSync, sign, verify } from 'crypto';

export interface CanonicalPreprocessingManifestV3 {
  readonly manifestSchemaVersion: '3.0.0';
  readonly embeddingSpaceId: 'SFACE_128_YUNET_2023MAR_UMEYAMA_CANONICAL112_V2';
  readonly preprocessingSoftwareVersion: 'v20.13.0';

  readonly featureExtractor: {
    readonly modelIdentifier: 'sface_opencv_zoo_v1_primary';
    readonly modelSha256: '0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79';
    readonly inputDimensions: [1, 3, 112, 112];
    readonly colorFormat: 'BGR';
    readonly scalingFactor: 1.0;
    readonly meanSubtraction: [0.0, 0.0, 0.0];
    readonly embeddingDimension: 128;
    readonly featureNormalization: 'L2_UNIT_HYPERSPHERE_S127';
  };

  readonly detector: {
    readonly modelIdentifier: 'yunet_opencv_zoo_2023mar_primary';
    readonly modelSha256: '8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4';
    readonly inputDimensions: [1, 3, 320, 320];
    readonly outputInterpretation: 'YUNET_BOUNDING_BOX_AND_5_LANDMARKS';
    readonly confidenceThreshold: 0.8;
    readonly nmsThreshold: 0.3;
    readonly landmarkConvention: '5_POINT_RIGHT_EYE_LEFT_EYE_NOSE_RIGHT_MOUTH_LEFT_MOUTH';
  };

  readonly alignment: {
    readonly umeyamaImplementationVersion: 'umeyama_similarity_closed_form_v1';
    readonly alignmentInterpolation: 'BILINEAR_AFFINE_WARP';
    readonly canonicalImageDimensions: {
      readonly width: 112;
      readonly height: 112;
      readonly channels: 3;
    };
    readonly canonicalTargetCoordinates: {
      readonly rightEye: { readonly x: 38.2946; readonly y: 51.6963 };
      readonly leftEye: { readonly x: 73.5318; readonly y: 51.5014 };
      readonly noseTip: { readonly x: 56.0252; readonly y: 71.7366 };
      readonly rightMouth: { readonly x: 41.5493; readonly y: 92.3655 };
      readonly leftMouth: { readonly x: 70.7299; readonly y: 92.2041 };
    };
  };
}

export const CANONICAL_PREPROCESSING_MANIFEST_V3: CanonicalPreprocessingManifestV3 = {
  manifestSchemaVersion: '3.0.0',
  embeddingSpaceId: 'SFACE_128_YUNET_2023MAR_UMEYAMA_CANONICAL112_V2',
  preprocessingSoftwareVersion: 'v20.13.0',
  featureExtractor: {
    modelIdentifier: 'sface_opencv_zoo_v1_primary',
    modelSha256: '0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79',
    inputDimensions: [1, 3, 112, 112],
    colorFormat: 'BGR',
    scalingFactor: 1.0,
    meanSubtraction: [0.0, 0.0, 0.0],
    embeddingDimension: 128,
    featureNormalization: 'L2_UNIT_HYPERSPHERE_S127',
  },
  detector: {
    modelIdentifier: 'yunet_opencv_zoo_2023mar_primary',
    modelSha256: '8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4',
    inputDimensions: [1, 3, 320, 320],
    outputInterpretation: 'YUNET_BOUNDING_BOX_AND_5_LANDMARKS',
    confidenceThreshold: 0.8,
    nmsThreshold: 0.3,
    landmarkConvention: '5_POINT_RIGHT_EYE_LEFT_EYE_NOSE_RIGHT_MOUTH_LEFT_MOUTH',
  },
  alignment: {
    umeyamaImplementationVersion: 'umeyama_similarity_closed_form_v1',
    alignmentInterpolation: 'BILINEAR_AFFINE_WARP',
    canonicalImageDimensions: {
      width: 112,
      height: 112,
      channels: 3,
    },
    canonicalTargetCoordinates: {
      rightEye: { x: 38.2946, y: 51.6963 },
      leftEye: { x: 73.5318, y: 51.5014 },
      noseTip: { x: 56.0252, y: 71.7366 },
      rightMouth: { x: 41.5493, y: 92.3655 },
      leftMouth: { x: 70.7299, y: 92.2041 },
    },
  },
} as const;

/**
 * Deterministic Manifest Fingerprint computed using RFC 8785 JSON Canonicalization Scheme.
 */
export const CANONICAL_MANIFEST_FINGERPRINT_V3 = computeJcsSha256(CANONICAL_PREPROCESSING_MANIFEST_V3);

export interface SignedManifestEnvelope {
  readonly manifest: CanonicalPreprocessingManifestV3;
  readonly fingerprint: string;
  readonly signatureAlgorithm: 'ECDSA_P256_SHA256' | 'RSA_PSS_SHA256';
  readonly keyId: string;
  readonly keyVersion: number;
  readonly signerRole: 'BIOMETRIC_AUTHORITY_ROOT' | 'CI_PIPELINE_AUTHORITY';
  readonly signedAtIso: string;
  readonly signatureBase64: string;
}

export interface RuntimeExecutionProvenance {
  readonly manifestFingerprint: string;
  readonly loadedSFaceSha256: string;
  readonly loadedYuNetSha256: string;
  readonly runtimeEnvironment: string;
  readonly verifiedAtMs: number;
  readonly matchesApprovedManifest: boolean;
}

export class ManifestAttestationAuthority {
  private static readonly REVOKED_KEY_IDS = new Set<string>(['revoked_key_compromised_2025']);

  /**
   * Signs a canonical preprocessing manifest using an asymmetric private key.
   */
  public static signManifest(params: {
    manifest: CanonicalPreprocessingManifestV3;
    privateKeyPem: string;
    keyId: string;
    keyVersion: number;
    signerRole: 'BIOMETRIC_AUTHORITY_ROOT' | 'CI_PIPELINE_AUTHORITY';
    nowIso?: string;
  }): SignedManifestEnvelope {
    if (this.REVOKED_KEY_IDS.has(params.keyId)) {
      throw new Error(`SIGNING_KEY_REVOKED: Key ${params.keyId} is on the active revocation list.`);
    }

    const canonicalBytes = Buffer.from(canonicalizeJson(params.manifest), 'utf8');
    const fingerprint = computeJcsSha256(params.manifest);

    const signer = crypto.createSign('SHA256');
    signer.update(canonicalBytes);
    signer.end();

    const signature = signer.sign(params.privateKeyPem, 'base64');

    return {
      manifest: params.manifest,
      fingerprint,
      signatureAlgorithm: 'ECDSA_P256_SHA256',
      keyId: params.keyId,
      keyVersion: params.keyVersion,
      signerRole: params.signerRole,
      signedAtIso: params.nowIso ?? new Date().toISOString(),
      signatureBase64: signature,
    };
  }

  /**
   * Verifies the cryptographic signature of an approved manifest.
   */
  public static verifyManifestSignature(
    envelope: SignedManifestEnvelope,
    publicKeyPem: string
  ): { valid: boolean; reason?: string } {
    if (this.REVOKED_KEY_IDS.has(envelope.keyId)) {
      return { valid: false, reason: `KEY_REVOKED: Key ID ${envelope.keyId} is revoked.` };
    }

    // 1. Recompute and verify RFC 8785 fingerprint
    const computedFingerprint = computeJcsSha256(envelope.manifest);
    if (computedFingerprint !== envelope.fingerprint) {
      return { valid: false, reason: 'FINGERPRINT_MISMATCH: Manifest contents do not match envelope fingerprint.' };
    }

    // 2. Verify asymmetric signature over canonical bytes
    try {
      const canonicalBytes = Buffer.from(canonicalizeJson(envelope.manifest), 'utf8');
      const verifier = crypto.createVerify('SHA256');
      verifier.update(canonicalBytes);
      verifier.end();

      const validSig = verifier.verify(publicKeyPem, envelope.signatureBase64, 'base64');
      if (!validSig) {
        return { valid: false, reason: 'INVALID_SIGNATURE: Asymmetric cryptographic signature check failed.' };
      }
      return { valid: true };
    } catch (err: any) {
      return { valid: false, reason: `SIGNATURE_VERIFICATION_ERROR: ${err.message}` };
    }
  }

  /**
   * Validates runtime execution provenance by comparing active loaded weights against the approved manifest.
   */
  public static verifyRuntimeExecutionProvenance(params: {
    manifest: CanonicalPreprocessingManifestV3;
    actualSFaceBytes: Buffer;
    actualYuNetBytes: Buffer;
  }): RuntimeExecutionProvenance {
    const sfaceSha = crypto.createHash('sha256').update(params.actualSFaceBytes).digest('hex');
    const yunetSha = crypto.createHash('sha256').update(params.actualYuNetBytes).digest('hex');

    const matchesApprovedManifest =
      sfaceSha.toLowerCase() === params.manifest.featureExtractor.modelSha256.toLowerCase() &&
      yunetSha.toLowerCase() === params.manifest.detector.modelSha256.toLowerCase();

    return {
      manifestFingerprint: computeJcsSha256(params.manifest),
      loadedSFaceSha256: sfaceSha,
      loadedYuNetSha256: yunetSha,
      runtimeEnvironment: `Node.js ${process.version} / ${process.platform}-${process.arch}`,
      verifiedAtMs: Date.now(),
      matchesApprovedManifest,
    };
  }
}
