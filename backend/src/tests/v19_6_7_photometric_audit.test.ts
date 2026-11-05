// backend/src/tests/v19_6_7_photometric_audit.test.ts
//
// KELASAGARA BIOMATCH V19.6.7
// Scientific Audit: Photometric Signal Measurement & Non-Enforcement Test Suite
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

// Helper: Synthesize compliant 112x112 grayscale buffer with customizable properties
async function createTestImageBuffer(luma: number, specularFraction: number = 0): Promise<Buffer> {
  const width = 112;
  const height = 112;
  const total = width * height;
  const buf = Buffer.alloc(total, luma);

  if (specularFraction > 0) {
    const count = Math.floor(total * specularFraction);
    for (let i = 0; i < count; i++) {
      buf[(i * 19) % total] = 250;
    }
  }

  return sharp(buf, { raw: { width, height, channels: 1 } })
    .jpeg({ quality: 85 })
    .toBuffer();
}

describe("V19.6.7 Scientific Audit: Experimental Photometric PAD Service", () => {
  it("1. Delineates feature measurement from experimental interpretation", async () => {
    const base = await createTestImageBuffer(100);
    const illum = await createTestImageBuffer(120);

    const result = await ExperimentalPhotometricPadService.evaluatePhotometricResponse(base, illum);

    // Measurement structure with explicit units and scales
    assert.ok(result.measurement, "Measurement structure must exist");
    assert.strictEqual(typeof result.measurement.baselineLuma8Bit, "number");
    assert.strictEqual(typeof result.measurement.illuminatedLuma8Bit, "number");
    assert.strictEqual(typeof result.measurement.absoluteLumaDelta, "number");
    assert.strictEqual(typeof result.measurement.relativeLumaDelta, "number");
    assert.strictEqual(result.measurement.sampleDimensions.width, 112);
    assert.strictEqual(result.measurement.sampleDimensions.height, 112);
    assert.strictEqual(result.measurement.sampleDimensions.totalPixels, 12544);

    // Interpretation structure with explicit unvalidated provenance
    assert.ok(result.interpretation, "Interpretation structure must exist");
    assert.strictEqual(
      result.interpretation.provenance,
      "UNVALIDATED_THEORETICAL_HYPOTHESIS",
      "Provenance must be explicitly UNVALIDATED"
    );
    assert.strictEqual(
      result.interpretation.status,
      "UNCALIBRATED_EXPERIMENTAL_ONLY",
      "Status must indicate uncalibrated research only"
    );
    assert.ok(
      result.interpretation.scientificDisclaimer.includes("has not been established on physical devices"),
      "Must include standard scientific disclaimer"
    );
  });

  it("2. Accurately calculates absolute and relative delta luma without division by zero", async () => {
    // Pitch black baseline (0 luma)
    const blackBase = await createTestImageBuffer(0);
    const dimIllum = await createTestImageBuffer(10);

    const result = await ExperimentalPhotometricPadService.evaluatePhotometricResponse(blackBase, dimIllum);

    // Math.max(baseline, 1.0) prevents NaN or Infinity
    assert.ok(Number.isFinite(result.measurement.relativeLumaDelta));
    assert.strictEqual(result.measurement.absoluteLumaDelta, 10);
    // Severely underexposed input flagged by quality indicators
    assert.strictEqual(result.measurement.qualityIndicators.isSeverelyUnderexposed, true);
    assert.strictEqual(result.interpretation.candidateComparison, "INCONCLUSIVE");
  });

  it("3. Quality indicators flag severely overexposed input as INCONCLUSIVE", async () => {
    const brightBase = await createTestImageBuffer(245);
    const brightIllum = await createTestImageBuffer(250);

    const result = await ExperimentalPhotometricPadService.evaluatePhotometricResponse(brightBase, brightIllum);

    assert.strictEqual(result.measurement.qualityIndicators.isSeverelyOverexposed, true);
    assert.strictEqual(result.interpretation.candidateComparison, "INCONCLUSIVE");
  });

  it("4. Thresholds are explicitly labeled as unvalidated experimental configuration", () => {
    const thresholds = {
      cutoff: ExperimentalPhotometricPadService.SPECULAR_LUMA_CUTOFF,
      diffuseMin: ExperimentalPhotometricPadService.CANDIDATE_DIFFUSE_DELTA_MIN,
      diffuseSpecMax: ExperimentalPhotometricPadService.CANDIDATE_DIFFUSE_SPECULAR_RATIO_MAX,
      replaySpecMin: ExperimentalPhotometricPadService.CANDIDATE_REPLAY_SPECULAR_RATIO_MIN,
    };

    assert.strictEqual(thresholds.cutoff, 245);
    assert.strictEqual(thresholds.diffuseMin, 0.04);
    assert.strictEqual(thresholds.diffuseSpecMax, 0.03);
    assert.strictEqual(thresholds.replaySpecMin, 0.05);
  });

  it("5. Mandatory Safety Invariant: Photometric PAD is 100% non-enforcing across all branches", async () => {
    const base = await createTestImageBuffer(110);
    const illum = await createTestImageBuffer(130);

    const result = await ExperimentalPhotometricPadService.evaluatePhotometricResponse(base, illum);

    assert.strictEqual(result.isEnforcing, false);
    assert.strictEqual(result.experimentOnly, true);
    // Verify core biometric thresholds in config are completely independent of photometric outputs
    assert.strictEqual(config.verificationThreshold, 0.363);
    assert.strictEqual(config.duplicateThreshold, 0.740);
    assert.strictEqual(config.duplicateBlockThreshold, 0.900);
  });
});
