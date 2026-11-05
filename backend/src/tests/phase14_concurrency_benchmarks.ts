// File: backend/src/tests/phase14_concurrency_benchmarks.ts
// KELASAGARA V18 / PHASE 14 — Gate 7: Reproducible Load, Contention & Latency Benchmarks
// Measures OCC conflict rates, cold-boot hydration latency, and 1:N scan performance.

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
  FirestoreCollectionRefLike,
  FirestoreDatabaseLike,
  FirestoreDocRefLike,
  FirestoreDocSnapshotLike,
  FirestoreTransactionLike,
} from '../services/firestore_transaction_adapter_v18';
import {
  TransactionalGalleryCoordinatorV18,
} from '../services/transactional_gallery_coordinator_v18';
import {
  exportEncryptedAlignedSnapshotKs18,
  encodeSnapshotCanonicalAad,
  hydrateEncryptedSnapshotKs18,
} from '../biometrics/iso24745_iom_cancelable_snapshot_v18';
import {
  HighSpeedBiometricIndexV3,
  EnrolledWorkerSfaceRecordV3,
} from '../services/hnsw_biometric_matcher_v3';

function generateRandomNormalizedEmbedding(seedStr: string): Float32Array {
  const hash = crypto.createHash('sha256').update(seedStr).digest();
  const vec = new Float32Array(SFACE_EMBEDDING_DIMENSION);
  let normSq = 0;
  for (let i = 0; i < SFACE_EMBEDDING_DIMENSION; i++) {
    const subHash = crypto
      .createHash('sha256')
      .update(`${seedStr}_dim_${i}`)
      .digest();
    const val = subHash.readInt16BE(0) / 32768.0;
    vec[i] = val;
    normSq += val * val;
  }
  const invNorm = 1.0 / Math.sqrt(normSq);
  for (let i = 0; i < SFACE_EMBEDDING_DIMENSION; i++) vec[i] *= invNorm;
  return vec;
}

/**
 * Realistic Optimistic Concurrency Control (OCC) Firestore Simulator:
 * Enforces atomic version checking on commit. If two concurrent transactions read version V,
 * the first one to commit increments to V+1, and the second one fails with CONCURRENCY_ABORT (forcing retry).
 */
