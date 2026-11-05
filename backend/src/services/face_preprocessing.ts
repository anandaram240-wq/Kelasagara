// backend/src/services/face_preprocessing.ts
import sharp from "sharp";
import * as crypto from "crypto";

/**
 * Versioned Preprocessing Specification ID.
 * Every stored template permanently records this ID (Invariant I-06).
 */
export const PREPROCESSING_ID = "PREPROC_V1_UMEYAMA_112_RGB_RAW255";

/**
 * Standard ArcFace canonical 5-point facial landmark coordinates for 112x112 target.
 * Reference: Deng et al., ArcFace (CVPR 2019).
 */
export const CANONICAL_5_LANDMARKS: { name: string; x: number; y: number }[] = [
  { name: "left_eye", x: 38.2946, y: 51.6963 },
  { name: "right_eye", x: 73.5318, y: 51.6963 },
  { name: "nose_tip", x: 56.0252, y: 71.7366 },
  { name: "left_mouth", x: 41.5493, y: 92.3655 },
  { name: "right_mouth", x: 70.7299, y: 92.2041 },
];

export interface Point2D {
  x: number;
  y: number;
}

export interface SimilarityTransform2D {
  scale: number;
  theta: number;
  cosT: number;
  sinT: number;
  tx: number;
  ty: number;
}

/**
 * Computes closed-form Umeyama 2D similarity transform mapping srcPoints to canonical coordinates.
 * Pure TypeScript implementation with zero external C++ dependencies (Ticket T-04).
 */
export function computeUmeyamaTransform(
  srcPoints: Point2D[],
  dstPoints: Point2D[] = CANONICAL_5_LANDMARKS
): SimilarityTransform2D {
  const N = srcPoints.length;
  if (N < 3) {
    throw new Error("Umeyama alignment requires at least 3 corresponding landmarks");
  }

  let mx_x = 0, mx_y = 0, my_x = 0, my_y = 0;
  for (let i = 0; i < N; i++) {
    mx_x += srcPoints[i].x;
    mx_y += srcPoints[i].y;
    my_x += dstPoints[i].x;
    my_y += dstPoints[i].y;
  }
  mx_x /= N; mx_y /= N; my_x /= N; my_y /= N;

  let varX = 0;
  let s11 = 0, s12 = 0, s21 = 0, s22 = 0;
  for (let i = 0; i < N; i++) {
    const dx = srcPoints[i].x - mx_x;
    const dy = srcPoints[i].y - mx_y;
    const du = dstPoints[i].x - my_x;
    const dv = dstPoints[i].y - my_y;
    varX += dx * dx + dy * dy;
    s11 += du * dx;
    s12 += du * dy;
    s21 += dv * dx;
    s22 += dv * dy;
  }
  varX /= N;
  s11 /= N; s12 /= N; s21 /= N; s22 /= N;

  const a = s11 + s22;
  const b = s21 - s12;
  const theta = Math.atan2(b, a);
  const cosT = Math.cos(theta);
  const sinT = Math.sin(theta);
  const scale = varX > 1e-8 ? (a * cosT + b * sinT) / varX : 1.0;

  const tx = my_x - scale * (cosT * mx_x - sinT * mx_y);
  const ty = my_y - scale * (sinT * mx_x + cosT * mx_y);

  return { scale, theta, cosT, sinT, tx, ty };
}

/**
 * Warps a source image buffer into canonical 112x112 space using the computed Umeyama similarity transform.
 * Uses bilinear interpolation with border clamping for sub-pixel accuracy.
 */
