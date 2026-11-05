// File: backend/src/services/biometric_template_crypto.ts
/**
 * KELASAGARA V20.1 — Phase 20.1: Zero-Plaintext Biometric Vault Cryptographic Service
 *
 * Implements authenticated envelope encryption for 128-D biometric embeddings:
 * - Cipher: AES-256-GCM with 96-bit random IV and 128-bit authentication tag.
 * - Key Management: Unique 256-bit ephemeral DEK wrapped via Google Cloud KMS KEK.
 * - Authenticated Additional Data (AAD): Canonical length-prefixed binary structure
 *   binding tenant, collection, template ID, owner UID, model ID, and schema version.
 * - Lossless Serialization: IEEE-754 Float32 Little-Endian binary layout (512 bytes).
 */

import * as crypto from 'node:crypto';
import {
  KmsKeyProvider,
  CloudKmsKeyProvider,
  LocalDevKeyProvider,
  CANONICAL_SFACE_MODEL_ID,
  CANONICAL_SFACE_MODEL_VERSION,
  SFACE_EMBEDDING_DIMENSION,
} from '../crypto/cloud_kms_envelope';

export const BIOMETRIC_VAULT_SCHEMA_VERSION = 2 as const;
export const CANONICAL_ENCODING_FORMAT = 'FLOAT32_LE_V1' as const;
export const CANONICAL_CIPHER_ALGORITHM = 'AES-256-GCM' as const;
export const CANONICAL_AAD_PURPOSE = 'BIOMETRIC_VAULT_ENVELOPE_V2' as const;
export const DEFAULT_TENANT_ID = 'kelasagara-f127a' as const;

/**
 * Versioned Encrypted Envelope structure stored in Firestore `biometric_vault`.
 * Zero plaintext biometric vectors are stored alongside this envelope.
 */
export interface EncryptedBiometricEnvelopeV2 {
  readonly algorithm: typeof CANONICAL_CIPHER_ALGORITHM;
  readonly encoding: typeof CANONICAL_ENCODING_FORMAT;
  readonly ciphertextBase64: string;
  readonly ivBase64: string;
  readonly authTagBase64: string;
  readonly wrappedDekBase64: string;
  readonly kmsKeyVersion: string;
  readonly aadVersion: number;
  readonly envelopeVersion: typeof BIOMETRIC_VAULT_SCHEMA_VERSION;
  readonly createdAtEpochMs: number;
}

/**
 * Stable, non-mutable document and identity context bound into canonical AAD.
 */
export interface BiometricAadContext {
  readonly tenantId: string;
  readonly collection: 'biometric_vault';
  readonly templateId: string;
  readonly ownerUid: string;
  readonly modelId: string;
  readonly modelVersion: string;
  readonly schemaVersion: number;
  readonly purpose: typeof CANONICAL_AAD_PURPOSE;
}

/**
 * Result of encrypting a template ready for Firestore persistence.
 */
export interface EncryptedTemplatePersistencePackage {
  readonly schemaVersion: typeof BIOMETRIC_VAULT_SCHEMA_VERSION;
  readonly biometricEnvelope: EncryptedBiometricEnvelopeV2;
  readonly metadata: {
    readonly modelId: string;
    readonly modelVersion: string;
    readonly dimensions: number;
    readonly matchingSpace: 'SFACE_NEURAL_SPACE';
    readonly createdAtEpochMs: number;
  };
}

export class BiometricTemplateCryptoService {
  private static instance: BiometricTemplateCryptoService | null = null;
  private readonly keyProvider: KmsKeyProvider;
  private readonly defaultTenantId: string;

  constructor(keyProvider?: KmsKeyProvider, defaultTenantId: string = DEFAULT_TENANT_ID) {
    if (keyProvider) {
      this.keyProvider = keyProvider;
    } else {
      // Automatic environment provider selection:
      // If KMS key resource is configured and credentials exist, use CloudKmsKeyProvider.
      // Otherwise, use LocalDevKeyProvider for local dev and automated test suites.
      const kmsKeyName = process.env.BIOMETRIC_KMS_KEY_NAME;
      if (kmsKeyName && process.env.GOOGLE_APPLICATION_CREDENTIALS) {
        try {
          this.keyProvider = new CloudKmsKeyProvider(kmsKeyName);
        } catch {
          this.keyProvider = new LocalDevKeyProvider();
        }
      } else {
        this.keyProvider = new LocalDevKeyProvider();
      }
    }
    this.defaultTenantId = defaultTenantId;
  }

