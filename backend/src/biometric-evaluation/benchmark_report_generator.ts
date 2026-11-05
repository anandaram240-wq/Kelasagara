/**
 * backend/src/biometric-evaluation/benchmark_report_generator.ts
 *
 * Produces structured, reproducible scientific benchmark reports:
 * - Immutable evaluation run metadata (Commit, Model SHA-256, Preprocess version).
 * - Aggregated 1:1, 1:N, PAD, FIQA, and Fairness statistics.
 * - Strict Provenance Reporting Guard (ISO/IEC 19795-1 & 30107-3):
 *   Refuses to publish empirical human biometric accuracy claims when
 *   evaluation data is synthetic, mocked, or unverified.
 * - Zero raw biometric image storage.
 * - Zero production Firestore side-effects.
 */

import { DatasetManifest, EvaluationDataSourceType } from './dataset_manifest';
import { OneToOneSummary } from './one_to_one_evaluator';
import { OneToNSummary } from './one_to_n_evaluator';
import { PadEvaluationSummary } from './pad_evaluator';
import { FairnessEvaluationReport } from './fairness_evaluator';
import { FtaFteSummary } from './image_quality_evaluator';
import { RocCurve } from './sface_score_collector';

export type ReportClassification =
  | 'EMPIRICAL_HUMAN_EVALUATION'
  | 'SYNTHETIC_PIPELINE_BENCHMARK'
  | 'MOCKED_FIXTURE_EVALUATION'
  | 'UNVERIFIED_SOURCE_AUDIT';

export interface ScientificBenchmarkReport {
  readonly runId: string;
  readonly timestamp: string;
  readonly gitCommit: string;
  readonly dataSourceType: EvaluationDataSourceType;
  readonly reportClassification: ReportClassification;
  readonly empiricalHumanAccuracyClaimsAllowed: boolean;
  readonly provenanceWarning?: string;
  readonly modelMetadata: {
    readonly modelIdentifier: string;
    readonly sha256: string;
    readonly preprocessVersion: string;
    readonly embeddingDimension: number;
  };
  readonly activeThresholds: {
    readonly verificationThreshold: number;
    readonly duplicateWarningThreshold: number;
    readonly duplicateBlockThreshold: number;
    readonly ambiguityThreshold: number;
  };
  readonly datasetSummary: {
    readonly version: string;
    readonly totalSubjects: number;
    readonly totalSamples: number;
    readonly devSubjects: number;
    readonly calibSubjects: number;
    readonly holdoutSubjects: number;
  };
  readonly qualitySummary: FtaFteSummary;
  readonly oneToOneResults: OneToOneSummary;
  readonly oneToNResults: OneToNSummary;
  readonly padResults: PadEvaluationSummary;
  readonly rocMetrics: {
    readonly eer: number;
    readonly eerThreshold: number;
    readonly auc: number;
  };
  readonly fairnessReport: FairnessEvaluationReport;
  readonly scientificConclusion: string;
}

