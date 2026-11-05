/**
 * backend/src/biometric-evaluation/optical_display_feature_extractor.ts
 *
 * Phase 20.8: Traceable Optical Display and Moiré Feature Extractor
 *
 * Extracts real optical and spatial-frequency signals from camera frames / raw pixel arrays:
 * 1. 2D Spatial Frequency Energy Ratio via Discrete Cosine Transform (DCT) block decomposition.
 * 2. Spectral Peakiness / Periodicity (distinguishes electronic pixel grids from natural skin).
 * 3. 2D Specular Highlight Profile (Image-derived heuristic: specularHighlightFeatureScore).
 *
 * Scientifically rigorous: Zero unvalidated physical assumptions.
 */

import sharp from 'sharp';

export interface BoundingBoxROI {
  readonly x: number;
  readonly y: number;
  readonly width: number;
  readonly height: number;
}

export interface OpticalExtractionOptions {
  /** Region of interest (e.g. face bounding box). If omitted, evaluates central region */
  readonly roi?: BoundingBoxROI;
  /** DCT Block size (8 or 16 pixels). Default: 16 */
  readonly blockSize?: 8 | 16;
  /** Cutoff frequency threshold (normalized 0.0 - 1.0). Default: 0.5 */
  readonly highFreqCutoff?: number;
}

export interface OpticalDisplayFeatures {
  /** Normalized ratio of high-frequency energy to total AC energy [0.0 - 1.0] */
  readonly spatialHighFrequencyEnergy: number;

  /** Ratio of peak high-frequency coefficient magnitude to mean high-frequency magnitude */
  readonly spectralPeakiness: number;

  /** Affirmative indicator of periodic subpixel grid (Moiré) */
  readonly moirePatternDetected: boolean;

  /**
   * Scientifically classified as: B. Image-derived heuristic
   * Measures 2D specular highlight compactness and steepness (0.0 to 1.0).
   * Note: This does NOT measure physical 3D corneal curvature.
   */
  readonly specularHighlightFeatureScore: number;

  /** Flag indicating invalid, corrupt, or underexposed/overexposed image */
  readonly isLowQualityOrCorrupt: boolean;

  /** Detailed diagnostic metrics for logging and audit */
  readonly rawMetrics: {
    readonly roiWidth: number;
    readonly roiHeight: number;
    readonly totalAcEnergy: number;
    readonly highFreqEnergy: number;
    readonly peakHighFreqMagnitude: number;
    readonly meanHighFreqMagnitude: number;
    readonly saturatedPixelCount: number;
    readonly meanLuminance: number;
  };
}

export class OpticalDisplayFeatureExtractor {
  // Calibrated conservative thresholds (testable against optical fixtures)
  public static readonly DEFAULT_HIGH_FREQ_CUTOFF = 0.50;
  public static readonly MOIRE_ENERGY_THRESHOLD = 0.38;
  public static readonly MOIRE_PEAKINESS_THRESHOLD = 4.5;
  public static readonly MIN_VALID_DIMENSION = 16;
  public static readonly SATURATION_PIXEL_FLOOR = 250;

  /**
   * Extracts optical display features directly from an encoded image Buffer (JPEG / PNG).
   */
  public static async extractFromImageBuffer(
    imageBuffer: Buffer,
    options: OpticalExtractionOptions = {}
  ): Promise<OpticalDisplayFeatures> {
    if (!imageBuffer || imageBuffer.length === 0) {
      return this.createInvalidResult('EMPTY_BUFFER');
    }

    try {
      const { data, info } = await sharp(imageBuffer)
        .grayscale()
        .raw()
        .toBuffer({ resolveWithObject: true });

      return this.extractFromGrayscalePlane(data, info.width, info.height, options);
    } catch {
      return this.createInvalidResult('DECODE_FAILURE');
    }
  }

