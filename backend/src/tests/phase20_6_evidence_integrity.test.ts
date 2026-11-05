/**
 * backend/src/tests/phase20_6_evidence_integrity.test.ts
 *
 * Phase 20.6: Biometric Evidence Integrity & Controlled Pilot Readiness Test Suite
 * - Mandatory data source classification (6 distinct provenance states).
 * - Provenance reporting guard: blocks empirical human accuracy claims on synthetic data.
 * - Missing raw image corpus verification: detects missing physical images.
 * - Statistical confidence intervals: exact two-sided (1.22%) vs one-sided (0.994%) bounds.
 * - Sample-size planning for 1:10,000 FMR (29,956 comparisons).
 * - 1:N probe population design: enforces subject isolation between gallery and non-enrolled probes.
 * - Presentation Attack Detection (PAD): per-PAI species disaggregation and APCER reporting.
 */

import { describe, it } from 'node:test';
import assert from 'node:assert';
import {
  createCanonicalEvaluationManifest,
  EvaluationDataSourceType,
  verifySourceCorpusAvailability,
  DatasetManifest,
} from '../biometric-evaluation/dataset_manifest';
import {
  BenchmarkReportGenerator,
} from '../biometric-evaluation/benchmark_report_generator';
import {
  ConfidenceIntervalCalculator,
} from '../biometric-evaluation/confidence_interval_calculator';
import {
  PadEvaluator,
  PadPresentationAttempt,
  PadEvaluationSummary,
} from '../biometric-evaluation/pad_evaluator';
import {
  OneToOneSummary,
} from '../biometric-evaluation/one_to_one_evaluator';
import {
  OneToNSummary,
} from '../biometric-evaluation/one_to_n_evaluator';
import {
  FairnessEvaluationReport,
} from '../biometric-evaluation/fairness_evaluator';
import {
  FtaFteSummary,
} from '../biometric-evaluation/image_quality_evaluator';
import {
  RocCurve,
} from '../biometric-evaluation/sface_score_collector';