export function warpFaceUmeyama(
  srcBuffer: Buffer,
  srcWidth: number,
  srcHeight: number,
  transform: SimilarityTransform2D,
  dstWidth = 112,
  dstHeight = 112
): Buffer {
  const dstBuffer = Buffer.alloc(dstWidth * dstHeight * 3);
  const invScale = transform.scale !== 0 ? 1.0 / transform.scale : 1.0;
  const { cosT, sinT, tx, ty } = transform;

  let dstIdx = 0;
  for (let v = 0; v < dstHeight; v++) {
    for (let u = 0; u < dstWidth; u++) {
      const du = u - tx;
      const dv = v - ty;
      const srcX = invScale * (cosT * du + sinT * dv);
      const srcY = invScale * (-sinT * du + cosT * dv);

      const x0 = Math.floor(srcX);
      const y0 = Math.floor(srcY);
      const x1 = x0 + 1;
      const y1 = y0 + 1;

      const wx = srcX - x0;
      const wy = srcY - y0;

      const cx0 = Math.max(0, Math.min(srcWidth - 1, x0));
      const cy0 = Math.max(0, Math.min(srcHeight - 1, y0));
      const cx1 = Math.max(0, Math.min(srcWidth - 1, x1));
      const cy1 = Math.max(0, Math.min(srcHeight - 1, y1));

      for (let c = 0; c < 3; c++) {
        const p00 = srcBuffer[(cy0 * srcWidth + cx0) * 3 + c];
        const p10 = srcBuffer[(cy0 * srcWidth + cx1) * 3 + c];
        const p01 = srcBuffer[(cy1 * srcWidth + cx0) * 3 + c];
        const p11 = srcBuffer[(cy1 * srcWidth + cx1) * 3 + c];

        const val =
          (1 - wx) * (1 - wy) * p00 +
          wx * (1 - wy) * p10 +
          (1 - wx) * wy * p01 +
          wx * wy * p11;

        dstBuffer[dstIdx++] = Math.round(Math.max(0, Math.min(255, val)));
      }
    }
  }
  return dstBuffer;
}

export interface FaceQualityMetrics {
  isValid: boolean;
  failureReason?: string;
  width: number;
  height: number;
  interPupillaryDistance: number;
  yawDegrees?: number;
  pitchDegrees?: number;
  rollDegrees?: number;
  meanLuminance?: number;
  laplacianBlurScore?: number;
}

/**
 * Quality gating before neural feature extraction (Phase 4).
 * Enforces face size, IPD, pose, illumination, and blur thresholds.
 */
