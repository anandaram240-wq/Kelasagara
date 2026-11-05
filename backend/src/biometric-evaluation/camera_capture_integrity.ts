/**
 * backend/src/biometric-evaluation/camera_capture_integrity.ts
 *
 * Kelasagara V20.10: Camera Capture Integrity & Hardware Optical Pipeline.
 *
 * Provides backend decoding, plane layout normalization, color space conversion,
 * frame integrity verification, color conversion metrics (MAE, PSNR, SSIM),
 * and optical signal preservation checks.
 */

import crypto from 'node:crypto';
import sharp from 'sharp';

export interface RawPlaneBuffer {
  data: Uint8Array;
  rowStride: number;
  pixelStride: number;
}

export interface CropRect {
  left: number;
  top: number;
  width: number;
  height: number;
}

export interface CanonicalYuv420 {
  width: number;
  height: number;
  yPlane: Uint8Array;
  uPlane: Uint8Array;
  vPlane: Uint8Array;
  sha256Hex: string;
}

export interface FrameMetadata {
  sequenceIndex: number;
  timestampNs: number;
  rotationDegrees: number;
  exposureTimeNs?: number;
  iso?: number;
}

export interface ColorConversionMetrics {
  readonly maxAbsoluteError: number;
  readonly meanAbsoluteError: number;
  readonly psnr: number;
  readonly ssim: number;
}

export class CameraCaptureIntegrity {
  public static readonly MAX_DIMENSION = 4096;
  public static readonly MAX_ALLOCATION_BYTES = 25 * 1024 * 1024;

