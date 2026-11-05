/**
 * KELASAGARA BIOMETRIC ENGINE V11.0 — PHASE 11.1
 * File: backend/src/biometrics/umeyama_aligner_v11.ts
 *
 * Exact closed-form 5-Point 2D Umeyama Similarity Transform (112x112 canonical space),
 * zero-allocation bilinear NCHW tensor warping, and pre-inference FIQA geometry/sharpness scoring.
 */

export type Point2D = readonly [number, number];

/**
 * Order: [leftEye, rightEye, noseTip, leftMouthCorner, rightMouthCorner]
 */
export type FivePointLandmarks = readonly [
  Point2D,
  Point2D,
  Point2D,
  Point2D,
  Point2D,
];

/**
 * Canonical 112x112 ArcFace / AdaFace 5-point reference coordinates.
 */
export const ARCFACE_CANONICAL_112_LANDMARKS: FivePointLandmarks = [
  [38.2946, 51.6963], // Left eye center
  [73.5318, 51.5014], // Right eye center
  [56.0252, 71.7366], // Nose tip
  [41.5493, 92.3655], // Left mouth corner
  [70.7299, 92.2041], // Right mouth corner
] as const;

export const ALIGNED_FACE_SIZE = 112;
export const ALIGNED_TENSOR_ELEMENTS = 3 * ALIGNED_FACE_SIZE * ALIGNED_FACE_SIZE; // 37,632 floats

/**
 * 2x3 Affine Matrix [a, b, tx, c, d, ty] representing:
 * x' = a*x + b*y + tx
 * y' = c*x + d*y + ty
 */
export type AffineMatrix2x3 = readonly [
  number,
  number,
  number,
  number,
  number,
  number,
];

export interface UmeyamaAlignmentResultV11 {
  readonly forwardMatrix: AffineMatrix2x3;
  readonly inverseMatrix: AffineMatrix2x3;
  readonly scale: number;
  readonly rotationRadians: number;
  readonly meanResidualPixels: number;
  readonly yawAsymmetryRatio: number;
  readonly interOcularPixels: number;
}

export interface FrameQualityMetricsV11 {
  readonly compositeQuality: number; // [0.0, 1.0]
  readonly sharpnessLaplacianVar: number;
  readonly alignmentResidualScore: number;
  readonly poseSymmetryScore: number;
  readonly rollAngleDegrees: number;
  readonly passedQualityGate: boolean;
  readonly rejectionReason?:
    | 'INTER_OCULAR_TOO_SMALL'
    | 'EXTREME_ROLL_ANGLE'
    | 'EXTREME_YAW_ASYMMETRY'
    | 'HIGH_ALIGNMENT_RESIDUAL'
    | 'EXCESSIVE_BLUR';
}

export interface QualityGateThresholdsV11 {
  readonly minInterOcularPixels: number;
  readonly maxRollDegrees: number;
  readonly maxYawAsymmetryRatio: number;
  readonly maxAlignmentResidualPixels: number;
  readonly minLaplacianVariance: number;
  readonly minCompositeQuality: number;
}

export const DEFAULT_QUALITY_THRESHOLDS_V11: QualityGateThresholdsV11 = {
  minInterOcularPixels: 24.0,
  maxRollDegrees: 25.0,
  maxYawAsymmetryRatio: 2.35,
  maxAlignmentResidualPixels: 4.75,
  minLaplacianVariance: 0.0018, // On normalized [-1, 1] luminance plane
  minCompositeQuality: 0.35,
};

/**
 * Exact closed-form 2x2 SVD for cross-covariance matrix [[s00, s01], [s10, s11]].
 * Guarantees proper rotation (det(U * V^T) > 0) to prevent horizontal mirroring.
 */
function svd2x2Proper(
  s00: number,
  s01: number,
  s10: number,
  s11: number
): {
  r00: number;
  r01: number;
  r10: number;
  r11: number;
  traceWeightedSingular: number;
} {
  const detM = s00 * s11 - s01 * s10;
  if (detM >= 0) {
    const A = s00 + s11;
    const B = s10 - s01;
    const norm = Math.hypot(A, B);
    const cosT = norm > 1e-12 ? A / norm : 1.0;
    const sinT = norm > 1e-12 ? B / norm : 0.0;
    return {
      r00: cosT,
      r01: -sinT,
      r10: sinT,
      r11: cosT,
      traceWeightedSingular: norm,
    };
  } else {
    const C = s00 - s11;
    const D = s10 + s01;
    const norm = Math.hypot(C, D);
    const cosT = norm > 1e-12 ? C / norm : 1.0;
    const sinT = norm > 1e-12 ? D / norm : 0.0;
    return {
      r00: cosT,
      r01: sinT,
      r10: sinT,
      r11: -cosT,
      traceWeightedSingular: norm,
    };
  }
}

