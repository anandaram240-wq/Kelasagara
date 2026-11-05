// backend/src/tests/v19_6_6_security_and_photometric.test.ts
//
// KELASAGARA BIOMATCH V19.6.6
// Advanced Security Regression, Pipeline Invariants & Experimental Photometric PAD Test Suite
// Standards: ISO/IEC 30107-3:2023, ISO/IEC 19794-5:2025, ISO/IEC 24745:2022

process.env.ALLOW_DEV_TOKEN = "true";

import { describe, it } from "node:test";
import assert from "node:assert";
import sharp from "sharp";
import {
  ExperimentalPhotometricPadService,
  PhotometricAnalysisResult,
} from "../services/experimental_photometric_pad_service";
import {
  TemporalActionValidator,
  BurstFrameInput,
} from "../services/temporal_action_validator";

// Helper: Synthesize compliant 112x112 grayscale buffer with customizable specular & diffuse properties
async function createSyntheticPhotometricBuffer(options: {
  baseLuma: number;
  specularPixelsFraction?: number;
  seed?: number;
}): Promise<Buffer> {
  const width = 112;
  const height = 112;
  const total = width * height;
  const buf = Buffer.alloc(total, options.baseLuma);
  const seed = options.seed ?? 1;

  for (let i = 0; i < total; i++) {
    buf[i] = Math.max(0, Math.min(255, options.baseLuma + ((i * seed) % 5) - 2));
  }

  // Inject specular glare pixels if requested (luma >= 248)
  if (options.specularPixelsFraction && options.specularPixelsFraction > 0) {
    const specularCount = Math.floor(total * options.specularPixelsFraction);
    for (let i = 0; i < specularCount; i++) {
      const idx = Math.floor((i * 17) % total);
      buf[idx] = 250;
    }
  }

  return sharp(buf, { raw: { width, height, channels: 1 } })
    .jpeg({ quality: 85 })
    .toBuffer();
}

// Helper: Synthesize 3-frame temporal burst frames
async function createSyntheticBurstFrame(
  sequenceIndex: number,
  offsetMs: number,
  ocularState: "open" | "closed",
  seed: number
): Promise<BurstFrameInput> {
  const width = 112;
  const height = 112;
  const buf = Buffer.alloc(width * height, 130);

  // Pseudo-random noise
  for (let i = 0; i < width * height; i++) {
    buf[i] = Math.max(0, Math.min(255, 130 + ((i * seed) % 7) - 3));
  }

  // Draw face contour boundary
  for (let y = 15; y < 97; y++) {
    for (let x = 15; x < 97; x++) {
      const dist = Math.sqrt((x - 56) ** 2 + (y - 56) ** 2);
      if (dist < 38) {
        buf[y * width + x] = 160;
      }
    }
  }

  // Lower facial feature
  for (let y = 78; y < 86; y++) {
    for (let x = 38; x < 74; x++) {
      buf[y * width + x] = 35;
    }
  }

  // Ocular features
  if (ocularState === "open") {
    for (let x = 25; x < 87; x++) {
      buf[42 * width + x] = 20;
      buf[48 * width + x] = 240;
      buf[52 * width + x] = 30;
      buf[56 * width + x] = 240;
    }
  } else {
    for (let x = 25; x < 87; x++) {
      buf[42 * width + x] = 25;
      buf[50 * width + x] = 120;
    }
  }

  const jpeg = await sharp(buf, { raw: { width, height, channels: 1 } })
    .jpeg({ quality: 85 })
    .toBuffer();

  return {
    sequenceIndex,
    capturedOffsetMs: offsetMs,
    jpegBase64: jpeg.toString("base64"),
  };
}

