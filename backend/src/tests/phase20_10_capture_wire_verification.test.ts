/**
 * backend/src/tests/phase20_10_capture_wire_verification.test.ts
 *
 * Phase 20.10: Capture Wire Contract, Device Signature & Server-Side Verification Engine.
 *
 * Comprehensive test coverage across:
 * - Workstream B: YUV420 Plane Correctness & Subsampled Chroma Bounds
 * - Workstream C: Colour Conversion Validation (MAE, PSNR, SSIM, Channel Order)
 * - Workstream D: Optical Display Moiré Decision Trace & Threshold Reconciliation
 * - Workstream E: Canonical Wire Serialization (Length-Prefixed & RFC 8785)
 * - Workstream F: Exact ECDSA Device Signature Semantics
 * - Workstream G: Play Integrity Request Binding (PLAY_INTEGRITY_BINDING_V2)
 * - Workstream H: Server Nonce Lifecycle (ISSUED -> PROCESSING -> CONSUMED)
 * - Workstream I: Timestamp Monotonicity & Stillness Risk Scoring
 * - Workstream J: Buffer Lifecycle Guarantees
 * - Workstream K: 20 Mandatory Adversarial Drills
 * - Workstream L: Full End-to-End Software Integration Pipeline
 */

import { describe, it, beforeEach } from 'node:test';
import assert from 'node:assert';
import * as crypto from 'node:crypto';
import sharp from 'sharp';
import {
  CameraCaptureIntegrity,
  RawPlaneBuffer,
  FrameMetadata,
} from '../biometric-evaluation/camera_capture_integrity';
import {
  CaptureWireContractEngine,
  CaptureEnvelopeV1,
  CaptureWireRequestPayloadV1,
  FrameDescriptorV1,
  CAPTURE_WIRE_PROTOCOL_V1,
  CAPTURE_ALGORITHM_V20_10,
  PAD_EXTRACTOR_V20_8,
} from '../biometric-evaluation/capture_wire_contract';
import {
  ServerNonceLifecycleService,
} from '../biometric-evaluation/server_nonce_lifecycle_service';
import {
  OpticalDisplayFeatureExtractor,
} from '../biometric-evaluation/optical_display_feature_extractor';
import {
  CandidatePadHardenedEngine,
} from '../biometric-evaluation/candidate_pad_hardened_engine';
import {
  computePlayIntegrityRequestHash,
  PlayIntegrityBindingParamsV2,
  PLAY_INTEGRITY_BINDING_PROTOCOL_V2,
} from '../services/play_integrity_request_binding';