  /**
   * Unpacks raw YUV_420_888 planes into canonical unpadded I420 format.
   * Handles arbitrary row strides (stride > width) and chroma interleaving (NV12 / NV21 / I420).
   * Enforces strict buffer bounds checking and subsampled chroma alignment for odd dimensions.
   */
  public static unpackYuv420Planes(
    yPlane: RawPlaneBuffer,
    uPlane: RawPlaneBuffer,
    vPlane: RawPlaneBuffer,
    rawWidth: number,
    rawHeight: number,
    crop?: CropRect,
    isFrontMirrored: boolean = false
  ): CanonicalYuv420 {
    if (rawWidth < 2 || rawHeight < 2 || rawWidth > this.MAX_DIMENSION || rawHeight > this.MAX_DIMENSION) {
      throw new Error(`Dimensions out of allowed bounds [2..${this.MAX_DIMENSION}]: ${rawWidth}x${rawHeight}`);
    }

    const cropLeftRaw = crop ? crop.left : 0;
    const cropTopRaw = crop ? crop.top : 0;
    const widthRaw = crop ? crop.width : rawWidth;
    const heightRaw = crop ? crop.height : rawHeight;

    if (cropLeftRaw < 0 || cropTopRaw < 0 || cropLeftRaw + widthRaw > rawWidth || cropTopRaw + heightRaw > rawHeight) {
      throw new Error(`Crop boundary out of bounds: [${cropLeftRaw}, ${cropTopRaw}, ${widthRaw}, ${heightRaw}] vs [${rawWidth}, ${rawHeight}]`);
    }

    // Subsampled Chroma Alignment: Snap odd crop origins and dimensions to 2x2 chroma boundaries
    const cropLeft = cropLeftRaw % 2 !== 0 ? cropLeftRaw - 1 : cropLeftRaw;
    const cropTop = cropTopRaw % 2 !== 0 ? cropTopRaw - 1 : cropTopRaw;
    let width = widthRaw % 2 !== 0 && widthRaw > 2 ? widthRaw - 1 : widthRaw;
    let height = heightRaw % 2 !== 0 && heightRaw > 2 ? heightRaw - 1 : heightRaw;

    if (width < 2 || height < 2) {
      throw new Error(`Aligned crop dimensions must be >= 2: ${width}x${height}`);
    }

    const totalBytes = width * height + Math.floor(width / 2) * Math.floor(height / 2) * 2;
    if (totalBytes > this.MAX_ALLOCATION_BYTES) {
      throw new Error(`Requested frame exceeds maximum allocation limit of ${this.MAX_ALLOCATION_BYTES} bytes`);
    }

    const yOut = new Uint8Array(width * height);
    const halfW = Math.floor(width / 2);
    const halfH = Math.floor(height / 2);
    const uOut = new Uint8Array(halfW * halfH);
    const vOut = new Uint8Array(halfW * halfH);

    // 1. Unpack Luminance Y with bounds checking
    const yLen = yPlane.data.length;
    for (let row = 0; row < height; row++) {
      const srcOffset = (cropTop + row) * yPlane.rowStride + cropLeft * yPlane.pixelStride;
      const dstOffset = row * width;

      if (yPlane.pixelStride === 1) {
        if (srcOffset + width > yLen) {
          throw new Error(`BUFFER_OUT_OF_BOUNDS: Y-plane offset ${srcOffset + width} > data length ${yLen} at row ${row}`);
        }
        yOut.set(yPlane.data.subarray(srcOffset, srcOffset + width), dstOffset);
      } else {
        for (let col = 0; col < width; col++) {
          const pos = srcOffset + col * yPlane.pixelStride;
          if (pos >= yLen) {
            throw new Error(`BUFFER_OUT_OF_BOUNDS: Y-plane pos ${pos} >= data length ${yLen} at row ${row}, col ${col}`);
          }
          yOut[dstOffset + col] = yPlane.data[pos];
        }
      }
    }

    // 2. Unpack Chroma U and V with subsampled coordinates
    const cropTopHalf = Math.floor(cropTop / 2);
    const cropLeftHalf = Math.floor(cropLeft / 2);
    const uLen = uPlane.data.length;
    const vLen = vPlane.data.length;

    for (let row = 0; row < halfH; row++) {
      const uSrcRow = (cropTopHalf + row) * uPlane.rowStride + cropLeftHalf * uPlane.pixelStride;
      const vSrcRow = (cropTopHalf + row) * vPlane.rowStride + cropLeftHalf * vPlane.pixelStride;
      const dstOffset = row * halfW;

      for (let col = 0; col < halfW; col++) {
        const uPos = uSrcRow + col * uPlane.pixelStride;
        const vPos = vSrcRow + col * vPlane.pixelStride;

        if (uPos >= uLen) {
          throw new Error(`BUFFER_OUT_OF_BOUNDS: U-plane pos ${uPos} >= data length ${uLen} at row ${row}, col ${col}`);
        }
        if (vPos >= vLen) {
          throw new Error(`BUFFER_OUT_OF_BOUNDS: V-plane pos ${vPos} >= data length ${vLen} at row ${row}, col ${col}`);
        }

        uOut[dstOffset + col] = uPlane.data[uPos];
        vOut[dstOffset + col] = vPlane.data[vSrcRow + col * vPlane.pixelStride];
      }
    }

    // 3. Front-camera horizontal mirroring if requested
    let finalY: Uint8Array = yOut;
    let finalU: Uint8Array = uOut;
    let finalV: Uint8Array = vOut;

    if (isFrontMirrored) {
      finalY = new Uint8Array(this.mirrorHorizontal(yOut, width, height));
      finalU = new Uint8Array(this.mirrorHorizontal(uOut, halfW, halfH));
      finalV = new Uint8Array(this.mirrorHorizontal(vOut, halfW, halfH));
    }

    // SHA-256 of canonical I420 planar memory
    const hasher = crypto.createHash('sha256');
    hasher.update(finalY);
    hasher.update(finalU);
    hasher.update(finalV);
    const sha256Hex = hasher.digest('hex');

    return {
      width,
      height,
      yPlane: finalY,
      uPlane: finalU,
      vPlane: finalV,
      sha256Hex,
    };
  }

