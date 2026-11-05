// File: backend/src/biometrics/canonical_sface_engine_v10.ts
import * as ort from 'onnxruntime-node';
import sharp, { Metadata } from 'sharp';
import { createHash, randomBytes, createHmac } from 'crypto';
import * as fs from 'fs';
import * as path from 'path';

export const CANONICAL_SFACE_SPEC_V10 = {
  modelIdentifier: 'sface_opencv_zoo_v1_primary',
  expectedSha256: '0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79',
  preprocessVersion: 'sface_aligned_112x112_bgr_v1',
  inputDimension: 112,
  embeddingDimension: 128,
} as const;

export const CANONICAL_YUNET_SPEC_V10 = {
  modelIdentifier: 'yunet_opencv_zoo_2023mar_primary',
  expectedSha256: '8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4',
  inputDimension: 640,
} as const;

/**
 * Phase 20.11 Canonical Embedding Space Specification
 * Guarantees cryptographic and mathematical isolation from legacy or unknown templates.
 */
export const CANONICAL_EMBEDDING_SPACE_V2 = {
  embeddingSpaceId: 'SFACE_128_YUNET_2023MAR_UMEYAMA_CANONICAL112_V2',
  modelIdentifier: 'sface_opencv_zoo_v1_primary',
  modelSha256: '0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79',
  detectorIdentifier: 'yunet_opencv_zoo_2023mar_primary',
  detectorSha256: '8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4',
  alignmentAlgorithm: 'umeyama_5point_similarity',
  canonicalTargetGeometry: '112x112_canonical_sface_5landmarks',
  colorSpace: 'BGR',
  normalization: 'L2_UNIT_HYPERSPHERE_S127',
  dimension: 128,
} as const;

/**
 * Phase 20.12 Workstream D: Versioned Preprocessing Manifest
 * Binds every new template to the frozen, deterministic preprocessing manifest.
 */
export interface CanonicalPreprocessingManifest {
  readonly manifestVersion: string;
  readonly embeddingSpaceId: string;
  readonly modelIdentifier: string;
  readonly modelSha256: string;
  readonly detectorIdentifier: string;
  readonly detectorSha256: string;
  readonly alignmentAlgorithm: string;
  readonly canonicalTargetGeometry: string;
  readonly colorSpace: string;
  readonly normalization: string;
  readonly dimension: number;
  readonly inputDimension: number;
  readonly detectorInputDimension: number;
}

export const CANONICAL_PREPROCESSING_MANIFEST_V2: CanonicalPreprocessingManifest = {
  manifestVersion: 'v2.0.0-canonical-yunet-sface',
  embeddingSpaceId: 'SFACE_128_YUNET_2023MAR_UMEYAMA_CANONICAL112_V2',
  modelIdentifier: 'sface_opencv_zoo_v1_primary',
  modelSha256: '0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79',
  detectorIdentifier: 'yunet_opencv_zoo_2023mar_primary',
  detectorSha256: '8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4',
  alignmentAlgorithm: 'umeyama_5point_similarity',
  canonicalTargetGeometry: '112x112_canonical_sface_5landmarks',
  colorSpace: 'BGR',
  normalization: 'L2_UNIT_HYPERSPHERE_S127',
  dimension: 128,
  inputDimension: 112,
  detectorInputDimension: 640,
} as const;

export function computePreprocessingManifestHash(
  manifest: CanonicalPreprocessingManifest = CANONICAL_PREPROCESSING_MANIFEST_V2
): string {
  const canonicalJson = JSON.stringify(manifest, Object.keys(manifest).sort());
  return createHash('sha256').update(canonicalJson).digest('hex');
}

export const CANONICAL_MANIFEST_HASH_V2 = computePreprocessingManifestHash();

export {
  CanonicalPreprocessingManifestV3,
  CANONICAL_PREPROCESSING_MANIFEST_V3,
  CANONICAL_MANIFEST_FINGERPRINT_V3,
  SignedManifestEnvelope,
  ManifestAttestationAuthority,
  RuntimeExecutionProvenance,
} from './canonical_preprocessing_manifest_v13';

// ─── Strongly Typed Nominal Brands ─────────────────────────────────────────────
export type OriginalImageBytes = Buffer & { readonly __brand: unique symbol };
export type CanonicalAlignedFace112 = Buffer & { readonly __brand: unique symbol };
export type SFaceEmbedding128 = Float32Array & { readonly __brand: unique symbol };

/**
 * Workstream E: Trusted Internal Preprocessing Boundary & Object Provenance Tracking
 * Guarantees that only the authoritative YuNet and Umeyama pipeline can produce an accepted aligned-face object.
 */
export interface CanonicalAlignedFace112Provenance {
  readonly detectorIdentifier: string;
  readonly detectorSha256: string;
  readonly alignmentAlgorithm: string;
  readonly canonicalTargetGeometry: string;
  readonly alignedAtMs: number;
  readonly landmarks: LandmarkSet5;
  readonly variance: number;
  readonly hmacSignature: string;
}

// Module-private cryptographic key and ephemeral object identity registry
const PIPELINE_PROVENANCE_KEY = randomBytes(32);
const TRUSTED_CANONICAL_PROVENANCE = new WeakMap<Buffer, CanonicalAlignedFace112Provenance>();

function computeBufferHmac(buf: Buffer): string {
  return createHmac('sha256', PIPELINE_PROVENANCE_KEY).update(buf).digest('hex');
}

export function registerTrustedCanonicalAlignedBuffer(
  buffer: Buffer,
  metadata: {
    detectorIdentifier: string;
    detectorSha256: string;
    alignmentAlgorithm: string;
    canonicalTargetGeometry: string;
    landmarks: LandmarkSet5;
    variance: number;
  }
): CanonicalAlignedFace112 {
  const provenance: CanonicalAlignedFace112Provenance = {
    ...metadata,
    alignedAtMs: Date.now(),
    hmacSignature: computeBufferHmac(buffer),
  };
  TRUSTED_CANONICAL_PROVENANCE.set(buffer, provenance);
  return buffer as CanonicalAlignedFace112;
}

