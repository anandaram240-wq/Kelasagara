// backend/src/services/biometric_quality_assessment.ts
/**
 * Track D: Biometric Quality Assessment Engine (Ticket D-01).
 * Implements ISO/IEC 29794-5 Quality Metric Gates and Error-vs-Reject Modeling.
 * Enforces Invariants I-01 (Fail-Closed) and I-12 (Strict Quality Gates).
 */

export interface FaceGeometry {
  bbox: { width: number; height: number };
  landmarks: {
    leftEye: { x: number; y: number };
    rightEye: { x: number; y: number };
    nose: { x: number; y: number };
    leftMouth: { x: number; y: number };
    rightMouth: { x: number; y: number };
  };
}

export interface ImageQualityMetrics {
  laplacianVariance: number; // Blur metric (>= 100)
  meanLuminance: number;     // Exposure metric [40, 220]
  yawDegrees: number;        // Pose yaw [ -30 to +30 ]
  pitchDegrees: number;      // Pose pitch [ -20 to +20 ]
  rollDegrees: number;       // Pose roll [ -20 to +20 ]
  interEyeDistancePx: number;// IOD (>= 40px)
  embeddingNorm?: number;    // MagFace / Feature magnitude proxy
}

export interface QualityAssessmentResult {
  passed: boolean;
  compositeQualityScore: number; // [0.0, 1.0]
  rejectionReasons: string[];
  metrics: {
    interEyeDistance: number;
    laplacianVariance: number;
    meanLuminance: number;
    yaw: number;
    pitch: number;
    roll: number;
  };
}

export class BiometricQualityAssessment {
  // ISO/IEC 29794-5 Hard Gates
  private static readonly MIN_FACE_DIM = 80;        // pixels
  private static readonly MIN_IOD = 40;             // Inter-Eye Distance (px)
  private static readonly MIN_SHARPNESS = 100.0;    // Laplacian Variance
  private static readonly MIN_LUMINANCE = 40.0;     // Mean Gray Level [0..255]
  private static readonly MAX_LUMINANCE = 220.0;    // Mean Gray Level [0..255]
  private static readonly MAX_YAW = 30.0;           // degrees
  private static readonly MAX_PITCH = 20.0;         // degrees
  private static readonly MAX_ROLL = 20.0;          // degrees

