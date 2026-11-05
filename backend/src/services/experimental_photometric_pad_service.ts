// backend/src/services/experimental_photometric_pad_service.ts
//
// KELASAGARA BIOMATCH V19.6.8
// Measurement Semantics & Scientific Refactor: Experimental Photometric PAD Feasibility Service
// Standards: ISO/IEC 30107-3:2023, ISO/IEC 24745:2022
//
// SCIENTIFIC PRINCIPLE:
// Separates objective physical feature measurement from uncalibrated research interpretation.
// Renames speculative 'specular' metrics to physical 'high-luma' pixel counts to prevent
// deceptive validation claims. Evaluates both baseline and illuminated image quality.
//
// NON-ENFORCING SAFETY INVARIANT:
// This service is strictly a research and telemetry measurement tool.
// It CANNOT approve enrollments, CANNOT override server challenge rejections,
// and CANNOT alter biometric similarity or duplicate thresholds.

import sharp from "sharp";

/**
 * Objective optical and pixel-level feature measurements extracted from
 * standardized 112x112 facial regions before and after active illumination.
 */
export interface PhotometricFeatureMeasurement {
  sampleDimensions: { width: number; height: number; totalPixels: number };
  baselineLuma8Bit: number;       // Mean luma [0, 255]
  illuminatedLuma8Bit: number;     // Mean luma [0, 255]
  absoluteLumaDelta: number;       // (illuminated - baseline) [-255, 255]
  relativeLumaDelta: number;       // (illuminated - baseline) / max(baseline, 1.0) [dimensionless]
  highLumaPixelCount: number;      // Pixels with luma >= HIGH_LUMA_CUTOFF (245)
  highLumaPixelRatio: number;      // highLumaPixelCount / totalPixels [0.0, 1.0]
  /** @deprecated Use highLumaPixelCount */
  specularPixelCount: number;      // Backward-compatible alias
  /** @deprecated Use highLumaPixelRatio */
  specularSaturationRatio: number; // Backward-compatible alias
  qualityIndicators: {
    baselineUnderexposed: boolean;    // baseline < 15
    baselineOverexposed: boolean;     // baseline > 240
    illuminatedUnderexposed: boolean; // illuminated < 15
    illuminatedOverexposed: boolean;  // illuminated > 240
    isSeverelyUnderexposed: boolean;  // baseline < 15 || illuminated < 15
    isSeverelyOverexposed: boolean;   // baseline > 240 || illuminated > 240
    hasValidContrast: boolean;        // baseline span >= 20 && illuminated span >= 20
    isQualityAcceptable: boolean;     // !isSeverelyUnderexposed && !isSeverelyOverexposed
  };
}

/**
 * Isolated, non-authoritative experimental interpretation.
 * Explicitly marked as UNVALIDATED without physical device calibration.
 */
export interface PhotometricExperimentalInterpretation {
  provenance: "UNVALIDATED_THEORETICAL_HYPOTHESIS";
  status: "UNCALIBRATED_EXPERIMENTAL_ONLY";
  candidateComparison: "UNVALIDATED_DIFFUSE_CANDIDATE" | "UNVALIDATED_SPECULAR_CANDIDATE" | "INCONCLUSIVE";
  unvalidatedThresholdsUsed: {
    candidateDiffuseDeltaMin: number;
    candidateHighLumaRatioMax: number;
    candidateReplayHighLumaRatioMin: number;
    highLumaCutoff: number;
    /** @deprecated Use candidateHighLumaRatioMax */
    candidateSpecularRatioMax: number;
    /** @deprecated Use candidateReplayHighLumaRatioMin */
    candidateReplayRatioMin: number;
    /** @deprecated Use highLumaCutoff */
    specularLumaCutoff: number;
  };
  scientificDisclaimer: string;
}

/**
 * Full telemetry analysis payload. Retains backward-compatible root fields
 * while exposing clearly delineated measurement and interpretation structures.
 */
export interface PhotometricAnalysisResult {
  isEnforcing: false;
  experimentOnly: true;
  measurement: PhotometricFeatureMeasurement;
  interpretation: PhotometricExperimentalInterpretation;

  // Measurement fields
  highLumaPixelCount: number;
  highLumaPixelRatio: number;

