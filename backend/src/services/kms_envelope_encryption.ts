// backend/src/services/kms_envelope_encryption.ts
/**
 * KELASAGARA V16.0: BIOMETRIC ENVELOPE ENCRYPTION SERVICE
 *
 * Implements ISO/IEC 24745 compliant template protection using AES-256-GCM
 * with Google Cloud KMS Key Encryption Key (KEK) wrapping Data Encryption Keys (DEKs).
 */

import crypto from 'crypto';
import { KeyProvider, LocalDevKeyProvider, CloudKmsKeyProvider, WrappedDekResult } from './kms_key_provider';

export interface KeyEncryptionProvider {
  readonly providerType: string;
  readonly defaultKeyResourceName?: string;
  wrapDataKey?(dek: Buffer): Promise<{
    wrappedDekBase64: string;
    kekResourceVersion: string;
    providerType: string;
  }>;
  unwrapDataKey?(wrappedBase64: string): Promise<Buffer>;
  wrapDek?(dek: Buffer, context: Buffer): Promise<WrappedDekResult>;
  unwrapDek?(wrappedDek: Buffer, context: Buffer, keyResourceName?: string): Promise<Buffer>;
}

export interface BiometricEnvelopeV16 {
  version: 'v16_kms_gcm';
  uid: string;
  tenantId: string;
  purpose: string;
  keyVersion: string;
  kmsKeyResourceName: string;
  wrappedDekBase64: string;
  ciphertextBase64: string;
  ivBase64: string;
  authTagBase64: string;
  encryptedAt: string;
  modelId?: string;
  templateSchemaVersion?: number;
}

export type EncryptedBiometricEnvelope = BiometricEnvelopeV16;

export class BiometricEnvelopeEncryptionService {
  public static readonly AAD_PREFIX = 'kelasagara-biometric-v16';
  public static readonly DEFAULT_PURPOSE = 'biometric_template';
  public static readonly DEFAULT_TENANT = 'kelasagara-primary';

  private provider: KeyEncryptionProvider;

  constructor(provider?: KeyEncryptionProvider, private readonly envName?: string) {
    this.provider = provider || new LocalDevKeyProvider();
    this.assertEnvironmentSafety(this.provider);
  }

  public assertEnvironmentSafety(provider: KeyEncryptionProvider): void {
    const env = this.envName || process.env.NODE_ENV || 'development';
    const isRestrictedEnv = env === 'production' || env === 'staging';
    const isLocalProvider = provider.providerType === 'local' || provider.providerType === 'LOCAL_DEV';
    const allowBypass = process.env.ALLOW_LOCAL_DEV_KMS_IN_NON_PROD === 'true';

    if (isRestrictedEnv && isLocalProvider && !allowBypass) {
      throw new Error(
        `[BiometricEnvelopeEncryptionService] KMS_ENVIRONMENT_SECURITY_ERROR: ` +
          `LocalDevKeyProvider is strictly forbidden in environment '${env}'. ` +
          `Production/Staging environments must configure CloudKmsKeyProvider with active GCP KMS credentials.`
      );
    }
  }

  public setProvider(provider: KeyEncryptionProvider): void {
    this.assertEnvironmentSafety(provider);
    this.provider = provider;
  }

  public getProvider(): KeyEncryptionProvider {
    return this.provider;
  }

  public buildPayloadAad(
    uid: string,
    purpose: string = BiometricEnvelopeEncryptionService.DEFAULT_PURPOSE,
    tenantId: string = BiometricEnvelopeEncryptionService.DEFAULT_TENANT
  ): Buffer {
    if (!uid || typeof uid !== 'string') {
      throw new Error('[BiometricEnvelopeEncryptionService] UID must be a non-empty string for AAD binding.');
    }
    return Buffer.from(
      `${BiometricEnvelopeEncryptionService.AAD_PREFIX}|uid:${uid}|purpose:${purpose}|tenant:${tenantId}`,
      'utf8'
    );
  }

  public buildDekWrappingAad(
    uid: string,
    keyVersion: string,
    purpose: string = BiometricEnvelopeEncryptionService.DEFAULT_PURPOSE
  ): Buffer {
    if (!uid || typeof uid !== 'string') {
      throw new Error('[BiometricEnvelopeEncryptionService] UID must be a non-empty string for AAD binding.');
    }
    return Buffer.from(
      `${BiometricEnvelopeEncryptionService.AAD_PREFIX}|uid:${uid}|purpose:${purpose}|ver:${keyVersion}`,
      'utf8'
    );
  }