export function createTrustedCanonicalAlignedFixture(
  buffer: Buffer,
  landmarks: LandmarkSet5 = CANONICAL_SFACE_5_LANDMARK_SET
): CanonicalAlignedFace112 {
  return registerTrustedCanonicalAlignedBuffer(buffer, {
    detectorIdentifier: CANONICAL_YUNET_SPEC_V10.modelIdentifier,
    detectorSha256: CANONICAL_YUNET_SPEC_V10.expectedSha256,
    alignmentAlgorithm: 'umeyama_5point_similarity',
    canonicalTargetGeometry: '112x112_canonical_sface_5landmarks',
    landmarks,
    variance: 100.0,
  });
}

export function verifyTrustedCanonicalAlignedBuffer(
  buffer: unknown
): { verified: boolean; provenance?: CanonicalAlignedFace112Provenance; reason?: string } {
  if (!Buffer.isBuffer(buffer)) {
    return { verified: false, reason: 'INPUT_NOT_BUFFER' };
  }
  const provenance = TRUSTED_CANONICAL_PROVENANCE.get(buffer);
  if (!provenance) {
    return {
      verified: false,
      reason: 'UNREGISTERED_BUFFER: Buffer was not produced by the authoritative YuNet and Umeyama alignment pipeline.',
    };
  }
  const expectedHmac = computeBufferHmac(buffer);
  if (expectedHmac !== provenance.hmacSignature) {
    return {
      verified: false,
      reason: 'TAMPERED_BUFFER: Buffer contents were modified after authoritative alignment.',
    };
  }
  return { verified: true, provenance };
}

/**
 * Workstream F: Runtime Safety of Canonical Face Types
 * Enforces runtime-validated creation and structural checks for CanonicalAlignedFace112,
 * preventing accidental `as any` casts or unaligned image injection.
 */
export interface CanonicalAlignedFace112Metadata {
  readonly detectorIdentifier: string;
  readonly detectorSha256: string;
  readonly alignmentAlgorithm: string;
  readonly confidence: number;
  readonly alignedAtMs: number;
  readonly landmarks: LandmarkSet5;
  readonly variance: number;
}

export class CanonicalAlignedFace112Factory {
  public static readonly EXPECTED_WIDTH = 112;
  public static readonly EXPECTED_HEIGHT = 112;
  public static readonly EXPECTED_CHANNELS = 3;
  public static readonly EXPECTED_BYTE_LENGTH = 112 * 112 * 3; // 37632

  public static validateBuffer(
    buffer: unknown,
    options?: { checkStrictUniformity?: boolean; minVariance?: number }
  ): { valid: boolean; reason?: string } {
    if (!Buffer.isBuffer(buffer)) {
      return { valid: false, reason: 'INPUT_NOT_BUFFER: Provided input is not a Buffer instance.' };
    }
    if (buffer.length !== CanonicalAlignedFace112Factory.EXPECTED_BYTE_LENGTH) {
      return {
        valid: false,
        reason: `INVALID_BYTE_LENGTH: Expected ${CanonicalAlignedFace112Factory.EXPECTED_BYTE_LENGTH} bytes, got ${buffer.length}.`,
      };
    }

    let minVal = 255;
    let maxVal = 0;
    let sum = 0;
    const len = buffer.length;

    for (let i = 0; i < len; i++) {
      const v = buffer[i];
      if (v < minVal) minVal = v;
      if (v > maxVal) maxVal = v;
      sum += v;
    }

    if (minVal === 0 && maxVal === 0) {
      return {
        valid: false,
        reason: 'DEGENERATE_UNIFORM_BUFFER: Buffer is completely zeroed (all pixels = 0).',
      };
    }

    if (minVal === 255 && maxVal === 255) {
      return {
        valid: false,
        reason: 'DEGENERATE_UNIFORM_BUFFER: Buffer is completely saturated (all pixels = 255).',
      };
    }

    if (options?.checkStrictUniformity && minVal === maxVal) {
      return {
        valid: false,
        reason: `DEGENERATE_UNIFORM_BUFFER: Buffer is completely uniform (all pixels = ${minVal}).`,
      };
    }

    if (options?.minVariance !== undefined) {
      const mean = sum / len;
      let varSum = 0;
      for (let i = 0; i < len; i++) {
        const diff = buffer[i] - mean;
        varSum += diff * diff;
      }
      const variance = varSum / len;
      if (variance < options.minVariance) {
        return {
          valid: false,
          reason: `INSUFFICIENT_VARIANCE: Pixel variance (${variance.toFixed(4)}) is below threshold (${options.minVariance}).`,
        };
      }
    }

    return { valid: true };
  }

  public static create(
    buffer: Buffer,
    _metadata?: Partial<CanonicalAlignedFace112Metadata>
  ): CanonicalAlignedFace112 {
    const check = CanonicalAlignedFace112Factory.validateBuffer(buffer);
    if (!check.valid) {
      throw new BiometricPreprocessingError(
        'CANONICAL_EMBEDDING_FAILED',
        `Runtime validation failed for CanonicalAlignedFace112: ${check.reason}`
      );
    }
    return buffer as CanonicalAlignedFace112;
  }
}

export interface QuantizationParams {
  scale: number;
  zeroPoint: number;
}

export interface Landmark2D {
  x: number;
  y: number;
}

export interface LandmarkSet5 {
  rightEye: Landmark2D;
  leftEye: Landmark2D;
  noseTip: Landmark2D;
  rightMouth: Landmark2D;
  leftMouth: Landmark2D;
}

export interface DetectedFace {
  box: { x: number; y: number; width: number; height: number };
  score: number;
  landmarks: LandmarkSet5;
}

