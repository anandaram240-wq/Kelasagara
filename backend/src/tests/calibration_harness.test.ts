// File: backend/src/tests/calibration_harness.test.ts
// KELASAGARA V18 — Gate G-01 Dual-Subspace Calibration & De-Identified Manifest Validator Tests

import * as crypto from 'node:crypto';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';

import {
  BiometricSampleRecord,
  CANONICAL_SFACE_THRESHOLDS,
  CalibrationDatasetManifestV18,
  DEPLOYMENT_GATE_MODE,
  LANDMARK_V3_FULL_DIMENSION,
  LANDMARK_V3_PERI_DIMENSION,
  MANIFEST_SCHEMA_ID,
  MANIFEST_SCHEMA_VERSION,
  PRODUCTION_BIOMETRIC_CALIBRATION_APPROVED,
  SFACE_DIMENSION,
  computeExactCosine,
  computeWilsonScoreInterval95,
  createDeterministicPrng,
  runCalibrationCliWithManifestValidation,
  runV18DualSubspaceCalibrationSuite,
  validateAndLoadCalibrationManifest,
  validateAndNormalizeEmbedding,
  verifyPartitionDisjointness,
} from '../scripts/calibration_harness';

function makeUnitVec(dim: number, seed: number): Float32Array {
  const rng = createDeterministicPrng(seed);
  const out = new Float32Array(dim);
  let normSq = 0.0;
  for (let i = 0; i < dim; i++) {
    const v = rng() * 2.0 - 1.0;
    out[i] = v;
    normSq += v * v;
  }
  const inv = 1.0 / Math.sqrt(normSq);
  for (let i = 0; i < dim; i++) {
    out[i] *= inv;
  }
  return out;
}

function perturbVec(
  base: Float32Array,
  targetCos: number,
  seed: number,
): Float32Array {
  const noise = makeUnitVec(base.length, seed);
  let dot = 0.0;
  for (let i = 0; i < base.length; i++) dot += base[i] * noise[i];

  const ortho = new Float32Array(base.length);
  let orthoNormSq = 0.0;
  for (let i = 0; i < base.length; i++) {
    ortho[i] = noise[i] - dot * base[i];
    orthoNormSq += ortho[i] * ortho[i];
  }
  const invOrtho = 1.0 / Math.sqrt(orthoNormSq);
  const sinTheta = Math.sqrt(Math.max(0.0, 1.0 - targetCos * targetCos));

  const res = new Float32Array(base.length);
  for (let i = 0; i < base.length; i++) {
    res[i] = targetCos * base[i] + sinTheta * ortho[i] * invOrtho;
  }
  return validateAndNormalizeEmbedding(res, base.length, 'perturbed');
}

function buildDisjointTestDataset(): BiometricSampleRecord[] {
  const records: BiometricSampleRecord[] = [];
  const splits: Array<{
    partition: 'CALIBRATION' | 'VALIDATION' | 'HELD_OUT_EVAL';
    subjectOffset: number;
    subjectCount: number;
  }> = [
    { partition: 'CALIBRATION', subjectOffset: 100, subjectCount: 6 },
    { partition: 'VALIDATION', subjectOffset: 200, subjectCount: 6 },
    { partition: 'HELD_OUT_EVAL', subjectOffset: 300, subjectCount: 8 },
  ];

  for (const split of splits) {
    for (let s = 0; s < split.subjectCount; s++) {
      const subjId = `SUBJ_${split.subjectOffset + s}`;
      const baseSface = makeUnitVec(
        SFACE_DIMENSION,
        (split.subjectOffset + s) * 13,
      );
      const baseFull = makeUnitVec(
        LANDMARK_V3_FULL_DIMENSION,
        (split.subjectOffset + s) * 29,
      );
      const basePeri = makeUnitVec(
        LANDMARK_V3_PERI_DIMENSION,
        (split.subjectOffset + s) * 47,
      );

      for (let capture = 1; capture <= 2; capture++) {
        const sface =
          capture === 1
            ? baseSface
            : perturbVec(
                baseSface,
                0.86,
                (split.subjectOffset + s) * 100 + capture,
              );
        const full =
          capture === 1
            ? baseFull
            : perturbVec(
                baseFull,
                0.82,
                (split.subjectOffset + s) * 200 + capture,
              );
        const peri =
          capture === 1
            ? basePeri
            : perturbVec(
                basePeri,
                0.88,
                (split.subjectOffset + s) * 300 + capture,
              );

        records.push({
          sampleId: `${subjId}_SAMP_${capture}`,
          subjectId: subjId,
          sessionId: `${subjId}_SESS_${capture}`,
          partition: split.partition,
          isSyntheticData: true,
          sfaceEmbedding128: sface,
          landmarkFull512: full,
          landmarkPeri256: peri,
          occlusionRatio: capture === 2 ? 0.35 : 0.05,
          isoQualityScore: 88.0,
        });
      }
    }
  }
  return records;
}

