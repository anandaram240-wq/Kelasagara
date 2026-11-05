// backend/src/tests/biometric_calibration_harness.test.ts
import { describe, it } from 'node:test';
import assert from 'node:assert';
import {
  BiometricCalibrationHarness,
  BiometricEvaluationHarness,
  wilsonInterval,
  SubjectEnrollment,
} from '../services/biometric_evaluation_harness';

describe('Biometric Calibration & Statistical Harness (Gate G-01)', () => {
  it('computes valid Wilson score confidence intervals for proportions', () => {
    // 0 out of 1000 false accepts
    const [low0, high0] = wilsonInterval(0, 1000);
    assert.strictEqual(low0, 0);
    assert.ok(high0 > 0 && high0 < 0.01, `Expected high0 in (0, 0.01), got ${high0}`);

    // 50 out of 100 (50%)
    const [low50, high50] = wilsonInterval(50, 100);
    assert.ok(low50 < 0.50 && low50 > 0.35);
    assert.ok(high50 > 0.50 && high50 < 0.65);

    // 100 out of 100 (100%)
    const [low100, high100] = wilsonInterval(100, 100);
    assert.ok(low100 > 0.95);
    assert.strictEqual(high100, 1.0);
  });

  it('evaluates 1:1 verification with subject-level cluster bootstrap', () => {
    // Create 10 synthetic subjects with 2 embeddings each
    const subjects: SubjectEnrollment[] = [];
    for (let s = 0; s < 10; s++) {
      const base = new Array(128).fill(0);
      base[s % 128] = 1.0; // orthogonal subjects
      // sample 1
      const emb1 = [...base];
      // sample 2 slightly perturbed
      const emb2 = [...base];
      emb2[(s + 1) % 128] = 0.05;
      const norm = Math.sqrt(emb2.reduce((acc, v) => acc + v * v, 0));
      const emb2Norm = emb2.map((v) => v / norm);

      subjects.push({
        subjectId: `subject_${s}`,
        embeddings: [emb1, emb2Norm],
      });
    }

    const result = BiometricEvaluationHarness.evaluateOneToOne(subjects, 0.50, 50);

    assert.strictEqual(result.threshold, 0.50);
    assert.strictEqual(result.tar.pointEstimate, 1.0); // High similarity within subjects
    assert.strictEqual(result.far.pointEstimate, 0.0); // Orthogonal across subjects
    assert.ok(result.bootstrapReplications === 50);
    assert.ok(result.tar.ciLower95 <= result.tar.pointEstimate);
  });

  it('calibrates threshold from score distributions', () => {
    const genuine = [0.85, 0.88, 0.92, 0.79, 0.81, 0.76, 0.95];
    const impostor = [0.12, 0.05, 0.18, 0.02, 0.08, -0.05, 0.22];

    const report = BiometricCalibrationHarness.calibrateFromScores(genuine, impostor);
    assert.ok(report.recommendedVerifyThreshold > 0.22);
    assert.ok(report.recommendedVerifyThreshold <= 0.76);
    assert.ok(report.equalErrorRate <= 0.05);
    assert.ok(report.asciiDetCurve.length > 0);
  });
});