  // Backward-compatibility aliases for existing telemetry consumers
  baselineLuma: number;
  illuminatedLuma: number;
  deltaLuma: number;
  specularPixelCount: number;
  specularSaturationRatio: number;
  classification: "CANDIDATE_DIFFUSE_RESPONSE" | "CANDIDATE_SPECULAR_REPLAY" | "INCONCLUSIVE";
  details: string;
}

export class ExperimentalPhotometricPadService {
  // Physical high-luma cutoff (>= 245 in 8-bit luma)
  public static readonly HIGH_LUMA_CUTOFF = 245;
  public static readonly CANDIDATE_DIFFUSE_DELTA_MIN = 0.04; // 4% theoretical relative gain
  public static readonly CANDIDATE_DIFFUSE_HIGH_LUMA_RATIO_MAX = 0.03; // Max 3% high luma pixels
  public static readonly CANDIDATE_REPLAY_HIGH_LUMA_RATIO_MIN = 0.05; // >= 5% high luma clipping hypothesis

  /** @deprecated Use HIGH_LUMA_CUTOFF */
  public static readonly SPECULAR_LUMA_CUTOFF = 245;
  /** @deprecated Use CANDIDATE_DIFFUSE_HIGH_LUMA_RATIO_MAX */
  public static readonly CANDIDATE_DIFFUSE_SPECULAR_RATIO_MAX = 0.03;
  /** @deprecated Use CANDIDATE_REPLAY_HIGH_LUMA_RATIO_MIN */
  public static readonly CANDIDATE_REPLAY_SPECULAR_RATIO_MIN = 0.05;

  private static readonly SCIENTIFIC_DISCLAIMER =
    "Experimental image-change features are being evaluated for possible usefulness in " +
    "presentation-attack detection. Their ability to distinguish live participants from " +
    "display replay has not been established on physical devices.";

  /**
   * Evaluates the photometric response of a subject across baseline and illuminated frames.
   * Separates mathematical feature extraction from unvalidated experimental categorization.
   */
  public static async evaluatePhotometricResponse(
    baselineInput: Buffer | string,
    illuminatedInput: Buffer | string
  ): Promise<PhotometricAnalysisResult> {
    try {
      const baseBuf = this.toBuffer(baselineInput);
      const illumBuf = this.toBuffer(illuminatedInput);

      if (!baseBuf || !illumBuf || baseBuf.length === 0 || illumBuf.length === 0) {
        return this.inconclusiveResult("Invalid or empty image buffer provided.");
      }

      // Standardize to 112x112 grayscale raw pixel planes
      const [basePlane, illumPlane] = await Promise.all([
        this.extractGrayscalePlane(baseBuf),
        this.extractGrayscalePlane(illumBuf),
      ]);

      if (!basePlane || !illumPlane || basePlane.data.length !== illumPlane.data.length) {
        return this.inconclusiveResult("Failed to decode standardized grayscale pixel plane.");
      }

      // Step A: Feature Measurement
      const measurement = this.computeFeatureMeasurement(basePlane.data, illumPlane.data);

      // Step B: Experimental Interpretation (Unvalidated Research Candidate Comparison)
      const interpretation = this.deriveExperimentalInterpretation(measurement);

      // Maintain backward-compatible classification aliases
      let legacyClassification: "CANDIDATE_DIFFUSE_RESPONSE" | "CANDIDATE_SPECULAR_REPLAY" | "INCONCLUSIVE";
      if (interpretation.candidateComparison === "UNVALIDATED_SPECULAR_CANDIDATE") {
        legacyClassification = "CANDIDATE_SPECULAR_REPLAY";
      } else if (interpretation.candidateComparison === "UNVALIDATED_DIFFUSE_CANDIDATE") {
        legacyClassification = "CANDIDATE_DIFFUSE_RESPONSE";
      } else {
        legacyClassification = "INCONCLUSIVE";
      }

      return {
        isEnforcing: false,
        experimentOnly: true,
        measurement,
        interpretation,
        baselineLuma: measurement.baselineLuma8Bit,
        illuminatedLuma: measurement.illuminatedLuma8Bit,
        deltaLuma: measurement.relativeLumaDelta,
        highLumaPixelCount: measurement.highLumaPixelCount,
        highLumaPixelRatio: measurement.highLumaPixelRatio,
        specularPixelCount: measurement.specularPixelCount,
        specularSaturationRatio: measurement.specularSaturationRatio,
        classification: legacyClassification,
        details: `${interpretation.scientificDisclaimer} Analysis: ${legacyClassification}`,
      };
    } catch (err) {
      return this.inconclusiveResult(`Exception during photometric evaluation: ${err}`);
    }
  }