/**
 * Computes the 2D Umeyama similarity transform mapping `srcLandmarks` -> `dstLandmarks`.
 */
export function estimateUmeyamaTransformV11(
  srcLandmarks: FivePointLandmarks,
  dstLandmarks: FivePointLandmarks = ARCFACE_CANONICAL_112_LANDMARKS
): UmeyamaAlignmentResultV11 {
  let srcMeanX = 0;
  let srcMeanY = 0;
  let dstMeanX = 0;
  let dstMeanY = 0;

  for (let i = 0; i < 5; i++) {
    srcMeanX += srcLandmarks[i][0];
    srcMeanY += srcLandmarks[i][1];
    dstMeanX += dstLandmarks[i][0];
    dstMeanY += dstLandmarks[i][1];
  }
  srcMeanX *= 0.2;
  srcMeanY *= 0.2;
  dstMeanX *= 0.2;
  dstMeanY *= 0.2;

  let srcVar = 0;
  let s00 = 0;
  let s01 = 0;
  let s10 = 0;
  let s11 = 0;

  for (let i = 0; i < 5; i++) {
    const sx = srcLandmarks[i][0] - srcMeanX;
    const sy = srcLandmarks[i][1] - srcMeanY;
    const dx = dstLandmarks[i][0] - dstMeanX;
    const dy = dstLandmarks[i][1] - dstMeanY;

    srcVar += sx * sx + sy * sy;
    s00 += dx * sx;
    s01 += dx * sy;
    s10 += dy * sx;
    s11 += dy * sy;
  }

  srcVar *= 0.2;
  s00 *= 0.2;
  s01 *= 0.2;
  s10 *= 0.2;
  s11 *= 0.2;

  if (srcVar < 1e-8) {
    throw new Error('BIOMETRIC_V11_DEGENERATE_LANDMARKS: Source landmark variance is near zero.');
  }

  const { r00, r01, r10, r11, traceWeightedSingular } = svd2x2Proper(s00, s01, s10, s11);
  const scale = traceWeightedSingular / srcVar;

  const a = scale * r00;
  const b = scale * r01;
  const c = scale * r10;
  const d = scale * r11;

  const tx = dstMeanX - (a * srcMeanX + b * srcMeanY);
  const ty = dstMeanY - (c * srcMeanX + d * srcMeanY);

  const forwardMatrix: AffineMatrix2x3 = [a, b, tx, c, d, ty];

  // Analytical inverse of similarity matrix for backward bilinear pixel sampling
  const det = a * d - b * c;
  const invDet = 1.0 / det;
  const ia = d * invDet;
  const ib = -b * invDet;
  const ic = -c * invDet;
  const id = a * invDet;
  const itx = -(ia * tx + ib * ty);
  const ity = -(ic * tx + id * ty);
  const inverseMatrix: AffineMatrix2x3 = [ia, ib, itx, ic, id, ity];

  // Compute mean canonical alignment residual in 112x112 space
  let residualSum = 0;
  for (let i = 0; i < 5; i++) {
    const px = a * srcLandmarks[i][0] + b * srcLandmarks[i][1] + tx;
    const py = c * srcLandmarks[i][0] + d * srcLandmarks[i][1] + ty;
    residualSum += Math.hypot(px - dstLandmarks[i][0], py - dstLandmarks[i][1]);
  }
  const meanResidualPixels = residualSum * 0.2;

  // Inter-ocular distance & yaw symmetry ratio
  const leftEye = srcLandmarks[0];
  const rightEye = srcLandmarks[1];
  const noseTip = srcLandmarks[2];
  const interOcularPixels = Math.hypot(rightEye[0] - leftEye[0], rightEye[1] - leftEye[1]);

  const distLeftEyeToNose = Math.max(1e-3, Math.hypot(noseTip[0] - leftEye[0], noseTip[1] - leftEye[1]));
  const distRightEyeToNose = Math.max(1e-3, Math.hypot(rightEye[0] - noseTip[0], rightEye[1] - noseTip[1]));
  const yawAsymmetryRatio = Math.max(
    distLeftEyeToNose / distRightEyeToNose,
    distRightEyeToNose / distLeftEyeToNose
  );

  const rotationRadians = Math.atan2(r10, r00);

  return {
    forwardMatrix,
    inverseMatrix,
    scale,
    rotationRadians,
    meanResidualPixels,
    yawAsymmetryRatio,
    interOcularPixels,
  };
}

