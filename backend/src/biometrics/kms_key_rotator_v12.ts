/**
 * KELASAGARA BIOMETRIC ENGINE V12.0 — PHASE 12.1
 * File: backend/src/biometrics/kms_key_rotator_v12.ts
 *
 * Zero-Downtime AES-256-GCM Envelope Key Rotation, AAD Cryptographic Binding,
 * and Dual-Epoch HMAC-SHA256 Cancelable Biometric Salt Rotation (DPDP Rules 2025).
 */

import crypto from 'node:crypto';

export type KeyEpochStatusV12 = 'ACTIVE' | 'DECRYPT_ONLY' | 'REVOKED';

export interface KeyEpochDescriptorV12 {
  readonly keyId: string;
  readonly aesKey256: Buffer; // Exactly 32 bytes (256 bits)
  readonly hmacSalt256: Buffer; // Exactly 32 bytes (256 bits)
  status: KeyEpochStatusV12;
  readonly createdAtMs: number;
  rotatedAtMs?: number;
}

export interface EncryptedBiometricEnvelopeV12 {
  readonly uid: string;
  readonly faceId: string;
  readonly modelVersion: 'v10_sface_128' | 'v11_adaface_512';
  readonly keyId: string;
  readonly aadSchemaVersion: 1 | 2;
  readonly ivBase64: string; // 96-bit (12-byte) GCM nonce
  readonly authTagBase64: string; // 128-bit (16-byte) GCM authentication tag
  readonly ciphertextBase64: string; // Float32Array byte buffer
  readonly cancelableBiometricHash: string; // HMAC-SHA256 quantized template hash
  readonly previousCancelableHash?: string; // Retained during rotation grace period
  readonly lockToken: string;
  readonly rotationGeneration: number;
  readonly updatedAtMs: number;
}

export interface VaultPersistencePortV12 {
  listBatchAfterUid(afterUid: string | null, limit: number): Promise<EncryptedBiometricEnvelopeV12[]>;
  atomicCompareAndSwapEnvelope(
    uid: string,
    expectedGeneration: number,
    updatedEnvelope: EncryptedBiometricEnvelopeV12
  ): Promise<boolean>;
}

export interface BatchRotationProgressReportV12 {
  readonly targetKeyId: string;
  readonly scannedCount: number;
  readonly rotatedCount: number;
  readonly alreadyCurrentCount: number;
  readonly skippedConflictCount: number;
  readonly lastCursorUid: string | null;
  readonly durationMs: number;
}

export class KmsKeyRotatorV12 {
  private readonly epochs = new Map<string, KeyEpochDescriptorV12>();
  private activeKeyId: string;

  constructor(initialEpoch: {
    keyId: string;
    aesKey256: Buffer;
    hmacSalt256: Buffer;
    createdAtMs?: number;
  }) {
    this.validateKeyMaterial(initialEpoch.keyId, initialEpoch.aesKey256, initialEpoch.hmacSalt256);
    this.epochs.set(initialEpoch.keyId, {
      keyId: initialEpoch.keyId,
      aesKey256: Buffer.from(initialEpoch.aesKey256),
      hmacSalt256: Buffer.from(initialEpoch.hmacSalt256),
      status: 'ACTIVE',
      createdAtMs: initialEpoch.createdAtMs ?? Date.now(),
    });
    this.activeKeyId = initialEpoch.keyId;
  }

  private validateKeyMaterial(keyId: string, aesKey: Buffer, hmacSalt: Buffer): void {
    if (!keyId || keyId.trim().length === 0) {
      throw new Error('BIOMETRIC_V12_KMS_INVALID_KEY_ID');
    }
    if (aesKey.byteLength !== 32) {
      throw new Error(
        `BIOMETRIC_V12_KMS_INVALID_AES_KEY_LENGTH: Expected 32 bytes, got ${aesKey.byteLength}`
      );
    }
    if (hmacSalt.byteLength !== 32) {
      throw new Error(
        `BIOMETRIC_V12_KMS_INVALID_SALT_LENGTH: Expected 32 bytes, got ${hmacSalt.byteLength}`
      );
    }
  }

  public getActiveKeyId(): string {
    return this.activeKeyId;
  }