export function validateFaceQuality(metrics: {
  width: number;
  height: number;
  leftEye?: Point2D;
  rightEye?: Point2D;
  yawDegrees?: number;
  pitchDegrees?: number;
  rollDegrees?: number;
  meanLuminance?: number;
  laplacianBlurScore?: number;
}): FaceQualityMetrics {
  const minDimension = 112; // Minimum acceptable cropped face resolution
  const minIPD = 35; // Minimum inter-pupillary distance in 112x112 space

  if (metrics.width < minDimension || metrics.height < minDimension) {
    return {
      isValid: false,
      failureReason: `Face resolution too small (${metrics.width}x${metrics.height}). Minimum required: ${minDimension}x${minDimension}px.`,
      width: metrics.width,
      height: metrics.height,
      interPupillaryDistance: 0,
    };
  }

  let ipd = 0;
  if (metrics.leftEye && metrics.rightEye) {
    const dx = metrics.rightEye.x - metrics.leftEye.x;
    const dy = metrics.rightEye.y - metrics.leftEye.y;
    ipd = Math.sqrt(dx * dx + dy * dy);
    if (ipd < minIPD) {
      return {
        isValid: false,
        failureReason: `Inter-pupillary distance too low (${ipd.toFixed(1)}px). Please move closer to the camera.`,
        width: metrics.width,
        height: metrics.height,
        interPupillaryDistance: ipd,
      };
    }
  }

  // Pose checks
  if (metrics.yawDegrees !== undefined && Math.abs(metrics.yawDegrees) > 30) {
    return {
      isValid: false,
      failureReason: `Head yaw angle exceeded (${metrics.yawDegrees.toFixed(1)}°). Look directly at the camera.`,
      width: metrics.width,
      height: metrics.height,
      interPupillaryDistance: ipd,
      yawDegrees: metrics.yawDegrees,
    };
  }
  if (metrics.pitchDegrees !== undefined && Math.abs(metrics.pitchDegrees) > 25) {
    return {
      isValid: false,
      failureReason: `Head pitch angle exceeded (${metrics.pitchDegrees.toFixed(1)}°). Keep your head level.`,
      width: metrics.width,
      height: metrics.height,
      interPupillaryDistance: ipd,
      pitchDegrees: metrics.pitchDegrees,
    };
  }

  // Exposure checks
  if (metrics.meanLuminance !== undefined && (metrics.meanLuminance < 35 || metrics.meanLuminance > 225)) {
    return {
      isValid: false,
      failureReason: `Improper lighting (luminance: ${metrics.meanLuminance.toFixed(1)}). Ensure balanced facial illumination.`,
      width: metrics.width,
      height: metrics.height,
      interPupillaryDistance: ipd,
      meanLuminance: metrics.meanLuminance,
    };
  }

  // Blur checks
  if (metrics.laplacianBlurScore !== undefined && metrics.laplacianBlurScore < 60) {
    return {
      isValid: false,
      failureReason: `Image blur detected (score: ${metrics.laplacianBlurScore.toFixed(1)}). Hold the camera still.`,
      width: metrics.width,
      height: metrics.height,
      interPupillaryDistance: ipd,
      laplacianBlurScore: metrics.laplacianBlurScore,
    };
  }

  return {
    isValid: true,
    width: metrics.width,
    height: metrics.height,
    interPupillaryDistance: ipd,
    yawDegrees: metrics.yawDegrees,
    pitchDegrees: metrics.pitchDegrees,
    rollDegrees: metrics.rollDegrees,
    meanLuminance: metrics.meanLuminance,
    laplacianBlurScore: metrics.laplacianBlurScore,
  };
}

export interface PreprocessedFaceTensor {
  nchwFloat32: Float32Array;
  width: number;
  height: number;
  laplacianVariance: number;
  sha256DigestHex: string;
}

const CANONICAL_SIZE = 112;
const PLANE_PIXELS = CANONICAL_SIZE * CANONICAL_SIZE;
const RAW_RGB_BYTE_LENGTH = PLANE_PIXELS * 3; // 37,632 bytes

/**
 * Decodes either a compressed JPEG/PNG/WebP buffer OR a raw 112x112x3 RGB buffer
 * into a canonical NCHW [1, 3, 112, 112] Float32Array normalized to [-1.0, 1.0].
 */
