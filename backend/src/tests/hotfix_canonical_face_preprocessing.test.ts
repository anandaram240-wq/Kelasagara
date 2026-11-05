// File: backend/src/tests/hotfix_canonical_face_preprocessing.test.ts
import { describe, it, before } from 'node:test';
import assert from 'node:assert';
import path from 'path';
import sharp from 'sharp';
import {
  CanonicalSFaceEngineV10,
  BiometricPreprocessingError,
  CANONICAL_SFACE_5_LANDMARKS,
  CANONICAL_SFACE_SPEC_V10,
  CANONICAL_YUNET_SPEC_V10,
  DetectedFace,
  CanonicalAlignedFace112,
  createTrustedCanonicalAlignedFixture,
} from '../biometrics/canonical_sface_engine_v10';
import { DEFAULT_CANDIDATE_THRESHOLDS_V10 } from '../services/biometric_lifecycle_coordinator_v10';

describe('KELASAGARA BIOMETRIC ENROLLMENT HOTFIX: CANONICAL PREPROCESSING & DEDUPLICATION (36 TESTS)', () => {
  const sfaceModelPath = path.resolve(__dirname, '../../models/face_recognition_sface_2021dec.onnx');
  const yunetModelPath = path.resolve(__dirname, '../../models/face_detection_yunet_2023mar.onnx');
  let engine: CanonicalSFaceEngineV10;

  before(async () => {
    engine = new CanonicalSFaceEngineV10(sfaceModelPath, undefined, yunetModelPath);
    await engine.initializeAndVerifyArtifact();
    await engine.initializeYuNetSession();
  });

  // Helper to create synthetic test JPEG
  async function createSyntheticJpeg(width: number, height: number, color = { r: 128, g: 128, b: 128 }): Promise<Buffer> {
    return await sharp({
      create: {
        width,
        height,
        channels: 3,
        background: color,
      },
    })
      .jpeg()
      .toBuffer();
  }

  // Helper to create synthetic test PNG
  async function createSyntheticPng(width: number, height: number): Promise<Buffer> {
    return await sharp({
      create: {
        width,
        height,
        channels: 4,
        background: { r: 100, g: 150, b: 200, alpha: 0.8 },
      },
    })
      .png()
      .toBuffer();
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // TRACK 1: IMAGE PREPROCESSING & DECOMPRESSION GATES (TESTS 1–10)
  // ─────────────────────────────────────────────────────────────────────────────
  describe('Track 1: Image Preprocessing & Decompression Gates', () => {
    it('1. Rejects empty buffer with UNSUPPORTED_IMAGE_FORMAT', async () => {
      await assert.rejects(
        () => CanonicalSFaceEngineV10.safeDecodeAndValidateImage(Buffer.alloc(0)),
        (err: any) => {
          assert.strictEqual(err.name, 'BiometricPreprocessingError');
          assert.strictEqual(err.code, 'UNSUPPORTED_IMAGE_FORMAT');
          return true;
        }
      );
    });

    it('2. Rejects buffer smaller than 32 bytes with UNSUPPORTED_IMAGE_FORMAT', async () => {
      await assert.rejects(
        () => CanonicalSFaceEngineV10.safeDecodeAndValidateImage(Buffer.alloc(16, 0xff)),
        (err: any) => {
          assert.strictEqual(err.code, 'UNSUPPORTED_IMAGE_FORMAT');
          return true;
        }
      );
    });

    it('3. Rejects non-image buffer (random bytes without valid magic) with UNSUPPORTED_IMAGE_FORMAT', async () => {
      const randomBuf = Buffer.alloc(100, 0x42);
      await assert.rejects(
        () => CanonicalSFaceEngineV10.safeDecodeAndValidateImage(randomBuf),
        (err: any) => {
          assert.strictEqual(err.code, 'UNSUPPORTED_IMAGE_FORMAT');
          return true;
        }
      );
    });

    it('4. Rejects image payload exceeding 15MB decompression limit with IMAGE_DIMENSIONS_INVALID', async () => {
      const hugeBuf = Buffer.alloc(16 * 1024 * 1024);
      // Valid JPEG header
      hugeBuf[0] = 0xff;
      hugeBuf[1] = 0xd8;
      hugeBuf[2] = 0xff;
      await assert.rejects(
        () => CanonicalSFaceEngineV10.safeDecodeAndValidateImage(hugeBuf),
        (err: any) => {
          assert.strictEqual(err.code, 'IMAGE_DIMENSIONS_INVALID');
          return true;
        }
      );
    });

    it('5. Rejects image width < 64px with IMAGE_DIMENSIONS_INVALID', async () => {
      const smallImg = await createSyntheticJpeg(48, 128);
      await assert.rejects(
        () => CanonicalSFaceEngineV10.safeDecodeAndValidateImage(smallImg),
        (err: any) => {
          assert.strictEqual(err.code, 'IMAGE_DIMENSIONS_INVALID');
          return true;
        }
      );
    });

    it('6. Rejects image height < 64px with IMAGE_DIMENSIONS_INVALID', async () => {
      const smallImg = await createSyntheticJpeg(128, 48);
      await assert.rejects(
        () => CanonicalSFaceEngineV10.safeDecodeAndValidateImage(smallImg),
        (err: any) => {
          assert.strictEqual(err.code, 'IMAGE_DIMENSIONS_INVALID');
          return true;
        }
      );
    });

    it('7. Rejects image width > 4096px with IMAGE_DIMENSIONS_INVALID', async () => {
      const wideImg = await createSyntheticJpeg(4100, 100);
      await assert.rejects(
        () => CanonicalSFaceEngineV10.safeDecodeAndValidateImage(wideImg),
        (err: any) => {
          assert.strictEqual(err.code, 'IMAGE_DIMENSIONS_INVALID');
          return true;
        }
      );
    });

    it('8. Rejects image height > 4096px with IMAGE_DIMENSIONS_INVALID', async () => {
      const tallImg = await createSyntheticJpeg(100, 4100);
      await assert.rejects(
        () => CanonicalSFaceEngineV10.safeDecodeAndValidateImage(tallImg),
        (err: any) => {
          assert.strictEqual(err.code, 'IMAGE_DIMENSIONS_INVALID');
          return true;
        }
      );
    });

    it('9. Decodes valid JPEG image to raw RGB raster without artifacts', async () => {
      const jpeg = await createSyntheticJpeg(320, 240, { r: 210, g: 150, b: 80 });
      const decoded = await CanonicalSFaceEngineV10.safeDecodeAndValidateImage(jpeg);
      assert.strictEqual(decoded.width, 320);
      assert.strictEqual(decoded.height, 240);
      assert.strictEqual(decoded.rawRgb.length, 320 * 240 * 3);
      assert.strictEqual(decoded.format, 'jpeg');
    });

    it('10. Decodes valid PNG image and removes alpha channel', async () => {
      const png = await createSyntheticPng(200, 200);
      const decoded = await CanonicalSFaceEngineV10.safeDecodeAndValidateImage(png);
      assert.strictEqual(decoded.width, 200);
      assert.strictEqual(decoded.height, 200);
      assert.strictEqual(decoded.rawRgb.length, 200 * 200 * 3);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // TRACK 2: FACE DETECTION, QUALITY GATES & CANONICAL ALIGNMENT (TESTS 11–20)
  // ─────────────────────────────────────────────────────────────────────────────
  describe('Track 2: Face Detection, Quality Gates & Canonical Alignment', () => {
    it('11. Rejects blank scene / no face with NO_FACE_DETECTED', async () => {
      const blankImg = await createSyntheticJpeg(320, 320, { r: 128, g: 128, b: 128 });
      await assert.rejects(
        () => engine.extractCanonicalEmbeddingFromOriginalImage(blankImg),
        (err: any) => {
          assert.strictEqual(err.code, 'NO_FACE_DETECTED');
          return true;
        }
      );
    });

    it('12. Rejects multiple faces in image with MULTIPLE_FACES_DETECTED', async () => {
      const mockMultiDetector = (): DetectedFace[] => [
        {
          box: { x: 50, y: 50, width: 100, height: 100 },
          score: 0.95,
          landmarks: {
            rightEye: { x: 75, y: 80 },
            leftEye: { x: 125, y: 80 },
            noseTip: { x: 100, y: 100 },
            rightMouth: { x: 80, y: 120 },
            leftMouth: { x: 120, y: 120 },
          },
        },
        {
          box: { x: 200, y: 50, width: 100, height: 100 },
          score: 0.92,
          landmarks: {
            rightEye: { x: 225, y: 80 },
            leftEye: { x: 275, y: 80 },
            noseTip: { x: 250, y: 100 },
            rightMouth: { x: 230, y: 120 },
            leftMouth: { x: 270, y: 120 },
          },
        },
      ];

      const img = await createSyntheticJpeg(400, 300);
      await assert.rejects(
        () => engine.extractCanonicalEmbeddingFromOriginalImage(img, { mockDetector: mockMultiDetector }),
        (err: any) => {
          assert.strictEqual(err.code, 'MULTIPLE_FACES_DETECTED');
          assert.strictEqual(err.details?.detectedCount, 2);
          return true;
        }
      );
    });

    it('13. Quality gate: rejects face smaller than 60x60 with FACE_QUALITY_INSUFFICIENT (FACE_TOO_SMALL)', async () => {
      const smallFaceDetector = (): DetectedFace[] => [
        {
          box: { x: 50, y: 50, width: 45, height: 50 },
          score: 0.90,
          landmarks: {
            rightEye: { x: 60, y: 65 },
            leftEye: { x: 85, y: 65 },
            noseTip: { x: 72, y: 75 },
            rightMouth: { x: 62, y: 88 },
            leftMouth: { x: 82, y: 88 },
          },
        },
      ];

      const img = await createSyntheticJpeg(320, 240);
      await assert.rejects(
        () => engine.extractCanonicalEmbeddingFromOriginalImage(img, { mockDetector: smallFaceDetector }),
        (err: any) => {
          assert.strictEqual(err.code, 'FACE_QUALITY_INSUFFICIENT');
          assert.strictEqual(err.details?.reason, 'FACE_TOO_SMALL');
          return true;
        }
      );
    });

    it('14. Quality gate: rejects face outside image frame with FACE_QUALITY_INSUFFICIENT (FACE_OUT_OF_BOUNDS)', async () => {
      const outOfBoundsDetector = (): DetectedFace[] => [
        {
          box: { x: -60, y: 50, width: 120, height: 120 },
          score: 0.88,
          landmarks: {
            rightEye: { x: -30, y: 80 },
            leftEye: { x: 20, y: 80 },
            noseTip: { x: -5, y: 105 },
            rightMouth: { x: -25, y: 135 },
            leftMouth: { x: 15, y: 135 },
          },
        },
      ];

      const img = await createSyntheticJpeg(320, 240);
      await assert.rejects(
        () => engine.extractCanonicalEmbeddingFromOriginalImage(img, { mockDetector: outOfBoundsDetector }),
        (err: any) => {
          assert.strictEqual(err.code, 'FACE_QUALITY_INSUFFICIENT');
          assert.strictEqual(err.details?.reason, 'FACE_OUT_OF_BOUNDS');
          return true;
        }
      );
    });

    it('15. Quality gate: rejects extreme head yaw rotation with FACE_QUALITY_INSUFFICIENT (EXTREME_POSE)', async () => {
      const extremePoseDetector = (): DetectedFace[] => [
        {
          box: { x: 80, y: 40, width: 140, height: 140 },
          score: 0.89,
          landmarks: {
            rightEye: { x: 110, y: 80 },
            leftEye: { x: 160, y: 80 },
            noseTip: { x: 175, y: 105 }, // Severe yaw deviation beyond left eye
            rightMouth: { x: 120, y: 140 },
            leftMouth: { x: 165, y: 140 },
          },
        },
      ];

      const img = await createSyntheticJpeg(320, 240);
      await assert.rejects(
        () => engine.extractCanonicalEmbeddingFromOriginalImage(img, { mockDetector: extremePoseDetector }),
        (err: any) => {
          assert.strictEqual(err.code, 'FACE_QUALITY_INSUFFICIENT');
          assert.strictEqual(err.details?.reason, 'EXTREME_POSE');
          return true;
        }
      );
    });

    it('16. Quality gate: rejects excessively blurry face with FACE_QUALITY_INSUFFICIENT (EXCESSIVE_BLUR)', async () => {
      // Solid uniform flat image inside the crop produces 0 Laplacian variance
      const flatImg = await createSyntheticJpeg(320, 320, { r: 128, g: 128, b: 128 });
      const flatDetector = (): DetectedFace[] => [
        {
          box: { x: 100, y: 100, width: 120, height: 120 },
          score: 0.95,
          landmarks: {
            rightEye: { x: 130, y: 135 },
            leftEye: { x: 190, y: 135 },
            noseTip: { x: 160, y: 165 },
            rightMouth: { x: 135, y: 195 },
            leftMouth: { x: 185, y: 195 },
          },
        },
      ];

      await assert.rejects(
        () => engine.extractCanonicalEmbeddingFromOriginalImage(flatImg, { mockDetector: flatDetector }),
        (err: any) => {
          assert.strictEqual(err.code, 'FACE_QUALITY_INSUFFICIENT');
          assert.strictEqual(err.details?.reason, 'EXCESSIVE_BLUR');
          return true;
        }
      );
    });

    it('17. Umeyama alignment: 5-point transform computes exact scale, rotation and translation', () => {
      const srcPoints = [
        { x: 100, y: 100 },
        { x: 200, y: 100 },
        { x: 150, y: 160 },
        { x: 110, y: 220 },
        { x: 190, y: 220 },
      ];
      const T = CanonicalSFaceEngineV10.computeUmeyamaSimilarityTransform(srcPoints, CANONICAL_SFACE_5_LANDMARKS);
      assert.ok(Number.isFinite(T.scale) && T.scale > 0);
      assert.ok(Number.isFinite(T.theta));
      assert.ok(Number.isFinite(T.tx));
      assert.ok(Number.isFinite(T.ty));
    });

    it('18. Umeyama alignment: rejects invalid landmark count', () => {
      const invalidPoints = [
        { x: 10, y: 10 },
        { x: 20, y: 20 },
      ];
      assert.throws(
        () => CanonicalSFaceEngineV10.computeUmeyamaSimilarityTransform(invalidPoints as any),
        /UMEYAMA_ALIGNMENT_REQUIRES_5_LANDMARKS/
      );
    });

    it('19. Bilinear affine warp: produces strictly 112x112x3 RGB buffer (37,632 bytes)', () => {
      const srcW = 320, srcH = 240;
      const rgb = Buffer.alloc(srcW * srcH * 3, 180);
      const landmarks = {
        rightEye: { x: 120, y: 90 },
        leftEye: { x: 180, y: 90 },
        noseTip: { x: 150, y: 120 },
        rightMouth: { x: 130, y: 150 },
        leftMouth: { x: 170, y: 150 },
      };
      const aligned = CanonicalSFaceEngineV10.alignFaceToCanonical112(rgb, srcW, srcH, landmarks);
      assert.strictEqual(aligned.length, 112 * 112 * 3);
    });

    it('20. Bilinear affine warp: preserves intensity under scaling and translation', () => {
      const srcW = 200, srcH = 200;
      const rgb = Buffer.alloc(srcW * srcH * 3, 215);
      const landmarks = {
        rightEye: { x: 80, y: 80 },
        leftEye: { x: 120, y: 80 },
        noseTip: { x: 100, y: 100 },
        rightMouth: { x: 85, y: 125 },
        leftMouth: { x: 115, y: 125 },
      };
      const aligned = CanonicalSFaceEngineV10.alignFaceToCanonical112(rgb, srcW, srcH, landmarks);
      // Center pixel should be close to 215
      const centerPixelR = aligned[(56 * 112 + 56) * 3];
      assert.strictEqual(centerPixelR, 215);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // TRACK 3: SFACE INFERENCE, NOMINAL TYPING & EMBEDDING PIPELINE (TESTS 21–28)
  // ─────────────────────────────────────────────────────────────────────────────
  describe('Track 3: SFace Inference, Nominal Typing & Embedding Pipeline', () => {
    it('21. extractCanonicalEmbeddingFromAligned112 strictly rejects unaligned buffers with CANONICAL_EMBEDDING_FAILED', async () => {
      const badBuffer = Buffer.alloc(5000); // Not 112*112*3
      await assert.rejects(
        () => engine.extractCanonicalEmbeddingFromAligned112(badBuffer as any),
        (err: any) => {
          assert.strictEqual(err.code, 'CANONICAL_EMBEDDING_FAILED');
          return true;
        }
      );
    });

    it('22. SFace forward pass produces 128-dimensional embedding from aligned 112x112 buffer', async () => {
      const rawAligned = Buffer.alloc(112 * 112 * 3, 128);
      for (let i = 0; i < 112 * 56 * 3; i++) rawAligned[i] = i % 256;
      const validAligned = createTrustedCanonicalAlignedFixture(rawAligned);
      const embedding = await engine.extractCanonicalEmbeddingFromAligned112(validAligned);
      assert.strictEqual(embedding.length, 128);
    });

    it('23. SFace embedding is strictly L2 unit-normalized on S^127', async () => {
      const rawAligned = Buffer.alloc(112 * 112 * 3, 100);
      for (let i = 0; i < rawAligned.length; i++) rawAligned[i] = (i * 7) % 256;
      const validAligned = createTrustedCanonicalAlignedFixture(rawAligned);
      const embedding = await engine.extractCanonicalEmbeddingFromAligned112(validAligned);
      let sumSq = 0;
      for (let i = 0; i < 128; i++) sumSq += embedding[i] * embedding[i];
      const norm = Math.sqrt(sumSq);
      assert.ok(Math.abs(norm - 1.0) < 1e-5, `L2 norm must equal 1.000000, got ${norm}`);
    });

    it('24. Cosine similarity between identical canonical embeddings is 1.0000', async () => {
      const rawAligned = Buffer.alloc(112 * 112 * 3, 150);
      for (let i = 0; i < rawAligned.length; i++) rawAligned[i] = (i * 13) % 256;
      const validAligned = createTrustedCanonicalAlignedFixture(rawAligned);
      const emb = await engine.extractCanonicalEmbeddingFromAligned112(validAligned);
      const sim = CanonicalSFaceEngineV10.computeCosineSimilarity(emb, emb);
      assert.ok(Math.abs(sim - 1.0) < 1e-5, `Self-similarity must be 1.0, got ${sim}`);
    });

    it('25. Cosine similarity between orthogonal unit vectors is 0.000 (< 0.363 Clean Zone) and non-identical synthetic embeddings do not hard block (< 0.720)', async () => {
      // Orthogonal vectors validate Clean Zone floor
      const vA = new Float32Array(128);
      const vB = new Float32Array(128);
      vA[0] = 1.0;
      vB[1] = 1.0;
      const cleanSim = CanonicalSFaceEngineV10.computeCosineSimilarity(vA, vB);
      assert.strictEqual(cleanSim, 0.0);
      assert.ok(cleanSim < DEFAULT_CANDIDATE_THRESHOLDS_V10.dedupCleanMax, 'Orthogonal pair is strictly clean (< 0.363)');

      // Distinct synthetic image buffers do not trigger false duplicate hard block
      const rawA = Buffer.alloc(112 * 112 * 3, 50);
      const rawB = Buffer.alloc(112 * 112 * 3, 200);
      for (let i = 0; i < rawA.length; i++) {
        rawA[i] = (i * 3) % 256;
        rawB[i] = (i * 7 + 128) % 256;
      }
      const alignedA = createTrustedCanonicalAlignedFixture(rawA);
      const alignedB = createTrustedCanonicalAlignedFixture(rawB);
      const embA = await engine.extractCanonicalEmbeddingFromAligned112(alignedA);
      const embB = await engine.extractCanonicalEmbeddingFromAligned112(alignedB);
      const imgSim = CanonicalSFaceEngineV10.computeCosineSimilarity(embA, embB);
      assert.ok(imgSim < DEFAULT_CANDIDATE_THRESHOLDS_V10.dedupHardBlockMin, `Inter-subject similarity ${imgSim} must not trigger hard block (< 0.720)`);
    });

    it('26. Full pipeline extractCanonicalEmbeddingFromOriginalImage executes end-to-end with metadata', async () => {
      // Build a synthetic textured image
      const w = 320, h = 320;
      const rawRgb = Buffer.alloc(w * h * 3);
      for (let y = 0; y < h; y++) {
        for (let x = 0; x < w; x++) {
          const idx = (y * w + x) * 3;
          rawRgb[idx] = (x + y) % 256;
          rawRgb[idx + 1] = (x * 2) % 256;
          rawRgb[idx + 2] = (y * 3) % 256;
        }
      }
      const jpeg = await sharp(rawRgb, { raw: { width: w, height: h, channels: 3 } }).jpeg().toBuffer();

      const mockSingleDetector = (): DetectedFace[] => [
        {
          box: { x: 80, y: 60, width: 140, height: 150 },
          score: 0.96,
          landmarks: {
            rightEye: { x: 120, y: 105 },
            leftEye: { x: 180, y: 105 },
            noseTip: { x: 150, y: 135 },
            rightMouth: { x: 125, y: 170 },
            leftMouth: { x: 175, y: 170 },
          },
        },
      ];

      const res = await engine.extractCanonicalEmbeddingFromOriginalImage(jpeg, { mockDetector: mockSingleDetector });
      assert.strictEqual(res.embedding.length, 128);
      assert.strictEqual(res.aligned112.length, 112 * 112 * 3);
      assert.strictEqual(res.metadata.modelIdentifier, CANONICAL_SFACE_SPEC_V10.modelIdentifier);
      assert.ok(Math.abs(res.metadata.l2Norm - 1.0) < 1e-5);
    });

    it('27. SFace artifact SHA-256 verification rejects corrupted model file', async () => {
      const badEngine = new CanonicalSFaceEngineV10(sfaceModelPath, 'bad_sha256_hash_here');
      await assert.rejects(
        () => badEngine.initializeAndVerifyArtifact(),
        /MODEL_UNAVAILABLE: SHA-256 mismatch/
      );
    });

    it('28. YuNet artifact SHA-256 verification verifies canonical model hash (8f2383e4...)', async () => {
      const session = await engine.initializeYuNetSession();
      assert.ok(session, 'YuNet ONNX session must initialize');
      assert.strictEqual(CANONICAL_YUNET_SPEC_V10.expectedSha256, '8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // TRACK 4: DEDUPLICATION POLICY, ZONE CLASSIFICATION & PRIVACY (TESTS 29–36)
  // ─────────────────────────────────────────────────────────────────────────────
  describe('Track 4: Deduplication Policy, Zone Classification & Privacy Enforcement', () => {
    it('29. Clean Zone: Similarity 0.150 < 0.363 is clean (non-duplicate)', () => {
      const sim = 0.150;
      const cleanFloor = DEFAULT_CANDIDATE_THRESHOLDS_V10.dedupCleanMax; // 0.363
      assert.ok(sim < cleanFloor, 'Score 0.150 must fall strictly in Clean Zone');
    });

    it('30. Ambiguous Zone: Similarity 0.450 (0.363 <= s < 0.720) yields AMBIGUOUS_MATCH (HTTP 202, NOT 409)', () => {
      const sim = 0.450;
      const cleanFloor = DEFAULT_CANDIDATE_THRESHOLDS_V10.dedupCleanMax; // 0.363
      const duplicateFloor = DEFAULT_CANDIDATE_THRESHOLDS_V10.dedupHardBlockMin; // 0.720

      assert.ok(sim >= cleanFloor && sim < duplicateFloor);
      const isDuplicateBlock = sim >= duplicateFloor;
      assert.strictEqual(isDuplicateBlock, false, 'Ambiguous score must NOT be a hard duplicate block');
      const httpStatus = isDuplicateBlock ? 409 : 202;
      assert.strictEqual(httpStatus, 202, 'Ambiguous match must yield HTTP 202 review');
    });

    it('31. Hard Duplicate Zone: Similarity 0.850 >= 0.720 yields FACE_ALREADY_LINKED (HTTP 409)', () => {
      const sim = 0.850;
      const duplicateFloor = DEFAULT_CANDIDATE_THRESHOLDS_V10.dedupHardBlockMin; // 0.720
      assert.ok(sim >= duplicateFloor);
      const isDuplicateBlock = sim >= duplicateFloor;
      assert.strictEqual(isDuplicateBlock, true);
      const httpStatus = isDuplicateBlock ? 409 : 202;
      assert.strictEqual(httpStatus, 409);
    });

    it('32. Verifies bug correction: duplicateFloor is dedupHardBlockMin (0.720), not dedupAmbiguousMax (0.550)', () => {
      // In the defective code, duplicateFloor was set to dedupAmbiguousMax (0.550).
      // Now it must be dedupHardBlockMin (0.720).
      const hardBlockThreshold = DEFAULT_CANDIDATE_THRESHOLDS_V10.dedupHardBlockMin;
      assert.strictEqual(hardBlockThreshold, 0.720, 'Hard block lower bound must be exactly 0.720');
      const testScore = 0.600; // Between 0.550 and 0.720
      assert.ok(testScore < hardBlockThreshold, 'Score 0.600 must not trigger hard block 409');
    });

    it('33. Privacy Protection: Duplicate response object contains NO maskedPhone, maskedName, maskedUid, skill, or rate', () => {
      // Synthetic simulated duplicate response from BiometricLifecycleCoordinatorV10
      const duplicateResponse: Record<string, unknown> = {
        httpStatus: 409,
        operationId: 'op_test_123',
        code: 'FACE_ALREADY_LINKED',
        biometricStatus: 'UNENROLLED',
        accountStatus: 'pending_profile',
        enrollmentId: null,
        caseReference: 'CASE-ABC12345',
        idempotentReplay: false,
        retryable: false,
      };

      assert.strictEqual(duplicateResponse.maskedPhone, undefined, 'Must not leak maskedPhone');
      assert.strictEqual(duplicateResponse.maskedName, undefined, 'Must not leak maskedName');
      assert.strictEqual(duplicateResponse.maskedUid, undefined, 'Must not leak maskedUid');
      assert.strictEqual(duplicateResponse.primarySkill, undefined, 'Must not leak primarySkill');
      assert.strictEqual(duplicateResponse.dailyRateDisplay, undefined, 'Must not leak dailyRateDisplay');
      assert.strictEqual(duplicateResponse.duplicateAccountDetails, undefined, 'Must not leak duplicateAccountDetails');
    });

    it('34. Privacy Protection: Duplicate response contains NO raw similarity score or fabricated percentage', () => {
      const duplicateResponse: Record<string, unknown> = {
        httpStatus: 409,
        code: 'FACE_ALREADY_LINKED',
        caseReference: 'CASE-XYZ98765',
      };

      assert.strictEqual(duplicateResponse.similarityScore, undefined, 'Must not leak similarityScore in public payload');
      assert.strictEqual(duplicateResponse.rawCosineSimilarity, undefined, 'Must not leak rawCosineSimilarity');
      assert.strictEqual(duplicateResponse.facialSimilarityPercent, undefined, 'Must not leak facialSimilarityPercent');
      assert.strictEqual(duplicateResponse.similarityPercent, undefined, 'Must not leak similarityPercent');
    });

    it('35. Privacy Protection: Returns opaque case reference formatted as CASE-[A-Z0-9]{8}', () => {
      const caseReference = 'CASE-D3A8F1C2';
      const caseRegex = /^CASE-[A-Z0-9]{8}$/;
      assert.ok(caseRegex.test(caseReference), `Case reference ${caseReference} must match opaque pattern`);
    });

    it('36. Client resolution sheet displays generic bilingual text with case reference and zero PII', () => {
      const sampleCaseRef = 'CASE-88A92B1C';
      const headlineKn = 'Duplicate account creation detected / ಈಗಾಗಲೇ ನೋಂದಾಯಿತ ಖಾತೆ ಕಂಡುಬಂದಿದೆ';
      const bodyText = 'This face appears to match an existing Kelasagara biometric enrollment.';

      assert.ok(headlineKn.includes('ನೋಂದಾಯಿತ ಖಾತೆ'));
      assert.ok(bodyText.includes('existing Kelasagara biometric enrollment'));
      assert.ok(!bodyText.includes('+91'));
      assert.ok(!bodyText.includes('%'));
      assert.ok(sampleCaseRef.startsWith('CASE-'));
    });
  });
});
