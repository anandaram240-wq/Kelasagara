// File: backend/src/scripts/run_v19_5_2_deep_audit.ts
// KELASAGARA BIOMATCH V19.5.2: MEMORY, RECALL, ROUTING & DEPLOYMENT AUDIT HARNESS
// Explicitly reconciles memory metrics, exact vs approximate routing, and synthetic stress testing.
// DISCLAIMER: Measures indexing mechanics, memory, latency, and algorithmic nearest-neighbor recall only;
// DOES NOT measure human facial recognition accuracy or demographic matching rates.

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

export function runDeepAudit() {
  const tiers = [100, 1000, 10000, 50000, 100000];
  const queryCount = 100;
  const warmupCount = 20;

  const report: any = {
    auditDateIso: new Date().toISOString(),
    evaluationType: 'ALGORITHMIC_STRESS_TEST_SYNTHETIC_VECTORS',
    disclaimer:
      'Measures indexing mechanics, memory allocation, and vector search recall on synthetic hypersphere points. Does NOT guarantee correct-person identification, zero false matches, or zero false non-matches in real-world human biometrics.',
    hostHardware: {
      platform: os.platform(),
      arch: os.arch(),
      cpus: `${os.cpus().length}x ${os.cpus()[0]?.model}`,
      totalMemoryGb: Number((os.totalmem() / 1e9).toFixed(2)),
      totalMemoryGiB: Number((os.totalmem() / (1024 ** 3)).toFixed(2)),
    },
    softwareVersions: {
      nodeVersion: process.version,
      v8Version: process.versions.v8,
      sfaceEmbeddingDimension: SFACE_EMBEDDING_DIMENSION,
      productionExactScanThreshold: 50000,
    },
    tiers: [],
  };

  for (const N of tiers) {
    if (global.gc) global.gc();
    const memBefore = process.memoryUsage();
    const t0 = process.hrtime.bigint();

    // Default production constructor has exactScanThreshold = 50000
    const index = new HighSpeedBiometricIndexV3(N, 50000);

    for (let i = 0; i < N; i++) {
      const vec = generateDeterministicVector(1000000 + i);
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
    const memAfter = process.memoryUsage();
    const buildTimeMs = Number(t1 - t0) / 1e6;

    // Warmup
    for (let w = 0; w < warmupCount; w++) {
      const qVec = generateDeterministicVector(8000000 + w);
      index.search1toN(`warmup_${w}`, qVec);
    }

    // Benchmark 100 independent queries
    const latExact: number[] = [];
    const latApprox: number[] = [];
    const latProd: number[] = [];

    let approxRecallHits = 0;
    let prodRecallHits = 0;

    for (let q = 0; q < queryCount; q++) {
      const qVec = generateDeterministicVector(5000000 + q);
      const qUid = `probe_${q}`;

      // 1. Exact Scan
      const te0 = process.hrtime.bigint();
      const resE = index.searchExact1toN(qUid, qVec);
      const te1 = process.hrtime.bigint();
      latExact.push(Number(te1 - te0) / 1e6);

      // 2. Approximate Graph Search
      const ta0 = process.hrtime.bigint();
      const resA = index.searchApproximate1toN(qUid, qVec, 256);
      const ta1 = process.hrtime.bigint();
      latApprox.push(Number(ta1 - ta0) / 1e6);

      // 3. Production search1toN
      const tp0 = process.hrtime.bigint();
      const resP = index.search1toN(qUid, qVec);
      const tp1 = process.hrtime.bigint();
      latProd.push(Number(tp1 - tp0) / 1e6);

      if (
        resA.matchedUid === resE.matchedUid ||
        Math.abs(resA.maxCosineSimilarity - resE.maxCosineSimilarity) < 1e-4
      ) {
        approxRecallHits++;
      }

      if (
        resP.matchedUid === resE.matchedUid ||
        Math.abs(resP.maxCosineSimilarity - resE.maxCosineSimilarity) < 1e-4
      ) {
        prodRecallHits++;
      }
    }

    latExact.sort((a, b) => a - b);
    latApprox.sort((a, b) => a - b);
    latProd.sort((a, b) => a - b);

    const rawVectorBytes = N * SFACE_EMBEDDING_DIMENSION * 4;

    const sampleProd = index.search1toN('sample_probe', generateDeterministicVector(5000000));

    report.tiers.push({
      gallerySizeN: N,
      buildTimeMs: Number(buildTimeMs.toFixed(2)),
      memoryBreakdown: {
        rawVectorStorage: {
          bytes: rawVectorBytes,
          decimalMB: Number((rawVectorBytes / 1e6).toFixed(4)),
          binaryMiB: Number((rawVectorBytes / (1024 * 1024)).toFixed(4)),
        },
        heapUsedDelta: {
          bytes: memAfter.heapUsed - memBefore.heapUsed,
          decimalMB: Number(((memAfter.heapUsed - memBefore.heapUsed) / 1e6).toFixed(2)),
          binaryMiB: Number(((memAfter.heapUsed - memBefore.heapUsed) / (1024 * 1024)).toFixed(2)),
        },
        arrayBuffersDelta: {
          bytes: memAfter.arrayBuffers - memBefore.arrayBuffers,
          decimalMB: Number(((memAfter.arrayBuffers - memBefore.arrayBuffers) / 1e6).toFixed(2)),
          binaryMiB: Number(((memAfter.arrayBuffers - memBefore.arrayBuffers) / (1024 * 1024)).toFixed(2)),
        },
        externalDelta: {
          bytes: memAfter.external - memBefore.external,
          decimalMB: Number(((memAfter.external - memBefore.external) / 1e6).toFixed(2)),
          binaryMiB: Number(((memAfter.external - memBefore.external) / (1024 * 1024)).toFixed(2)),
        },
        processRssDelta: {
          bytes: memAfter.rss - memBefore.rss,
          decimalMB: Number(((memAfter.rss - memBefore.rss) / 1e6).toFixed(2)),
          binaryMiB: Number(((memAfter.rss - memBefore.rss) / (1024 * 1024)).toFixed(2)),
        },
      },
      exactScan: {
        latencyP50Ms: Number(latExact[Math.floor(queryCount * 0.5)].toFixed(4)),
        latencyP95Ms: Number(latExact[Math.floor(queryCount * 0.95)].toFixed(4)),
        recallAt1VsExact: 1.0,
      },
      approximateGraph: {
        efSearch: 256,
        latencyP50Ms: Number(latApprox[Math.floor(queryCount * 0.5)].toFixed(4)),
        latencyP95Ms: Number(latApprox[Math.floor(queryCount * 0.95)].toFixed(4)),
        recallAt1VsExact: Number((approxRecallHits / queryCount).toFixed(4)),
      },
      productionSearch1toN: {
        routedMode: sampleProd.searchMode,
        latencyP50Ms: Number(latProd[Math.floor(queryCount * 0.5)].toFixed(4)),
        latencyP95Ms: Number(latProd[Math.floor(queryCount * 0.95)].toFixed(4)),
        recallAt1VsExact: Number((prodRecallHits / queryCount).toFixed(4)),
      },
    });

    console.log(`[V19.5.2 Audit] N = ${N.toLocaleString()} Tier Complete.`);
  }

  const outPath = path.resolve(__dirname, '../../../benchmark_results_v19_5_2.json');
  fs.writeFileSync(outPath, JSON.stringify(report, null, 2), 'utf-8');
  console.log(`[V19.5.2 Audit] Saved machine-readable audit report to ${outPath}`);
}

if (require.main === module) {
  runDeepAudit();
}
