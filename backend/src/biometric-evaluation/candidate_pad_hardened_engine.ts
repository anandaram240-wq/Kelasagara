/**
 * backend/src/biometric-evaluation/candidate_pad_hardened_engine.ts
 *
 * Phase 20.8 Candidate Presentation Attack Detection (PAD) Hardened Engine
 * - Evaluated strictly in isolated test mode (production baseline untouched).
 * - Separates:
 *   A. Raw-frame feature extraction (via OpticalDisplayFeatureExtractor).
 *   B. Feature validation & bounds checking.
 *   C. Dynamic challenge sequence validation.
 *   D. Multi-signal decision fusion.
 *   E. Isolated experimental comparison mode.
 * - ISO/IEC 30107-3 compliance.
 * - Renames unvalidated corneal claims to specularHighlightFeatureScore (Image-derived heuristic).
 */

import {
  OpticalDisplayFeatureExtractor,
  OpticalDisplayFeatures,
  BoundingBoxROI,
} from './optical_display_feature_extractor';

export type PadFusionOutcome =
  | 'BONA_FIDE_CANDIDATE'
  | 'PRESENTATION_ATTACK_SUSPECTED'
  | 'CAPTURE_QUALITY_INSUFFICIENT'
  | 'CHALLENGE_INVALID'
  | 'SIGNAL_UNAVAILABLE'
  | 'MANUAL_REVIEW_REQUIRED';

export interface PadDiagnosticTelemetry {
  readonly challengeId: string;
  readonly challengeActionRequested: 'UNPROMPTED_BLINK' | 'RANDOMIZED_CHALLENGE_SEQUENCE';
  readonly challengeOutcome: 'CHALLENGE_COMPLIANT' | 'CHALLENGE_TIMED_OUT' | 'CHALLENGE_MISMATCH';
  readonly earSequence: {
    readonly f1OpenEar: number;
    readonly f2ApexEar: number;
    readonly f3RecoveryEar: number;
    readonly apexCompressionRatio: number;
    readonly earClassification: 'GENUINE_BLINK_TRAJECTORY' | 'SYNTHETIC_VIDEO_REPLAY' | 'INSUFFICIENT_CLOSURE';
  };
  readonly timingIrregularityMs: {
    readonly dt12: number;
    readonly dt23: number;
    readonly isTimingMonotonic: boolean;
  };
  readonly luminanceStability: {
    readonly lumaDelta13Percent: number;
    readonly isLumaStable: boolean;
  };
  readonly textureQuality: {
    readonly laplacianVariance: number;
    readonly isTextureWithinNaturalBounds: boolean;
  };
  readonly moireGridScore: {
    readonly periodicGridEnergy: number;
    readonly displayReplaySuspected: boolean;
  };
  /**
   * Reclassified: Image-derived specular highlight feature score [0.0 - 1.0].
   * Does NOT claim physical 3D corneal curvature measurement.
   */
  readonly specularHighlightScore?: {
    readonly score: number;
    readonly highlightProfileAcceptable: boolean;
  };
  /** Legacy alias for backwards compatibility with V20.7 test fixtures */
  readonly chromaticReflectionDelta?: {
    readonly flashHueShift: number;
    readonly specularCurvatureDetected: boolean;
  };
  readonly padDecision: 'PASS_LIVE_BONAFIDE' | 'REJECT_PRESENTATION_ATTACK';
  readonly padDecisionReason: string;
  readonly fusionOutcome?: PadFusionOutcome;
}

export interface CandidatePadEvaluationInput {
  readonly f1Aperture: number;
  readonly f2Aperture: number;
  readonly f3Aperture: number;
  readonly dt12Ms: number;
  readonly dt23Ms: number;
  readonly mu1Luma: number;
  readonly mu2Luma: number;
  readonly mu3Luma: number;
  readonly laplacianVar: number;
  readonly identityCosine13: number;
  readonly periodicScreenGridEnergy: number; // 0.0 to 1.0 (High on electronic displays)
  /** Image-derived specular highlight score (formerly activeChromaticReflectionDelta) */
  readonly specularHighlightFeatureScore?: number;
  /** Legacy alias for backward compatibility */
  readonly activeChromaticReflectionDelta?: number;
  readonly requestedChallengeAction?: 'UNPROMPTED_BLINK' | 'RANDOMIZED_CHALLENGE_SEQUENCE';
  readonly userCompliedWithAction?: boolean;
  readonly sequenceTimestampsMs?: [number, number, number];
  readonly challengeIssuedAtMs?: number;
  readonly challengeExpiresAtMs?: number;
}