/**
 * Creates a valid binary PNG payload (>= 256 bytes) with deterministic seed content and returns its SHA-256 hex.
 */
function writeSyntheticPngFile(filePath: string, seed: number): string {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  const pngHeader = Buffer.from([
    0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
  ]);
  const body = Buffer.alloc(256);
  const rng = createDeterministicPrng(seed);
  for (let i = 0; i < body.length; i++) {
    body[i] = Math.floor(rng() * 256);
  }
  const fullBuf = Buffer.concat([pngHeader, body]);
  fs.writeFileSync(filePath, fullBuf);
  return crypto.createHash('sha256').update(fullBuf).digest('hex');
}

describe('Part A: V18 Dual-Subspace ROC/DET Calibration Math Suite', () => {
  it('1. Rejects invalid or incompatible feature dimensions', () => {
    const wrongDimSface = new Float32Array(64).fill(0.1);
    assert.throws(
      () =>
        validateAndNormalizeEmbedding(
          wrongDimSface,
          SFACE_DIMENSION,
          'SFaceTest',
        ),
      /Dimension mismatch for SFaceTest: expected 128, got 64/,
    );

    const vec128 = makeUnitVec(128, 1);
    const vec512 = makeUnitVec(512, 2);
    assert.throws(
      () => computeExactCosine(vec128, vec512),
      /Incompatible vector dimensions in cosine: 128 vs 512/,
    );
  });

  it('2. Rejects non-finite (NaN / Infinity) embeddings and zero-norm vectors', () => {
    const nanVec = new Float32Array(SFACE_DIMENSION).fill(0.1);
    nanVec[17] = Number.NaN;
    assert.throws(
      () => validateAndNormalizeEmbedding(nanVec, SFACE_DIMENSION, 'NaNVec'),
      /Non-finite value at index 17/,
    );

    const infVec = new Float32Array(SFACE_DIMENSION).fill(0.1);
    infVec[0] = Number.POSITIVE_INFINITY;
    assert.throws(
      () => validateAndNormalizeEmbedding(infVec, SFACE_DIMENSION, 'InfVec'),
      /Non-finite value at index 0/,
    );

    const zeroVec = new Float32Array(SFACE_DIMENSION).fill(0.0);
    assert.throws(
      () => validateAndNormalizeEmbedding(zeroVec, SFACE_DIMENSION, 'ZeroVec'),
      /Zero-norm degenerate vector/,
    );
  });

  it('3. Rejects empty datasets and single-sample partitions', () => {
    assert.throws(
      () => verifyPartitionDisjointness([]),
      /Calibration dataset is empty/,
    );

    assert.throws(
      () => runV18DualSubspaceCalibrationSuite([]),
      /Calibration dataset is empty/,
    );
  });

  it('4. Detects and blocks subject leakage and session leakage across partitions', () => {
    const dataset = buildDisjointTestDataset();
    const leakedSubjectDataset: BiometricSampleRecord[] = [
      ...dataset,
      {
        ...dataset[0],
        sampleId: 'LEAKED_SAMPLE_999',
        subjectId: 'SUBJ_100',
        sessionId: 'UNIQUE_SESSION_999',
        partition: 'HELD_OUT_EVAL',
      },
    ];

    assert.throws(
      () => verifyPartitionDisjointness(leakedSubjectDataset),
      /Subject leakage detected: subjectId 'SUBJ_100' appears in both CALIBRATION and HELD_OUT_EVAL/,
    );

    const leakedSessionDataset: BiometricSampleRecord[] = [
      ...dataset,
      {
        ...dataset[0],
        sampleId: 'LEAKED_SAMPLE_998',
        subjectId: 'UNIQUE_SUBJECT_998',
        sessionId: dataset[0].sessionId,
        partition: 'VALIDATION',
      },
    ];

    assert.throws(
      () => verifyPartitionDisjointness(leakedSessionDataset),
      /Session leakage detected/,
    );
  });

  it('5. Computes separate SFace (Track A), Landmark V3 (Track B), and Calibrated Fusion (Track C) metrics', () => {
    const dataset = buildDisjointTestDataset();
    const report = runV18DualSubspaceCalibrationSuite(dataset, {
      bootstrapIterations: 50,
      randomSeed: 42,
    });

    assert.equal(report.productionBiometricCalibrationApproved, false);
    assert.equal(report.deploymentGateMode, 'CONTROLLED_TEST_BUILD_ONLY');
    assert.equal(PRODUCTION_BIOMETRIC_CALIBRATION_APPROVED, false);
    assert.equal(DEPLOYMENT_GATE_MODE, 'CONTROLLED_TEST_BUILD_ONLY');

    assert.equal(report.tracks.trackA_SFace.enabled, true);
    assert.equal(report.tracks.trackB_LandmarkV3.enabled, true);
    assert.equal(report.tracks.trackC_DualFusion.enabled, true);

    assert.deepEqual(report.tracks.trackA_SFace.selectedThresholds, {
      ...CANONICAL_SFACE_THRESHOLDS,
      monotonicValid: true,
    });

    assert.notEqual(
      report.tracks.trackB_LandmarkV3.selectedThresholds?.verify1to1,
      CANONICAL_SFACE_THRESHOLDS.verify1to1,
    );

    assert.ok(report.tracks.trackC_DualFusion.fusionParameters);
    assert.equal(
      report.tracks.trackC_DualFusion.fusionParameters.fittedOnGenuinePairs,
      6,
    );
  });

  it('6. Gracefully disables Track B and Track C when secondary landmark vectors are absent', () => {
    const sfaceOnlyDataset = buildDisjointTestDataset().map((rec) => ({
      ...rec,
      landmarkFull512: undefined,
      landmarkPeri256: undefined,
    }));

    const report = runV18DualSubspaceCalibrationSuite(sfaceOnlyDataset, {
      bootstrapIterations: 30,
    });

    assert.equal(report.tracks.trackA_SFace.enabled, true);
    assert.equal(report.tracks.trackB_LandmarkV3.enabled, false);
    assert.equal(report.tracks.trackC_DualFusion.enabled, false);
    assert.ok(
      report.tracks.trackC_DualFusion.disabledReason?.includes(
        'dual-modality samples',
      ),
    );
  });

  it('7. Enforces threshold sweep monotonicity (verify1to1 < duplicateWarning < hardBlock)', () => {
    const dataset = buildDisjointTestDataset();
    const report = runV18DualSubspaceCalibrationSuite(dataset, {
      bootstrapIterations: 40,
    });

    for (const track of [
      report.tracks.trackA_SFace,
      report.tracks.trackB_LandmarkV3,
      report.tracks.trackC_DualFusion,
    ]) {
      assert.ok(track.selectedThresholds);
      assert.equal(track.selectedThresholds.monotonicValid, true);
      assert.ok(
        track.selectedThresholds.verify1to1 <
          track.selectedThresholds.duplicateWarning,
      );
      assert.ok(
        track.selectedThresholds.duplicateWarning <
          track.selectedThresholds.hardBlock,
      );
    }
  });

  it('8. Computes exact Wilson 95% confidence bounds at k=0 and k=n without underflow', () => {
    const zeroErrors = computeWilsonScoreInterval95(0, 500);
    assert.equal(zeroErrors.pointEstimate, 0.0);
    assert.equal(zeroErrors.lower95, 0.0);
    assert.ok(zeroErrors.upper95 > 0.007 && zeroErrors.upper95 < 0.008);

    const allErrors = computeWilsonScoreInterval95(500, 500);
    assert.equal(allErrors.pointEstimate, 1.0);
    assert.equal(allErrors.upper95, 1.0);
    assert.ok(allErrors.lower95 > 0.992);
  });

  it('9. Emits INSUFFICIENT_SAMPLE_SIZE warnings to prevent unsubstantiated 0.1% FMR claims', () => {
    const realFlaggedSmallDataset = buildDisjointTestDataset().map((rec) => ({
      ...rec,
      isSyntheticData: false,
    }));

    const report = runV18DualSubspaceCalibrationSuite(realFlaggedSmallDataset, {
      bootstrapIterations: 30,
    });

    assert.equal(
      report.overallValidationStatus,
      'INSUFFICIENT_SAMPLE_SIZE_FOR_0_1_PCT_FMR',
    );
    assert.ok(
      report.tracks.trackA_SFace.warnings.some((w) =>
        w.includes('INSUFFICIENT_SAMPLE_SIZE'),
      ),
    );
  });

  it('10. Guarantees bit-exact reproducible output artifacts from identical inputs and seed', () => {
    const dataset = buildDisjointTestDataset();
    const run1 = runV18DualSubspaceCalibrationSuite(dataset, {
      bootstrapIterations: 60,
      randomSeed: 20261023,
    });
    const run2 = runV18DualSubspaceCalibrationSuite(dataset, {
      bootstrapIterations: 60,
      randomSeed: 20261023,
    });

    assert.equal(JSON.stringify(run1), JSON.stringify(run2));
  });
});

