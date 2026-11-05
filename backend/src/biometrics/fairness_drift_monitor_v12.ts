/**
 * KELASAGARA BIOMETRIC ENGINE V12.0 — PHASE 12.3
 * File: backend/src/biometrics/fairness_drift_monitor_v12.ts
 *
 * ISO/IEC 19795-10 Demographic Differential Performance & Grey-Zone Drift Monitor.
 * Tracks GAR, FRR, FAR, and Grey-Zone step-up rates across luminance bands and Android sensor tiers.
 */

export type LuminanceCohortV12 = 'LOW_LIGHT_40_85' | 'BALANCED_85_175' | 'BRIGHT_SUN_175_220';
export type SensorTierCohortV12 = 'ANDROID_BUDGET' | 'ANDROID_MIDRANGE' | 'ANDROID_FLAGSHIP_OR_IOS';

export type DecisionOutcomeTypeV12 =
  | 'GENUINE_VERIFIED'
  | 'GENUINE_FALSE_REJECT'
  | 'GREY_ZONE_STEP_UP'
  | 'IMPOSTOR_REJECTED'
  | 'IMPOSTOR_FALSE_ACCEPT'
  | 'PAD_OR_FIQA_REJECTED';

export interface TelemetryObservationV12 {
  readonly timestampMs: number;
  readonly luminanceMean: number;
  readonly sensorTier: SensorTierCohortV12;
  readonly regionCode: string;
  readonly similarityScore: number;
  readonly outcome: DecisionOutcomeTypeV12;
  readonly latencyMs: number;
}

export interface CohortMetricsSummaryV12 {
  readonly cohortKey: string;
  readonly sampleCount: number;
  readonly genuineAcceptRate: number; // GAR = 1 - FRR
  readonly falseRejectRate: number; // FRR
  readonly greyZoneStepUpRate: number;
  readonly padFiqaRejectRate: number;
  readonly meanSimilarityScore: number;
  readonly p95LatencyMs: number;
}

export interface FairnessDriftAuditReportV12 {
  readonly evaluatedAtMs: number;
  readonly totalWindowSamples: number;
  readonly globalGreyZoneRate: number;
  readonly iso19795DifferentialDisparityRatio: number; // min(GAR_cohort) / max(GAR_cohort)
  readonly passes80PercentParityRule: boolean; // Four-Fifths (0.80) fairness parity invariant
  readonly maxCohortGreyZoneRate: number;
  readonly driftAlertTriggered: boolean;
  readonly alertReasons: readonly string[];
  readonly cohortBreakdowns: readonly CohortMetricsSummaryV12[];
}

export interface FairnessPolicyConfigV12 {
  readonly windowCapacity?: number;
  readonly minCohortSamplesForParity?: number;
  readonly maxAllowedGreyZoneStepUpRate?: number; // Default 0.05 (5.0%)
  readonly minIsoParityRatio?: number; // Default 0.80 (ISO/IEC 19795-10 parity threshold)
}

export class FairnessDriftMonitorV12 {
  private readonly buffer: TelemetryObservationV12[] = [];
  private readonly windowCapacity: number;
  private readonly minCohortSamplesForParity: number;
  private readonly maxAllowedGreyZoneStepUpRate: number;
  private readonly minIsoParityRatio: number;

  constructor(config: FairnessPolicyConfigV12 = {}) {
    this.windowCapacity = config.windowCapacity ?? 5000;
    this.minCohortSamplesForParity = config.minCohortSamplesForParity ?? 20;
    this.maxAllowedGreyZoneStepUpRate = config.maxAllowedGreyZoneStepUpRate ?? 0.05;
    this.minIsoParityRatio = config.minIsoParityRatio ?? 0.80;
  }

  public static classifyLuminanceCohort(luminanceMean: number): LuminanceCohortV12 {
    if (luminanceMean < 85) return 'LOW_LIGHT_40_85';
    if (luminanceMean <= 175) return 'BALANCED_85_175';
    return 'BRIGHT_SUN_175_220';
  }

  public recordObservation(obs: TelemetryObservationV12): void {
    if (this.buffer.length >= this.windowCapacity) {
      this.buffer.shift();
    }
    this.buffer.push(obs);
  }