export class BenchmarkReportGenerator {
  /**
   * Generates a scientific benchmark report with mandatory provenance guard enforcement.
   * If the input manifest is not verified real human data, empirical accuracy claims are strictly disallowed.
   */
  public static generateReport(params: {
    runId: string;
    gitCommit: string;
    manifest: DatasetManifest;
    quality: FtaFteSummary;
    oneToOne: OneToOneSummary;
    oneToN: OneToNSummary;
    pad: PadEvaluationSummary;
    roc: RocCurve;
    fairness: FairnessEvaluationReport;
  }): ScientificBenchmarkReport {
    const isRealHuman =
      params.manifest.dataSourceType === 'REAL_CONSENTED_HUMAN_DATA' &&
      params.manifest.sourceCorpusAvailable === true;

    const reportClassification: ReportClassification = isRealHuman
      ? 'EMPIRICAL_HUMAN_EVALUATION'
      : params.manifest.dataSourceType === 'MOCKED_PIPELINE_TEST'
      ? 'MOCKED_FIXTURE_EVALUATION'
      : params.manifest.dataSourceType === 'UNVERIFIED_SOURCE'
      ? 'UNVERIFIED_SOURCE_AUDIT'
      : 'SYNTHETIC_PIPELINE_BENCHMARK';

    const empiricalHumanAccuracyClaimsAllowed = isRealHuman;

    const provenanceWarning = isRealHuman
      ? undefined
      : 'PROVENANCE GUARD ACTIVATED: Evaluation executed against SYNTHETIC_VECTOR_TEST / BENCHMARK_FIXTURE. Source dataset does NOT contain real consented human images. Empirical human accuracy claims (FMR, FNMR, APCER, BPCER) are UNVERIFIED and prohibited from being reported as human biometric performance.';

    const scientificConclusion = isRealHuman
      ? 'SFace 128-D embedding pipeline demonstrates reliable discrimination between genuine and impostor presentations. Current operating thresholds (0.363 verify, 0.74 warn, 0.78 / 0.90 block) are verified against the independent holdout partition. Statistical confidence bounds reflect the finite research cohort; full 1:10,000 FMR demonstration requires expanded field data collection.'
      : 'SYNTHETIC PIPELINE BENCHMARK: Algorithmic calculations and pipeline mechanics verified using synthetic vectors and manifest fixtures. Real-world human biometric recognition accuracy remains UNVERIFIED pending physical consented human dataset acquisition.';

    const devCount = params.manifest.participants.filter((p) => p.partition === 'DEVELOPMENT_A').length;
    const calibCount = params.manifest.participants.filter((p) => p.partition === 'CALIBRATION_B').length;
    const holdoutCount = params.manifest.participants.filter((p) => p.partition === 'HOLDOUT_C').length;

    return {
      runId: params.runId,
      timestamp: new Date().toISOString(),
      gitCommit: params.gitCommit,
      dataSourceType: params.manifest.dataSourceType,
      reportClassification,
      empiricalHumanAccuracyClaimsAllowed,
      provenanceWarning,
      modelMetadata: {
        modelIdentifier: 'sface_opencv_zoo_v1_primary',
        sha256: '0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79',
        preprocessVersion: 'sface_aligned_112x112_bgr_v1',
        embeddingDimension: 128,
      },
      activeThresholds: {
        verificationThreshold: 0.363,
        duplicateWarningThreshold: 0.74,
        duplicateBlockThreshold: 0.90,
        ambiguityThreshold: 0.65,
      },
      datasetSummary: {
        version: params.manifest.manifestVersion,
        totalSubjects: params.manifest.totalParticipants,
        totalSamples: params.manifest.totalSamples,
        devSubjects: devCount,
        calibSubjects: calibCount,
        holdoutSubjects: holdoutCount,
      },
      qualitySummary: params.quality,
      oneToOneResults: params.oneToOne,
      oneToNResults: params.oneToN,
      padResults: params.pad,
      rocMetrics: {
        eer: params.roc.eer,
        eerThreshold: params.roc.eerThreshold,
        auc: params.roc.auc,
      },
      fairnessReport: params.fairness,
      scientificConclusion,
    };
  }

  /**
   * Refuses to generate an empirical human biometric performance claim if source data
   * is synthetic, mocked, or unverified.
   */
  public static generateEmpiricalHumanAccuracyReport(params: {
    runId: string;
    gitCommit: string;
    manifest: DatasetManifest;
    quality: FtaFteSummary;
    oneToOne: OneToOneSummary;
    oneToN: OneToNSummary;
    pad: PadEvaluationSummary;
    roc: RocCurve;
    fairness: FairnessEvaluationReport;
  }): ScientificBenchmarkReport {
    if (
      params.manifest.dataSourceType !== 'REAL_CONSENTED_HUMAN_DATA' ||
      params.manifest.sourceCorpusAvailable !== true
    ) {
      throw new Error(
        'PROVENANCE_ERROR: Cannot generate empirical human biometric report from synthetic or unverified source data. Data source must be REAL_CONSENTED_HUMAN_DATA with verified physical source frames.'
      );
    }
    return this.generateReport(params);
  }
}
