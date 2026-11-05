// File: backend/src/biometrics/iso24745_iom_cancelable_snapshot_v18.ts
// KELASAGARA V18 / PHASE 13 — ISO/IEC 24745 IoM Cancelable Biometrics & Encrypted KS18 Binary Snapshot
// Fixes V12.1 broken HMAC-SHA256 float quantizer and V12.2 unencrypted KS12 snapshot vulnerability.

import * as crypto from 'node:crypto';
import {
  CANONICAL_SFACE_MODEL_ID,
  CANONICAL_SFACE_MODEL_VERSION,
  CANONICAL_TEMPLATE_SCHEMA_VERSION,
  SFACE_EMBEDDING_DIMENSION,
  assertValidCanonicalSfaceEmbedding,
} from '../crypto/cloud_kms_envelope';
import {
  EnrolledWorkerSfaceRecordV3,
  HighSpeedBiometricIndexV3,
} from '../services/hnsw_biometric_matcher_v3';

export const KS18_SNAPSHOT_MAGIC = 0x4b533138; // "KS18" in ASCII Big-Endian
export const KS18_FORMAT_VERSION = 18 as const;
export const IOM_SUBSPACES_M = 64 as const;
export const IOM_SUBSPACE_SIZE_K = 16 as const;

/**
 * Computes an ISO/IEC 24745 compliant Index-of-Maximum (IoM) Cancelable Biometric Code.
 * Unlike HMAC-SHA256 over quantized floats (which destroys similarity via avalanche effect),
 * IoM is a Locality-Sensitive Hash (LSH) on the unit hypersphere:
 * - Non-invertible (many-to-one argmax projection)
 * - Revocable (changing the 256-bit tenant/epoch salt produces an independent projection)
 * - Distance-preserving (Hamming agreement correlates monotonically with cosine similarity)
 */
export function computeIso24745IomCancelableCode(
  sfaceEmbedding128: Float32Array,
  epochSaltKey: Buffer,
): Uint8Array {
  const validated = assertValidCanonicalSfaceEmbedding(
    sfaceEmbedding128,
    'computeIso24745IomCancelableCode',
  );
  if (epochSaltKey.byteLength < 32) {
    throw new Error('ISO24745_SALT_TOO_SHORT: epochSaltKey requires at least 32 bytes.');
  }

  // Derive deterministic pseudo-random stream from epochSaltKey using SHAKE256
  const prngBuf = crypto
    .createHash('shake256', {
      outputLength: IOM_SUBSPACES_M * IOM_SUBSPACE_SIZE_K * 2,
    })
    .update(epochSaltKey)
    .digest();

  const iomCode = new Uint8Array(IOM_SUBSPACES_M);
  let byteCursor = 0;

  for (let m = 0; m < IOM_SUBSPACES_M; m++) {
    let maxProjection = -Infinity;
    let bestIndex = 0;

    for (let k = 0; k < IOM_SUBSPACE_SIZE_K; k++) {
      // Sparse ternary/Gaussian projection over 4 canonical dimensions per candidate
      const b0 = prngBuf[byteCursor % prngBuf.length];
      const b1 = prngBuf[(byteCursor + 1) % prngBuf.length];
      byteCursor += 2;

      const idx0 = (b0 + m * 7 + k * 13) & 127;
      const idx1 = (b1 + m * 11 + k * 19) & 127;
      const idx2 = ((b0 ^ b1) + m * 17 + k * 23) & 127;
      const idx3 = ((b0 + b1) + m * 29 + k * 31) & 127;

      const sign0 = (b0 & 1) === 0 ? 1.0 : -1.0;
      const sign1 = (b0 & 2) === 0 ? 1.0 : -1.0;
      const sign2 = (b1 & 1) === 0 ? 1.0 : -1.0;
      const sign3 = (b1 & 2) === 0 ? 1.0 : -1.0;

      const proj =
        sign0 * validated[idx0] +
        sign1 * validated[idx1] +
        sign2 * validated[idx2] +
        sign3 * validated[idx3];

      if (proj > maxProjection) {
        maxProjection = proj;
        bestIndex = k;
      }
    }
    iomCode[m] = bestIndex;
  }

  return iomCode;
}

/**
 * Computes normalized Hamming similarity in [0.0, 1.0] between two 64-byte IoM cancelable codes.
 */