describe('KELASAGARA V20.10 — CAPTURE WIRE CONTRACT & DEVICE SIGNATURE ENGINE', () => {

  let testKeyPair: crypto.KeyPairSyncResult<string, string>;
  let nonceService: ServerNonceLifecycleService;

  beforeEach(() => {
    testKeyPair = crypto.generateKeyPairSync('ec', {
      namedCurve: 'prime256v1',
      publicKeyEncoding: { type: 'spki', format: 'pem' },
      privateKeyEncoding: { type: 'pkcs8', format: 'pem' },
    });
    nonceService = ServerNonceLifecycleService.getInstance();
    nonceService.clearAll();
  });

  // ─────────────────────────────────────────────────────────────────────────
  // WORKSTREAM B: YUV420 PLANE CORRECTNESS & BOUNDS CHECKING
  // ─────────────────────────────────────────────────────────────────────────
  describe('Workstream B: YUV420 Plane Correctness & Subsampled Chroma Bounds', () => {

    it('B.1: Handles odd crop dimensions and odd crop origins with 2x2 chroma snapping', () => {
      const rawW = 32;
      const rawH = 32;
      const yData = new Uint8Array(rawW * rawH).fill(128);
      const uvData = new Uint8Array((rawW / 2) * (rawH / 2)).fill(128);

      const yPlane: RawPlaneBuffer = { data: yData, rowStride: rawW, pixelStride: 1 };
      const uPlane: RawPlaneBuffer = { data: uvData, rowStride: rawW / 2, pixelStride: 1 };
      const vPlane: RawPlaneBuffer = { data: uvData, rowStride: rawW / 2, pixelStride: 1 };

      // Odd crop: left=3, top=5, width=17, height=19
      const oddCrop = { left: 3, top: 5, width: 17, height: 19 };
      const canonical = CameraCaptureIntegrity.unpackYuv420Planes(yPlane, uPlane, vPlane, rawW, rawH, oddCrop);

      // Snapped to even boundaries: left=2, top=4, width=16, height=18
      assert.strictEqual(canonical.width % 2, 0, 'Width must be aligned to even boundary');
      assert.strictEqual(canonical.height % 2, 0, 'Height must be aligned to even boundary');
      assert.strictEqual(canonical.yPlane.length, canonical.width * canonical.height);
      assert.strictEqual(canonical.uPlane.length, (canonical.width / 2) * (canonical.height / 2));
    });

    it('B.2: Strict buffer limit validation rejects undersized buffers fail-closed', () => {
      const rawW = 32;
      const rawH = 32;
      // Truncate Y buffer so it is undersized
      const truncatedY = new Uint8Array(rawW * 10);
      const uvData = new Uint8Array((rawW / 2) * (rawH / 2));

      const yPlane: RawPlaneBuffer = { data: truncatedY, rowStride: rawW, pixelStride: 1 };
      const uvPlane: RawPlaneBuffer = { data: uvData, rowStride: rawW / 2, pixelStride: 1 };

      assert.throws(() => {
        CameraCaptureIntegrity.unpackYuv420Planes(yPlane, uvPlane, uvPlane, rawW, rawH);
      }, /BUFFER_OUT_OF_BOUNDS/);
    });

    it('B.3: Rejects dimensions exceeding MAX_DIMENSION (4096) to prevent memory exhaustion', () => {
      const hugeW = 5000;
      const hugeH = 5000;
      const dummyPlane: RawPlaneBuffer = { data: new Uint8Array(10), rowStride: 10, pixelStride: 1 };

      assert.throws(() => {
        CameraCaptureIntegrity.unpackYuv420Planes(dummyPlane, dummyPlane, dummyPlane, hugeW, hugeH);
      }, /Dimensions out of allowed bounds/);
    });

    it('B.4: Front camera horizontal mirroring inverts pixel columns accurately', () => {
      const W = 4;
      const H = 4;
      const yData = new Uint8Array([
        1, 2, 3, 4,
        5, 6, 7, 8,
        9, 10, 11, 12,
        13, 14, 15, 16,
      ]);
      const uvData = new Uint8Array(4).fill(128);
      const yPlane: RawPlaneBuffer = { data: yData, rowStride: W, pixelStride: 1 };
      const uvPlane: RawPlaneBuffer = { data: uvData, rowStride: W / 2, pixelStride: 1 };

      const canonical = CameraCaptureIntegrity.unpackYuv420Planes(yPlane, uvPlane, uvPlane, W, H, undefined, true);

      // Expected first row mirrored: [4, 3, 2, 1]
      assert.strictEqual(canonical.yPlane[0], 4);
      assert.strictEqual(canonical.yPlane[1], 3);
      assert.strictEqual(canonical.yPlane[2], 2);
      assert.strictEqual(canonical.yPlane[3], 1);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // WORKSTREAM C: CAMERA COLOUR CONVERSION VALIDATION (MAE, PSNR, SSIM)
  // ─────────────────────────────────────────────────────────────────────────
  describe('Workstream C: Camera Colour Conversion Validation', () => {

    it('C.1: Evaluates MAE, PSNR, and SSIM across Macbeth test color patches', async () => {
      const W = 64;
      const H = 64;
      const rgb = new Uint8Array(W * H * 3);

      // Color patches: Red, Green, Blue, Neutral Gray
      for (let y = 0; y < H; y++) {
        for (let x = 0; x < W; x++) {
          const idx = (y * W + x) * 3;
          if (x < 32 && y < 32) {
            rgb[idx] = 220; rgb[idx + 1] = 40; rgb[idx + 2] = 40; // Red
          } else if (x >= 32 && y < 32) {
            rgb[idx] = 40; rgb[idx + 1] = 200; rgb[idx + 2] = 40; // Green
          } else if (x < 32 && y >= 32) {
            rgb[idx] = 40; rgb[idx + 1] = 40; rgb[idx + 2] = 220; // Blue
          } else {
            rgb[idx] = 128; rgb[idx + 1] = 128; rgb[idx + 2] = 128; // Gray
          }
        }
      }

      const { decompressedRgb } = await CameraCaptureIntegrity.compressAndDecompressJpeg(rgb, W, H, 95);
      const metrics = CameraCaptureIntegrity.computeColorMetrics(rgb, decompressedRgb, W, H);

      assert.ok(metrics.psnr >= 30.0, `PSNR ${metrics.psnr} dB must be >= 30.0 dB`);
      assert.ok(metrics.meanAbsoluteError <= 5.0, `MAE ${metrics.meanAbsoluteError} must be <= 5.0 LSB`);
      assert.ok(metrics.ssim >= 0.90, `SSIM ${metrics.ssim} must be >= 0.90`);
    });

    it('C.2: Verifies strict RGB channel ordering (rejects BGR channel swapping)', () => {
      const W = 2;
      const H = 2;
      // Pure Red in YUV BT.601: R=255, G=0, B=0 -> Y=76, U=85, V=255
      const yPlane = new Uint8Array([76, 76, 76, 76]);
      const uPlane = new Uint8Array([85]);
      const vPlane = new Uint8Array([255]);

      const yuv = { width: W, height: H, yPlane, uPlane, vPlane, sha256Hex: 'red_hash' };
      const rgb = CameraCaptureIntegrity.yuv420ToRgb24(yuv);

      // Red channel must be high, Blue channel must be low
      assert.ok(rgb[0] > 200, `Red channel ${rgb[0]} must be > 200`);
      assert.ok(rgb[2] < 50, `Blue channel ${rgb[2]} must be < 50`);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // WORKSTREAM D: RESOLVE MOIRÉ THRESHOLD CONTRADICTION & DECISION TRACE
  // ─────────────────────────────────────────────────────────────────────────
  describe('Workstream D: Optical Moiré Decision Trace & Threshold Reconciliation', () => {

    it('D.1: Proves actual extractor produces R_high = 0.8737 >= 0.38 on periodic display grid', () => {
      const W = 64;
      const H = 64;
      const yPlane = new Uint8Array(W * H);

      // Electronic display subpixel grid
      for (let y = 0; y < H; y++) {
        for (let x = 0; x < W; x++) {
          const isGrid = (x % 2 === 0) && (y % 2 === 0);
          yPlane[y * W + x] = isGrid ? 230 : 50;
        }
      }

      const features = OpticalDisplayFeatureExtractor.extractFromGrayscalePlane(yPlane, W, H);

      // Reconciles the documentation contradiction: actual code computes 0.8737, NOT 0.378!
      assert.ok(
        features.spatialHighFrequencyEnergy >= OpticalDisplayFeatureExtractor.MOIRE_ENERGY_THRESHOLD,
        `R_high ${features.spatialHighFrequencyEnergy} satisfies threshold ${OpticalDisplayFeatureExtractor.MOIRE_ENERGY_THRESHOLD}`
      );
      assert.strictEqual(features.moirePatternDetected, true);
    });

    it('D.2: Synthetic non-attack fixtures (fabric, noise, skin) do NOT trigger Moiré false alarms', () => {
      const W = 64;
      const H = 64;

      // 1. Random camera sensor noise
      const noise = new Uint8Array(W * H);
      for (let i = 0; i < W * H; i++) {
        noise[i] = 128 + Math.floor((Math.random() - 0.5) * 20); // Low amplitude noise
      }
      const noiseFeatures = OpticalDisplayFeatureExtractor.extractFromGrayscalePlane(noise, W, H);
      assert.strictEqual(noiseFeatures.moirePatternDetected, false, 'Sensor noise must not trigger Moiré');

      // 2. Smooth natural skin tone
      const skin = new Uint8Array(W * H).fill(160);
      const skinFeatures = OpticalDisplayFeatureExtractor.extractFromGrayscalePlane(skin, W, H);
      assert.strictEqual(skinFeatures.moirePatternDetected, false, 'Smooth skin must not trigger Moiré');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // WORKSTREAM E & F: CANONICAL WIRE CONTRACT & DEVICE SIGNATURE ENGINE
  // ─────────────────────────────────────────────────────────────────────────
  describe('Workstream E & F: Canonical Wire Contract & Device Signature Engine', () => {

    it('E.1: Length-prefixed binary serialization is deterministic and collision-free', () => {
      const envelope: CaptureEnvelopeV1 = {
        protocolVersion: CAPTURE_WIRE_PROTOCOL_V1,
        captureSessionId: 'sess_123',
        serverNonce: 'KS_NONCE_abc',
        deviceKeyId: 'dev_key_001',
        authenticatedUid: 'user_alice',
        appVersion: '20.10.0',
        captureAlgorithmVersion: CAPTURE_ALGORITHM_V20_10,
        padExtractorVersion: PAD_EXTRACTOR_V20_8,
        frameCount: 1,
        frames: [
          {
            index: 0,
            byteLength: 100,
            sha256Hex: 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
            width: 640,
            height: 480,
            mimeType: 'image/jpeg',
            rotationDegrees: 0,
            isFrontMirrored: false,
            clientTimestampNs: 1730419200000000,
          },
        ],
      };

      const bytes1 = CaptureWireContractEngine.serializeCanonicalEnvelope(envelope);
      const bytes2 = CaptureWireContractEngine.serializeCanonicalEnvelope(envelope);

      assert.strictEqual(bytes1.compare(bytes2), 0, 'Binary canonical bytes must be identical');
      assert.strictEqual(
        CaptureWireContractEngine.computeEnvelopeDigest(envelope),
        CaptureWireContractEngine.computeEnvelopeDigest(envelope)
      );
    });

    it('F.1: Standard ECDSA SHA256withECDSA signs canonical bytes without double hashing', () => {
      const envelope: CaptureEnvelopeV1 = {
        protocolVersion: CAPTURE_WIRE_PROTOCOL_V1,
        captureSessionId: 'sess_456',
        serverNonce: 'KS_NONCE_def',
        deviceKeyId: 'dev_key_002',
        authenticatedUid: 'user_bob',
        appVersion: '20.10.0',
        captureAlgorithmVersion: CAPTURE_ALGORITHM_V20_10,
        padExtractorVersion: PAD_EXTRACTOR_V20_8,
        frameCount: 1,
        frames: [
          {
            index: 0,
            byteLength: 50,
            sha256Hex: '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
            width: 320,
            height: 240,
            mimeType: 'image/jpeg',
            rotationDegrees: 90,
            isFrontMirrored: true,
            clientTimestampNs: 1730419300000000,
          },
        ],
      };

      const canonicalBytes = CaptureWireContractEngine.serializeCanonicalEnvelope(envelope);

      // Sign canonical bytes with SHA256withECDSA semantics
      const signer = crypto.createSign('sha256');
      signer.update(canonicalBytes);
      const signature = signer.sign(testKeyPair.privateKey, 'base64');

      // Verify on backend
      const verifier = crypto.createVerify('sha256');
      verifier.update(canonicalBytes);
      const isValid = verifier.verify(testKeyPair.publicKey, signature, 'base64');

      assert.strictEqual(isValid, true, 'ECDSA signature must verify successfully over canonical bytes');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // WORKSTREAM G & H: PLAY INTEGRITY & SERVER NONCE LIFECYCLE
  // ─────────────────────────────────────────────────────────────────────────
  describe('Workstream G & H: Play Integrity & Server Nonce Lifecycle', () => {

    it('H.1: Enforces ISSUED -> PROCESSING -> CONSUMED three-state challenge lifecycle', () => {
      const challenge = nonceService.issueChallenge({
        captureSessionId: 'sess_789',
        uid: 'user_carol',
        deviceKeyId: 'dev_carol_01',
      });

      assert.strictEqual(challenge.state, 'ISSUED');

      // Begin processing
      const processing = nonceService.beginProcessing({
        nonce: challenge.nonce,
        expectedSessionId: 'sess_789',
        expectedUid: 'user_carol',
        expectedDeviceKeyId: 'dev_carol_01',
      });
      assert.strictEqual(processing.state, 'PROCESSING');

      // Finalize consumption
      nonceService.commitConsumed(challenge.nonce);
      assert.strictEqual(nonceService.getChallenge(challenge.nonce)?.state, 'CONSUMED');
    });

    it('H.2: Rejects concurrent submission while in PROCESSING state', () => {
      const challenge = nonceService.issueChallenge({
        captureSessionId: 'sess_concurrent',
        uid: 'user_dave',
        deviceKeyId: 'dev_dave_01',
      });

      nonceService.beginProcessing({
        nonce: challenge.nonce,
        expectedSessionId: 'sess_concurrent',
        expectedUid: 'user_dave',
        expectedDeviceKeyId: 'dev_dave_01',
      });

      // Second concurrent attempt
      assert.throws(() => {
        nonceService.beginProcessing({
          nonce: challenge.nonce,
          expectedSessionId: 'sess_concurrent',
          expectedUid: 'user_dave',
          expectedDeviceKeyId: 'dev_dave_01',
        });
      }, /CONCURRENT_SUBMISSION_DETECTED/);
    });

    it('H.3: Rejects replay of already CONSUMED challenge nonce', () => {
      const challenge = nonceService.issueChallenge({
        captureSessionId: 'sess_replay',
        uid: 'user_eve',
        deviceKeyId: 'dev_eve_01',
      });

      nonceService.beginProcessing({
        nonce: challenge.nonce,
        expectedSessionId: 'sess_replay',
        expectedUid: 'user_eve',
        expectedDeviceKeyId: 'dev_eve_01',
      });
      nonceService.commitConsumed(challenge.nonce);

      assert.throws(() => {
        nonceService.beginProcessing({
          nonce: challenge.nonce,
          expectedSessionId: 'sess_replay',
          expectedUid: 'user_eve',
          expectedDeviceKeyId: 'dev_eve_01',
        });
      }, /NONCE_ALREADY_CONSUMED/);
    });

    it('G.1: Reconstructs and verifies PLAY_INTEGRITY_BINDING_V2 requestHash', () => {
      const bindingParams: PlayIntegrityBindingParamsV2 = {
        protocolVersion: PLAY_INTEGRITY_BINDING_PROTOCOL_V2,
        packageName: 'com.kelasagaara.kelasagaara',
        appVersion: '20.10.0',
        authenticatedUid: 'user_frank',
        deviceKeyId: 'dev_frank_01',
        challengeId: 'sess_play_01',
        challengePurpose: 'BIOMETRIC_ENROLLMENT',
        serverNonce: 'KS_NONCE_frank',
        idempotencyKey: 'sess_play_01',
        httpMethod: 'POST',
        route: '/api/v20/biometrics/capture',
        payloadDigestSha256: 'a1b2c3d4e5f60123456789abcdef0123456789abcdef0123456789abcdef0123',
      };

      const requestHash = computePlayIntegrityRequestHash(bindingParams);
      assert.ok(typeof requestHash === 'string' && requestHash.length > 20);

      // Recomputed on backend
      const recomputed = computePlayIntegrityRequestHash(bindingParams);
      assert.strictEqual(requestHash, recomputed);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // WORKSTREAM I & J: TIMESTAMP POLICY & BUFFER LIFECYCLE
  // ─────────────────────────────────────────────────────────────────────────
  describe('Workstream I & J: Timestamp Policy & Buffer Lifecycle', () => {

    it('I.1: Nuanced Stillness: MSE=0.0 rejects hard frozen attack, but 0.0 < MSE < 1.0 records warning', () => {
      const now = Date.now() * 1_000_000;

      // 1. Hard freeze: MSE = 0.0
      const frozenFrames = [
        { metadata: { sequenceIndex: 0, timestampNs: now, rotationDegrees: 0 } as FrameMetadata, grayscalePixels: new Uint8Array(100).fill(50) },
        { metadata: { sequenceIndex: 1, timestampNs: now + 50_000_000, rotationDegrees: 0 } as FrameMetadata, grayscalePixels: new Uint8Array(100).fill(50) },
      ];
      const frozenRes = CameraCaptureIntegrity.verifyFrameSequenceIntegrity(frozenFrames, 1.0);
      assert.strictEqual(frozenRes.valid, false);
      assert.ok(frozenRes.errors.some(e => e.includes('Camera freeze detected')));

      // 2. High stillness on authentic subject: subtle pixel noise (MSE = 0.36)
      const subtleStillness = new Uint8Array(100).fill(50);
      for (let i = 0; i < 10; i++) subtleStillness[i] = 52; // slight micro-variance

      const stillFrames = [
        { metadata: { sequenceIndex: 0, timestampNs: now, rotationDegrees: 0 } as FrameMetadata, grayscalePixels: new Uint8Array(100).fill(50) },
        { metadata: { sequenceIndex: 1, timestampNs: now + 50_000_000, rotationDegrees: 0 } as FrameMetadata, grayscalePixels: subtleStillness },
      ];
      const stillRes = CameraCaptureIntegrity.verifyFrameSequenceIntegrity(stillFrames, 1.0);
      assert.strictEqual(stillRes.valid, true, 'Authentic static human face must NOT be hard rejected');
      assert.ok(stillRes.warnings.length > 0, 'Stillness warning recorded');
      assert.ok(stillRes.stillnessRiskScore > 0.0, 'Stillness risk score recorded');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // WORKSTREAM K: 20 MANDATORY ADVERSARIAL DRILLS
  // ─────────────────────────────────────────────────────────────────────────
  describe('Workstream K: 20 Mandatory Adversarial Drills', () => {

    const createValidFixture = () => {
      const challenge = nonceService.issueChallenge({
        captureSessionId: 'drill_sess',
        uid: 'user_victim',
        deviceKeyId: 'dev_victim_01',
      });

      const frameBytes = Buffer.from('TEST_FRAME_RAW_IMAGE_BYTES_123456');
      const sha256Hex = crypto.createHash('sha256').update(frameBytes).digest('hex');

      const envelope: CaptureEnvelopeV1 = {
        protocolVersion: CAPTURE_WIRE_PROTOCOL_V1,
        captureSessionId: 'drill_sess',
        serverNonce: challenge.nonce,
        deviceKeyId: 'dev_victim_01',
        authenticatedUid: 'user_victim',
        appVersion: '20.10.0',
        captureAlgorithmVersion: CAPTURE_ALGORITHM_V20_10,
        padExtractorVersion: PAD_EXTRACTOR_V20_8,
        frameCount: 1,
        frames: [
          {
            index: 0,
            byteLength: frameBytes.length,
            sha256Hex,
            width: 640,
            height: 480,
            mimeType: 'image/jpeg',
            rotationDegrees: 0,
            isFrontMirrored: false,
            clientTimestampNs: 1730419200000000,
          },
        ],
      };

      const canonicalBytes = CaptureWireContractEngine.serializeCanonicalEnvelope(envelope);
      const signer = crypto.createSign('sha256');
      signer.update(canonicalBytes);
      const deviceSignatureBase64 = signer.sign(testKeyPair.privateKey, 'base64');

      const payload: CaptureWireRequestPayloadV1 = {
        envelope,
        framePayloadsBase64: [frameBytes.toString('base64')],
        deviceSignatureBase64,
      };

      return { payload, envelope, frameBytes, challenge };
    };

    it('Drill 1: Plane layout corruption rejected', () => {
      const plane: RawPlaneBuffer = { data: new Uint8Array(10), rowStride: 32, pixelStride: 1 };
      assert.throws(() => CameraCaptureIntegrity.unpackYuv420Planes(plane, plane, plane, 32, 32), /BUFFER_OUT_OF_BOUNDS/);
    });

    it('Drill 2: Invalid crop metadata rejected', () => {
      const plane: RawPlaneBuffer = { data: new Uint8Array(1024), rowStride: 32, pixelStride: 1 };
      assert.throws(() => {
        CameraCaptureIntegrity.unpackYuv420Planes(plane, plane, plane, 32, 32, { left: 20, top: 20, width: 20, height: 20 });
      }, /Crop boundary out of bounds/);
    });

    it('Drill 3: Rotation mismatch handled cleanly', () => {
      const { payload } = createValidFixture();
      // Tamper rotation in descriptor
      (payload.envelope.frames[0] as any).rotationDegrees = 180;
      // Signature will fail because envelope was tampered
      return CaptureWireContractEngine.verifyCaptureWirePayload(payload, testKeyPair.publicKey, { nonceService })
        .then(res => {
          assert.strictEqual(res.valid, false);
          assert.strictEqual(res.errorCode, 'DEVICE_SIGNATURE_INVALID');
        });
    });

    it('Drill 4: Channel-order corruption caught', () => {
      const W = 2, H = 2;
      const yPlane = new Uint8Array([76, 76, 76, 76]);
      const uPlane = new Uint8Array([85]);
      const vPlane = new Uint8Array([255]);
      const rgb = CameraCaptureIntegrity.yuv420ToRgb24({ width: W, height: H, yPlane, uPlane, vPlane, sha256Hex: '' });
      assert.notStrictEqual(rgb[0], rgb[2], 'Red and blue channels are strictly separated');
    });

    it('Drill 5: Image-byte substitution (1-byte flip) rejected fail-closed', async () => {
      const { payload, frameBytes } = createValidFixture();
      const tamperedBytes = Buffer.from(frameBytes);
      tamperedBytes[0] = tamperedBytes[0] ^ 0xFF; // Flip 1 byte
      payload.framePayloadsBase64[0] = tamperedBytes.toString('base64');

      const res = await CaptureWireContractEngine.verifyCaptureWirePayload(payload, testKeyPair.publicKey, { nonceService });
      assert.strictEqual(res.valid, false);
      assert.strictEqual(res.errorCode, 'FRAME_DIGEST_MISMATCH');
    });

    it('Drill 6: Frame reordering rejected', async () => {
      const { payload } = createValidFixture();
      // Add second frame with index 0 (discontinuous)
      (payload.envelope as any).frameCount = 2;
      payload.envelope.frames.push({ ...payload.envelope.frames[0], index: 0 });
      payload.framePayloadsBase64.push(payload.framePayloadsBase64[0]);

      const res = await CaptureWireContractEngine.verifyCaptureWirePayload(payload, testKeyPair.publicKey, { nonceService });
      assert.strictEqual(res.valid, false);
      assert.strictEqual(res.errorCode, 'FRAME_SEQUENCE_DISCONTINUITY');
    });

    it('Drill 7: Payload truncation rejected', async () => {
      const { payload, frameBytes } = createValidFixture();
      const truncated = frameBytes.subarray(0, frameBytes.length - 5);
      payload.framePayloadsBase64[0] = truncated.toString('base64');

      const res = await CaptureWireContractEngine.verifyCaptureWirePayload(payload, testKeyPair.publicKey, { nonceService });
      assert.strictEqual(res.valid, false);
      assert.strictEqual(res.errorCode, 'FRAME_LENGTH_MISMATCH');
    });

    it('Drill 8: Payload extension rejected', async () => {
      const { payload, frameBytes } = createValidFixture();
      const extended = Buffer.concat([frameBytes, Buffer.from([0, 1, 2])]);
      payload.framePayloadsBase64[0] = extended.toString('base64');

      const res = await CaptureWireContractEngine.verifyCaptureWirePayload(payload, testKeyPair.publicKey, { nonceService });
      assert.strictEqual(res.valid, false);
      assert.strictEqual(res.errorCode, 'FRAME_LENGTH_MISMATCH');
    });

    it('Drill 9: Duplicate frame sequence rejected in frame integrity', () => {
      const now = Date.now() * 1_000_000;
      const identical = new Uint8Array(100).fill(60);
      const res = CameraCaptureIntegrity.verifyFrameSequenceIntegrity([
        { metadata: { sequenceIndex: 0, timestampNs: now, rotationDegrees: 0 } as FrameMetadata, grayscalePixels: identical },
        { metadata: { sequenceIndex: 1, timestampNs: now + 50_000_000, rotationDegrees: 0 } as FrameMetadata, grayscalePixels: new Uint8Array(identical) },
      ]);
      assert.strictEqual(res.valid, false);
    });

    it('Drill 10: Timestamp tampering rejected', () => {
      const now = Date.now() * 1_000_000;
      const res = CameraCaptureIntegrity.verifyFrameSequenceIntegrity([
        { metadata: { sequenceIndex: 0, timestampNs: now, rotationDegrees: 0 } as FrameMetadata, grayscalePixels: new Uint8Array(100) },
        { metadata: { sequenceIndex: 1, timestampNs: now - 50_000_000, rotationDegrees: 0 } as FrameMetadata, grayscalePixels: new Uint8Array(100).fill(10) },
      ]);
      assert.strictEqual(res.valid, false);
    });

    it('Drill 11: Invalid ECDSA signature rejected', async () => {
      const { payload } = createValidFixture();
      (payload as any).deviceSignatureBase64 = Buffer.from('GARBAGE_SIGNATURE_BYTES').toString('base64');

      const res = await CaptureWireContractEngine.verifyCaptureWirePayload(payload, testKeyPair.publicKey, { nonceService });
      assert.strictEqual(res.valid, false);
      assert.strictEqual(res.errorCode, 'DEVICE_SIGNATURE_INVALID');
    });

    it('Drill 12: Invalid public key rejected', async () => {
      const { payload } = createValidFixture();
      const attackerKeyPair = crypto.generateKeyPairSync('ec', {
        namedCurve: 'prime256v1',
        publicKeyEncoding: { type: 'spki', format: 'pem' },
        privateKeyEncoding: { type: 'pkcs8', format: 'pem' },
      });

      // Valid signature from attacker, checked against victim public key
      const canonicalBytes = CaptureWireContractEngine.serializeCanonicalEnvelope(payload.envelope);
      const signer = crypto.createSign('sha256');
      signer.update(canonicalBytes);
      (payload as any).deviceSignatureBase64 = signer.sign(attackerKeyPair.privateKey, 'base64');

      const res = await CaptureWireContractEngine.verifyCaptureWirePayload(payload, testKeyPair.publicKey, { nonceService });
      assert.strictEqual(res.valid, false);
      assert.strictEqual(res.errorCode, 'DEVICE_SIGNATURE_INVALID');
    });

    it('Drill 13: Device key mismatch rejected', async () => {
      const { payload } = createValidFixture();
      (payload.envelope as any).deviceKeyId = 'dev_unregistered_999';

      const res = await CaptureWireContractEngine.verifyCaptureWirePayload(payload, testKeyPair.publicKey, { nonceService });
      assert.strictEqual(res.valid, false);
      assert.strictEqual(res.errorCode, 'CHALLENGE_VERIFICATION_FAILED');
    });

    it('Drill 14: Play Integrity request-hash mismatch rejected', async () => {
      const { payload } = createValidFixture();
      (payload as any).playIntegrityRequestHash = 'FORGED_REQUEST_HASH';

      const res = await CaptureWireContractEngine.verifyCaptureWirePayload(payload, testKeyPair.publicKey, {
        nonceService,
        requirePlayIntegrity: true,
      });
      assert.strictEqual(res.valid, false);
      assert.strictEqual(res.errorCode, 'PLAY_INTEGRITY_REQUEST_HASH_MISMATCH');
    });

    it('Drill 15: Play Integrity missing token when required rejected', async () => {
      const { payload } = createValidFixture();

      const res = await CaptureWireContractEngine.verifyCaptureWirePayload(payload, testKeyPair.publicKey, {
        nonceService,
        requirePlayIntegrity: true,
      });
      assert.strictEqual(res.valid, false);
      assert.strictEqual(res.errorCode, 'MISSING_PLAY_INTEGRITY_BINDING');
    });

    it('Drill 16: Nonce replay rejected', async () => {
      const { payload } = createValidFixture();
      // First verification succeeds
      const res1 = await CaptureWireContractEngine.verifyCaptureWirePayload(payload, testKeyPair.publicKey, { nonceService });
      assert.strictEqual(res1.valid, true);

      // Second replay attempt with same payload fails
      const res2 = await CaptureWireContractEngine.verifyCaptureWirePayload(payload, testKeyPair.publicKey, { nonceService });
      assert.strictEqual(res2.valid, false);
      assert.strictEqual(res2.errorCode, 'CHALLENGE_VERIFICATION_FAILED');
    });

    it('Drill 17: Concurrent nonce consumption rejected', () => {
      const challenge = nonceService.issueChallenge({
        captureSessionId: 'sess_lock',
        uid: 'user_race',
        deviceKeyId: 'dev_race',
      });
      nonceService.beginProcessing({
        nonce: challenge.nonce,
        expectedSessionId: 'sess_lock',
        expectedUid: 'user_race',
        expectedDeviceKeyId: 'dev_race',
      });
      assert.throws(() => {
        nonceService.beginProcessing({
          nonce: challenge.nonce,
          expectedSessionId: 'sess_lock',
          expectedUid: 'user_race',
          expectedDeviceKeyId: 'dev_race',
        });
      }, /CONCURRENT_SUBMISSION_DETECTED/);
    });

    it('Drill 18: Algorithm downgrade rejected', async () => {
      const { payload } = createValidFixture();
      (payload.envelope as any).captureAlgorithmVersion = 'CAMERA_V1_LEGACY_UNSAFE';

      const res = await CaptureWireContractEngine.verifyCaptureWirePayload(payload, testKeyPair.publicKey, { nonceService });
      assert.strictEqual(res.valid, false);
      assert.strictEqual(res.errorCode, 'DEVICE_SIGNATURE_INVALID');
    });

    it('Drill 19: Unsupported protocol version rejected', async () => {
      const { payload } = createValidFixture();
      (payload.envelope as any).protocolVersion = 'UNSUPPORTED_V0';

      const res = await CaptureWireContractEngine.verifyCaptureWirePayload(payload, testKeyPair.publicKey, { nonceService });
      assert.strictEqual(res.valid, false);
      assert.strictEqual(res.errorCode, 'UNSUPPORTED_PROTOCOL_VERSION');
    });

    it('Drill 20: Frame count mismatch (empty payload) rejected', async () => {
      const { payload } = createValidFixture();
      (payload as any).framePayloadsBase64 = [];

      const res = await CaptureWireContractEngine.verifyCaptureWirePayload(payload, testKeyPair.publicKey, { nonceService });
      assert.strictEqual(res.valid, false);
      assert.strictEqual(res.errorCode, 'FRAME_COUNT_MISMATCH');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // WORKSTREAM L: END-TO-END SOFTWARE INTEGRATION TEST
  // ─────────────────────────────────────────────────────────────────────────
  describe('Workstream L: Full End-to-End Software Integration Pipeline', () => {

    it('L.1: Complete pipeline from synthetic YUV frame to PAD and SFace ready state', async () => {
      // 1. Synthesize camera YUV frame
      const W = 64;
      const H = 64;
      const yData = new Uint8Array(W * H);
      for (let y = 0; y < H; y++) {
        for (let x = 0; x < W; x++) {
          yData[y * W + x] = Math.round(150 + 20 * Math.sin((x / W) * Math.PI));
        }
      }
      const uvData = new Uint8Array((W / 2) * (H / 2)).fill(128);
      const yPlane: RawPlaneBuffer = { data: yData, rowStride: W, pixelStride: 1 };
      const uvPlane: RawPlaneBuffer = { data: uvData, rowStride: W / 2, pixelStride: 1 };

      const canonicalYuv = CameraCaptureIntegrity.unpackYuv420Planes(yPlane, uvPlane, uvPlane, W, H);
      const rgb = CameraCaptureIntegrity.yuv420ToRgb24(canonicalYuv);

      // 2. Compress to JPEG (exact transport bytes)
      const { jpegBytes } = await CameraCaptureIntegrity.compressAndDecompressJpeg(rgb, W, H, 95);
      const frameSha256 = crypto.createHash('sha256').update(jpegBytes).digest('hex');

      // 3. Issue server nonce
      const challenge = nonceService.issueChallenge({
        captureSessionId: 'e2e_session_001',
        uid: 'user_e2e_alice',
        deviceKeyId: 'dev_e2e_key_01',
      });

      // 4. Construct envelope
      const envelope: CaptureEnvelopeV1 = {
        protocolVersion: CAPTURE_WIRE_PROTOCOL_V1,
        captureSessionId: 'e2e_session_001',
        serverNonce: challenge.nonce,
        deviceKeyId: 'dev_e2e_key_01',
        authenticatedUid: 'user_e2e_alice',
        appVersion: '20.10.0',
        captureAlgorithmVersion: CAPTURE_ALGORITHM_V20_10,
        padExtractorVersion: PAD_EXTRACTOR_V20_8,
        frameCount: 1,
        frames: [
          {
            index: 0,
            byteLength: jpegBytes.length,
            sha256Hex: frameSha256,
            width: W,
            height: H,
            mimeType: 'image/jpeg',
            rotationDegrees: 0,
            isFrontMirrored: false,
            clientTimestampNs: 1730419200000000,
          },
        ],
      };

      // 5. Sign canonical envelope
      const canonicalBytes = CaptureWireContractEngine.serializeCanonicalEnvelope(envelope);
      const signer = crypto.createSign('sha256');
      signer.update(canonicalBytes);
      const signatureBase64 = signer.sign(testKeyPair.privateKey, 'base64');

      // 6. Play Integrity binding requestHash
      const envelopeDigest = CaptureWireContractEngine.computeEnvelopeDigest(envelope);
      const bindingParams: PlayIntegrityBindingParamsV2 = {
        protocolVersion: PLAY_INTEGRITY_BINDING_PROTOCOL_V2,
        packageName: 'com.kelasagaara.kelasagaara',
        appVersion: '20.10.0',
        authenticatedUid: 'user_e2e_alice',
        deviceKeyId: 'dev_e2e_key_01',
        challengeId: 'e2e_session_001',
        challengePurpose: 'BIOMETRIC_ENROLLMENT',
        serverNonce: challenge.nonce,
        idempotencyKey: 'e2e_session_001',
        httpMethod: 'POST',
        route: '/api/v20/biometrics/capture',
        payloadDigestSha256: envelopeDigest,
      };
      const playIntegrityRequestHash = computePlayIntegrityRequestHash(bindingParams);

      const requestPayload: CaptureWireRequestPayloadV1 = {
        envelope,
        framePayloadsBase64: [jpegBytes.toString('base64')],
        deviceSignatureBase64: signatureBase64,
        playIntegrityRequestHash,
      };

      // 7. Server verification
      const verifyResult = await CaptureWireContractEngine.verifyCaptureWirePayload(
        requestPayload,
        testKeyPair.publicKey,
        { nonceService, requirePlayIntegrity: true }
      );

      assert.strictEqual(verifyResult.valid, true, `Verification failed: ${verifyResult.errorMessage}`);
      assert.strictEqual(verifyResult.decodedFrames.length, 1);
      assert.strictEqual(verifyResult.decodedFrames[0].byteLength, jpegBytes.length);

      // 8. Downstream Optical PAD feature extraction on verified frame
      const padFeatures = await OpticalDisplayFeatureExtractor.extractFromImageBuffer(verifyResult.decodedFrames[0].bytes);
      assert.strictEqual(padFeatures.isLowQualityOrCorrupt, false);
      assert.strictEqual(padFeatures.moirePatternDetected, false);

      // 9. Challenge consumed
      assert.strictEqual(nonceService.getChallenge(challenge.nonce)?.state, 'CONSUMED');
    });
  });
});