export interface MultiSignalFusionInput {
  readonly fiqaQualityAcceptable: boolean;
  readonly poseContinuityAcceptable: boolean;
  readonly eyelidApertureClosureRatio: number; // Apex / Open <= 0.60
  readonly opticalFeatures: OpticalDisplayFeatures;
  readonly sequenceTimingsValid: boolean;
  readonly dynamicChallengeCompliant: boolean;
  readonly identitySimilarity: number;
}

export class CandidatePadHardenedEngine {
  // Baseline Production Constants (Preserved for comparison)
  public static readonly BASELINE_MAX_APEX_RATIO = 0.60;
  public static readonly BASELINE_MAX_LUMA_DELTA = 0.15;
  public static readonly BASELINE_MIN_IDENTITY_COSINE = 0.85;
  public static readonly BASELINE_MIN_LAPLACIAN = 110.0;
  public static readonly BASELINE_MAX_LAPLACIAN = 1500.0;

  // Candidate Hardened Thresholds (Tested in isolated experimental harness)
  public static readonly CANDIDATE_MAX_MOIRE_GRID_ENERGY = 0.38;
  public static readonly CANDIDATE_MIN_SPECULAR_SCORE = 0.12;

  /**
   * Extracts real optical display features from a raw image Buffer.
   */
  public static async extractOpticalFeatures(
    imageBuffer: Buffer,
    roi?: BoundingBoxROI
  ): Promise<OpticalDisplayFeatures> {
    return OpticalDisplayFeatureExtractor.extractFromImageBuffer(imageBuffer, { roi });
  }

  /**
   * Validates frame sequence continuity and timestamp monotonicity.
   */
  public static validateFrameSequenceContinuity(
    timestampsMs: [number, number, number],
    issuedAtMs?: number,
    expiresAtMs?: number
  ): { isValid: boolean; failureReason?: string } {
    const [t0, t1, t2] = timestampsMs;

    // Invariant 1: Monotonicity
    if (t0 >= t1 || t1 >= t2) {
      return { isValid: false, failureReason: 'NON_MONOTONIC_TIMESTAMPS' };
    }

    // Invariant 2: Inter-frame interval bounds [40ms, 350ms]
    const dt01 = t1 - t0;
    const dt12 = t2 - t1;
    if (dt01 < 40 || dt01 > 350 || dt12 < 40 || dt12 > 350) {
      return { isValid: false, failureReason: 'INVALID_INTER_FRAME_INTERVAL' };
    }

    // Invariant 3: Challenge freshness
    if (issuedAtMs !== undefined && t0 < issuedAtMs) {
      return { isValid: false, failureReason: 'FRAME_PREDATES_CHALLENGE' };
    }
    if (expiresAtMs !== undefined && t2 > expiresAtMs) {
      return { isValid: false, failureReason: 'CHALLENGE_EXPIRED' };
    }

    return { isValid: true };
  }

  /**
   * Seven-Signal Decision Fusion Pipeline.
   * Categorizes capture into formal ISO/IEC 30107-3 experimental states.
   */
  public static fusePadSignals(input: MultiSignalFusionInput): {
    outcome: PadFusionOutcome;
    reason: string;
  } {
    // 1. Image Quality Signal Check
    if (!input.fiqaQualityAcceptable) {
      return {
        outcome: 'CAPTURE_QUALITY_INSUFFICIENT',
        reason: 'FIQA_QUALITY_BELOW_ACCEPTABLE_THRESHOLD',
      };
    }

    // 2. Frame Sequence & Monotonicity Check
    if (!input.sequenceTimingsValid) {
      return {
        outcome: 'CHALLENGE_INVALID',
        reason: 'TEMPORAL_SEQUENCE_CONTINUITY_VIOLATED',
      };
    }

    // 3. Dynamic Challenge Compliance Check
    if (!input.dynamicChallengeCompliant) {
      return {
        outcome: 'CHALLENGE_INVALID',
        reason: 'DYNAMIC_CHALLENGE_NON_COMPLIANT',
      };
    }

    // 4. Optical Spatial Artifact (Moiré) Check
    if (input.opticalFeatures.isLowQualityOrCorrupt) {
      return {
        outcome: 'SIGNAL_UNAVAILABLE',
        reason: 'OPTICAL_FEATURE_EXTRACTION_UNAVAILABLE',
      };
    }

    if (input.opticalFeatures.moirePatternDetected) {
      return {
        outcome: 'PRESENTATION_ATTACK_SUSPECTED',
        reason: 'ELECTRONIC_DISPLAY_PERIODIC_GRID_DETECTED',
      };
    }

    // 5. Eye-Blink Temporal Aperture Check
    if (input.eyelidApertureClosureRatio > this.BASELINE_MAX_APEX_RATIO) {
      return {
        outcome: 'PRESENTATION_ATTACK_SUSPECTED',
        reason: 'INSUFFICIENT_OCULAR_CLOSURE_TRAJECTORY',
      };
    }

    // 6. Identity Continuity Check
    if (input.identitySimilarity < this.BASELINE_MIN_IDENTITY_COSINE) {
      return {
        outcome: 'PRESENTATION_ATTACK_SUSPECTED',
        reason: 'IDENTITY_DISCONTINUITY_DETECTED',
      };
    }

    // 7. Pose Continuity Check
    if (!input.poseContinuityAcceptable) {
      return {
        outcome: 'MANUAL_REVIEW_REQUIRED',
        reason: 'BORDERLINE_POSE_INSTABILITY',
      };
    }

    return {
      outcome: 'BONA_FIDE_CANDIDATE',
      reason: 'ALL_MULTI_FACTOR_SIGNALS_SATISFIED',
    };
  }

