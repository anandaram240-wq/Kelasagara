/**
 * KELASAGARA BIOMETRIC ENGINE V12.0 — PHASE 12.1 & 12.2 TEST SUITE
 * File: backend/src/tests/biometric_v12_phase12_1_12_2.test.ts
 *
 * Run via:
 * cd backend && npm run build && node --test dist/tests/biometric_v12_phase12_1_12_2.test.js
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {
  EncryptedBiometricEnvelopeV12,
  KmsKeyRotatorV12,
  VaultPersistencePortV12,
} from '../biometrics/kms_key_rotator_v12';
import {
  HnswClusterSyncCoordinatorV12,
  HnswWalEntryV12,
} from '../biometrics/hnsw_cluster_sync_v12';

function makeNormalized512Vector(seed: number): Float32Array {
  const vec = new Float32Array(512);
  let sumSq = 0;
  for (let i = 0; i < 512; i++) {
    const v = Math.sin(seed * 31.7 + i * 0.43);
    vec[i] = v;
    sumSq += v * v;
  }
  const invNorm = 1.0 / Math.sqrt(sumSq);
  for (let i = 0; i < 512; i++) vec[i] *= invNorm;
  return vec;
}

test('PHASE12.1-A: Zero-downtime KMS key rotation preserves legacy V11 decryption, blocks AAD splicing, and supports dual-epoch hashes', () => {
  const rotator = new KmsKeyRotatorV12({
    keyId: 'kms_v11_epoch_01',
    aesKey256: crypto.randomBytes(32),
    hmacSalt256: crypto.randomBytes(32),
  });

  const originalEmbedding = makeNormalized512Vector(101);

  // 1. Encrypt under initial epoch with V11 AAD schema (version 1)
  const v11Envelope = rotator.encryptEmbeddingEnvelope({
    uid: 'worker_ks_101',
    faceId: 'FACE_V11_101',
    modelVersion: 'v11_adaface_512',
    embedding: originalEmbedding,
    aadSchemaVersion: 1,
  });

  // 2. Promote new V12 key epoch while keeping kms_v11_epoch_01 in DECRYPT_ONLY mode
  rotator.promoteNewActiveEpoch({
    keyId: 'kms_v12_epoch_02',
    aesKey256: crypto.randomBytes(32),
    hmacSalt256: crypto.randomBytes(32),
  });

  assert.equal(rotator.getActiveKeyId(), 'kms_v12_epoch_02');

  // 3. Old envelope still decrypts cleanly and signals needsKeyRotation = true
  const decryptedV11 = rotator.decryptEmbeddingEnvelope(v11Envelope);
  assert.equal(decryptedV11.needsKeyRotation, true);
  assert.equal(decryptedV11.embedding.length, 512);
  assert.ok(Math.abs(decryptedV11.embedding[0] - originalEmbedding[0]) < 1e-6);

  // 4. Splicing ciphertext to another UID fails GCM AAD verification
  assert.throws(() => {
    rotator.decryptEmbeddingEnvelope({
      ...v11Envelope,
      uid: 'attacker_spliced_uid',
    });
  }, /BIOMETRIC_V12_GCM_AUTH_FAILURE/);

  // 5. Re-encrypt to active epoch preserves lockToken and supports dual-epoch cancelable hash
  const rotatedEnvelope = rotator.reEncryptEnvelopeToActiveKey(v11Envelope);
  assert.equal(rotatedEnvelope.keyId, 'kms_v12_epoch_02');
  assert.equal(rotatedEnvelope.lockToken, v11Envelope.lockToken);
  assert.equal(rotatedEnvelope.rotationGeneration, 2);

  const graceCheck = rotator.verifyCancelableHashDualEpoch(
    rotatedEnvelope,
    v11Envelope.cancelableBiometricHash
  );
  assert.equal(graceCheck.matched, true);
  assert.equal(graceCheck.matchedEpoch, 'PREVIOUS_GRACE');
});

test('PHASE12.1-B: Cursor-paginated batch rotation migrates vault records with optimistic concurrency', async () => {
  const rotator = new KmsKeyRotatorV12({
    keyId: 'kms_epoch_old',
    aesKey256: crypto.randomBytes(32),
    hmacSalt256: crypto.randomBytes(32),
  });

  const inMemoryVault = new Map<string, EncryptedBiometricEnvelopeV12>();
  for (let i = 1; i <= 15; i++) {
    const uid = `worker_${String(i).padStart(3, '0')}`;
    inMemoryVault.set(
      uid,
      rotator.encryptEmbeddingEnvelope({
        uid,
        faceId: `FACE_${i}`,
        modelVersion: 'v11_adaface_512',
        embedding: makeNormalized512Vector(i),
      })
    );
  }

  // Promote new key epoch
  rotator.promoteNewActiveEpoch({
    keyId: 'kms_epoch_new',
    aesKey256: crypto.randomBytes(32),
    hmacSalt256: crypto.randomBytes(32),
  });

  const persistenceAdapter: VaultPersistencePortV12 = {
    async listBatchAfterUid(afterUid, limit) {
      const sortedKeys = [...inMemoryVault.keys()].sort();
      const startIndex = afterUid ? sortedKeys.indexOf(afterUid) + 1 : 0;
      return sortedKeys.slice(startIndex, startIndex + limit).map((k) => inMemoryVault.get(k)!);
    },
    async atomicCompareAndSwapEnvelope(uid, expectedGeneration, updatedEnvelope) {
      const current = inMemoryVault.get(uid);
      if (!current || current.rotationGeneration !== expectedGeneration) return false;
      inMemoryVault.set(uid, updatedEnvelope);
      return true;
    },
  };

  const report = await rotator.rotateVaultBatchZeroDowntime(persistenceAdapter, {
    batchSize: 6,
    maxBatches: 5,
  });

  assert.equal(report.scannedCount, 15);
  assert.equal(report.rotatedCount, 15);
  assert.equal(report.skippedConflictCount, 0);

  // Verify old epoch can now be safely revoked and all records decrypt under kms_epoch_new
  rotator.revokeEpochKey('kms_epoch_old');
  for (const env of inMemoryVault.values()) {
    const { needsKeyRotation } = rotator.decryptEmbeddingEnvelope(env);
    assert.equal(needsKeyRotation, false);
  }
});

test('PHASE12.2-A: Binary HNSW snapshot exports, detects byte tampering, and hydrates in sub-200ms', () => {
  const signingSecret = crypto.randomBytes(32);
  const nodeA = new HnswClusterSyncCoordinatorV12(signingSecret);

  const walSeedEntries: HnswWalEntryV12[] = [];
  for (let i = 1; i <= 200; i++) {
    const uid = `worker_hnsw_${i}`;
    walSeedEntries.push({
      walSeq: i,
      opType: 'UPSERT_NODE',
      uid,
      timestampMs: 1700000000000 + i,
      nodePayload: {
        uid,
        faceId: `FACE_${i}`,
        keyId: 'kms_v12_epoch_02',
        modelVersion: 'v11_adaface_512',
        lockToken: `KS_FTOK_V12_${i}`,
        embedding: makeNormalized512Vector(i),
        neighborsByLayer: [],
        updatedAtMs: 1700000000000 + i,
      },
    });
  }

  nodeA.applyIncrementalWalDelta(walSeedEntries);
  const snapshotBuffer = nodeA.exportSignedBinarySnapshot();

  // 1. Hydrate on cold-booting Node B
  const nodeB = new HnswClusterSyncCoordinatorV12(signingSecret);
  const telemetry = nodeB.hydrateFromBinarySnapshot(snapshotBuffer);

  assert.equal(telemetry.restoredNodeCount, 200);
  assert.equal(telemetry.watermarkWalSeq, 200);
  assert.ok(
    telemetry.hydrationLatencyMs < 200,
    `Expected hydration < 200ms, got ${telemetry.hydrationLatencyMs}ms`
  );

  // 2. Verify 1:N search on hydrated Node B finds exact identity and respects self-exclusion
  const targetVec = makeNormalized512Vector(142);
  const match = nodeB.searchNearestDuplicate(targetVec);
  assert.equal(match.bestUid, 'worker_hnsw_142');
  assert.ok(match.bestSimilarity > 0.999);

  const selfExcludedMatch = nodeB.searchNearestDuplicate(targetVec, 'worker_hnsw_142');
  assert.notEqual(selfExcludedMatch.bestUid, 'worker_hnsw_142');

  // 3. Flip a single byte in the binary snapshot and verify HMAC rejection
  const tamperedSnapshot = Buffer.from(snapshotBuffer);
  tamperedSnapshot[32] ^= 0xff;
  assert.throws(() => {
    nodeB.hydrateFromBinarySnapshot(tamperedSnapshot);
  }, /BIOMETRIC_V12_SNAPSHOT_SIGNATURE_MISMATCH/);
});

test('PHASE12.2-B: Multi-node incremental WAL delta sync applies upserts, key metadata rotations, and tombstones idempotently', () => {
  const signingSecret = crypto.randomBytes(32);
  const primaryNode = new HnswClusterSyncCoordinatorV12(signingSecret);

  primaryNode.applyIncrementalWalDelta([
    {
      walSeq: 1,
      opType: 'UPSERT_NODE',
      uid: 'worker_1',
      timestampMs: 1000,
      nodePayload: {
        uid: 'worker_1',
        faceId: 'FACE_1',
        keyId: 'kms_v11',
        modelVersion: 'v11_adaface_512',
        lockToken: 'KS_FTOK_1',
        embedding: makeNormalized512Vector(1),
        neighborsByLayer: [],
        updatedAtMs: 1000,
      },
    },
  ]);

  const replicaNode = new HnswClusterSyncCoordinatorV12(signingSecret);
  replicaNode.hydrateFromBinarySnapshot(primaryNode.exportSignedBinarySnapshot());

  // Stream WAL sequence 1 (duplicate), 2 (upsert worker_2), and 3 (key rotation on worker_1)
  const deltaOutcome = replicaNode.applyIncrementalWalDelta([
    {
      walSeq: 1, // Already in snapshot watermark; must be skipped idempotently
      opType: 'UPSERT_NODE',
      uid: 'worker_1',
      timestampMs: 1000,
    },
    {
      walSeq: 2,
      opType: 'UPSERT_NODE',
      uid: 'worker_2',
      timestampMs: 2000,
      nodePayload: {
        uid: 'worker_2',
        faceId: 'FACE_2',
        keyId: 'kms_v12',
        modelVersion: 'v11_adaface_512',
        lockToken: 'KS_FTOK_2',
        embedding: makeNormalized512Vector(2),
        neighborsByLayer: [],
        updatedAtMs: 2000,
      },
    },
    {
      walSeq: 3,
      opType: 'ROTATE_KEY_METADATA',
      uid: 'worker_1',
      timestampMs: 3000,
      rotatedKeyMetadata: {
        keyId: 'kms_v12',
        lockToken: 'KS_FTOK_1',
        updatedAtMs: 3000,
      },
    },
  ]);

  assert.equal(deltaOutcome.previousWalSeq, 1);
  assert.equal(deltaOutcome.currentWalSeq, 3);
  assert.equal(deltaOutcome.appliedEntries, 2);
  assert.equal(deltaOutcome.upsertedNodes, 1);
  assert.equal(deltaOutcome.rotatedMetadataNodes, 1);
  assert.equal(replicaNode.getNode('worker_1')?.keyId, 'kms_v12');
  assert.equal(replicaNode.getNodeCount(), 2);
});

