/**
 * backend/src/biometric-evaluation/capture_wire_contract.ts
 *
 * Kelasagara V20.10: Authoritative Capture Wire Contract & Verification Engine.
 *
 * Establishes one canonical, unambiguous wire specification binding:
 * - Native CameraX frames
 * - Transmitted encoded frame bytes
 * - Hardware ECDSA device signature (Android Keystore)
 * - Play Integrity requestHash (PLAY_INTEGRITY_BINDING_V2)
 * - Server-side independent per-frame digest reconstruction
 * - Replay & concurrent submission defense
 */

import * as crypto from 'node:crypto';
import { ServerNonceLifecycleService } from './server_nonce_lifecycle_service';
import {
  PlayIntegrityBindingParamsV2,
  PLAY_INTEGRITY_BINDING_PROTOCOL_V2,
  computePlayIntegrityRequestHash,
  verifyPlayIntegrityRequestHash,
} from '../services/play_integrity_request_binding';

export const CAPTURE_WIRE_PROTOCOL_V1 = 'KS_CAPTURE_ENVELOPE_V1' as const;
export const CAPTURE_ALGORITHM_V20_10 = 'CAMERA_V20_10' as const;
export const PAD_EXTRACTOR_V20_8 = 'OPTICAL_PAD_V20_8' as const;

export type SupportedMimeType = 'image/jpeg' | 'image/x-canonical-i420';

export interface FrameDescriptorV1 {
  readonly index: number;
  readonly byteLength: number;
  readonly sha256Hex: string;
  readonly width: number;
  readonly height: number;
  readonly mimeType: SupportedMimeType;
  readonly rotationDegrees: 0 | 90 | 180 | 270;
  readonly isFrontMirrored: boolean;
  readonly clientTimestampNs: number;
}

export interface CaptureEnvelopeV1 {
  readonly protocolVersion: typeof CAPTURE_WIRE_PROTOCOL_V1;
  readonly captureSessionId: string;
  readonly serverNonce: string;
  readonly deviceKeyId: string;
  readonly authenticatedUid: string;
  readonly appVersion: string;
  readonly captureAlgorithmVersion: typeof CAPTURE_ALGORITHM_V20_10;
  readonly padExtractorVersion: typeof PAD_EXTRACTOR_V20_8;
  readonly frameCount: number;
  readonly frames: FrameDescriptorV1[];
}

export interface CaptureWireRequestPayloadV1 {
  readonly envelope: CaptureEnvelopeV1;
  readonly framePayloadsBase64: string[];
  readonly deviceSignatureBase64: string;
  readonly playIntegrityToken?: string;
  readonly playIntegrityRequestHash?: string;
}

export interface VerifiedCapturePayload {
  readonly valid: boolean;
  readonly envelope: CaptureEnvelopeV1;
  readonly canonicalEnvelopeBytes: Buffer;
  readonly envelopeDigestHex: string;
  readonly decodedFrames: Array<{
    readonly index: number;
    readonly bytes: Buffer;
    readonly byteLength: number;
    readonly sha256Hex: string;
    readonly width: number;
    readonly height: number;
    readonly mimeType: SupportedMimeType;
    readonly rotationDegrees: number;
    readonly isFrontMirrored: boolean;
  }>;
  readonly errorCode?: string;
  readonly errorMessage?: string;
}

export class CaptureWireContractEngine {

