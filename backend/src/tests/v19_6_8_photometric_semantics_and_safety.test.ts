// backend/src/tests/v19_6_8_photometric_semantics_and_safety.test.ts
//
// KELASAGARA BIOMATCH V19.6.8
// Scientific Verification: Photometric Measurement Semantics, Image Quality Guards,
// Non-Enforcement Invariants, and Biometric Decoupling Test Suite
// Standards: ISO/IEC 30107-3:2023, ISO/IEC 24745:2022

process.env.ALLOW_DEV_TOKEN = "true";

import { describe, it } from "node:test";
import assert from "node:assert";
import sharp from "sharp";
import {
  ExperimentalPhotometricPadService,
  PhotometricAnalysisResult,
} from "../services/experimental_photometric_pad_service";
import { config } from "../config";
import {
  SessionChallengeService,
  VERIFIED_CHALLENGE_ACTIONS,
} from "../services/session_challenge_service";

// Helper: Synthesize compliant 112x112 grayscale buffer with customizable properties
async function createTestImageBuffer(
  luma: number,
  options?: {
    highLumaPixelFraction?: number;
    highLumaPixelValue?: number;
    gradientSpan?: number;
  }
): Promise<Buffer> {
  const width = 112;
  const height = 112;
  const total = width * height;
  const buf = Buffer.alloc(total, luma);
  const span = options?.gradientSpan ?? 0;

  for (let i = 0; i < total; i++) {
    const offset = span > 0 ? (i % span) - Math.floor(span / 2) : 0;
    buf[i] = Math.max(0, Math.min(255, luma + offset));
  }

  if (options?.highLumaPixelFraction && options.highLumaPixelFraction > 0) {
    const val = options.highLumaPixelValue ?? 250;
    const count = Math.floor(total * options.highLumaPixelFraction);
    for (let i = 0; i < count; i++) {
      buf[i] = val;
    }
  }

  return sharp(buf, { raw: { width, height, channels: 1 } })
    .png()
    .toBuffer();
}

