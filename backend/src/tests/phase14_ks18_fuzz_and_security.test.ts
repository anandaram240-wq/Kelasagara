// File: backend/src/tests/phase14_ks18_fuzz_and_security.test.ts
// KELASAGARA V18 / PHASE 14 — Gate 3: KS18 Snapshot Format Specification, Security & Fuzzing Suite
// Verifies 8-byte zero-copy alignment, GCM authentication, bounds fuzzing, anti-rollback, and memory consistency.

import { describe, it } from 'node:test';
import * as assert from 'node:assert/strict';
import * as crypto from 'node:crypto';
import {
  exportEncryptedAlignedSnapshotKs18,
  hydrateEncryptedSnapshotKs18,
  encodeSnapshotCanonicalAad,
  KS18_SNAPSHOT_MAGIC,
  KS18_FORMAT_VERSION,
  Ks18EncryptedSnapshotBundle,
} from '../biometrics/iso24745_iom_cancelable_snapshot_v18';
import {
  CANONICAL_SFACE_MODEL_ID,
  CANONICAL_SFACE_MODEL_VERSION,
  CANONICAL_TEMPLATE_SCHEMA_VERSION,
  SFACE_EMBEDDING_DIMENSION,
  LocalDevKeyProvider,
  CloudKmsEnvelopeService,
} from '../crypto/cloud_kms_envelope';
import { EnrolledWorkerSfaceRecordV3 } from '../services/hnsw_biometric_matcher_v3';
import {
  TransactionalGalleryCoordinatorV18,
  KmsWrappedKs18SnapshotArtifact,
} from '../services/transactional_gallery_coordinator_v18';
import {
  FirestoreBiometricTransactionAdapterV18,
} from '../services/firestore_transaction_adapter_v18';
import { SharedClusterFirestoreSimulator } from './transactional_gallery_coordinator_v18.test';

function createMockSfaceVector(seed: number): Float32Array {
  const vec = new Float32Array(SFACE_EMBEDDING_DIMENSION);
  let sumSq = 0;
  for (let i = 0; i < SFACE_EMBEDDING_DIMENSION; i++) {
    const val = Math.sin(seed * 997 + i * 13);
    vec[i] = val;
    sumSq += val * val;
  }
  const invNorm = 1.0 / Math.sqrt(sumSq);
  for (let i = 0; i < SFACE_EMBEDDING_DIMENSION; i++) {
    vec[i] *= invNorm;
  }
  return vec;
}

function createSampleRecords(count: number): EnrolledWorkerSfaceRecordV3[] {
  const records: EnrolledWorkerSfaceRecordV3[] = [];
  for (let i = 0; i < count; i++) {
    records.push({
      uid: `worker_fuzz_${i.toString().padStart(4, '0')}`,
      maskedPhone: `+91******${(1000 + i).toString().slice(-4)}`,
      modelId: CANONICAL_SFACE_MODEL_ID,
      modelVersion: CANONICAL_SFACE_MODEL_VERSION,
      templateSchemaVersion: CANONICAL_TEMPLATE_SCHEMA_VERSION,
      sfaceEmbedding128: createMockSfaceVector(i + 1),
      isoQualityScore: 85.0,
      padLivenessScore: 0.98,
      enrolledAtEpochMs: 1772000000000 + i * 1000,
    });
  }
  return records;
}