  public evaluateFairnessAndDrift(nowMs = Date.now()): FairnessDriftAuditReportV12 {
    if (this.buffer.length === 0) {
      return {
        evaluatedAtMs: nowMs,
        totalWindowSamples: 0,
        globalGreyZoneRate: 0,
        iso19795DifferentialDisparityRatio: 1.0,
        passes80PercentParityRule: true,
        maxCohortGreyZoneRate: 0,
        driftAlertTriggered: false,
        alertReasons: [],
        cohortBreakdowns: [],
      };
    }

    const grouped = new Map<string, TelemetryObservationV12[]>();
    let totalGreyZone = 0;

    for (const item of this.buffer) {
      if (item.outcome === 'GREY_ZONE_STEP_UP') {
        totalGreyZone++;
      }
      const lumBand = FairnessDriftMonitorV12.classifyLuminanceCohort(item.luminanceMean);
      const key = `${item.sensorTier}::${lumBand}`;
      const list = grouped.get(key);
      if (list) {
        list.push(item);
      } else {
        grouped.set(key, [item]);
      }
    }

    const cohortBreakdowns: CohortMetricsSummaryV12[] = [];
    const eligibleGarRates: number[] = [];
    let maxCohortGreyZoneRate = 0;
    const alertReasons: string[] = [];

    for (const [cohortKey, items] of grouped.entries()) {
      let genuinePass = 0;
      let genuineFail = 0;
      let greyZoneCount = 0;
      let padFiqaRejects = 0;
      let simSum = 0;
      const latencies: number[] = [];

      for (const obs of items) {
        simSum += obs.similarityScore;
        latencies.push(obs.latencyMs);
        if (obs.outcome === 'GENUINE_VERIFIED') genuinePass++;
        else if (obs.outcome === 'GENUINE_FALSE_REJECT') genuineFail++;
        else if (obs.outcome === 'GREY_ZONE_STEP_UP') greyZoneCount++;
        else if (obs.outcome === 'PAD_OR_FIQA_REJECTED') padFiqaRejects++;
      }

      const genuineTotal = genuinePass + genuineFail;
      const gar = genuineTotal > 0 ? genuinePass / genuineTotal : 1.0;
      const frr = genuineTotal > 0 ? genuineFail / genuineTotal : 0.0;
      const greyZoneRate = greyZoneCount / items.length;
      const padFiqaRate = padFiqaRejects / items.length;

      latencies.sort((a, b) => a - b);
      const p95Idx = Math.min(latencies.length - 1, Math.floor(latencies.length * 0.95));

      const summary: CohortMetricsSummaryV12 = {
        cohortKey,
        sampleCount: items.length,
        genuineAcceptRate: Number(gar.toFixed(4)),
        falseRejectRate: Number(frr.toFixed(4)),
        greyZoneStepUpRate: Number(greyZoneRate.toFixed(4)),
        padFiqaRejectRate: Number(padFiqaRate.toFixed(4)),
        meanSimilarityScore: Number((simSum / items.length).toFixed(4)),
        p95LatencyMs: Number((latencies[p95Idx] ?? 0).toFixed(2)),
      };

      cohortBreakdowns.push(summary);

      if (items.length >= this.minCohortSamplesForParity) {
        eligibleGarRates.push(gar);
        if (greyZoneRate > maxCohortGreyZoneRate) {
          maxCohortGreyZoneRate = greyZoneRate;
        }
        if (greyZoneRate > this.maxAllowedGreyZoneStepUpRate) {
          alertReasons.push(
            `COHORT_GREY_ZONE_DRIFT_EXCEEDED:${cohortKey} (${(greyZoneRate * 100).toFixed(2)}% > ${(
              this.maxAllowedGreyZoneStepUpRate * 100
            ).toFixed(2)}%)`
          );
        }
      }
    }

    let parityRatio = 1.0;
    if (eligibleGarRates.length >= 2) {
      const minGar = Math.min(...eligibleGarRates);
      const maxGar = Math.max(...eligibleGarRates);
      parityRatio = maxGar > 0 ? Number((minGar / maxGar).toFixed(4)) : 1.0;
    }

    const passes80PercentParityRule = parityRatio >= this.minIsoParityRatio;
    if (!passes80PercentParityRule) {
      alertReasons.push(
        `ISO_19795_10_DEMOGRAPHIC_PARITY_BREACH: GAR ratio ${parityRatio} < ${this.minIsoParityRatio}`
      );
    }

    const globalGreyZoneRate = Number((totalGreyZone / this.buffer.length).toFixed(4));

    return {
      evaluatedAtMs: nowMs,
      totalWindowSamples: this.buffer.length,
      globalGreyZoneRate,
      iso19795DifferentialDisparityRatio: parityRatio,
      passes80PercentParityRule,
      maxCohortGreyZoneRate: Number(maxCohortGreyZoneRate.toFixed(4)),
      driftAlertTriggered: alertReasons.length > 0,
      alertReasons,
      cohortBreakdowns,
    };
  }
}
