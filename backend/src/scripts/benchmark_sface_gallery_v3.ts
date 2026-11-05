// File: backend/src/scripts/benchmark_sface_gallery_v3.ts
// KELASAGARA V18 — Phase 7: Reproducible Algorithmic Benchmark for HighSpeedBiometricIndexV3 (128-D SFace)
// Evaluates indexing mechanics, latency, memory, and recall vs. naive exact search.
// Does NOT claim real-world biometric recognition accuracy from synthetic vectors.

import * as os from 'node:os';
import {
  CANONICAL_SFACE_MODEL_ID,
  CANONICAL_SFACE_MODEL_VERSION,
  CANONICAL_TEMPLATE_SCHEMA_VERSION,
  SFACE_EMBEDDING_DIMENSION,
  l2NormalizeSfaceVector,
} from '../crypto/cloud_kms_envelope';
import { HighSpeedBiometricIndexV3 } from '../services/hnsw_biometric_matcher_v3';

function mulberry32(seed: number): () => number {
  let state = seed >>> 0;
  return () => {
    state = (state + 0x6d2b79f5) >>> 0;
    let t = Math.imul(state ^ (state >>> 15), 1 | state);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function generateUnitVec128(seed: number): Float32Array {
  const rng = mulberry32(seed);
  const raw = new Float32Array(SFACE_EMBEDDING_DIMENSION);
  for (let i = 0; i < SFACE_EMBEDDING_DIMENSION; i++) {
    raw[i] = rng() * 2.0 - 1.0;
  }
  return l2NormalizeSfaceVector(raw);
}

function naiveBaselineExactSearch(
  gallery: ReadonlyArray<{ uid: string; vec: Float32Array }>,
  probeUid: string,
  probeVec: Float32Array,
): { matchedUid: string | null; maxCos: number } {
  let bestUid: string | null = null;
  let maxCos = -2.0;
  for (let i = 0; i < gallery.length; i++) {
    const item = gallery[i];
    if (item.uid === probeUid) continue;
    let dot = 0.0;
    for (let d = 0; d < 128; d++) {
      dot += probeVec[d] * item.vec[d];
    }
    if (dot > maxCos) {
      maxCos = dot;
      bestUid = item.uid;
    }
  }
  return { matchedUid: bestUid, maxCos };
}

export function runAlgorithmicGalleryBenchmark(
  gallerySizes = [1000, 5000, 10000],
  queryCount = 200,
): void {
  const envMetadata = {
    nodeVersion: process.version,
    platform: process.platform,
    arch: process.arch,
    cpuModel: os.cpus()[0]?.model ?? 'unknown',
    cpuCores: os.cpus().length,
    embeddingDimension: SFACE_EMBEDDING_DIMENSION,
    modelVersion: CANONICAL_SFACE_MODEL_VERSION,
    note: 'SYNTHETIC_ALGORITHMIC_BENCHMARK_ONLY_NOT_BIOMETRIC_ACCURACY',
  };

  console.log('=== KELASAGARA V18 ALGORITHMIC BENCHMARK ===');
  console.log(JSON.stringify(envMetadata, null, 2));

  for (const n of gallerySizes) {
    const index = new HighSpeedBiometricIndexV3(n + 100, n + 100);
    const baselineGallery: Array<{ uid: string; vec: Float32Array }> = [];

    const heapBeforeBytes = process.memoryUsage().heapUsed;
    const initStartNs = process.hrtime.bigint();

    for (let i = 0; i < n; i++) {
      const uid = `KLS-BENCH-${i}`;
      const vec = generateUnitVec128(100000 + i);
      baselineGallery.push({ uid, vec });
      index.upsertTemplate({
        uid,
        maskedPhone: '******0000',
        modelId: CANONICAL_SFACE_MODEL_ID,
        modelVersion: CANONICAL_SFACE_MODEL_VERSION,
        templateSchemaVersion: CANONICAL_TEMPLATE_SCHEMA_VERSION,
        sfaceEmbedding128: vec,
        isoQualityScore: 90.0,
        padLivenessScore: 0.95,
        enrolledAtEpochMs: 1700000000000,
      });
    }

    const initMs = Number(process.hrtime.bigint() - initStartNs) / 1e6;
    const heapDeltaMb =
      (process.memoryUsage().heapUsed - heapBeforeBytes) / (1024 * 1024);

    const exactLatenciesMs: number[] = [];
    let exactRecallMatches = 0;

    for (let q = 0; q < queryCount; q++) {
      const probeVec = generateUnitVec128(900000 + q);
      const probeUid = `KLS-PROBE-${q}`;

      const baseline = naiveBaselineExactSearch(
        baselineGallery,
        probeUid,
        probeVec,
      );
      const v3Exact = index.searchExact1toN(probeUid, probeVec);

      exactLatenciesMs.push(v3Exact.searchLatencyMs);
      if (v3Exact.matchedUid === baseline.matchedUid) {
        exactRecallMatches++;
      }
    }

    exactLatenciesMs.sort((a, b) => a - b);
    const p50 = exactLatenciesMs[Math.floor(queryCount * 0.5)];
    const p95 = exactLatenciesMs[Math.floor(queryCount * 0.95)];
    const p99 = exactLatenciesMs[Math.floor(queryCount * 0.99)];

    // Measure CoW update & delete latency
    const cowStartNs = process.hrtime.bigint();
    const updatedIndex = index.cloneWithUpsert({
      uid: 'KLS-COW-NEW',
      maskedPhone: '******9999',
      modelId: CANONICAL_SFACE_MODEL_ID,
      modelVersion: CANONICAL_SFACE_MODEL_VERSION,
      templateSchemaVersion: CANONICAL_TEMPLATE_SCHEMA_VERSION,
      sfaceEmbedding128: generateUnitVec128(777777),
      isoQualityScore: 92.0,
      padLivenessScore: 0.96,
      enrolledAtEpochMs: Date.now(),
    });
    const cowUpsertMs = Number(process.hrtime.bigint() - cowStartNs) / 1e6;

    const delStartNs = process.hrtime.bigint();
    updatedIndex.cloneWithoutUid('KLS-COW-NEW');
    const cowDeleteMs = Number(process.hrtime.bigint() - delStartNs) / 1e6;

    console.log(
      JSON.stringify({
        gallerySize: n,
        queryCount,
        initTimeMs: Number(initMs.toFixed(2)),
        approxHeapDeltaMb: Number(heapDeltaMb.toFixed(2)),
        exactSearchLatencyMs: { p50, p95, p99 },
        exactTop1RecallVsBaseline: exactRecallMatches / queryCount,
        cowUpsertMs: Number(cowUpsertMs.toFixed(2)),
        cowDeleteMs: Number(cowDeleteMs.toFixed(2)),
      }),
    );
  }
}

if (require.main === module) {
  runAlgorithmicGalleryBenchmark();
}