  public static getInstance(keyProvider?: KmsKeyProvider): BiometricTemplateCryptoService {
    if (!BiometricTemplateCryptoService.instance || keyProvider) {
      BiometricTemplateCryptoService.instance = new BiometricTemplateCryptoService(keyProvider);
    }
    return BiometricTemplateCryptoService.instance;
  }

  /**
   * Resets the singleton instance (useful in isolated unit test suites).
   */
  public static resetInstance(): void {
    BiometricTemplateCryptoService.instance = null;
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // A. encryptTemplate()
  // ─────────────────────────────────────────────────────────────────────────────
  /**
   * Validates, encodes, and encrypts a 128-D SFace embedding with a fresh DEK and AAD binding.
   */
  public async encryptTemplate(params: {
    readonly templateId: string;
    readonly ownerUid: string;
    readonly embedding128: Float32Array | readonly number[];
    readonly modelId?: string;
    readonly modelVersion?: string;
    readonly tenantId?: string;
    readonly nowMs?: number;
  }): Promise<EncryptedTemplatePersistencePackage> {
    const {
      templateId,
      ownerUid,
      embedding128,
      modelId = CANONICAL_SFACE_MODEL_ID,
      modelVersion = CANONICAL_SFACE_MODEL_VERSION,
      tenantId = this.defaultTenantId,
      nowMs = Date.now(),
    } = params;

    // 1. Validate vector before encryption (H)
    const validatedVector = this.validateVectorBeforeEncryption(embedding128);

    // 2. Validate template context (D)
    const context: BiometricAadContext = {
      tenantId,
      collection: 'biometric_vault',
      templateId,
      ownerUid,
      modelId,
      modelVersion,
      schemaVersion: BIOMETRIC_VAULT_SCHEMA_VERSION,
      purpose: CANONICAL_AAD_PURPOSE,
    };
    this.validateTemplateContext(context);

    // 3. Lossless binary serialization: 128 Float32 Little-Endian (512 bytes)
    const binaryPayload = this.serializeVectorFloat32LE(validatedVector);

    // 4. Generate fresh 256-bit DEK and 96-bit IV
    const plaintextDek = crypto.randomBytes(32);
    const iv = crypto.randomBytes(12);

    // 5. Construct canonical AAD
    const aadBuffer = this.constructCanonicalAadBuffer(context);

    try {
      // 6. Encrypt with AES-256-GCM
      const cipher = crypto.createCipheriv('aes-256-gcm', plaintextDek, iv);
      cipher.setAAD(aadBuffer);
      const ciphertext = Buffer.concat([cipher.update(binaryPayload), cipher.final()]);
      const authTag = cipher.getAuthTag();

      // 7. Wrap DEK via Cloud KMS KEK
      let wrapResult: { wrappedDek: Buffer; keyVersionName: string };
      try {
        wrapResult = await this.keyProvider.wrapKey(plaintextDek, aadBuffer);
      } catch (kmsErr: any) {
        throw this.handleKmsFailures(kmsErr, 'wrapKey');
      }

      const envelope: EncryptedBiometricEnvelopeV2 = {
        algorithm: CANONICAL_CIPHER_ALGORITHM,
        encoding: CANONICAL_ENCODING_FORMAT,
        ciphertextBase64: ciphertext.toString('base64'),
        ivBase64: iv.toString('base64'),
        authTagBase64: authTag.toString('base64'),
        wrappedDekBase64: wrapResult.wrappedDek.toString('base64'),
        kmsKeyVersion: wrapResult.keyVersionName,
        aadVersion: 1,
        envelopeVersion: BIOMETRIC_VAULT_SCHEMA_VERSION,
        createdAtEpochMs: nowMs,
      };

      return {
        schemaVersion: BIOMETRIC_VAULT_SCHEMA_VERSION,
        biometricEnvelope: envelope,
        metadata: {
          modelId,
          modelVersion,
          dimensions: SFACE_EMBEDDING_DIMENSION,
          matchingSpace: 'SFACE_NEURAL_SPACE',
          createdAtEpochMs: nowMs,
        },
      };
    } finally {
      // Ephemeral memory hygiene: zeroize plaintext DEK and binary buffer
      plaintextDek.fill(0);
      binaryPayload.fill(0);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // B. decryptTemplate()
  // ─────────────────────────────────────────────────────────────────────────────
  /**
   * Authenticates AAD, unwraps DEK via KMS, decrypts ciphertext, and returns the 128-D vector.
   */
  public async decryptTemplate(params: {
    readonly templateId: string;
    readonly ownerUid: string;
    readonly envelope: unknown;
    readonly modelId?: string;
    readonly modelVersion?: string;
    readonly tenantId?: string;
  }): Promise<Float32Array> {
    const {
      templateId,
      ownerUid,
      envelope,
      modelId = CANONICAL_SFACE_MODEL_ID,
      modelVersion = CANONICAL_SFACE_MODEL_VERSION,
      tenantId = this.defaultTenantId,
    } = params;

    // 1. Validate envelope structure (C)
    const validEnvelope = this.validateEncryptedEnvelope(envelope);

    // 2. Validate template context (D)
    const context: BiometricAadContext = {
      tenantId,
      collection: 'biometric_vault',
      templateId,
      ownerUid,
      modelId,
      modelVersion,
      schemaVersion: validEnvelope.envelopeVersion,
      purpose: CANONICAL_AAD_PURPOSE,
    };
    this.validateTemplateContext(context);

    // 3. Reconstruct canonical AAD buffer independently from trusted context
    const aadBuffer = this.constructCanonicalAadBuffer(context);

    const wrappedDek = Buffer.from(validEnvelope.wrappedDekBase64, 'base64');
    const iv = Buffer.from(validEnvelope.ivBase64, 'base64');
    const authTag = Buffer.from(validEnvelope.authTagBase64, 'base64');
    const ciphertext = Buffer.from(validEnvelope.ciphertextBase64, 'base64');

    // 4. Verify envelope structural integrity (F)
    this.verifyEnvelopeIntegrity({ wrappedDek, iv, authTag, ciphertext });

    let plaintextDek: Buffer | null = null;
    let decryptedPayload: Buffer | null = null;

    try {
      // 5. Unwrap DEK via KMS
      try {
        plaintextDek = await this.keyProvider.unwrapKey(
          wrappedDek,
          aadBuffer,
          validEnvelope.kmsKeyVersion,
        );
      } catch (kmsErr: any) {
        throw this.handleKmsFailures(kmsErr, 'unwrapKey');
      }

      // 6. Decrypt and authenticate GCM tag + AAD
      const decipher = crypto.createDecipheriv('aes-256-gcm', plaintextDek, iv);
      decipher.setAAD(aadBuffer);
      decipher.setAuthTag(authTag);

      decryptedPayload = Buffer.concat([
        decipher.update(ciphertext),
        decipher.final(),
      ]);

      // 7. Deserialize binary Float32 LE buffer
      const rawVector = this.deserializeVectorFloat32LE(decryptedPayload);

      // 8. Validate vector after decryption (I)
      return this.validateVectorAfterDecryption(rawVector);
    } catch (err: any) {
      if (err.name === 'BiometricCryptoError') {
        throw err;
      }
      throw new BiometricCryptoError(
        'AUTHENTICATION_TAG_VERIFICATION_FAILED',
        `Ciphertext or AAD authentication failed: ${err.message}`,
        false,
      );
    } finally {
      if (plaintextDek) plaintextDek.fill(0);
      if (decryptedPayload) decryptedPayload.fill(0);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // C. validateEncryptedEnvelope()
  // ─────────────────────────────────────────────────────────────────────────────
  /**
   * Asserts that an unknown object conforms strictly to the EncryptedBiometricEnvelopeV2 schema.
   */
  public validateEncryptedEnvelope(envelope: unknown): EncryptedBiometricEnvelopeV2 {
    if (!envelope || typeof envelope !== 'object') {
      throw new BiometricCryptoError(
        'INVALID_ENVELOPE_SCHEMA',
        'Biometric envelope must be a non-null object.',
        false,
      );
    }
    const env = envelope as Record<string, unknown>;

    if (env.algorithm !== CANONICAL_CIPHER_ALGORITHM) {
      throw new BiometricCryptoError(
        'UNSUPPORTED_CIPHER_ALGORITHM',
        `Envelope algorithm must be ${CANONICAL_CIPHER_ALGORITHM}, got ${env.algorithm}`,
        false,
      );
    }

    if (env.encoding !== CANONICAL_ENCODING_FORMAT) {
      throw new BiometricCryptoError(
        'UNSUPPORTED_ENCODING_FORMAT',
        `Envelope encoding must be ${CANONICAL_ENCODING_FORMAT}, got ${env.encoding}`,
        false,
      );
    }

    if (env.envelopeVersion !== BIOMETRIC_VAULT_SCHEMA_VERSION) {
      throw new BiometricCryptoError(
        'UNSUPPORTED_ENVELOPE_VERSION',
        `Envelope version must be ${BIOMETRIC_VAULT_SCHEMA_VERSION}, got ${env.envelopeVersion}`,
        false,
      );
    }

    const requiredStringFields = [
      'ciphertextBase64',
      'ivBase64',
      'authTagBase64',
      'wrappedDekBase64',
      'kmsKeyVersion',
    ];
    for (const field of requiredStringFields) {
      if (typeof env[field] !== 'string' || (env[field] as string).trim().length === 0) {
        throw new BiometricCryptoError(
          'MALFORMED_ENVELOPE_FIELD',
          `Envelope field '${field}' must be a non-empty string.`,
          false,
        );
      }
    }

    return env as unknown as EncryptedBiometricEnvelopeV2;
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // D. validateTemplateContext()
  // ─────────────────────────────────────────────────────────────────────────────
  /**
   * Validates that all context fields used to build AAD are well-formed and non-empty.
   */
  public validateTemplateContext(context: BiometricAadContext): void {
    if (!context.tenantId || typeof context.tenantId !== 'string') {
      throw new BiometricCryptoError('INVALID_CONTEXT_TENANT', 'Valid tenantId is required.');
    }
    if (context.collection !== 'biometric_vault') {
      throw new BiometricCryptoError('INVALID_CONTEXT_COLLECTION', 'Collection must be biometric_vault.');
    }
    if (!context.templateId || typeof context.templateId !== 'string') {
      throw new BiometricCryptoError('INVALID_CONTEXT_TEMPLATE_ID', 'Valid templateId is required.');
    }
    if (!context.ownerUid || typeof context.ownerUid !== 'string') {
      throw new BiometricCryptoError('INVALID_CONTEXT_OWNER_UID', 'Valid ownerUid is required.');
    }
    if (!context.modelId || typeof context.modelId !== 'string') {
      throw new BiometricCryptoError('INVALID_CONTEXT_MODEL_ID', 'Valid modelId is required.');
    }
    if (!context.modelVersion || typeof context.modelVersion !== 'string') {
      throw new BiometricCryptoError('INVALID_CONTEXT_MODEL_VERSION', 'Valid modelVersion is required.');
    }
    if (context.schemaVersion !== BIOMETRIC_VAULT_SCHEMA_VERSION) {
      throw new BiometricCryptoError('INVALID_CONTEXT_SCHEMA_VERSION', 'schemaVersion must match current vault version.');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // E. getKeyVersion()
  // ─────────────────────────────────────────────────────────────────────────────
  /**
   * Resolves the KMS key version recorded on an envelope.
   */
  public getKeyVersion(envelope: EncryptedBiometricEnvelopeV2): string {
    return envelope.kmsKeyVersion;
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // F. verifyEnvelopeIntegrity()
  // ─────────────────────────────────────────────────────────────────────────────
  /**
   * Verifies byte lengths of cryptographic components before attempting cipher operations.
   */
  public verifyEnvelopeIntegrity(params: {
    readonly wrappedDek: Buffer;
    readonly iv: Buffer;
    readonly authTag: Buffer;
    readonly ciphertext: Buffer;
  }): void {
    if (params.iv.byteLength !== 12) {
      throw new BiometricCryptoError(
        'INVALID_IV_LENGTH',
        `AES-256-GCM IV must be exactly 12 bytes (96 bits), got ${params.iv.byteLength}`,
        false,
      );
    }
    if (params.authTag.byteLength !== 16) {
      throw new BiometricCryptoError(
        'INVALID_AUTH_TAG_LENGTH',
        `AES-256-GCM authTag must be exactly 16 bytes (128 bits), got ${params.authTag.byteLength}`,
        false,
      );
    }
    if (params.wrappedDek.byteLength < 32) {
      throw new BiometricCryptoError(
        'INVALID_WRAPPED_DEK_LENGTH',
        `Wrapped DEK must be at least 32 bytes, got ${params.wrappedDek.byteLength}`,
        false,
      );
    }
    if (params.ciphertext.byteLength !== 512) {
      throw new BiometricCryptoError(
        'INVALID_CIPHERTEXT_LENGTH',
        `Encrypted 128-D Float32 vector must be exactly 512 bytes, got ${params.ciphertext.byteLength}`,
        false,
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // G. handleKmsFailures()
  // ─────────────────────────────────────────────────────────────────────────────
  /**
   * Maps lower-level KMS errors into structured fail-closed BiometricCryptoError objects.
   */
  public handleKmsFailures(err: any, operation: 'wrapKey' | 'unwrapKey'): BiometricCryptoError {
    const msg = (err?.message || 'Unknown KMS failure').toLowerCase();
    const isRetryable =
      msg.includes('unavailable') ||
      msg.includes('timeout') ||
      msg.includes('deadline') ||
      msg.includes('econnreset') ||
      msg.includes('resource_exhausted');

    return new BiometricCryptoError(
      `KMS_${operation.toUpperCase()}_FAILURE`,
      `KMS ${operation} failed: ${err?.message || 'Service unavailable'}`,
      isRetryable,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // H. validateVectorBeforeEncryption()
  // ─────────────────────────────────────────────────────────────────────────────
  /**
   * Asserts that a feature vector is finite, 128-D, and L2 unit-normalized prior to encryption.
   */
  public validateVectorBeforeEncryption(rawVector: unknown): Float32Array {
    if (!rawVector || (!Array.isArray(rawVector) && !(rawVector instanceof Float32Array))) {
      throw new BiometricCryptoError(
        'INVALID_VECTOR_TYPE',
        'Embedding vector must be a Float32Array or number array.',
        false,
      );
    }

    if (rawVector.length !== SFACE_EMBEDDING_DIMENSION) {
      throw new BiometricCryptoError(
        'INVALID_VECTOR_DIMENSION',
        `Expected ${SFACE_EMBEDDING_DIMENSION} dimensions, got ${rawVector.length}`,
        false,
      );
    }

    const out = new Float32Array(SFACE_EMBEDDING_DIMENSION);
    let normSq = 0.0;

    for (let i = 0; i < SFACE_EMBEDDING_DIMENSION; i++) {
      const val = Number(rawVector[i]);
      if (!Number.isFinite(val)) {
        throw new BiometricCryptoError(
          'NON_FINITE_VECTOR_VALUE',
          `Non-finite numerical value at index ${i}`,
          false,
        );
      }
      out[i] = val;
      normSq += val * val;
    }

    const norm = Math.sqrt(normSq);
    if (norm < 1e-12) {
      throw new BiometricCryptoError('ZERO_NORM_VECTOR', 'Vector has zero magnitude.', false);
    }

    // Unit hypersphere normalization tolerance (+/- 0.05)
    if (Math.abs(norm - 1.0) > 0.05) {
      throw new BiometricCryptoError(
        'UNNORMALIZED_VECTOR',
        `L2 norm ${norm.toFixed(6)} deviates from unit hypersphere (tolerance +/-0.05).`,
        false,
      );
    }

    // Re-normalize to exact unit L2 float precision
    const invNorm = 1.0 / norm;
    for (let i = 0; i < SFACE_EMBEDDING_DIMENSION; i++) {
      out[i] *= invNorm;
    }
    return out;
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // I. validateVectorAfterDecryption()
  // ─────────────────────────────────────────────────────────────────────────────
  /**
   * Validates vector numerical sanity after decryption to guard against corruption or tampering.
   */
  public validateVectorAfterDecryption(vector: Float32Array): Float32Array {
    if (vector.length !== SFACE_EMBEDDING_DIMENSION) {
      throw new BiometricCryptoError(
        'DECRYPTED_VECTOR_DIMENSION_MISMATCH',
        `Decrypted vector expected ${SFACE_EMBEDDING_DIMENSION} dimensions, got ${vector.length}`,
        false,
      );
    }

    let normSq = 0.0;
    for (let i = 0; i < SFACE_EMBEDDING_DIMENSION; i++) {
      const val = vector[i];
      if (!Number.isFinite(val)) {
        throw new BiometricCryptoError(
          'DECRYPTED_VECTOR_NON_FINITE',
          `Decrypted vector contains non-finite float at index ${i}`,
          false,
        );
      }
      normSq += val * val;
    }

    const norm = Math.sqrt(normSq);
    if (norm < 1e-6 || Math.abs(norm - 1.0) > 0.05) {
      throw new BiometricCryptoError(
        'DECRYPTED_VECTOR_NORM_CORRUPTED',
        `Decrypted vector norm ${norm.toFixed(6)} indicates corrupted embedding.`,
        false,
      );
    }
    return vector;
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Internal Helpers: Serialization & Canonical AAD
  // ─────────────────────────────────────────────────────────────────────────────

  /**
   * Serializes 128 Float32 values into a 512-byte Little-Endian buffer.
   */
  private serializeVectorFloat32LE(vector: Float32Array): Buffer {
    const buf = Buffer.allocUnsafe(512);
    const view = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
    for (let i = 0; i < SFACE_EMBEDDING_DIMENSION; i++) {
      view.setFloat32(i * 4, vector[i], true); // Little-Endian
    }
    return buf;
  }

  /**
   * Deserializes a 512-byte Little-Endian buffer into a Float32Array(128).
   */
  private deserializeVectorFloat32LE(buf: Buffer): Float32Array {
    if (buf.byteLength !== 512) {
      throw new BiometricCryptoError(
        'CORRUPTED_SERIALIZATION_LENGTH',
        `Expected 512 bytes for 128 Float32 values, got ${buf.byteLength}`,
        false,
      );
    }
    const view = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
    const vector = new Float32Array(SFACE_EMBEDDING_DIMENSION);
    for (let i = 0; i < SFACE_EMBEDDING_DIMENSION; i++) {
      vector[i] = view.getFloat32(i * 4, true); // Little-Endian
    }
    return vector;
  }

  /**
   * Constructs length-prefixed canonical AAD buffer to eliminate delimiter collisions.
   */
  private constructCanonicalAadBuffer(context: BiometricAadContext): Buffer {
    const fields = [
      Buffer.from(context.purpose, 'utf8'),
      Buffer.from(context.tenantId, 'utf8'),
      Buffer.from(context.collection, 'utf8'),
      Buffer.from(context.templateId, 'utf8'),
      Buffer.from(context.ownerUid, 'utf8'),
      Buffer.from(context.modelId, 'utf8'),
      Buffer.from(context.modelVersion, 'utf8'),
      Buffer.from(String(context.schemaVersion), 'utf8'),
    ];

    const totalBytes = fields.reduce((sum, f) => sum + 4 + f.byteLength, 0);
    const aadBuf = Buffer.allocUnsafe(totalBytes);

    let offset = 0;
    for (const field of fields) {
      aadBuf.writeUInt32BE(field.byteLength, offset);
      offset += 4;
      field.copy(aadBuf, offset);
      offset += field.byteLength;
    }
    return aadBuf;
  }
}

export class BiometricCryptoError extends Error {
  public readonly code: string;
  public readonly retryable: boolean;

  constructor(code: string, message: string, retryable = false) {
    super(`[${code}] ${message}`);
    this.name = 'BiometricCryptoError';
    this.code = code;
    this.retryable = retryable;
  }
}