describe("V19.6.6 Experimental Photometric PAD Feasibility Service", () => {
  it("1. Correctly classifies diffuse skin illumination gain (CANDIDATE_DIFFUSE_RESPONSE)", async () => {
    // Baseline: natural ambient skin (luma ~110)
    const baseBuffer = await createSyntheticPhotometricBuffer({
      baseLuma: 110,
      specularPixelsFraction: 0.005, // 0.5% natural mild specular
      seed: 3,
    });

    // Illuminated: diffuse skin gain (+18% luma, minimal specular)
    const illumBuffer = await createSyntheticPhotometricBuffer({
      baseLuma: 130,
      specularPixelsFraction: 0.008, // 0.8% specular
      seed: 7,
    });

    const result = await ExperimentalPhotometricPadService.evaluatePhotometricResponse(
      baseBuffer,
      illumBuffer
    );

    assert.strictEqual(result.classification, "CANDIDATE_DIFFUSE_RESPONSE");
    assert.strictEqual(result.isEnforcing, false);
    assert.strictEqual(result.experimentOnly, true);
    assert(result.deltaLuma >= 0.04, `Expected deltaLuma >= 0.04, got ${result.deltaLuma}`);
    assert(
      result.specularSaturationRatio <= 0.03,
      `Expected specularRatio <= 0.03, got ${result.specularSaturationRatio}`
    );
  });

  it("2. Correctly flags electronic display glass reflection (CANDIDATE_SPECULAR_REPLAY)", async () => {
    // Baseline: emissive screen presentation (luma ~180)
    const baseBuffer = await createSyntheticPhotometricBuffer({
      baseLuma: 180,
      seed: 2,
    });

    // Illuminated: strong glass reflection with >= 6% saturated pixels (luma >= 248)
    const illumBuffer = await createSyntheticPhotometricBuffer({
      baseLuma: 182,
      specularPixelsFraction: 0.07, // 7% specular glare
      seed: 5,
    });

    const result = await ExperimentalPhotometricPadService.evaluatePhotometricResponse(
      baseBuffer,
      illumBuffer
    );

    assert.strictEqual(result.classification, "CANDIDATE_SPECULAR_REPLAY");
    assert.strictEqual(result.isEnforcing, false);
    assert.strictEqual(result.experimentOnly, true);
    assert(
      result.specularSaturationRatio >= 0.05,
      `Expected specularRatio >= 0.05, got ${result.specularSaturationRatio}`
    );
  });

  it("3. Returns INCONCLUSIVE on flat, identical, or unilluminated presentations", async () => {
    const baseBuffer = await createSyntheticPhotometricBuffer({ baseLuma: 120, seed: 1 });
    const sameBuffer = await createSyntheticPhotometricBuffer({ baseLuma: 121, seed: 2 });

    const result = await ExperimentalPhotometricPadService.evaluatePhotometricResponse(
      baseBuffer,
      sameBuffer
    );

    assert.strictEqual(result.classification, "INCONCLUSIVE");
    assert.strictEqual(result.isEnforcing, false);
    assert.strictEqual(result.experimentOnly, true);
  });

  it("4. Gracefully handles corrupted, malformed, or empty image buffers", async () => {
    const emptyBuf = Buffer.alloc(0);
    const junkBuf = Buffer.from("not_a_real_image_buffer");

    const result = await ExperimentalPhotometricPadService.evaluatePhotometricResponse(
      emptyBuf,
      junkBuf
    );

    assert.strictEqual(result.classification, "INCONCLUSIVE");
    assert.strictEqual(result.isEnforcing, false);
    assert.strictEqual(result.experimentOnly, true);
    assert(result.details.includes("Invalid") || result.details.includes("Failed"));
  });

  it("5. Mandatory Safety Invariant: Photometric PAD is 100% non-enforcing", async () => {
    // Under no circumstances can photometric PAD return isEnforcing: true
    const baseBuffer = await createSyntheticPhotometricBuffer({ baseLuma: 100, seed: 1 });
    const illumBuffer = await createSyntheticPhotometricBuffer({ baseLuma: 125, seed: 2 });

    const result: PhotometricAnalysisResult =
      await ExperimentalPhotometricPadService.evaluatePhotometricResponse(
        baseBuffer,
        illumBuffer
      );

    assert.strictEqual(result.isEnforcing, false);
    assert.strictEqual(result.experimentOnly, true);
  });
});

