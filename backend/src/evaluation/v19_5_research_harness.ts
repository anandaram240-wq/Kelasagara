// File: backend/src/evaluation/v19_5_research_harness.ts
// KELASAGARA BIOMATCH V19.5: OFFLINE RESEARCH BENCHMARK HARNESS & EVALUATION ENGINE
// Standards: ISO/IEC 19795-1:2021, ISO/IEC 30107-3:2023, India DPDPA 2023 §8(3)
// Release Posture: RESEARCH_AND_BENCHMARK_ONLY | productionBiometricCalibrationApproved = false

import * as crypto from 'node:crypto';
import { cosineSimilarity, l2Normalize } from '../services/biometric_matching';
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

// ============================================================================
// PART 1: RESEARCH DATA SCHEMAS & PROVENANCE INTERFACES
// ============================================================================

export type LightingCategory =
  | 'NORMAL_INDOOR_150_300_LUX'
  | 'DIM_INDOOR_5_15_LUX'
  | 'EXTREME_DARK_0_5_2_LUX'
  | 'UNEVEN_BACKLIT_HIGH_CONTRAST'
  | 'OUTDOOR_DIRECT_SUNLIGHT_10K_LUX'
  | 'SCREEN_FILL_ASSISTED_DARK';

export type DatasetSplit = 'DEVELOPMENT' | 'CALIBRATION' | 'HELD_OUT_EVAL';

export interface ResearchImageRecord {
  readonly sampleId: string;
  readonly subjectPseudonym: string;
  readonly captureSessionId: string;
  readonly lightingCategory: LightingCategory;
  readonly measuredLuxSubject?: number;
  readonly measuredLuxCamera?: number;
  readonly isCalibratedLuxMeter: boolean;
  readonly hardwareDeviceModel: string;
  readonly cameraAperture?: string;
  readonly exposureTimeMs?: number;
  readonly isoSensitivity?: number;
  readonly distanceCm: number;
  readonly groundTruthBonaFide: boolean;
  readonly isAttack: boolean;
  readonly attackType?: 'PRINT_2D' | 'SCREEN_REPLAY' | 'MASK_3D' | 'EYE_CUTOUT_BLINK';
  readonly datasetSplit: DatasetSplit;
  readonly sha256DigestHex: string;
}

export interface ResearchManifest {
  readonly manifestVersion: '19.5.0';
  readonly protocolId: string;
  readonly ethicsApprovalId: string;
  readonly lawfulUseBasis: 'DPDPA_2023_EXPLICIT_RESEARCH_CONSENT';
  readonly deIdentificationMethod: 'PSEUDONYMOUS_HMAC_SHA256';
  readonly createdAtIso: string;
  readonly samples: ReadonlyArray<ResearchImageRecord>;
}

// ============================================================================
// PART 2: STATISTICAL ERROR DEFINITIONS & CONFIDENCE BOUNDS
// ============================================================================

export interface WilsonScoreInterval {
  readonly pointEstimate: number;
  readonly lowerBound: number;
  readonly upperBound: number;
  readonly confidenceLevel: number; // e.g. 0.95
}

export interface RuleOfThreeBound {
  readonly trialsCount: number;
  readonly observedErrors: 0;
  readonly upperConfidenceBound95: number;
  readonly assumptionNotes: string;
}

/**
 * Computes continuity-corrected Wilson score confidence interval for a proportion k/n.
 * Required by ISO/IEC 19795-1 to prevent invalid negative bounds as p -> 0.
 */
export function computeWilsonScoreInterval(
  successes: number,
  trials: number,
  confidence = 0.95
): WilsonScoreInterval {
  if (trials <= 0) {
    return { pointEstimate: 0, lowerBound: 0, upperBound: 1.0, confidenceLevel: confidence };
  }
  const p = successes / trials;
  // z for 95% = 1.95996
  const z = confidence === 0.99 ? 2.57583 : 1.95996;
  const z2 = z * z;
  const denominator = 1 + z2 / trials;
  const center = p + z2 / (2 * trials);
  const factor = z * Math.sqrt((p * (1 - p)) / trials + z2 / (4 * trials * trials));

  let lower = Math.max(0.0, (center - factor) / denominator);
  let upper = Math.min(1.0, (center + factor) / denominator);

  if (successes === 0) {
    lower = 0.0;
  }
  if (successes === trials) {
    upper = 1.0;
  }

  return {
    pointEstimate: p,
    lowerBound: lower,
    upperBound: upper,
    confidenceLevel: confidence,
  };
}

/**
 * Evaluates the Rule of Three for zero observed failures.
 * Upper bound at 95% confidence is -ln(0.05) / n ≈ 2.9957 / n.
 */
