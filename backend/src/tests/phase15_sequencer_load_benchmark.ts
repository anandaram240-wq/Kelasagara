// File: backend/src/tests/phase15_sequencer_load_benchmark.ts
// Statistically powered high-volume benchmark: 1,000 operations across C in {1, 2, 5, 10, 20, 50}

import * as crypto from 'node:crypto';
import { performance } from 'node:perf_hooks';

import {
  LocalDevKeyProvider,
  CloudKmsEnvelopeService,
  SFACE_EMBEDDING_DIMENSION,
} from '../crypto/cloud_kms_envelope';
import {
  FirestoreBiometricTransactionAdapterV18,
  FirestoreCollectionRefLike,
  FirestoreDatabaseLike,
  FirestoreDocRefLike,
  FirestoreDocSnapshotLike,
  FirestoreTransactionLike,
} from '../services/firestore_transaction_adapter_v18';
import {
  TransactionalGalleryCoordinatorV18,
} from '../services/transactional_gallery_coordinator_v18';

function generateNormalizedEmbedding(seedStr: string): Float32Array {
  const vec = new Float32Array(SFACE_EMBEDDING_DIMENSION);
  let normSq = 0;
  for (let i = 0; i < SFACE_EMBEDDING_DIMENSION; i++) {
    const subHash = crypto
      .createHash('sha256')
      .update(`${seedStr}_coord_${i}`)
      .digest();
    const val = subHash.readInt16BE(0) / 32768.0;
    vec[i] = val;
    normSq += val * val;
  }
  const invNorm = 1.0 / Math.sqrt(normSq);
  for (let i = 0; i < SFACE_EMBEDDING_DIMENSION; i++) vec[i] *= invNorm;
  return vec;
}

class FastOccFirestore implements FirestoreDatabaseLike {
  public readonly store = new Map<string, { version: number; data: Record<string, unknown> }>();
  public totalAttempts = 0;
  public totalAborts = 0;

  constructor() {
    this.store.set('biometric_cluster_meta/global_state', {
      version: 1,
      data: { globalEpoch: 0, watermarkWalSeq: 0, clusterId: 'bench-cluster' },
    });
  }

  public collection<T = Record<string, unknown>>(collectionName: string): FirestoreCollectionRefLike<T> {
    return {
      doc: (docId: string): FirestoreDocRefLike<T> => {
        const fullPath = `${collectionName}/${docId}`;
        return {
          id: docId,
          path: fullPath,
          get: async () => {
            const entry = this.store.get(fullPath);
            return {
              exists: entry !== undefined,
              id: docId,
              data: () => (entry ? (structuredClone(entry.data) as unknown as T) : undefined),
            };
          },
          set: async (data: T) => {
            const prev = this.store.get(fullPath);
            this.store.set(fullPath, {
              version: (prev?.version ?? 0) + 1,
              data: structuredClone(data) as Record<string, unknown>,
            });
          },
          delete: async () => {
            this.store.delete(fullPath);
          },
        };
      },
      where: (field: string, op: any, value: unknown) => ({
        get: async () => {
          const matching: Array<FirestoreDocSnapshotLike<T>> = [];
          for (const [k, v] of this.store.entries()) {
            if (!k.startsWith(`${collectionName}/`)) continue;
            const fieldVal = v.data[field] as number;
            const pass =
              (op === '==' && fieldVal === value) ||
              (op === '>' && fieldVal > (value as number));
            if (pass) {
              matching.push({
                exists: true,
                id: k.split('/')[1],
                data: () => structuredClone(v.data) as unknown as T,
              });
            }
          }
          matching.sort((a, b) => {
            const seqA = ((a.data() as any)?.walSeq as number) ?? 0;
            const seqB = ((b.data() as any)?.walSeq as number) ?? 0;
            return seqA - seqB;
          });
          return { docs: matching };
        },
      }),
      get: async () => {
        const docs: Array<FirestoreDocSnapshotLike<T>> = [];
        for (const [k, v] of this.store.entries()) {
          if (k.startsWith(`${collectionName}/`)) {
            docs.push({ exists: true, id: k.split('/')[1], data: () => structuredClone(v.data) as unknown as T });
          }
        }
        return { docs };
      },
    };
  }