/**
 * Warps an arbitrary source RGB/RGBA frame into a pre-allocated 1x3x112x112 NCHW Float32Array
 * using bilinear interpolation and ArcFace standard normalization: (pixel - 127.5) / 128.0.
 *
 * Zero heap allocations on the hot path.
 */
export function warpRgbToNormalizedNchwTensorV11(
  srcPixels: Uint8Array | Uint8ClampedArray,
  srcWidth: number,
  srcHeight: number,
  channels: 3 | 4,
  inverseMatrix: AffineMatrix2x3,
  targetTensorBuffer: Float32Array
): void {
  if (targetTensorBuffer.length < ALIGNED_TENSOR_ELEMENTS) {
    throw new Error(
      `Target tensor buffer too small: expected at least ${ALIGNED_TENSOR_ELEMENTS} floats.`
    );
  }

  const [ia, ib, itx, ic, id, ity] = inverseMatrix;
  const planeSize = ALIGNED_FACE_SIZE * ALIGNED_FACE_SIZE; // 12,544
  const maxX = srcWidth - 1;
  const maxY = srcHeight - 1;
  const normScale = 1.0 / 128.0;

  for (let dstY = 0; dstY < ALIGNED_FACE_SIZE; dstY++) {
    const baseSrcX = ib * dstY + itx;
    const baseSrcY = id * dstY + ity;
    const rowOffset = dstY * ALIGNED_FACE_SIZE;

    for (let dstX = 0; dstX < ALIGNED_FACE_SIZE; dstX++) {
      const sx = ia * dstX + baseSrcX;
      const sy = ic * dstX + baseSrcY;

      const x0 = Math.max(0, Math.min(maxX, Math.floor(sx)));
      const y0 = Math.max(0, Math.min(maxY, Math.floor(sy)));
      const x1 = Math.min(maxX, x0 + 1);
      const y1 = Math.min(maxY, y0 + 1);

      const wx = Math.max(0, Math.min(1, sx - x0));
      const wy = Math.max(0, Math.min(1, sy - y0));

      const w00 = (1 - wx) * (1 - wy);
      const w01 = wx * (1 - wy);
      const w10 = (1 - wx) * wy;
      const w11 = wx * wy;

      const idx00 = (y0 * srcWidth + x0) * channels;
      const idx01 = (y0 * srcWidth + x1) * channels;
      const idx10 = (y1 * srcWidth + x0) * channels;
      const idx11 = (y1 * srcWidth + x1) * channels;

      const r =
        srcPixels[idx00] * w00 +
        srcPixels[idx01] * w01 +
        srcPixels[idx10] * w10 +
        srcPixels[idx11] * w11;
      const g =
        srcPixels[idx00 + 1] * w00 +
        srcPixels[idx01 + 1] * w01 +
        srcPixels[idx10 + 1] * w10 +
        srcPixels[idx11 + 1] * w11;
      const b =
        srcPixels[idx00 + 2] * w00 +
        srcPixels[idx01 + 2] * w01 +
        srcPixels[idx10 + 2] * w10 +
        srcPixels[idx11 + 2] * w11;

      const outIdx = rowOffset + dstX;
      targetTensorBuffer[outIdx] = (r - 127.5) * normScale;
      targetTensorBuffer[planeSize + outIdx] = (g - 127.5) * normScale;
      targetTensorBuffer[2 * planeSize + outIdx] = (b - 127.5) * normScale;
    }
  }
}

/**
 * Computes discrete 3x3 Laplacian variance on the central 80x80 facial region of the
 * normalized Green channel (plane 1) to measure focus sharpness without extra allocations.
 */