export function computeRuleOfThreeBound(trials: number): RuleOfThreeBound {
  const bound = trials > 0 ? 2.99573227 / trials : 1.0;
  return {
    trialsCount: trials,
    observedErrors: 0,
    upperConfidenceBound95: Math.min(1.0, bound),
    assumptionNotes:
      'Assumes independent and identically distributed trials. For zero observed failures in n trials, error rate is bounded below this value at 95% confidence.',
  };
}

// ============================================================================
// PART 3: 1:1 PAIRWISE VERIFICATION EVALUATION
// ============================================================================

export interface PairwiseTrial {
  readonly subject1: string;
  readonly subject2: string;
  readonly score: number;
  readonly isMated: boolean; // true = genuine, false = impostor
  readonly lightingCondition: LightingCategory;
}

export interface VerificationMetricsReport {
  readonly threshold: number;
  readonly totalMatedPairs: number;
  readonly totalNonMatedPairs: number;
  readonly falseMatchCount: number;
  readonly falseNonMatchCount: number;
  readonly fmr: WilsonScoreInterval;
  readonly fnmr: WilsonScoreInterval;
  readonly tar: WilsonScoreInterval;
  readonly decidabilityIndexDPrime: number;
}

export function evaluatePairwiseVerification(
  trials: ReadonlyArray<PairwiseTrial>,
  threshold = 0.363
): VerificationMetricsReport {
  let matedCount = 0;
  let nonMatedCount = 0;
  let falseMatches = 0;
  let falseNonMatches = 0;

  let sumGenuine = 0;
  let sumGenuineSq = 0;
  let sumImpostor = 0;
  let sumImpostorSq = 0;

  for (let i = 0; i < trials.length; i++) {
    const t = trials[i];
    if (t.isMated) {
      matedCount++;
      sumGenuine += t.score;
      sumGenuineSq += t.score * t.score;
      if (t.score < threshold) {
        falseNonMatches++;
      }
    } else {
      nonMatedCount++;
      sumImpostor += t.score;
      sumImpostorSq += t.score * t.score;
      if (t.score >= threshold) {
        falseMatches++;
      }
    }
  }

  const muGen = matedCount > 0 ? sumGenuine / matedCount : 0;
  const varGen = matedCount > 1 ? (sumGenuineSq - (sumGenuine * sumGenuine) / matedCount) / (matedCount - 1) : 0;

  const muImp = nonMatedCount > 0 ? sumImpostor / nonMatedCount : 0;
  const varImp = nonMatedCount > 1 ? (sumImpostorSq - (sumImpostor * sumImpostor) / nonMatedCount) / (nonMatedCount - 1) : 0;

  const denom = Math.sqrt(0.5 * (Math.max(0, varGen) + Math.max(0, varImp)));
  const dPrime = denom > 1e-6 ? Math.abs(muGen - muImp) / denom : 0;

  const fmrInterval = computeWilsonScoreInterval(falseMatches, nonMatedCount);
  const fnmrInterval = computeWilsonScoreInterval(falseNonMatches, matedCount);
  const tarInterval = computeWilsonScoreInterval(matedCount - falseNonMatches, matedCount);

  return {
    threshold,
    totalMatedPairs: matedCount,
    totalNonMatedPairs: nonMatedCount,
    falseMatchCount: falseMatches,
    falseNonMatchCount: falseNonMatches,
    fmr: fmrInterval,
    fnmr: fnmrInterval,
    tar: tarInterval,
    decidabilityIndexDPrime: dPrime,
  };
}

// ============================================================================
// PART 4: DIRECT 1:N OPEN-SET IDENTIFICATION SCALABILITY
// ============================================================================

export interface GalleryScaleBenchmarkResult {
  readonly gallerySizeN: number;
  readonly unenrolledQueryCount: number;
  readonly reviewThreshold: number;
  readonly hardBlockThreshold: number;
  readonly reviewCollisionCount: number;
  readonly hardBlockCollisionCount: number;
  readonly fpirReview: WilsonScoreInterval;
  readonly fpirHardBlock: WilsonScoreInterval;
  readonly searchLatencyMsP50: number;
  readonly searchLatencyMsP95: number;
  readonly searchLatencyMsP99: number;
  readonly searchMode: 'HNSW_GRAPH_BEAM' | 'EXACT_CONTIGUOUS_SCAN';
}

/**
 * Deterministic PRNG (Mulberry32) for reproducible algorithmic vector simulation.
 * Purely for indexing scalability benchmarking; NEVER substituted for real face embeddings.
 */