export function computeIomHammingSimilarity(
  codeA: Uint8Array,
  codeB: Uint8Array,
): number {
  if (codeA.length !== IOM_SUBSPACES_M || codeB.length !== IOM_SUBSPACES_M) {
    throw new Error('Incompatible IoM cancelable code lengths.');
  }
  let matches = 0;
  for (let i = 0; i < IOM_SUBSPACES_M; i++) {
    if (codeA[i] === codeB[i]) {
      matches++;
    }
  }
  return matches / IOM_SUBSPACES_M;
}

/**
 * Encodes Snapshot AAD using Big-Endian 32-bit length prefixes (eliminating ':' delimiter splicing).
 */
export function encodeSnapshotCanonicalAad(params: {
  readonly clusterId: string;
  readonly keyId: string;
  readonly modelVersion: string;
  readonly watermarkWalSeq: number;
  readonly nodeCount: number;
}): Buffer {
  const parts = [
    Buffer.from('KS18_ENCRYPTED_HNSW_SNAPSHOT', 'utf8'),
    Buffer.from(params.clusterId, 'utf8'),
    Buffer.from(params.keyId, 'utf8'),
    Buffer.from(params.modelVersion, 'utf8'),
    Buffer.from(String(params.watermarkWalSeq), 'utf8'),
    Buffer.from(String(params.nodeCount), 'utf8'),
  ];

  const totalLen = parts.reduce((acc, p) => acc + 4 + p.byteLength, 0);
  const out = Buffer.allocUnsafe(totalLen);
  let offset = 0;
  for (const part of parts) {
    out.writeUInt32BE(part.byteLength, offset);
    offset += 4;
    part.copy(out, offset);
    offset += part.byteLength;
  }
  return out;
}

export interface Ks18EncryptedSnapshotBundle {
  readonly formatMagic: 'KS18';
  readonly formatVersion: typeof KS18_FORMAT_VERSION;
  readonly clusterId: string;
  readonly keyId: string;
  readonly modelVersion: typeof CANONICAL_SFACE_MODEL_VERSION;
  readonly watermarkWalSeq: number;
  readonly nodeCount: number;
  readonly ivBase64: string;
  readonly authTagBase64: string;
  readonly encryptedPayloadBuffer: Buffer;
}

/**
 * Exports a `HighSpeedBiometricIndexV3` into a 64-bit aligned binary frame and encrypts it
 * with AES-256-GCM bound to length-prefixed AAD so snapshots in Cloud Storage are never plaintext.
 */
