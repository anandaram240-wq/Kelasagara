/**
 * backend/src/tests/phase20_9_capture_pipeline.test.ts
 *
 * Phase 20.9: Camera Capture Integrity & Hardware Optical Pipeline Verification Suite.
 *
 * Tests:
 * 1. Plane layout unpacking (padded row strides, semi-planar NV12/NV21, crop bounds).
 * 2. Color space conversion parity (BT.601 limited/full range, direct grayscale, Sharp round-trip).
 * 3. Optical signal preservation (periodic high-frequency grid survival across transport).
 * 4. Frame lifecycle and timestamp security (monotonicity, gap detection, anti-freeze).
 * 5. Request payload digest & Play Integrity binding parity (hash determinism, tamper detection).
 */

import { describe, it } from 'node:test';
import assert from 'node:assert';
import {
  CameraCaptureIntegrity,
  RawPlaneBuffer,
  FrameMetadata,
} from '../biometric-evaluation/camera_capture_integrity';
import { OpticalDisplayFeatureExtractor } from '../biometric-evaluation/optical_display_feature_extractor';

describe('KELASAGARA V20.9 — CAMERA CAPTURE INTEGRITY & OPTICAL BENCH SUITE', () => {

  // ─────────────────────────────────────────────────────────────────────────
  // SUITE 1: HARDWARE-INDEPENDENT PLANE LAYOUT UNPACKING
  // ─────────────────────────────────────────────────────────────────────────
  describe('Suite 1: Hardware-Independent Plane Layout Unpacking', () => {

    it('1.1: Unpacks padded row strides (stride > width) without row slippage', () => {
      const W = 4;
      const H = 4;
      const rowStride = 8; // 4 padding bytes per row (e.g. Qualcomm 64-byte alignment)

      // Y plane with rowStride 8
      const yData = new Uint8Array(H * rowStride);
      for (let r = 0; r < H; r++) {
        for (let c = 0; c < W; c++) {
          yData[r * rowStride + c] = (r + 1) * 10 + c; // Distinct value per pixel
        }
        for (let p = W; p < rowStride; p++) {
          yData[r * rowStride + p] = 0xFF; // Padding garbage
        }
      }

      // Chroma planes
      const halfW = W / 2;
      const halfH = H / 2;
      const uvStride = 4;
      const uData = new Uint8Array(halfH * uvStride);
      const vData = new Uint8Array(halfH * uvStride);

      const yPlane: RawPlaneBuffer = { data: yData, rowStride, pixelStride: 1 };
      const uPlane: RawPlaneBuffer = { data: uData, rowStride: uvStride, pixelStride: 1 };
      const vPlane: RawPlaneBuffer = { data: vData, rowStride: uvStride, pixelStride: 1 };

      const canonical = CameraCaptureIntegrity.unpackYuv420Planes(yPlane, uPlane, vPlane, W, H);

      assert.strictEqual(canonical.width, W);
      assert.strictEqual(canonical.height, H);
      assert.strictEqual(canonical.yPlane.length, W * H);

      // Verify exact pixel contents without padding garbage
      for (let r = 0; r < H; r++) {
        for (let c = 0; c < W; c++) {
          const expected = (r + 1) * 10 + c;
          assert.strictEqual(
            canonical.yPlane[r * W + c],
            expected,
            `Pixel mismatch at row ${r}, col ${c}: expected ${expected}, got ${canonical.yPlane[r * W + c]}`
          );
        }
      }
    });

    it('1.2: Unpacks semi-planar NV12 (pixelStride = 2, U first) correctly', () => {
      const W = 4;
      const H = 4;
      const yData = new Uint8Array(W * H).fill(128);

      const halfW = W / 2;
      const halfH = H / 2;
      const uvData = new Uint8Array(halfW * halfH * 2);

      // Interleave U and V: [U0, V0, U1, V1, ...]
      for (let i = 0; i < halfW * halfH; i++) {
        uvData[i * 2] = 100 + i;     // U
        uvData[i * 2 + 1] = 200 + i; // V
      }

      const yPlane: RawPlaneBuffer = { data: yData, rowStride: W, pixelStride: 1 };
      const uPlane: RawPlaneBuffer = { data: uvData, rowStride: halfW * 2, pixelStride: 2 };
      // V buffer points to offset 1 of interleaved data
      const vPlane: RawPlaneBuffer = { data: uvData.subarray(1), rowStride: halfW * 2, pixelStride: 2 };

      const canonical = CameraCaptureIntegrity.unpackYuv420Planes(yPlane, uPlane, vPlane, W, H);

      for (let i = 0; i < halfW * halfH; i++) {
        assert.strictEqual(canonical.uPlane[i], 100 + i, `U plane index ${i} mismatch`);
        assert.strictEqual(canonical.vPlane[i], 200 + i, `V plane index ${i} mismatch`);
      }
    });

    it('1.3: Unpacks sub-rect crop boundaries accurately', () => {
      const rawW = 8;
      const rawH = 8;
      const yData = new Uint8Array(rawW * rawH);
      for (let r = 0; r < rawH; r++) {
        for (let c = 0; c < rawW; c++) {
          yData[r * rawW + c] = r * 10 + c;
        }
      }

      const halfRawW = rawW / 2;
      const halfRawH = rawH / 2;
      const uData = new Uint8Array(halfRawW * halfRawH).fill(128);
      const vData = new Uint8Array(halfRawW * halfRawH).fill(128);

      const yPlane: RawPlaneBuffer = { data: yData, rowStride: rawW, pixelStride: 1 };
      const uPlane: RawPlaneBuffer = { data: uData, rowStride: halfRawW, pixelStride: 1 };
      const vPlane: RawPlaneBuffer = { data: vData, rowStride: halfRawW, pixelStride: 1 };

      // Crop center 4x4: left=2, top=2, width=4, height=4
      const crop = { left: 2, top: 2, width: 4, height: 4 };
      const canonical = CameraCaptureIntegrity.unpackYuv420Planes(yPlane, uPlane, vPlane, rawW, rawH, crop);

      assert.strictEqual(canonical.width, 4);
      assert.strictEqual(canonical.height, 4);
      for (let r = 0; r < 4; r++) {
        for (let c = 0; c < 4; c++) {
          const expected = (r + 2) * 10 + (c + 2);
          assert.strictEqual(canonical.yPlane[r * 4 + c], expected);
        }
      }
    });

    it('1.4: Rejects out-of-bounds crop rect with typed Error', () => {
      const W = 4;
      const H = 4;
      const yData = new Uint8Array(W * H);
      const uvData = new Uint8Array((W / 2) * (H / 2));
      const plane: RawPlaneBuffer = { data: yData, rowStride: W, pixelStride: 1 };
      const uvPlane: RawPlaneBuffer = { data: uvData, rowStride: W / 2, pixelStride: 1 };

      assert.throws(() => {
        CameraCaptureIntegrity.unpackYuv420Planes(plane, uvPlane, uvPlane, W, H, {
          left: 2,
          top: 2,
          width: 4, // 2 + 4 = 6 > W
          height: 4,
        });
      }, /Crop boundary out of bounds/);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // SUITE 2: COLOR SPACE CONVERSION & SHARP PARITY
  // ─────────────────────────────────────────────────────────────────────────
  describe('Suite 2: Color Space Conversion & Sharp Parity', () => {

    it('2.1: ITU-R BT.601 full-range RGB conversion matches theoretical values', () => {
      const W = 2;
      const H = 2;
      // Pure neutral gray: Y=128, U=128, V=128 -> R=128, G=128, B=128
      const yPlane = new Uint8Array([128, 128, 128, 128]);
      const uPlane = new Uint8Array([128]);
      const vPlane = new Uint8Array([128]);

      const yuv = {
        width: W,
        height: H,
        yPlane,
        uPlane,
        vPlane,
        sha256Hex: 'test_hash',
      };

      const rgb = CameraCaptureIntegrity.yuv420ToRgb24(yuv, 'full');
      assert.strictEqual(rgb.length, W * H * 3);
      for (let i = 0; i < rgb.length; i++) {
        assert.strictEqual(rgb[i], 128, `Byte ${i} expected 128, got ${rgb[i]}`);
      }
    });

    it('2.2: Pure green / skin tone conversion verifies non-neutral chroma channels', () => {
      const W = 2;
      const H = 2;
      // Skin tone approximation: Y=180, U=110, V=145
      const yPlane = new Uint8Array([180, 180, 180, 180]);
      const uPlane = new Uint8Array([110]);
      const vPlane = new Uint8Array([145]);

      const yuv = { width: W, height: H, yPlane, uPlane, vPlane, sha256Hex: 'skin_hash' };
      const rgb = CameraCaptureIntegrity.yuv420ToRgb24(yuv, 'full');

      // Expected:
      // R = 180 + 1.402 * (145 - 128) = 180 + 23.834 = 204
      // G = 180 - 0.344136 * (110 - 128) - 0.714136 * (145 - 128) = 180 + 6.194 - 12.14 = 174
      // B = 180 + 1.772 * (110 - 128) = 180 - 31.896 = 148
      assert.strictEqual(rgb[0], 204, `R value mismatch: got ${rgb[0]}`);
      assert.strictEqual(rgb[1], 174, `G value mismatch: got ${rgb[1]}`);
      assert.strictEqual(rgb[2], 148, `B value mismatch: got ${rgb[2]}`);
    });

    it('2.3: Direct Y-plane extraction produces identical 8-bit luminance grayscale buffer', () => {
      const W = 4;
      const H = 4;
      const yPlane = new Uint8Array([
        10, 20, 30, 40,
        50, 60, 70, 80,
        90, 100, 110, 120,
        130, 140, 150, 160,
      ]);
      const uPlane = new Uint8Array(4).fill(128);
      const vPlane = new Uint8Array(4).fill(128);

      const yuv = { width: W, height: H, yPlane, uPlane, vPlane, sha256Hex: 'gray_hash' };
      const gray = CameraCaptureIntegrity.yuv420ToGrayscale(yuv);

      assert.strictEqual(gray.length, yPlane.length);
      for (let i = 0; i < yPlane.length; i++) {
        assert.strictEqual(gray[i], yPlane[i]);
      }
    });

    it('2.4: Sharp JPEG round-trip achieves high PSNR (> 32 dB) on smooth images', async () => {
      const W = 64;
      const H = 64;
      const rgb = new Uint8Array(W * H * 3);
      for (let y = 0; y < H; y++) {
        for (let x = 0; x < W; x++) {
          const idx = (y * W + x) * 3;
          rgb[idx] = Math.round((x / W) * 200 + 30);
          rgb[idx + 1] = Math.round((y / H) * 180 + 40);
          rgb[idx + 2] = 120;
        }
      }

      const { psnr, jpegBytes } = await CameraCaptureIntegrity.compressAndDecompressJpeg(rgb, W, H, 95);
      assert.ok(jpegBytes.length > 0, 'JPEG bytes should be non-empty');
      assert.ok(psnr >= 32.0, `PSNR ${psnr} dB is lower than target 32.0 dB`);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // SUITE 3: OPTICAL SIGNAL PRESERVATION ACROSS PIPELINE
  // ─────────────────────────────────────────────────────────────────────────
  describe('Suite 3: Optical Signal Preservation Across Pipeline', () => {

    it('3.1: Periodic high-frequency screen grid survives YUV unpacking and JPEG compression', async () => {
      const W = 64;
      const H = 64;
      const yPlane = new Uint8Array(W * H);

      // Synthesize high-frequency display pixel grid
      for (let y = 0; y < H; y++) {
        for (let x = 0; x < W; x++) {
          const isGrid = (x % 2 === 0) && (y % 2 === 0);
          yPlane[y * W + x] = isGrid ? 230 : 50;
        }
      }

      const halfW = W / 2;
      const halfH = H / 2;
      const uPlane = new Uint8Array(halfW * halfH).fill(128);
      const vPlane = new Uint8Array(halfW * halfH).fill(128);

      const yuv = { width: W, height: H, yPlane, uPlane, vPlane, sha256Hex: 'grid_hash' };
      const rgb = CameraCaptureIntegrity.yuv420ToRgb24(yuv);

      // Compress to JPEG and decompress
      const { decompressedRgb } = await CameraCaptureIntegrity.compressAndDecompressJpeg(rgb, W, H, 95);

      // Extract grayscale from decompressed RGB
      const decompressedGray = new Uint8Array(W * H);
      for (let i = 0; i < W * H; i++) {
        decompressedGray[i] = decompressedRgb[i * 3]; // R channel represents Y for neutral UV
      }

      const rawFeatures = OpticalDisplayFeatureExtractor.extractFromGrayscalePlane(yPlane, W, H);
      const postPipelineFeatures = OpticalDisplayFeatureExtractor.extractFromGrayscalePlane(decompressedGray, W, H);

      assert.strictEqual(rawFeatures.moirePatternDetected, true, 'Raw frame must detect Moiré');
      assert.strictEqual(postPipelineFeatures.moirePatternDetected, true, 'Decompressed frame must preserve Moiré detection');
      assert.ok(
        postPipelineFeatures.spatialHighFrequencyEnergy >= 0.25,
        `Post-pipeline high frequency energy ${postPipelineFeatures.spatialHighFrequencyEnergy} should be >= 0.25`
      );
    });

    it('3.2: Smooth natural skin gradient preserves low spectral peakiness after pipeline', async () => {
      const W = 64;
      const H = 64;
      const yPlane = new Uint8Array(W * H);

      for (let y = 0; y < H; y++) {
        for (let x = 0; x < W; x++) {
          yPlane[y * W + x] = Math.round(140 + 20 * Math.sin((x / W) * Math.PI) * Math.cos((y / H) * Math.PI));
        }
      }

      const uPlane = new Uint8Array((W / 2) * (H / 2)).fill(110);
      const vPlane = new Uint8Array((W / 2) * (H / 2)).fill(145);

      const yuv = { width: W, height: H, yPlane, uPlane, vPlane, sha256Hex: 'skin_hash' };
      const rgb = CameraCaptureIntegrity.yuv420ToRgb24(yuv);

      const { decompressedRgb } = await CameraCaptureIntegrity.compressAndDecompressJpeg(rgb, W, H, 90);
      const decompressedGray = new Uint8Array(W * H);
      for (let i = 0; i < W * H; i++) {
        // Standard RGB to grayscale luminance: 0.299R + 0.587G + 0.114B
        decompressedGray[i] = Math.round(
          0.299 * decompressedRgb[i * 3] +
          0.587 * decompressedRgb[i * 3 + 1] +
          0.114 * decompressedRgb[i * 3 + 2]
        );
      }

      const features = OpticalDisplayFeatureExtractor.extractFromGrayscalePlane(decompressedGray, W, H);
      assert.strictEqual(features.moirePatternDetected, false, 'Natural skin must not falsely trigger Moiré');
      assert.ok(
        features.spatialHighFrequencyEnergy <= 0.25,
        `Smooth skin high frequency energy ${features.spatialHighFrequencyEnergy} must remain low`
      );
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // SUITE 4: FRAME LIFECYCLE & ANTI-REPLAY / ANTI-FREEZE SECURITY
  // ─────────────────────────────────────────────────────────────────────────
  describe('Suite 4: Frame Lifecycle & Anti-Replay / Anti-Freeze Security', () => {

    it('4.1: Accepts valid continuous monotonic frame sequence', () => {
      const now = Date.now() * 1_000_000;
      const frames = [
        {
          metadata: { sequenceIndex: 0, timestampNs: now, rotationDegrees: 0 } as FrameMetadata,
          grayscalePixels: new Uint8Array(100).fill(50),
        },
        {
          metadata: { sequenceIndex: 1, timestampNs: now + 66_000_000, rotationDegrees: 0 } as FrameMetadata, // +66ms (~15 fps)
          grayscalePixels: new Uint8Array(100).fill(55), // Natural motion variation
        },
        {
          metadata: { sequenceIndex: 2, timestampNs: now + 132_000_000, rotationDegrees: 0 } as FrameMetadata, // +132ms
          grayscalePixels: new Uint8Array(100).fill(60),
        },
      ];

      const result = CameraCaptureIntegrity.verifyFrameSequenceIntegrity(frames, 1.0);
      assert.strictEqual(result.valid, true);
      assert.strictEqual(result.errors.length, 0);
    });

    it('4.2: Detects and rejects non-monotonic timestamps (dt <= 0)', () => {
      const now = Date.now() * 1_000_000;
      const frames = [
        {
          metadata: { sequenceIndex: 0, timestampNs: now, rotationDegrees: 0 } as FrameMetadata,
          grayscalePixels: new Uint8Array(100).fill(50),
        },
        {
          metadata: { sequenceIndex: 1, timestampNs: now - 1_000_000, rotationDegrees: 0 } as FrameMetadata, // Backwards in time!
          grayscalePixels: new Uint8Array(100).fill(60),
        },
      ];

      const result = CameraCaptureIntegrity.verifyFrameSequenceIntegrity(frames, 1.0);
      assert.strictEqual(result.valid, false);
      assert.ok(result.errors.some(e => e.includes('Timestamp non-monotonic')));
    });

    it('4.3: Detects and rejects sequence index gaps', () => {
      const now = Date.now() * 1_000_000;
      const frames = [
        {
          metadata: { sequenceIndex: 0, timestampNs: now, rotationDegrees: 0 } as FrameMetadata,
          grayscalePixels: new Uint8Array(100).fill(50),
        },
        {
          metadata: { sequenceIndex: 2, timestampNs: now + 50_000_000, rotationDegrees: 0 } as FrameMetadata, // Skipped index 1!
          grayscalePixels: new Uint8Array(100).fill(60),
        },
      ];

      const result = CameraCaptureIntegrity.verifyFrameSequenceIntegrity(frames, 1.0);
      assert.strictEqual(result.valid, false);
      assert.ok(result.errors.some(e => e.includes('Sequence index discontinuity')));
    });

    it('4.4: Detects frozen camera feed (zero inter-frame pixel variance)', () => {
      const now = Date.now() * 1_000_000;
      const identicalPixels = new Uint8Array(100).fill(75);
      const frames = [
        {
          metadata: { sequenceIndex: 0, timestampNs: now, rotationDegrees: 0 } as FrameMetadata,
          grayscalePixels: identicalPixels,
        },
        {
          metadata: { sequenceIndex: 1, timestampNs: now + 50_000_000, rotationDegrees: 0 } as FrameMetadata,
          grayscalePixels: new Uint8Array(identicalPixels), // Exact identical bytes!
        },
      ];

      const result = CameraCaptureIntegrity.verifyFrameSequenceIntegrity(frames, 1.0);
      assert.strictEqual(result.valid, false);
      assert.ok(result.errors.some(e => e.includes('Camera freeze detected')));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // SUITE 5: REQUEST PAYLOAD DIGEST & PLAY INTEGRITY BINDING PARITY
  // ─────────────────────────────────────────────────────────────────────────
  describe('Suite 5: Request Payload Digest & Play Integrity Binding Parity', () => {

    it('5.1: Computes deterministic PLAY_INTEGRITY_BINDING_V2 payload hash', () => {
      const rawPayload = new Uint8Array([1, 2, 3, 4, 5, 6, 7, 8]);
      const sessionNonce = 'KS_NONCE_7f8a9b0c';
      const timestampNs = 1730419200000000;

      const digest1 = CameraCaptureIntegrity.computePlayIntegrityBindingDigest(
        rawPayload,
        sessionNonce,
        timestampNs
      );
      const digest2 = CameraCaptureIntegrity.computePlayIntegrityBindingDigest(
        rawPayload,
        sessionNonce,
        timestampNs
      );

      assert.strictEqual(digest1, digest2);
      assert.strictEqual(digest1.length, 64, 'SHA-256 hex string must be 64 characters');
    });

    it('5.2: Detects 1-bit payload tampering (avalanche effect)', () => {
      const rawPayload1 = new Uint8Array([1, 2, 3, 4, 5, 6, 7, 8]);
      const rawPayload2 = new Uint8Array([1, 2, 3, 4, 5, 6, 7, 9]); // 1 bit flip
      const sessionNonce = 'KS_NONCE_7f8a9b0c';
      const timestampNs = 1730419200000000;

      const digest1 = CameraCaptureIntegrity.computePlayIntegrityBindingDigest(
        rawPayload1,
        sessionNonce,
        timestampNs
      );
      const digest2 = CameraCaptureIntegrity.computePlayIntegrityBindingDigest(
        rawPayload2,
        sessionNonce,
        timestampNs
      );

      assert.notStrictEqual(digest1, digest2);
    });

    it('5.3: Detects session nonce tampering', () => {
      const rawPayload = new Uint8Array([1, 2, 3, 4, 5, 6, 7, 8]);
      const timestampNs = 1730419200000000;

      const digest1 = CameraCaptureIntegrity.computePlayIntegrityBindingDigest(
        rawPayload,
        'KS_NONCE_A',
        timestampNs
      );
      const digest2 = CameraCaptureIntegrity.computePlayIntegrityBindingDigest(
        rawPayload,
        'KS_NONCE_B',
        timestampNs
      );

      assert.notStrictEqual(digest1, digest2);
    });
  });
});
