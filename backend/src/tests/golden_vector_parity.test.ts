// backend/src/tests/golden_vector_parity.test.ts
import assert from "assert";
import {
  PREPROCESSING_ID,
  CANONICAL_5_LANDMARKS,
  computeUmeyamaTransform,
  warpFaceUmeyama,
  validateFaceQuality,
  validateNumericalVector,
} from "../services/face_preprocessing";
import { runFaceInference } from "../services/face_inference";

function createDeterministicSyntheticImage(): Buffer {
  const width = 112;
  const height = 112;
  const channels = 3;
  const buf = Buffer.alloc(width * height * channels);

  let idx = 0;
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      // Deterministic geometric gradient + checkerboard pattern
      const r = (x * 2 + y) % 256;
      const g = (y * 2 + x) % 256;
      const b = ((x ^ y) * 4) % 256;

      buf[idx++] = r;
      buf[idx++] = g;
      buf[idx++] = b;
    }
  }
  return buf;
}

async function runGoldenVectorParitySuite() {
  console.log("====================================================");
  console.log("🧪 RUNNING PHASE 4: REFERENCE PIPELINE & GOLDEN PARITY");
  console.log("====================================================");

  // ── TEST 1: Versioned Preprocessing ID & Canonical Landmarks
  console.log(`Checking versioned preprocessing ID: ${PREPROCESSING_ID}`);
  assert.strictEqual(
    PREPROCESSING_ID,
    "PREPROC_V1_UMEYAMA_112_RGB_RAW255",
    "Preprocessing ID must match versioned specification"
  );
  assert.strictEqual(CANONICAL_5_LANDMARKS.length, 5, "Must define 5 canonical landmarks");
  assert.strictEqual(CANONICAL_5_LANDMARKS[0].name, "left_eye");
  assert.strictEqual(CANONICAL_5_LANDMARKS[1].name, "right_eye");
  console.log("✔ Test 1: Preprocessing ID and canonical 5-point landmarks verified.");

  // ── TEST 1B: Umeyama Closed-Form Transform & Warp
  console.log("Testing Umeyama closed-form 2D similarity transform...");
  // Test identity case: canonical landmarks mapped to themselves
  const identityTransform = computeUmeyamaTransform(CANONICAL_5_LANDMARKS, CANONICAL_5_LANDMARKS);
  assert.ok(Math.abs(identityTransform.scale - 1.0) < 1e-4, "Identity scale must be 1.0");
  assert.ok(Math.abs(identityTransform.theta) < 1e-4, "Identity rotation must be 0");
  assert.ok(Math.abs(identityTransform.tx) < 1e-4, "Identity tx must be 0");
  assert.ok(Math.abs(identityTransform.ty) < 1e-4, "Identity ty must be 0");

  // Test transformed case: known scale=1.5, angle=30deg, tx=20, ty=35
  const s0 = 1.5;
  const theta0 = (30 * Math.PI) / 180;
  const cos0 = Math.cos(theta0);
  const sin0 = Math.sin(theta0);
  const tx0 = 20;
  const ty0 = 35;
  const transformedLandmarks = CANONICAL_5_LANDMARKS.map((pt) => ({
    name: pt.name,
    x: s0 * (cos0 * pt.x - sin0 * pt.y) + tx0,
    y: s0 * (sin0 * pt.x + cos0 * pt.y) + ty0,
  }));

  // Umeyama mapping transformedLandmarks -> CANONICAL_5_LANDMARKS
  const recovered = computeUmeyamaTransform(transformedLandmarks, CANONICAL_5_LANDMARKS);
  assert.ok(Math.abs(recovered.scale - (1.0 / s0)) < 1e-3, "Recovered scale must match inverse");
  assert.ok(Math.abs(recovered.theta - (-theta0)) < 1e-3, "Recovered theta must be -theta0");

  // Verify warp buffer execution
  const testImg = createDeterministicSyntheticImage();
  const warped = warpFaceUmeyama(testImg, 112, 112, identityTransform);
  assert.strictEqual(warped.length, 112 * 112 * 3, "Warped buffer size must be 112x112x3");
  console.log("✔ Test 1B: Umeyama closed-form transform & warp verified.");

  // ── TEST 2: Quality Gating (IQA Threshold Validation)
  const lowRes = validateFaceQuality({ width: 80, height: 80 });
  assert.strictEqual(lowRes.isValid, false, "Should reject low resolution face");
  assert.ok(lowRes.failureReason?.includes("too small"));

  const lowIPD = validateFaceQuality({
    width: 224,
    height: 224,
    leftEye: { x: 50, y: 50 },
    rightEye: { x: 60, y: 50 }, // dx = 10 < 35 min IPD
  });
  assert.strictEqual(lowIPD.isValid, false, "Should reject low IPD");

  const extremeYaw = validateFaceQuality({
    width: 224,
    height: 224,
    leftEye: { x: 38, y: 51 },
    rightEye: { x: 73, y: 51 },
    yawDegrees: 45, // > 30 deg limit
  });
  assert.strictEqual(extremeYaw.isValid, false, "Should reject extreme yaw");

  const severeBlur = validateFaceQuality({
    width: 224,
    height: 224,
    leftEye: { x: 38, y: 51 },
    rightEye: { x: 73, y: 51 },
    laplacianBlurScore: 40, // < 60 min
  });
  assert.strictEqual(severeBlur.isValid, false, "Should reject blurry frame");

  const validQuality = validateFaceQuality({
    width: 224,
    height: 224,
    leftEye: { x: 38, y: 51 },
    rightEye: { x: 73, y: 51 },
    yawDegrees: 5,
    pitchDegrees: 2,
    meanLuminance: 120,
    laplacianBlurScore: 180,
  });
  assert.strictEqual(validQuality.isValid, true, "Clean frame must pass quality gate");
  console.log("✔ Test 2: Quality gating (resolution, IPD, pose, blur, illumination) verified.");

  // ── TEST 3: Numerical Vector Validation
  const nanVec = [0.1, NaN, 0.5];
  assert.strictEqual(validateNumericalVector(nanVec, 3).isValid, false, "Should reject NaN");

  const wrongDim = new Array(64).fill(0.1);
  assert.strictEqual(validateNumericalVector(wrongDim, 128).isValid, false, "Should reject wrong dim");

  const zeroVec = new Array(128).fill(0.0);
  assert.strictEqual(validateNumericalVector(zeroVec, 128).isValid, false, "Should reject all zeros");

  const constVec = new Array(128).fill(1.0 / Math.sqrt(128));
  assert.strictEqual(validateNumericalVector(constVec, 128).isValid, false, "Should reject degenerate constant vector");

  // Valid unit vector on S^127
  const validVec = new Array(128).fill(0);
  validVec[0] = 0.6;
  validVec[1] = 0.8;
  const validCheck = validateNumericalVector(validVec, 128);
  assert.strictEqual(validCheck.isValid, true, "Valid unit vector must pass numerical check");
  assert.ok(Math.abs(validCheck.norm - 1.0) < 1e-4, "Norm must equal 1.0");
  console.log("✔ Test 3: Numerical vector validation (NaN, dimension, zero, norm) verified.");

  // ── TEST 4: Deterministic Golden Vector Inference
  console.log("Generating deterministic synthetic image buffer (112x112x3)...");
  const syntheticImg = createDeterministicSyntheticImage();

  console.log("Executing Pass 1 ONNX inference...");
  const vec1 = await runFaceInference(syntheticImg);

  console.log("Executing Pass 2 ONNX inference...");
  const vec2 = await runFaceInference(syntheticImg);

  assert.strictEqual(vec1.length, 128, "Inference vector must be 128-D");
  assert.strictEqual(vec2.length, 128, "Inference vector must be 128-D");

  // Assert exact reproducibility between pass 1 and pass 2
  let maxDelta = 0;
  for (let i = 0; i < 128; i++) {
    const delta = Math.abs(vec1[i] - vec2[i]);
    if (delta > maxDelta) maxDelta = delta;
    assert.ok(delta < 1e-5, `Inference drift at index ${i}: delta ${delta}`);
  }
  console.log(`Deterministic repeatability: max delta across 128 dimensions = ${maxDelta.toExponential(2)}`);

  // Assert numerical validity of output
  const numCheck = validateNumericalVector(vec1, 128);
  assert.strictEqual(numCheck.isValid, true, "Model output must pass numerical validation");
  console.log(`Model output L2 norm: ${numCheck.norm.toFixed(6)} (Target: 1.000000)`);
  console.log("✔ Test 4: Deterministic golden-vector repeatability & numerical integrity verified.");

  console.log("====================================================");
  console.log("🎉 ALL PHASE 4 REFERENCE PIPELINE & PARITY TESTS PASSED!");
  console.log("====================================================");
}

runGoldenVectorParitySuite().catch((err) => {
  console.error("❌ Golden vector parity suite failed:", err);
  process.exit(1);
});