export function exportEncryptedAlignedSnapshotKs18(params: {
  readonly records: readonly EnrolledWorkerSfaceRecordV3[];
  readonly watermarkWalSeq: number;
  readonly clusterId: string;
  readonly keyId: string;
  readonly snapshotEncryptionKey32: Buffer;
}): Ks18EncryptedSnapshotBundle {
  if (params.snapshotEncryptionKey32.byteLength !== 32) {
    throw new Error('KS18_KEY_ERROR: snapshotEncryptionKey32 must be 32 bytes (256 bits).');
  }

  const nodeCount = params.records.length;
  const metaItems = params.records.map((r) => ({
    u: r.uid,
    p: r.maskedPhone,
    q: r.isoQualityScore,
    l: r.padLivenessScore,
    t: r.enrolledAtEpochMs,
  }));

  const metaJsonBytes = Buffer.from(JSON.stringify(metaItems), 'utf8');
  // Pad header + JSON metadata to an exact 8-byte boundary for zero-copy Float32Array alignment
  const headerAndMetaLen = 16 + metaJsonBytes.byteLength;
  const paddingBytes = (8 - (headerAndMetaLen % 8)) % 8;
  const alignedVectorOffset = headerAndMetaLen + paddingBytes;
  const vectorArenaBytes = nodeCount * SFACE_EMBEDDING_DIMENSION * 4;
  const totalPlaintextBytes = alignedVectorOffset + vectorArenaBytes;

  const plaintextBuf = Buffer.alloc(totalPlaintextBytes);
  plaintextBuf.writeUInt32BE(KS18_SNAPSHOT_MAGIC, 0);
  plaintextBuf.writeUInt32BE(KS18_FORMAT_VERSION, 4);
  plaintextBuf.writeUInt32BE(nodeCount, 8);
  plaintextBuf.writeUInt32BE(metaJsonBytes.byteLength, 12);
  metaJsonBytes.copy(plaintextBuf, 16);

  // Copy 128-D Float32 vectors directly into the 8-byte aligned arena region
  const floatView = new Float32Array(
    plaintextBuf.buffer,
    plaintextBuf.byteOffset + alignedVectorOffset,
    nodeCount * SFACE_EMBEDDING_DIMENSION,
  );

  for (let i = 0; i < nodeCount; i++) {
    const validated = assertValidCanonicalSfaceEmbedding(
      params.records[i].sfaceEmbedding128,
      `exportKs18(${params.records[i].uid})`,
    );
    floatView.set(validated, i * SFACE_EMBEDDING_DIMENSION);
  }

  const aad = encodeSnapshotCanonicalAad({
    clusterId: params.clusterId,
    keyId: params.keyId,
    modelVersion: CANONICAL_SFACE_MODEL_VERSION,
    watermarkWalSeq: params.watermarkWalSeq,
    nodeCount,
  });

  const iv = crypto.randomBytes(12);
  try {
    const cipher = crypto.createCipheriv(
      'aes-256-gcm',
      params.snapshotEncryptionKey32,
      iv,
    );
    cipher.setAAD(aad);
    const encryptedPayloadBuffer = Buffer.concat([
      cipher.update(plaintextBuf),
      cipher.final(),
    ]);
    const authTag = cipher.getAuthTag();

    return {
      formatMagic: 'KS18',
      formatVersion: KS18_FORMAT_VERSION,
      clusterId: params.clusterId,
      keyId: params.keyId,
      modelVersion: CANONICAL_SFACE_MODEL_VERSION,
      watermarkWalSeq: params.watermarkWalSeq,
      nodeCount,
      ivBase64: iv.toString('base64'),
      authTagBase64: authTag.toString('base64'),
      encryptedPayloadBuffer,
    };
  } finally {
    plaintextBuf.fill(0);
  }
}

/**
 * Decrypts, authenticates, and hydrates a `KS18` binary snapshot into a ready-to-search
 * `HighSpeedBiometricIndexV3` instance. Rejects any bit-tampering or AAD splicing.
 */
