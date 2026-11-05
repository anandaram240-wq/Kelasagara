// File: backend/src/crypto/cloud_kms_envelope.ts
// KELASAGARA V18 — Gate G-03 & G-04: Canonical SFace 128-D Cloud KMS HSM Envelope Encryption
// Release Status: CONTROLLED_TEST_BUILD_ONLY | productionBiometricCalibrationApproved = false

import * as crypto from 'node:crypto';
import { KeyManagementServiceClient } from '@google-cloud/kms';

export const PRODUCTION_BIOMETRIC_CALIBRATION_APPROVED = false as const;
export const RELEASE_STATUS = 'CONTROLLED_TEST_BUILD_ONLY' as const;

export const CANONICAL_SFACE_MODEL_ID = 'face_recognition_sface_2021dec' as const;
export const CANONICAL_SFACE_MODEL_VERSION = 'sface_2021dec_128d_v1' as const;
export const CANONICAL_TEMPLATE_SCHEMA_VERSION = 3 as const;
export const SFACE_EMBEDDING_DIMENSION = 128 as const;

/**
 * Binary layout:
 * - [0..511]:   128 Float32 Little-Endian L2-normalized SFace embedding (512 bytes)
 * - [512..515]: 1 Float32 Little-Endian ISO/IEC 29794-5 capture quality score [0..100] (4 bytes)
 * - [516..519]: 1 Float32 Little-Endian ISO/IEC 30107-3 PAD liveness score [0..1] (4 bytes)
 * Total = 520 bytes.
 */
export const SFACE_V3_BINARY_PAYLOAD_BYTES = 520 as const;

export interface CanonicalAadContext {
  readonly uid: string;
  readonly modelVersion: string;
  readonly templateSchemaVersion: number;
  readonly tenantId: string;
  readonly purpose: 'BIOMETRIC_VAULT_SFACE_V3';
}

export interface BiometricPlaintextSfacePayloadV3 {
  readonly sfaceEmbedding128: Float32Array;
  readonly isoQualityScore: number;
  readonly padLivenessScore: number;
}

export interface EncryptedBiometricEnvelopeV3 {
  readonly schemaVersion: typeof CANONICAL_TEMPLATE_SCHEMA_VERSION;
  readonly modelId: typeof CANONICAL_SFACE_MODEL_ID;
  readonly modelVersion: typeof CANONICAL_SFACE_MODEL_VERSION;
  readonly dimensions: typeof SFACE_EMBEDDING_DIMENSION;
  readonly kmsKeyVersionName: string;
  readonly wrappedDekBase64: string;
  readonly ivBase64: string;
  readonly authTagBase64: string;
  readonly ciphertextBase64: string;
  readonly createdAtEpochMs: number;
}

export interface KmsKeyProvider {
  wrapKey(
    plaintextDek: Buffer,
    aad: Buffer,
  ): Promise<{ wrappedDek: Buffer; keyVersionName: string }>;
  unwrapKey(
    wrappedDek: Buffer,
    aad: Buffer,
    keyVersionName: string,
  ): Promise<Buffer>;
}

/**
 * Validates that a candidate vector is a genuine 128-D finite L2-normalized SFace embedding.
 * Rejects empty arrays, wrong dimensions (e.g. 512-D or 256-D landmark vectors), NaN/Infinity,
 * and unnormalized vectors whose L2 norm deviates from 1.0 by more than tolerance (1e-3).
 */
export function assertValidCanonicalSfaceEmbedding(
  embedding: unknown,
  contextLabel = 'sfaceEmbedding128',
  normTolerance = 1e-3,
): Float32Array {
  if (
    !(embedding instanceof Float32Array) &&
    !Array.isArray(embedding)
  ) {
    throw new Error(
      `INVALID_SFACE_VECTOR_TYPE: ${contextLabel} must be a Float32Array or number array.`,
    );
  }

  if (embedding.length !== SFACE_EMBEDDING_DIMENSION) {
    throw new Error(
      `INVALID_SFACE_DIMENSION: ${contextLabel} expected ${SFACE_EMBEDDING_DIMENSION} dimensions, got ${embedding.length}. Landmark or non-SFace vectors are rejected.`,
    );
  }

  const out = new Float32Array(SFACE_EMBEDDING_DIMENSION);
  let normSq = 0.0;
  for (let i = 0; i < SFACE_EMBEDDING_DIMENSION; i++) {
    const v = Number(embedding[i]);
    if (!Number.isFinite(v)) {
      throw new Error(
        `NON_FINITE_SFACE_VALUE: ${contextLabel} contains non-finite value at index ${i}.`,
      );
    }
    out[i] = v;
    normSq += v * v;
  }

  const norm = Math.sqrt(normSq);
  if (norm < 1e-12) {
    throw new Error(
      `ZERO_NORM_SFACE_VECTOR: ${contextLabel} has zero L2 norm.`,
    );
  }

  if (Math.abs(norm - 1.0) > normTolerance) {
    throw new Error(
      `UNNORMALIZED_SFACE_VECTOR: ${contextLabel} L2 norm is ${norm.toFixed(6)}, expected 1.0 (+/- ${normTolerance}).`,
    );
  }

  // Re-normalize to Float32 unit precision
  const invNorm = 1.0 / norm;
  for (let i = 0; i < SFACE_EMBEDDING_DIMENSION; i++) {
    out[i] *= invNorm;
  }
  return out;
}