  /**
   * Evaluates capture burst under baseline production rules.
   */
  public static evaluateBaselinePolicy(input: CandidatePadEvaluationInput): PadDiagnosticTelemetry {
    const compressionRatio = input.f1Aperture > 0 ? input.f2Aperture / input.f1Aperture : 1.0;
    const lumaDelta = Math.abs(input.mu1Luma - input.mu3Luma) / Math.max(input.mu1Luma, input.mu3Luma, 1.0);

    const timingOk = input.dt12Ms >= 40 && input.dt12Ms <= 350 && input.dt23Ms >= 40 && input.dt23Ms <= 350;
    const closureOk = compressionRatio <= this.BASELINE_MAX_APEX_RATIO;
    const lumaOk = lumaDelta <= this.BASELINE_MAX_LUMA_DELTA;
    const textureOk = input.laplacianVar >= this.BASELINE_MIN_LAPLACIAN && input.laplacianVar <= this.BASELINE_MAX_LAPLACIAN;
    const identityOk = input.identityCosine13 >= this.BASELINE_MIN_IDENTITY_COSINE;

    let passed = timingOk && closureOk && lumaOk && textureOk && identityOk;
    let reason = 'ALL_BASELINE_INVARIANTS_PASSED';

    if (!timingOk) reason = 'INVALID_INTER_FRAME_TIMING';
    else if (!closureOk) reason = 'OCULAR_CLOSURE_MISSING';
    else if (!lumaOk) reason = 'PHOTOMETRIC_STEP_JUMP';
    else if (!textureOk) reason = 'LAPLACIAN_TEXTURE_OUT_OF_BOUNDS';
    else if (!identityOk) reason = 'IDENTITY_DISCONTINUITY';

    return {
      challengeId: 'DIAG-BASELINE-01',
      challengeActionRequested: 'UNPROMPTED_BLINK',
      challengeOutcome: closureOk ? 'CHALLENGE_COMPLIANT' : 'CHALLENGE_MISMATCH',
      earSequence: {
        f1OpenEar: input.f1Aperture,
        f2ApexEar: input.f2Aperture,
        f3RecoveryEar: input.f3Aperture,
        apexCompressionRatio: Number(compressionRatio.toFixed(4)),
        earClassification: closureOk ? 'GENUINE_BLINK_TRAJECTORY' : 'INSUFFICIENT_CLOSURE',
      },
      timingIrregularityMs: {
        dt12: input.dt12Ms,
        dt23: input.dt23Ms,
        isTimingMonotonic: timingOk,
      },
      luminanceStability: {
        lumaDelta13Percent: Number((lumaDelta * 100).toFixed(2)),
        isLumaStable: lumaOk,
      },
      textureQuality: {
        laplacianVariance: Number(input.laplacianVar.toFixed(2)),
        isTextureWithinNaturalBounds: textureOk,
      },
      moireGridScore: {
        periodicGridEnergy: Number(input.periodicScreenGridEnergy.toFixed(4)),
        displayReplaySuspected: input.periodicScreenGridEnergy >= this.CANDIDATE_MAX_MOIRE_GRID_ENERGY,
      },
      padDecision: passed ? 'PASS_LIVE_BONAFIDE' : 'REJECT_PRESENTATION_ATTACK',
      padDecisionReason: reason,
      fusionOutcome: passed ? 'BONA_FIDE_CANDIDATE' : 'PRESENTATION_ATTACK_SUSPECTED',
    };
  }