  private static mirrorHorizontal(src: Uint8Array, w: number, h: number): Uint8Array {
    const dst = new Uint8Array(w * h);
    for (let y = 0; y < h; y++) {
      const rowOffset = y * w;
      for (let x = 0; x < w; x++) {
        dst[rowOffset + (w - 1 - x)] = src[rowOffset + x];
      }
    }
    return dst;
  }

  /**
   * Converts canonical I420 planar buffers to RGB24 bytes.
   * Full range BT.601:
   * R = Y + 1.402 * (V - 128)
   * G = Y - 0.344136 * (U - 128) - 0.714136 * (V - 128)
   * B = Y + 1.772 * (U - 128)
   */
  public static yuv420ToRgb24(yuv: CanonicalYuv420, range: 'full' | 'limited' = 'full'): Uint8Array {
    const { width, height, yPlane, uPlane, vPlane } = yuv;
    const rgb = new Uint8Array(width * height * 3);
    const halfW = Math.floor(width / 2);
    let outIdx = 0;

    for (let row = 0; row < height; row++) {
      const yRowOffset = row * width;
      const uvRowOffset = Math.floor(row / 2) * halfW;

      for (let col = 0; col < width; col++) {
        let y = yPlane[yRowOffset + col];
        const uvIdx = uvRowOffset + Math.floor(col / 2);
        const u = uPlane[uvIdx] - 128;
        const v = vPlane[uvIdx] - 128;

        let r: number, g: number, b: number;

        if (range === 'limited') {
          // BT.601 Limited range (Y: 16-235, UV: 16-240)
          const c = y - 16;
          const d = u;
          const e = v;
          r = Math.min(255, Math.max(0, (298 * c + 409 * e + 128) >> 8));
          g = Math.min(255, Math.max(0, (298 * c - 100 * d - 208 * e + 128) >> 8));
          b = Math.min(255, Math.max(0, (298 * c + 516 * d + 128) >> 8));
        } else {
          // BT.601 Full range (Y: 0-255, UV: 0-255)
          r = Math.min(255, Math.max(0, Math.round(y + 1.402 * v)));
          g = Math.min(255, Math.max(0, Math.round(y - 0.344136 * u - 0.714136 * v)));
          b = Math.min(255, Math.max(0, Math.round(y + 1.772 * u)));
        }

        rgb[outIdx++] = r;
        rgb[outIdx++] = g;
        rgb[outIdx++] = b;
      }
    }
    return rgb;
  }

  /**
   * Extracts direct grayscale buffer (8-bit luminance Y-plane).
   */
  public static yuv420ToGrayscale(yuv: CanonicalYuv420): Uint8Array {
    return new Uint8Array(yuv.yPlane);
  }

  /**
   * Compresses RGB buffer to JPEG using Sharp and decompresses back to test round-trip fidelity.
   */
  public static async compressAndDecompressJpeg(
    rgbBuffer: Uint8Array,
    width: number,
    height: number,
    quality: number = 90
  ): Promise<{ decompressedRgb: Uint8Array; jpegBytes: Buffer; psnr: number }> {
    const jpegBytes = await sharp(Buffer.from(rgbBuffer), {
      raw: { width, height, channels: 3 },
    })
      .jpeg({ quality })
      .toBuffer();

    const { data: decompressedData } = await sharp(jpegBytes)
      .raw()
      .toBuffer({ resolveWithObject: true });

    const decompressedRgb = new Uint8Array(decompressedData);

    // Compute PSNR between original RGB and decompressed RGB
    let mse = 0;
    const totalPixels = width * height * 3;
    for (let i = 0; i < totalPixels; i++) {
      const diff = rgbBuffer[i] - decompressedRgb[i];
      mse += diff * diff;
    }
    mse /= totalPixels;

    const psnr = mse === 0 ? 99.0 : 10 * Math.log10((255 * 255) / mse);

    return { decompressedRgb, jpegBytes, psnr };
  }