  /**
   * Registers a new KMS epoch and atomically promotes it to `ACTIVE`
   * while demoting the previous active key to `DECRYPT_ONLY`.
   */
  public promoteNewActiveEpoch(newEpoch: {
    keyId: string;
    aesKey256: Buffer;
    hmacSalt256: Buffer;
    nowMs?: number;
  }): void {
    this.validateKeyMaterial(newEpoch.keyId, newEpoch.aesKey256, newEpoch.hmacSalt256);
    if (this.epochs.has(newEpoch.keyId)) {
      throw new Error(`BIOMETRIC_V12_KMS_DUPLICATE_KEY_ID:${newEpoch.keyId}`);
    }

    const nowMs = newEpoch.nowMs ?? Date.now();
    const prevActive = this.epochs.get(this.activeKeyId);
    if (prevActive && prevActive.status === 'ACTIVE') {
      prevActive.status = 'DECRYPT_ONLY';
      prevActive.rotatedAtMs = nowMs;
    }

    this.epochs.set(newEpoch.keyId, {
      keyId: newEpoch.keyId,
      aesKey256: Buffer.from(newEpoch.aesKey256),
      hmacSalt256: Buffer.from(newEpoch.hmacSalt256),
      status: 'ACTIVE',
      createdAtMs: nowMs,
    });
    this.activeKeyId = newEpoch.keyId;
  }

  /**
   * Marks an old epoch as `REVOKED` once all vault records have been re-encrypted.
   */
  public revokeEpochKey(keyId: string): void {
    if (keyId === this.activeKeyId) {
      throw new Error('BIOMETRIC_V12_KMS_CANNOT_REVOKE_ACTIVE_KEY');
    }
    const epoch = this.epochs.get(keyId);
    if (!epoch) {
      throw new Error(`BIOMETRIC_V12_KMS_UNKNOWN_KEY_ID:${keyId}`);
    }
    epoch.status = 'REVOKED';
  }

  /**
   * Constructs the deterministic Additional Authenticated Data (AAD) buffer.
   * Schema v1 (V11 legacy): `${uid}:${faceId}:${modelVersion}`
   * Schema v2 (V12 hardened): `${uid}:${faceId}:${modelVersion}:${keyId}`
   */
  private buildAadBuffer(
    uid: string,
    faceId: string,
    modelVersion: string,
    keyId: string,
    aadSchemaVersion: 1 | 2
  ): Buffer {
    const raw =
      aadSchemaVersion === 1
        ? `${uid}:${faceId}:${modelVersion}`
        : `${uid}:${faceId}:${modelVersion}:${keyId}`;
    return Buffer.from(raw, 'utf8');
  }

  /**
   * Computes a salted HMAC-SHA256 cancelable biometric identifier from quantized embedding planes.
   */
  public computeCancelableBiometricHash(
    embedding: Float32Array,
    uid: string,
    keyId: string = this.activeKeyId
  ): string {
    const epoch = this.epochs.get(keyId);
    if (!epoch || epoch.status === 'REVOKED') {
      throw new Error(`BIOMETRIC_V12_KMS_UNAVAILABLE_KEY_EPOCH:${keyId}`);
    }

    // Quantize unit-normalized coordinates into signed 8-bit buckets to tolerate float jitter
    const quantized = Buffer.allocUnsafe(embedding.length);
    for (let i = 0; i < embedding.length; i++) {
      const clamped = Math.max(-1.0, Math.min(1.0, embedding[i]));
      quantized[i] = Math.round((clamped + 1.0) * 127.5) & 0xff;
    }

    return crypto
      .createHmac('sha256', epoch.hmacSalt256)
      .update(uid, 'utf8')
      .update(':')
      .update(quantized)
      .digest('hex');
  }

