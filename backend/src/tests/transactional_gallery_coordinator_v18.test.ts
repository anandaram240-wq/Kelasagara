// File: backend/src/tests/transactional_gallery_coordinator_v18.test.ts
// KELASAGARA V18 / PHASE 13.3 — Multi-Node Auto-Retry & KMS Snapshot Hydration Tests

import { describe, it, beforeEach } from 'node:test';
import assert from 'node:assert/strict';

import {
  CloudKmsEnvelopeService,
  LocalDevKeyProvider,
  SFACE_EMBEDDING_DIMENSION,
  l2NormalizeSfaceVector,
} from '../crypto/cloud_kms_envelope';
import {
  FirestoreBiometricTransactionAdapterV18,
  FirestoreCollectionRefLike,
  FirestoreDatabaseLike,
  FirestoreDocRefLike,
  FirestoreDocSnapshotLike,
  FirestoreTransactionLike,
} from '../services/firestore_transaction_adapter_v18';
import { TransactionalGalleryCoordinatorV18 } from '../services/transactional_gallery_coordinator_v18';

export class SharedClusterFirestoreSimulator implements FirestoreDatabaseLike {
  private readonly store = new Map<
    string,
    { version: number; data: Record<string, unknown> }
  >();
  public onBeforeTransactionEntry?: () => Promise<void>;

  public collection<T = Record<string, unknown>>(
    collectionName: string,
  ): FirestoreCollectionRefLike<T> {
    return {
      doc: (docId: string): FirestoreDocRefLike<T> => {
        const fullPath = `${collectionName}/${docId}`;
        return {
          id: docId,
          path: fullPath,
          get: async (): Promise<FirestoreDocSnapshotLike<T>> => {
            const entry = this.store.get(fullPath);
            return {
              exists: entry !== undefined,
              id: docId,
              data: () =>
                entry
                  ? (structuredClone(entry.data) as unknown as T)
                  : undefined,
            };
          },
          set: async (data: T): Promise<void> => {
            const prev = this.store.get(fullPath);
            this.store.set(fullPath, {
              version: (prev?.version ?? 0) + 1,
              data: structuredClone(data) as Record<string, unknown>,
            });
          },
          delete: async (): Promise<void> => {
            this.store.delete(fullPath);
          },
        };
      },
      where: (field: string, op: '==' | '>' | '>=' | '<=', value: unknown) => ({
        get: async () => {
          const matching: Array<FirestoreDocSnapshotLike<T>> = [];
          for (const [k, v] of this.store.entries()) {
            if (!k.startsWith(`${collectionName}/`)) continue;
            const fieldVal = v.data[field] as number;
            const pass =
              (op === '==' && fieldVal === value) ||
              (op === '>' && fieldVal > (value as number)) ||
              (op === '>=' && fieldVal >= (value as number)) ||
              (op === '<=' && fieldVal <= (value as number));
            if (pass) {
              matching.push({
                exists: true,
                id: k.split('/')[1],
                data: () => structuredClone(v.data) as unknown as T,
              });
            }
          }
          return { docs: matching };
        },
      }),
      get: async () => {
        const docs: Array<FirestoreDocSnapshotLike<T>> = [];
        for (const [k, v] of this.store.entries()) {
          if (k.startsWith(`${collectionName}/`)) {
            docs.push({
              exists: true,
              id: k.split('/')[1],
              data: () => structuredClone(v.data) as unknown as T,
            });
          }
        }
        return { docs };
      },
    };
  }

  public async runTransaction<R>(
    updateFunction: (transaction: FirestoreTransactionLike) => Promise<R>,
  ): Promise<R> {
    if (this.onBeforeTransactionEntry) {
      const hook = this.onBeforeTransactionEntry;
      this.onBeforeTransactionEntry = undefined;
      await hook();
    }

    let writeStarted = false;
    const stagedWrites = new Map<string, Record<string, unknown> | null>();

    const tx: FirestoreTransactionLike = {
      get: async <T = Record<string, unknown>>(
        docRef: FirestoreDocRefLike<T>,
      ): Promise<FirestoreDocSnapshotLike<T>> => {
        if (writeStarted) {
          throw new Error('Reads must precede writes in Firestore transaction.');
        }
        const entry = this.store.get(docRef.path);
        return {
          exists: entry !== undefined,
          id: docRef.id,
          data: () =>
            entry ? (structuredClone(entry.data) as unknown as T) : undefined,
        };
      },
      set: <T = Record<string, unknown>>(
        docRef: FirestoreDocRefLike<T>,
        data: T,
      ): FirestoreTransactionLike => {
        writeStarted = true;
        stagedWrites.set(
          docRef.path,
          structuredClone(data) as Record<string, unknown>,
        );
        return tx;
      },
      delete: (
        docRef: FirestoreDocRefLike<unknown>,
      ): FirestoreTransactionLike => {
        writeStarted = true;
        stagedWrites.set(docRef.path, null);
        return tx;
      },
    };

    const res = await updateFunction(tx);
    for (const [docPath, payload] of stagedWrites.entries()) {
      if (payload === null) {
        this.store.delete(docPath);
      } else {
        const prev = this.store.get(docPath);
        this.store.set(docPath, {
          version: (prev?.version ?? 0) + 1,
          data: payload,
        });
      }
    }
    return res;
  }
}