describe("V19.6.6 Security Regression & Liveness Protocol Bounds", () => {
  it("6. TemporalActionValidator rejects identical frozen frames (anti-replay)", async () => {
    const f0 = await createSyntheticBurstFrame(0, 1000, "open", 1);
    const f1 = { ...f0, sequenceIndex: 1, capturedOffsetMs: 1150 }; // Exact duplicate of f0
    const f2 = await createSyntheticBurstFrame(2, 1300, "open", 3);

    const validation = await TemporalActionValidator.validateBurst([f0, f1, f2], "BLINK");
    assert.strictEqual(validation.passed, false);
    assert.strictEqual(validation.status, "rejected");
    assert.strictEqual(validation.rejectionReason, "DUPLICATE_FRAME_REPLAY_DETECTED");
  });

  it("7. TemporalActionValidator rejects timing gaps under 40ms or over 600ms", async () => {
    // Interval too short (< 40ms)
    const f0 = await createSyntheticBurstFrame(0, 1000, "open", 1);
    const f1TooFast = await createSyntheticBurstFrame(1, 1020, "closed", 2); // dt = 20ms
    const f2 = await createSyntheticBurstFrame(2, 1180, "open", 3);

    const resTooFast = await TemporalActionValidator.validateBurst([f0, f1TooFast, f2], "BLINK");
    assert.strictEqual(resTooFast.passed, false);
    assert.strictEqual(resTooFast.rejectionReason, "INTER_FRAME_TIMING_OUT_OF_BOUNDS");

    // Interval too slow (> 600ms)
    const f1TooSlow = await createSyntheticBurstFrame(1, 1800, "closed", 2); // dt = 800ms
    const resTooSlow = await TemporalActionValidator.validateBurst([f0, f1TooSlow, f2], "BLINK");
    assert.strictEqual(resTooSlow.passed, false);
    assert.strictEqual(resTooSlow.rejectionReason, "INTER_FRAME_TIMING_OUT_OF_BOUNDS");
  });

  it("8. TemporalActionValidator rejects out-of-order sequence index submission", async () => {
    const f0 = await createSyntheticBurstFrame(0, 1000, "open", 1);
    const f1 = await createSyntheticBurstFrame(1, 1150, "closed", 2);
    const f2 = await createSyntheticBurstFrame(2, 1300, "open", 3);

    // Swap indices
    const outOfOrder = [f0, { ...f2, sequenceIndex: 1 }, { ...f1, sequenceIndex: 2 }];
    const res = await TemporalActionValidator.validateBurst(outOfOrder, "BLINK");
    assert.strictEqual(res.passed, false);
    // Captured offset is also out of order: 1300 then 1150
    assert(
      res.rejectionReason === "INTER_FRAME_TIMING_OUT_OF_BOUNDS" ||
      res.rejectionReason === "OUT_OF_ORDER_FRAME_SEQUENCE"
    );
  });

  it("9. TemporalActionValidator accepts valid blink trajectory (open -> closed -> open)", async () => {
    const f0 = await createSyntheticBurstFrame(0, 1000, "open", 10);
    const f1 = await createSyntheticBurstFrame(1, 1160, "closed", 20);
    const f2 = await createSyntheticBurstFrame(2, 1320, "open", 30);

    const res = await TemporalActionValidator.validateBurst([f0, f1, f2], "BLINK");
    assert.strictEqual(res.passed, true);
    assert.strictEqual(res.status, "verified");
    assert(res.telemetry.actionApexMetric <= 0.65, `Apex aperture ${res.telemetry.actionApexMetric} <= 0.65`);
    assert(res.telemetry.anchorIdentitySimilarity02 >= 0.80);
  });
});