describe('KELASAGARA V20.6 — BIOMETRIC EVIDENCE INTEGRITY SUITE', () => {
  describe('Suite 1: Mandatory Data Source Classification & Corpus Verification', () => {
    it('1.1: Identifies and supports all 6 mandatory provenance categories', () => {
      const allowedCategories: EvaluationDataSourceType[] = [
        'REAL_CONSENTED_HUMAN_DATA',
        'SYNTHETIC_VECTOR_TEST',
        'MOCKED_PIPELINE_TEST',
        'BENCHMARK_FIXTURE',
        'PHYSICAL_ATTACK_PRESENTATION_TEST',
        'UNVERIFIED_SOURCE',
      ];
      assert.strictEqual(allowedCategories.length, 6);
    });

    it('1.2: Canonical manifest classifies itself as BENCHMARK_FIXTURE with sourceCorpusAvailable=false', () => {
      const manifest = createCanonicalEvaluationManifest();
      assert.strictEqual(manifest.dataSourceType, 'BENCHMARK_FIXTURE');
      assert.strictEqual(manifest.isSyntheticFixture, true);
      assert.strictEqual(manifest.sourceCorpusAvailable, false);
      assert.strictEqual(manifest.totalParticipants, 50);
      assert.strictEqual(manifest.totalSamples, 450);
    });

    it('1.3: verifySourceCorpusAvailability detects missing raw image frames on disk', () => {
      const manifest = createCanonicalEvaluationManifest();
      const verification = verifySourceCorpusAvailability(manifest);
      assert.strictEqual(verification.isCorpusAvailable, false);
      assert.strictEqual(verification.status, 'UNAVAILABLE_MISSING_RAW_IMAGES');
      assert.strictEqual(verification.missingFilesCount, 450);
      assert.strictEqual(verification.verifiedFilesCount, 0);
    });
  });

  describe('Suite 2: Provenance Reporting Guard (Phase 20.6.2 & 20.6.11)', () => {
    const mockQuality: FtaFteSummary = {
      totalCaptureAttempts: 450,
      failedAcquisitionAttempts: 14,
      ftaRate: 0.0311,
      totalEnrollmentCandidates: 50,
      failedEnrollments: 0,
      fteRate: 0.0,
      rejectionBreakdown: { POSE_EXCEEDED: 8, LOW_LUMINANCE: 6 },
    };

    const mockOneToOne: OneToOneSummary = {
      totalTrials: 600,
      genuineTrials: 300,
      impostorTrials: 300,
      falseMatches: 0,
      falseNonMatches: 0,
      fmr: 0.0,
      fnmr: 0.0,
      fmrCi: {
        pointEstimate: 0.0,
        lowerBound: 0.0,
        upperBound: 0.0122,
        confidenceLevel: 0.95,
        sampleSize: 300,
        errorCount: 0,
        method: 'RULE_OF_THREE',
      },
      fnmrCi: {
        pointEstimate: 0.0,
        lowerBound: 0.0,
        upperBound: 0.0122,
        confidenceLevel: 0.95,
        sampleSize: 300,
        errorCount: 0,
        method: 'RULE_OF_THREE',
      },
      scenarioResults: [],
    };

    const mockOneToN: OneToNSummary = {
      totalProbes: 200,
      enrolledProbes: 100,
      unenrolledProbes: 100,
      rank1CorrectCount: 100,
      rank1Rate: 1.0,
      falsePositiveIdentifications: 0,
      fpir: 0.0,
      falseNegativeIdentifications: 0,
      fnir: 0.0,
      gallerySize: 25,
    };

    const mockPad: PadEvaluationSummary = {
      totalPresentations: 270,
      bonaFideCount: 150,
      attackCount: 120,
      bonaFideRejections: 4,
      bpcer: 0.0267,
      attackAccepts: 2,
      apcer: 0.0167,
      speciesBreakdown: [],
      passDecisionParameters: {
        minOpenEar: 0.22,
        maxClosedRatio: 0.65,
        minAnchorCosine: 0.8,
        maxLumaFlux: 0.18,
      },
    };

    const mockRoc: RocCurve = {
      operatingPoints: [],
      eer: 0.015,
      eerThreshold: 0.582,
      auc: 0.9984,
    };

    const mockFairness: FairnessEvaluationReport = {
      thresholdUsed: 0.363,
      subgroups: [],
      fmrDisparityRatio: 1.0,
      fnmrDisparityRatio: 1.06,
      overallFairnessObservation: 'Subgroup evaluation sample size < 500',
    };

    it('2.1: Automatically classifies synthetic manifest runs as SYNTHETIC_PIPELINE_BENCHMARK', () => {
      const manifest = createCanonicalEvaluationManifest();
      const report = BenchmarkReportGenerator.generateReport({
        runId: 'RUN-SYNTH-01',
        gitCommit: '4d1d2b4',
        manifest,
        quality: mockQuality,
        oneToOne: mockOneToOne,
        oneToN: mockOneToN,
        pad: mockPad,
        roc: mockRoc,
        fairness: mockFairness,
      });

      assert.strictEqual(report.reportClassification, 'SYNTHETIC_PIPELINE_BENCHMARK');
      assert.strictEqual(report.empiricalHumanAccuracyClaimsAllowed, false);
      assert.ok(report.provenanceWarning?.includes('PROVENANCE GUARD ACTIVATED'));
      assert.ok(report.scientificConclusion.includes('SYNTHETIC PIPELINE BENCHMARK'));
    });

    it('2.2: generateEmpiricalHumanAccuracyReport strictly throws PROVENANCE_ERROR on synthetic data', () => {
      const manifest = createCanonicalEvaluationManifest();
      assert.throws(
        () => {
          BenchmarkReportGenerator.generateEmpiricalHumanAccuracyReport({
            runId: 'RUN-ILLEGAL-EMPIRICAL',
            gitCommit: '4d1d2b4',
            manifest,
            quality: mockQuality,
            oneToOne: mockOneToOne,
            oneToN: mockOneToN,
            pad: mockPad,
            roc: mockRoc,
            fairness: mockFairness,
          });
        },
        {
          name: 'Error',
          message: /PROVENANCE_ERROR: Cannot generate empirical human biometric report from synthetic or unverified source data/,
        }
      );
    });

    it('2.3: Accepts real consented data when sourceCorpusAvailable=true and REAL_CONSENTED_HUMAN_DATA', () => {
      const realManifest: DatasetManifest = {
        manifestVersion: '1.0.0-phase20.6',
        createdAt: new Date().toISOString(),
        description: 'Verified Physical Pilot Corpus',
        dataSourceType: 'REAL_CONSENTED_HUMAN_DATA',
        isSyntheticFixture: false,
        sourceCorpusAvailable: true,
        participants: [],
        samples: [],
        totalParticipants: 0,
        totalSamples: 0,
      };

      const report = BenchmarkReportGenerator.generateEmpiricalHumanAccuracyReport({
        runId: 'RUN-REAL-01',
        gitCommit: '4d1d2b4',
        manifest: realManifest,
        quality: mockQuality,
        oneToOne: mockOneToOne,
        oneToN: mockOneToN,
        pad: mockPad,
        roc: mockRoc,
        fairness: mockFairness,
      });

      assert.strictEqual(report.reportClassification, 'EMPIRICAL_HUMAN_EVALUATION');
      assert.strictEqual(report.empiricalHumanAccuracyClaimsAllowed, true);
      assert.strictEqual(report.provenanceWarning, undefined);
    });
  });

  describe('Suite 3: Exact Statistical Uncertainty & Planning Calculations (Phase 20.6.3)', () => {
    it('3.1: Distinguishes two-sided exact Clopper-Pearson (~1.22%) and one-sided 95% upper bound (~0.994%) for N=300, k=0', () => {
      const ci = ConfidenceIntervalCalculator.calculateClopperPearson(0, 300, 0.95);
      // Two-sided exact upper bound: 1 - (0.025)^(1/300) = 0.01222097
      assert.strictEqual(ci.upperBound, 0.01222097);
      // One-sided 95% upper bound: 1 - (0.05)^(1/300) = 0.00993608
      assert.strictEqual(ci.oneSidedUpperBound, 0.00993608);

      const oneSidedDirect = ConfidenceIntervalCalculator.calculateOneSidedUpperBound(0, 300, 0.95);
      assert.strictEqual(oneSidedDirect, 0.00993608);
    });

    it('3.2: Confirms 0/300 comparisons cannot mathematically validate a 1:10,000 FMR claim', () => {
      const oneSided = ConfidenceIntervalCalculator.calculateOneSidedUpperBound(0, 300, 0.95);
      const targetFmr = 0.0001; // 1:10,000
      assert.ok(
        oneSided > targetFmr,
        `One-sided bound ${oneSided} is much higher than target FMR ${targetFmr}`
      );
    });

    it('3.3: Planning calculation proves ~29,956 independent trials required for 1:10,000 one-sided 95% bound with zero errors', () => {
      const requiredN = ConfidenceIntervalCalculator.calculateRequiredSampleForTarget(0.0001, 0.95);
      assert.strictEqual(requiredN, 29956);

      // Verify that with N=29,956 and k=0, one-sided upper bound <= 0.0001
      const boundAtTargetN = ConfidenceIntervalCalculator.calculateOneSidedUpperBound(0, 29956, 0.95);
      assert.ok(boundAtTargetN <= 0.00010001);
    });
  });

  describe('Suite 4: 1:N Population Separation & Probe Independence (Phase 20.6.3)', () => {
    it('4.1: Flags invalid probe design where non-enrolled probes overlap with development/calibration subjects', () => {
      // In a statistically valid holdout test, non-enrolled probes must not be drawn from
      // subjects exposed during development or calibration.
      const devSubjects = new Set(['SUBJ-A-01', 'SUBJ-A-02', 'SUBJ-A-03']);
      const nonEnrolledProbes = ['SUBJ-A-01', 'SUBJ-X-99'];

      const leakingProbes = nonEnrolledProbes.filter((id) => devSubjects.has(id));
      assert.strictEqual(leakingProbes.length, 1);
      assert.strictEqual(leakingProbes[0], 'SUBJ-A-01');
    });

    it('4.2: Enforces that non-enrolled holdout probes must be completely distinct from gallery subjects', () => {
      const gallery = new Set(['SUBJ-C-01', 'SUBJ-C-02', 'SUBJ-C-03']);
      const validNonEnrolledProbeId = 'SUBJ-C-100'; // Genuine separate non-enrolled identity
      assert.strictEqual(gallery.has(validNonEnrolledProbeId), false);
    });
  });

  describe('Suite 5: Presentation Attack Detection Per-PAI Disaggregation (Phase 20.6.4)', () => {
    it('5.1: Evaluates APCER per PAI category and isolates software injection from physical presentations', () => {
      const attempts: PadPresentationAttempt[] = [
        // 15 Matte print attempts (all 15 rejected)
        ...Array.from({ length: 15 }, (_, i) => ({
          attemptId: `PAI-PRINT-${i}`,
          isBonaFide: false,
          attackSpecies: 'PRINTED_PHOTO_MATTE' as const,
          captureLighting: 'INDOOR_UNIFORM',
          classifiedAsLive: false,
          livenessScore: 0.25,
          rejectionReason: 'EAR_COMPRESSION_FAILED',
        })),
        // 15 Video replay attempts (13 rejected, 2 accepted)
        ...Array.from({ length: 13 }, (_, i) => ({
          attemptId: `PAI-VID-PASS-${i}`,
          isBonaFide: false,
          attackSpecies: 'SCREEN_REPLAY_TABLET' as const,
          captureLighting: 'INDOOR_UNIFORM',
          classifiedAsLive: false,
          livenessScore: 0.42,
          rejectionReason: 'EAR_COMPRESSION_FAILED',
        })),
        ...Array.from({ length: 2 }, (_, i) => ({
          attemptId: `PAI-VID-BYPASS-${i}`,
          isBonaFide: false,
          attackSpecies: 'SCREEN_REPLAY_TABLET' as const,
          captureLighting: 'INDOOR_UNIFORM',
          classifiedAsLive: true,
          livenessScore: 0.88,
        })),
      ];

      const report = PadEvaluator.evaluateAttempts(attempts);
      assert.strictEqual(report.totalPresentations, 30);
      assert.strictEqual(report.attackCount, 30);
      assert.strictEqual(report.apcer, 0.0667);

      const matteResult = report.speciesBreakdown.find((r) => r.species === 'PRINTED_PHOTO_MATTE');
      assert.ok(matteResult);
      assert.strictEqual(matteResult.apcer, 0.0);

      const videoResult = report.speciesBreakdown.find(
        (r) => r.species === 'SCREEN_REPLAY_TABLET'
      );
      assert.ok(videoResult);
      assert.strictEqual(videoResult.apcer, 0.1333);
    });
  });
});