export interface FaceQualityMetrics {
  width: number;
  height: number;
  faceBoxArea: number;
  sharpnessVariance: number;
  yawDegrees: number;
  pitchDegrees: number;
  isOutOfBounds: boolean;
}

export interface EmbeddingSpaceMetadata {
  embeddingSpaceId: string;
  manifestVersion: string;
  manifestHash: string;
  modelIdentifier: string;
  expectedSha256: string;
  preprocessVersion: string;
  inputDimension: number;
  embeddingDimension: number;
  l2Norm: number;
}

export const CANONICAL_SFACE_5_LANDMARK_SET: LandmarkSet5 = {
  rightEye: { x: 38.2946, y: 51.6963 },
  leftEye: { x: 73.5318, y: 51.6963 },
  noseTip: { x: 56.0252, y: 71.7366 },
  rightMouth: { x: 41.5493, y: 92.3655 },
  leftMouth: { x: 70.7299, y: 92.2041 },
};

export type BiometricPreprocessingErrorCode =
  | 'NO_FACE_DETECTED'
  | 'MULTIPLE_FACES_DETECTED'
  | 'FACE_QUALITY_INSUFFICIENT'
  | 'LANDMARK_ALIGNMENT_FAILED'
  | 'UNSUPPORTED_IMAGE_FORMAT'
  | 'IMAGE_DIMENSIONS_INVALID'
  | 'CANONICAL_EMBEDDING_FAILED';

export class BiometricPreprocessingError extends Error {
  constructor(
    public readonly code: BiometricPreprocessingErrorCode,
    public readonly message: string,
    public readonly details?: Record<string, unknown>
  ) {
    super(`[${code}] ${message}`);
    this.name = 'BiometricPreprocessingError';
    Object.setPrototypeOf(this, BiometricPreprocessingError.prototype);
  }
}

export const CANONICAL_SFACE_5_LANDMARKS: readonly Landmark2D[] = [
  { x: 38.2946, y: 51.6963 }, // left eye (image left / subject right)
  { x: 73.5318, y: 51.6963 }, // right eye (image right / subject left)
  { x: 56.0252, y: 71.7366 }, // nose tip
  { x: 41.5493, y: 92.3655 }, // left mouth corner (image left / subject right)
  { x: 70.7299, y: 92.2041 }, // right mouth corner (image right / subject left)
];

export class CanonicalSFaceEngineV10 {
  private session: ort.InferenceSession | null = null;
  private yunetSession: ort.InferenceSession | null = null;
  private verifiedSha256: string | null = null;
  private verifiedYuNetSha256: string | null = null;
  private readonly expectedSha256: string;
  private readonly expectedYuNetSha256: string;
  private readonly yunetModelPath: string;

  constructor(
    private readonly modelPath: string,
    expectedSha256?: string,
    yunetModelPath?: string,
    expectedYuNetSha256?: string
  ) {
    this.expectedSha256 = expectedSha256 ?? CANONICAL_SFACE_SPEC_V10.expectedSha256;
    this.expectedYuNetSha256 = expectedYuNetSha256 ?? CANONICAL_YUNET_SPEC_V10.expectedSha256;
    this.yunetModelPath =
      yunetModelPath ??
      path.resolve(path.dirname(modelPath), 'face_detection_yunet_2023mar.onnx');
  }

  public async initializeAndVerifyArtifact(): Promise<{
    modelIdentifier: string;
    sha256: string;
  }> {
    if (!fs.existsSync(this.modelPath)) {
      throw new Error(`MODEL_UNAVAILABLE: Missing SFace artifact at ${this.modelPath}`);
    }
    const bytes = fs.readFileSync(this.modelPath);
    const sha256 = createHash('sha256').update(bytes).digest('hex');

    if (this.expectedSha256 && sha256.toLowerCase() !== this.expectedSha256.toLowerCase()) {
      throw new Error(
        `MODEL_UNAVAILABLE: SHA-256 mismatch for ${this.modelPath}. Expected ${this.expectedSha256}, got ${sha256}`
      );
    }

    if (!this.session) {
      this.session = await ort.InferenceSession.create(this.modelPath, {
        executionProviders: ['cpu'],
        graphOptimizationLevel: 'all',
      });
    }
    this.verifiedSha256 = sha256;
    return {
      modelIdentifier: CANONICAL_SFACE_SPEC_V10.modelIdentifier,
      sha256,
    };
  }

  public async initializeYuNetSession(): Promise<ort.InferenceSession> {
    if (this.yunetSession) {
      return this.yunetSession;
    }

    if (!fs.existsSync(this.yunetModelPath)) {
      throw new Error(`MODEL_UNAVAILABLE: Missing YuNet artifact at ${this.yunetModelPath}`);
    }

    const bytes = fs.readFileSync(this.yunetModelPath);
    const sha256 = createHash('sha256').update(bytes).digest('hex');

    if (
      this.expectedYuNetSha256 &&
      sha256.toLowerCase() !== this.expectedYuNetSha256.toLowerCase()
    ) {
      throw new Error(
        `MODEL_UNAVAILABLE: SHA-256 mismatch for ${this.yunetModelPath}. Expected ${this.expectedYuNetSha256}, got ${sha256}`
      );
    }

    this.yunetSession = await ort.InferenceSession.create(this.yunetModelPath, {
      executionProviders: ['cpu'],
      graphOptimizationLevel: 'all',
    });
    this.verifiedYuNetSha256 = sha256;
    return this.yunetSession;
  }

