// File: backend/src/tests/wal_compaction_and_gap_guard_v18.test.ts
// KELASAGARA V18 / PHASE 13.4 — WAL Compaction & Sequence Gap Recovery Tests

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
import {
  WalCompactorServiceV18,
  verifyContiguousWalSequence,
} from '../services/wal_compaction_and_gap_guard_v18';

class CompactionTestFirestoreHarness implements FirestoreDatabaseLike {
  private readonly store = new Map<string, Record<string, unknown>>();

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
            const data = this.store.get(fullPath);
            return {
              exists: data !== undefined,
              id: docId,
              data: () =>
                data ? (structuredClone(data) as unknown as T) : undefined,
            };
          },
          set: async (data: T): Promise<void> => {
            this.store.set(
              fullPath,
              structuredClone(data) as Record<string, unknown>,
            );
          },
          delete: async (): Promise<void> => {
            this.store.delete(fullPath);
          },
        };
      },
      where: (field: string, op: '==' | '>' | '>=' | '<=', value: unknown) => ({
        get: async () => {
          const docs: Array<FirestoreDocSnapshotLike<T>> = [];
          for (const [k, v] of this.store.entries()) {
            if (!k.startsWith(`${collectionName}/`)) continue;
            const fVal = v[field] as number;
            const match =
              (op === '==' && fVal === value) ||
              (op === '>' && fVal > (value as number)) ||
              (op === '>=' && fVal >= (value as number)) ||
              (op === '<=' && fVal <= (value as number));
            if (match) {
              docs.push({
                exists: true,
                id: k.split('/')[1],
                data: () => structuredClone(v) as unknown as T,
              });
            }
          }
          return { docs };
        },
      }),
      get: async () => {
        const docs: Array<FirestoreDocSnapshotLike<T>> = [];
        for (const [k, v] of this.store.entries()) {
          if (k.startsWith(`${collectionName}/`)) {
            docs.push({
              exists: true,
              id: k.split('/')[1],
              data: () => structuredClone(v) as unknown as T,
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
    const staged = new Map<string, Record<string, unknown> | null>();
    const tx: FirestoreTransactionLike = {
      get: async <T = Record<string, unknown>>(
        docRef: FirestoreDocRefLike<T>,
      ): Promise<FirestoreDocSnapshotLike<T>> => {
        const data = this.store.get(docRef.path);
        return {
          exists: data !== undefined,
          id: docRef.id,
          data: () =>
            data ? (structuredClone(data) as unknown as T) : undefined,
        };
      },
      set: <T = Record<string, unknown>>(
        docRef: FirestoreDocRefLike<T>,
        data: T,
      ): FirestoreTransactionLike => {
        staged.set(
          docRef.path,
          structuredClone(data) as Record<string, unknown>,
        );
        return tx;
      },
      delete: (docRef: FirestoreDocRefLike<unknown>): FirestoreTransactionLike => {
        staged.set(docRef.path, null);
        return tx;
      },
    };

    const res = await updateFunction(tx);
    for (const [p, val] of staged.entries()) {
      if (val === null) this.store.delete(p);
      else this.store.set(p, val);
    }
    return res;
  }
}

function makeVec128(seed: number): Float32Array {
  const vec = new Float32Array(SFACE_EMBEDDING_DIMENSION);
  let state = seed >>> 0;
  for (let i = 0; i < SFACE_EMBEDDING_DIMENSION; i++) {
    state = (state * 1664525 + 1013904223) >>> 0;
    vec[i] = (state / 4294967296) * 2.0 - 1.0;
  }
  return l2NormalizeSfaceVector(vec);
}

describe('KELASAGARA V18 / PHASE 13.4 — WAL Compaction & Contiguous Gap Guard Suite', () => {
  let db: CompactionTestFirestoreHarness;
  let keyProvider: LocalDevKeyProvider;
  let kmsEnvelope: CloudKmsEnvelopeService;
  let primaryNode: TransactionalGalleryCoordinatorV18;
  let laggingNode: TransactionalGalleryCoordinatorV18;

  beforeEach(() => {
    db = new CompactionTestFirestoreHarness();
    keyProvider = new LocalDevKeyProvider();
    kmsEnvelope = new CloudKmsEnvelopeService(keyProvider);

    primaryNode = new TransactionalGalleryCoordinatorV18({
      txAdapter: new FirestoreBiometricTransactionAdapterV18(db),
      kmsEnvelope,
      kmsKeyProvider: keyProvider,
    });
    laggingNode = new TransactionalGalleryCoordinatorV18({
      txAdapter: new FirestoreBiometricTransactionAdapterV18(db),
      kmsEnvelope,
      kmsKeyProvider: keyProvider,
    });
  });

  it('1. Compacts WAL entries older than (snapshotWatermark - safetyWindow) and preserves trailing window', async () => {
    for (let i = 1; i <= 6; i++) {
      await primaryNode.enrollWorkerWithEpochFencedRetry({
        uid: `KLS-COMPACT-W${i}`,
        maskedPhone: `******100${i}`,
        idempotencyKey: `idem-c-${i}`,
        payload: {
          sfaceEmbedding128: makeVec128(800 + i),
          isoQualityScore: 91.0,
          padLivenessScore: 0.95,
        },
      });
    }

    // Export KMS-wrapped KS18 snapshot at Epoch 6
    const snapshotAt6 = await primaryNode.exportKmsWrappedSnapshotKs18();
    assert.equal(snapshotAt6.bundle.watermarkWalSeq, 6);

    // Compact with safety window = 2 (prunes walSeq <= 4; retains walSeq 5 and 6)
    const compactor = new WalCompactorServiceV18(db, {
      retainSafetyWindowEntries: 2,
      maxDeleteBatchSize: 100,
    });
    const report = await compactor.compactWalBeforeVerifiedSnapshot(snapshotAt6);

    assert.equal(report.snapshotWatermarkWalSeq, 6);
    assert.equal(report.pruneUpToWalSeqInclusive, 4);
    assert.deepEqual(report.deletedWalSeqs, [1, 2, 3, 4]);

    // Verify remaining WAL entries are [5, 6]
    const txAdapter = new FirestoreBiometricTransactionAdapterV18(db);
    const remaining = await txAdapter.fetchIncrementalWalSince(0);
    assert.deepEqual(
      remaining.map((r) => r.walSeq),
      [5, 6],
    );

    // Verify verifyContiguousWalSequence throws WAL_GAP_DETECTED_SNAPSHOT_REQUIRED
    // when a lagging node at watermark 0 receives [5, 6] (missing 1..4)
    assert.throws(
      () => verifyContiguousWalSequence(0, remaining),
      /WAL_GAP_DETECTED_SNAPSHOT_REQUIRED: Expected contiguous walSeq 1 after watermark 0, but received walSeq 5/,
    );

    // Lagging node recovers cleanly by hydrating from the KMS-wrapped KS18 snapshot at 6
    const recovery = await laggingNode.hydrateFromKmsSnapshotAndWalTail(
      snapshotAt6,
    );
    assert.equal(recovery.finalEpochAfterWalTail, 6);
    assert.equal(recovery.activeGallerySize, 6);
  });
});
