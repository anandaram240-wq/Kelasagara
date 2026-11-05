// backend/src/tests/mediapipe_routes_integration.test.ts
process.env.ALLOW_DEV_TOKEN = 'true';

import { describe, it, before, beforeEach } from 'node:test';
import assert from 'node:assert';
import express, { Express } from 'express';
import request from 'supertest';
import sharp from 'sharp';
import {
  createFaceBiometricRouter,
  FaceRoutesDependencies,
} from '../routes/face_routes';
import {
  BurstFrameItem,
  FrameAnalyzerAdapter,
} from '../services/challenge_burst_pad_service';
import { KeyEncryptionProvider, BiometricEnvelopeEncryptionService } from '../services/kms_envelope_encryption';

class MockKeyProvider implements KeyEncryptionProvider {
  readonly providerType = 'local_dev' as const;
  readonly defaultKeyResourceName = 'projects/test/locations/global/keyRings/r/cryptoKeys/k1';

  async wrapDek(dek: Buffer, aad: Buffer) {
    return {
      wrappedDek: Buffer.from(dek),
      keyVersion: 'v1',
      kmsKeyResourceName: this.defaultKeyResourceName,
    };
  }

  async unwrapDek(wrappedDek: Buffer, aad: Buffer, keyResourceName: string) {
    return Buffer.from(wrappedDek);
  }
}

class MockFirestore {
  private collections: Map<string, Map<string, any>> = new Map();

  collection(colName: string) {
    if (!this.collections.has(colName)) {
      this.collections.set(colName, new Map());
    }
    const store = this.collections.get(colName)!;
    return {
      doc: (docId: string) => ({
        get: async () => ({
          exists: store.has(docId),
          data: () => store.get(docId),
        }),
        set: async (data: any) => {
          store.set(docId, { ...data });
        },
        update: async (data: any) => {
          const existing = store.get(docId) || {};
          store.set(docId, { ...existing, ...data });
        },
      }),
    };
  }

  async runTransaction(updateFn: (tx: any) => Promise<any>): Promise<any> {
    const tx = {
      get: async (docRef: any) => docRef.get(),
      update: async (docRef: any, data: any) => docRef.update(data),
      set: async (docRef: any, data: any) => docRef.set(data),
    };
    return updateFn(tx);
  }
}

async function createTestJpegBase64(colorVal: number): Promise<string> {
  const buf = await sharp({
    create: {
      width: 160,
      height: 160,
      channels: 3,
      background: { r: colorVal, g: colorVal, b: colorVal },
    },
  })
    .jpeg({ quality: 90 })
    .toBuffer();
  return buf.toString('base64');
}

function makeUnitVector(seed: number): Float32Array {
  const v = new Float32Array(128);
  let sumSq = 0;
  for (let i = 0; i < 128; i++) {
    v[i] = Math.sin(seed + i * 0.1);
    sumSq += v[i] * v[i];
  }
  const norm = Math.sqrt(sumSq);
  for (let i = 0; i < 128; i++) v[i] /= norm;
  return v;
}