  /**
   * Length-prefixed binary canonical serialization of CaptureEnvelopeV1.
   * Completely immune to JSON key-ordering, whitespace, and Unicode normalization differences.
   */
  public static serializeCanonicalEnvelope(envelope: CaptureEnvelopeV1): Buffer {
    const buffers: Buffer[] = [];

    // Helper to write length-prefixed UTF-8 string
    const writeString = (str: string) => {
      const valBuf = Buffer.from(str, 'utf8');
      const lenBuf = Buffer.alloc(4);
      lenBuf.writeUInt32BE(valBuf.length, 0);
      buffers.push(lenBuf, valBuf);
    };

    // Helper to write unsigned 32-bit integer
    const writeUInt32 = (val: number) => {
      const buf = Buffer.alloc(4);
      buf.writeUInt32BE(val >>> 0, 0);
      buffers.push(buf);
    };

    // Helper to write unsigned 64-bit integer
    const writeUInt64 = (val: number) => {
      const buf = Buffer.alloc(8);
      buf.writeBigUInt64BE(BigInt(val), 0);
      buffers.push(buf);
    };

    // Helper to write boolean as uint8
    const writeBoolean = (val: boolean) => {
      buffers.push(Buffer.from([val ? 1 : 0]));
    };

    // 1. Envelope Root Fields
    writeString(envelope.protocolVersion);
    writeString(envelope.captureSessionId);
    writeString(envelope.serverNonce);
    writeString(envelope.deviceKeyId);
    writeString(envelope.authenticatedUid);
    writeString(envelope.appVersion);
    writeString(envelope.captureAlgorithmVersion);
    writeString(envelope.padExtractorVersion);
    writeUInt32(envelope.frameCount);

    // 2. Ordered Frame Descriptors
    for (const frame of envelope.frames) {
      writeUInt32(frame.index);
      writeUInt32(frame.byteLength);
      writeString(frame.sha256Hex.toLowerCase());
      writeUInt32(frame.width);
      writeUInt32(frame.height);
      writeString(frame.mimeType);
      writeUInt32(frame.rotationDegrees);
      writeBoolean(frame.isFrontMirrored);
      writeUInt64(frame.clientTimestampNs);
    }

    return Buffer.concat(buffers);
  }

  /**
   * Computes the deterministic SHA-256 digest of the canonical envelope representation.
   */
  public static computeEnvelopeDigest(envelope: CaptureEnvelopeV1): string {
    const canonicalBytes = this.serializeCanonicalEnvelope(envelope);
    return crypto.createHash('sha256').update(canonicalBytes).digest('hex');
  }

  /**
   * RFC 8785 JSON Canonicalization Scheme (JCS) representation.
   * Produces sorted keys, no whitespace, strict UTF-8 output.
   */
  public static serializeRfc8785Json(envelope: CaptureEnvelopeV1): string {
    const sortObject = (obj: any): any => {
      if (obj === null || typeof obj !== 'object') {
        return obj;
      }
      if (Array.isArray(obj)) {
        return obj.map(sortObject);
      }
      const sortedKeys = Object.keys(obj).sort();
      const result: Record<string, any> = {};
      for (const key of sortedKeys) {
        result[key] = sortObject(obj[key]);
      }
      return result;
    };

    return JSON.stringify(sortObject(envelope));
  }

