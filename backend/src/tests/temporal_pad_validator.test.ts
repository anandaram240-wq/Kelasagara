// backend/src/tests/temporal_pad_validator.test.ts
import { describe, it } from 'node:test';
import assert from 'node:assert';
import sharp from 'sharp';
import { TemporalPadValidator, BiometricBurstPayload } from '../services/temporal_pad_validator';
import { FaceInferenceService, YuNetDetection } from '../services/face_inference';

async function createSyntheticFaceFrame(options: {
  baseLuma: number;
  eyeOpenHeightPx: number;
  addCheckerboardTexture: boolean;
}): Promise<string> {
  const width = 160;
  const height = 160;
  const buf = Buffer.alloc(width * height, options.baseLuma);

  if (options.addCheckerboardTexture) {
    for (let y = 10; y < 150; y++) {
      for (let x = 10; x < 150; x++) {
        const delta = (x * 3 + y * 5) % 17 - 8;
        buf[y * width + x] = Math.max(0, Math.min(255, options.baseLuma + delta));
      }
    }
  }

  // Draw dark ocular regions around (55, 60) and (105, 60)
  const halfH = Math.max(1, Math.floor(options.eyeOpenHeightPx / 2));
  for (const eyeX of [55, 105]) {
    for (let y = 60 - halfH; y <= 60 + halfH; y++) {
      for (let x = eyeX - 10; x <= eyeX + 10; x++) {
        buf[y * width + x] = 15;
      }
    }
  }

  const jpeg = await sharp(buf, { raw: { width, height, channels: 1 } })
    .jpeg({ quality: 95 })
    .toBuffer();
  return jpeg.toString('base64');
}

describe('TemporalPadValidator (Gate G-02)', () => {
  const mockDetection: YuNetDetection = {
    box: { x: 20, y: 20, width: 120, height: 120 },
    landmarks: {
      leftEye: { x: 55, y: 60 },
      rightEye: { x: 105, y: 60 },
      noseTip: { x: 80, y: 85 },
      mouthLeft: { x: 60, y: 115 },
      mouthRight: { x: 100, y: 115 },
    },
    score: 0.99,
  };

  const baseVector = new Float32Array(128).fill(1 / Math.sqrt(128));

  const createMockInference = (u1: Float32Array, u3: Float32Array): FaceInferenceService => {
    let callCount = 0;
    return {
      detectFaceYuNet: async () => mockDetection,
      alignFace112: async (buf: Buffer) => buf,
      extractEmbeddingFromAligned: async () => {
        callCount++;
        return callCount === 1 ? u1 : u3;
      },
    };
  };

  it('accepts a valid 3-frame blink burst (Open -> Closed -> Open) with stable luma & identity', async () => {
    const f1 = await createSyntheticFaceFrame({ baseLuma: 130, eyeOpenHeightPx: 12, addCheckerboardTexture: true });
    const f2 = await createSyntheticFaceFrame({ baseLuma: 132, eyeOpenHeightPx: 2, addCheckerboardTexture: true });
    const f3 = await createSyntheticFaceFrame({ baseLuma: 129, eyeOpenHeightPx: 12, addCheckerboardTexture: true });

    const payload: BiometricBurstPayload = {
      burstFramesBase64: [f1, f2, f3],
      clientMetadata: {
        interFrameIntervalMs: [105, 110],
        eulerYaw: 1.2,
        eulerPitch: -0.8,
        deviceTimestamp: new Date().toISOString(),
      },
    };

    const res = await TemporalPadValidator.validateBurst(
      payload,
      createMockInference(baseVector, baseVector)
    );

    assert.strictEqual(res.passed, true);
    assert.strictEqual(res.status, 'live_verified');
    assert.ok(Math.abs((res.metrics?.identityContinuityCosine13 || 0) - 1.0) < 0.001);
  });

  it('rejects a static 3-frame replay where Frame 2 shows no ocular compression', async () => {
    const fOpen = await createSyntheticFaceFrame({ baseLuma: 130, eyeOpenHeightPx: 12, addCheckerboardTexture: true });

    const payload: BiometricBurstPayload = {
      burstFramesBase64: [fOpen, fOpen, fOpen],
      clientMetadata: {
        interFrameIntervalMs: [100, 100],
        eulerYaw: 0,
        eulerPitch: 0,
        deviceTimestamp: new Date().toISOString(),
      },
    };

    const res = await TemporalPadValidator.validateBurst(
      payload,
      createMockInference(baseVector, baseVector)
    );

    assert.strictEqual(res.passed, false);
    assert.strictEqual(res.status, 'spoof_detected');
    assert.strictEqual(res.rejectionReason, 'OCULAR_CLOSURE_MISSING');
  });

  it('rejects a burst with artificial screen brightness step-jump (>= 15% luma shift)', async () => {
    const f1 = await createSyntheticFaceFrame({ baseLuma: 100, eyeOpenHeightPx: 12, addCheckerboardTexture: true });
    const f2 = await createSyntheticFaceFrame({ baseLuma: 100, eyeOpenHeightPx: 2, addCheckerboardTexture: true });
    const f3 = await createSyntheticFaceFrame({ baseLuma: 165, eyeOpenHeightPx: 12, addCheckerboardTexture: true });

    const payload: BiometricBurstPayload = {
      burstFramesBase64: [f1, f2, f3],
      clientMetadata: {
        interFrameIntervalMs: [100, 100],
        eulerYaw: 0,
        eulerPitch: 0,
        deviceTimestamp: new Date().toISOString(),
      },
    };

    const res = await TemporalPadValidator.validateBurst(
      payload,
      createMockInference(baseVector, baseVector)
    );

    assert.strictEqual(res.passed, false);
    assert.strictEqual(res.rejectionReason, 'PHOTOMETRIC_STEP_JUMP');
  });

  it('rejects a splice attack where Frame 1 and Frame 3 belong to different identities', async () => {
    const f1 = await createSyntheticFaceFrame({ baseLuma: 130, eyeOpenHeightPx: 12, addCheckerboardTexture: true });
    const f2 = await createSyntheticFaceFrame({ baseLuma: 130, eyeOpenHeightPx: 2, addCheckerboardTexture: true });
    const f3 = await createSyntheticFaceFrame({ baseLuma: 130, eyeOpenHeightPx: 12, addCheckerboardTexture: true });

    const u3Orthogonal = new Float32Array(128).fill(0);
    u3Orthogonal[0] = 1.0;

    const payload: BiometricBurstPayload = {
      burstFramesBase64: [f1, f2, f3],
      clientMetadata: {
        interFrameIntervalMs: [100, 100],
        eulerYaw: 0,
        eulerPitch: 0,
        deviceTimestamp: new Date().toISOString(),
      },
    };

    const res = await TemporalPadValidator.validateBurst(
      payload,
      createMockInference(baseVector, u3Orthogonal)
    );

    assert.strictEqual(res.passed, false);
    assert.strictEqual(res.rejectionReason, 'IDENTITY_DISCONTINUITY');
  });
});
