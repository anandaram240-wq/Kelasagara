// backend/src/services/quality_gate.ts
/**
 * Authoritative Face Quality Gate (Ticket T-14).
 * Implements ISO/IEC 29794-5 (Face Image Quality - OFIQ standard principles).
 * Gating rejects frames before neural inference to prevent biometric degradation.
 */

export interface OfiqQualityParams {
  width: number;
  height: number;
  leftEye?: { x: number; y: number };
  rightEye?: { x: number; y: number };
  yawDegrees?: number;
  pitchDegrees?: number;
  rollDegrees?: number;
  laplacianBlurScore?: number;
  meanLuminance?: number;
  faceConfidence?: number;
}

export interface QualityGateResult {
  passed: boolean;
  score: number; // 0.0 - 100.0 unified quality score
  failureReasons: string[];
  metrics: {
    ipdPixels?: number;
    poseDeviationDegrees?: number;
    sharpnessScore?: number;
    illuminationScore?: number;
  };
}

export class QualityGateService {
  // ISO/IEC 29794-5 Normative Minimums
  public static readonly MIN_WIDTH = 112;
  public static readonly MIN_HEIGHT = 112;
  public static readonly MIN_IPD = 35.0; // Inter-pupillary distance in pixels
  public static readonly MAX_YAW = 25.0; // Degrees
  public static readonly MAX_PITCH = 20.0; // Degrees
  public static readonly MAX_ROLL = 20.0; // Degrees
  public static readonly MIN_BLUR = 60.0; // Laplacian variance sharpness
  public static readonly MIN_LUMINANCE = 40.0;
  public static readonly MAX_LUMINANCE = 220.0;
  public static readonly MIN_DETECTION_CONFIDENCE = 0.70;

  /**
   * Evaluates face frame against ISO/IEC 29794-5 OFIQ quality standards.
   */
  static evaluate(params: OfiqQualityParams): QualityGateResult {
    const reasons: string[] = [];
    let score = 100.0;

    // 1. Spatial Resolution
    if (params.width < this.MIN_WIDTH || params.height < this.MIN_HEIGHT) {
      reasons.push(
        `Face resolution too low (${params.width}x${params.height}). Minimum required: ${this.MIN_WIDTH}x${this.MIN_HEIGHT}.`
      );
      score -= 30;
    }

    // 2. Inter-Pupillary Distance (IPD)
    let ipd: number | undefined;
    if (params.leftEye && params.rightEye) {
      const dx = params.rightEye.x - params.leftEye.x;
      const dy = params.rightEye.y - params.leftEye.y;
      ipd = Math.sqrt(dx * dx + dy * dy);

      if (ipd < this.MIN_IPD) {
        reasons.push(
          `Inter-pupillary distance too small (${ipd.toFixed(1)}px). Face too distant; minimum IPD: ${this.MIN_IPD}px.`
        );
        score -= 25;
      }
    }

    // 3. Pose / Angular Deviation (Yaw, Pitch, Roll)
    const yaw = Math.abs(params.yawDegrees ?? 0);
    const pitch = Math.abs(params.pitchDegrees ?? 0);
    const roll = Math.abs(params.rollDegrees ?? 0);
    const maxPose = Math.max(yaw, pitch, roll);

    if (yaw > this.MAX_YAW) {
      reasons.push(`Yaw angle exceeded (${yaw.toFixed(1)}°). Max allowed: ±${this.MAX_YAW}°.`);
      score -= 20;
    }
    if (pitch > this.MAX_PITCH) {
      reasons.push(`Pitch angle exceeded (${pitch.toFixed(1)}°). Max allowed: ±${this.MAX_PITCH}°.`);
      score -= 20;
    }
    if (roll > this.MAX_ROLL) {
      reasons.push(`Roll angle exceeded (${roll.toFixed(1)}°). Max allowed: ±${this.MAX_ROLL}°.`);
      score -= 15;
    }

    // 4. Sharpness / Blur Assessment
    if (params.laplacianBlurScore !== undefined && params.laplacianBlurScore < this.MIN_BLUR) {
      reasons.push(
        `Severe image blur detected (${params.laplacianBlurScore.toFixed(1)} < ${this.MIN_BLUR}). Hold camera still.`
      );
      score -= 25;
    }

    // 5. Illumination Uniformity
    if (params.meanLuminance !== undefined) {
      if (params.meanLuminance < this.MIN_LUMINANCE) {
        reasons.push(`Under-exposed / low light (${params.meanLuminance.toFixed(1)} < ${this.MIN_LUMINANCE}).`);
        score -= 20;
      } else if (params.meanLuminance > this.MAX_LUMINANCE) {
        reasons.push(`Over-exposed / glare (${params.meanLuminance.toFixed(1)} > ${this.MAX_LUMINANCE}).`);
        score -= 20;
      }
    }

    // 6. Face Detector Confidence
    if (params.faceConfidence !== undefined && params.faceConfidence < this.MIN_DETECTION_CONFIDENCE) {
      reasons.push(`Low face detection confidence (${params.faceConfidence.toFixed(2)}).`);
      score -= 20;
    }

    score = Math.max(0, Math.min(100, Math.round(score)));
    return {
      passed: reasons.length === 0,
      score,
      failureReasons: reasons,
      metrics: {
        ipdPixels: ipd,
        poseDeviationDegrees: maxPose,
        sharpnessScore: params.laplacianBlurScore,
        illuminationScore: params.meanLuminance,
      },
    };
  }
}