  /**
   * Computes rigorous color conversion fidelity metrics (MAE, Max Error, PSNR, SSIM).
   */
  public static computeColorMetrics(
    rgbOriginal: Uint8Array,
    rgbTest: Uint8Array,
    width: number,
    height: number
  ): ColorConversionMetrics {
    const totalBytes = width * height * 3;
    let maxAbsErr = 0;
    let sumAbsErr = 0;
    let sumSqErr = 0;

    for (let i = 0; i < totalBytes; i++) {
      const diff = Math.abs(rgbOriginal[i] - rgbTest[i]);
      if (diff > maxAbsErr) maxAbsErr = diff;
      sumAbsErr += diff;
      sumSqErr += diff * diff;
    }

    const meanAbsErr = totalBytes > 0 ? sumAbsErr / totalBytes : 0;
    const mse = totalBytes > 0 ? sumSqErr / totalBytes : 0;
    const psnr = mse === 0 ? 99.0 : 10 * Math.log10((255 * 255) / mse);

    // Simplified 8x8 block SSIM calculation
    const C1 = (0.01 * 255) ** 2;
    const C2 = (0.03 * 255) ** 2;
    let ssimSum = 0;
    let blockCount = 0;

    const blockSize = 8;
    const numBlocksX = Math.floor(width / blockSize);
    const numBlocksY = Math.floor(height / blockSize);

    for (let by = 0; by < numBlocksY; by++) {
      for (let bx = 0; bx < numBlocksX; bx++) {
        let meanX = 0;
        let meanY = 0;
        const N = blockSize * blockSize;

        for (let y = 0; y < blockSize; y++) {
          for (let x = 0; x < blockSize; x++) {
            const idx = ((by * blockSize + y) * width + (bx * blockSize + x)) * 3;
            // Use luminance approx: 0.299R + 0.587G + 0.114B
            const lumaOrig = 0.299 * rgbOriginal[idx] + 0.587 * rgbOriginal[idx + 1] + 0.114 * rgbOriginal[idx + 2];
            const lumaTest = 0.299 * rgbTest[idx] + 0.587 * rgbTest[idx + 1] + 0.114 * rgbTest[idx + 2];
            meanX += lumaOrig;
            meanY += lumaTest;
          }
        }
        meanX /= N;
        meanY /= N;

        let varX = 0;
        let varY = 0;
        let covXY = 0;

        for (let y = 0; y < blockSize; y++) {
          for (let x = 0; x < blockSize; x++) {
            const idx = ((by * blockSize + y) * width + (bx * blockSize + x)) * 3;
            const lumaOrig = 0.299 * rgbOriginal[idx] + 0.587 * rgbOriginal[idx + 1] + 0.114 * rgbOriginal[idx + 2];
            const lumaTest = 0.299 * rgbTest[idx] + 0.587 * rgbTest[idx + 1] + 0.114 * rgbTest[idx + 2];
            const diffX = lumaOrig - meanX;
            const diffY = lumaTest - meanY;
            varX += diffX * diffX;
            varY += diffY * diffY;
            covXY += diffX * diffY;
          }
        }
        varX /= N;
        varY /= N;
        covXY /= N;

        const ssimBlock = ((2 * meanX * meanY + C1) * (2 * covXY + C2)) /
          ((meanX * meanX + meanY * meanY + C1) * (varX + varY + C2));

        ssimSum += ssimBlock;
        blockCount++;
      }
    }

    const ssim = blockCount > 0 ? ssimSum / blockCount : 1.0;

    return {
      maxAbsoluteError: maxAbsErr,
      meanAbsoluteError: Number(meanAbsErr.toFixed(4)),
      psnr: Number(psnr.toFixed(2)),
      ssim: Number(ssim.toFixed(4)),
    };
  }