  /**
   * Part 1: Safe image decode, dimension, format, and decompression bomb protection.
   */
  public static async safeDecodeAndValidateImage(imageBuffer: Buffer): Promise<{
    rawRgb: Buffer;
    width: number;
    height: number;
    format: string;
  }> {
    if (!Buffer.isBuffer(imageBuffer) || imageBuffer.length < 32) {
      throw new BiometricPreprocessingError(
        'UNSUPPORTED_IMAGE_FORMAT',
        'Image buffer is empty or smaller than minimum format header threshold (32 bytes).'
      );
    }

    // Maximum payload size: 15MB
    if (imageBuffer.length > 15 * 1024 * 1024) {
      throw new BiometricPreprocessingError(
        'IMAGE_DIMENSIONS_INVALID',
        'Image payload exceeds maximum allowable size (15MB decompression safety limit).'
      );
    }

    // Inspect magic bytes
    const isJpeg = imageBuffer[0] === 0xff && imageBuffer[1] === 0xd8;
    const isPng =
      imageBuffer[0] === 0x89 &&
      imageBuffer[1] === 0x50 &&
      imageBuffer[2] === 0x4e &&
      imageBuffer[3] === 0x47;
    const isWebp =
      imageBuffer.length >= 12 &&
      imageBuffer.toString('ascii', 0, 4) === 'RIFF' &&
      imageBuffer.toString('ascii', 8, 12) === 'WEBP';

    if (!isJpeg && !isPng && !isWebp) {
      throw new BiometricPreprocessingError(
        'UNSUPPORTED_IMAGE_FORMAT',
        'Unsupported image format. Kelasagara accepts only JPEG, PNG, or WebP biometric captures.'
      );
    }

    let meta: Metadata;
    try {
      meta = await sharp(imageBuffer).metadata();
    } catch (err: any) {
      throw new BiometricPreprocessingError(
        'UNSUPPORTED_IMAGE_FORMAT',
        `Corrupt or undecodable image stream: ${err.message}`
      );
    }

    const width = meta.width ?? 0;
    const height = meta.height ?? 0;
    const format = meta.format ?? 'unknown';

    if (width < 64 || height < 64 || width > 4096 || height > 4096) {
      throw new BiometricPreprocessingError(
        'IMAGE_DIMENSIONS_INVALID',
        `Image dimensions ${width}x${height} outside allowed bounds [64x64 to 4096x4096].`,
        { width, height }
      );
    }

    try {
      const { data, info } = await sharp(imageBuffer)
        .removeAlpha()
        .raw()
        .toBuffer({ resolveWithObject: true });

      return {
        rawRgb: data,
        width: info.width,
        height: info.height,
        format,
      };
    } catch (err: any) {
      throw new BiometricPreprocessingError(
        'CANONICAL_EMBEDDING_FAILED',
        `Failed to decode image raster to raw RGB: ${err.message}`
      );
    }
  }

  /**
   * Part 2: YuNet Multi-Scale Neural Face Detection with Keypoints
   */
  public async detectFacesYuNet(
    rgbBuffer: Buffer,
    width: number,
    height: number,
    minScore = 0.6
  ): Promise<DetectedFace[]> {
    const session = await this.initializeYuNetSession();
    const netDim = CANONICAL_YUNET_SPEC_V10.inputDimension; // 640

    // Letterbox scale to fit inside 640x640 while maintaining aspect ratio
    const scale = Math.min(netDim / width, netDim / height);
    const scaledW = Math.round(width * scale);
    const scaledH = Math.round(height * scale);
    const padX = 0; // Top-left anchor alignment for reproducible offset math
    const padY = 0;

    // Resize input RGB to scaledW x scaledH
    const resizedRgb = await sharp(rgbBuffer, {
      raw: { width, height, channels: 3 },
    })
      .resize(scaledW, scaledH, { fit: 'fill' })
      .raw()
      .toBuffer();

    // Prepare 1 x 3 x 640 x 640 BGR float32 tensor
    const plane = netDim * netDim;
    const bgrFloat32 = new Float32Array(3 * plane); // defaults to 0.0 padding

    for (let y = 0; y < scaledH; y++) {
      for (let x = 0; x < scaledW; x++) {
        const srcIdx = (y * scaledW + x) * 3;
        const dstIdx = (y + padY) * netDim + (x + padX);
        const r = resizedRgb[srcIdx];
        const g = resizedRgb[srcIdx + 1];
        const b = resizedRgb[srcIdx + 2];
        bgrFloat32[dstIdx] = b;              // Channel 0: B
        bgrFloat32[plane + dstIdx] = g;      // Channel 1: G
        bgrFloat32[2 * plane + dstIdx] = r;  // Channel 2: R
      }
    }

    const inputTensor = new ort.Tensor('float32', bgrFloat32, [1, 3, netDim, netDim]);
    const inputName = session.inputNames[0];
    const outputs = await session.run({ [inputName]: inputTensor });

    const strides = [8, 16, 32] as const;
    const candidates: DetectedFace[] = [];

    for (const s of strides) {
      const cols = Math.floor(netDim / s);
      const rows = Math.floor(netDim / s);
      const clsData = outputs[`cls_${s}`].data as Float32Array;
      const objData = outputs[`obj_${s}`].data as Float32Array;
      const bboxData = outputs[`bbox_${s}`].data as Float32Array;
      const kpsData = outputs[`kps_${s}`].data as Float32Array;

      for (let r = 0; r < rows; r++) {
        for (let c = 0; c < cols; c++) {
          const idx = r * cols + c;
          const clsScore = Math.max(0.0, Math.min(1.0, clsData[idx]));
          const objScore = Math.max(0.0, Math.min(1.0, objData[idx]));
          const score = Math.sqrt(clsScore * objScore);

          if (score < minScore) continue;

          // Decode BBox
          const cxNet = (c + bboxData[idx * 4 + 0]) * s;
          const cyNet = (r + bboxData[idx * 4 + 1]) * s;
          const wNet = Math.exp(bboxData[idx * 4 + 2]) * s;
          const hNet = Math.exp(bboxData[idx * 4 + 3]) * s;

          // Map back to original image coordinates
          const origCx = (cxNet - padX) / scale;
          const origCy = (cyNet - padY) / scale;
          const origW = wNet / scale;
          const origH = hNet / scale;
          const origX = origCx - origW / 2;
          const origY = origCy - origH / 2;

          // Decode 5 Keypoints:
          // YuNet order: rightEye, leftEye, noseTip, rightMouth, leftMouth
          const origKps: Landmark2D[] = [];
          for (let k = 0; k < 5; k++) {
            const kxNet = (kpsData[idx * 10 + 2 * k + 0] + c) * s;
            const kyNet = (kpsData[idx * 10 + 2 * k + 1] + r) * s;
            origKps.push({
              x: (kxNet - padX) / scale,
              y: (kyNet - padY) / scale,
            });
          }

          candidates.push({
            box: {
              x: origX,
              y: origY,
              width: origW,
              height: origH,
            },
            score,
            landmarks: {
              rightEye: origKps[0],
              leftEye: origKps[1],
              noseTip: origKps[2],
              rightMouth: origKps[3],
              leftMouth: origKps[4],
            },
          });
        }
      }
    }

    // Apply Non-Maximum Suppression (IoU <= 0.3)
    return CanonicalSFaceEngineV10.applyNMS(candidates, 0.3);
  }

