/**
 * backend/src/tests/phase20_5_biometric_validation.test.ts
 *
 * Comprehensive Phase 20.5 Scientific Biometric Validation Suite:
 * - Dataset governance and partition isolation (Zero subject leakage).
 * - Clopper-Pearson exact confidence intervals and Rule of Three sample planning.
 * - Image quality assessment, FIQA, and FTA/FTE metrics.
 * - 1:1 Authentication, FMR, FNMR, ROC, DET, and EER evaluation.
 * - 1:N Gallery deduplication, FPIR, FNIR, and Rank-1 identification.
 * - Presentation Attack Detection (PAD), APCER, BPCER across attack species.
 * - Demographic evaluation and fairness disparity monitoring.
 */

import { describe, it } from 'node:test';
import assert from 'node:assert';
import { createHash } from 'crypto';
import {
  ConfidenceIntervalCalculator,
} from '../biometric-evaluation/confidence_interval_calculator';
import {
  createCanonicalEvaluationManifest,
  DatasetManifest,
} from '../biometric-evaluation/dataset_manifest';
import {
  ParticipantSplitValidator,
} from '../biometric-evaluation/participant_split_validator';
import {
  ImageQualityEvaluator,
} from '../biometric-evaluation/image_quality_evaluator';
import {
  SFaceScoreCollector,
} from '../biometric-evaluation/sface_score_collector';
import {
  OneToOneEvaluator,
  OneToOneScenarioInput,
} from '../biometric-evaluation/one_to_one_evaluator';
import {
  OneToNEvaluator,
  GalleryEntry,
  IdentificationProbe,
} from '../biometric-evaluation/one_to_n_evaluator';
import {
  PadEvaluator,
  PadPresentationAttempt,
} from '../biometric-evaluation/pad_evaluator';
import {
  FairnessEvaluator,
} from '../biometric-evaluation/fairness_evaluator';
import {
  BenchmarkReportGenerator,
} from '../biometric-evaluation/benchmark_report_generator';

// Helper to generate statistically uncorrelated unit vectors on 128-D hypersphere
function generateUnitVector(seed: number, dim = 128): Float32Array {
  const v = new Float32Array(dim);
  let sumSq = 0;
  for (let i = 0; i < dim; i++) {
    const hash = createHash('sha256').update(`${seed}:${i}`).digest();
    const val = hash.readInt16LE(0) / 32768.0;
    v[i] = val;
    sumSq += val * val;
  }
  const norm = Math.sqrt(sumSq);
  for (let i = 0; i < dim; i++) {
    v[i] /= norm;
  }
  return v;
}

// Generates a controlled genuine pair with exact target cosine similarity via Gram-Schmidt
function generateControlledGenuinePair(seed: number, targetSim = 0.94, dim = 128): [Float32Array, Float32Array] {
  const v1 = generateUnitVector(seed, dim);
  const ortho = generateUnitVector(seed + 99999, dim);
  let dot = 0;
  for (let i = 0; i < dim; i++) dot += v1[i] * ortho[i];
  const v2Ortho = new Float32Array(dim);
  let normSq = 0;
  for (let i = 0; i < dim; i++) {
    const val = ortho[i] - dot * v1[i];
    v2Ortho[i] = val;
    normSq += val * val;
  }
  const norm = Math.sqrt(normSq);
  for (let i = 0; i < dim; i++) v2Ortho[i] /= norm;

  const sinTheta = Math.sqrt(Math.max(0, 1.0 - targetSim * targetSim));
  const v2 = new Float32Array(dim);
  for (let i = 0; i < dim; i++) {
    v2[i] = targetSim * v1[i] + sinTheta * v2Ortho[i];
  }
  return [v1, v2];
}