  public buildAad(uid: string, keyVersion: string, purpose: string = BiometricEnvelopeEncryptionService.DEFAULT_PURPOSE): Buffer {
    return this.buildDekWrappingAad(uid, keyVersion, purpose);
  }

  public async encryptTemplate(
    uid: string,
    embedding: Float32Array | number[] | Buffer,
    options?: {
      purpose?: string;
      tenantId?: string;
    }
  ): Promise<BiometricEnvelopeV16> {
    const purpose = options?.purpose || BiometricEnvelopeEncryptionService.DEFAULT_PURPOSE;
    const tenantId = options?.tenantId || BiometricEnvelopeEncryptionService.DEFAULT_TENANT;

    let rawBuffer: Buffer;
    if (Buffer.isBuffer(embedding)) {
      rawBuffer = embedding;
    } else if (embedding instanceof Float32Array) {
      rawBuffer = Buffer.from(embedding.buffer, embedding.byteOffset, embedding.byteLength);
    } else if (Array.isArray(embedding)) {
      rawBuffer = Buffer.from(new Float32Array(embedding).buffer);
    } else {
      throw new Error('[BiometricEnvelopeEncryptionService] Invalid embedding input type.');
    }

    const dek = crypto.randomBytes(32);
    const iv = crypto.randomBytes(12);

    try {
      let wrappedDekBase64: string;
      let keyVersion = 'v1';
      let kmsKeyResourceName = this.provider.defaultKeyResourceName || 'local-key-resource';

      if (typeof this.provider.wrapDataKey === 'function') {
        const res = await this.provider.wrapDataKey(dek);
        wrappedDekBase64 = res.wrappedDekBase64;
        keyVersion = res.kekResourceVersion;
      } else if (typeof this.provider.wrapDek === 'function') {
        const initialDekAad = this.buildDekWrappingAad(uid, 'initial', purpose);
        const wrapped = await this.provider.wrapDek(dek, initialDekAad);
        const exactDekAad = this.buildDekWrappingAad(uid, wrapped.keyVersion, purpose);
        const finalized = wrapped.keyVersion === 'initial'
          ? wrapped
          : await this.provider.wrapDek(dek, exactDekAad);
        wrappedDekBase64 = finalized.wrappedDek.toString('base64');
        keyVersion = finalized.keyVersion;
        kmsKeyResourceName = finalized.kmsKeyResourceName;
      } else {
        throw new Error('[BiometricEnvelopeEncryptionService] Key provider lacks wrap implementation.');
      }

      const payloadAad = this.buildPayloadAad(uid, purpose, tenantId);
      const cipher = crypto.createCipheriv('aes-256-gcm', dek, iv);
      cipher.setAAD(payloadAad);
      const ciphertext = Buffer.concat([cipher.update(rawBuffer), cipher.final()]);
      const authTag = cipher.getAuthTag();

      return {
        version: 'v16_kms_gcm',
        uid,
        tenantId,
        purpose,
        keyVersion,
        kmsKeyResourceName,
        wrappedDekBase64,
        ciphertextBase64: ciphertext.toString('base64'),
        ivBase64: iv.toString('base64'),
        authTagBase64: authTag.toString('base64'),
        encryptedAt: new Date().toISOString(),
      };
    } finally {
      dek.fill(0);
    }
  }