  /**
   * Computes objective pixel and luma measurements with explicit scales and units.
   * Assesses underexposure, overexposure, and contrast span for BOTH baseline and illuminated frames.
   */
  private static computeFeatureMeasurement(
    baseData: Buffer,
    illumData: Buffer
  ): PhotometricFeatureMeasurement {
    const totalPixels = baseData.length;
    let sumBase = 0;
    let sumIllum = 0;
    let highLumaCount = 0;
    let minBase = 255;
    let maxBase = 0;
    let minIllum = 255;
    let maxIllum = 0;

    for (let i = 0; i < totalPixels; i++) {
      const b = baseData[i];
      const l = illumData[i];
      sumBase += b;
      sumIllum += l;

      if (b < minBase) minBase = b;
      if (b > maxBase) maxBase = b;
      if (l < minIllum) minIllum = l;
      if (l > maxIllum) maxIllum = l;

      if (l >= this.HIGH_LUMA_CUTOFF) {
        highLumaCount++;
      }
    }

    const baselineLuma = sumBase / totalPixels;
    const illuminatedLuma = sumIllum / totalPixels;
    const absDelta = illuminatedLuma - baselineLuma;
    const relDelta = absDelta / Math.max(baselineLuma, 1.0);
    const highLumaRatio = highLumaCount / totalPixels;

    const baselineUnderexposed = baselineLuma < 15;
    const baselineOverexposed = baselineLuma > 240;
    const baselineHasContrast = maxBase - minBase >= 20;

    const illuminatedUnderexposed = illuminatedLuma < 15;
    const illuminatedOverexposed = illuminatedLuma > 240;
    const illuminatedHasContrast = maxIllum - minIllum >= 20;

    const isSeverelyUnderexposed = baselineUnderexposed || illuminatedUnderexposed;
    const isSeverelyOverexposed = baselineOverexposed || illuminatedOverexposed;
    const hasValidContrast = baselineHasContrast && illuminatedHasContrast;
    const isQualityAcceptable = !isSeverelyUnderexposed && !isSeverelyOverexposed;

    return {
      sampleDimensions: { width: 112, height: 112, totalPixels },
      baselineLuma8Bit: Math.round(baselineLuma * 10) / 10,
      illuminatedLuma8Bit: Math.round(illuminatedLuma * 10) / 10,
      absoluteLumaDelta: Math.round(absDelta * 10) / 10,
      relativeLumaDelta: Math.round(relDelta * 1000) / 1000,
      highLumaPixelCount: highLumaCount,
      highLumaPixelRatio: Math.round(highLumaRatio * 1000) / 1000,
      specularPixelCount: highLumaCount,
      specularSaturationRatio: Math.round(highLumaRatio * 1000) / 1000,
      qualityIndicators: {
        baselineUnderexposed,
        baselineOverexposed,
        illuminatedUnderexposed,
        illuminatedOverexposed,
        isSeverelyUnderexposed,
        isSeverelyOverexposed,
        hasValidContrast,
        isQualityAcceptable,
      },
    };
  }

  /**
   * Derives research categorization while explicitly flagging it as unvalidated hypothesis.
   */
  private static deriveExperimentalInterpretation(
    measurement: PhotometricFeatureMeasurement
  ): PhotometricExperimentalInterpretation {
    const { relativeLumaDelta, highLumaPixelRatio, qualityIndicators } = measurement;

    let candidateComparison: "UNVALIDATED_DIFFUSE_CANDIDATE" | "UNVALIDATED_SPECULAR_CANDIDATE" | "INCONCLUSIVE";

    if (qualityIndicators.isSeverelyUnderexposed || qualityIndicators.isSeverelyOverexposed) {
      candidateComparison = "INCONCLUSIVE";
    } else if (highLumaPixelRatio >= this.CANDIDATE_REPLAY_HIGH_LUMA_RATIO_MIN) {
      candidateComparison = "UNVALIDATED_SPECULAR_CANDIDATE";
    } else if (
      relativeLumaDelta >= this.CANDIDATE_DIFFUSE_DELTA_MIN &&
      highLumaPixelRatio <= this.CANDIDATE_DIFFUSE_HIGH_LUMA_RATIO_MAX
    ) {
      candidateComparison = "UNVALIDATED_DIFFUSE_CANDIDATE";
    } else {
      candidateComparison = "INCONCLUSIVE";
    }

    return {
      provenance: "UNVALIDATED_THEORETICAL_HYPOTHESIS",
      status: "UNCALIBRATED_EXPERIMENTAL_ONLY",
      candidateComparison,
      unvalidatedThresholdsUsed: {
        candidateDiffuseDeltaMin: this.CANDIDATE_DIFFUSE_DELTA_MIN,
        candidateHighLumaRatioMax: this.CANDIDATE_DIFFUSE_HIGH_LUMA_RATIO_MAX,
        candidateReplayHighLumaRatioMin: this.CANDIDATE_REPLAY_HIGH_LUMA_RATIO_MIN,
        highLumaCutoff: this.HIGH_LUMA_CUTOFF,
        candidateSpecularRatioMax: this.CANDIDATE_DIFFUSE_SPECULAR_RATIO_MAX,
        candidateReplayRatioMin: this.CANDIDATE_REPLAY_SPECULAR_RATIO_MIN,
        specularLumaCutoff: this.SPECULAR_LUMA_CUTOFF,
      },
      scientificDisclaimer: this.SCIENTIFIC_DISCLAIMER,
    };
  }