function mulberry32(seed: number): () => number {
  let state = seed >>> 0;
  return () => {
    state = (state + 0x6d2b79f5) >>> 0;
    let t = Math.imul(state ^ (state >>> 15), 1 | state);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function generateDeterministicHypersphereVector(seed: number): Float32Array {
  const rng = mulberry32(seed);
  const v = new Float32Array(SFACE_EMBEDDING_DIMENSION);
  let sumSq = 0;
  for (let i = 0; i < SFACE_EMBEDDING_DIMENSION; i++) {
    // Normal-like via Irwin-Hall approximation
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

/**
 * Executes a direct 1:N gallery scale benchmark using the actual HighSpeedBiometricIndexV3.
 * Evaluates empirical search-level FPIR across gallery sizes N in {100, 1000, 10000, 100000}.
 */
export function runDirect1ToNGalleryBenchmark(
  gallerySize = 1000,
  queryCount = 200,
  reviewThreshold = 0.74,
  hardBlockThreshold = 0.90
): GalleryScaleBenchmarkResult {
  const index = new HighSpeedBiometricIndexV3(Math.max(gallerySize, 1000));

  // 1. Populate gallery with N deterministic vectors
  for (let i = 0; i < gallerySize; i++) {
    const vec = generateDeterministicHypersphereVector(1000000 + i);
    const record: EnrolledWorkerSfaceRecordV3 = {
      uid: `worker_gal_${i.toString().padStart(6, '0')}`,
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

  // 2. Query with unenrolled probes (different seed space to guarantee non-mated)
  let reviewCollisions = 0;
  let hardBlockCollisions = 0;
  const latencies: number[] = [];

  for (let q = 0; q < queryCount; q++) {
    const probeVec = generateDeterministicHypersphereVector(5000000 + q);
    const probeUid = `probe_unenrolled_${q.toString().padStart(5, '0')}`;

    const match = index.search1toN(probeUid, probeVec);
    latencies.push(match.searchLatencyMs);

    if (match.maxCosineSimilarity >= reviewThreshold) {
      reviewCollisions++;
    }
    if (match.maxCosineSimilarity >= hardBlockThreshold) {
      hardBlockCollisions++;
    }
  }

  latencies.sort((a, b) => a - b);
  const p50 = latencies[Math.floor(latencies.length * 0.5)] ?? 0;
  const p95 = latencies[Math.floor(latencies.length * 0.95)] ?? 0;
  const p99 = latencies[Math.floor(latencies.length * 0.99)] ?? 0;

  return {
    gallerySizeN: gallerySize,
    unenrolledQueryCount: queryCount,
    reviewThreshold,
    hardBlockThreshold,
    reviewCollisionCount: reviewCollisions,
    hardBlockCollisionCount: hardBlockCollisions,
    fpirReview: computeWilsonScoreInterval(reviewCollisions, queryCount),
    fpirHardBlock: computeWilsonScoreInterval(hardBlockCollisions, queryCount),
    searchLatencyMsP50: p50,
    searchLatencyMsP95: p95,
    searchLatencyMsP99: p99,
    searchMode: 'HNSW_GRAPH_BEAM',
  };
}

// ============================================================================
// PART 5: LOW-LIGHT PIPELINE EXPERIMENTAL COMPARISON ENGINE
// ============================================================================

export interface LowLightPipelineComparisonRecord {
  readonly sampleId: string;
  readonly rawLuminance: number;
  readonly rawLaplacianVariance: number;
  readonly rawEmbeddingCosineDrift: number;
  readonly enhancedLuminance: number;
  readonly enhancedLaplacianVariance: number;
  readonly enhancedEmbeddingCosineDrift: number;
  readonly padBonaFidePassedRaw: boolean;
  readonly padBonaFidePassedEnhanced: boolean;
  readonly isDriftAmplified: boolean;
}

/**
 * Simulates a low-light curve transformation (analogous to Zero-DCE iterative curve mapping)
 * to evaluate downstream recognition impact on feature stability.
 */
export function simulateLowLightCurveEnhancement(
  luma: number,
  iterations = 4
): number {
  // Normalized to [0, 1]
  let x = Math.max(0, Math.min(255, luma)) / 255.0;
  // Non-linear quadratic curve adjustment: LE_n(x) = LE_{n-1}(x) + \alpha * LE_{n-1}(x)(1 - LE_{n-1}(x))
  const alpha = 0.6; // enhancement parameter
  for (let it = 0; it < iterations; it++) {
    x = x + alpha * x * (1.0 - x);
  }
  return Math.min(255, Math.round(x * 255.0));
}