  /**
   * Encrypts a 128-D or 512-D Float32Array embedding under the current `ACTIVE` KMS epoch.
   */
  public encryptEmbeddingEnvelope(params: {
    uid: string;
    faceId: string;
    modelVersion: 'v10_sface_128' | 'v11_adaface_512';
    embedding: Float32Array;
    lockToken?: string;
    previousCancelableHash?: string;
    rotationGeneration?: number;
    aadSchemaVersion?: 1 | 2;
    nowMs?: number;
  }): EncryptedBiometricEnvelopeV12 {
    const epoch = this.epochs.get(this.activeKeyId);
    if (!epoch || epoch.status !== 'ACTIVE') {
      throw new Error('BIOMETRIC_V12_KMS_NO_ACTIVE_EPOCH');
    }

    const aadSchemaVersion = params.aadSchemaVersion ?? 2;
    const iv = crypto.randomBytes(12); // 96-bit IV per NIST SP 800-38D
    const aad = this.buildAadBuffer(
      params.uid,
      params.faceId,
      params.modelVersion,
      epoch.keyId,
      aadSchemaVersion
    );

    const plaintextBytes = Buffer.from(
      params.embedding.buffer,
      params.embedding.byteOffset,
      params.embedding.byteLength
    );

    const cipher = crypto.createCipheriv('aes-256-gcm', epoch.aesKey256, iv, {
      authTagLength: 16,
    });
    cipher.setAAD(aad);

    const ciphertext = Buffer.concat([cipher.update(plaintextBytes), cipher.final()]);
    const authTag = cipher.getAuthTag();

    const cancelableBiometricHash = this.computeCancelableBiometricHash(
      params.embedding,
      params.uid,
      epoch.keyId
    );

    const lockToken =
      params.lockToken ??
      `KS_FTOK_V12_${crypto
        .createHmac('sha256', epoch.hmacSalt256)
        .update(`${params.uid}:${params.faceId}:${cancelableBiometricHash}`)
        .digest('hex')
        .slice(0, 24)
        .toUpperCase()}`;

    return {
      uid: params.uid,
      faceId: params.faceId,
      modelVersion: params.modelVersion,
      keyId: epoch.keyId,
      aadSchemaVersion,
      ivBase64: iv.toString('base64'),
      authTagBase64: authTag.toString('base64'),
      ciphertextBase64: ciphertext.toString('base64'),
      cancelableBiometricHash,
      previousCancelableHash: params.previousCancelableHash,
      lockToken,
      rotationGeneration: params.rotationGeneration ?? 1,
      updatedAtMs: params.nowMs ?? Date.now(),
    };
  }

  /**
   * Decrypts an envelope using either the `ACTIVE` or a `DECRYPT_ONLY` historical key epoch.
   * Rejects tampered ciphertexts, spliced UIDs, or `REVOKED` epochs immediately.
   */
  public decryptEmbeddingEnvelope(envelope: EncryptedBiometricEnvelopeV12): {
    embedding: Float32Array;
    needsKeyRotation: boolean;
  } {
    const epoch = this.epochs.get(envelope.keyId);
    if (!epoch) {
      throw new Error(`BIOMETRIC_V12_KMS_UNKNOWN_KEY_ID:${envelope.keyId}`);
    }
    if (epoch.status === 'REVOKED') {
      throw new Error(`BIOMETRIC_V12_KMS_REVOKED_KEY_ID:${envelope.keyId}`);
    }

    const iv = Buffer.from(envelope.ivBase64, 'base64');
    const authTag = Buffer.from(envelope.authTagBase64, 'base64');
    const ciphertext = Buffer.from(envelope.ciphertextBase64, 'base64');

    if (iv.byteLength !== 12 || authTag.byteLength !== 16) {
      throw new Error('BIOMETRIC_V12_KMS_MALFORMED_IV_OR_TAG');
    }

    const aad = this.buildAadBuffer(
      envelope.uid,
      envelope.faceId,
      envelope.modelVersion,
      envelope.keyId,
      envelope.aadSchemaVersion
    );

    try {
      const decipher = crypto.createDecipheriv('aes-256-gcm', epoch.aesKey256, iv, {
        authTagLength: 16,
      });
      decipher.setAAD(aad);
      decipher.setAuthTag(authTag);

      const decryptedBytes = Buffer.concat([decipher.update(ciphertext), decipher.final()]);
      if (decryptedBytes.byteLength % 4 !== 0) {
        throw new Error('BIOMETRIC_V12_KMS_CORRUPTED_FLOAT32_BUFFER');
      }

      const floatCount = decryptedBytes.byteLength / 4;
      const alignedCopy = new Uint8Array(decryptedBytes.byteLength);
      alignedCopy.set(decryptedBytes);
      const embedding = new Float32Array(alignedCopy.buffer, 0, floatCount);

      return {
        embedding,
        needsKeyRotation: envelope.keyId !== this.activeKeyId || envelope.aadSchemaVersion !== 2,
      };
    } catch {
      throw new Error(
        `BIOMETRIC_V12_GCM_AUTH_FAILURE: Envelope integrity check failed for uid=${envelope.uid}`
      );
    }
  }