  /**
   * Evaluates face geometry and image metrics against ISO/IEC 29794-5 standards.
   */
  static assessQuality(
    geometry: FaceGeometry,
    metrics: ImageQualityMetrics
  ): QualityAssessmentResult {
    const reasons: string[] = [];

    // 1. Face size gate
    if (
      geometry.bbox.width < this.MIN_FACE_DIM ||
      geometry.bbox.height < this.MIN_FACE_DIM
    ) {
      reasons.push(
        `FACE_TOO_SMALL: ${geometry.bbox.width}x${geometry.bbox.height} < ${this.MIN_FACE_DIM}px`
      );
    }

    // 2. Inter-Eye Distance (IOD)
    const dx = geometry.landmarks.rightEye.x - geometry.landmarks.leftEye.x;
    const dy = geometry.landmarks.rightEye.y - geometry.landmarks.leftEye.y;
    const computedIOD = Math.sqrt(dx * dx + dy * dy);
    const iod = metrics.interEyeDistancePx || computedIOD;

    if (iod < this.MIN_IOD) {
      reasons.push(`INTER_EYE_DISTANCE_DEFICIENT: ${iod.toFixed(1)}px < ${this.MIN_IOD}px`);
    }

    // 3. Sharpness / Blur Gate
    if (metrics.laplacianVariance < this.MIN_SHARPNESS) {
      reasons.push(
        `MOTION_BLUR_DETECTED: variance ${metrics.laplacianVariance.toFixed(1)} < ${this.MIN_SHARPNESS}`
      );
    }

    // 4. Illumination / Exposure Gate
    if (
      metrics.meanLuminance < this.MIN_LUMINANCE ||
      metrics.meanLuminance > this.MAX_LUMINANCE
    ) {
      reasons.push(
        `ILLUMINATION_FAULT: luminance ${metrics.meanLuminance.toFixed(1)} outside [${this.MIN_LUMINANCE}, ${this.MAX_LUMINANCE}]`
      );
    }

    // 5. Pose Gates
    if (Math.abs(metrics.yawDegrees) > this.MAX_YAW) {
      reasons.push(`EXCESSIVE_YAW: ${metrics.yawDegrees.toFixed(1)}deg > ${this.MAX_YAW}deg`);
    }
    if (Math.abs(metrics.pitchDegrees) > this.MAX_PITCH) {
      reasons.push(`EXCESSIVE_PITCH: ${metrics.pitchDegrees.toFixed(1)}deg > ${this.MAX_PITCH}deg`);
    }
    if (Math.abs(metrics.rollDegrees) > this.MAX_ROLL) {
      reasons.push(`EXCESSIVE_ROLL: ${metrics.rollDegrees.toFixed(1)}deg > ${this.MAX_ROLL}deg`);
    }

    // Compute composite quality score [0, 1]
    const sharpnessFactor = Math.min(1.0, metrics.laplacianVariance / 300.0);
    const iodFactor = Math.min(1.0, iod / 80.0);
    const posePenalty =
      Math.min(1.0, Math.abs(metrics.yawDegrees) / this.MAX_YAW) * 0.4 +
      Math.min(1.0, Math.abs(metrics.pitchDegrees) / this.MAX_PITCH) * 0.3 +
      Math.min(1.0, Math.abs(metrics.rollDegrees) / this.MAX_ROLL) * 0.3;
    const poseFactor = Math.max(0.0, 1.0 - posePenalty);
    const luminanceFactor =
      1.0 -
      Math.abs(metrics.meanLuminance - 128.0) / 128.0;

    const compositeQualityScore = Math.max(
      0.0,
      Math.min(
        1.0,
        0.35 * sharpnessFactor +
          0.25 * iodFactor +
          0.25 * poseFactor +
          0.15 * Math.max(0, luminanceFactor)
      )
    );

    return {
      passed: reasons.length === 0,
      compositeQualityScore: parseFloat(compositeQualityScore.toFixed(3)),
      rejectionReasons: reasons,
      metrics: {
        interEyeDistance: parseFloat(iod.toFixed(1)),
        laplacianVariance: parseFloat(metrics.laplacianVariance.toFixed(1)),
        meanLuminance: parseFloat(metrics.meanLuminance.toFixed(1)),
        yaw: parseFloat(metrics.yawDegrees.toFixed(1)),
        pitch: parseFloat(metrics.pitchDegrees.toFixed(1)),
        roll: parseFloat(metrics.rollDegrees.toFixed(1)),
      },
    };
  }

  /**
   * Computes Error-vs-Reject Curve:
   * Measures FNMR at a fixed operating threshold as a function of the fraction
   * of lowest-quality samples discarded.
   */
  static computeErrorVsRejectCurve(
    pairs: { genuine: boolean; score: number; quality: number }[],
    operatingThreshold: number,
    rejectFractions: number[] = [0.0, 0.05, 0.1, 0.2, 0.3]
  ): { rejectFraction: number; retainedCount: number; fnmr: number }[] {
    const genuinePairs = pairs.filter((p) => p.genuine);
    if (genuinePairs.length === 0) return [];

    // Sort genuine pairs by quality ascending (lowest quality first)
    const sorted = [...genuinePairs].sort((a, b) => a.quality - b.quality);
    const totalGenuines = sorted.length;

    return rejectFractions.map((fraction) => {
      const cutIndex = Math.floor(fraction * totalGenuines);
      const retained = sorted.slice(cutIndex);

      if (retained.length === 0) {
        return { rejectFraction: fraction, retainedCount: 0, fnmr: 0.0 };
      }

      // False non-match count: genuine pairs scoring BELOW operating threshold
      const fnmCount = retained.filter((p) => p.score < operatingThreshold).length;
      const fnmr = fnmCount / retained.length;

      return {
        rejectFraction: fraction,
        retainedCount: retained.length,
        fnmr: parseFloat(fnmr.toFixed(4)),
      };
    });
  }
}