function makeUnitVec128(seed: number): Float32Array {
  const vec = new Float32Array(SFACE_EMBEDDING_DIMENSION);
  let state = seed >>> 0;
  for (let i = 0; i < SFACE_EMBEDDING_DIMENSION; i++) {
    state = (state * 1664525 + 1013904223) >>> 0;
    vec[i] = (state / 4294967296) * 2.0 - 1.0;
  }
  return l2NormalizeSfaceVector(vec);
}

function perturbVecToCosine(
  base: Float32Array,
  targetCos: number,
  seed: number,
): Float32Array {
  const randomDir = makeUnitVec128(seed);
  let dot = 0.0;
  for (let i = 0; i < 128; i++) dot += base[i] * randomDir[i];

  const ortho = new Float32Array(128);
  let normSq = 0.0;
  for (let i = 0; i < 128; i++) {
    ortho[i] = randomDir[i] - dot * base[i];
    normSq += ortho[i] * ortho[i];
  }
  const inv = 1.0 / Math.sqrt(normSq);
  const sinT = Math.sqrt(Math.max(0.0, 1.0 - targetCos * targetCos));

  const out = new Float32Array(128);
  for (let i = 0; i < 128; i++) {
    out[i] = targetCos * base[i] + sinT * ortho[i] * inv;
  }
  return l2NormalizeSfaceVector(out);
}

