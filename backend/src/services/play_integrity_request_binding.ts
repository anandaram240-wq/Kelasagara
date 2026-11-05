// File: backend/src/services/play_integrity_request_binding.ts
import * as crypto from 'node:crypto';

export const PLAY_INTEGRITY_BINDING_PROTOCOL_V1 = 'PLAY_INTEGRITY_BINDING_V1' as const;
export const PLAY_INTEGRITY_BINDING_PROTOCOL_V2 = 'PLAY_INTEGRITY_BINDING_V2' as const;
export const EXPECTED_PACKAGE_NAME = 'com.kelasagaara.kelasagaara' as const;

export type PlayIntegrityProtectedPurpose =
  | 'INITIAL_ENROLLMENT'
  | 'AUTH_1TO1'
  | 'REPLACE_FACE'
  | 'RECOVERY_CLAIM'
  | 'SENSITIVE_IDENTITY_CHANGE'
  | 'BIOMETRIC_ENROLLMENT'
  | 'BIOMETRIC_VERIFICATION_1TO1'
  | 'BIOMETRIC_REPLACEMENT'
  | 'DEVICE_REGISTRATION';

export interface PlayIntegrityBindingParamsV1 {
  readonly protocolVersion?: typeof PLAY_INTEGRITY_BINDING_PROTOCOL_V1;
  readonly packageName?: string;
  readonly authenticatedUid: string;
  readonly challengeId: string;
  readonly challengePurpose: PlayIntegrityProtectedPurpose;
  readonly serverNonce: string; // Plaintext server challenge nonce
  readonly idempotencyKey: string;
  readonly httpMethod: 'POST' | 'PUT';
  readonly route: string;
  readonly payloadDigestSha256: string; // SHA-256 hex or base64url digest of request body/vector
}

export interface PlayIntegrityBindingParamsV2 {
  readonly protocolVersion: typeof PLAY_INTEGRITY_BINDING_PROTOCOL_V2;
  readonly packageName?: string;
  readonly appVersion?: string;
  readonly authenticatedUid: string;
  readonly deviceKeyId: string;
  readonly challengeId: string;
  readonly challengePurpose: PlayIntegrityProtectedPurpose;
  readonly serverNonce: string;
  readonly idempotencyKey: string;
  readonly httpMethod: 'POST' | 'PUT';
  readonly route: string;
  readonly payloadDigestSha256: string; // SHA256(exact submitted image bytes)
}

export type PlayIntegrityBindingParams = PlayIntegrityBindingParamsV1 | PlayIntegrityBindingParamsV2;

/**
 * Length-prefixed canonical binary serialization of request binding context.
 * Guarantees 100% deterministic binary representation across languages (TypeScript & Dart),
 * completely immune to JSON key-ordering issues, whitespace, and delimiter collisions.
 */
export function serializeCanonicalBinding(params: PlayIntegrityBindingParams): Buffer {
  const isV2 = params.protocolVersion === PLAY_INTEGRITY_BINDING_PROTOCOL_V2;
  const protocol = params.protocolVersion ?? PLAY_INTEGRITY_BINDING_PROTOCOL_V1;
  const pkg = params.packageName ?? EXPECTED_PACKAGE_NAME;

  // Compute SHA-256 of server nonce to normalize representations
  const nonceHash = crypto
    .createHash('sha256')
    .update(params.serverNonce, 'utf8')
    .digest('hex');

  let fields: string[];

  if (isV2) {
    const v2Params = params as PlayIntegrityBindingParamsV2;
    fields = [
      protocol,
      pkg,
      v2Params.appVersion ?? '1.0.0',
      v2Params.authenticatedUid,
      v2Params.deviceKeyId,
      v2Params.challengeId,
      v2Params.challengePurpose,
      nonceHash,
      v2Params.httpMethod.toUpperCase(),
      v2Params.route.toLowerCase(),
      v2Params.idempotencyKey,
      v2Params.payloadDigestSha256,
    ];
  } else {
    fields = [
      protocol,
      pkg,
      params.authenticatedUid,
      params.challengeId,
      params.challengePurpose,
      nonceHash,
      params.idempotencyKey,
      params.httpMethod.toUpperCase(),
      params.route.toLowerCase(),
      params.payloadDigestSha256,
    ];
  }

  const buffers: Buffer[] = [];
  for (const field of fields) {
    const valBuf = Buffer.from(field, 'utf8');
    const lenBuf = Buffer.alloc(4);
    lenBuf.writeUInt32BE(valBuf.length, 0);
    buffers.push(lenBuf, valBuf);
  }

  return Buffer.concat(buffers);
}

/**
 * Computes the canonical requestHash string required by the Google Play Standard Integrity API.
 * Output: Base64Url-encoded SHA-256 digest (URL-safe, without padding '=').
 */
export function computePlayIntegrityRequestHash(params: PlayIntegrityBindingParams): string {
  const canonicalBytes = serializeCanonicalBinding(params);
  const hash = crypto.createHash('sha256').update(canonicalBytes).digest();
  // Standard base64url encoding (RFC 4648 section 5)
  return hash
    .toString('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}

/**
 * Validates that an incoming requestHash exactly matches the expected recomputed canonical digest.
 */
export function verifyPlayIntegrityRequestHash(
  clientRequestHash: string,
  params: PlayIntegrityBindingParams
): { valid: boolean; expectedRequestHash: string; reason?: string } {
  if (!clientRequestHash || typeof clientRequestHash !== 'string') {
    return {
      valid: false,
      expectedRequestHash: '',
      reason: 'MISSING_CLIENT_REQUEST_HASH',
    };
  }

  const expectedRequestHash = computePlayIntegrityRequestHash(params);
  const bufA = crypto.createHash('sha256').update(clientRequestHash).digest();
  const bufB = crypto.createHash('sha256').update(expectedRequestHash).digest();
  const matches = crypto.timingSafeEqual(bufA, bufB);

  if (!matches) {
    return {
      valid: false,
      expectedRequestHash,
      reason: 'REQUEST_HASH_MISMATCH',
    };
  }

  return {
    valid: true,
    expectedRequestHash,
  };
}

/**
 * Computes a standardized SHA-256 hex digest for arbitrary bytes (e.g. raw image capture bytes).
 */
export function computePayloadDigest(data: Float32Array | Buffer | string): string {
  if (data instanceof Float32Array) {
    const buf = Buffer.alloc(data.length * 4);
    for (let i = 0; i < data.length; i++) {
      buf.writeFloatLE(data[i], i * 4);
    }
    return crypto.createHash('sha256').update(buf).digest('hex');
  }

  if (Buffer.isBuffer(data)) {
    return crypto.createHash('sha256').update(data).digest('hex');
  }

  return crypto.createHash('sha256').update(data, 'utf8').digest('hex');
}