/**
 * Normalizes a raw 128-D SFace model output vector onto the unit hypersphere S^127.
 */
export function l2NormalizeSfaceVector(raw128: Float32Array | readonly number[]): Float32Array {
  if (!raw128 || raw128.length !== SFACE_EMBEDDING_DIMENSION) {
    throw new Error(
      `INVALID_SFACE_DIMENSION: Expected ${SFACE_EMBEDDING_DIMENSION} floats, got ${raw128 ? raw128.length : 0}.`,
    );
  }
  const out = new Float32Array(SFACE_EMBEDDING_DIMENSION);
  let normSq = 0.0;
  for (let i = 0; i < SFACE_EMBEDDING_DIMENSION; i++) {
    const val = Number(raw128[i]);
    if (!Number.isFinite(val)) {
      throw new Error(`NON_FINITE_SFACE_VALUE: Non-finite float at index ${i}.`);
    }
    out[i] = val;
    normSq += val * val;
  }
  if (normSq < 1e-12) {
    throw new Error('ZERO_NORM_SFACE_VECTOR: Cannot normalize all-zero vector.');
  }
  const inv = 1.0 / Math.sqrt(normSq);
  for (let i = 0; i < SFACE_EMBEDDING_DIMENSION; i++) {
    out[i] *= inv;
  }
  return out;
}

/**
 * Encodes AAD fields using Big-Endian 32-bit length prefixes to prevent delimiter collisions.
 */
export function encodeCanonicalAad(ctx: CanonicalAadContext): Buffer {
  if (!ctx.uid || !ctx.tenantId || !ctx.modelVersion) {
    throw new Error('INVALID_AAD_CONTEXT: uid, tenantId, and modelVersion are required.');
  }
  const fields = [
    Buffer.from(ctx.purpose, 'utf8'),
    Buffer.from(ctx.tenantId, 'utf8'),
    Buffer.from(ctx.uid, 'utf8'),
    Buffer.from(ctx.modelVersion, 'utf8'),
    Buffer.from(String(ctx.templateSchemaVersion), 'utf8'),
  ];

  const totalBytes = fields.reduce((acc, buf) => acc + 4 + buf.byteLength, 0);
  const out = Buffer.allocUnsafe(totalBytes);

  let offset = 0;
  for (const field of fields) {
    out.writeUInt32BE(field.byteLength, offset);
    offset += 4;
    field.copy(out, offset);
    offset += field.byteLength;
  }
  return out;
}

/**
 * Packs a validated 128-D SFace embedding + quality/PAD metadata into a 520-byte Little-Endian frame.
 */
export function packSfacePayloadV3(payload: BiometricPlaintextSfacePayloadV3): Buffer {
  const validatedVec = assertValidCanonicalSfaceEmbedding(
    payload.sfaceEmbedding128,
    'packSfacePayloadV3.sfaceEmbedding128',
  );
  if (
    !Number.isFinite(payload.isoQualityScore) ||
    payload.isoQualityScore < 0.0 ||
    payload.isoQualityScore > 100.0
  ) {
    throw new Error('INVALID_QUALITY_SCORE: isoQualityScore must be in [0.0, 100.0].');
  }
  if (
    !Number.isFinite(payload.padLivenessScore) ||
    payload.padLivenessScore < 0.0 ||
    payload.padLivenessScore > 1.0
  ) {
    throw new Error('INVALID_PAD_SCORE: padLivenessScore must be in [0.0, 1.0].');
  }

  const buf = Buffer.allocUnsafe(SFACE_V3_BINARY_PAYLOAD_BYTES);
  const view = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);

  let offset = 0;
  for (let i = 0; i < SFACE_EMBEDDING_DIMENSION; i++) {
    view.setFloat32(offset, validatedVec[i], true);
    offset += 4;
  }
  view.setFloat32(offset, payload.isoQualityScore, true);
  offset += 4;
  view.setFloat32(offset, payload.padLivenessScore, true);

  return buf;
}

/**
 * Unpacks a 520-byte Little-Endian binary frame and validates the 128-D SFace vector.
 */