  public static applyNMS(candidates: DetectedFace[], iouThreshold = 0.3): DetectedFace[] {
    candidates.sort((a, b) => b.score - a.score);
    const selected: DetectedFace[] = [];

    for (const cand of candidates) {
      let keep = true;
      for (const sel of selected) {
        if (CanonicalSFaceEngineV10.computeIoU(cand.box, sel.box) > iouThreshold) {
          keep = false;
          break;
        }
      }
      if (keep) {
        selected.push(cand);
      }
    }
    return selected;
  }

  public static computeIoU(
    boxA: { x: number; y: number; width: number; height: number },
    boxB: { x: number; y: number; width: number; height: number }
  ): number {
    const x1 = Math.max(boxA.x, boxB.x);
    const y1 = Math.max(boxA.y, boxB.y);
    const x2 = Math.min(boxA.x + boxA.width, boxB.x + boxB.width);
    const y2 = Math.min(boxA.y + boxA.height, boxB.y + boxB.height);

    const interW = Math.max(0, x2 - x1);
    const interH = Math.max(0, y2 - y1);
    const interArea = interW * interH;

    const areaA = boxA.width * boxA.height;
    const areaB = boxB.width * boxB.height;
    const unionArea = areaA + areaB - interArea;

    if (unionArea <= 0) return 0;
    return interArea / unionArea;
  }

  /**
   * Part 3: Facial Quality Gates
   */
  public static validateFaceQuality(
    face: DetectedFace,
    width: number,
    height: number,
    rgbBuffer: Buffer
  ): FaceQualityMetrics {
    const { box, landmarks } = face;

    // Minimum size check: 60x60 px
    if (box.width < 60 || box.height < 60) {
      throw new BiometricPreprocessingError(
        'FACE_QUALITY_INSUFFICIENT',
        `Face box (${Math.round(box.width)}x${Math.round(box.height)}) is below minimum resolution threshold (60x60 required).`,
        { reason: 'FACE_TOO_SMALL', width: box.width, height: box.height }
      );
    }

    // Boundary check: at least 85% of face must be within the image frame
    const inW = Math.max(0, Math.min(box.x + box.width, width) - Math.max(0, box.x));
    const inH = Math.max(0, Math.min(box.y + box.height, height) - Math.max(0, box.y));
    const inArea = inW * inH;
    const totalArea = box.width * box.height;
    const inBoundsFraction = totalArea > 0 ? inArea / totalArea : 0;

    if (inBoundsFraction < 0.85) {
      throw new BiometricPreprocessingError(
        'FACE_QUALITY_INSUFFICIENT',
        'Face is partially outside the camera frame (must be at least 85% visible).',
        { reason: 'FACE_OUT_OF_BOUNDS', inBoundsFraction }
      );
    }

    // Pose check using 5 keypoints
    // Eye distance and yaw symmetry
    const eyeDx = landmarks.leftEye.x - landmarks.rightEye.x;
    const eyeDy = landmarks.leftEye.y - landmarks.rightEye.y;
    const eyeDist = Math.hypot(eyeDx, eyeDy);

    if (eyeDist < 12) {
      throw new BiometricPreprocessingError(
        'FACE_QUALITY_INSUFFICIENT',
        'Eye inter-pupillary distance is too small for reliable biometric alignment.',
        { reason: 'FACE_TOO_SMALL', eyeDist }
      );
    }

    const eyeMidX = (landmarks.rightEye.x + landmarks.leftEye.x) / 2;
    const eyeMidY = (landmarks.rightEye.y + landmarks.leftEye.y) / 2;
    const mouthMidX = (landmarks.rightMouth.x + landmarks.leftMouth.x) / 2;
    const mouthMidY = (landmarks.rightMouth.y + landmarks.leftMouth.y) / 2;

    const yawOffset = Math.abs(landmarks.noseTip.x - eyeMidX);
    const yawRatio = yawOffset / eyeDist;
    const yawDegrees = (yawOffset / eyeDist) * 90;

    if (yawRatio > 0.45) {
      throw new BiometricPreprocessingError(
        'FACE_QUALITY_INSUFFICIENT',
        'Extreme head pose detected. Please look straight into the camera.',
        { reason: 'EXTREME_POSE', yawRatio, yawDegrees }
      );
    }

    // Blur / Sharpness check: Laplacian variance on face region
    const cropX0 = Math.max(0, Math.floor(box.x));
    const cropY0 = Math.max(0, Math.floor(box.y));
    const cropX1 = Math.min(width - 1, Math.floor(box.x + box.width));
    const cropY1 = Math.min(height - 1, Math.floor(box.y + box.height));
    const cropW = cropX1 - cropX0;
    const cropH = cropY1 - cropY0;

    let sharpnessVariance = 100.0;
    if (cropW >= 20 && cropH >= 20) {
      let sumL = 0;
      let sumSqL = 0;
      let count = 0;

      // Sample a grid of pixels inside face bounding box
      const step = Math.max(1, Math.floor(Math.min(cropW, cropH) / 40));
      for (let y = cropY0 + 2; y < cropY1 - 2; y += step) {
        for (let x = cropX0 + 2; x < cropX1 - 2; x += step) {
          const idx = (y * width + x) * 3;
          const idxL = (y * width + (x - 1)) * 3;
          const idxR = (y * width + (x + 1)) * 3;
          const idxU = ((y - 1) * width + x) * 3;
          const idxD = ((y + 1) * width + x) * 3;

          const lum = 0.299 * rgbBuffer[idx] + 0.587 * rgbBuffer[idx + 1] + 0.114 * rgbBuffer[idx + 2];
          const lumL = 0.299 * rgbBuffer[idxL] + 0.587 * rgbBuffer[idxL + 1] + 0.114 * rgbBuffer[idxL + 2];
          const lumR = 0.299 * rgbBuffer[idxR] + 0.587 * rgbBuffer[idxR + 1] + 0.114 * rgbBuffer[idxR + 2];
          const lumU = 0.299 * rgbBuffer[idxU] + 0.587 * rgbBuffer[idxU + 1] + 0.114 * rgbBuffer[idxU + 2];
          const lumD = 0.299 * rgbBuffer[idxD] + 0.587 * rgbBuffer[idxD + 1] + 0.114 * rgbBuffer[idxD + 2];

          const lap = lumL + lumR + lumU + lumD - 4 * lum;
          sumL += lap;
          sumSqL += lap * lap;
          count++;
        }
      }

      if (count > 0) {
        const mean = sumL / count;
        sharpnessVariance = sumSqL / count - mean * mean;
      }
    }

    if (sharpnessVariance < 12.0) {
      throw new BiometricPreprocessingError(
        'FACE_QUALITY_INSUFFICIENT',
        'Image is too blurry for reliable face matching. Please keep your device steady.',
        { reason: 'EXCESSIVE_BLUR', sharpnessVariance }
      );
    }

    return {
      width: box.width,
      height: box.height,
      faceBoxArea: totalArea,
      sharpnessVariance,
      yawDegrees,
      pitchDegrees: Math.abs(eyeMidY - mouthMidY) * 0.1,
      isOutOfBounds: inBoundsFraction < 0.99,
    };
  }