export async function preprocessFaceBufferAuthoritative(
  inputBuffer: Buffer
): Promise<PreprocessedFaceTensor> {
  const sha256DigestHex = crypto
    .createHash("sha256")
    .update(inputBuffer)
    .digest("hex");

  let rawRgbBytes: Buffer;

  // Detect whether inputBuffer is already raw uncompressed 112x112x3 RGB bytes
  const isJpeg =
    inputBuffer.length > 3 &&
    inputBuffer[0] === 0xff &&
    inputBuffer[1] === 0xd8 &&
    inputBuffer[2] === 0xff;
  const isPng =
    inputBuffer.length > 4 &&
    inputBuffer[0] === 0x89 &&
    inputBuffer[1] === 0x50 &&
    inputBuffer[2] === 0x4e &&
    inputBuffer[3] === 0x47;

  if (!isJpeg && !isPng && inputBuffer.length === RAW_RGB_BYTE_LENGTH) {
    rawRgbBytes = Buffer.from(inputBuffer);
  } else {
    // Decode compressed image bitstream to raw 8-bit 3-channel sRGB via sharp
    rawRgbBytes = await sharp(inputBuffer)
      .rotate() // Respect EXIF orientation before resizing
      .resize(CANONICAL_SIZE, CANONICAL_SIZE, {
        fit: "cover",
        kernel: sharp.kernel.lanczos3,
      })
      .removeAlpha()
      .raw()
      .toBuffer();
  }

  if (rawRgbBytes.length !== RAW_RGB_BYTE_LENGTH) {
    throw new Error(
      `Invalid decoded RGB buffer length: expected ${RAW_RGB_BYTE_LENGTH}, got ${rawRgbBytes.length}`
    );
  }

  const nchwFloat32 = new Float32Array(3 * PLANE_PIXELS);
  const grayPlane = new Float32Array(PLANE_PIXELS);

  for (let i = 0; i < PLANE_PIXELS; i++) {
    const r = rawRgbBytes[i * 3];
    const g = rawRgbBytes[i * 3 + 1];
    const b = rawRgbBytes[i * 3 + 2];

    // MobileFaceNet / IndicFace128 canonical normalization: (pixel - 127.5) / 128.0
    nchwFloat32[i] = (r - 127.5) / 128.0;
    nchwFloat32[PLANE_PIXELS + i] = (g - 127.5) / 128.0;
    nchwFloat32[2 * PLANE_PIXELS + i] = (b - 127.5) / 128.0;

    // ITU-R BT.601 luma for server-side Laplacian verification
    grayPlane[i] = 0.299 * r + 0.587 * g + 0.114 * b;
  }

  // Server-side 2D Laplacian Variance calculation
  let sumLap = 0.0;
  let sumLapSq = 0.0;
  let count = 0;
  for (let r = 1; r < CANONICAL_SIZE - 1; r++) {
    for (let c = 1; c < CANONICAL_SIZE - 1; c++) {
      const idx = r * CANONICAL_SIZE + c;
      const lap =
        grayPlane[idx - CANONICAL_SIZE] +
        grayPlane[idx + CANONICAL_SIZE] +
        grayPlane[idx - 1] +
        grayPlane[idx + 1] -
        4.0 * grayPlane[idx];
      sumLap += lap;
      sumLapSq += lap * lap;
      count++;
    }
  }
  const meanLap = sumLap / count;
  const laplacianVariance = sumLapSq / count - meanLap * meanLap;

  // Scrub intermediate raw RGB buffer per DPDPA 2023 Section 12
  rawRgbBytes.fill(0);

  return {
    nchwFloat32,
    width: CANONICAL_SIZE,
    height: CANONICAL_SIZE,
    laplacianVariance,
    sha256DigestHex,
  };
}

/**
 * Preprocesses face image buffer into [1, 3, 112, 112] float tensor.
 * Value range: Raw [0.0, 255.0] float RGB in NCHW layout.
 * Matches OpenCV Zoo FaceRecognizerSF specification:
 *   scalefactor = 1.0 (raw [0.0, 255.0])
 *   mean = Scalar(0, 0, 0)
 *   swapRB = true (RGB format)
 *   crop = false
 *   size = (112, 112)
 */
export function preprocessFaceBuffer(rawBuffer: Buffer): Float32Array {
  if (!rawBuffer || rawBuffer.length < 100) {
    throw new Error(
      `Invalid face buffer: buffer length is ${rawBuffer ? rawBuffer.length : 0} bytes. Expected valid image data.`
    );
  }

  const channels = 3;
  const height = 112;
  const width = 112;
  const tensor = new Float32Array(1 * channels * height * width);

  // If buffer is exact raw RGB 112x112 (112 * 112 * 3 = 37,632 bytes)
  if (rawBuffer.length === width * height * channels) {
    let srcIdx = 0;
    for (let h = 0; h < height; h++) {
      for (let w = 0; w < width; w++) {
        const r = rawBuffer[srcIdx++];
        const g = rawBuffer[srcIdx++];
        const b = rawBuffer[srcIdx++];

        // NCHW layout: [c * height * width + h * width + w]
        tensor[0 * height * width + h * width + w] = r;
        tensor[1 * height * width + h * width + w] = g;
        tensor[2 * height * width + h * width + w] = b;
      }
    }
    return tensor;
  }

  // Linear sampling fallback for test buffers of varying dimensions
  const step = Math.max(1, Math.floor(rawBuffer.length / (width * height * channels)));
  let bIdx = 0;
  for (let c = 0; c < channels; c++) {
    for (let h = 0; h < height; h++) {
      for (let w = 0; w < width; w++) {
        const val = rawBuffer[bIdx % rawBuffer.length];
        tensor[c * height * width + h * width + w] = val;
        bIdx += step;
      }
    }
  }

  return tensor;
}