describe('KELASAGARA V18 / PHASE 13.3 — TransactionalGalleryCoordinatorV18 Suite', () => {
  let sharedDb: SharedClusterFirestoreSimulator;
  let keyProvider: LocalDevKeyProvider;
  let kmsEnvelope: CloudKmsEnvelopeService;
  let nodeACoordinator: TransactionalGalleryCoordinatorV18;
  let nodeBCoordinator: TransactionalGalleryCoordinatorV18;
  let nodeCCoordinator: TransactionalGalleryCoordinatorV18;

  beforeEach(() => {
    sharedDb = new SharedClusterFirestoreSimulator();
    keyProvider = new LocalDevKeyProvider();
    kmsEnvelope = new CloudKmsEnvelopeService(keyProvider);

    nodeACoordinator = new TransactionalGalleryCoordinatorV18({
      txAdapter: new FirestoreBiometricTransactionAdapterV18(sharedDb),
      kmsEnvelope,
      kmsKeyProvider: keyProvider,
    });
    nodeBCoordinator = new TransactionalGalleryCoordinatorV18({
      txAdapter: new FirestoreBiometricTransactionAdapterV18(sharedDb),
      kmsEnvelope,
      kmsKeyProvider: keyProvider,
    });
    nodeCCoordinator = new TransactionalGalleryCoordinatorV18({
      txAdapter: new FirestoreBiometricTransactionAdapterV18(sharedDb),
      kmsEnvelope,
      kmsKeyProvider: keyProvider,
    });
  });

  it('1. Auto-recovers from RECHECK_REQUIRED_EPOCH_DRIFT via incremental WAL catch-up when two unrelated workers enroll concurrently', async () => {
    const workerAVec = makeUnitVec128(101);
    const workerBVec = makeUnitVec128(202);

    // Inject hook: right after Node B finishes screening at Epoch 0 (before Node B's transaction runs),
    // Node A commits Worker A (advancing globalEpoch from 0 -> 1).
    sharedDb.onBeforeTransactionEntry = async () => {
      await nodeACoordinator.enrollWorkerWithEpochFencedRetry({
        uid: 'KLS-WKR-NODE-A',
        maskedPhone: '******1111',
        idempotencyKey: 'idem-node-a-1',
        payload: {
          sfaceEmbedding128: workerAVec,
          isoQualityScore: 92.0,
          padLivenessScore: 0.96,
        },
      });
    };

    const resB = await nodeBCoordinator.enrollWorkerWithEpochFencedRetry({
      uid: 'KLS-WKR-NODE-B',
      maskedPhone: '******2222',
      idempotencyKey: 'idem-node-b-1',
      payload: {
        sfaceEmbedding128: workerBVec,
        isoQualityScore: 91.0,
        padLivenessScore: 0.95,
      },
    });

    // Node B detected epoch drift (0 -> 1), replayed Worker A from WAL, re-screened Worker B against Worker A,
    // and cleanly committed Worker B at Epoch 2!
    assert.equal(resB.enrolled, true);
    assert.equal(resB.decisionStatus, 'CLEAN_APPROVED');
    assert.equal(resB.committedGlobalEpoch, 2);
    assert.equal(resB.epochDriftRetriesUsed, 1);
    assert.equal(nodeBCoordinator.getActiveGallerySize(), 2);
  });

  it('2. Blocks concurrent cross-node duplicate fraud when the same face is submitted simultaneously to Node A and Node B', async () => {
    const fraudsterFace = makeUnitVec128(999);
    const sameFraudsterSecondCapture = perturbVecToCosine(
      fraudsterFace,
      0.95,
      1000,
    );

    // Right after Node B screens at Epoch 0 (seeing an empty gallery), Node A commits the same face at Epoch 1
    sharedDb.onBeforeTransactionEntry = async () => {
      const resA = await nodeACoordinator.enrollWorkerWithEpochFencedRetry({
        uid: 'KLS-FRAUD-ACCT-1',
        maskedPhone: '******5177',
        idempotencyKey: 'idem-fraud-1',
        payload: {
          sfaceEmbedding128: fraudsterFace,
          isoQualityScore: 93.0,
          padLivenessScore: 0.97,
        },
      });
      assert.equal(resA.enrolled, true);
      assert.equal(resA.committedGlobalEpoch, 1);
    };

    // Node B attempts to commit at screenedAtGlobalEpoch = 0 -> gets RECHECK_REQUIRED_EPOCH_DRIFT ->
    // pulls WAL entry 1 (`KLS-FRAUD-ACCT-1`) -> re-screens `KLS-FRAUD-ACCT-2` -> sees cosine 0.95 >= 0.90 ->
    // immediately halts with HARD_DUPLICATE_BLOCKED!
    const resB = await nodeBCoordinator.enrollWorkerWithEpochFencedRetry({
      uid: 'KLS-FRAUD-ACCT-2',
      maskedPhone: '******9988',
      idempotencyKey: 'idem-fraud-2',
      payload: {
        sfaceEmbedding128: sameFraudsterSecondCapture,
        isoQualityScore: 90.0,
        padLivenessScore: 0.95,
      },
    });

    assert.equal(resB.enrolled, false);
    assert.equal(resB.decisionStatus, 'HARD_DUPLICATE_BLOCKED');
    assert.equal(resB.duplicateSearch.matchedUid, 'KLS-FRAUD-ACCT-1');
    assert.equal(resB.epochDriftRetriesUsed, 1);
    assert.equal(nodeBCoordinator.getActiveGallerySize(), 1);
  });

  it('3. Exports KMS-wrapped KS18 encrypted snapshot and cold-boots Node C with incremental WAL tail replay', async () => {
    const vec1 = makeUnitVec128(301);
    const vec2 = makeUnitVec128(302);
    const vec3 = makeUnitVec128(303);

    await nodeACoordinator.enrollWorkerWithEpochFencedRetry({
      uid: 'KLS-SNAP-W1',
      maskedPhone: '******3001',
      idempotencyKey: 'idem-s1',
      payload: {
        sfaceEmbedding128: vec1,
        isoQualityScore: 90.0,
        padLivenessScore: 0.95,
      },
    });
    await nodeACoordinator.enrollWorkerWithEpochFencedRetry({
      uid: 'KLS-SNAP-W2',
      maskedPhone: '******3002',
      idempotencyKey: 'idem-s2',
      payload: {
        sfaceEmbedding128: vec2,
        isoQualityScore: 91.0,
        padLivenessScore: 0.96,
      },
    });

    // Export KMS-wrapped KS18 snapshot at Epoch 2
    const kmsSnapshotArtifact =
      await nodeACoordinator.exportKmsWrappedSnapshotKs18();
    assert.equal(kmsSnapshotArtifact.bundle.watermarkWalSeq, 2);

    // Enroll a 3rd worker AFTER the snapshot was taken (Epoch 3 in WAL tail)
    await nodeACoordinator.enrollWorkerWithEpochFencedRetry({
      uid: 'KLS-SNAP-W3',
      maskedPhone: '******3003',
      idempotencyKey: 'idem-s3',
      payload: {
        sfaceEmbedding128: vec3,
        isoQualityScore: 92.0,
        padLivenessScore: 0.97,
      },
    });

    // Cold-boot Node C using the Epoch 2 KMS snapshot + automatic WAL tail catch-up to Epoch 3
    const bootReport =
      await nodeCCoordinator.hydrateFromKmsSnapshotAndWalTail(
        kmsSnapshotArtifact,
      );

    assert.equal(bootReport.snapshotWatermark, 2);
    assert.equal(bootReport.finalEpochAfterWalTail, 3);
    assert.equal(bootReport.activeGallerySize, 3);
    assert.ok(bootReport.snapshotHydrationLatencyMs < 200.0);

    // Verify Node C can immediately authenticate Worker 3 (from WAL tail) and Worker 1 (from KS18 snapshot)
    const verifyW1 = await nodeCCoordinator.verifyWorker1to1('KLS-SNAP-W1', {
      sfaceEmbedding128: perturbVecToCosine(vec1, 0.85, 401),
      isoQualityScore: 88.0,
      padLivenessScore: 0.92,
    });
    const verifyW3 = await nodeCCoordinator.verifyWorker1to1('KLS-SNAP-W3', {
      sfaceEmbedding128: perturbVecToCosine(vec3, 0.85, 403),
      isoQualityScore: 88.0,
      padLivenessScore: 0.92,
    });

    assert.equal(verifyW1.verified, true);
    assert.equal(verifyW3.verified, true);
  });
});