describe('Part B: Gate G-01 De-Identified Dataset Manifest Validator Suite', () => {
  let tempRoot: string;
  let datasetRoot: string;
  let outsideRoot: string;

  beforeEach(() => {
    tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'kls-v18-manifest-test-'));
    datasetRoot = path.join(tempRoot, 'authorized_dataset');
    outsideRoot = path.join(tempRoot, 'outside_untrusted');
    fs.mkdirSync(datasetRoot, { recursive: true });
    fs.mkdirSync(outsideRoot, { recursive: true });
  });

  afterEach(() => {
    fs.rmSync(tempRoot, { recursive: true, force: true });
  });

  function createValidFixtureManifest(): CalibrationDatasetManifestV18 {
    const shaCal1 = writeSyntheticPngFile(
      path.join(datasetRoot, 'calibration/img_cal_01.png'),
      1,
    );
    const shaCal2 = writeSyntheticPngFile(
      path.join(datasetRoot, 'calibration/img_cal_02.png'),
      2,
    );
    const shaVal1 = writeSyntheticPngFile(
      path.join(datasetRoot, 'validation/img_val_01.png'),
      3,
    );
    const shaEval1 = writeSyntheticPngFile(
      path.join(datasetRoot, 'evaluation/img_eval_01.png'),
      4,
    );
    const shaEval2 = writeSyntheticPngFile(
      path.join(datasetRoot, 'evaluation/img_eval_02.png'),
      5,
    );

    return {
      schemaId: MANIFEST_SCHEMA_ID,
      schemaVersion: MANIFEST_SCHEMA_VERSION,
      provenance: {
        datasetId: 'KLS_BENCH_BLR_2026_Q4',
        collectionProtocolId: 'PROTO_ISO_19795_V18',
        lawfulUseReference: 'DPDPA_CONSENT_BATCH_REF_2026_10',
        ethicsApprovalId: 'IEC_KARNATAKA_2026_099',
        deIdentificationMethod: 'HMAC_SHA256_PSEUDONYMIZATION_V2',
        authorizedByRole: 'BIOMETRIC_SECURITY_LEAD',
        createdAtIso: '2026-10-23T09:00:00.000Z',
      },
      records: [
        {
          imageId: 'IMG_CAL_0001',
          subjectId: 'SUBJ_CAL001A',
          sessionId: 'SESS_CAL001S1',
          partition: 'calibration',
          relativePath: 'calibration/img_cal_01.png',
          sha256: shaCal1,
          captureMetadata: {
            poseYawDeg: -3.5,
            posePitchDeg: 1.2,
            poseRollDeg: 0.4,
            occlusionRatio: 0.05,
            isoQualityScore: 91.0,
            illuminationLux: 450,
          },
        },
        {
          imageId: 'IMG_CAL_0002',
          subjectId: 'SUBJ_CAL001A',
          sessionId: 'SESS_CAL001S2',
          partition: 'calibration',
          relativePath: 'calibration/img_cal_02.png',
          sha256: shaCal2,
        },
        {
          imageId: 'IMG_VAL_0001',
          subjectId: 'SUBJ_VAL002B',
          sessionId: 'SESS_VAL002S1',
          partition: 'validation',
          relativePath: 'validation/img_val_01.png',
          sha256: shaVal1,
        },
        {
          imageId: 'IMG_EVAL_0001',
          subjectId: 'SUBJ_EVL003C',
          sessionId: 'SESS_EVL003S1',
          partition: 'evaluation',
          relativePath: 'evaluation/img_eval_01.png',
          sha256: shaEval1,
        },
        {
          imageId: 'IMG_EVAL_0002',
          subjectId: 'SUBJ_EVL004D',
          sessionId: 'SESS_EVL004S1',
          partition: 'evaluation',
          relativePath: 'evaluation/img_eval_02.png',
          sha256: shaEval2,
        },
      ],
    };
  }

  it('11. Validates a compliant manifest and generates provenance & de-identification notices', () => {
    const manifest = createValidFixtureManifest();
    const res = validateAndLoadCalibrationManifest(
      JSON.stringify(manifest),
      datasetRoot,
    );

    assert.equal(res.integrityDigest.totalRecords, 5);
    assert.equal(res.integrityDigest.partitionImageCounts.calibration, 2);
    assert.equal(res.integrityDigest.partitionImageCounts.validation, 1);
    assert.equal(res.integrityDigest.partitionImageCounts.evaluation, 2);
    assert.equal(
      res.integrityDigest.provenanceNote,
      'RECORDED_PROVENANCE_REFERENCE_ONLY_NOT_LEGAL_PROOF',
    );
    assert.equal(
      res.integrityDigest.deIdentificationNote,
      'PSEUDONYMOUS_BIOMETRIC_DATA_REMAINS_PERSONAL_DATA_UNDER_DPDPA',
    );
    assert.equal(res.integrityDigest.masterIntegritySha256.length, 64);
  });

  it('12. Rejects duplicate image IDs', () => {
    const manifest = createValidFixtureManifest();
    const dupManifest = {
      ...manifest,
      records: [
        ...manifest.records,
        {
          ...manifest.records[0],
          relativePath: 'calibration/img_cal_02.png',
        },
      ],
    };

    assert.throws(
      () => validateAndLoadCalibrationManifest(dupManifest, datasetRoot),
      /DUPLICATE_IMAGE_ID: Duplicate imageId "IMG_CAL_0001"/,
    );
  });

  it('13. Rejects subject leakage across calibration, validation, and evaluation partitions', () => {
    const manifest = createValidFixtureManifest();
    const leaked = {
      ...manifest,
      records: manifest.records.map((r, idx) =>
        idx === 3 ? { ...r, subjectId: 'SUBJ_CAL001A' } : r,
      ),
    };

    assert.throws(
      () => validateAndLoadCalibrationManifest(leaked, datasetRoot),
      /SUBJECT_PARTITION_LEAKAGE: subjectId "SUBJ_CAL001A" appears in both "calibration" and "evaluation"/,
    );
  });

  it('14. Rejects duplicate image paths and contradictory session-to-subject records', () => {
    const manifest = createValidFixtureManifest();
    const dupPathManifest = {
      ...manifest,
      records: manifest.records.map((r, idx) =>
        idx === 1 ? { ...r, relativePath: 'calibration/img_cal_01.png' } : r,
      ),
    };

    assert.throws(
      () => validateAndLoadCalibrationManifest(dupPathManifest, datasetRoot),
      /DUPLICATE_IMAGE_PATH/,
    );

    const contradictorySessionManifest = {
      ...manifest,
      records: manifest.records.map((r, idx) =>
        idx === 4 ? { ...r, sessionId: 'SESS_EVL003S1' } : r,
      ),
    };

    assert.throws(
      () =>
        validateAndLoadCalibrationManifest(
          contradictorySessionManifest,
          datasetRoot,
        ),
      /CONTRADICTORY_SESSION_SUBJECT/,
    );
  });

  it('15. Rejects missing image files on disk', () => {
    const manifest = createValidFixtureManifest();
    fs.unlinkSync(path.join(datasetRoot, 'evaluation/img_eval_02.png'));

    assert.throws(
      () => validateAndLoadCalibrationManifest(manifest, datasetRoot),
      /IMAGE_FILE_MISSING/,
    );
  });

  it('16. Rejects invalid image extensions, corrupted magic headers, and out-of-bounds sizes', () => {
    const manifest = createValidFixtureManifest();

    // Case A: Unsupported extension (.bmp)
    const bmpPath = path.join(datasetRoot, 'calibration/bad_format.bmp');
    writeSyntheticPngFile(bmpPath, 99);
    const badExtManifest = {
      ...manifest,
      records: manifest.records.map((r, idx) =>
        idx === 0 ? { ...r, relativePath: 'calibration/bad_format.bmp' } : r,
      ),
    };
    assert.throws(
      () => validateAndLoadCalibrationManifest(badExtManifest, datasetRoot),
      /INVALID_IMAGE_FORMAT/,
    );

    // Case B: .png extension containing plain text instead of PNG magic bytes
    const fakePngPath = path.join(datasetRoot, 'calibration/fake_image.png');
    fs.writeFileSync(fakePngPath, Buffer.alloc(300, 0x41));
    const badMagicManifest = {
      ...manifest,
      records: manifest.records.map((r, idx) =>
        idx === 0 ? { ...r, relativePath: 'calibration/fake_image.png' } : r,
      ),
    };
    assert.throws(
      () => validateAndLoadCalibrationManifest(badMagicManifest, datasetRoot),
      /INVALID_IMAGE_MAGIC_BYTES/,
    );

    // Case C: Undersized 10-byte file
    const tinyPath = path.join(datasetRoot, 'calibration/tiny.png');
    fs.writeFileSync(tinyPath, Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]));
    const tinyManifest = {
      ...manifest,
      records: manifest.records.map((r, idx) =>
        idx === 0 ? { ...r, relativePath: 'calibration/tiny.png' } : r,
      ),
    };
    assert.throws(
      () => validateAndLoadCalibrationManifest(tinyManifest, datasetRoot),
      /IMAGE_SIZE_OUT_OF_BOUNDS/,
    );
  });

  it('17. Rejects relative paths containing .. or ... traversal segments', () => {
    const manifest = createValidFixtureManifest();
    for (const badRel of [
      '../outside_untrusted/secret.png',
      'calibration/../../escape.png',
      'calibration/.../hidden.png',
    ]) {
      const traversalManifest = {
        ...manifest,
        records: manifest.records.map((r, idx) =>
          idx === 0 ? { ...r, relativePath: badRel } : r,
        ),
      };
      assert.throws(
        () =>
          validateAndLoadCalibrationManifest(traversalManifest, datasetRoot),
        /PATH_TRAVERSAL_REJECTED/,
      );
    }
  });

  it('18. Rejects absolute paths and symbolic-link escapes outside datasetRoot', () => {
    const manifest = createValidFixtureManifest();
    const absPath = path.join(datasetRoot, 'calibration/img_cal_01.png');

    const absManifest = {
      ...manifest,
      records: manifest.records.map((r, idx) =>
        idx === 0 ? { ...r, relativePath: absPath } : r,
      ),
    };
    assert.throws(
      () => validateAndLoadCalibrationManifest(absManifest, datasetRoot),
      /PATH_TRAVERSAL_REJECTED: Absolute path is forbidden/,
    );

    // Create a file outside datasetRoot and a symlink inside datasetRoot pointing to it
    const outsideTarget = path.join(outsideRoot, 'escaped.png');
    writeSyntheticPngFile(outsideTarget, 777);
    const symlinkInside = path.join(datasetRoot, 'calibration/symlink_escape.png');
    fs.symlinkSync(outsideTarget, symlinkInside);

    const symlinkManifest = {
      ...manifest,
      records: manifest.records.map((r, idx) =>
        idx === 0
          ? { ...r, relativePath: 'calibration/symlink_escape.png' }
          : r,
      ),
    };
    assert.throws(
      () => validateAndLoadCalibrationManifest(symlinkManifest, datasetRoot),
      /SYMLINK_ESCAPE_REJECTED/,
    );
  });

  it('19. Rejects forbidden personal-information keys at every nesting level without echoing values', () => {
    const manifest = createValidFixtureManifest();
    const secretSentinel = 'SENSITIVE_SECRET_VALUE_DO_NOT_ECHO';

    // Level 1: Top-level forbidden key
    const topLevelPii = { ...manifest, fullName: secretSentinel };
    assert.throws(
      () => validateAndLoadCalibrationManifest(topLevelPii, datasetRoot),
      (err: Error) =>
        err.message.includes('PROHIBITED_PII_KEY') &&
        err.message.includes('fullName') &&
        !err.message.includes(secretSentinel),
    );

    // Level 2: Inside provenance
    const provPii = {
      ...manifest,
      provenance: { ...manifest.provenance, emailAddress: secretSentinel },
    };
    assert.throws(
      () => validateAndLoadCalibrationManifest(provPii, datasetRoot),
      (err: Error) =>
        err.message.includes('PROHIBITED_PII_KEY') &&
        err.message.includes('emailAddress') &&
        !err.message.includes(secretSentinel),
    );

    // Level 3: Inside record
    const recordPii = {
      ...manifest,
      records: manifest.records.map((r, idx) =>
        idx === 0 ? { ...r, firebaseUid: secretSentinel } : r,
      ),
    };
    assert.throws(
      () => validateAndLoadCalibrationManifest(recordPii, datasetRoot),
      (err: Error) =>
        err.message.includes('PROHIBITED_PII_KEY') &&
        err.message.includes('firebaseUid') &&
        !err.message.includes(secretSentinel),
    );

    // Level 4: Deeply nested inside captureMetadata
    const nestedPii = {
      ...manifest,
      records: manifest.records.map((r, idx) =>
        idx === 0
          ? {
              ...r,
              captureMetadata: {
                ...r.captureMetadata,
                nestedAudit: { phoneNumber: secretSentinel },
              },
            }
          : r,
      ),
    };
    assert.throws(
      () => validateAndLoadCalibrationManifest(nestedPii, datasetRoot),
      (err: Error) =>
        err.message.includes('PROHIBITED_PII_KEY') &&
        err.message.includes('phoneNumber') &&
        !err.message.includes(secretSentinel),
    );
  });

  it('20. Rejects invalid partition names, unknown fields, and contradictory metadata ranges', () => {
    const manifest = createValidFixtureManifest();

    const badPartition = {
      ...manifest,
      records: manifest.records.map((r, idx) =>
        idx === 0
          ? ({ ...r, partition: 'training_split' } as unknown as typeof r)
          : r,
      ),
    };
    assert.throws(
      () => validateAndLoadCalibrationManifest(badPartition, datasetRoot),
      /INVALID_PARTITION/,
    );

    const unknownField = {
      ...manifest,
      records: manifest.records.map((r, idx) =>
        idx === 0 ? { ...r, arbitraryExtraColumn: 123 } : r,
      ),
    };
    assert.throws(
      () => validateAndLoadCalibrationManifest(unknownField, datasetRoot),
      /DISALLOWED_MANIFEST_FIELD/,
    );

    const contradictoryOcclusion = {
      ...manifest,
      records: manifest.records.map((r, idx) =>
        idx === 0
          ? { ...r, captureMetadata: { occlusionRatio: 1.45 } }
          : r,
      ),
    };
    assert.throws(
      () =>
        validateAndLoadCalibrationManifest(contradictoryOcclusion, datasetRoot),
      /CONTRADICTORY_METADATA/,
    );
  });

  it('21. Rejects image SHA-256 hash mismatch when an image file is modified on disk', () => {
    const manifest = createValidFixtureManifest();
    // Tamper with calibration/img_cal_01.png after manifest creation
    writeSyntheticPngFile(
      path.join(datasetRoot, 'calibration/img_cal_01.png'),
      99999,
    );

    assert.throws(
      () => validateAndLoadCalibrationManifest(manifest, datasetRoot),
      /IMAGE_SHA256_MISMATCH/,
    );
  });

  it('22. Rejects empty records array and malformed JSON strings', () => {
    const manifest = createValidFixtureManifest();
    assert.throws(
      () =>
        validateAndLoadCalibrationManifest(
          { ...manifest, records: [] },
          datasetRoot,
        ),
      /EMPTY_MANIFEST_RECORDS/,
    );

    assert.throws(
      () => validateAndLoadCalibrationManifest('{bad json', datasetRoot),
      /MALFORMED_MANIFEST_JSON/,
    );
  });

  it('23. Produces bit-exact reproducible integrity digests and blocks CLI inference on invalid manifests', async () => {
    const manifest = createValidFixtureManifest();
    const res1 = validateAndLoadCalibrationManifest(manifest, datasetRoot);

    // Reverse record order: deterministic Merkle & Master digest must remain identical
    const reversedManifest = {
      ...manifest,
      records: [...manifest.records].reverse(),
    };
    const res2 = validateAndLoadCalibrationManifest(
      reversedManifest,
      datasetRoot,
    );

    assert.equal(
      res1.integrityDigest.masterIntegritySha256,
      res2.integrityDigest.masterIntegritySha256,
    );
    assert.equal(
      JSON.stringify(res1.integrityDigest),
      JSON.stringify(res2.integrityDigest),
    );

    // Verify CLI gate blocks before calling extractEmbeddingsForRecord when manifest is invalid
    const invalidManifestFile = path.join(tempRoot, 'invalid_manifest.json');
    fs.writeFileSync(
      invalidManifestFile,
      JSON.stringify({ ...manifest, records: [] }),
      'utf8',
    );

    let inferenceCalled = false;
    await assert.rejects(
      async () =>
        runCalibrationCliWithManifestValidation({
          manifestFilePath: invalidManifestFile,
          datasetRoot,
          extractEmbeddingsForRecord: async () => {
            inferenceCalled = true;
            return { isSyntheticData: true };
          },
        }),
      /EMPTY_MANIFEST_RECORDS/,
    );
    assert.equal(
      inferenceCalled,
      false,
      'Model inference must never run on an invalid manifest',
    );
  });
});