  /**
   * Re-encrypts a single historical envelope under the current `ACTIVE` epoch
   * while preserving its primary `lockToken` and recording `previousCancelableHash`
   * so in-flight worker sessions experience zero disruption.
   */
  public reEncryptEnvelopeToActiveKey(
    envelope: EncryptedBiometricEnvelopeV12,
    nowMs = Date.now()
  ): EncryptedBiometricEnvelopeV12 {
    const { embedding } = this.decryptEmbeddingEnvelope(envelope);
    return this.encryptEmbeddingEnvelope({
      uid: envelope.uid,
      faceId: envelope.faceId,
      modelVersion: envelope.modelVersion,
      embedding,
      lockToken: envelope.lockToken, // Preserve worker's locked KS_FTOK token across key rotation
      previousCancelableHash: envelope.cancelableBiometricHash,
      rotationGeneration: envelope.rotationGeneration + 1,
      aadSchemaVersion: 2,
      nowMs,
    });
  }

  /**
   * Verifies a candidate cancelable hash against both the current and grace-period hashes
   * using timing-safe comparison.
   */
  public verifyCancelableHashDualEpoch(
    envelope: EncryptedBiometricEnvelopeV12,
    candidateHashHex: string
  ): { matched: boolean; matchedEpoch: 'CURRENT' | 'PREVIOUS_GRACE' | 'NONE' } {
    const candidateBuf = Buffer.from(candidateHashHex, 'hex');
    const currentBuf = Buffer.from(envelope.cancelableBiometricHash, 'hex');

    if (
      candidateBuf.byteLength === currentBuf.byteLength &&
      crypto.timingSafeEqual(candidateBuf, currentBuf)
    ) {
      return { matched: true, matchedEpoch: 'CURRENT' };
    }

    if (envelope.previousCancelableHash) {
      const prevBuf = Buffer.from(envelope.previousCancelableHash, 'hex');
      if (
        candidateBuf.byteLength === prevBuf.byteLength &&
        crypto.timingSafeEqual(candidateBuf, prevBuf)
      ) {
        return { matched: true, matchedEpoch: 'PREVIOUS_GRACE' };
      }
    }

    return { matched: false, matchedEpoch: 'NONE' };
  }

  /**
   * Executes a cursor-paginated zero-downtime batch key rotation across the vault store.
   */
  public async rotateVaultBatchZeroDowntime(
    store: VaultPersistencePortV12,
    options: { startAfterUid?: string | null; batchSize?: number; maxBatches?: number } = {}
  ): Promise<BatchRotationProgressReportV12> {
    const startTime = performance.now();
    const batchSize = options.batchSize ?? 250;
    const maxBatches = options.maxBatches ?? 20;
    let cursorUid: string | null = options.startAfterUid ?? null;

    let scannedCount = 0;
    let rotatedCount = 0;
    let alreadyCurrentCount = 0;
    let skippedConflictCount = 0;

    for (let batchIdx = 0; batchIdx < maxBatches; batchIdx++) {
      const records = await store.listBatchAfterUid(cursorUid, batchSize);
      if (records.length === 0) break;

      for (const record of records) {
        scannedCount++;
        cursorUid = record.uid;

        if (record.keyId === this.activeKeyId && record.aadSchemaVersion === 2) {
          alreadyCurrentCount++;
          continue;
        }

        const rotatedEnvelope = this.reEncryptEnvelopeToActiveKey(record);
        const swapped = await store.atomicCompareAndSwapEnvelope(
          record.uid,
          record.rotationGeneration,
          rotatedEnvelope
        );

        if (swapped) {
          rotatedCount++;
        } else {
          skippedConflictCount++;
        }
      }

      if (records.length < batchSize) break;
    }

    return {
      targetKeyId: this.activeKeyId,
      scannedCount,
      rotatedCount,
      alreadyCurrentCount,
      skippedConflictCount,
      lastCursorUid: cursorUid,
      durationMs: Number((performance.now() - startTime).toFixed(3)),
    };
  }
}