  public async runTransaction<R>(
    updateFunction: (transaction: FirestoreTransactionLike) => Promise<R>,
    options?: { maxAttempts?: number },
  ): Promise<R> {
    const maxAttempts = options?.maxAttempts ?? 25;
    for (let attempt = 1; attempt <= maxAttempts; attempt++) {
      this.totalAttempts++;
      const readVersions = new Map<string, number>();
      const stagedWrites = new Map<string, Record<string, unknown> | null>();
      let writeStarted = false;

      const tx: FirestoreTransactionLike = {
        get: async <T = Record<string, unknown>>(
          docRef: FirestoreDocRefLike<T>,
        ): Promise<FirestoreDocSnapshotLike<T>> => {
          if (writeStarted) throw new Error('Reads must precede writes');
          const entry = this.store.get(docRef.path);
          readVersions.set(docRef.path, entry?.version ?? 0);
          return {
            exists: entry !== undefined,
            id: docRef.id,
            data: () => (entry ? (structuredClone(entry.data) as unknown as T) : undefined),
          };
        },
        set: <T = Record<string, unknown>>(
          docRef: FirestoreDocRefLike<T>,
          data: T,
        ): FirestoreTransactionLike => {
          writeStarted = true;
          stagedWrites.set(docRef.path, structuredClone(data) as Record<string, unknown>);
          return tx;
        },
        delete: (docRef: FirestoreDocRefLike<unknown>): FirestoreTransactionLike => {
          writeStarted = true;
          stagedWrites.set(docRef.path, null);
          return tx;
        },
      };

      const result = await updateFunction(tx);

      let conflict = false;
      for (const [path, expectedVer] of readVersions.entries()) {
        const currentVer = this.store.get(path)?.version ?? 0;
        if (currentVer !== expectedVer) {
          conflict = true;
          break;
        }
      }

      if (conflict) {
        this.totalAborts++;
        await new Promise((r) => setTimeout(r, Math.random() * 2 + 0.5));
        continue;
      }

      for (const [path, data] of stagedWrites.entries()) {
        if (data === null) {
          this.store.delete(path);
        } else {
          const cur = this.store.get(path);
          this.store.set(path, { version: (cur?.version ?? 0) + 1, data });
        }
      }

      return result;
    }
    throw new Error('OCC_MAX_ATTEMPTS_EXCEEDED');
  }
}

async function runBenchmark() {
  console.log('========================================================================');
  console.log('KELASAGARA V18 / PHASE 15 — Statistically Powered Sequencer Load Study');
  console.log('Workload: 1,000 Operations across Concurrency Levels C in {1, 2, 5, 10, 20, 50}');
  console.log('========================================================================\n');

  const keyProvider = new LocalDevKeyProvider();
  const kmsEnvelope = new CloudKmsEnvelopeService(keyProvider);

  const concurrencyLevels = [1, 2, 5, 10, 20, 50];
  const TOTAL_OPS = 1000;

  for (const C of concurrencyLevels) {
    const simDb = new FastOccFirestore();
    const adapter = new FirestoreBiometricTransactionAdapterV18(simDb);

    const nodes: TransactionalGalleryCoordinatorV18[] = [];
    for (let i = 0; i < C; i++) {
      nodes.push(
        new TransactionalGalleryCoordinatorV18({
          txAdapter: adapter,
          kmsEnvelope,
          kmsKeyProvider: keyProvider,
        }),
      );
    }

    const latencies: number[] = [];
    const tStart = performance.now();
    let completed = 0;

    for (let batch = 0; batch < TOTAL_OPS; batch += C) {
      const tasks: Promise<void>[] = [];
      const currentBatchSize = Math.min(C, TOTAL_OPS - batch);
      for (let i = 0; i < currentBatchSize; i++) {
        const opIndex = batch + i;
        const node = nodes[i % C];
        const uid = `bench_w_${C}_${opIndex}`;
        const phone = `+9198765${String(opIndex).padStart(5, '0')}`;
        const vec = generateNormalizedEmbedding(`bench_seed_${C}_${opIndex}`);

        tasks.push(
          (async () => {
            const t0 = performance.now();
            const res = await node.enrollWorkerWithEpochFencedRetry({
              uid,
              maskedPhone: phone,
              idempotencyKey: `idemp_${uid}`,
              payload: {
                sfaceEmbedding128: vec,
                isoQualityScore: 95.0,
                padLivenessScore: 0.98,
              },
            });
            const dur = performance.now() - t0;
            latencies.push(dur);
            if (res.enrolled) completed++;
          })(),
        );
      }
      await Promise.all(tasks);
    }

    const totalDurMs = performance.now() - tStart;
    latencies.sort((a, b) => a - b);
    const p50 = latencies[Math.floor(latencies.length * 0.5)];
    const p95 = latencies[Math.floor(latencies.length * 0.95)];
    const p99 = latencies[Math.floor(latencies.length * 0.99)];
    const conflictRate = (simDb.totalAborts / simDb.totalAttempts) * 100;
    const throughput = (completed / (totalDurMs / 1000)).toFixed(1);

    console.log(
      `Concurrency C=${String(C).padStart(2)}: ` +
        `Completed=${completed}/${TOTAL_OPS}, ` +
        `Attempts=${simDb.totalAttempts}, ` +
        `Aborts=${String(simDb.totalAborts).padStart(4)}, ` +
        `ConflictRate=${conflictRate.toFixed(2).padStart(5)}%, ` +
        `P50=${p50.toFixed(2)}ms, ` +
        `P95=${p95.toFixed(2)}ms, ` +
        `P99=${p99.toFixed(2)}ms, ` +
        `Throughput=${throughput} ops/s`,
    );
  }
  console.log('\n========================================================================');
  console.log('BENCHMARK COMPLETE');
  console.log('========================================================================');
}

runBenchmark().catch((err) => {
  console.error('Benchmark failed:', err);
  process.exit(1);
});