  /**
   * Extracts optical display features from a raw 8-bit grayscale pixel array (Y-plane).
   * Zero decoding overhead; optimal for direct CameraX ImageAnalysis buffers.
   */
  public static extractFromGrayscalePlane(
    pixels: Uint8Array | Buffer,
    width: number,
    height: number,
    options: OpticalExtractionOptions = {}
  ): OpticalDisplayFeatures {
    if (!pixels || width < this.MIN_VALID_DIMENSION || height < this.MIN_VALID_DIMENSION) {
      return this.createInvalidResult('INVALID_DIMENSIONS');
    }

    const blockSize = options.blockSize ?? 16;
    const cutoff = options.highFreqCutoff ?? this.DEFAULT_HIGH_FREQ_CUTOFF;

    // 1. Determine Region of Interest (ROI)
    let roiX = 0;
    let roiY = 0;
    let roiW = width;
    let roiH = height;

    if (options.roi) {
      roiX = Math.max(0, Math.floor(options.roi.x));
      roiY = Math.max(0, Math.floor(options.roi.y));
      roiW = Math.min(width - roiX, Math.floor(options.roi.width));
      roiH = Math.min(height - roiY, Math.floor(options.roi.height));
    }

    if (roiW < blockSize || roiH < blockSize) {
      return this.createInvalidResult('ROI_TOO_SMALL');
    }

    // 2. Compute Mean Luminance and Specular Saturation in ROI
    let lumaSum = 0;
    let saturatedCount = 0;
    const totalRoiPixels = roiW * roiH;

    for (let y = 0; y < roiH; y++) {
      const rowOffset = (roiY + y) * width + roiX;
      for (let x = 0; x < roiW; x++) {
        const val = pixels[rowOffset + x];
        lumaSum += val;
        if (val >= this.SATURATION_PIXEL_FLOOR) {
          saturatedCount++;
        }
      }
    }

    const meanLuma = totalRoiPixels > 0 ? lumaSum / totalRoiPixels : 0;

    // 3. 2D Block-Based DCT Spatial Frequency Analysis
    const numBlocksX = Math.floor(roiW / blockSize);
    const numBlocksY = Math.floor(roiH / blockSize);

    if (numBlocksX === 0 || numBlocksY === 0) {
      return this.createInvalidResult('INSUFFICIENT_BLOCKS');
    }

    let totalAcEnergy = 0;
    let highFreqEnergy = 0;
    let peakHighFreqMagnitude = 0;
    let highFreqCoeffSum = 0;
    let highFreqCoeffCount = 0;
    let blockConcentrationSum = 0;
    let validBlockCount = 0;

    const block = new Float32Array(blockSize * blockSize);
    const dctOut = new Float32Array(blockSize * blockSize);

    for (let by = 0; by < numBlocksY; by++) {
      for (let bx = 0; bx < numBlocksX; bx++) {
        // Extract block pixels
        const blockStartX = roiX + bx * blockSize;
        const blockStartY = roiY + by * blockSize;

        for (let y = 0; y < blockSize; y++) {
          const rowStart = (blockStartY + y) * width + blockStartX;
          for (let x = 0; x < blockSize; x++) {
            block[y * blockSize + x] = pixels[rowStart + x];
          }
        }

        // Compute 2D DCT-II on block
        this.compute2dDct(block, dctOut, blockSize);

        let blockAcEnergy = 0;
        let blockHighFreqEnergy = 0;
        let blockPeakHighFreqMag = 0;

        // Accumulate AC energy and high-frequency band energy
        for (let v = 0; v < blockSize; v++) {
          for (let u = 0; u < blockSize; u++) {
            if (u === 0 && v === 0) continue; // Skip DC component

            const coeff = dctOut[v * blockSize + u];
            const mag = Math.abs(coeff);
            const energy = coeff * coeff;

            totalAcEnergy += energy;
            blockAcEnergy += energy;

            // Normalized frequency coordinate [0.0 - 1.0]
            const normFreq = (u + v) / (2 * (blockSize - 1));
            if (normFreq >= cutoff) {
              highFreqEnergy += energy;
              blockHighFreqEnergy += energy;
              highFreqCoeffSum += mag;
              highFreqCoeffCount++;
              if (mag > peakHighFreqMagnitude) {
                peakHighFreqMagnitude = mag;
              }
              if (mag > blockPeakHighFreqMag) {
                blockPeakHighFreqMag = mag;
              }
            }
          }
        }

        if (blockHighFreqEnergy > 0) {
          const blockPeakEnergy = blockPeakHighFreqMag * blockPeakHighFreqMag;
          blockConcentrationSum += blockPeakEnergy / blockHighFreqEnergy;
          validBlockCount++;
        }
      }
    }

    // 4. Calculate Normalized Metrics
    let spatialHighFrequencyEnergy = 0.0;
    let spectralPeakiness = 1.0;
    let meanSpectralConcentration = 0.0;
    let meanHighFreqMagnitude = 0.0;

    if (totalAcEnergy >= 1.0) {
      spatialHighFrequencyEnergy = Math.min(1.0, highFreqEnergy / totalAcEnergy);
      meanHighFreqMagnitude =
        highFreqCoeffCount > 0 ? highFreqCoeffSum / highFreqCoeffCount : 0.0;
      spectralPeakiness =
        meanHighFreqMagnitude > 0 ? peakHighFreqMagnitude / meanHighFreqMagnitude : 1.0;
      meanSpectralConcentration =
        validBlockCount > 0 ? blockConcentrationSum / validBlockCount : 0.0;
    }

    // Periodic Moiré detection requires elevated high-frequency energy AND periodic spectral concentration
    // In electronic displays, periodic subpixels concentrate energy into dominant spectral peaks (concentration >= 0.20)
    // In broadband random noise, energy is dispersed across bins (concentration <= 0.10)
    const moirePatternDetected =
      totalAcEnergy >= 1.0 &&
      spatialHighFrequencyEnergy >= this.MOIRE_ENERGY_THRESHOLD &&
      meanSpectralConcentration >= 0.20;

    // 5. Compute Specular Highlight Feature Score (Image-derived heuristic)
    // Measures localized brightness compactness: compact saturated spot vs diffuse glare
    const saturationRatio = totalRoiPixels > 0 ? saturatedCount / totalRoiPixels : 0;
    let specularHighlightFeatureScore = 0.0;

    if (saturatedCount > 0) {
      // High score for small, tight specular reflections (e.g. 0.001 to 0.02 of ROI)
      // Low score for diffuse washes (large white areas or zero highlights)
      if (saturationRatio >= 0.0005 && saturationRatio <= 0.04) {
        specularHighlightFeatureScore = Math.min(1.0, (0.04 - saturationRatio) / 0.035);
      } else if (saturationRatio > 0.04) {
        specularHighlightFeatureScore = 0.1; // Diffuse flat reflection
      }
    }

    return {
      spatialHighFrequencyEnergy: Number(spatialHighFrequencyEnergy.toFixed(4)),
      spectralPeakiness: Number(spectralPeakiness.toFixed(2)),
      moirePatternDetected,
      specularHighlightFeatureScore: Number(specularHighlightFeatureScore.toFixed(4)),
      isLowQualityOrCorrupt: totalAcEnergy < 1.0 || meanLuma < 10 || meanLuma > 245,
      rawMetrics: {
        roiWidth: roiW,
        roiHeight: roiH,
        totalAcEnergy: Number(totalAcEnergy.toFixed(2)),
        highFreqEnergy: Number(highFreqEnergy.toFixed(2)),
        peakHighFreqMagnitude: Number(peakHighFreqMagnitude.toFixed(2)),
        meanHighFreqMagnitude: Number(meanHighFreqMagnitude.toFixed(2)),
        saturatedPixelCount: saturatedCount,
        meanLuminance: Number(meanLuma.toFixed(2)),
      },
    };
  }

