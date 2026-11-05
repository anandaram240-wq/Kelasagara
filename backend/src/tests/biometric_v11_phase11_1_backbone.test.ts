/**
 * KELASAGARA BIOMETRIC ENGINE V11.0 — PHASE 11.1 TEST SUITE
 * File: backend/src/tests/biometric_v11_phase11_1_backbone.test.ts
 *
 * Run via:
 * npx tsc && node --test dist/tests/biometric_v11_phase11_1_backbone.test.js
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import {
  ARCFACE_CANONICAL_112_LANDMARKS,
  FivePointLandmarks,
  estimateUmeyamaTransformV11,
} from '../biometrics/umeyama_aligner_v11';
import {
  cosineSimilarityV11,
  fuseQualityWeightedCentroidV11,
  l2NormalizeEmbeddingV11,
} from '../biometrics/centroid_fusion_v11';
import {
  ArcFace512SessionPoolV11,
  OnnxInferenceBackendV11,
  RawBurstFrameInputV11,
} from '../biometrics/arcface_512_session_pool_v11';

/**
 * Generates a high-frequency textured synthetic face frame so Laplacian sharpness passes FIQA.
 */
function createTexturedRgbFrame(
  width: number,
  height: number,
  landmarks: FivePointLandmarks,
  seedOffset = 0
): RawBurstFrameInputV11 {
  const pixels = new Uint8Array(width * height * 3);
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const idx = (y * width + x) * 3;
      const checker = ((x + seedOffset) ^ y) & 1 ? 215 : 40;
      const grad = ((x * 7 + y * 13 + seedOffset) % 180) + 30;
      pixels[idx] = checker;
      pixels[idx + 1] = (checker + grad) >> 1;
      pixels[idx + 2] = grad;
    }
  }
  return {
    pixels,
    width,
    height,
    channels: 3,
    landmarks,
  };
}

function createDeterministicVector(dim: 128 | 512, identitySeed: number, noise = 0): Float32Array {
  const vec = new Float32Array(dim);
  for (let i = 0; i < dim; i++) {
    let h = (identitySeed * 15485863 + i * 2038074743) | 0;
    h = Math.imul(h ^ (h >>> 16), 2246822507);
    h = Math.imul(h ^ (h >>> 13), 3266489909);
    const baseVal = ((h >>> 0) / 4294967296) * 2 - 1;
    vec[i] = baseVal + noise * Math.cos(i * 1.9);
  }
  return l2NormalizeEmbeddingV11(vec);
}

test('PHASE11.1-A: 5-Point Umeyama Similarity Transform recovers exact scale, rotation, and translation', () => {
  const trueScale = 0.5; // Source landmarks are 2x larger than canonical 112x112
  const trueAngleRad = (12 * Math.PI) / 180; // 12 degrees roll
  const cosA = Math.cos(trueAngleRad);
  const sinA = Math.sin(trueAngleRad);
  const offsetX = 140;
  const offsetY = 95;

  // Map canonical landmarks into unaligned camera coordinates via inverse similarity transform
  const cameraLandmarks = ARCFACE_CANONICAL_112_LANDMARKS.map(([cx, cy]) => {
    const invScale = 1.0 / trueScale;
    const rx = invScale * (cosA * cx + sinA * cy) + offsetX;
    const ry = invScale * (-sinA * cx + cosA * cy) + offsetY;
    return [rx, ry] as const;
  }) as unknown as FivePointLandmarks;

  const result = estimateUmeyamaTransformV11(cameraLandmarks);

  assert.ok(Math.abs(result.scale - trueScale) < 1e-5, `Expected scale ~0.5, got ${result.scale}`);
  assert.ok(
    result.meanResidualPixels < 1e-4,
    `Expected near-zero residual for exact similarity transform, got ${result.meanResidualPixels}`
  );
});