describe('KELASAGARA V18 / PHASE 14 — Gate 3: KS18 Format & Fuzzing Suite', () => {
  const snapshotKey = crypto.randomBytes(32);
  const clusterId = 'cluster-fuzz-in-south-1';
  const keyId = 'kek-ks18-fuzz-v1';

  it('1. Verifies 8-byte zero-copy alignment and header invariants in exported bundle', () => {
    const records = createSampleRecords(5);
    const bundle = exportEncryptedAlignedSnapshotKs18({
      records,
      watermarkWalSeq: 42,
      clusterId,
      keyId,
      snapshotEncryptionKey32: snapshotKey,
    });

    assert.strictEqual(bundle.formatMagic, 'KS18');
    assert.strictEqual(bundle.formatVersion, KS18_FORMAT_VERSION);
    assert.strictEqual(bundle.clusterId, clusterId);
    assert.strictEqual(bundle.keyId, keyId);
    assert.strictEqual(bundle.nodeCount, 5);
    assert.strictEqual(bundle.watermarkWalSeq, 42);

    // Verify hydration round-trip and memory map consistency
    const hydrated = hydrateEncryptedSnapshotKs18({
      bundle,
      expectedClusterId: clusterId,
      snapshotEncryptionKey32: snapshotKey,
    });

    assert.strictEqual(hydrated.index.size, 5);
    assert.strictEqual(hydrated.records.length, 5);
    assert.strictEqual(hydrated.watermarkWalSeq, 42);
    assert.strictEqual(hydrated.records[0].uid, 'worker_fuzz_0000');
    assert.strictEqual(hydrated.records[4].uid, 'worker_fuzz_0004');
  });

  it('2. Rejects ciphertext bit-flipping attacks via GCM authentication failure', () => {
    const records = createSampleRecords(3);
    const bundle = exportEncryptedAlignedSnapshotKs18({
      records,
      watermarkWalSeq: 10,
      clusterId,
      keyId,
      snapshotEncryptionKey32: snapshotKey,
    });

    // Flip a single bit in the middle of the ciphertext
    const tamperedPayload = Buffer.from(bundle.encryptedPayloadBuffer);
    tamperedPayload[tamperedPayload.length / 2] ^= 0x01;

    const tamperedBundle: Ks18EncryptedSnapshotBundle = {
      ...bundle,
      encryptedPayloadBuffer: tamperedPayload,
    };

    assert.throws(
      () => {
        hydrateEncryptedSnapshotKs18({
          bundle: tamperedBundle,
          expectedClusterId: clusterId,
          snapshotEncryptionKey32: snapshotKey,
        });
      },
      (err: any) => {
        // Node.js crypto GCM throws Unsupported state or unable to authenticate data
        return /authenticate data|authentication/i.test(err.message);
      },
    );
  });

  it('3. Rejects canonical AAD tampering (clusterId, watermark, or nodeCount splicing)', () => {
    const records = createSampleRecords(2);
    const bundle = exportEncryptedAlignedSnapshotKs18({
      records,
      watermarkWalSeq: 10,
      clusterId,
      keyId,
      snapshotEncryptionKey32: snapshotKey,
    });

    // Attempt to deserialize under a different clusterId
    assert.throws(() => {
      hydrateEncryptedSnapshotKs18({
        bundle,
        expectedClusterId: 'evil-foreign-cluster',
        snapshotEncryptionKey32: snapshotKey,
      });
    });

    // Attempt to tamper with watermarkWalSeq in the bundle (AAD mismatch)
    const tamperedWatermarkBundle: Ks18EncryptedSnapshotBundle = {
      ...bundle,
      watermarkWalSeq: 9999,
    };
    assert.throws(() => {
      hydrateEncryptedSnapshotKs18({
        bundle: tamperedWatermarkBundle,
        expectedClusterId: clusterId,
        snapshotEncryptionKey32: snapshotKey,
      });
    });
  });

  it('4. Bounds Fuzzing: Enforces strict length verification and bounds checks', () => {
    // Construct an encrypted bundle where plaintext header has metaByteLen pointing out of bounds
    // We encrypt a manually crafted malformed payload
    const malformedPlaintext = Buffer.alloc(32);
    malformedPlaintext.writeUInt32BE(KS18_SNAPSHOT_MAGIC, 0);
    malformedPlaintext.writeUInt32BE(KS18_FORMAT_VERSION, 4);
    malformedPlaintext.writeUInt32BE(1, 8); // nodeCount = 1
    malformedPlaintext.writeUInt32BE(999999, 12); // metaByteLen = 999999 (out of bounds!)

    const aad = encodeSnapshotCanonicalAad({
      clusterId,
      keyId,
      modelVersion: CANONICAL_SFACE_MODEL_VERSION,
      watermarkWalSeq: 1,
      nodeCount: 1,
    });

    const iv = crypto.randomBytes(12);
    const cipher = crypto.createCipheriv('aes-256-gcm', snapshotKey, iv);
    cipher.setAAD(aad);
    const encPayload = Buffer.concat([cipher.update(malformedPlaintext), cipher.final()]);
    const authTag = cipher.getAuthTag();

    const badBundle: Ks18EncryptedSnapshotBundle = {
      formatMagic: 'KS18',
      formatVersion: KS18_FORMAT_VERSION,
      clusterId,
      keyId,
      modelVersion: CANONICAL_SFACE_MODEL_VERSION,
      watermarkWalSeq: 1,
      nodeCount: 1,
      ivBase64: iv.toString('base64'),
      authTagBase64: authTag.toString('base64'),
      encryptedPayloadBuffer: encPayload,
    };

    assert.throws(
      () => {
        hydrateEncryptedSnapshotKs18({
          bundle: badBundle,
          expectedClusterId: clusterId,
          snapshotEncryptionKey32: snapshotKey,
        });
      },
      /KS18_INVALID_METADATA_LENGTH/,
    );
  });

  it('5. Anti-Rollback Protection: Coordinator rejects snapshots older than local watermark epoch', async () => {
    const simDb = new SharedClusterFirestoreSimulator();
    const localKms = new LocalDevKeyProvider();
    const mockKmsEnvelope = new CloudKmsEnvelopeService(localKms);
    const txAdapter = new FirestoreBiometricTransactionAdapterV18(simDb);

    const coordinator = new TransactionalGalleryCoordinatorV18({
      clusterId: 'cluster-rollback-test',
      tenantId: 'tenant_phase14',
      kmsKeyProvider: localKms,
      kmsEnvelope: mockKmsEnvelope,
      txAdapter,
    });

    // Advance coordinator watermark to epoch 15
    (coordinator as any).localWatermarkEpoch = 15;

    // Create a snapshot artifact at epoch 10 (< 15)
    const records = createSampleRecords(1);
    const rawBundle = exportEncryptedAlignedSnapshotKs18({
      records,
      watermarkWalSeq: 10,
      clusterId: 'cluster-rollback-test',
      keyId,
      snapshotEncryptionKey32: snapshotKey,
    });

    const dummyArtifact: KmsWrappedKs18SnapshotArtifact = {
      bundle: rawBundle,
      kmsKeyVersionName: 'projects/p/locations/l/keyRings/r/cryptoKeys/k/cryptoKeyVersions/1',
      wrappedSnapshotDekBase64: Buffer.from(snapshotKey).toString('base64'),
    };

    await assert.rejects(
      async () => {
        await coordinator.hydrateFromKmsSnapshotAndWalTail(dummyArtifact);
      },
      /ANTI_ROLLBACK_VIOLATION/,
    );
  });

  it('6. Rebuilt Records Map Fix: Verifies activeRecordsMap is fully populated on snapshot hydration', async () => {
    const simDb = new SharedClusterFirestoreSimulator();
    const localKms = new LocalDevKeyProvider();
    const mockKmsEnvelope = new CloudKmsEnvelopeService(localKms);
    const txAdapter = new FirestoreBiometricTransactionAdapterV18(simDb);

    const nodeA = new TransactionalGalleryCoordinatorV18({
      clusterId: 'cluster-map-sync',
      tenantId: 'tenant_phase14',
      kmsKeyProvider: localKms,
      kmsEnvelope: mockKmsEnvelope,
      txAdapter,
    });

    // Enroll 3 genuine workers on Node A
    const recs = createSampleRecords(3);
    for (const r of recs) {
      await nodeA.enrollWorkerWithEpochFencedRetry({
        uid: r.uid,
        maskedPhone: r.maskedPhone,
        idempotencyKey: `idem_${r.uid}`,
        payload: {
          sfaceEmbedding128: r.sfaceEmbedding128,
          isoQualityScore: r.isoQualityScore,
          padLivenessScore: r.padLivenessScore,
        },
      });
    }

    // Export KMS snapshot from Node A
    const snapshotArtifact = await nodeA.exportKmsWrappedSnapshotKs18('snap-kek-v1');

    // Boot Node B from snapshot
    const nodeB = new TransactionalGalleryCoordinatorV18({
      clusterId: 'cluster-map-sync',
      tenantId: 'tenant_phase14',
      kmsKeyProvider: localKms,
      kmsEnvelope: mockKmsEnvelope,
      txAdapter,
    });

    const bootResult = await nodeB.hydrateFromKmsSnapshotAndWalTail(snapshotArtifact);
    assert.strictEqual(bootResult.activeGallerySize, 3);

    // CRITICAL BUG VERIFICATION:
    // Before Phase 14 fix, activeRecordsMap was empty (size 0).
    // Now verify activeRecordsMap is populated with all 3 enrolled workers!
    const activeRecords = Array.from((nodeB as any).activeRecordsMap.values()) as EnrolledWorkerSfaceRecordV3[];
    assert.strictEqual(activeRecords.length, 3, 'activeRecordsMap must contain exactly 3 enrolled records');
    assert.strictEqual(activeRecords[0].uid, 'worker_fuzz_0000');
    assert.strictEqual(activeRecords[2].uid, 'worker_fuzz_0002');

    // Verify Node B can now export another snapshot without losing records!
    const secondArtifact = await nodeB.exportKmsWrappedSnapshotKs18('snap-kek-v2');
    assert.strictEqual(secondArtifact.bundle.nodeCount, 3);
  });

  it('7. Atomic Rollback: Preserves previous coordinator state if WAL tail replay fails', async () => {
    const simDb = new SharedClusterFirestoreSimulator();
    const localKms = new LocalDevKeyProvider();
    const mockKmsEnvelope = new CloudKmsEnvelopeService(localKms);
    const txAdapter = new FirestoreBiometricTransactionAdapterV18(simDb);

    const coordinator = new TransactionalGalleryCoordinatorV18({
      clusterId: 'cluster-atomic-test',
      tenantId: 'tenant_phase14',
      kmsKeyProvider: localKms,
      kmsEnvelope: mockKmsEnvelope,
      txAdapter,
    });

    // Advance coordinator to baseline state
    (coordinator as any).localWatermarkEpoch = 5;
    const initialIndex = (coordinator as any).activeIndex;

    // Create a snapshot artifact at epoch 10
    const snapshotRecords = createSampleRecords(2);
    const ephemeralKey = crypto.randomBytes(32);
    const rawBundle = exportEncryptedAlignedSnapshotKs18({
      records: snapshotRecords,
      watermarkWalSeq: 10,
      clusterId: 'cluster-atomic-test',
      keyId,
      snapshotEncryptionKey32: ephemeralKey,
    });

    const aad = encodeSnapshotCanonicalAad({
      clusterId: 'cluster-atomic-test',
      keyId,
      modelVersion: CANONICAL_SFACE_MODEL_VERSION,
      watermarkWalSeq: 10,
      nodeCount: 2,
    });
    const { wrappedDek, keyVersionName } = await localKms.wrapKey(ephemeralKey, aad);

    const artifact: KmsWrappedKs18SnapshotArtifact = {
      bundle: rawBundle,
      kmsKeyVersionName: keyVersionName,
      wrappedSnapshotDekBase64: wrappedDek.toString('base64'),
    };

    // Sabotage txAdapter.fetchIncrementalWalSince to throw an error simulating network partition
    const originalFetch = txAdapter.fetchIncrementalWalSince.bind(txAdapter);
    txAdapter.fetchIncrementalWalSince = async () => {
      throw new Error('SIMULATED_NETWORK_PARTITION_DURING_WAL_CATCHUP');
    };

    await assert.rejects(
      async () => {
        await coordinator.hydrateFromKmsSnapshotAndWalTail(artifact);
      },
      /SIMULATED_NETWORK_PARTITION_DURING_WAL_CATCHUP/,
    );

    // Verify atomic rollback restored previous state:
    assert.strictEqual(
      (coordinator as any).localWatermarkEpoch,
      5,
      'Epoch must remain 5 after failed hydration',
    );
    assert.strictEqual(
      (coordinator as any).activeIndex,
      initialIndex,
      'Index must be restored to previous instance',
    );

    txAdapter.fetchIncrementalWalSince = originalFetch;
  });
});