class OccSimulatedFirestore implements FirestoreDatabaseLike {
  public readonly store = new Map<string, { version: number; data: Record<string, unknown> }>();
  public totalAttempts = 0;
  public totalAborts = 0;

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
    const maxAttempts = options?.maxAttempts ?? 10;
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
        delete: (docRef: FirestoreDocRefLike<unknown>): FirestoreTransactionLike => {
          writeStarted = true;
          stagedWrites.set(docRef.path, null);
          return tx;
        },
      };

      const result = await updateFunction(tx);

      // Verify OCC commit condition: all read versions must still match the store
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
        // Random backoff jitter simulating network retry
        await new Promise((r) => setTimeout(r, Math.random() * 5 + 1));
        continue;
      }

      // Apply staged writes atomically
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
  console.log('KELASAGARA V18 / PHASE 14 — OCC Contention & Hydration Benchmarks');
  console.log('========================================================================\n');

  // Benchmark 1: OCC Contention Scaling across Concurrency Levels
  console.log('--- BENCHMARK 1: OCC Conflict Rates on biometric_cluster_meta/global_state ---');
  const concurrencyLevels = [1, 2, 5, 10, 20];
  const totalOperationsPerBatch = 20;

  for (const C of concurrencyLevels) {
    const occDb = new OccSimulatedFirestore();
    const localKms = new LocalDevKeyProvider();
    const kmsEnvelope = new CloudKmsEnvelopeService(localKms);
    const txAdapter = new FirestoreBiometricTransactionAdapterV18(occDb, 'bench-cluster');
    const coordinator = new TransactionalGalleryCoordinatorV18({
      clusterId: 'bench-cluster',
      tenantId: 'tenant_bench',
      kmsKeyProvider: localKms,
      kmsEnvelope,
      txAdapter,
    });

    const startMs = Date.now();
    let completed = 0;
    const workers = [];

    for (let c = 0; c < C; c++) {
      workers.push(
        (async () => {
          const opsForThisWorker = Math.floor(totalOperationsPerBatch / C);
          for (let op = 0; op < opsForThisWorker; op++) {
            const uid = `bench_w_${c}_${op}`;
            const vec = generateRandomNormalizedEmbedding(uid);
            await coordinator.enrollWorkerWithEpochFencedRetry({
              uid,
              maskedPhone: '+91******0000',
              idempotencyKey: `idem_${uid}`,
              payload: { sfaceEmbedding128: vec, isoQualityScore: 90, padLivenessScore: 0.99 },
            });
            completed++;
          }
        })(),
      );
    }

    await Promise.all(workers);
    const durationMs = Date.now() - startMs;
    const conflictRatePct = ((occDb.totalAborts / occDb.totalAttempts) * 100).toFixed(2);
    const throughputOpsPerSec = ((completed / durationMs) * 1000).toFixed(1);

    console.log(
      `Concurrency C=${String(C).padStart(2)}: Ops=${completed}, Attempts=${occDb.totalAttempts}, ` +
      `Aborts=${String(occDb.totalAborts).padStart(3)}, ConflictRate=${conflictRatePct.padStart(5)}%, ` +
      `Duration=${durationMs}ms, Throughput=${throughputOpsPerSec} ops/s`,
    );
  }

  // Benchmark 2: Cold-Boot Hydration Latency vs WAL Tail Length
  console.log('\n--- BENCHMARK 2: Cold-Boot Hydration Latency vs WAL Tail Length ---');
  const walTailLengths = [0, 10, 25, 50, 100];
  const baseGallerySize = 500;

  const mockRecords: EnrolledWorkerSfaceRecordV3[] = [];
  for (let i = 0; i < baseGallerySize; i++) {
    mockRecords.push({
      uid: `worker_snap_${i}`,
      maskedPhone: '+91******9999',
      modelId: CANONICAL_SFACE_MODEL_ID,
      modelVersion: CANONICAL_SFACE_MODEL_VERSION,
      templateSchemaVersion: CANONICAL_TEMPLATE_SCHEMA_VERSION,
      sfaceEmbedding128: generateRandomNormalizedEmbedding(`snap_${i}`),
      isoQualityScore: 88,
      padLivenessScore: 0.98,
      enrolledAtEpochMs: 1770000000000 + i,
    });
  }

  const snapKey = crypto.randomBytes(32);
  const bundle = exportEncryptedAlignedSnapshotKs18({
    records: mockRecords,
    watermarkWalSeq: baseGallerySize,
    clusterId: 'bench-cluster',
    keyId: 'snap-kek-v1',
    snapshotEncryptionKey32: snapKey,
  });

  const hydratedBase = hydrateEncryptedSnapshotKs18({
    bundle,
    expectedClusterId: 'bench-cluster',
    snapshotEncryptionKey32: snapKey,
  });
  console.log(`Snapshot Base Hydration (N=${baseGallerySize}): ${hydratedBase.hydrationLatencyMs} ms`);

  for (const tailLen of walTailLengths) {
    const simDb = new OccSimulatedFirestore();
    const localKms = new LocalDevKeyProvider();
    const kmsEnvelope = new CloudKmsEnvelopeService(localKms);
    const txAdapter = new FirestoreBiometricTransactionAdapterV18(simDb, 'bench-cluster');

    // Seed trailing WAL entries
    for (let t = 1; t <= tailLen; t++) {
      const seq = baseGallerySize + t;
      const vec = generateRandomNormalizedEmbedding(`tail_${t}`);
      const aadContext = {
        uid: `worker_tail_${t}`,
        modelVersion: CANONICAL_SFACE_MODEL_VERSION,
        templateSchemaVersion: CANONICAL_TEMPLATE_SCHEMA_VERSION,
        tenantId: 'tenant_bench',
        purpose: 'BIOMETRIC_VAULT_SFACE_V3' as const,
      };
      const sealed = await kmsEnvelope.sealTemplateV3({
        sfaceEmbedding128: vec,
        isoQualityScore: 85,
        padLivenessScore: 0.98,
      }, aadContext);

      await simDb.collection('biometric_wal_outbox').doc(String(seq).padStart(12, '0')).set({
        walSeq: seq,
        uid: `worker_tail_${t}`,
        maskedPhone: '+91******8888',
        operation: 'UPSERT',
        templateGeneration: 1,
        modelId: CANONICAL_SFACE_MODEL_ID,
        modelVersion: CANONICAL_SFACE_MODEL_VERSION,
        templateSchemaVersion: CANONICAL_TEMPLATE_SCHEMA_VERSION,
        envelope: sealed,
        committedAtEpochMs: Date.now(),
      });
    }

    const coordinator = new TransactionalGalleryCoordinatorV18({
      clusterId: 'bench-cluster',
      tenantId: 'tenant_bench',
      kmsKeyProvider: localKms,
      kmsEnvelope,
      txAdapter,
    });

    const aad = encodeSnapshotCanonicalAad({
      clusterId: 'bench-cluster',
      keyId: 'snap-kek-v1',
      modelVersion: CANONICAL_SFACE_MODEL_VERSION,
      watermarkWalSeq: baseGallerySize,
      nodeCount: baseGallerySize,
    });
    const { wrappedDek, keyVersionName } = await localKms.wrapKey(snapKey, aad);

    const artifact = {
      bundle,
      kmsKeyVersionName: keyVersionName,
      wrappedSnapshotDekBase64: wrappedDek.toString('base64'),
    };

    const startNs = process.hrtime.bigint();
    const bootResult = await coordinator.hydrateFromKmsSnapshotAndWalTail(artifact);
    const totalBootLatencyMs = Number((Number(process.hrtime.bigint() - startNs) / 1e6).toFixed(3));

    console.log(
      `WAL Tail L=${String(tailLen).padStart(3)}: SnapshotHydration=${bootResult.snapshotHydrationLatencyMs}ms, ` +
      `TotalColdBoot=${totalBootLatencyMs}ms, FinalGallerySize=${bootResult.activeGallerySize}`,
    );
  }

  // Benchmark 3: 1:N Search Latency vs Gallery Size
  console.log('\n--- BENCHMARK 3: 1:N Exact Contiguous Dot Product Scan Latency ---');
  for (const N of [100, 1000, 5000, 10000]) {
    const index = new HighSpeedBiometricIndexV3(N + 100, N + 100);
    for (let i = 0; i < N; i++) {
      index.upsertTemplate({
        uid: `worker_${i}`,
        maskedPhone: '+91******0000',
        modelId: CANONICAL_SFACE_MODEL_ID,
        modelVersion: CANONICAL_SFACE_MODEL_VERSION,
        templateSchemaVersion: CANONICAL_TEMPLATE_SCHEMA_VERSION,
        sfaceEmbedding128: generateRandomNormalizedEmbedding(`cand_${i}`),
        isoQualityScore: 85,
        padLivenessScore: 0.98,
        enrolledAtEpochMs: Date.now(),
      });
    }

    const probe = generateRandomNormalizedEmbedding('probe_candidate');
    const startNs = process.hrtime.bigint();
    const searchRes = index.search1toN('probe_candidate', probe);
    const scanLatencyMs = Number((Number(process.hrtime.bigint() - startNs) / 1e6).toFixed(3));

    console.log(
      `Gallery N=${String(N).padStart(5)}: ScanLatency=${scanLatencyMs}ms ` +
      `(Engine Reported: ${searchRes.searchLatencyMs}ms), Mode=${searchRes.searchMode}`,
    );
  }

  console.log('\n========================================================================');
  console.log('BENCHMARK COMPLETE');
  console.log('========================================================================');
}

runBenchmark().catch((err) => {
  console.error(err);
  process.exit(1);
});