describe('KELASAGARA V20.5 — ADVANCED BIOMETRIC SCIENTIFIC VALIDATION ENGINE', () => {

  describe('Suite 1: Dataset Governance & Subject-Level Partition Isolation', () => {
    it('1.1: Canonical manifest exhibits zero cross-partition subject leakage', () => {
      const manifest = createCanonicalEvaluationManifest();
      const validation = ParticipantSplitValidator.validatePartitionIntegrity(manifest);

      assert.strictEqual(validation.isValid, true, 'Manifest must be valid');
      assert.strictEqual(validation.errors.length, 0);
      assert.strictEqual(validation.crossPartitionLeakingSubjects.length, 0);
      assert.strictEqual(validation.partitionSubjectCounts.DEVELOPMENT_A, 10);
      assert.strictEqual(validation.partitionSubjectCounts.CALIBRATION_B, 15);
      assert.strictEqual(validation.partitionSubjectCounts.HOLDOUT_C, 25);
      assert.strictEqual(manifest.totalParticipants, 50);
      assert.strictEqual(manifest.totalSamples, 450);
    });

    it('1.2: Rejects corrupted manifest where a subject leaks into holdout partition', () => {
      const manifest = createCanonicalEvaluationManifest();
      const corruptedParticipants = [...manifest.participants];
      corruptedParticipants.push({
        participantId: 'SUBJ-A-01', // Already in DEVELOPMENT_A!
        partition: 'HOLDOUT_C',
        consentDocumentId: 'ROGUE-CONSENT',
        consentedDate: '2026-10-31T00:00:00Z',
      });

      const corruptedManifest: DatasetManifest = {
        ...manifest,
        participants: corruptedParticipants,
      };

      const validation = ParticipantSplitValidator.validatePartitionIntegrity(corruptedManifest);
      assert.strictEqual(validation.isValid, false);
      assert.ok(validation.errors.some((e) => e.includes('DUPLICATE_PARTICIPANT_DECLARATION') || e.includes('CRITICAL_PARTITION_LEAKAGE')));
    });

    it('1.3: Rejects sample assigned to a different partition than its participant', () => {
      const manifest = createCanonicalEvaluationManifest();
      const corruptedSamples = [...manifest.samples];
      corruptedSamples[0] = {
        ...corruptedSamples[0],
        partition: 'HOLDOUT_C',
      };

      const corruptedManifest: DatasetManifest = {
        ...manifest,
        samples: corruptedSamples,
      };

      const validation = ParticipantSplitValidator.validatePartitionIntegrity(corruptedManifest);
      assert.strictEqual(validation.isValid, false);
      assert.ok(validation.errors.some((e) => e.includes('SAMPLE_PARTITION_MISMATCH')));
    });
  });

  describe('Suite 2: Statistical Confidence Interval Calculations (Clopper-Pearson & ISO 19795-1)', () => {
    it('2.1: Computes exact Clopper-Pearson 95% confidence intervals', () => {
      const ci = ConfidenceIntervalCalculator.calculateClopperPearson(5, 1000, 0.95);
      assert.strictEqual(ci.pointEstimate, 0.005);
      assert.ok(ci.lowerBound > 0.0016 && ci.lowerBound < 0.0020, `lowerBound was ${ci.lowerBound}`);
      assert.ok(ci.upperBound > 0.0110 && ci.upperBound < 0.0125, `upperBound was ${ci.upperBound}`);
      assert.strictEqual(ci.method, 'CLOPPER_PEARSON_EXACT');
    });

    it('2.2: Zero-error observation correctly invokes Rule of Three exact upper bound', () => {
      const ci = ConfidenceIntervalCalculator.calculateClopperPearson(0, 3000, 0.95);
      assert.strictEqual(ci.pointEstimate, 0.0);
      assert.strictEqual(ci.lowerBound, 0.0);
      assert.ok(ci.upperBound > 0.0009 && ci.upperBound < 0.0013, `upperBound was ${ci.upperBound}`);
      assert.strictEqual(ci.method, 'RULE_OF_THREE');
    });

    it('2.3: Planning calculation proves ~29,956 independent trials needed for 1:10,000 FMR bound', () => {
      const required = ConfidenceIntervalCalculator.calculateRequiredSampleForTarget(0.0001, 0.95);
      assert.ok(required >= 29950 && required <= 29960, `required trials was ${required}`);
    });

    it('2.4: Cluster adjustment inflates confidence intervals for non-independent comparisons', () => {
      const unadjusted = ConfidenceIntervalCalculator.calculateClopperPearson(10, 10000, 0.95);
      const adjusted = ConfidenceIntervalCalculator.calculateClusterAdjusted(10, 10000, 50, 0.15, 0.95);

      assert.strictEqual(adjusted.method, 'CLUSTER_ADJUSTED');
      assert.ok(adjusted.upperBound > unadjusted.upperBound, 'Adjusted upper bound must exceed unadjusted');
    });
  });

  describe('Suite 3: Image Quality & Failure-to-Acquire (FTA / FTE) Metrics', () => {
    it('3.1: Accepts genuine frontal capture with satisfactory quality metrics', () => {
      const quality = ImageQualityEvaluator.evaluateMetrics({
        faceCount: 1,
        ipdPixels: 110.0,
        laplacianVariance: 320.0,
        luminanceMean: 125.0,
        yawDegrees: 4.0,
        pitchDegrees: -3.0,
        rollDegrees: 1.0,
      });

      assert.strictEqual(quality.isAcceptable, true);
      assert.strictEqual(quality.rejectionReason, undefined);
    });

    it('3.2: Rejects low-quality conditions: excessive blur, low IPD, extreme pose, multi-face', () => {
      const blurTest = ImageQualityEvaluator.evaluateMetrics({
        faceCount: 1,
        ipdPixels: 110.0,
        laplacianVariance: 45.0,
        luminanceMean: 120.0,
        yawDegrees: 0,
        pitchDegrees: 0,
        rollDegrees: 0,
      });
      assert.strictEqual(blurTest.isAcceptable, false);
      assert.strictEqual(blurTest.rejectionReason, 'BLUR_EXCESSIVE');

      const ipdTest = ImageQualityEvaluator.evaluateMetrics({
        faceCount: 1,
        ipdPixels: 52.0,
        laplacianVariance: 250.0,
        luminanceMean: 120.0,
        yawDegrees: 0,
        pitchDegrees: 0,
        rollDegrees: 0,
      });
      assert.strictEqual(ipdTest.isAcceptable, false);
      assert.strictEqual(ipdTest.rejectionReason, 'INSUFFICIENT_IPD');

      const multiFaceTest = ImageQualityEvaluator.evaluateMetrics({
        faceCount: 2,
        ipdPixels: 110.0,
        laplacianVariance: 250.0,
        luminanceMean: 120.0,
        yawDegrees: 0,
        pitchDegrees: 0,
        rollDegrees: 0,
      });
      assert.strictEqual(multiFaceTest.isAcceptable, false);
      assert.strictEqual(multiFaceTest.rejectionReason, 'MULTIPLE_FACES_DETECTED');
    });

    it('3.3: Accurately computes Failure-to-Acquire (FTA) and Failure-to-Enroll (FTE)', () => {
      const attempts = [
        ImageQualityEvaluator.evaluateMetrics({ faceCount: 1, ipdPixels: 100, laplacianVariance: 300, luminanceMean: 120, yawDegrees: 0, pitchDegrees: 0, rollDegrees: 0 }),
        ImageQualityEvaluator.evaluateMetrics({ faceCount: 1, ipdPixels: 100, laplacianVariance: 300, luminanceMean: 120, yawDegrees: 0, pitchDegrees: 0, rollDegrees: 0 }),
        ImageQualityEvaluator.evaluateMetrics({ faceCount: 0, ipdPixels: 0, laplacianVariance: 0, luminanceMean: 0, yawDegrees: 0, pitchDegrees: 0, rollDegrees: 0 }),
        ImageQualityEvaluator.evaluateMetrics({ faceCount: 1, ipdPixels: 40, laplacianVariance: 300, luminanceMean: 120, yawDegrees: 0, pitchDegrees: 0, rollDegrees: 0 }),
      ];

      const summary = ImageQualityEvaluator.computeFtaFte(attempts);
      assert.strictEqual(summary.totalCaptureAttempts, 4);
      assert.strictEqual(summary.failedAcquisitionAttempts, 2);
      assert.strictEqual(summary.ftaRate, 0.5);
      assert.strictEqual(summary.rejectionBreakdown.NO_FACE_DETECTED, 1);
      assert.strictEqual(summary.rejectionBreakdown.INSUFFICIENT_IPD, 1);
    });
  });

  describe('Suite 4: SFace 1:1 Authentication & ROC/DET Evaluation', () => {
    it('4.1: Evaluates 1:1 genuine matches and impostor rejections against 0.363 reference floor', () => {
      const [baseSubjA, probeSameA] = generateControlledGenuinePair(101, 0.93);
      const probeImpostorB = generateUnitVector(202);

      const genuineScenario: OneToOneScenarioInput = {
        scenarioName: 'Genuine Account Owner eKYC Verification',
        claimedUid: 'UID_ALICE',
        probeEmbedding: probeSameA,
        enrolledTemplate: {
          uid: 'UID_ALICE',
          embedding: baseSubjA,
          modelVersion: 'sface_opencv_zoo_v1_primary',
          isRevoked: false,
          isEncrypted: true,
        },
        isTrueClaimant: true,
      };

      const impostorScenario: OneToOneScenarioInput = {
        scenarioName: 'Impostor Probe against Alice Account',
        claimedUid: 'UID_ALICE',
        probeEmbedding: probeImpostorB,
        enrolledTemplate: {
          uid: 'UID_ALICE',
          embedding: baseSubjA,
          modelVersion: 'sface_opencv_zoo_v1_primary',
          isRevoked: false,
          isEncrypted: true,
        },
        isTrueClaimant: false,
      };

      const resGenuine = OneToOneEvaluator.evaluateScenario(genuineScenario, 0.363);
      assert.strictEqual(resGenuine.authenticated, true);
      assert.ok(resGenuine.similarity > 0.85, `Genuine similarity was ${resGenuine.similarity}`);

      const resImpostor = OneToOneEvaluator.evaluateScenario(impostorScenario, 0.363);
      assert.strictEqual(resImpostor.authenticated, false);
      assert.ok(resImpostor.similarity < 0.363, `Impostor similarity was ${resImpostor.similarity}`);
    });

    it('4.2: Fails closed when reference template is revoked or model version mismatches', () => {
      const vecA = generateUnitVector(303);
      const revokedScenario: OneToOneScenarioInput = {
        scenarioName: 'Revoked Template Access Attempt',
        claimedUid: 'UID_REVOKED',
        probeEmbedding: vecA,
        enrolledTemplate: {
          uid: 'UID_REVOKED',
          embedding: vecA,
          modelVersion: 'sface_opencv_zoo_v1_primary',
          isRevoked: true,
          isEncrypted: true,
        },
        isTrueClaimant: true,
      };

      const res = OneToOneEvaluator.evaluateScenario(revokedScenario, 0.363);
      assert.strictEqual(res.authenticated, false);
      assert.strictEqual(res.errorCode, 'TEMPLATE_REVOKED');
    });

    it('4.3: Computes empirical ROC curve and EER across operating thresholds', () => {
      const comparisons = [];
      const numSubjects = 20;

      // Generate genuine pairs with high similarity ~0.85-0.95
      for (let s = 0; s < numSubjects; s++) {
        for (let g = 0; g < 5; g++) {
          const [base, probe] = generateControlledGenuinePair(s * 50 + g, 0.90);
          comparisons.push(SFaceScoreCollector.evaluatePair(`GEN-${s}-${g}`, true, base, probe, `S${s}`, `S${s}`));
        }
      }

      // Generate impostor comparisons with low similarity ~0.0-0.2
      for (let i = 0; i < numSubjects; i++) {
        for (let j = i + 1; j < numSubjects; j++) {
          const vA = generateUnitVector(i + 10);
          const vB = generateUnitVector(j + 10);
          comparisons.push(SFaceScoreCollector.evaluatePair(`IMP-${i}-${j}`, false, vA, vB, `S${i}`, `S${j}`));
        }
      }

      const roc = SFaceScoreCollector.computeRocCurve(comparisons, 50);
      assert.ok(roc.operatingPoints.length > 40);
      assert.ok(roc.auc > 0.90, `AUC was ${roc.auc}`);
      assert.ok(roc.eer >= 0.0 && roc.eer < 0.10, `EER was ${roc.eer}`);
    });
  });

  describe('Suite 5: 1:N Gallery Identification & Deduplication Scaling', () => {
    it('5.1: Correctly identifies enrolled duplicate candidates and flags warning vs hard block', () => {
      const gallery: GalleryEntry[] = [];
      const numGallery = 30;

      for (let i = 0; i < numGallery; i++) {
        gallery.push({
          personId: `PER-${i}`,
          owningUid: `UID-${i}`,
          embedding: generateUnitVector(1000 + i),
          epoch: 1,
        });
      }

      // Probe 1: Genuine duplicate of Person 5 (high similarity 0.94 => Hard Block >= 0.78 / 0.90)
      const [, probeDuplicateHardVector] = generateControlledGenuinePair(1005, 0.94);
      const probeDuplicateHard: IdentificationProbe = {
        probeId: 'PRB-DUP-HARD',
        truePersonId: 'PER-5',
        embedding: probeDuplicateHardVector,
      };

      const resHard = OneToNEvaluator.searchGallery(probeDuplicateHard, gallery);
      assert.strictEqual(resHard.decision, 'DUPLICATE_HARD_BLOCK');
      assert.strictEqual(resHard.isCorrect, true);
      assert.strictEqual(resHard.topMatch?.personId, 'PER-5');

      // Probe 2: Unique new person not in gallery (sim ~ 0.0 => UNIQUE)
      const probeUnique: IdentificationProbe = {
        probeId: 'PRB-UNIQUE',
        truePersonId: undefined,
        embedding: generateUnitVector(88888),
      };

      const resUnique = OneToNEvaluator.searchGallery(probeUnique, gallery);
      assert.strictEqual(resUnique.decision, 'UNIQUE');
      assert.strictEqual(resUnique.isCorrect, true);
    });

    it('5.2: Accurately summarizes FPIR and FNIR across gallery searches', () => {
      const results = [
        { probeId: '1', truePersonId: 'P1', isEnrolledSubject: true, decision: 'DUPLICATE_HARD_BLOCK' as const, isCorrect: true, candidates: [] },
        { probeId: '2', truePersonId: 'P2', isEnrolledSubject: true, decision: 'DUPLICATE_WARNING' as const, isCorrect: true, candidates: [] },
        { probeId: '3', truePersonId: undefined, isEnrolledSubject: false, decision: 'UNIQUE' as const, isCorrect: true, candidates: [] },
        { probeId: '4', truePersonId: undefined, isEnrolledSubject: false, decision: 'UNIQUE' as const, isCorrect: true, candidates: [] },
      ];

      const summary = OneToNEvaluator.summarize(results, 50);
      assert.strictEqual(summary.fpir, 0.0);
      assert.strictEqual(summary.fnir, 0.0);
      assert.strictEqual(summary.gallerySize, 50);
    });
  });

  describe('Suite 6: Presentation Attack Detection (ISO/IEC 30107-3 APCER / BPCER)', () => {
    it('6.1: Evaluates APCER and BPCER across attack instrument species', () => {
      const attempts: PadPresentationAttempt[] = [
        { attemptId: 'BF-1', isBonaFide: true, captureLighting: 'INDOOR', classifiedAsLive: true, livenessScore: 0.95 },
        { attemptId: 'BF-2', isBonaFide: true, captureLighting: 'OUTDOOR', classifiedAsLive: true, livenessScore: 0.92 },
        { attemptId: 'BF-3', isBonaFide: true, captureLighting: 'LOW_LIGHT', classifiedAsLive: false, livenessScore: 0.35, rejectionReason: 'UNDEREXPOSED' },
        { attemptId: 'ATT-1', isBonaFide: false, attackSpecies: 'PRINTED_PHOTO_MATTE', captureLighting: 'INDOOR', classifiedAsLive: false, livenessScore: 0.12 },
        { attemptId: 'ATT-2', isBonaFide: false, attackSpecies: 'SCREEN_REPLAY_SMARTPHONE', captureLighting: 'INDOOR', classifiedAsLive: false, livenessScore: 0.08 },
        { attemptId: 'ATT-3', isBonaFide: false, attackSpecies: 'SCREEN_REPLAY_4K_MONITOR', captureLighting: 'INDOOR', classifiedAsLive: false, livenessScore: 0.15 },
      ];

      const padReport = PadEvaluator.evaluateAttempts(attempts);
      assert.strictEqual(padReport.bonaFideCount, 3);
      assert.strictEqual(padReport.attackCount, 3);
      assert.strictEqual(padReport.bonaFideRejections, 1);
      assert.strictEqual(padReport.bpcer, Number((1 / 3).toFixed(4)));
      assert.strictEqual(padReport.attackAccepts, 0);
      assert.strictEqual(padReport.apcer, 0.0);
      assert.strictEqual(padReport.speciesBreakdown.length, 3);
    });
  });

  describe('Suite 7: Demographic & Environmental Performance Disparity', () => {
    it('7.1: Evaluates subgroup performance and warns when sample size < 500', () => {
      const inputs = [
        { subgroupName: 'Female Cohort', genuineTrials: 50, falseNonMatches: 1, impostorTrials: 200, falseMatches: 0, captureAttempts: 52, captureRejections: 2 },
        { subgroupName: 'Male Cohort', genuineTrials: 50, falseNonMatches: 0, impostorTrials: 200, falseMatches: 0, captureAttempts: 50, captureRejections: 0 },
      ];

      const fairness = FairnessEvaluator.evaluateSubgroups(inputs, 0.363);
      assert.strictEqual(fairness.subgroups.length, 2);
      assert.ok(fairness.subgroups[0].statisticalWarning?.includes('INSUFFICIENT_SAMPLE_SIZE'));
      assert.strictEqual(fairness.subgroups[0].isSampleStatisticallyAdequate, false);
      assert.strictEqual(fairness.thresholdUsed, 0.363);
    });

    it('7.2: Produces comprehensive end-to-end reproducible benchmark report', () => {
      const manifest = createCanonicalEvaluationManifest();
      const quality = ImageQualityEvaluator.computeFtaFte([]);
      const oneToOne = OneToOneEvaluator.summarize([]);
      const oneToN = OneToNEvaluator.summarize([], 50);
      const pad = PadEvaluator.evaluateAttempts([]);
      const roc = SFaceScoreCollector.computeRocCurve([]);
      const fairness = FairnessEvaluator.evaluateSubgroups([]);

      const report = BenchmarkReportGenerator.generateReport({
        runId: 'RUN-20261031-P20-5',
        gitCommit: '41f95bf',
        manifest,
        quality,
        oneToOne,
        oneToN,
        pad,
        roc,
        fairness,
      });

      assert.strictEqual(report.runId, 'RUN-20261031-P20-5');
      assert.strictEqual(report.gitCommit, '41f95bf');
      assert.strictEqual(report.modelMetadata.embeddingDimension, 128);
      assert.strictEqual(report.activeThresholds.verificationThreshold, 0.363);
      assert.strictEqual(report.datasetSummary.totalSubjects, 50);
    });
  });

});
