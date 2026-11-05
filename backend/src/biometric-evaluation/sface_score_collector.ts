/**
 * backend/src/biometric-evaluation/sface_score_collector.ts
 *
 * Collects pairwise similarity scores and evaluates:
 * - Cosine similarity: (a · b) / (||a|| ||b||).
 * - FMR (False Match Rate): P(Score >= Threshold | Impostor).
 * - FNMR (False Non-Match Rate): P(Score < Threshold | Genuine).
 * - EER (Equal Error Rate): Threshold where FMR approx FNMR.
 * - ROC (Receiver Operating Characteristic): TAR = 1 - FNMR vs FMR.
 * - DET (Detection Error Tradeoff): FNMR vs FMR.
 */

import { cosineSimilarity } from '../services/biometric_matching';
import { ConfidenceIntervalCalculator, ConfidenceInterval } from './confidence_interval_calculator';

export interface ScoredComparison {
  readonly pairId: string;
  readonly isGenuine: boolean;
  readonly similarity: number;
  readonly subjectIdA: string;
  readonly subjectIdB: string;
}

export interface OperatingPointEvaluation {
  readonly threshold: number;
  readonly genuineCount: number;
  readonly impostorCount: number;
  readonly falseMatches: number;
  readonly falseNonMatches: number;
  readonly fmr: number;
  readonly fnmr: number;
  readonly tar: number; // 1 - fnmr
  readonly fmrCi: ConfidenceInterval;
  readonly fnmrCi: ConfidenceInterval;
}

export interface RocCurve {
  readonly operatingPoints: readonly OperatingPointEvaluation[];
  readonly eer: number;
  readonly eerThreshold: number;
  readonly auc: number; // Area under ROC curve
}

export class SFaceScoreCollector {
  public static evaluatePair(
    pairId: string,
    isGenuine: boolean,
    embA: number[] | Float32Array,
    embB: number[] | Float32Array,
    subjA: string,
    subjB: string
  ): ScoredComparison {
    const sim = cosineSimilarity(embA, embB);
    return {
      pairId,
      isGenuine,
      similarity: Number(sim.toFixed(6)),
      subjectIdA: subjA,
      subjectIdB: subjB,
    };
  }

  public static evaluateOperatingPoint(
    comparisons: readonly ScoredComparison[],
    threshold: number
  ): OperatingPointEvaluation {
    let genuineTotal = 0;
    let impostorTotal = 0;
    let falseMatches = 0;
    let falseNonMatches = 0;

    for (const c of comparisons) {
      if (c.isGenuine) {
        genuineTotal++;
        if (c.similarity < threshold) {
          falseNonMatches++;
        }
      } else {
        impostorTotal++;
        if (c.similarity >= threshold) {
          falseMatches++;
        }
      }
    }

    const fmr = impostorTotal > 0 ? falseMatches / impostorTotal : 0;
    const fnmr = genuineTotal > 0 ? falseNonMatches / genuineTotal : 0;

    const fmrCi = impostorTotal > 0
      ? ConfidenceIntervalCalculator.calculateClopperPearson(falseMatches, impostorTotal)
      : { pointEstimate: 0, lowerBound: 0, upperBound: 0, confidenceLevel: 0.95, sampleSize: 0, errorCount: 0, method: 'CLOPPER_PEARSON_EXACT' as const };

    const fnmrCi = genuineTotal > 0
      ? ConfidenceIntervalCalculator.calculateClopperPearson(falseNonMatches, genuineTotal)
      : { pointEstimate: 0, lowerBound: 0, upperBound: 0, confidenceLevel: 0.95, sampleSize: 0, errorCount: 0, method: 'CLOPPER_PEARSON_EXACT' as const };

    return {
      threshold,
      genuineCount: genuineTotal,
      impostorCount: impostorTotal,
      falseMatches,
      falseNonMatches,
      fmr: Number(fmr.toFixed(8)),
      fnmr: Number(fnmr.toFixed(8)),
      tar: Number((1.0 - fnmr).toFixed(8)),
      fmrCi,
      fnmrCi,
    };
  }

  public static computeRocCurve(
    comparisons: readonly ScoredComparison[],
    steps = 100
  ): RocCurve {
    const operatingPoints: OperatingPointEvaluation[] = [];
    let bestEerDiff = 1.0;
    let eer = 0.0;
    let eerThreshold = 0.363;

    // Sweep from -1.0 to +1.0 to span the full cosine similarity domain
    for (let i = 0; i <= steps; i++) {
      const thresh = Number((-1.0 + (2.0 * i) / steps).toFixed(4));
      const op = this.evaluateOperatingPoint(comparisons, thresh);
      operatingPoints.push(op);

      const diff = Math.abs(op.fmr - op.fnmr);
      if (diff < bestEerDiff) {
        bestEerDiff = diff;
        eer = (op.fmr + op.fnmr) / 2.0;
        eerThreshold = thresh;
      }
    }

    // Trapezoidal numerical integration for AUC (TAR vs FMR)
    let auc = 0.0;
    for (let i = 1; i < operatingPoints.length; i++) {
      const p1 = operatingPoints[i - 1];
      const p2 = operatingPoints[i];
      const deltaFmr = Math.abs(p1.fmr - p2.fmr);
      const avgTar = (p1.tar + p2.tar) / 2.0;
      auc += deltaFmr * avgTar;
    }

    return {
      operatingPoints,
      eer: Number(eer.toFixed(6)),
      eerThreshold,
      auc: Number(Math.min(1.0, Math.max(0.5, auc)).toFixed(6)),
    };
  }
}
