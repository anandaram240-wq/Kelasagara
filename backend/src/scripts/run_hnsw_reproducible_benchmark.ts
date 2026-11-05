// File: backend/src/scripts/run_hnsw_reproducible_benchmark.ts
// KELASAGARA BIOMATCH V19.5.1: REPRODUCIBLE HNSW & EXACT BENCHMARK HARNESS
// Explicitly measures indexing mechanics, memory, latency, and recall.
// Uses deterministic synthetic vectors; explicitly measures index performance, NOT biometric accuracy.

import * as os from 'node:os';
import * as fs from 'node:fs';
import * as path from 'node:path';
import {
  CANONICAL_SFACE_MODEL_ID,
  CANONICAL_SFACE_MODEL_VERSION,
  CANONICAL_TEMPLATE_SCHEMA_VERSION,
  SFACE_EMBEDDING_DIMENSION,
} from '../crypto/cloud_kms_envelope';
import {
  HighSpeedBiometricIndexV3,
  EnrolledWorkerSfaceRecordV3,
} from '../services/hnsw_biometric_matcher_v3';
import { computeWilsonScoreInterval, computeRuleOfThreeBound } from '../evaluation/v19_5_research_harness';

function mulberry32(seed: number): () => number {
  let state = seed >>> 0;
  return () => {
    state = (state + 0x6d2b79f5) >>> 0;
    let t = Math.imul(state ^ (state >>> 15), 1 | state);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function generateDeterministicVector(seed: number): Float32Array {
  const rng = mulberry32(seed);
  const v = new Float32Array(SFACE_EMBEDDING_DIMENSION);
  let sumSq = 0;
  for (let i = 0; i < SFACE_EMBEDDING_DIMENSION; i++) {
    // Normal-like distribution via central limit theorem
    const u = rng() + rng() + rng() + rng() - 2.0;
    v[i] = u;
    sumSq += u * u;
  }
  const norm = Math.sqrt(sumSq);
  if (norm > 0) {
    for (let i = 0; i < SFACE_EMBEDDING_DIMENSION; i++) {
      v[i] /= norm;
    }
  }
  return v;
}

export interface TierBenchmarkResult {
  gallerySizeN: number;
  indexBuildTimeMs: number;
  heapUsedMb: number;
  warmupQueryCount: number;
  benchmarkQueryCount: number;
  hnswParameters: {
    efSearch: number;
    maxEdgesPerNode: number;
    entryPoints: number;
  };
  exactScanLatency: {
    p50: number;
    p95: number;
    mean: number;
  };
  hnswLatency: {
    min: number;
    p50: number;
    p90: number;
    p95: number;
    p99: number;
    max: number;
    mean: number;
  };
  recallAt1VsExact: number; // Fraction of queries where HNSW top-1 matched exact scan top-1
  collisionCountReview074: number;
  collisionCountHardBlock090: number;
  fpirReview074: {
    pointEstimate: number;
    lowerBound: number;
    upperBound: number;
  };
  fpirHardBlock090: {
    pointEstimate: number;
    lowerBound: number;
    upperBound: number;
    ruleOfThreeBound95: number;
  };
}

export interface ComprehensiveBenchmarkReport {
  auditDateIso: string;
  hostHardware: {
    platform: string;
    arch: string;
    cpus: string;
    totalMemoryGb: number;
    freeMemoryGb: number;
  };
  softwareVersions: {
    nodeVersion: string;
    v8Version: string;
    sfaceEmbeddingDimension: number;
  };
  vectorSource: {
    type: 'SYNTHETIC_DETERMINISTIC_HYPERSPHERE_PRNG';
    generator: 'Mulberry32_NormalApproximation';
    seedBaseGallery: number;
    seedBaseQuery: number;
    disclaimer: 'Measures indexing mechanics, memory, and search recall only; does NOT measure human facial recognition accuracy.';
  };
  tiers: TierBenchmarkResult[];
}

export function runComprehensiveReproducibleBenchmark(
  galleryTiers = [100, 1000, 10000, 50000, 100000],
  queryCount = 200,
  warmupCount = 20
): ComprehensiveBenchmarkReport {
  console.log(`[Benchmark] Starting reproducible HNSW evaluation on ${os.cpus()[0]?.model} (${os.arch()})...`);

  const report: ComprehensiveBenchmarkReport = {
    auditDateIso: new Date().toISOString(),
    hostHardware: {
      platform: os.platform(),
      arch: os.arch(),
      cpus: `${os.cpus().length}x ${os.cpus()[0]?.model}`,
      totalMemoryGb: Number((os.totalmem() / (1024 ** 3)).toFixed(2)),
      freeMemoryGb: Number((os.freemem() / (1024 ** 3)).toFixed(2)),
    },
    softwareVersions: {
      nodeVersion: process.version,
      v8Version: process.versions.v8,
      sfaceEmbeddingDimension: SFACE_EMBEDDING_DIMENSION,
    },
    vectorSource: {
      type: 'SYNTHETIC_DETERMINISTIC_HYPERSPHERE_PRNG',
      generator: 'Mulberry32_NormalApproximation',
      seedBaseGallery: 1000000,
      seedBaseQuery: 5000000,
      disclaimer: 'Measures indexing mechanics, memory, and search recall only; does NOT measure human facial recognition accuracy.',
    },
    tiers: [],
  };

  for (const N of galleryTiers) {
    console.log(`[Benchmark] Initializing Tier N = ${N.toLocaleString()}...`);
    const heapBefore = process.memoryUsage().heapUsed;
    const t0 = process.hrtime.bigint();

    const index = new HighSpeedBiometricIndexV3(N);

    // Build gallery
    for (let i = 0; i < N; i++) {
      const vec = generateDeterministicVector(report.vectorSource.seedBaseGallery + i);
      const record: EnrolledWorkerSfaceRecordV3 = {
        uid: `w_gal_${i.toString().padStart(6, '0')}`,
        maskedPhone: `+91 ******${(1000 + (i % 9000)).toString()}`,
        modelId: CANONICAL_SFACE_MODEL_ID,
        modelVersion: CANONICAL_SFACE_MODEL_VERSION,
        templateSchemaVersion: CANONICAL_TEMPLATE_SCHEMA_VERSION,
        sfaceEmbedding128: vec,
        isoQualityScore: 85,
        padLivenessScore: 0.95,
        enrolledAtEpochMs: 1700000000000 + i,
      };
      index.upsertTemplate(record);
    }

    const t1 = process.hrtime.bigint();
    const buildTimeMs = Number(t1 - t0) / 1e6;
    const heapAfter = process.memoryUsage().heapUsed;
    const heapUsedMb = Number(((heapAfter - heapBefore) / (1024 * 1024)).toFixed(2));

    console.log(`[Benchmark] N = ${N.toLocaleString()} built in ${buildTimeMs.toFixed(2)} ms (Heap: ${heapUsedMb} MB). Warming up...`);

    // Warm-up queries
    for (let w = 0; w < warmupCount; w++) {
      const qVec = generateDeterministicVector(8000000 + w);
      index.search1toN(`warmup_${w}`, qVec);
    }

    // Benchmark queries
    const hnswLatencies: number[] = [];
    const exactLatencies: number[] = [];
    let recallAt1Hits = 0;
    let reviewCollisions = 0;
    let hardBlockCollisions = 0;

    for (let q = 0; q < queryCount; q++) {
      const qVec = generateDeterministicVector(report.vectorSource.seedBaseQuery + q);
      const qUid = `probe_${q}`;

      // 1. Exact scan ground truth
      const startExact = process.hrtime.bigint();
      const exactRes = index.searchExact1toN(qUid, qVec);
      const endExact = process.hrtime.bigint();
      const latExact = Number(endExact - startExact) / 1e6;
      exactLatencies.push(latExact);

      // 2. Approximate / default search (forceApproximate = true to benchmark the graph search)
      const startHnsw = process.hrtime.bigint();
      const hnswRes = index.searchApproximate1toN(qUid, qVec, 256);
      const endHnsw = process.hrtime.bigint();
      const latHnsw = Number(endHnsw - startHnsw) / 1e6;
      hnswLatencies.push(latHnsw);

      if (hnswRes.matchedUid === exactRes.matchedUid || Math.abs(hnswRes.maxCosineSimilarity - exactRes.maxCosineSimilarity) < 1e-4) {
        recallAt1Hits++;
      }

      // Record collisions for exact scan (authoritative)
      if (exactRes.maxCosineSimilarity >= 0.74) {
        reviewCollisions++;
      }
      if (exactRes.maxCosineSimilarity >= 0.90) {
        hardBlockCollisions++;
      }
    }

    hnswLatencies.sort((a, b) => a - b);
    exactLatencies.sort((a, b) => a - b);

    const sumHnsw = hnswLatencies.reduce((a, b) => a + b, 0);
    const meanHnsw = Number((sumHnsw / hnswLatencies.length).toFixed(4));

    const sumExact = exactLatencies.length > 0 ? exactLatencies.reduce((a, b) => a + b, 0) : 0;
    const meanExact = exactLatencies.length > 0 ? Number((sumExact / exactLatencies.length).toFixed(4)) : 0;

    const evaluatedRecallCount = exactLatencies.length;
    const recallAt1 = evaluatedRecallCount > 0 ? Number((recallAt1Hits / evaluatedRecallCount).toFixed(4)) : 1.0;

    const p50 = hnswLatencies[Math.floor(hnswLatencies.length * 0.50)] ?? 0;
    const p90 = hnswLatencies[Math.floor(hnswLatencies.length * 0.90)] ?? 0;
    const p95 = hnswLatencies[Math.floor(hnswLatencies.length * 0.95)] ?? 0;
    const p99 = hnswLatencies[Math.floor(hnswLatencies.length * 0.99)] ?? 0;
    const min = hnswLatencies[0] ?? 0;
    const max = hnswLatencies[hnswLatencies.length - 1] ?? 0;

    const exactP50 = exactLatencies[Math.floor(exactLatencies.length * 0.50)] ?? meanExact;
    const exactP95 = exactLatencies[Math.floor(exactLatencies.length * 0.95)] ?? meanExact;

    const fpirReviewInterval = computeWilsonScoreInterval(reviewCollisions, queryCount);
    const fpirHardBlockInterval = computeWilsonScoreInterval(hardBlockCollisions, queryCount);
    const ruleOfThree = computeRuleOfThreeBound(queryCount);

    const tierResult: TierBenchmarkResult = {
      gallerySizeN: N,
      indexBuildTimeMs: Number(buildTimeMs.toFixed(2)),
      heapUsedMb,
      warmupQueryCount: warmupCount,
      benchmarkQueryCount: queryCount,
      hnswParameters: {
        efSearch: 256,
        maxEdgesPerNode: 16,
        entryPoints: 8,
      },
      exactScanLatency: {
        p50: Number(exactP50.toFixed(4)),
        p95: Number(exactP95.toFixed(4)),
        mean: meanExact,
      },
      hnswLatency: {
        min: Number(min.toFixed(4)),
        p50: Number(p50.toFixed(4)),
        p90: Number(p90.toFixed(4)),
        p95: Number(p95.toFixed(4)),
        p99: Number(p99.toFixed(4)),
        max: Number(max.toFixed(4)),
        mean: meanHnsw,
      },
      recallAt1VsExact: recallAt1,
      collisionCountReview074: reviewCollisions,
      collisionCountHardBlock090: hardBlockCollisions,
      fpirReview074: {
        pointEstimate: fpirReviewInterval.pointEstimate,
        lowerBound: fpirReviewInterval.lowerBound,
        upperBound: fpirReviewInterval.upperBound,
      },
      fpirHardBlock090: {
        pointEstimate: fpirHardBlockInterval.pointEstimate,
        lowerBound: fpirHardBlockInterval.lowerBound,
        upperBound: fpirHardBlockInterval.upperBound,
        ruleOfThreeBound95: ruleOfThree.upperConfidenceBound95,
      },
    };

    report.tiers.push(tierResult);
    console.log(`[Benchmark] Tier N = ${N.toLocaleString()} Result: p50 = ${p50.toFixed(4)} ms, p95 = ${p95.toFixed(4)} ms, Recall@1 = ${(recallAt1 * 100).toFixed(1)}%`);
  }

  return report;
}

// If invoked as standalone script
if (require.main === module) {
  const tiers = [100, 1000, 10000, 50000, 100000];
  const report = runComprehensiveReproducibleBenchmark(tiers, 200, 20);

  const outputPath = path.resolve(__dirname, '../../../benchmark_results_v19_5_1.json');
  fs.writeFileSync(outputPath, JSON.stringify(report, null, 2), 'utf-8');
  console.log(`[Benchmark] Machine-readable results saved to: ${outputPath}`);
}