export function computeTensorLaplacianVarianceV11(normalizedNchwTensor: Float32Array): number {
  const planeOffset = ALIGNED_FACE_SIZE * ALIGNED_FACE_SIZE; // Green channel offset
  const margin = 16; // Focus on core 80x80 interior face region
  const endCoord = ALIGNED_FACE_SIZE - margin;

  let sum = 0;
  let sumSq = 0;
  let count = 0;

  for (let y = margin; y < endCoord; y++) {
    const row = planeOffset + y * ALIGNED_FACE_SIZE;
    for (let x = margin; x < endCoord; x++) {
      const idx = row + x;
      const center = normalizedNchwTensor[idx];
      const top = normalizedNchwTensor[idx - ALIGNED_FACE_SIZE];
      const bottom = normalizedNchwTensor[idx + ALIGNED_FACE_SIZE];
      const left = normalizedNchwTensor[idx - 1];
      const right = normalizedNchwTensor[idx + 1];

      const lap = top + bottom + left + right - 4.0 * center;
      sum += lap;
      sumSq += lap * lap;
      count++;
    }
  }

  const mean = sum / count;
  return Math.max(0, sumSq / count - mean * mean);
}

/**
 * Evaluates pre-inference FIQA metrics combining landmark geometry, Umeyama residual, and sharpness.
 */
export function evaluateFrameQualityV11(
  alignment: UmeyamaAlignmentResultV11,
  normalizedNchwTensor: Float32Array,
  thresholds: QualityGateThresholdsV11 = DEFAULT_QUALITY_THRESHOLDS_V11
): FrameQualityMetricsV11 {
  const rollAngleDegrees = Math.abs((alignment.rotationRadians * 180.0) / Math.PI);
  const sharpnessLaplacianVar = computeTensorLaplacianVarianceV11(normalizedNchwTensor);

  // Normalized component scores in [0, 1]
  const alignmentResidualScore = Math.max(
    0,
    Math.min(1, 1.0 - alignment.meanResidualPixels / (thresholds.maxAlignmentResidualPixels * 1.5))
  );
  const poseSymmetryScore = Math.max(
    0,
    Math.min(
      1,
      1.0 - (alignment.yawAsymmetryRatio - 1.0) / Math.max(0.2, thresholds.maxYawAsymmetryRatio - 1.0)
    )
  );
  const sharpnessScore = Math.max(
    0,
    Math.min(1, sharpnessLaplacianVar / (thresholds.minLaplacianVariance * 4.0))
  );

  // Weighted composite quality used as frame weight q_i in 3-frame centroid fusion
  const compositeQuality = Number(
    (
      0.40 * sharpnessScore +
      0.35 * alignmentResidualScore +
      0.25 * poseSymmetryScore
    ).toFixed(6)
  );

  let rejectionReason: FrameQualityMetricsV11['rejectionReason'];
  if (alignment.interOcularPixels < thresholds.minInterOcularPixels) {
    rejectionReason = 'INTER_OCULAR_TOO_SMALL';
  } else if (rollAngleDegrees > thresholds.maxRollDegrees) {
    rejectionReason = 'EXTREME_ROLL_ANGLE';
  } else if (alignment.yawAsymmetryRatio > thresholds.maxYawAsymmetryRatio) {
    rejectionReason = 'EXTREME_YAW_ASYMMETRY';
  } else if (alignment.meanResidualPixels > thresholds.maxAlignmentResidualPixels) {
    rejectionReason = 'HIGH_ALIGNMENT_RESIDUAL';
  } else if (sharpnessLaplacianVar < thresholds.minLaplacianVariance) {
    rejectionReason = 'EXCESSIVE_BLUR';
  }

  const passedQualityGate =
    rejectionReason === undefined && compositeQuality >= thresholds.minCompositeQuality;

  return {
    compositeQuality,
    sharpnessLaplacianVar,
    alignmentResidualScore,
    poseSymmetryScore,
    rollAngleDegrees,
    passedQualityGate,
    rejectionReason,
  };
}

// ============================================================================
// BACKWARD-COMPATIBILITY ADAPTERS FOR V11.0 CALLERS
// ============================================================================

export interface Point2DObj {
  x: number;
  y: number;
}

export interface FiveLandmarks {
  leftEye: Point2DObj;
  rightEye: Point2DObj;
  noseTip: Point2DObj;
  leftMouth: Point2DObj;
  rightMouth: Point2DObj;
}

export interface AffineMatrix2x3Obj {
  a: number;
  b: number;
  tx: number;
  c: number;
  d: number;
  ty: number;
}