  public async decryptTemplate(
    uidOrEnvelope: string | BiometricEnvelopeV16,
    secondArgEnvelope?: BiometricEnvelopeV16
  ): Promise<Float32Array> {
    const envelope: BiometricEnvelopeV16 =
      typeof uidOrEnvelope === 'string'
        ? { ...secondArgEnvelope!, uid: uidOrEnvelope }
        : uidOrEnvelope;

    if (!envelope || !envelope.ciphertextBase64) {
      throw new Error('[BiometricEnvelopeEncryptionService] Invalid envelope provided to decryptTemplate.');
    }

    const dekAad = this.buildDekWrappingAad(
      envelope.uid,
      envelope.keyVersion || 'v1',
      envelope.purpose || BiometricEnvelopeEncryptionService.DEFAULT_PURPOSE
    );
    const payloadAad = this.buildPayloadAad(
      envelope.uid,
      envelope.purpose || BiometricEnvelopeEncryptionService.DEFAULT_PURPOSE,
      envelope.tenantId || BiometricEnvelopeEncryptionService.DEFAULT_TENANT
    );

    let dek: Buffer;
    if (typeof this.provider.unwrapDataKey === 'function') {
      dek = await this.provider.unwrapDataKey(envelope.wrappedDekBase64);
    } else if (typeof this.provider.unwrapDek === 'function') {
      const wrappedDek = Buffer.from(envelope.wrappedDekBase64, 'base64');
      dek = await this.provider.unwrapDek(wrappedDek, dekAad, envelope.kmsKeyResourceName);
    } else {
      throw new Error('[BiometricEnvelopeEncryptionService] Key provider lacks unwrap implementation.');
    }

    try {
      const ciphertext = Buffer.from(envelope.ciphertextBase64, 'base64');
      const iv = Buffer.from(envelope.ivBase64, 'base64');
      const authTag = Buffer.from(envelope.authTagBase64, 'base64');

      const decipher = crypto.createDecipheriv('aes-256-gcm', dek, iv);
      decipher.setAAD(payloadAad);
      decipher.setAuthTag(authTag);

      const plaintext = Buffer.concat([decipher.update(ciphertext), decipher.final()]);

      const floatCount = plaintext.length / 4;
      const result = new Float32Array(floatCount);
      for (let i = 0; i < floatCount; i++) {
        result[i] = plaintext.readFloatLE(i * 4);
      }
      return result;
    } catch (err: any) {
      throw new Error(`[BiometricEnvelopeEncryptionService] DECRYPTION_FAILED: ${err.message}`);
    } finally {
      dek.fill(0);
    }
  }

  public async rewrapTemplateDek(
    envelope: BiometricEnvelopeV16,
    newProvider?: KeyEncryptionProvider
  ): Promise<BiometricEnvelopeV16> {
    const targetProvider = newProvider || this.provider;
    this.assertEnvironmentSafety(targetProvider);

    const oldDekAad = this.buildDekWrappingAad(envelope.uid, envelope.keyVersion, envelope.purpose);
    const wrappedDek = Buffer.from(envelope.wrappedDekBase64, 'base64');

    let dek: Buffer;
    if (typeof this.provider.unwrapDataKey === 'function') {
      dek = await this.provider.unwrapDataKey(envelope.wrappedDekBase64);
    } else if (typeof this.provider.unwrapDek === 'function') {
      dek = await this.provider.unwrapDek(wrappedDek, oldDekAad, envelope.kmsKeyResourceName);
    } else {
      throw new Error('[BiometricEnvelopeEncryptionService] Provider lacks unwrap implementation.');
    }

    try {
      let newWrappedDekBase64: string;
      let newKeyVersion = 'v1';
      let newKmsKeyResourceName = targetProvider.defaultKeyResourceName || 'local-key-resource';

      if (typeof targetProvider.wrapDataKey === 'function') {
        const res = await targetProvider.wrapDataKey(dek);
        newWrappedDekBase64 = res.wrappedDekBase64;
        newKeyVersion = res.kekResourceVersion;
      } else if (typeof targetProvider.wrapDek === 'function') {
        const initialNewDekAad = this.buildDekWrappingAad(envelope.uid, 'initial', envelope.purpose);
        const newWrapped = await targetProvider.wrapDek(dek, initialNewDekAad);
        const exactNewDekAad = this.buildDekWrappingAad(envelope.uid, newWrapped.keyVersion, envelope.purpose);
        const finalizedNewWrapped = newWrapped.keyVersion === 'initial'
          ? newWrapped
          : await targetProvider.wrapDek(dek, exactNewDekAad);
        newWrappedDekBase64 = finalizedNewWrapped.wrappedDek.toString('base64');
        newKeyVersion = finalizedNewWrapped.keyVersion;
        newKmsKeyResourceName = finalizedNewWrapped.kmsKeyResourceName;
      } else {
        throw new Error('[BiometricEnvelopeEncryptionService] Target provider lacks wrap implementation.');
      }

      return {
        ...envelope,
        keyVersion: newKeyVersion,
        kmsKeyResourceName: newKmsKeyResourceName,
        wrappedDekBase64: newWrappedDekBase64,
        encryptedAt: new Date().toISOString(),
      };
    } finally {
      dek.fill(0);
    }
  }
}

export { BiometricEnvelopeEncryptionService as KmsEnvelopeEncryptionService };