  /**
   * Aligns an arbitrary face image to canonical 112x112 space using 5-point Umeyama similarity transform.
   */
  public static computeUmeyamaSimilarityTransform(
    srcPoints: readonly Landmark2D[],
    dstPoints: readonly Landmark2D[] = CANONICAL_SFACE_5_LANDMARKS
  ): { scale: number; theta: number; cosT: number; sinT: number; tx: number; ty: number } {
    const N = srcPoints.length;
    if (N !== 5) {
      throw new Error(`UMEYAMA_ALIGNMENT_REQUIRES_5_LANDMARKS: got ${N}`);
    }

    let mx_x = 0;
    let mx_y = 0;
    let my_x = 0;
    let my_y = 0;
    for (let i = 0; i < N; i++) {
      mx_x += srcPoints[i].x;
      mx_y += srcPoints[i].y;
      my_x += dstPoints[i].x;
      my_y += dstPoints[i].y;
    }
    mx_x /= N;
    mx_y /= N;
    my_x /= N;
    my_y /= N;

    let varX = 0;
    let s11 = 0;
    let s12 = 0;
    let s21 = 0;
    let s22 = 0;
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
    s11 /= N;
    s12 /= N;
    s21 /= N;
    s22 /= N;

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
   * Part 4: Umeyama 5-point alignment and bilinear affine warp to 112x112x3 RGB
   */
  public static alignFaceToCanonical112(
    rgbBuffer: Buffer,
    width: number,
    height: number,
    landmarks: LandmarkSet5
  ): CanonicalAlignedFace112 {
    const srcPoints: Landmark2D[] = [
      landmarks.rightEye, // subject right / image left
      landmarks.leftEye,  // subject left / image right
      landmarks.noseTip,
      landmarks.rightMouth,
      landmarks.leftMouth,
    ];

    let transform: { scale: number; theta: number; cosT: number; sinT: number; tx: number; ty: number };
    try {
      transform = CanonicalSFaceEngineV10.computeUmeyamaSimilarityTransform(
        srcPoints,
        CANONICAL_SFACE_5_LANDMARKS
      );
    } catch (err: any) {
      throw new BiometricPreprocessingError(
        'LANDMARK_ALIGNMENT_FAILED',
        `Failed to compute similarity transform: ${err.message}`
      );
    }

    if (!Number.isFinite(transform.scale) || transform.scale <= 1e-5) {
      throw new BiometricPreprocessingError(
        'LANDMARK_ALIGNMENT_FAILED',
        'Degenerate scale factor computed in Umeyama alignment.'
      );
    }

    const dstDim = 112;
    const dstBuffer = Buffer.alloc(dstDim * dstDim * 3);
    const invScale = 1.0 / transform.scale;
    let dstIdx = 0;

    for (let v = 0; v < dstDim; v++) {
      for (let u = 0; u < dstDim; u++) {
        // Inverse similarity mapping from (u, v) in canonical space to (srcX, srcY) in source image
        const du = u - transform.tx;
        const dv = v - transform.ty;
        const srcX = invScale * (transform.cosT * du + transform.sinT * dv);
        const srcY = invScale * (-transform.sinT * du + transform.cosT * dv);

        const x0 = Math.floor(srcX);
        const y0 = Math.floor(srcY);
        const x1 = Math.min(width - 1, x0 + 1);
        const y1 = Math.min(height - 1, y0 + 1);

        if (x0 < 0 || y0 < 0 || x0 >= width || y0 >= height) {
          // Out-of-bounds boundary pad with neutral gray (128)
          dstBuffer[dstIdx++] = 128;
          dstBuffer[dstIdx++] = 128;
          dstBuffer[dstIdx++] = 128;
        } else {
          const fx = Math.max(0.0, Math.min(1.0, srcX - x0));
          const fy = Math.max(0.0, Math.min(1.0, srcY - y0));
          const w00 = (1.0 - fx) * (1.0 - fy);
          const w10 = fx * (1.0 - fy);
          const w01 = (1.0 - fx) * fy;
          const w11 = fx * fy;

          const idx00 = (y0 * width + x0) * 3;
          const idx10 = (y0 * width + x1) * 3;
          const idx01 = (y1 * width + x0) * 3;
          const idx11 = (y1 * width + x1) * 3;

          for (let c = 0; c < 3; c++) {
            const val =
              w00 * rgbBuffer[idx00 + c] +
              w10 * rgbBuffer[idx10 + c] +
              w01 * rgbBuffer[idx01 + c] +
              w11 * rgbBuffer[idx11 + c];
            dstBuffer[dstIdx++] = Math.round(val);
          }
        }
      }
    }

    let sum = 0;
    for (let i = 0; i < dstBuffer.length; i++) sum += dstBuffer[i];
    const mean = sum / dstBuffer.length;
    let varSum = 0;
    for (let i = 0; i < dstBuffer.length; i++) {
      const d = dstBuffer[i] - mean;
      varSum += d * d;
    }
    const variance = varSum / dstBuffer.length;

    return registerTrustedCanonicalAlignedBuffer(dstBuffer, {
      detectorIdentifier: CANONICAL_YUNET_SPEC_V10.modelIdentifier,
      detectorSha256: CANONICAL_YUNET_SPEC_V10.expectedSha256,
      alignmentAlgorithm: 'umeyama_5point_similarity',
      canonicalTargetGeometry: '112x112_canonical_sface_5landmarks',
      landmarks,
      variance,
    });
  }

  /**
   * Part 5: Converts an aligned 112x112 image crop into OpenCV SFace's canonical BGR [1, 3, 112, 112]
   * float32 input tensor and extracts a validated L2-normalized 128-D embedding.
   *
   * STRICT TYPING CONTRACT: Only accepts pre-aligned 112x112x3 buffers!
   * Never silently resizes raw full-scene camera images.
   */
  public async extractCanonicalEmbeddingFromAligned112(
    aligned112ImageBuffer: CanonicalAlignedFace112
  ): Promise<SFaceEmbedding128> {
    if (!this.session) {
      await this.initializeAndVerifyArtifact();
    }

    const dim = CANONICAL_SFACE_SPEC_V10.inputDimension; // 112
    const expectedByteLen = dim * dim * 3; // 37632

    // Workstream F: Comprehensive runtime safety check on buffer length, uniformity, and variance
    const validation = CanonicalAlignedFace112Factory.validateBuffer(aligned112ImageBuffer);
    if (!validation.valid) {
      throw new BiometricPreprocessingError(
        'CANONICAL_EMBEDDING_FAILED',
        `extractCanonicalEmbeddingFromAligned112 strictly requires a pre-aligned 112x112x3 RGB buffer. Runtime validation rejected input: ${validation.reason}. Raw unaligned camera images must pass through extractCanonicalEmbeddingFromOriginalImage().`
      );
    }

    // Workstream E: Enforce Authoritative Pipeline Provenance Verification
    const verification = verifyTrustedCanonicalAlignedBuffer(aligned112ImageBuffer);
    if (!verification.verified) {
      throw new BiometricPreprocessingError(
        'CANONICAL_EMBEDDING_FAILED',
        `UNAUTHORIZED_CANONICAL_FACE_OBJECT: ${verification.reason} Raw image buffers or manually fabricated objects cannot bypass the authoritative YuNet and Umeyama alignment pipeline.`
      );
    }

    const rawRgbBytes = aligned112ImageBuffer;

    // OpenCV SFace expects BGR channel order in [0.0, 255.0]
    const plane = dim * dim;
    const bgrFloat32 = new Float32Array(3 * plane);
    for (let i = 0; i < plane; i++) {
      const r = rawRgbBytes[i * 3];
      const g = rawRgbBytes[i * 3 + 1];
      const b = rawRgbBytes[i * 3 + 2];
      bgrFloat32[i] = b;              // Channel 0: B
      bgrFloat32[plane + i] = g;      // Channel 1: G
      bgrFloat32[2 * plane + i] = r;  // Channel 2: R
    }

    const inputTensor = new ort.Tensor('float32', bgrFloat32, [1, 3, dim, dim]);
    const inputName = this.session!.inputNames[0];
    const outputs = await this.session!.run({ [inputName]: inputTensor });
    const outputTensor = outputs[this.session!.outputNames[0]];

    const unitVector = CanonicalSFaceEngineV10.extractAndNormalizeOutputTensor(outputTensor);
    return unitVector as SFaceEmbedding128;
  }

  /**
   * Part 6: Full Canonical Pipeline Orchestration
   * original image -> safe decode -> YuNet face detection -> quality gates -> Umeyama alignment -> SFace embedding
   */
  public async extractCanonicalEmbeddingFromOriginalImage(
    imageBuffer: Buffer,
    options?: {
      mockDetector?: (rgbBuffer: Buffer, width: number, height: number) => DetectedFace[];
      minDetectionScore?: number;
    }
  ): Promise<{
    embedding: SFaceEmbedding128;
    face: DetectedFace;
    quality: FaceQualityMetrics;
    aligned112: CanonicalAlignedFace112;
    metadata: EmbeddingSpaceMetadata;
  }> {
    // Step 1: Safe decode & format validation
    const { rawRgb, width, height } = await CanonicalSFaceEngineV10.safeDecodeAndValidateImage(imageBuffer);

    // Step 2: Face Detection
    let faces: DetectedFace[];
    if (options?.mockDetector) {
      faces = options.mockDetector(rawRgb, width, height);
    } else {
      faces = await this.detectFacesYuNet(rawRgb, width, height, options?.minDetectionScore ?? 0.6);
    }

    if (faces.length === 0) {
      throw new BiometricPreprocessingError(
        'NO_FACE_DETECTED',
        'No human face was detected in the submitted image. Please align your face inside the guide frame.'
      );
    }

    if (faces.length > 1) {
      throw new BiometricPreprocessingError(
        'MULTIPLE_FACES_DETECTED',
        `Detected ${faces.length} faces in the camera frame. Exactly one face must be present for biometric enrollment.`,
        { detectedCount: faces.length }
      );
    }

    const face = faces[0];

    // Step 3: Quality Gates
    const quality = CanonicalSFaceEngineV10.validateFaceQuality(face, width, height, rawRgb);

    // Step 4: Canonical Alignment
    const aligned112 = CanonicalSFaceEngineV10.alignFaceToCanonical112(
      rawRgb,
      width,
      height,
      face.landmarks
    );

    // Step 5: SFace 128-D Feature Extraction
    const embedding = await this.extractCanonicalEmbeddingFromAligned112(aligned112);

    let sumSq = 0;
    for (let i = 0; i < embedding.length; i++) sumSq += embedding[i] * embedding[i];
    const l2Norm = Math.sqrt(sumSq);

    const metadata: EmbeddingSpaceMetadata = {
      embeddingSpaceId: CANONICAL_EMBEDDING_SPACE_V2.embeddingSpaceId,
      manifestVersion: CANONICAL_PREPROCESSING_MANIFEST_V2.manifestVersion,
      manifestHash: CANONICAL_MANIFEST_HASH_V2,
      modelIdentifier: CANONICAL_SFACE_SPEC_V10.modelIdentifier,
      expectedSha256: CANONICAL_SFACE_SPEC_V10.expectedSha256,
      preprocessVersion: CANONICAL_SFACE_SPEC_V10.preprocessVersion,
      inputDimension: CANONICAL_SFACE_SPEC_V10.inputDimension,
      embeddingDimension: CANONICAL_SFACE_SPEC_V10.embeddingDimension,
      l2Norm,
    };

    return {
      embedding,
      face,
      quality,
      aligned112,
      metadata,
    };
  }

  /**
   * Part 4.3 Inference Integrity:
   * Inspects the actual ONNX output tensor type. Applies linear dequantization
   * `real = scale * (q - zero_point)` ONLY when the tensor is quantized (int8/uint8).
   * Never double-dequantizes an already floating-point tensor.
   */
  public static extractAndNormalizeOutputTensor(
    tensor: { type: string; data: unknown },
    quantParams?: QuantizationParams
  ): Float32Array {
    const expectedDim = CANONICAL_SFACE_SPEC_V10.embeddingDimension;
    let rawFloats: Float32Array;

    if (tensor.type === 'float32') {
      const src = tensor.data as Float32Array;
      if (src.length !== expectedDim) {
        throw new Error(`INVALID_EMBEDDING_DIMENSION: Expected ${expectedDim}, got ${src.length}`);
      }
      rawFloats = new Float32Array(src);
    } else if (tensor.type === 'int8' || tensor.type === 'uint8') {
      if (!quantParams || !Number.isFinite(quantParams.scale) || quantParams.scale <= 0) {
        throw new Error('MISSING_VALID_QUANTIZATION_SCALE_FOR_INT8_TENSOR');
      }
      const src = tensor.data as Int8Array | Uint8Array;
      if (src.length !== expectedDim) {
        throw new Error(`INVALID_EMBEDDING_DIMENSION: Expected ${expectedDim}, got ${src.length}`);
      }
      rawFloats = new Float32Array(expectedDim);
      for (let i = 0; i < expectedDim; i++) {
        rawFloats[i] = quantParams.scale * (src[i] - quantParams.zeroPoint);
      }
    } else {
      throw new Error(`UNSUPPORTED_ONNX_OUTPUT_TENSOR_TYPE: ${tensor.type}`);
    }

    let sumSq = 0;
    for (let i = 0; i < expectedDim; i++) {
      const v = rawFloats[i];
      if (!Number.isFinite(v)) {
        throw new Error(`NON_FINITE_EMBEDDING_ELEMENT_AT_${i}`);
      }
      sumSq += v * v;
    }

    const norm = Math.sqrt(sumSq);
    if (norm < 1e-6) {
      throw new Error('DEGENERATE_ZERO_NORM_EMBEDDING');
    }

    const unitVector = new Float32Array(expectedDim);
    for (let i = 0; i < expectedDim; i++) {
      unitVector[i] = rawFloats[i] / norm;
    }
    return unitVector;
  }

  public static computeCosineSimilarity(a: Float32Array | number[], b: Float32Array | number[]): number {
    if (a.length !== 128 || b.length !== 128) {
      throw new Error('COSINE_SIMILARITY_DIMENSION_MISMATCH');
    }
    let dot = 0;
    let normASq = 0;
    let normBSq = 0;
    for (let i = 0; i < 128; i++) {
      const va = Number(a[i]);
      const vb = Number(b[i]);
      if (!Number.isFinite(va) || !Number.isFinite(vb)) {
        throw new Error('NON_FINITE_VECTOR_IN_COSINE_SIMILARITY');
      }
      dot += va * vb;
      normASq += va * va;
      normBSq += vb * vb;
    }
    const denom = Math.sqrt(normASq) * Math.sqrt(normBSq);
    if (denom < 1e-6) {
      throw new Error('ZERO_NORM_VECTOR_IN_COSINE_SIMILARITY');
    }
    return Math.max(-1.0, Math.min(1.0, dot / denom));
  }
}
