// File: backend/tests/v19_5_research_harness.test.ts
// Tests for V19.5 Research Benchmark Harness, Wilson Score intervals, Rule of 3, and 1:N Scaling
import { describe, it } from 'node:test';
import * as assert from 'node:assert';
import {
  computeWilsonScoreInterval,
  computeRuleOfThreeBound,
  evaluatePairwiseVerification,
  runDirect1ToNGalleryBenchmark,
  simulateLowLightCurveEnhancement,
  PairwiseTrial,
} from '../evaluation/v19_5_research_harness';

describe('V19.5 Research Benchmark Harness & Statistical Engine', () => {
  it('computes correct Wilson score intervals without negative bounds', () => {
    // 0 errors out of 1000 trials
    const zeroErr = computeWilsonScoreInterval(0, 1000, 0.95);
    assert.strictEqual(zeroErr.pointEstimate, 0);
    assert.strictEqual(zeroErr.lowerBound, 0);
    assert.ok(zeroErr.upperBound > 0 && zeroErr.upperBound < 0.005);

    // 5 errors out of 1000 trials
    const someErr = computeWilsonScoreInterval(5, 1000, 0.95);
    assert.strictEqual(someErr.pointEstimate, 0.005);
    assert.ok(someErr.lowerBound > 0.001);
    assert.ok(someErr.upperBound < 0.012);
  });

  it('computes Rule of Three upper bound for zero observed failures', () => {
    const bound30k = computeRuleOfThreeBound(30000);
    assert.strictEqual(bound30k.trialsCount, 30000);
    assert.strictEqual(bound30k.observedErrors, 0);
    // Upper bound ≈ 3 / 30,000 = 1e-4
    assert.ok(bound30k.upperConfidenceBound95 <= 0.0001001);
  });

  it('evaluates 1:1 pairwise verification metrics accurately', () => {
    const trials: PairwiseTrial[] = [
      // 4 genuine comparisons
      { subject1: 'u1', subject2: 'u1', score: 0.85, isMated: true, lightingCondition: 'NORMAL_INDOOR_150_300_LUX' },
      { subject1: 'u1', subject2: 'u1', score: 0.72, isMated: true, lightingCondition: 'NORMAL_INDOOR_150_300_LUX' },
      { subject1: 'u2', subject2: 'u2', score: 0.90, isMated: true, lightingCondition: 'NORMAL_INDOOR_150_300_LUX' },
      { subject1: 'u2', subject2: 'u2', score: 0.30, isMated: true, lightingCondition: 'DIM_INDOOR_5_15_LUX' }, // FNMR event at 0.363
      // 4 impostor comparisons
      { subject1: 'u1', subject2: 'u2', score: 0.12, isMated: false, lightingCondition: 'NORMAL_INDOOR_150_300_LUX' },
      { subject1: 'u1', subject2: 'u3', score: 0.05, isMated: false, lightingCondition: 'NORMAL_INDOOR_150_300_LUX' },
      { subject1: 'u2', subject2: 'u3', score: 0.18, isMated: false, lightingCondition: 'NORMAL_INDOOR_150_300_LUX' },
      { subject1: 'u1', subject2: 'u4', score: 0.40, isMated: false, lightingCondition: 'NORMAL_INDOOR_150_300_LUX' }, // FMR event at 0.363
    ];

    const report = evaluatePairwiseVerification(trials, 0.363);
    assert.strictEqual(report.totalMatedPairs, 4);
    assert.strictEqual(report.totalNonMatedPairs, 4);
    assert.strictEqual(report.falseNonMatchCount, 1);
    assert.strictEqual(report.falseMatchCount, 1);
    assert.strictEqual(report.fnmr.pointEstimate, 0.25);
    assert.strictEqual(report.fmr.pointEstimate, 0.25);
    assert.ok(report.decidabilityIndexDPrime > 0);
  });

  it('runs direct 1:N gallery scale benchmark across N=100 and N=1000', () => {
    const res100 = runDirect1ToNGalleryBenchmark(100, 50, 0.74, 0.90);
    assert.strictEqual(res100.gallerySizeN, 100);
    assert.strictEqual(res100.unenrolledQueryCount, 50);
    assert.ok(res100.searchLatencyMsP50 >= 0);
    assert.strictEqual(res100.hardBlockCollisionCount, 0); // No collision at 0.90 on random unit sphere

    const res1000 = runDirect1ToNGalleryBenchmark(1000, 50, 0.74, 0.90);
    assert.strictEqual(res1000.gallerySizeN, 1000);
    assert.strictEqual(res1000.hardBlockCollisionCount, 0);
  });

  it('verifies non-linear low-light curve brightening formula', () => {
    const darkLuma = 15;
    const brightened = simulateLowLightCurveEnhancement(darkLuma, 4);
    assert.ok(brightened > darkLuma, 'Brightened pixel must have higher luma');
    assert.ok(brightened <= 255, 'Must remain bounded in uint8 range');
  });
});