test('PHASE11.1-B: 3-Frame Quality-Weighted Centroid Fusion prunes corrupted outlier frame', () => {
  const cleanFrame0 = createDeterministicVector(512, 42, 0.02);
  const cleanFrame1 = createDeterministicVector(512, 42, -0.02);
  const corruptedBlinkOutlier = createDeterministicVector(512, 999, 0.0); // Orthogonal impostor/corrupted vector

  const fusion = fuseQualityWeightedCentroidV11([
    { frameIndex: 0, embedding: cleanFrame0, qualityWeight: 0.92 },
    { frameIndex: 1, embedding: cleanFrame1, qualityWeight: 0.85 },
    { frameIndex: 2, embedding: corruptedBlinkOutlier, qualityWeight: 0.41 },
  ]);

  assert.equal(fusion.dimension, 512);
  assert.deepEqual(fusion.retainedFrameIndices, [0, 1]);
  assert.deepEqual(fusion.droppedOutlierIndices, [2]);
  assert.ok(fusion.intraBurstMinCosine > 0.98);

  // Verify unit L2 norm of fused centroid
  let normSq = 0;
  for (let i = 0; i < 512; i++) normSq += fusion.centroid[i] * fusion.centroid[i];
  assert.ok(Math.abs(Math.sqrt(normSq) - 1.0) < 1e-5);
});

test('PHASE11.1-C: 512-D Session Pool executes 3-frame burst and transparently upgrades V10 128-D vault record on 1:1 eKYC', async () => {
  const workerIdentity512 = createDeterministicVector(512, 108, 0.0);
  const workerIdentity128 = createDeterministicVector(128, 108, 0.0);

  let callCount512 = 0;
  const mockBackend: OnnxInferenceBackendV11 = {
    async run512D() {
      callCount512++;
      return createDeterministicVector(512, 108, callCount512 * 0.01);
    },
    async run128DLegacy() {
      return createDeterministicVector(128, 108, 0.01);
    },
  };

  const pool = new ArcFace512SessionPoolV11(mockBackend, { poolSize: 2 });
  assert.equal(pool.sessionOptions.enableCpuMemArena, false);

  const burstFrames: RawBurstFrameInputV11[] = [
    createTexturedRgbFrame(256, 256, ARCFACE_CANONICAL_112_LANDMARKS, 1),
    createTexturedRgbFrame(256, 256, ARCFACE_CANONICAL_112_LANDMARKS, 2),
    createTexturedRgbFrame(256, 256, ARCFACE_CANONICAL_112_LANDMARKS, 3),
  ];

  // 1. Verify against legacy V10 (128-D) stored record
  const v10VerifyOutcome = await pool.verifyWithBackwardCompatibility(
    {
      uid: 'worker_ks_001',
      faceId: 'FACE_V10_001',
      lockToken: 'KS_FTOK_V10_LOCKED',
      modelVersion: 'v10_sface_128',
      embedding: workerIdentity128,
    },
    burstFrames
  );

  assert.equal(v10VerifyOutcome.verified, true);
  assert.equal(v10VerifyOutcome.evaluatedModelVersion, 'v10_sface_128');
  assert.equal(v10VerifyOutcome.shouldUpgradeVaultToV11, true);
  assert.ok(v10VerifyOutcome.upgradedV11Centroid instanceof Float32Array);
  assert.equal(v10VerifyOutcome.upgradedV11Centroid?.length, 512);

  // 2. Verify against upgraded V11 (512-D) stored record
  const v11VerifyOutcome = await pool.verifyWithBackwardCompatibility(
    {
      uid: 'worker_ks_001',
      faceId: 'FACE_V11_001',
      lockToken: 'KS_FTOK_V10_LOCKED',
      modelVersion: 'v11_adaface_512',
      embedding: v10VerifyOutcome.upgradedV11Centroid!,
    },
    burstFrames
  );

  assert.equal(v11VerifyOutcome.verified, true);
  assert.equal(v11VerifyOutcome.evaluatedModelVersion, 'v11_adaface_512');
  assert.equal(v11VerifyOutcome.shouldUpgradeVaultToV11, false);
  assert.ok(
    cosineSimilarityV11(v10VerifyOutcome.upgradedV11Centroid!, workerIdentity512) > 0.99
  );
});