  private static toBuffer(input: Buffer | string): Buffer | null {
    if (Buffer.isBuffer(input)) return input;
    if (typeof input === "string") {
      const cleaned = input.replace(/^data:image\/\w+;base64,/, "").trim();
      return Buffer.from(cleaned, "base64");
    }
    return null;
  }

  private static async extractGrayscalePlane(
    buffer: Buffer
  ): Promise<{ data: Buffer; width: number; height: number } | null> {
    try {
      const { data, info } = await sharp(buffer)
        .resize(112, 112)
        .grayscale()
        .raw()
        .toBuffer({ resolveWithObject: true });
      return { data, width: info.width, height: info.height };
    } catch {
      return null;
    }
  }

  private static inconclusiveResult(details: string): PhotometricAnalysisResult {
    const dummyMeasurement: PhotometricFeatureMeasurement = {
      sampleDimensions: { width: 112, height: 112, totalPixels: 12544 },
      baselineLuma8Bit: 0,
      illuminatedLuma8Bit: 0,
      absoluteLumaDelta: 0,
      relativeLumaDelta: 0,
      highLumaPixelCount: 0,
      highLumaPixelRatio: 0,
      specularPixelCount: 0,
      specularSaturationRatio: 0,
      qualityIndicators: {
        baselineUnderexposed: true,
        baselineOverexposed: false,
        illuminatedUnderexposed: true,
        illuminatedOverexposed: false,
        isSeverelyUnderexposed: true,
        isSeverelyOverexposed: false,
        hasValidContrast: false,
        isQualityAcceptable: false,
      },
    };

    const dummyInterpretation: PhotometricExperimentalInterpretation = {
      provenance: "UNVALIDATED_THEORETICAL_HYPOTHESIS",
      status: "UNCALIBRATED_EXPERIMENTAL_ONLY",
      candidateComparison: "INCONCLUSIVE",
      unvalidatedThresholdsUsed: {
        candidateDiffuseDeltaMin: this.CANDIDATE_DIFFUSE_DELTA_MIN,
        candidateHighLumaRatioMax: this.CANDIDATE_DIFFUSE_HIGH_LUMA_RATIO_MAX,
        candidateReplayHighLumaRatioMin: this.CANDIDATE_REPLAY_HIGH_LUMA_RATIO_MIN,
        highLumaCutoff: this.HIGH_LUMA_CUTOFF,
        candidateSpecularRatioMax: this.CANDIDATE_DIFFUSE_SPECULAR_RATIO_MAX,
        candidateReplayRatioMin: this.CANDIDATE_REPLAY_SPECULAR_RATIO_MIN,
        specularLumaCutoff: this.SPECULAR_LUMA_CUTOFF,
      },
      scientificDisclaimer: this.SCIENTIFIC_DISCLAIMER,
    };

    return {
      isEnforcing: false,
      experimentOnly: true,
      measurement: dummyMeasurement,
      interpretation: dummyInterpretation,
      highLumaPixelCount: 0,
      highLumaPixelRatio: 0,
      baselineLuma: 0,
      illuminatedLuma: 0,
      deltaLuma: 0,
      specularPixelCount: 0,
      specularSaturationRatio: 0,
      classification: "INCONCLUSIVE",
      details,
    };
  }
}