export function hydrateEncryptedSnapshotKs18(params: {
  readonly bundle: Ks18EncryptedSnapshotBundle;
  readonly expectedClusterId: string;
  readonly snapshotEncryptionKey32: Buffer;
  readonly maxArenaCapacity?: number;
}): {
  readonly index: HighSpeedBiometricIndexV3;
  readonly records: readonly EnrolledWorkerSfaceRecordV3[];
  readonly watermarkWalSeq: number;
  readonly hydrationLatencyMs: number;
} {
  const startNs = process.hrtime.bigint();

  if (
    params.bundle.formatMagic !== 'KS18' ||
    params.bundle.formatVersion !== KS18_FORMAT_VERSION ||
    params.bundle.modelVersion !== CANONICAL_SFACE_MODEL_VERSION
  ) {
    throw new Error('KS18_VERSION_MISMATCH: Incompatible snapshot format or model version.');
  }

  const aad = encodeSnapshotCanonicalAad({
    clusterId: params.expectedClusterId,
    keyId: params.bundle.keyId,
    modelVersion: params.bundle.modelVersion,
    watermarkWalSeq: params.bundle.watermarkWalSeq,
    nodeCount: params.bundle.nodeCount,
  });

  const iv = Buffer.from(params.bundle.ivBase64, 'base64');
  const authTag = Buffer.from(params.bundle.authTagBase64, 'base64');

  const decipher = crypto.createDecipheriv(
    'aes-256-gcm',
    params.snapshotEncryptionKey32,
    iv,
  );
  decipher.setAAD(aad);
  decipher.setAuthTag(authTag);

  const rawPayload = Buffer.isBuffer(params.bundle.encryptedPayloadBuffer)
    ? params.bundle.encryptedPayloadBuffer
    : Buffer.from(
        (params.bundle.encryptedPayloadBuffer as any)?.data ??
        params.bundle.encryptedPayloadBuffer,
      );

  const decryptedBuf = Buffer.concat([
    decipher.update(rawPayload),
    decipher.final(),
  ]);

  try {
    if (decryptedBuf.byteLength < 16) {
      throw new Error('KS18_TRUNCATED_HEADER: Decrypted buffer is shorter than header (16 bytes).');
    }

    const magic = decryptedBuf.readUInt32BE(0);
    const version = decryptedBuf.readUInt32BE(4);
    const nodeCount = decryptedBuf.readUInt32BE(8);
    const metaByteLen = decryptedBuf.readUInt32BE(12);

    if (magic !== KS18_SNAPSHOT_MAGIC || version !== KS18_FORMAT_VERSION) {
      throw new Error('KS18_CORRUPT_HEADER: Invalid magic bytes after decryption.');
    }

    if (metaByteLen < 2 || 16 + metaByteLen > decryptedBuf.byteLength) {
      throw new Error('KS18_INVALID_METADATA_LENGTH: Metadata length exceeds buffer boundary.');
    }

    const headerAndMetaLen = 16 + metaByteLen;
    const paddingBytes = (8 - (headerAndMetaLen % 8)) % 8;
    const alignedVectorOffset = headerAndMetaLen + paddingBytes;
    const expectedVectorBytes = nodeCount * SFACE_EMBEDDING_DIMENSION * 4;
    const expectedTotalBytes = alignedVectorOffset + expectedVectorBytes;

    if (decryptedBuf.byteLength !== expectedTotalBytes) {
      throw new Error(
        `KS18_CORRUPT_LENGTH: Decrypted buffer size ${decryptedBuf.byteLength} does not match expected size ${expectedTotalBytes}.`,
      );
    }

    const metaJsonStr = decryptedBuf
      .subarray(16, 16 + metaByteLen)
      .toString('utf8');
    let metaItems: Array<{
      u: string;
      p: string;
      q: number;
      l: number;
      t: number;
    }>;
    try {
      metaItems = JSON.parse(metaJsonStr);
    } catch {
      throw new Error('KS18_INVALID_JSON_METADATA: Failed to parse snapshot metadata JSON.');
    }

    if (!Array.isArray(metaItems) || metaItems.length !== nodeCount) {
      throw new Error(
        `KS18_METADATA_COUNT_MISMATCH: JSON meta count (${metaItems?.length}) does not match header node count (${nodeCount}).`,
      );
    }

    // Copy into an aligned ArrayBuffer view for Float32Array
    const vectorBytes = decryptedBuf.subarray(
      alignedVectorOffset,
      alignedVectorOffset + expectedVectorBytes,
    );
    const alignedCopy = new Uint8Array(vectorBytes.byteLength);
    alignedCopy.set(vectorBytes);
    const floatArena = new Float32Array(alignedCopy.buffer);

    const capacity = Math.max(params.maxArenaCapacity ?? 50000, nodeCount + 1024);
    const index = new HighSpeedBiometricIndexV3(capacity, capacity);
    const records: EnrolledWorkerSfaceRecordV3[] = [];

    for (let i = 0; i < nodeCount; i++) {
      const m = metaItems[i];
      if (
        !m ||
        typeof m.u !== 'string' ||
        typeof m.p !== 'string' ||
        typeof m.q !== 'number' ||
        typeof m.l !== 'number' ||
        typeof m.t !== 'number'
      ) {
        throw new Error(`KS18_MALFORMED_RECORD: Snapshot record at index ${i} is missing required fields.`);
      }
      const vecSlice = floatArena.subarray(
        i * SFACE_EMBEDDING_DIMENSION,
        (i + 1) * SFACE_EMBEDDING_DIMENSION,
      );
      const rec: EnrolledWorkerSfaceRecordV3 = {
        uid: m.u,
        maskedPhone: m.p,
        modelId: CANONICAL_SFACE_MODEL_ID,
        modelVersion: CANONICAL_SFACE_MODEL_VERSION,
        templateSchemaVersion: CANONICAL_TEMPLATE_SCHEMA_VERSION,
        sfaceEmbedding128: vecSlice,
        isoQualityScore: m.q,
        padLivenessScore: m.l,
        enrolledAtEpochMs: m.t,
      };
      index.upsertTemplate(rec);
      records.push(rec);
    }

    const hydrationLatencyMs = Number(
      (Number(process.hrtime.bigint() - startNs) / 1e6).toFixed(3),
    );

    return {
      index,
      records,
      watermarkWalSeq: params.bundle.watermarkWalSeq,
      hydrationLatencyMs,
    };
  } finally {
    decryptedBuf.fill(0);
  }
}