  /**
   * Verifies frame sequence integrity:
   * 1. Monotonicity: frame[i].timestampNs > frame[i-1].timestampNs
   * 2. Frame interval bounds: 10ms <= dt <= 2000ms
   * 3. Sequence continuity: sequence indices represent accepted application frames
   * 4. Stillness / Freeze Risk Assessment:
   *    - MSE == 0.0: Hard freeze attack rejection (identical duplicate frames)
   *    - 0.0 < MSE < 1.0: Stillness risk warning (does not permanently fail authentic static subjects)
   */
  public static verifyFrameSequenceIntegrity(
    frames: Array<{ metadata: FrameMetadata; grayscalePixels: Uint8Array }>,
    minInterFrameMse: number = 1.0
  ): { valid: boolean; errors: string[]; warnings: string[]; stillnessRiskScore: number } {
    const errors: string[] = [];
    const warnings: string[] = [];
    let stillnessRiskScore = 0.0;

    if (frames.length < 2) {
      return { valid: true, errors: [], warnings: [], stillnessRiskScore: 0.0 };
    }

    for (let i = 1; i < frames.length; i++) {
      const prev = frames[i - 1];
      const curr = frames[i];

      // 1. Sequence continuity (accepted application frames)
      if (curr.metadata.sequenceIndex !== prev.metadata.sequenceIndex + 1) {
        errors.push(
          `Sequence index discontinuity: frame ${i} has seq ${curr.metadata.sequenceIndex}, expected ${prev.metadata.sequenceIndex + 1}`
        );
      }

      // 2. Timestamp monotonicity
      const dtNs = curr.metadata.timestampNs - prev.metadata.timestampNs;
      if (dtNs <= 0) {
        errors.push(
          `Timestamp non-monotonic: frame ${i} dt=${dtNs}ns <= 0 (t_prev=${prev.metadata.timestampNs}, t_curr=${curr.metadata.timestampNs})`
        );
      }

      const dtMs = dtNs / 1_000_000;
      if (dtMs < 10 || dtMs > 2000) {
        errors.push(`Frame interval out of bounds: dt=${dtMs.toFixed(2)}ms, allowed [10ms, 2000ms]`);
      }

      // 3. Anti-freeze verification
      const pLen = Math.min(prev.grayscalePixels.length, curr.grayscalePixels.length);
      let mse = 0;
      for (let j = 0; j < pLen; j++) {
        const diff = prev.grayscalePixels[j] - curr.grayscalePixels[j];
        mse += diff * diff;
      }
      mse /= pLen;

      if (mse === 0.0) {
        // Exact duplicate bytes across different timestamps indicate injected frozen frames
        errors.push(
          `Camera freeze detected between frame ${i - 1} and ${i}: inter-frame MSE=0.0000 (exact byte duplication)`
        );
      } else if (mse < minInterFrameMse) {
        // Low variance on authentic static human face: record warning and risk score, do not hard fail
        warnings.push(
          `High stillness warning between frame ${i - 1} and ${i}: inter-frame MSE=${mse.toFixed(4)} < threshold ${minInterFrameMse}`
        );
        stillnessRiskScore = Math.max(stillnessRiskScore, (minInterFrameMse - mse) / minInterFrameMse);
      }
    }

    return {
      valid: errors.length === 0,
      errors,
      warnings,
      stillnessRiskScore: Number(stillnessRiskScore.toFixed(4)),
    };
  }

  /**
   * Constructs the canonical PLAY_INTEGRITY_BINDING_V2 payload digest.
   * Digest = SHA256( rawPayloadBytes || sessionNonce || clientTimestampNs )
   */
  public static computePlayIntegrityBindingDigest(
    rawPayloadBytes: Uint8Array,
    sessionNonce: string,
    clientTimestampNs: number
  ): string {
    const hasher = crypto.createHash('sha256');
    hasher.update(rawPayloadBytes);
    hasher.update(Buffer.from(sessionNonce, 'utf8'));
    const tsBuf = Buffer.alloc(8);
    tsBuf.writeBigInt64BE(BigInt(clientTimestampNs));
    hasher.update(tsBuf);
    return hasher.digest('hex');
  }
}