  /**
   * Full Server-Side Verification Pipeline:
   * 1. Protocol check
   * 2. Frame count parity
   * 3. Independent per-frame byte length and SHA-256 verification
   * 4. Server nonce lifecycle validation (ISSUED -> PROCESSING)
   * 5. Android Keystore ECDSA signature verification over canonical envelope bytes
   * 6. Play Integrity requestHash validation (if provided)
   * 7. Challenge commit (PROCESSING -> CONSUMED)
   * 8. Returns verified decoded image buffers ready for downstream PAD / YuNet / SFace.
   */
  public static async verifyCaptureWirePayload(
    payload: CaptureWireRequestPayloadV1,
    registeredPublicKeyPem: string,
    options: {
      nonceService?: ServerNonceLifecycleService;
      requirePlayIntegrity?: boolean;
      expectedPackageName?: string;
      expectedAppVersion?: string;
    } = {}
  ): Promise<VerifiedCapturePayload> {
    const { envelope, framePayloadsBase64, deviceSignatureBase64 } = payload;
    const nonceService = options.nonceService ?? ServerNonceLifecycleService.getInstance();

    // Guard 1: Protocol Version
    if (envelope.protocolVersion !== CAPTURE_WIRE_PROTOCOL_V1) {
      return this.createFailureResult(envelope, 'UNSUPPORTED_PROTOCOL_VERSION', `Protocol version ${envelope.protocolVersion} is not supported`);
    }

    // Guard 2: Frame Count Parity
    if (!envelope.frames || envelope.frames.length !== envelope.frameCount || framePayloadsBase64.length !== envelope.frameCount) {
      return this.createFailureResult(
        envelope,
        'FRAME_COUNT_MISMATCH',
        `Frame count mismatch: envelope claims ${envelope.frameCount}, descriptors have ${envelope.frames?.length ?? 0}, payloads have ${framePayloadsBase64.length}`
      );
    }

    if (envelope.frameCount <= 0) {
      return this.createFailureResult(envelope, 'EMPTY_FRAME_PAYLOAD', 'Capture envelope must contain at least 1 frame');
    }

    // Guard 3: Frame Sequence Continuity
    for (let i = 0; i < envelope.frames.length; i++) {
      if (envelope.frames[i].index !== i) {
        return this.createFailureResult(
          envelope,
          'FRAME_SEQUENCE_DISCONTINUITY',
          `Frame sequence discontinuity: frame at position ${i} has index ${envelope.frames[i].index}`
        );
      }
    }

    // Guard 4: Independent Server-Side Per-Frame Byte Hashing & Length Verification
    const decodedFrames: VerifiedCapturePayload['decodedFrames'] = [];
    for (let i = 0; i < envelope.frameCount; i++) {
      const descriptor = envelope.frames[i];
      const base64Str = framePayloadsBase64[i];

      if (!base64Str || typeof base64Str !== 'string') {
        return this.createFailureResult(envelope, 'INVALID_FRAME_ENCODING', `Frame ${i} payload is empty or invalid`);
      }

      const frameBytes = Buffer.from(base64Str, 'base64');

      // Verify exact byte length
      if (frameBytes.length !== descriptor.byteLength) {
        return this.createFailureResult(
          envelope,
          'FRAME_LENGTH_MISMATCH',
          `Frame ${i} byte length mismatch: descriptor declared ${descriptor.byteLength}, actual received ${frameBytes.length}`
        );
      }

      // Compute SHA-256 independently
      const actualSha256Hex = crypto.createHash('sha256').update(frameBytes).digest('hex');
      if (actualSha256Hex !== descriptor.sha256Hex.toLowerCase()) {
        return this.createFailureResult(
          envelope,
          'FRAME_DIGEST_MISMATCH',
          `Frame ${i} digest mismatch: descriptor declared ${descriptor.sha256Hex}, server calculated ${actualSha256Hex}`
        );
      }

      decodedFrames.push({
        index: i,
        bytes: frameBytes,
        byteLength: frameBytes.length,
        sha256Hex: actualSha256Hex,
        width: descriptor.width,
        height: descriptor.height,
        mimeType: descriptor.mimeType,
        rotationDegrees: descriptor.rotationDegrees,
        isFrontMirrored: descriptor.isFrontMirrored,
      });
    }

    // Guard 5: Server-Authoritative Challenge Lifecycle (ISSUED -> PROCESSING)
    try {
      nonceService.beginProcessing({
        nonce: envelope.serverNonce,
        expectedSessionId: envelope.captureSessionId,
        expectedUid: envelope.authenticatedUid,
        expectedDeviceKeyId: envelope.deviceKeyId,
      });
    } catch (err: any) {
      return this.createFailureResult(envelope, 'CHALLENGE_VERIFICATION_FAILED', err.message);
    }

    // Guard 6: Canonical Envelope Serialization & Android Keystore ECDSA Signature Verification
    const canonicalEnvelopeBytes = this.serializeCanonicalEnvelope(envelope);
    const envelopeDigestHex = crypto.createHash('sha256').update(canonicalEnvelopeBytes).digest('hex');

    if (!deviceSignatureBase64) {
      nonceService.markFailed(envelope.serverNonce, 'MISSING_DEVICE_SIGNATURE');
      return this.createFailureResult(envelope, 'MISSING_DEVICE_SIGNATURE', 'Hardware device signature is required');
    }

    let signatureBuffer: Buffer;
    try {
      signatureBuffer = Buffer.from(deviceSignatureBase64, 'base64');
    } catch {
      nonceService.markFailed(envelope.serverNonce, 'INVALID_SIGNATURE_BASE64');
      return this.createFailureResult(envelope, 'INVALID_SIGNATURE_BASE64', 'Device signature base64 decoding failed');
    }

    try {
      // Android Keystore signs data with "SHA256withECDSA" which hashes canonicalEnvelopeBytes once and signs with ECDSA
      // Node.js crypto.verify('sha256', canonicalEnvelopeBytes, ...) mirrors this exact standard behavior without double hashing
      const signatureValid = crypto.verify('sha256', canonicalEnvelopeBytes, registeredPublicKeyPem, signatureBuffer);
      if (!signatureValid) {
        nonceService.markFailed(envelope.serverNonce, 'DEVICE_SIGNATURE_INVALID');
        return this.createFailureResult(envelope, 'DEVICE_SIGNATURE_INVALID', 'Cryptographic signature verification failed against registered device key');
      }
    } catch (err: any) {
      nonceService.markFailed(envelope.serverNonce, 'SIGNATURE_VERIFICATION_ERROR');
      return this.createFailureResult(envelope, 'SIGNATURE_VERIFICATION_ERROR', `Error during signature verification: ${err.message}`);
    }

    // Guard 7: Play Integrity Request Hash Verification (Optional or Enforced)
    if (payload.playIntegrityRequestHash) {
      const bindingParams: PlayIntegrityBindingParamsV2 = {
        protocolVersion: PLAY_INTEGRITY_BINDING_PROTOCOL_V2,
        packageName: options.expectedPackageName ?? 'com.kelasagaara.kelasagaara',
        appVersion: envelope.appVersion,
        authenticatedUid: envelope.authenticatedUid,
        deviceKeyId: envelope.deviceKeyId,
        challengeId: envelope.captureSessionId,
        challengePurpose: 'BIOMETRIC_ENROLLMENT',
        serverNonce: envelope.serverNonce,
        idempotencyKey: envelope.captureSessionId,
        httpMethod: 'POST',
        route: '/api/v20/biometrics/capture',
        payloadDigestSha256: envelopeDigestHex,
      };

      const hashCheck = verifyPlayIntegrityRequestHash(payload.playIntegrityRequestHash, bindingParams);
      if (!hashCheck.valid) {
        nonceService.markFailed(envelope.serverNonce, 'PLAY_INTEGRITY_REQUEST_HASH_MISMATCH');
        return this.createFailureResult(
          envelope,
          'PLAY_INTEGRITY_REQUEST_HASH_MISMATCH',
          `Play Integrity requestHash mismatch: expected ${hashCheck.expectedRequestHash}, got ${payload.playIntegrityRequestHash}`
        );
      }
    } else if (options.requirePlayIntegrity) {
      nonceService.markFailed(envelope.serverNonce, 'MISSING_PLAY_INTEGRITY_BINDING');
      return this.createFailureResult(envelope, 'MISSING_PLAY_INTEGRITY_BINDING', 'Play Integrity binding is required for this operation');
    }

    // Guard 8: Finalize Challenge Consumption (PROCESSING -> CONSUMED)
    nonceService.commitConsumed(envelope.serverNonce);

    return {
      valid: true,
      envelope,
      canonicalEnvelopeBytes,
      envelopeDigestHex,
      decodedFrames,
    };
  }

  private static createFailureResult(
    envelope: CaptureEnvelopeV1,
    errorCode: string,
    errorMessage: string
  ): VerifiedCapturePayload {
    return {
      valid: false,
      envelope,
      canonicalEnvelopeBytes: Buffer.alloc(0),
      envelopeDigestHex: '',
      decodedFrames: [],
      errorCode,
      errorMessage,
    };
  }
}