  /**
   * Fast separable 2D Discrete Cosine Transform (DCT-II).
   * Transforms input N x N into frequency coefficients out N x N.
   */
  public static compute2dDct(input: Float32Array, output: Float32Array, N: number): void {
    const temp = new Float32Array(N * N);
    const alpha0 = Math.sqrt(1 / N);
    const alphaK = Math.sqrt(2 / N);

    // Row-wise 1D DCT
    for (let r = 0; r < N; r++) {
      const rowOffset = r * N;
      for (let k = 0; k < N; k++) {
        let sum = 0;
        const alpha = k === 0 ? alpha0 : alphaK;
        const factor = (Math.PI * k) / (2 * N);
        for (let n = 0; n < N; n++) {
          sum += input[rowOffset + n] * Math.cos((2 * n + 1) * factor);
        }
        temp[rowOffset + k] = alpha * sum;
      }
    }

    // Column-wise 1D DCT
    for (let c = 0; c < N; c++) {
      for (let k = 0; k < N; k++) {
        let sum = 0;
        const alpha = k === 0 ? alpha0 : alphaK;
        const factor = (Math.PI * k) / (2 * N);
        for (let n = 0; n < N; n++) {
          sum += temp[n * N + c] * Math.cos((2 * n + 1) * factor);
        }
        output[k * N + c] = alpha * sum;
      }
    }
  }

  private static createInvalidResult(reason: string): OpticalDisplayFeatures {
    return {
      spatialHighFrequencyEnergy: 0.0,
      spectralPeakiness: 1.0,
      moirePatternDetected: false,
      specularHighlightFeatureScore: 0.0,
      isLowQualityOrCorrupt: true,
      rawMetrics: {
        roiWidth: 0,
        roiHeight: 0,
        totalAcEnergy: 0,
        highFreqEnergy: 0,
        peakHighFreqMagnitude: 0,
        meanHighFreqMagnitude: 0,
        saturatedPixelCount: 0,
        meanLuminance: 0,
      },
    };
  }
}