  /**
   * Evaluates capture burst under candidate hardened multi-factor policy.
   */
  public static evaluateCandidateHardenedPolicy(input: CandidatePadEvaluationInput): PadDiagnosticTelemetry {
    // 1. Run baseline criteria
    const baseline = this.evaluateBaselinePolicy(input);
    if (baseline.padDecision === 'REJECT_PRESENTATION_ATTACK') {
      return baseline;
    }

    // 2. Layer 1: Electronic Display Grid Periodic Energy (Moiré)
    const isScreenGridDetected = input.periodicScreenGridEnergy >= this.CANDIDATE_MAX_MOIRE_GRID_ENERGY;
    if (isScreenGridDetected) {
      return {
        ...baseline,
        padDecision: 'REJECT_PRESENTATION_ATTACK',
        padDecisionReason: 'ELECTRONIC_DISPLAY_PERIODIC_GRID_DETECTED',
        moireGridScore: {
          periodicGridEnergy: input.periodicScreenGridEnergy,
          displayReplaySuspected: true,
        },
        fusionOutcome: 'PRESENTATION_ATTACK_SUSPECTED',
      };
    }

    // 3. Layer 2: Dynamic Randomized Challenge Compliance
    if (input.requestedChallengeAction === 'RANDOMIZED_CHALLENGE_SEQUENCE') {
      const isCompliant = input.userCompliedWithAction === true;
      if (!isCompliant) {
        return {
          ...baseline,
          challengeActionRequested: 'RANDOMIZED_CHALLENGE_SEQUENCE',
          challengeOutcome: 'CHALLENGE_MISMATCH',
          padDecision: 'REJECT_PRESENTATION_ATTACK',
          padDecisionReason: 'RANDOMIZED_CHALLENGE_RESPONSE_NON_COMPLIANT',
          fusionOutcome: 'CHALLENGE_INVALID',
        };
      }
    }

    // 4. Layer 3: Specular Highlight Feature Score (Reclassified Image-derived heuristic)
    const specularScore =
      input.specularHighlightFeatureScore ?? input.activeChromaticReflectionDelta;

    if (specularScore !== undefined) {
      const isSpecularAdequate = specularScore >= this.CANDIDATE_MIN_SPECULAR_SCORE;
      if (!isSpecularAdequate) {
        return {
          ...baseline,
          padDecision: 'REJECT_PRESENTATION_ATTACK',
          padDecisionReason: 'SPECULAR_CORNEAL_CURVATURE_ABSENT',
          specularHighlightScore: {
            score: specularScore,
            highlightProfileAcceptable: false,
          },
          chromaticReflectionDelta: {
            flashHueShift: specularScore,
            specularCurvatureDetected: false,
          },
          fusionOutcome: 'PRESENTATION_ATTACK_SUSPECTED',
        };
      }
    }

    return {
      ...baseline,
      challengeActionRequested: input.requestedChallengeAction || 'UNPROMPTED_BLINK',
      challengeOutcome: 'CHALLENGE_COMPLIANT',
      padDecision: 'PASS_LIVE_BONAFIDE',
      padDecisionReason: 'MULTI_FACTOR_HARDENED_INVARIANTS_PASSED',
      specularHighlightScore: specularScore !== undefined
        ? {
            score: specularScore,
            highlightProfileAcceptable: true,
          }
        : undefined,
      chromaticReflectionDelta: specularScore !== undefined
        ? {
            flashHueShift: specularScore,
            specularCurvatureDetected: true,
          }
        : undefined,
      fusionOutcome: 'BONA_FIDE_CANDIDATE',
    };
  }

  /**
   * Experimental side-by-side comparison mode.
   * Compares baseline decision with candidate hardened decision without modifying production auth.
   */
  public static comparePoliciesInIsolatedMode(input: CandidatePadEvaluationInput): {
    readonly baseline: PadDiagnosticTelemetry;
    readonly candidate: PadDiagnosticTelemetry;
    readonly policyAgreement: boolean;
    readonly isVulnerabilityIntercepted: boolean;
  } {
    const baseline = this.evaluateBaselinePolicy(input);
    const candidate = this.evaluateCandidateHardenedPolicy(input);

    const policyAgreement = baseline.padDecision === candidate.padDecision;
    const isVulnerabilityIntercepted =
      baseline.padDecision === 'PASS_LIVE_BONAFIDE' &&
      candidate.padDecision === 'REJECT_PRESENTATION_ATTACK';

    return {
      baseline,
      candidate,
      policyAgreement,
      isVulnerabilityIntercepted,
    };
  }
}