export function unpackSfacePayloadV3(buf: Buffer): BiometricPlaintextSfacePayloadV3 {
  if (buf.byteLength !== SFACE_V3_BINARY_PAYLOAD_BYTES) {
    throw new Error(
      `CORRUPTED_SFACE_PAYLOAD_BYTES: Expected ${SFACE_V3_BINARY_PAYLOAD_BYTES} bytes, got ${buf.byteLength}.`,
    );
  }

  const view = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
  const rawVec = new Float32Array(SFACE_EMBEDDING_DIMENSION);

  let offset = 0;
  for (let i = 0; i < SFACE_EMBEDDING_DIMENSION; i++) {
    rawVec[i] = view.getFloat32(offset, true);
    offset += 4;
  }
  const isoQualityScore = view.getFloat32(offset, true);
  offset += 4;
  const padLivenessScore = view.getFloat32(offset, true);

  const sfaceEmbedding128 = assertValidCanonicalSfaceEmbedding(
    rawVec,
    'unpackSfacePayloadV3.sfaceEmbedding128',
  );

  return {
    sfaceEmbedding128,
    isoQualityScore,
    padLivenessScore,
  };
}

export class CloudKmsKeyProvider implements KmsKeyProvider {
  private readonly client: KeyManagementServiceClient;
  private readonly cryptoKeyName: string;

  constructor(cryptoKeyName: string, client?: KeyManagementServiceClient) {
    if (!cryptoKeyName.includes('/cryptoKeys/')) {
      throw new Error(`Invalid Cloud KMS CryptoKey resource path: ${cryptoKeyName}`);
    }
    this.cryptoKeyName = cryptoKeyName;
    this.client = client ?? new KeyManagementServiceClient();
  }

  public async wrapKey(
    plaintextDek: Buffer,
    aad: Buffer,
  ): Promise<{ wrappedDek: Buffer; keyVersionName: string }> {
    const [response] = await this.client.encrypt({
      name: this.cryptoKeyName,
      plaintext: plaintextDek,
      additionalAuthenticatedData: aad,
    });

    if (!response.ciphertext || !response.name) {
      throw new Error('KMS_ENCRYPT_FAILURE: Cloud KMS failed to return ciphertext.');
    }

    return {
      wrappedDek: Buffer.from(response.ciphertext as Uint8Array),
      keyVersionName: response.name,
    };
  }

  public async unwrapKey(
    wrappedDek: Buffer,
    aad: Buffer,
    _keyVersionName: string,
  ): Promise<Buffer> {
    const [response] = await this.client.decrypt({
      name: this.cryptoKeyName,
      ciphertext: wrappedDek,
      additionalAuthenticatedData: aad,
    });

    if (!response.plaintext) {
      throw new Error('KMS_DECRYPT_FAILURE: Cloud KMS failed to return plaintext DEK.');
    }

    return Buffer.from(response.plaintext as Uint8Array);
  }
}

export class LocalDevKeyProvider implements KmsKeyProvider {
  private readonly masterKek: Buffer;
  private readonly keyVersionName: string;

  constructor(
    hexKey = '4b656c61736167616172614465764d61737465724b65795f323032365f48534d',
    keyVersionName = 'projects/kelasagaara-dev/locations/asia-south1/keyRings/kelasagara-biometric-vault-ring/cryptoKeys/biometric-kek/cryptoKeyVersions/1',
  ) {
    this.masterKek = Buffer.from(hexKey, 'hex');
    if (this.masterKek.byteLength !== 32) {
      throw new Error('LocalDevKeyProvider requires a 32-byte hex master key.');
    }
    this.keyVersionName = keyVersionName;
  }

  public async wrapKey(
    plaintextDek: Buffer,
    aad: Buffer,
  ): Promise<{ wrappedDek: Buffer; keyVersionName: string }> {
    const iv = crypto.randomBytes(12);
    const cipher = crypto.createCipheriv('aes-256-gcm', this.masterKek, iv);
    cipher.setAAD(aad);
    const enc = Buffer.concat([cipher.update(plaintextDek), cipher.final()]);
    const tag = cipher.getAuthTag();

    return {
      wrappedDek: Buffer.concat([iv, tag, enc]),
      keyVersionName: this.keyVersionName,
    };
  }

  public async unwrapKey(
    wrappedDek: Buffer,
    aad: Buffer,
    _keyVersionName: string,
  ): Promise<Buffer> {
    if (wrappedDek.byteLength < 28) {
      throw new Error('KMS_UNWRAP_FAILURE: Malformed wrapped DEK buffer.');
    }
    const iv = wrappedDek.subarray(0, 12);
    const tag = wrappedDek.subarray(12, 28);
    const ciphertext = wrappedDek.subarray(28);

    const decipher = crypto.createDecipheriv('aes-256-gcm', this.masterKek, iv);
    decipher.setAAD(aad);
    decipher.setAuthTag(tag);
    return Buffer.concat([decipher.update(ciphertext), decipher.final()]);
  }
}