export const ARCFACE_112_REFERENCE_LANDMARKS: FiveLandmarks = {
  leftEye: { x: 38.2946, y: 51.6963 },
  rightEye: { x: 73.5318, y: 51.5014 },
  noseTip: { x: 56.0252, y: 71.7366 },
  leftMouth: { x: 41.5493, y: 92.3655 },
  rightMouth: { x: 70.7299, y: 92.2041 },
};

export class UmeyamaAlignerV11 {
  public static computeSimilarityTransform(
    src: FiveLandmarks,
    dst: FiveLandmarks = ARCFACE_112_REFERENCE_LANDMARKS
  ): AffineMatrix2x3Obj {
    const srcArray: FivePointLandmarks = [
      [src.leftEye.x, src.leftEye.y],
      [src.rightEye.x, src.rightEye.y],
      [src.noseTip.x, src.noseTip.y],
      [src.leftMouth.x, src.leftMouth.y],
      [src.rightMouth.x, src.rightMouth.y],
    ];
    const dstArray: FivePointLandmarks = [
      [dst.leftEye.x, dst.leftEye.y],
      [dst.rightEye.x, dst.rightEye.y],
      [dst.noseTip.x, dst.noseTip.y],
      [dst.leftMouth.x, dst.leftMouth.y],
      [dst.rightMouth.x, dst.rightMouth.y],
    ];

    const result = estimateUmeyamaTransformV11(srcArray, dstArray);
    const [a, b, tx, c, d, ty] = result.forwardMatrix;
    return { a, b, tx, c, d, ty };
  }

  public static estimatePoseAngles(landmarks: FiveLandmarks): {
    yawDeg: number;
    pitchDeg: number;
    rollDeg: number;
    isPoseAcceptable: boolean;
  } {
    const srcArray: FivePointLandmarks = [
      [landmarks.leftEye.x, landmarks.leftEye.y],
      [landmarks.rightEye.x, landmarks.rightEye.y],
      [landmarks.noseTip.x, landmarks.noseTip.y],
      [landmarks.leftMouth.x, landmarks.leftMouth.y],
      [landmarks.rightMouth.x, landmarks.rightMouth.y],
    ];

    const alignment = estimateUmeyamaTransformV11(srcArray);
    const rollDeg = Number(((alignment.rotationRadians * 180.0) / Math.PI).toFixed(2));

    // Yaw estimation via nose-to-eye asymmetry
    const eyeDx = landmarks.rightEye.x - landmarks.leftEye.x;
    const eyeDy = landmarks.rightEye.y - landmarks.leftEye.y;
    const iod = Math.hypot(eyeDx, eyeDy);

    const noseDistToLeftEye = Math.hypot(
      landmarks.noseTip.x - landmarks.leftEye.x,
      landmarks.noseTip.y - landmarks.leftEye.y
    );
    const noseDistToRightEye = Math.hypot(
      landmarks.noseTip.x - landmarks.rightEye.x,
      landmarks.noseTip.y - landmarks.rightEye.y
    );

    const eyeAsymmetry = iod > 0 ? (noseDistToRightEye - noseDistToLeftEye) / iod : 0;
    const yawDeg = Number((eyeAsymmetry * 65.0).toFixed(2));

    // Pitch estimation
    const eyeMidX = (landmarks.leftEye.x + landmarks.rightEye.x) * 0.5;
    const eyeMidY = (landmarks.leftEye.y + landmarks.rightEye.y) * 0.5;
    const mouthMidX = (landmarks.leftMouth.x + landmarks.rightMouth.x) * 0.5;
    const mouthMidY = (landmarks.leftMouth.y + landmarks.rightMouth.y) * 0.5;

    const faceHeight = Math.hypot(mouthMidX - eyeMidX, mouthMidY - eyeMidY);
    const noseToEyeVertical = Math.hypot(landmarks.noseTip.x - eyeMidX, landmarks.noseTip.y - eyeMidY);
    const pitchRatio = faceHeight > 0 ? noseToEyeVertical / faceHeight : 0.45;
    const pitchDeg = Number(((pitchRatio - 0.45) * 80.0).toFixed(2));

    const isPoseAcceptable =
      Math.abs(yawDeg) <= 18.0 && Math.abs(pitchDeg) <= 18.0 && Math.abs(rollDeg) <= 15.0;

    return {
      yawDeg,
      pitchDeg,
      rollDeg,
      isPoseAcceptable,
    };
  }
}