describe('MediaPipe 478-Point FaceLandmarker & SFace Integration Routes (Gate G-02, G-03)', () => {
  let app: Express;
  let mockDb: MockFirestore;
  let kmsService: BiometricEnvelopeEncryptionService;
  let testFrames: BurstFrameItem[];
  let genuineEmbedding: Float32Array;
  let impostorEmbedding: Float32Array;

  before(async () => {
    genuineEmbedding = makeUnitVector(1.0);
    impostorEmbedding = makeUnitVector(50.0);

    const f0 = await createTestJpegBase64(100);
    const f1 = await createTestJpegBase64(120);
    const f2 = await createTestJpegBase64(140);

    testFrames = [
      { sequenceIndex: 0, capturedOffsetMs: 0, jpegBase64: f0 },
      { sequenceIndex: 1, capturedOffsetMs: 120, jpegBase64: f1 },
      { sequenceIndex: 2, capturedOffsetMs: 250, jpegBase64: f2 },
    ];
  });

  const setupTestApp = (analyzerOpts?: {
    earTrajectory?: [number, number, number];
    sfaceEmbedding?: Float32Array;
    throwError?: Error;
  }) => {
    mockDb = new MockFirestore();
    kmsService = new BiometricEnvelopeEncryptionService(new MockKeyProvider());

    let frameCallCount = 0;
    const mockAnalyzer: FrameAnalyzerAdapter = {
      analyzeFrame: async () => {
        if (analyzerOpts?.throwError) throw analyzerOpts.throwError;
        const idx = Math.min(frameCallCount++, 2);
        const ears = analyzerOpts?.earTrajectory || [0.28, 0.08, 0.28];
        const ear = ears[idx];
        const emb = analyzerOpts?.sfaceEmbedding || genuineEmbedding;

        return {
          faceCount: 1,
          facePresenceProbability: 0.98,
          interocularDistancePx: 120,
          yawDeg: 1.0,
          pitchDeg: -1.0,
          rollDeg: 0.5,
          meanFaceLuma: 130,
          laplacianSharpness: 350,
          eyeContours: {
            viewerLeftEye: {
              p1: { x: 30, y: 50 }, p2: { x: 40, y: 45 }, p3: { x: 50, y: 45 },
              p4: { x: 60, y: 50 }, p5: { x: 50, y: 55 }, p6: { x: 40, y: 55 },
            },
            viewerRightEye: {
              p1: { x: 100, y: 50 }, p2: { x: 110, y: 45 }, p3: { x: 120, y: 45 },
              p4: { x: 130, y: 50 }, p5: { x: 120, y: 55 }, p6: { x: 110, y: 55 },
            },
          },
          earViewerLeft: ear,
          earViewerRight: ear,
          earBilateralMean: ear,
          sfaceEmbedding128: emb,
        };
      },
    };

    const router = createFaceBiometricRouter({
      db: mockDb as any,
      landmarker: mockAnalyzer as any,
      kmsEncryptionService: kmsService,
    });

    app = express();
    app.use(express.json());
    app.use('/api/biometrics', router);
  };

  it('1. POST /challenge issues 3-frame expected burst ticket', async () => {
    setupTestApp();
    const res = await request(app)
      .post('/api/biometrics/challenge')
      .set('Authorization', 'Bearer dev-mock-token-worker1')
      .send({ purpose: 'verify_1to1' });

    assert.strictEqual(res.status, 200);
    assert.strictEqual(res.body.success, true);
    assert.strictEqual(res.body.status, 'challenge_issued');
    assert.ok(res.body.data.challengeId);
    assert.ok(res.body.data.challengeNonce);
    assert.strictEqual(res.body.data.expectedFrameCount, 3);
  });

  it('2. POST /verify-1to1 strictly rejects single static JPEG payload', async () => {
    setupTestApp();
    const chalRes = await request(app)
      .post('/api/biometrics/challenge')
      .set('Authorization', 'Bearer dev-mock-token-worker1')
      .send({ purpose: 'verify_1to1' });

    const res = await request(app)
      .post('/api/biometrics/verify-1to1')
      .set('Authorization', 'Bearer dev-mock-token-worker1')
      .send({
        challengeId: chalRes.body.data.challengeId,
        nonce: chalRes.body.data.challengeNonce,
        imageBase64: testFrames[0].jpegBase64, // Single image instead of 3-frame burst
      });

    assert.strictEqual(res.status, 400);
    assert.strictEqual(res.body.success, false);
    assert.strictEqual(res.body.error.code, 'SINGLE_OR_INVALID_FRAME_COUNT_REJECTED');
  });

  it('3. Ticket T-01: strictly rejects forbidden client-supplied vector fields', async () => {
    setupTestApp();
    const res = await request(app)
      .post('/api/biometrics/verify-1to1')
      .set('Authorization', 'Bearer dev-mock-token-worker1')
      .send({
        challengeId: 'test_chal',
        nonce: 'test_nonce',
        probeVector: [0.1, 0.2, 0.3], // Forbidden client vector
        frames: testFrames,
      });

    assert.strictEqual(res.status, 400);
    assert.strictEqual(res.body.status, 'client_vectors_forbidden');
    assert.strictEqual(res.body.error.code, 'CLIENT_VECTORS_FORBIDDEN');
  });

  it('4. Rejects out-of-order frame sequences (sequenceIndex)', async () => {
    setupTestApp();
    const chalRes = await request(app)
      .post('/api/biometrics/challenge')
      .set('Authorization', 'Bearer dev-mock-token-worker1')
      .send({ purpose: 'verify_1to1' });

    const outOfOrder = [
      { sequenceIndex: 0, capturedOffsetMs: 0, jpegBase64: testFrames[0].jpegBase64 },
      { sequenceIndex: 2, capturedOffsetMs: 120, jpegBase64: testFrames[1].jpegBase64 },
      { sequenceIndex: 1, capturedOffsetMs: 250, jpegBase64: testFrames[2].jpegBase64 },
    ];

    const res = await request(app)
      .post('/api/biometrics/verify-1to1')
      .set('Authorization', 'Bearer dev-mock-token-worker1')
      .send({
        challengeId: chalRes.body.data.challengeId,
        nonce: chalRes.body.data.challengeNonce,
        frames: outOfOrder,
      });

    assert.strictEqual(res.status, 400);
    assert.strictEqual(res.body.error.code, 'OUT_OF_ORDER_FRAME_SEQUENCE');
  });

  it('5. Rejects degenerate eye contours / invalid liveness as quality_rejected or pad_rejected', async () => {
    setupTestApp({
      throwError: new Error('DEGENERATE_EYE_CONTOUR: palpebral fissure height below minimum threshold'),
    });

    const chalRes = await request(app)
      .post('/api/biometrics/challenge')
      .set('Authorization', 'Bearer dev-mock-token-worker1')
      .send({ purpose: 'verify_1to1' });

    const res = await request(app)
      .post('/api/biometrics/verify-1to1')
      .set('Authorization', 'Bearer dev-mock-token-worker1')
      .send({
        challengeId: chalRes.body.data.challengeId,
        nonce: chalRes.body.data.challengeNonce,
        frames: testFrames,
      });

    assert.strictEqual(res.status, 400);
    assert.ok(
      res.body.error.code.includes('DEGENERATE_EYE_CONTOUR') ||
      res.body.status === 'pad_rejected' ||
      res.body.status === 'quality_rejected'
    );
  });

  it('6. Rejects SFace identity mismatch when blinking passes but probe face does not match enrolled template', async () => {
    // Impostor embedding presented, but eye blink trajectory passes
    setupTestApp({
      earTrajectory: [0.28, 0.08, 0.28], // Valid blink
      sfaceEmbedding: impostorEmbedding, // Impostor face
    });

    // Enroll genuine user in mock vault
    const encrypted = await kmsService.encryptTemplate('worker1', genuineEmbedding);
    await mockDb.collection('biometric_vault').doc('worker1').set(encrypted);

    const chalRes = await request(app)
      .post('/api/biometrics/challenge')
      .set('Authorization', 'Bearer dev-mock-token-worker1')
      .send({ purpose: 'verify_1to1' });

    const res = await request(app)
      .post('/api/biometrics/verify-1to1')
      .set('Authorization', 'Bearer dev-mock-token-worker1')
      .send({
        challengeId: chalRes.body.data.challengeId,
        nonce: chalRes.body.data.challengeNonce,
        frames: testFrames,
      });

    assert.strictEqual(res.status, 200);
    assert.strictEqual(res.body.status, 'mismatch');
    assert.strictEqual(res.body.data.isMatch, false);
    assert.ok(res.body.data.similarity < 0.363);
  });

  it('7. Accepts valid 3-frame burst when both blink trajectory and SFace match enrolled template', async () => {
    setupTestApp({
      earTrajectory: [0.28, 0.08, 0.28], // Valid blink
      sfaceEmbedding: genuineEmbedding, // Genuine face
    });

    const encrypted = await kmsService.encryptTemplate('worker1', genuineEmbedding);
    await mockDb.collection('biometric_vault').doc('worker1').set(encrypted);

    const chalRes = await request(app)
      .post('/api/biometrics/challenge')
      .set('Authorization', 'Bearer dev-mock-token-worker1')
      .send({ purpose: 'verify_1to1' });

    const res = await request(app)
      .post('/api/biometrics/verify-1to1')
      .set('Authorization', 'Bearer dev-mock-token-worker1')
      .send({
        challengeId: chalRes.body.data.challengeId,
        nonce: chalRes.body.data.challengeNonce,
        frames: testFrames,
      });

    assert.strictEqual(res.status, 200);
    assert.strictEqual(res.body.status, 'verified');
    assert.strictEqual(res.body.data.isMatch, true);
    assert.ok(res.body.data.similarity >= 0.363);
  });

  it('8. Rejects challenge replay (Invariant I-05)', async () => {
    setupTestApp({
      earTrajectory: [0.28, 0.08, 0.28],
      sfaceEmbedding: genuineEmbedding,
    });

    const encrypted = await kmsService.encryptTemplate('worker1', genuineEmbedding);
    await mockDb.collection('biometric_vault').doc('worker1').set(encrypted);

    const chalRes = await request(app)
      .post('/api/biometrics/challenge')
      .set('Authorization', 'Bearer dev-mock-token-worker1')
      .send({ purpose: 'verify_1to1' });

    const challengePayload = {
      challengeId: chalRes.body.data.challengeId,
      nonce: chalRes.body.data.challengeNonce,
      frames: testFrames,
    };

    // First attempt succeeds
    const res1 = await request(app)
      .post('/api/biometrics/verify-1to1')
      .set('Authorization', 'Bearer dev-mock-token-worker1')
      .send(challengePayload);
    assert.strictEqual(res1.status, 200);

    // Second attempt with consumed challenge must fail
    const res2 = await request(app)
      .post('/api/biometrics/verify-1to1')
      .set('Authorization', 'Bearer dev-mock-token-worker1')
      .send(challengePayload);
    assert.strictEqual(res2.status, 400);
    assert.strictEqual(res2.body.error.code, 'CHALLENGE_REPLAY_DETECTED');
  });
});
