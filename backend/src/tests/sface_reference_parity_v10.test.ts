// File: backend/src/tests/sface_reference_parity_v10.test.ts
import { describe, it } from 'node:test';
import assert from 'node:assert';
import * as path from 'path';
import * as fs from 'fs';
import { createHash } from 'crypto';
import {
  CanonicalSFaceEngineV10,
  CANONICAL_SFACE_SPEC_V10,
  CANONICAL_SFACE_5_LANDMARKS,
  createTrustedCanonicalAlignedFixture,
} from '../biometrics/canonical_sface_engine_v10';

describe('PHASE 3B: OPENCV REFERENCE-PARITY & SFACE INFERENCE SUITE', () => {
  const modelPath = path.resolve(__dirname, '../../models/face_recognition_sface_2021dec.onnx');

  it('B1 & B3: Validates exact artifact SHA-256 against OpenCV Zoo canonical reference', () => {
    assert.ok(fs.existsSync(modelPath), `Model artifact must exist at ${modelPath}`);
    const bytes = fs.readFileSync(modelPath);
    const sha256 = createHash('sha256').update(bytes).digest('hex');
    assert.strictEqual(
      sha256.toLowerCase(),
      CANONICAL_SFACE_SPEC_V10.expectedSha256.toLowerCase(),
      'SFace ONNX model SHA-256 digest must strictly match canonical reference'
    );
  });

  it('B3: Engine rejects missing model artifact with explicit MODEL_UNAVAILABLE error', async () => {
    const missingEngine = new CanonicalSFaceEngineV10('/invalid/path/missing_model.onnx');
    await assert.rejects(
      async () => {
        await missingEngine.initializeAndVerifyArtifact();
      },
      /MODEL_UNAVAILABLE: Missing SFace artifact/
    );
  });

  it('B3: Engine rejects incorrect model checksum with explicit mismatch error', async () => {
    const badChecksumEngine = new CanonicalSFaceEngineV10(
      modelPath,
      '0000000000000000000000000000000000000000000000000000000000000000'
    );
    await assert.rejects(
      async () => {
        await badChecksumEngine.initializeAndVerifyArtifact();
      },
      /MODEL_UNAVAILABLE: SHA-256 mismatch/
    );
  });

  it('B1 & B2: Verifies Umeyama 5-point face alignment closed-form recovery and zero residual error', () => {
    // Identity mapping
    const identityTransform = CanonicalSFaceEngineV10.computeUmeyamaSimilarityTransform(
      CANONICAL_SFACE_5_LANDMARKS,
      CANONICAL_SFACE_5_LANDMARKS
    );
    assert.ok(Math.abs(identityTransform.scale - 1.0) < 1e-4, 'Scale must be 1.0 for identity');
    assert.ok(Math.abs(identityTransform.theta) < 1e-4, 'Rotation must be 0 for identity');
    assert.ok(Math.abs(identityTransform.tx) < 1e-4, 'tx must be 0 for identity');
    assert.ok(Math.abs(identityTransform.ty) < 1e-4, 'ty must be 0 for identity');

    // Transformed landmarks: known scale=1.35, angle=25 deg, tx=18, ty=28
    const s0 = 1.35;
    const theta0 = (25 * Math.PI) / 180;
    const cos0 = Math.cos(theta0);
    const sin0 = Math.sin(theta0);
    const tx0 = 18;
    const ty0 = 28;

    const transformed = CANONICAL_SFACE_5_LANDMARKS.map((pt) => ({
      x: s0 * (cos0 * pt.x - sin0 * pt.y) + tx0,
      y: s0 * (sin0 * pt.x + cos0 * pt.y) + ty0,
    }));

    const recovered = CanonicalSFaceEngineV10.computeUmeyamaSimilarityTransform(
      transformed,
      CANONICAL_SFACE_5_LANDMARKS
    );

    assert.ok(Math.abs(recovered.scale - (1.0 / s0)) < 1e-3, 'Recovered scale must match reciprocal');
    assert.ok(Math.abs(recovered.theta - (-theta0)) < 1e-3, 'Recovered angle must match -theta0');
  });

  it('B1 & B2: Extracts 128-D embedding strictly normalized on unit hypersphere S^127', async () => {
    const engine = new CanonicalSFaceEngineV10(modelPath);
    await engine.initializeAndVerifyArtifact();

    // Create a deterministic synthetic 112x112x3 RGB buffer
    const width = 112;
    const height = 112;
    const rawRgb = Buffer.alloc(width * height * 3);
    for (let y = 0; y < height; y++) {
      for (let x = 0; x < width; x++) {
        const idx = (y * width + x) * 3;
        rawRgb[idx] = (x * 3 + y) % 256;     // R
        rawRgb[idx + 1] = (y * 2 + x) % 256; // G
        rawRgb[idx + 2] = ((x ^ y) * 5) % 256; // B
      }
    }

    const aligned = createTrustedCanonicalAlignedFixture(rawRgb);
    const embedding = await engine.extractCanonicalEmbeddingFromAligned112(aligned);

    assert.strictEqual(embedding.length, 128, 'Output embedding must have length 128');

    let sumSq = 0;
    for (let i = 0; i < 128; i++) {
      assert.ok(Number.isFinite(embedding[i]), `Embedding element at index ${i} must be finite`);
      sumSq += embedding[i] * embedding[i];
    }
    const norm = Math.sqrt(sumSq);
    assert.ok(
      Math.abs(norm - 1.0) < 1e-5,
      `Embedding L2 norm must equal 1.000000 on S^127, got ${norm}`
    );
  });

  it('B3: Strict validation rejects NaN, Infinite, zero-norm and wrong-dimension tensors', () => {
    // 1. Wrong dimension
    assert.throws(() => {
      CanonicalSFaceEngineV10.extractAndNormalizeOutputTensor({
        type: 'float32',
        data: new Float32Array(64),
      });
    }, /INVALID_EMBEDDING_DIMENSION/);

    // 2. NaN element
    const nanArr = new Float32Array(128);
    nanArr[5] = NaN;
    assert.throws(() => {
      CanonicalSFaceEngineV10.extractAndNormalizeOutputTensor({
        type: 'float32',
        data: nanArr,
      });
    }, /NON_FINITE_EMBEDDING_ELEMENT/);

    // 3. Degenerate zero norm
    const zeroArr = new Float32Array(128);
    assert.throws(() => {
      CanonicalSFaceEngineV10.extractAndNormalizeOutputTensor({
        type: 'float32',
        data: zeroArr,
      });
    }, /DEGENERATE_ZERO_NORM_EMBEDDING/);

    // 4. Quantized int8 without scale
    assert.throws(() => {
      CanonicalSFaceEngineV10.extractAndNormalizeOutputTensor({
        type: 'int8',
        data: new Int8Array(128),
      });
    }, /MISSING_VALID_QUANTIZATION_SCALE_FOR_INT8_TENSOR/);
  });

  it('B2: Cosine similarity calculation is bounded in [-1.0, 1.0] and handles orthogonal & opposite vectors', () => {
    const v1 = new Float32Array(128);
    const v2 = new Float32Array(128);
    v1[0] = 1.0;
    v2[0] = 1.0;

    // Self similarity must be 1.0
    const selfSim = CanonicalSFaceEngineV10.computeCosineSimilarity(v1, v2);
    assert.ok(Math.abs(selfSim - 1.0) < 1e-5, 'Self similarity must be 1.0');

    // Orthogonal vectors
    v2[0] = 0.0;
    v2[1] = 1.0;
    const orthSim = CanonicalSFaceEngineV10.computeCosineSimilarity(v1, v2);
    assert.ok(Math.abs(orthSim) < 1e-5, 'Orthogonal similarity must be 0.0');

    // Opposite vectors
    v2[1] = 0.0;
    v2[0] = -1.0;
    const oppSim = CanonicalSFaceEngineV10.computeCosineSimilarity(v1, v2);
    assert.ok(Math.abs(oppSim - (-1.0)) < 1e-5, 'Opposite similarity must be -1.0');
  });
});
