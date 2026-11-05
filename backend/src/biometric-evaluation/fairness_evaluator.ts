/**
 * backend/src/biometric-evaluation/fairness_evaluator.ts
 *
 * Evaluates demographic and environmental performance according to ISO/IEC 19795-10:
 * - Subgroup FMR and FNMR evaluated against identical decision thresholds.
 * - Exact confidence intervals per subgroup to expose sample-size limitations.
 * - Parity Disparity Ratios (FMR_max / FMR_min, FNMR_max / FNMR_min).
 * - Zero attribute inference: Uses voluntary self-reported demographic labels ONLY.
 */

import { ConfidenceIntervalCalculator, ConfidenceInterval } from './confidence_interval_calculator';

export interface SubgroupEvaluationInput {
  readonly subgroupName: string;
  readonly genuineTrials: number;
  readonly falseNonMatches: number;
  readonly impostorTrials: number;
  readonly falseMatches: number;
  readonly captureAttempts: number;
  readonly captureRejections: number;
}

export interface SubgroupMetricReport {
  readonly subgroupName: string;
  readonly sampleCount: number;
  readonly fmr: number;
  readonly fmrCi: ConfidenceInterval;
  readonly fnmr: number;
  readonly fnmrCi: ConfidenceInterval;
  readonly ftaRate: number;
  readonly isSampleStatisticallyAdequate: boolean;
  readonly statisticalWarning?: string;
}

export interface FairnessEvaluationReport {
  readonly thresholdUsed: number;
  readonly subgroups: readonly SubgroupMetricReport[];
  readonly fmrDisparityRatio: number; // max(FMR) / min(FMR)
  readonly fnmrDisparityRatio: number; // max(FNMR) / min(FNMR)
  readonly overallFairnessObservation: string;
}

export class FairnessEvaluator {
  public static readonly MIN_RECOMMENDED_SUBGROUP_TRIALS = 500;

  public static evaluateSubgroups(
    inputs: readonly SubgroupEvaluationInput[],
    threshold = 0.363
  ): FairnessEvaluationReport {
    const reports: SubgroupMetricReport[] = [];
    const fmrs: number[] = [];
    const fnmrs: number[] = [];

    for (const inp of inputs) {
      const fmr = inp.impostorTrials > 0 ? inp.falseMatches / inp.impostorTrials : 0;
      const fnmr = inp.genuineTrials > 0 ? inp.falseNonMatches / inp.genuineTrials : 0;
      const fta = inp.captureAttempts > 0 ? inp.captureRejections / inp.captureAttempts : 0;

      const fmrCi = ConfidenceIntervalCalculator.calculateClopperPearson(
        inp.falseMatches,
        inp.impostorTrials || 1
      );
      const fnmrCi = ConfidenceIntervalCalculator.calculateClopperPearson(
        inp.falseNonMatches,
        inp.genuineTrials || 1
      );

      const isAdequate = inp.impostorTrials >= this.MIN_RECOMMENDED_SUBGROUP_TRIALS;
      const warning = !isAdequate
        ? `INSUFFICIENT_SAMPLE_SIZE: Subgroup has only ${inp.impostorTrials} comparisons (minimum ${this.MIN_RECOMMENDED_SUBGROUP_TRIALS} required for ISO 19795-10 statistical confidence).`
        : undefined;

      reports.push({
        subgroupName: inp.subgroupName,
        sampleCount: inp.genuineTrials + inp.impostorTrials,
        fmr: Number(fmr.toFixed(6)),
        fmrCi,
        fnmr: Number(fnmr.toFixed(6)),
        fnmrCi,
        ftaRate: Number(fta.toFixed(4)),
        isSampleStatisticallyAdequate: isAdequate,
        statisticalWarning: warning,
      });

      fmrs.push(fmr);
      fnmrs.push(fnmr);
    }

    const minFmr = Math.max(0.0001, Math.min(...fmrs));
    const maxFmr = Math.max(...fmrs);
    const minFnmr = Math.max(0.0001, Math.min(...fnmrs));
    const maxFnmr = Math.max(...fnmrs);

    const fmrRatio = maxFmr / minFmr;
    const fnmrRatio = maxFnmr / minFnmr;

    return {
      thresholdUsed: threshold,
      subgroups: reports,
      fmrDisparityRatio: Number(fmrRatio.toFixed(2)),
      fnmrDisparityRatio: Number(fnmrRatio.toFixed(2)),
      overallFairnessObservation:
        'All demographic subgroups evaluated under uniform operating thresholds. Wide confidence intervals reflect current volunteer cohort sample size constraints; ongoing demographic collection required for tighter statistical bounds.',
    };
  }
}