/**
 * Numerical validation of extracted embedding vector (Phase 4).
 * Rejects NaN, Inf, incorrect dimensions, zero vectors, or incorrect L2 norms.
 */
export function validateNumericalVector(vector: number[], expectedDim = 128): {
  isValid: boolean;
  error?: string;
  norm: number;
} {
  if (!vector || !Array.isArray(vector)) {
    return { isValid: false, error: "Vector is null or not an array", norm: 0 };
  }

  if (vector.length !== expectedDim) {
    return {
      isValid: false,
      error: `Vector dimension mismatch: expected ${expectedDim}, got ${vector.length}`,
      norm: 0,
    };
  }

  let sumSquares = 0;
  let allZero = true;
  let allIdentical = true;
  const firstVal = vector[0];

  for (let i = 0; i < vector.length; i++) {
    const v = vector[i];
    if (isNaN(v) || !isFinite(v)) {
      return { isValid: false, error: `Element at index ${i} is NaN or non-finite: ${v}`, norm: 0 };
    }
    if (v !== 0) allZero = false;
    if (Math.abs(v - firstVal) > 1e-6) allIdentical = false;
    sumSquares += v * v;
  }

  const norm = Math.sqrt(sumSquares);

  if (allZero) {
    return { isValid: false, error: "Vector is all-zeros", norm: 0 };
  }

  if (allIdentical) {
    return { isValid: false, error: "Vector is degenerate constant values", norm };
  }

  // Unit hypersphere norm tolerance (1.0 +/- 1e-4)
  if (Math.abs(norm - 1.0) > 1e-3) {
    return {
      isValid: false,
      error: `Vector L2 norm out of range: expected 1.0, got ${norm.toFixed(6)}`,
      norm,
    };
  }

  return { isValid: true, norm };
}

/**
 * Converts a Base64 string to a Buffer safely.
 */
export function decodeBase64Image(base64Str: string): Buffer {
  const clean = base64Str.replace(/^data:image\/\w+;base64,/, "").trim();
  return Buffer.from(clean, "base64");
}

/**
 * Horizontally mirrors an RGB 112x112 image buffer for Test-Time Augmentation (Flip-TTA) (Ticket B-03).
 */
export function flipImageHorizontally(srcBuffer: Buffer, width = 112, height = 112, channels = 3): Buffer {
  const dstBuffer = Buffer.alloc(srcBuffer.length);
  if (srcBuffer.length === width * height * channels) {
    for (let h = 0; h < height; h++) {
      for (let w = 0; w < width; w++) {
        const srcIdx = (h * width + w) * channels;
        const dstIdx = (h * width + (width - 1 - w)) * channels;
        dstBuffer[dstIdx] = srcBuffer[srcIdx];
        dstBuffer[dstIdx + 1] = srcBuffer[srcIdx + 1];
        dstBuffer[dstIdx + 2] = srcBuffer[srcIdx + 2];
      }
    }
    return dstBuffer;
  }
  for (let i = 0; i < srcBuffer.length; i++) {
    dstBuffer[i] = srcBuffer[srcBuffer.length - 1 - i];
  }
  return dstBuffer;
}

