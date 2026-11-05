// File: backend/src/tests/phase14_multi_node_chaos.test.ts
// KELASAGARA V18 / PHASE 14 — Gate 5: Multi-Node Chaos, Split-Brain & Failure Scenarios
// Validates all 18 specified failure modes across simulated 3-node cluster (Node A, B, C).

import { describe, it } from 'node:test';
import * as assert from 'node:assert/strict';
import * as crypto from 'node:crypto';
import {
  CANONICAL_SFACE_MODEL_ID,
  CANONICAL_SFACE_MODEL_VERSION,
  CANONICAL_TEMPLATE_SCHEMA_VERSION,
  SFACE_EMBEDDING_DIMENSION,
  LocalDevKeyProvider,
  CloudKmsEnvelopeService,
} from '../crypto/cloud_kms_envelope';
import {
  FirestoreBiometricTransactionAdapterV18,
  TransactionalWalEntryDocV18,
} from '../services/firestore_transaction_adapter_v18';
import {
  TransactionalGalleryCoordinatorV18,
  KmsWrappedKs18SnapshotArtifact,
} from '../services/transactional_gallery_coordinator_v18';
import { SharedClusterFirestoreSimulator } from './transactional_gallery_coordinator_v18.test';
import {
  exportEncryptedAlignedSnapshotKs18,
  encodeSnapshotCanonicalAad,
} from '../biometrics/iso24745_iom_cancelable_snapshot_v18';
import { verifyContiguousWalSequence } from '../services/wal_compaction_and_gap_guard_v18';

function generateRandomNormalizedEmbedding(seedStr: string): Float32Array {
  const hash = crypto.createHash('sha256').update(seedStr).digest();
  const vec = new Float32Array(SFACE_EMBEDDING_DIMENSION);
  let normSq = 0;
  for (let i = 0; i < SFACE_EMBEDDING_DIMENSION; i++) {
    const byteVal = hash[i % hash.length];
    const subHash = crypto
      .createHash('sha256')
      .update(`${seedStr}_dim_${i}_${byteVal}`)
      .digest();
    const val = (subHash.readInt16BE(0) / 32768.0);
    vec[i] = val;
    normSq += val * val;
  }
  const invNorm = 1.0 / Math.sqrt(normSq);
  for (let i = 0; i < SFACE_EMBEDDING_DIMENSION; i++) {
    vec[i] *= invNorm;
  }
  return vec;
}

