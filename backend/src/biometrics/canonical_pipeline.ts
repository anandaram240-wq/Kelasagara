// backend/src/biometrics/canonical_pipeline.ts
/**
 * Canonical Biometric Pipeline & Quality Assurance (Phase 4).
 * Standards: ISO/IEC 19794-5, ISO/IEC 29794-5 (Face Quality), ISO/IEC 24745 (Template Protection).
 * Defines the canonical SFace 128-D model contract, input tensor extraction, and strict L2-normalization.
 */

import { createHash } from 'crypto';
import * as fs from 'fs';
import sharp from 'sharp';

export type BiometricOperationOutcome =
  | 'APPROVED'
  | 'QUALITY_REJECTED'
  | 'PAD_REJECTED'
  | 'PAD_INCONCLUSIVE'
  | 'IDENTITY_MISMATCH'
  | 'DUPLICATE_SUSPECTED_REVIEW'
  | 'DUPLICATE_HARD_BLOCK'
  | 'TEMPLATE_VERSION_MISMATCH'
  | 'TECHNICAL_FAILURE';

export type QualityRejectionCode =
  | 'MALFORMED_IMAGE'
  | 'NO_FACE_DETECTED'
  | 'MULTIPLE_FACES_DETECTED'
  | 'FACE_TOO_SMALL'
  | 'EXTREME_POSE'
  | 'UNDEREXPOSED'
  | 'OVEREXPOSED'
  | 'SEVERE_BLUR';

export interface CanonicalModelContract {
  readonly modelId: 'opencv_sface_2021dec_fp32_v1';
  readonly templateSchemaVersion: 2;
  readonly expectedSha256: string;
  readonly inputWidth: 112;
  readonly inputHeight: 112;
  readonly channelOrder: 'BGR';
  readonly pixelScale: 'RAW_0_255';
  readonly embeddingDimension: 128;
  readonly similarityMetric: 'COSINE_DOT_L2_NORMALIZED';
}

export const CANONICAL_SFACE_CONTRACT: CanonicalModelContract = {
  modelId: 'opencv_sface_2021dec_fp32_v1',
  templateSchemaVersion: 2,
  expectedSha256:
    process.env.SFACE_MODEL_SHA256 ||
    '0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79',
  inputWidth: 112,
  inputHeight: 112,
  channelOrder: 'BGR',
  pixelScale: 'RAW_0_255',
  embeddingDimension: 128,
  similarityMetric: 'COSINE_DOT_L2_NORMALIZED',
};

/**
 * Candidate engineering parameters for capture quality (NOT ISO-mandated constants;
 * subject to empirical tuning per device tier in Phase 7).
 */
export interface CaptureQualityCandidateConfig {
  minInterocularDistancePx: number;
  maxAbsYawDeg: number;
  maxAbsPitchDeg: number;
  maxAbsRollDeg: number;
  minFaceLuma: number;
  maxFaceLuma: number;
  minLaplacianSharpness: number;
}

export const DEFAULT_CANDIDATE_QUALITY_CONFIG: CaptureQualityCandidateConfig = {
  minInterocularDistancePx: 64,
  maxAbsYawDeg: 18,
  maxAbsPitchDeg: 18,
  maxAbsRollDeg: 15,
  minFaceLuma: 45,
  maxFaceLuma: 225,
  minLaplacianSharpness: 65,
};

export function verifyModelFileIntegrity(modelPath: string, contract = CANONICAL_SFACE_CONTRACT): void {
  const fileBuffer = fs.readFileSync(modelPath);
  const actualHash = createHash('sha256').update(fileBuffer).digest('hex');
  if (actualHash !== contract.expectedSha256) {
    throw new Error(
      `MODEL_INTEGRITY_FAILURE: Expected SHA-256 ${contract.expectedSha256}, got ${actualHash}`
    );
  }
}

/**
 * Decodes an aligned 112x112 face crop, auto-orienting EXIF, and packs it into a
 * contiguous NCHW [1, 3, 112, 112] Float32Array in BGR [0, 255] order as required by OpenCV SFace.
 */
export async function alignedCropToSFaceTensor(alignedImageBuffer: Buffer): Promise<Float32Array> {
  const { data, info } = await sharp(alignedImageBuffer)
    .rotate() // Respect EXIF orientation if present
    .removeAlpha()
    .raw()
    .toBuffer({ resolveWithObject: true });

  if (
    info.width !== CANONICAL_SFACE_CONTRACT.inputWidth ||
    info.height !== CANONICAL_SFACE_CONTRACT.inputHeight ||
    info.channels !== 3
  ) {
    throw new Error(
      `INVALID_ALIGNED_CROP_DIMENSIONS: Expected 112x112x3, received ${info.width}x${info.height}x${info.channels}`
    );
  }

  const planeSize = 112 * 112;
  const tensor = new Float32Array(3 * planeSize);

  for (let i = 0; i < planeSize; i++) {
    const r = data[i * 3];
    const g = data[i * 3 + 1];
    const b = data[i * 3 + 2];
    // OpenCV SFace expects BGR channel ordering in [0.0, 255.0]
    tensor[i] = b;
    tensor[planeSize + i] = g;
    tensor[2 * planeSize + i] = r;
  }

  return tensor;
}

/**
 * Strictly validates and L2-normalizes a raw 128-D output vector.
 * Rejects NaN, Infinity, wrong dimension, or near-zero norm (fail-closed).
 */
export function validateAndNormalizeEmbedding(
  raw: Float32Array | number[],
  contract = CANONICAL_SFACE_CONTRACT
): Float32Array {
  if (!raw || raw.length !== contract.embeddingDimension) {
    throw new Error(
      `INVALID_EMBEDDING_DIMENSION: Expected ${contract.embeddingDimension}, got ${raw?.length}`
    );
  }

  let sumSq = 0;
  for (let i = 0; i < raw.length; i++) {
    const val = raw[i];
    if (!Number.isFinite(val)) {
      throw new Error(`NON_FINITE_EMBEDDING_VALUE at index ${i}`);
    }
    sumSq += val * val;
  }

  const norm = Math.sqrt(sumSq);
  if (!Number.isFinite(norm) || norm < 1e-6) {
    throw new Error('ZERO_NORM_EMBEDDING_REJECTED');
  }

  const normalized = new Float32Array(contract.embeddingDimension);
  for (let i = 0; i < contract.embeddingDimension; i++) {
    normalized[i] = raw[i] / norm;
  }
  return normalized;
}

export function computeValidatedCosineSimilarity(a: Float32Array, b: Float32Array): number {
  const normA = validateAndNormalizeEmbedding(a);
  const normB = validateAndNormalizeEmbedding(b);

  let dot = 0;
  for (let i = 0; i < normA.length; i++) {
    dot += normA[i] * normB[i];
  }

  if (!Number.isFinite(dot) || dot < -1.0001 || dot > 1.0001) {
    throw new Error(`INVALID_COSINE_SCORE: ${dot}`);
  }
  return Math.max(-1.0, Math.min(1.0, dot));
}
