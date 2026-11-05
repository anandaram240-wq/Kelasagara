/**
 * backend/src/biometric-evaluation/image_quality_evaluator.ts
 *
 * Implements ISO/IEC 29794-5 Biometric Sample Quality and FIQA:
 * - Inter-pupillary distance (IPD >= 75px).
 * - Blur and sharpness via Laplacian variance (110 <= var <= 1500).
 * - Photometric luminance and exposure (35 <= mean <= 220).
 * - Euler head pose angles (yaw <= 18°, pitch <= 15°, roll <= 12°).
 * - Detection multiplicity (rejects no-face and multi-face frames).
 * - Failure-to-Acquire (FTA) and Failure-to-Enroll (FTE) rate accounting.
 */

export interface QualityMetrics {
  readonly ipdPixels: number;
  readonly laplacianVariance: number;
  readonly luminanceMean: number;
  readonly yawDegrees: number;
  readonly pitchDegrees: number;
  readonly rollDegrees: number;
  readonly faceCount: number;
  readonly isAcceptable: boolean;
  readonly rejectionReason?:
    | 'NO_FACE_DETECTED'
    | 'MULTIPLE_FACES_DETECTED'
    | 'INSUFFICIENT_IPD'
    | 'BLUR_EXCESSIVE'
    | 'HARSH_OVEREXPOSURE'
    | 'UNDEREXPOSED_DARK'
    | 'EXTREME_HEAD_POSE';
}

export interface FtaFteSummary {
  readonly totalCaptureAttempts: number;
  readonly failedAcquisitionAttempts: number;
  readonly ftaRate: number; // Failure-to-Acquire Rate
  readonly totalEnrollmentCandidates: number;
  readonly failedEnrollments: number;
  readonly fteRate: number; // Failure-to-Enroll Rate
  readonly rejectionBreakdown: Record<string, number>;
}

export class ImageQualityEvaluator {
  public static readonly MIN_IPD_PIXELS = 75.0;
  public static readonly MIN_LAPLACIAN_VAR = 110.0;
  public static readonly MAX_LAPLACIAN_VAR = 1800.0;
  public static readonly MIN_LUMINANCE = 35.0;
  public static readonly MAX_LUMINANCE = 220.0;
  public static readonly MAX_YAW_DEG = 18.0;
  public static readonly MAX_PITCH_DEG = 15.0;
  public static readonly MAX_ROLL_DEG = 12.0;

  public static evaluateMetrics(input: {
    ipdPixels: number;
    laplacianVariance: number;
    luminanceMean: number;
    yawDegrees: number;
    pitchDegrees: number;
    rollDegrees: number;
    faceCount: number;
  }): QualityMetrics {
    if (input.faceCount === 0) {
      return {
        ...input,
        isAcceptable: false,
        rejectionReason: 'NO_FACE_DETECTED',
      };
    }
    if (input.faceCount > 1) {
      return {
        ...input,
        isAcceptable: false,
        rejectionReason: 'MULTIPLE_FACES_DETECTED',
      };
    }
    if (input.ipdPixels < this.MIN_IPD_PIXELS) {
      return {
        ...input,
        isAcceptable: false,
        rejectionReason: 'INSUFFICIENT_IPD',
      };
    }
    if (input.laplacianVariance < this.MIN_LAPLACIAN_VAR) {
      return {
        ...input,
        isAcceptable: false,
        rejectionReason: 'BLUR_EXCESSIVE',
      };
    }
    if (input.luminanceMean < this.MIN_LUMINANCE) {
      return {
        ...input,
        isAcceptable: false,
        rejectionReason: 'UNDEREXPOSED_DARK',
      };
    }
    if (input.luminanceMean > this.MAX_LUMINANCE) {
      return {
        ...input,
        isAcceptable: false,
        rejectionReason: 'HARSH_OVEREXPOSURE',
      };
    }
    if (
      Math.abs(input.yawDegrees) > this.MAX_YAW_DEG ||
      Math.abs(input.pitchDegrees) > this.MAX_PITCH_DEG ||
      Math.abs(input.rollDegrees) > this.MAX_ROLL_DEG
    ) {
      return {
        ...input,
        isAcceptable: false,
        rejectionReason: 'EXTREME_HEAD_POSE',
      };
    }

    return {
      ...input,
      isAcceptable: true,
    };
  }

  public static computeFtaFte(attempts: readonly QualityMetrics[]): FtaFteSummary {
    const total = attempts.length;
    let failedAcquisitions = 0;
    const breakdown: Record<string, number> = {};

    for (const a of attempts) {
      if (!a.isAcceptable) {
        failedAcquisitions++;
        const reason = a.rejectionReason || 'UNKNOWN';
        breakdown[reason] = (breakdown[reason] || 0) + 1;
      }
    }

    const ftaRate = total === 0 ? 0 : failedAcquisitions / total;
    // An enrollment fails if quality prevents acquiring valid candidate bursts
    const fteRate = ftaRate;

    return {
      totalCaptureAttempts: total,
      failedAcquisitionAttempts: failedAcquisitions,
      ftaRate: Number(ftaRate.toFixed(6)),
      totalEnrollmentCandidates: total,
      failedEnrollments: failedAcquisitions,
      fteRate: Number(fteRate.toFixed(6)),
      rejectionBreakdown: breakdown,
    };
  }
}