describe("V19.6.8 Photometric Semantics, Image Quality & Safety Invariants", () => {
  it("1. Accurately reports highLumaPixelCount and highLumaPixelRatio with backward-compatible aliases", async () => {
    // 10% high-luma pixels (luma 250 >= 245)
    const base = await createTestImageBuffer(100, { gradientSpan: 24 });
    const illum = await createTestImageBuffer(120, {
      highLumaPixelFraction: 0.10,
      highLumaPixelValue: 250,
      gradientSpan: 24,
    });

    const result = await ExperimentalPhotometricPadService.evaluatePhotometricResponse(base, illum);

    // Explicit physical measurement names
    assert.strictEqual(typeof result.measurement.highLumaPixelCount, "number");
    assert.strictEqual(typeof result.measurement.highLumaPixelRatio, "number");
    assert(
      result.measurement.highLumaPixelCount > 0,
      "Expected highLumaPixelCount > 0"
    );
    assert(
      result.measurement.highLumaPixelRatio >= 0.09 && result.measurement.highLumaPixelRatio <= 0.11,
      `Expected highLumaPixelRatio ~0.10, got ${result.measurement.highLumaPixelRatio}`
    );

    // Deprecated aliases exact match
    assert.strictEqual(
      result.measurement.specularPixelCount,
      result.measurement.highLumaPixelCount,
      "specularPixelCount alias must strictly equal highLumaPixelCount"
    );
    assert.strictEqual(
      result.measurement.specularSaturationRatio,
      result.measurement.highLumaPixelRatio,
      "specularSaturationRatio alias must strictly equal highLumaPixelRatio"
    );
    assert.strictEqual(
      result.highLumaPixelCount,
      result.measurement.highLumaPixelCount,
      "Root highLumaPixelCount must match measurement"
    );
    assert.strictEqual(
      result.highLumaPixelRatio,
      result.measurement.highLumaPixelRatio,
      "Root highLumaPixelRatio must match measurement"
    );
  });

  it("2. Evaluates quality across BOTH frames: flags illuminated-frame overexposure as INCONCLUSIVE", async () => {
    // Baseline is well-exposed (luma 120), but illuminated frame is blown out / overexposed (luma 245 > 240)
    const normalBase = await createTestImageBuffer(120, { gradientSpan: 24 });
    const blownIllum = await createTestImageBuffer(245, { gradientSpan: 24 });

    const result = await ExperimentalPhotometricPadService.evaluatePhotometricResponse(normalBase, blownIllum);

    assert.strictEqual(result.measurement.qualityIndicators.baselineOverexposed, false);
    assert.strictEqual(result.measurement.qualityIndicators.illuminatedOverexposed, true);
    assert.strictEqual(result.measurement.qualityIndicators.isSeverelyOverexposed, true);
    assert.strictEqual(result.measurement.qualityIndicators.isQualityAcceptable, false);
    assert.strictEqual(result.interpretation.candidateComparison, "INCONCLUSIVE");
    assert.strictEqual(result.classification, "INCONCLUSIVE");
  });

  it("3. Evaluates quality across BOTH frames: flags illuminated-frame underexposure as INCONCLUSIVE", async () => {
    // Baseline is well-exposed (luma 100), but illuminated frame drops into darkness (luma 10 < 15)
    const normalBase = await createTestImageBuffer(100, { gradientSpan: 24 });
    const pitchBlackIllum = await createTestImageBuffer(10, { gradientSpan: 24 });

    const result = await ExperimentalPhotometricPadService.evaluatePhotometricResponse(normalBase, pitchBlackIllum);

    assert.strictEqual(result.measurement.qualityIndicators.baselineUnderexposed, false);
    assert.strictEqual(result.measurement.qualityIndicators.illuminatedUnderexposed, true);
    assert.strictEqual(result.measurement.qualityIndicators.isSeverelyUnderexposed, true);
    assert.strictEqual(result.measurement.qualityIndicators.isQualityAcceptable, false);
    assert.strictEqual(result.interpretation.candidateComparison, "INCONCLUSIVE");
    assert.strictEqual(result.classification, "INCONCLUSIVE");
  });

  it("4. Evaluates contrast span independently for both baseline and illuminated frames", async () => {
    // Both frames have wide contrast span (span 30 >= 20)
    const wideBase = await createTestImageBuffer(100, { gradientSpan: 30 });
    const wideIllum = await createTestImageBuffer(125, { gradientSpan: 30 });

    const result = await ExperimentalPhotometricPadService.evaluatePhotometricResponse(wideBase, wideIllum);

    assert.strictEqual(result.measurement.qualityIndicators.hasValidContrast, true);
    assert.strictEqual(result.measurement.qualityIndicators.baselineUnderexposed, false);
    assert.strictEqual(result.measurement.qualityIndicators.baselineOverexposed, false);
    assert.strictEqual(result.measurement.qualityIndicators.illuminatedUnderexposed, false);
    assert.strictEqual(result.measurement.qualityIndicators.illuminatedOverexposed, false);
    assert.strictEqual(result.measurement.qualityIndicators.isQualityAcceptable, true);
  });

  it("5. Verifies numeric safety on extreme dark frames (baseline 0 luma)", async () => {
    const zeroBase = await createTestImageBuffer(0);
    const lowIllum = await createTestImageBuffer(5);

    const result = await ExperimentalPhotometricPadService.evaluatePhotometricResponse(zeroBase, lowIllum);

    assert.ok(Number.isFinite(result.measurement.relativeLumaDelta));
    assert.strictEqual(result.measurement.qualityIndicators.isSeverelyUnderexposed, true);
    assert.strictEqual(result.interpretation.candidateComparison, "INCONCLUSIVE");
  });

  it("6. Threshold safety invariant: Photometric PAD is strictly non-enforcing", async () => {
    const base = await createTestImageBuffer(110, { gradientSpan: 24 });
    const illum = await createTestImageBuffer(130, { gradientSpan: 24 });

    const result = await ExperimentalPhotometricPadService.evaluatePhotometricResponse(base, illum);

    // Invariants
    assert.strictEqual(result.isEnforcing, false, "Must never enforce authentication decisions");
    assert.strictEqual(result.experimentOnly, true, "Must be tagged experimentOnly");

    // Biometric thresholds remain strictly decoupled and uncalibrated for production
    assert.strictEqual(config.verificationThreshold, 0.363);
    assert.strictEqual(config.duplicateThreshold, 0.740);
    assert.strictEqual(config.duplicateBlockThreshold, 0.900);
    assert.strictEqual(config.productionBiometricCalibrationApproved, false);
    assert.strictEqual(config.releaseGateStatus, "CONTROLLED_TEST_BUILD_ONLY");
    assert.deepStrictEqual(VERIFIED_CHALLENGE_ACTIONS, ["BLINK"]);
  });
});