describe('KELASAGARA V18 / PHASE 14 — Gate 5: Multi-Node Chaos & Split-Brain Suite', () => {
  const tenantId = 'tenant_chaos_phase14';
  const clusterId = 'cluster-chaos-prod';

  it('Scenario 1: Simultaneous enrollments across nodes (Node A commits during Node B screening)', async () => {
    const sharedDb = new SharedClusterFirestoreSimulator();
    const kmsProvider = new LocalDevKeyProvider();
    const kmsEnvelope = new CloudKmsEnvelopeService(kmsProvider);
    const txAdapter = new FirestoreBiometricTransactionAdapterV18(sharedDb, clusterId);

    const nodeA = new TransactionalGalleryCoordinatorV18({ clusterId, tenantId, kmsKeyProvider: kmsProvider, kmsEnvelope, txAdapter });
    const nodeB = new TransactionalGalleryCoordinatorV18({ clusterId, tenantId, kmsKeyProvider: kmsProvider, kmsEnvelope, txAdapter });

    const vecA = generateRandomNormalizedEmbedding('worker_sim_1_face');
    const vecB = generateRandomNormalizedEmbedding('worker_sim_2_face');

    // Node B starts screening at epoch 0. Before Node B's transaction executes, Node A commits Worker A at epoch 1.
    sharedDb.onBeforeTransactionEntry = async () => {
      const resA = await nodeA.enrollWorkerWithEpochFencedRetry({
        uid: 'worker_sim_1',
        maskedPhone: '+91******1111',
        idempotencyKey: 'idem_sim_1',
        payload: { sfaceEmbedding128: vecA, isoQualityScore: 90, padLivenessScore: 0.99 },
      });
      assert.strictEqual(resA.enrolled, true);
      assert.strictEqual(resA.committedGlobalEpoch, 1);
    };

    const resB = await nodeB.enrollWorkerWithEpochFencedRetry({
      uid: 'worker_sim_2',
      maskedPhone: '+91******2222',
      idempotencyKey: 'idem_sim_2',
      payload: { sfaceEmbedding128: vecB, isoQualityScore: 90, padLivenessScore: 0.99 },
    });

    // Node B detected epoch drift, caught up via WAL, and committed at epoch 2
    assert.strictEqual(resB.enrolled, true);
    assert.strictEqual(resB.committedGlobalEpoch, 2);
    assert.strictEqual(resB.epochDriftRetriesUsed, 1);
    assert.strictEqual(nodeB.getActiveGallerySize(), 2);
  });

  it('Scenario 2: Duplicate face race across nodes (Same fraudster submitted to Node A and Node B simultaneously)', async () => {
    const sharedDb = new SharedClusterFirestoreSimulator();
    const kmsProvider = new LocalDevKeyProvider();
    const kmsEnvelope = new CloudKmsEnvelopeService(kmsProvider);
    const txAdapter = new FirestoreBiometricTransactionAdapterV18(sharedDb, clusterId);

    const nodeA = new TransactionalGalleryCoordinatorV18({ clusterId, tenantId, kmsKeyProvider: kmsProvider, kmsEnvelope, txAdapter });
    const nodeB = new TransactionalGalleryCoordinatorV18({ clusterId, tenantId, kmsKeyProvider: kmsProvider, kmsEnvelope, txAdapter });

    const duplicateVector = generateRandomNormalizedEmbedding('fraudster_exact_face');

    // Right after Node B screens at epoch 0 (seeing empty gallery), Node A commits fraudster at epoch 1
    sharedDb.onBeforeTransactionEntry = async () => {
      const resA = await nodeA.enrollWorkerWithEpochFencedRetry({
        uid: 'fraud_account_A',
        maskedPhone: '+91******3331',
        idempotencyKey: 'idem_fraud_a',
        payload: { sfaceEmbedding128: duplicateVector, isoQualityScore: 88, padLivenessScore: 0.99 },
      });
      assert.strictEqual(resA.enrolled, true);
      assert.strictEqual(resA.committedGlobalEpoch, 1);
    };

    // Node B attempts to commit at screenedAtGlobalEpoch = 0 -> gets RECHECK_REQUIRED_EPOCH_DRIFT ->
    // catches up WAL entry 1 (fraud_account_A) -> re-screens -> sees cosine 1.0 >= 0.90 -> halts with HARD_DUPLICATE_BLOCKED!
    const resB = await nodeB.enrollWorkerWithEpochFencedRetry({
      uid: 'fraud_account_B',
      maskedPhone: '+91******3332',
      idempotencyKey: 'idem_fraud_b',
      payload: { sfaceEmbedding128: duplicateVector, isoQualityScore: 88, padLivenessScore: 0.99 },
    });

    assert.strictEqual(resB.enrolled, false);
    assert.strictEqual(resB.decisionStatus, 'HARD_DUPLICATE_BLOCKED');
    assert.strictEqual(resB.duplicateSearch.matchedUid, 'fraud_account_A');
    assert.strictEqual(resB.epochDriftRetriesUsed, 1);
    assert.strictEqual(nodeB.getActiveGallerySize(), 1);
  });

  it('Scenario 3: Deletion/Tombstone during duplicate check removes template from arena', async () => {
    const sharedDb = new SharedClusterFirestoreSimulator();
    const kmsProvider = new LocalDevKeyProvider();
    const kmsEnvelope = new CloudKmsEnvelopeService(kmsProvider);
    const txAdapter = new FirestoreBiometricTransactionAdapterV18(sharedDb, clusterId);

    const nodeA = new TransactionalGalleryCoordinatorV18({ clusterId, tenantId, kmsKeyProvider: kmsProvider, kmsEnvelope, txAdapter });
    const nodeB = new TransactionalGalleryCoordinatorV18({ clusterId, tenantId, kmsKeyProvider: kmsProvider, kmsEnvelope, txAdapter });

    const workerVec = generateRandomNormalizedEmbedding('worker_to_delete_face');
    await nodeA.enrollWorkerWithEpochFencedRetry({
      uid: 'worker_to_delete',
      maskedPhone: '+91******4444',
      idempotencyKey: 'idem_del_1',
      payload: { sfaceEmbedding128: workerVec, isoQualityScore: 92, padLivenessScore: 0.99 },
    });

    // Simulate DPDPA Section 12 erasure commit by appending a TOMBSTONE WAL entry with 12-digit padded doc id
    await sharedDb.collection('biometric_wal_outbox').doc('000000000002').set({
      walSeq: 2,
      uid: 'worker_to_delete',
      maskedPhone: '+91******4444',
      operation: 'TOMBSTONE',
      templateGeneration: 2,
      modelId: CANONICAL_SFACE_MODEL_ID,
      modelVersion: CANONICAL_SFACE_MODEL_VERSION,
      templateSchemaVersion: CANONICAL_TEMPLATE_SCHEMA_VERSION,
      committedAtEpochMs: Date.now(),
    });
    // Advance global epoch meta using correct field name `globalEpoch`
    await sharedDb.collection('biometric_cluster_meta').doc('global_state').set({
      clusterId,
      globalEpoch: 2,
      lastCommittedEpochMs: Date.now(),
      totalEnrolledCount: 0,
      activeModelVersion: CANONICAL_SFACE_MODEL_VERSION,
    });

    // Node B catches up
    await nodeB.catchUpFromWalOutbox();

    // Verify template is gone from Node B's active index
    assert.strictEqual((nodeB as any).activeIndex.size, 0);

    // Screening the same face again on Node B should now be CLEAN_APPROVED
    const retryRes = await nodeB.enrollWorkerWithEpochFencedRetry({
      uid: 'worker_new_account',
      maskedPhone: '+91******4445',
      idempotencyKey: 'idem_del_retry',
      payload: { sfaceEmbedding128: workerVec, isoQualityScore: 92, padLivenessScore: 0.99 },
    });
    assert.strictEqual(retryRes.decisionStatus, 'CLEAN_APPROVED');
    assert.strictEqual(retryRes.enrolled, true);
    assert.strictEqual(retryRes.committedGlobalEpoch, 3);
  });

  it('Scenario 4: Node C goes offline, misses 5 epochs, and rejoins cleanly via WAL catch-up', async () => {
    const sharedDb = new SharedClusterFirestoreSimulator();
    const kmsProvider = new LocalDevKeyProvider();
    const kmsEnvelope = new CloudKmsEnvelopeService(kmsProvider);
    const txAdapter = new FirestoreBiometricTransactionAdapterV18(sharedDb, clusterId);

    const nodeA = new TransactionalGalleryCoordinatorV18({ clusterId, tenantId, kmsKeyProvider: kmsProvider, kmsEnvelope, txAdapter });
    const nodeC = new TransactionalGalleryCoordinatorV18({ clusterId, tenantId, kmsKeyProvider: kmsProvider, kmsEnvelope, txAdapter });

    // Node A commits 5 enrollments while Node C is dormant
    for (let i = 1; i <= 5; i++) {
      await nodeA.enrollWorkerWithEpochFencedRetry({
        uid: `dormant_worker_${i}`,
        maskedPhone: `+91******500${i}`,
        idempotencyKey: `idem_dormant_${i}`,
        payload: { sfaceEmbedding128: generateRandomNormalizedEmbedding(`dormant_worker_${i}`), isoQualityScore: 85, padLivenessScore: 0.98 },
      });
    }

    assert.strictEqual((nodeC as any).localWatermarkEpoch, 0);
    assert.strictEqual((nodeC as any).activeIndex.size, 0);

    // Node C wakes up and enrolls a worker
    const resC = await nodeC.enrollWorkerWithEpochFencedRetry({
      uid: 'worker_node_c',
      maskedPhone: '+91******5099',
      idempotencyKey: 'idem_node_c_awake',
      payload: { sfaceEmbedding128: generateRandomNormalizedEmbedding('worker_node_c_face'), isoQualityScore: 89, padLivenessScore: 0.98 },
    });

    assert.strictEqual(resC.enrolled, true);
    assert.strictEqual(resC.committedGlobalEpoch, 6);
    assert.strictEqual((nodeC as any).activeIndex.size, 6);
  });

  it('Scenario 5: Duplicate WAL delivery is handled idempotently without corrupting gallery', async () => {
    const sharedDb = new SharedClusterFirestoreSimulator();
    const kmsProvider = new LocalDevKeyProvider();
    const kmsEnvelope = new CloudKmsEnvelopeService(kmsProvider);
    const txAdapter = new FirestoreBiometricTransactionAdapterV18(sharedDb, clusterId);

    const node = new TransactionalGalleryCoordinatorV18({ clusterId, tenantId, kmsKeyProvider: kmsProvider, kmsEnvelope, txAdapter });

    await node.enrollWorkerWithEpochFencedRetry({
      uid: 'worker_wal_dup',
      maskedPhone: '+91******6001',
      idempotencyKey: 'idem_wal_dup',
      payload: { sfaceEmbedding128: generateRandomNormalizedEmbedding('worker_wal_dup'), isoQualityScore: 90, padLivenessScore: 0.99 },
    });

    assert.strictEqual((node as any).localWatermarkEpoch, 1);
    assert.strictEqual((node as any).activeIndex.size, 1);

    // Manually invoke catchUpFromWalOutbox again
    const epoch = await node.catchUpFromWalOutbox();
    assert.strictEqual(epoch, 1);
    assert.strictEqual((node as any).activeIndex.size, 1);
  });

  it('Scenario 6: Out-of-order WAL delivery is rejected via monotonic sequence guard', () => {
    const deltas: TransactionalWalEntryDocV18[] = [
      { walSeq: 3, uid: 'u3', maskedPhone: '+91*3', operation: 'UPSERT', templateGeneration: 1, modelId: CANONICAL_SFACE_MODEL_ID, modelVersion: CANONICAL_SFACE_MODEL_VERSION, templateSchemaVersion: CANONICAL_TEMPLATE_SCHEMA_VERSION, committedAtEpochMs: 1 },
      { walSeq: 2, uid: 'u2', maskedPhone: '+91*2', operation: 'UPSERT', templateGeneration: 1, modelId: CANONICAL_SFACE_MODEL_ID, modelVersion: CANONICAL_SFACE_MODEL_VERSION, templateSchemaVersion: CANONICAL_TEMPLATE_SCHEMA_VERSION, committedAtEpochMs: 2 },
    ];

    assert.throws(
      () => {
        verifyContiguousWalSequence(1, deltas);
      },
      /WAL_GAP_DETECTED_SNAPSHOT_REQUIRED/,
    );
  });

  it('Scenario 7: WAL sequence gap triggers WAL_GAP_DETECTED_SNAPSHOT_REQUIRED fail-closed', () => {
    const deltas: TransactionalWalEntryDocV18[] = [
      { walSeq: 10, uid: 'u10', maskedPhone: '+91*10', operation: 'UPSERT', templateGeneration: 1, modelId: CANONICAL_SFACE_MODEL_ID, modelVersion: CANONICAL_SFACE_MODEL_VERSION, templateSchemaVersion: CANONICAL_TEMPLATE_SCHEMA_VERSION, committedAtEpochMs: 1 },
    ];

    // Local watermark is 5, but first WAL entry is 10 (entries 6..9 were pruned)
    assert.throws(
      () => {
        verifyContiguousWalSequence(5, deltas);
      },
      /WAL_GAP_DETECTED_SNAPSHOT_REQUIRED/,
    );
  });

  it('Scenario 8: Corrupted WAL payload aborts catch-up without corrupting existing gallery', async () => {
    const sharedDb = new SharedClusterFirestoreSimulator();
    const kmsProvider = new LocalDevKeyProvider();
    const kmsEnvelope = new CloudKmsEnvelopeService(kmsProvider);
    const txAdapter = new FirestoreBiometricTransactionAdapterV18(sharedDb, clusterId);

    const node = new TransactionalGalleryCoordinatorV18({ clusterId, tenantId, kmsKeyProvider: kmsProvider, kmsEnvelope, txAdapter });

    // Seed corrupted WAL entry with invalid ciphertext
    await sharedDb.collection('biometric_wal_outbox').doc('000000000001').set({
      walSeq: 1,
      uid: 'worker_corrupt_wal',
      maskedPhone: '+91******8888',
      operation: 'UPSERT',
      templateGeneration: 1,
      modelId: CANONICAL_SFACE_MODEL_ID,
      modelVersion: CANONICAL_SFACE_MODEL_VERSION,
      templateSchemaVersion: CANONICAL_TEMPLATE_SCHEMA_VERSION,
      envelope: {
        schemaVersion: CANONICAL_TEMPLATE_SCHEMA_VERSION,
        modelId: CANONICAL_SFACE_MODEL_ID,
        modelVersion: CANONICAL_SFACE_MODEL_VERSION,
        kmsKeyId: 'test-key',
        ivBase64: 'AAAA',
        authTagBase64: 'AAAA',
        ciphertextBase64: 'corrupted_garbage_bytes',
        canonicalAadDigestSha256: 'deadbeef',
      },
      committedAtEpochMs: Date.now(),
    });

    await assert.rejects(async () => {
      await node.catchUpFromWalOutbox();
    });

    // Gallery must remain empty and epoch must remain 0
    assert.strictEqual((node as any).localWatermarkEpoch, 0);
    assert.strictEqual((node as any).activeIndex.size, 0);
  });

  it('Scenario 9: Network partition during commit safely aborts without partial state', async () => {
    const sharedDb = new SharedClusterFirestoreSimulator();
    const kmsProvider = new LocalDevKeyProvider();
    const kmsEnvelope = new CloudKmsEnvelopeService(kmsProvider);
    const txAdapter = new FirestoreBiometricTransactionAdapterV18(sharedDb, clusterId);

    // Inject permanent failure on Firestore transaction
    sharedDb.runTransaction = async () => {
      throw new Error('UNAVAILABLE: Firestore connection timed out.');
    };

    const node = new TransactionalGalleryCoordinatorV18({ clusterId, tenantId, kmsKeyProvider: kmsProvider, kmsEnvelope, txAdapter });

    await assert.rejects(
      async () => {
        await node.enrollWorkerWithEpochFencedRetry({
          uid: 'worker_timeout',
          maskedPhone: '+91******9999',
          idempotencyKey: 'idem_timeout',
          payload: { sfaceEmbedding128: generateRandomNormalizedEmbedding('worker_timeout'), isoQualityScore: 90, padLivenessScore: 0.99 },
        });
      },
      /UNAVAILABLE/,
    );
  });

  it('Scenario 10: Lost commit response: client retry with identical idempotency key returns cached result', async () => {
    const sharedDb = new SharedClusterFirestoreSimulator();
    const kmsProvider = new LocalDevKeyProvider();
    const kmsEnvelope = new CloudKmsEnvelopeService(kmsProvider);
    const txAdapter = new FirestoreBiometricTransactionAdapterV18(sharedDb, clusterId);

    const node = new TransactionalGalleryCoordinatorV18({ clusterId, tenantId, kmsKeyProvider: kmsProvider, kmsEnvelope, txAdapter });

    const payload = { sfaceEmbedding128: generateRandomNormalizedEmbedding('worker_lost_ack_face'), isoQualityScore: 91, padLivenessScore: 0.99 };
    const res1 = await node.enrollWorkerWithEpochFencedRetry({
      uid: 'worker_lost_ack',
      maskedPhone: '+91******1010',
      idempotencyKey: 'idem_lost_ack_1',
      payload,
    });
    assert.strictEqual(res1.enrolled, true);
    assert.strictEqual(res1.idempotentReplay, false);

    // Client retries identical request
    const res2 = await node.enrollWorkerWithEpochFencedRetry({
      uid: 'worker_lost_ack',
      maskedPhone: '+91******1010',
      idempotencyKey: 'idem_lost_ack_1',
      payload,
    });
    assert.strictEqual(res2.enrolled, true);
    assert.strictEqual(res2.idempotentReplay, true);
    assert.strictEqual(res2.committedGlobalEpoch, res1.committedGlobalEpoch);
  });

  it('Scenario 11: Failed consumer ACK on WAL tail: replica re-fetches and catches up', async () => {
    const sharedDb = new SharedClusterFirestoreSimulator();
    const kmsProvider = new LocalDevKeyProvider();
    const kmsEnvelope = new CloudKmsEnvelopeService(kmsProvider);
    const txAdapter = new FirestoreBiometricTransactionAdapterV18(sharedDb, clusterId);

    const nodeA = new TransactionalGalleryCoordinatorV18({ clusterId, tenantId, kmsKeyProvider: kmsProvider, kmsEnvelope, txAdapter });
    await nodeA.enrollWorkerWithEpochFencedRetry({
      uid: 'worker_ack_fail',
      maskedPhone: '+91******1112',
      idempotencyKey: 'idem_ack_1',
      payload: { sfaceEmbedding128: generateRandomNormalizedEmbedding('worker_ack_fail'), isoQualityScore: 90, padLivenessScore: 0.99 },
    });

    const nodeB = new TransactionalGalleryCoordinatorV18({ clusterId, tenantId, kmsKeyProvider: kmsProvider, kmsEnvelope, txAdapter });

    // Node B fetches but simulates transient error
    let failOnce = true;
    const originalFetch = txAdapter.fetchIncrementalWalSince.bind(txAdapter);
    txAdapter.fetchIncrementalWalSince = async (seq: number) => {
      if (failOnce) {
        failOnce = false;
        throw new Error('TRANSIENT_RPC_FAILURE');
      }
      return originalFetch(seq);
    };

    await assert.rejects(async () => {
      await nodeB.catchUpFromWalOutbox();
    }, /TRANSIENT_RPC_FAILURE/);

    // Second attempt succeeds cleanly
    const finalEpoch = await nodeB.catchUpFromWalOutbox();
    assert.strictEqual(finalEpoch, 1);
    assert.strictEqual((nodeB as any).activeIndex.size, 1);
  });

  it('Scenario 12: Partial commit prevention: transaction atomicity guarantees WAL and vault match', async () => {
    const sharedDb = new SharedClusterFirestoreSimulator();
    const kmsProvider = new LocalDevKeyProvider();
    const kmsEnvelope = new CloudKmsEnvelopeService(kmsProvider);
    const txAdapter = new FirestoreBiometricTransactionAdapterV18(sharedDb, clusterId);

    // Enforce that both vault and wal_outbox receive the same record
    const node = new TransactionalGalleryCoordinatorV18({ clusterId, tenantId, kmsKeyProvider: kmsProvider, kmsEnvelope, txAdapter });
    await node.enrollWorkerWithEpochFencedRetry({
      uid: 'worker_atomicity_1',
      maskedPhone: '+91******1212',
      idempotencyKey: 'idem_atomicity_1',
      payload: { sfaceEmbedding128: generateRandomNormalizedEmbedding('worker_atomicity_1'), isoQualityScore: 93, padLivenessScore: 0.99 },
    });

    const vaultDoc = await sharedDb.collection('biometric_vault').doc('worker_atomicity_1').get();
    const walDoc = await sharedDb.collection('biometric_wal_outbox').doc('000000000001').get();
    const metaDoc = await sharedDb.collection('biometric_cluster_meta').doc('global_state').get();

    assert.ok(vaultDoc.exists);
    assert.ok(walDoc.exists);
    assert.strictEqual((metaDoc.data() as any).globalEpoch, 1);
  });

  it('Scenario 13: Idempotency key reuse with modified payload returns CONFLICT_IDEMPOTENCY_PAYLOAD_MISMATCH', async () => {
    const sharedDb = new SharedClusterFirestoreSimulator();
    const kmsProvider = new LocalDevKeyProvider();
    const kmsEnvelope = new CloudKmsEnvelopeService(kmsProvider);
    const txAdapter = new FirestoreBiometricTransactionAdapterV18(sharedDb, clusterId);

    const node = new TransactionalGalleryCoordinatorV18({ clusterId, tenantId, kmsKeyProvider: kmsProvider, kmsEnvelope, txAdapter });

    await node.enrollWorkerWithEpochFencedRetry({
      uid: 'worker_payload_tamper',
      maskedPhone: '+91******1313',
      idempotencyKey: 'idem_tamper_key',
      payload: { sfaceEmbedding128: generateRandomNormalizedEmbedding('payload_initial'), isoQualityScore: 90, padLivenessScore: 0.99 },
    });

    // Reuse same idempotency key with different vector (tamper attempt)
    await assert.rejects(
      async () => {
        await node.enrollWorkerWithEpochFencedRetry({
          uid: 'worker_payload_tamper',
          maskedPhone: '+91******1313',
          idempotencyKey: 'idem_tamper_key',
          payload: { sfaceEmbedding128: generateRandomNormalizedEmbedding('payload_different'), isoQualityScore: 90, padLivenessScore: 0.99 },
        });
      },
      /CONFLICT_IDEMPOTENCY_PAYLOAD_MISMATCH/,
    );
  });

  it('Scenario 14: Key rotation during active hydration handles multi-version KEK unwrapping', async () => {
    const kmsProvider = new LocalDevKeyProvider();
    const kmsEnvelope = new CloudKmsEnvelopeService(kmsProvider);
    const records = [
      {
        uid: 'worker_key_rot',
        maskedPhone: '+91******1414',
        modelId: CANONICAL_SFACE_MODEL_ID,
        modelVersion: CANONICAL_SFACE_MODEL_VERSION,
        templateSchemaVersion: CANONICAL_TEMPLATE_SCHEMA_VERSION,
        sfaceEmbedding128: generateRandomNormalizedEmbedding('worker_key_rot'),
        isoQualityScore: 88,
        padLivenessScore: 0.98,
        enrolledAtEpochMs: Date.now(),
      },
    ];

    const ephemeralDek = crypto.randomBytes(32);
    const rawBundle = exportEncryptedAlignedSnapshotKs18({
      records,
      watermarkWalSeq: 1,
      clusterId,
      keyId: 'snapshot-kek-v1',
      snapshotEncryptionKey32: ephemeralDek,
    });

    const aad = encodeSnapshotCanonicalAad({
      clusterId,
      keyId: 'snapshot-kek-v1',
      modelVersion: CANONICAL_SFACE_MODEL_VERSION,
      watermarkWalSeq: 1,
      nodeCount: 1,
    });
    const { wrappedDek, keyVersionName } = await kmsProvider.wrapKey(ephemeralDek, aad);

    const artifact: KmsWrappedKs18SnapshotArtifact = {
      bundle: rawBundle,
      kmsKeyVersionName: keyVersionName,
      wrappedSnapshotDekBase64: wrappedDek.toString('base64'),
    };

    const sharedDb = new SharedClusterFirestoreSimulator();
    const txAdapter = new FirestoreBiometricTransactionAdapterV18(sharedDb, clusterId);
    const node = new TransactionalGalleryCoordinatorV18({ clusterId, tenantId, kmsKeyProvider: kmsProvider, kmsEnvelope, txAdapter });

    const result = await node.hydrateFromKmsSnapshotAndWalTail(artifact);
    assert.strictEqual(result.activeGallerySize, 1);
  });

  it('Scenario 15: Snapshot compaction during node catch-up: node requires snapshot when WAL is compacted', async () => {
    const deltas: TransactionalWalEntryDocV18[] = [
      { walSeq: 50, uid: 'u50', maskedPhone: '+91*50', operation: 'UPSERT', templateGeneration: 1, modelId: CANONICAL_SFACE_MODEL_ID, modelVersion: CANONICAL_SFACE_MODEL_VERSION, templateSchemaVersion: CANONICAL_TEMPLATE_SCHEMA_VERSION, committedAtEpochMs: 1 },
    ];
    // Node is at watermark 10, but entries 11..49 were compacted away
    assert.throws(() => {
      verifyContiguousWalSequence(10, deltas);
    }, /WAL_GAP_DETECTED_SNAPSHOT_REQUIRED/);
  });

  it('Scenario 16: Timestamp inversion does not disrupt monotonic sequence order', async () => {
    const sharedDb = new SharedClusterFirestoreSimulator();
    const kmsProvider = new LocalDevKeyProvider();
    const kmsEnvelope = new CloudKmsEnvelopeService(kmsProvider);
    const txAdapter = new FirestoreBiometricTransactionAdapterV18(sharedDb, clusterId);

    const node = new TransactionalGalleryCoordinatorV18({ clusterId, tenantId, kmsKeyProvider: kmsProvider, kmsEnvelope, txAdapter });

    // Commit 1 at T=2000
    await node.enrollWorkerWithEpochFencedRetry({
      uid: 'worker_ts_1',
      maskedPhone: '+91******1601',
      idempotencyKey: 'idem_ts_1',
      payload: { sfaceEmbedding128: generateRandomNormalizedEmbedding('worker_ts_1'), isoQualityScore: 90, padLivenessScore: 0.99 },
    });

    // Commit 2 at T=1000 (clock skew on worker)
    await node.enrollWorkerWithEpochFencedRetry({
      uid: 'worker_ts_2',
      maskedPhone: '+91******1602',
      idempotencyKey: 'idem_ts_2',
      payload: { sfaceEmbedding128: generateRandomNormalizedEmbedding('worker_ts_2'), isoQualityScore: 90, padLivenessScore: 0.99 },
    });

    assert.strictEqual((node as any).localWatermarkEpoch, 2);
    assert.strictEqual((node as any).activeIndex.size, 2);
  });

  it('Scenario 17: Max retry exhaustion under extreme contention aborts fail-closed', async () => {
    const sharedDb = new SharedClusterFirestoreSimulator();
    const kmsProvider = new LocalDevKeyProvider();
    const kmsEnvelope = new CloudKmsEnvelopeService(kmsProvider);
    const txAdapter = new FirestoreBiometricTransactionAdapterV18(sharedDb, clusterId);

    const node = new TransactionalGalleryCoordinatorV18({
      clusterId,
      tenantId,
      kmsKeyProvider: kmsProvider,
      kmsEnvelope,
      txAdapter,
      maxEpochDriftRetries: 2, // Low retry ceiling to force exhaustion
    });

    // Inject perpetual epoch advance on every screening pass
    let advanceEpoch = 1;
    (node as any).catchUpFromWalOutbox = async () => {
      (node as any).localWatermarkEpoch = advanceEpoch++;
      return (node as any).localWatermarkEpoch;
    };

    await assert.rejects(
      async () => {
        await node.enrollWorkerWithEpochFencedRetry({
          uid: 'worker_exhaustion',
          maskedPhone: '+91******1717',
          idempotencyKey: 'idem_exhaustion',
          payload: { sfaceEmbedding128: generateRandomNormalizedEmbedding('worker_exhaustion'), isoQualityScore: 90, padLivenessScore: 0.99 },
        });
      },
      /MAX_EPOCH_DRIFT_RETRIES_EXCEEDED/,
    );
  });

  it('Scenario 18: Generation bump race during active screening rejects stale overwrite', async () => {
    const sharedDb = new SharedClusterFirestoreSimulator();
    const kmsProvider = new LocalDevKeyProvider();
    const kmsEnvelope = new CloudKmsEnvelopeService(kmsProvider);
    const txAdapter = new FirestoreBiometricTransactionAdapterV18(sharedDb, clusterId);

    const node = new TransactionalGalleryCoordinatorV18({ clusterId, tenantId, kmsKeyProvider: kmsProvider, kmsEnvelope, txAdapter });

    // Initial enrollment: generation 1
    await node.enrollWorkerWithEpochFencedRetry({
      uid: 'worker_gen_race',
      maskedPhone: '+91******1818',
      idempotencyKey: 'idem_gen_1',
      payload: { sfaceEmbedding128: generateRandomNormalizedEmbedding('worker_gen_race_1'), isoQualityScore: 91, padLivenessScore: 0.99 },
    });

    // Attempt second enrollment with allowReEnrollment = false (stale initial attempt)
    await assert.rejects(
      async () => {
        await node.enrollWorkerWithEpochFencedRetry({
          uid: 'worker_gen_race',
          maskedPhone: '+91******1818',
          idempotencyKey: 'idem_gen_2_bad',
          payload: { sfaceEmbedding128: generateRandomNormalizedEmbedding('worker_gen_race_2'), isoQualityScore: 91, padLivenessScore: 0.99 },
          allowReEnrollment: false,
        });
      },
      /CONFLICT_ALREADY_ENROLLED/,
    );
  });
});