export class CloudKmsEnvelopeService {
  private readonly keyProvider: KmsKeyProvider;

  constructor(keyProvider: KmsKeyProvider) {
    this.keyProvider = keyProvider;
  }

  public async sealTemplateV3(
    payload: BiometricPlaintextSfacePayloadV3,
    aadContext: CanonicalAadContext,
  ): Promise<EncryptedBiometricEnvelopeV3> {
    if (aadContext.modelVersion !== CANONICAL_SFACE_MODEL_VERSION) {
      throw new Error(
        `UNSUPPORTED_MODEL_VERSION: Expected ${CANONICAL_SFACE_MODEL_VERSION}, got ${aadContext.modelVersion}.`,
      );
    }
    if (aadContext.templateSchemaVersion !== CANONICAL_TEMPLATE_SCHEMA_VERSION) {
      throw new Error(
        `UNSUPPORTED_SCHEMA_VERSION: Expected ${CANONICAL_TEMPLATE_SCHEMA_VERSION}, got ${aadContext.templateSchemaVersion}.`,
      );
    }

    const aadBuffer = encodeCanonicalAad(aadContext);
    const plaintextDek = crypto.randomBytes(32);
    const iv = crypto.randomBytes(12);
    const packedPlaintext = packSfacePayloadV3(payload);

    try {
      const cipher = crypto.createCipheriv('aes-256-gcm', plaintextDek, iv);
      cipher.setAAD(aadBuffer);
      const ciphertext = Buffer.concat([
        cipher.update(packedPlaintext),
        cipher.final(),
      ]);
      const authTag = cipher.getAuthTag();

      const { wrappedDek, keyVersionName } = await this.keyProvider.wrapKey(
        plaintextDek,
        aadBuffer,
      );

      return {
        schemaVersion: CANONICAL_TEMPLATE_SCHEMA_VERSION,
        modelId: CANONICAL_SFACE_MODEL_ID,
        modelVersion: CANONICAL_SFACE_MODEL_VERSION,
        dimensions: SFACE_EMBEDDING_DIMENSION,
        kmsKeyVersionName: keyVersionName,
        wrappedDekBase64: wrappedDek.toString('base64'),
        ivBase64: iv.toString('base64'),
        authTagBase64: authTag.toString('base64'),
        ciphertextBase64: ciphertext.toString('base64'),
        createdAtEpochMs: Date.now(),
      };
    } finally {
      // Best-effort zeroization in Node/V8 managed memory
      plaintextDek.fill(0);
      packedPlaintext.fill(0);
    }
  }

  public async unsealTemplateV3(
    envelope: EncryptedBiometricEnvelopeV3,
    expectedAadContext: CanonicalAadContext,
  ): Promise<BiometricPlaintextSfacePayloadV3> {
    if (
      envelope.modelVersion !== CANONICAL_SFACE_MODEL_VERSION ||
      envelope.modelId !== CANONICAL_SFACE_MODEL_ID ||
      envelope.schemaVersion !== CANONICAL_TEMPLATE_SCHEMA_VERSION ||
      envelope.dimensions !== SFACE_EMBEDDING_DIMENSION
    ) {
      throw new Error(
        `INCOMPATIBLE_ENVELOPE_VERSION: Envelope (${envelope.modelId}/${envelope.modelVersion}/v${envelope.schemaVersion}/${envelope.dimensions}D) is incompatible with canonical SFace v3.`,
      );
    }

    const aadBuffer = encodeCanonicalAad(expectedAadContext);
    const wrappedDek = Buffer.from(envelope.wrappedDekBase64, 'base64');
    const iv = Buffer.from(envelope.ivBase64, 'base64');
    const authTag = Buffer.from(envelope.authTagBase64, 'base64');
    const ciphertext = Buffer.from(envelope.ciphertextBase64, 'base64');

    let plaintextDek: Buffer | null = null;
    let decryptedBuf: Buffer | null = null;

    try {
      plaintextDek = await this.keyProvider.unwrapKey(
        wrappedDek,
        aadBuffer,
        envelope.kmsKeyVersionName,
      );

      const decipher = crypto.createDecipheriv('aes-256-gcm', plaintextDek, iv);
      decipher.setAAD(aadBuffer);
      decipher.setAuthTag(authTag);

      decryptedBuf = Buffer.concat([
        decipher.update(ciphertext),
        decipher.final(),
      ]);
      return unpackSfacePayloadV3(decryptedBuf);
    } finally {
      if (plaintextDek) plaintextDek.fill(0);
      if (decryptedBuf) decryptedBuf.fill(0);
    }
  }
}

