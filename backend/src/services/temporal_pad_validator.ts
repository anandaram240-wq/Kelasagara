// backend/src/services/temporal_pad_validator.ts
/**
 * Temporal Presentation Attack Detection (PAD) Validator (Gate G-02 / Sprint 1).
 * Defends against static 2D printouts, high-resolution tablet replays, screen brightness injection,
 * and spliced multi-identity presentation attacks using 3-frame burst temporal dynamics.
 */

import sharp from 'sharp';
import { FaceInferenceService, YuNetDetection } from './face_inference';

export interface BiometricBurstClientMetadata {
  interFrameIntervalMs: number[];
  eulerYaw: number;
  eulerPitch: number;
  deviceTimestamp: string;
}

export interface BiometricBurstPayload {
  burstFramesBase64: [string, string, string]; // [frame1_open, frame2_apex, frame3_open]
  clientMetadata: BiometricBurstClientMetadata;
}

export interface TemporalPadValidationResult {
  passed: boolean;
  status: 'live_verified' | 'spoof_detected';
  rejectionReason?:
    | 'INVALID_BURST_STRUCTURE'
    | 'INVALID_INTER_FRAME_TIMING'
    | 'FACE_DETECTION_FAILED'
    | 'PHOTOMETRIC_STEP_JUMP'
    | 'OCULAR_CLOSURE_MISSING'
    | 'IDENTITY_DISCONTINUITY'
    | 'LAPLACIAN_TEXTURE_OUT_OF_BOUNDS';
  metrics?: {
    lumaMeans: [number, number, number];
    lumaRelativeDelta13: number;
    eyeApertureRatioF2F1: number;
    eyeApertureRatioF2F3: number;
    identityContinuityCosine13: number;
    laplacianVarianceF1: number;
  };
  frame1Embedding?: Float32Array;
  frame3Embedding?: Float32Array;
}

export class TemporalPadValidator {
  private static readonly MAX_LUMA_REL_DELTA = 0.15; // 15% max photometric shift
  private static readonly MAX_APEX_EYE_RATIO = 0.60; // Frame 2 eye height < 0.6 * Frame 1
  private static readonly MIN_IDENTITY_COSINE = 0.85; // Sim(u1, u3) >= 0.85
  private static readonly MIN_LAPLACIAN_VAR = 110.0;
  private static readonly MAX_LAPLACIAN_VAR = 1500.0;
  private static readonly MIN_INTERVAL_MS = 40;
  private static readonly MAX_INTERVAL_MS = 350;

  public static async validateBurst(
    payload: BiometricBurstPayload,
    inferenceService: FaceInferenceService
  ): Promise<TemporalPadValidationResult> {
    if (
      !payload ||
      !Array.isArray(payload.burstFramesBase64) ||
      payload.burstFramesBase64.length !== 3 ||
      payload.burstFramesBase64.some((f) => typeof f !== 'string' || f.length < 128)
    ) {
      return {
        passed: false,
        status: 'spoof_detected',
        rejectionReason: 'INVALID_BURST_STRUCTURE',
      };
    }

    const intervals = payload.clientMetadata?.interFrameIntervalMs;
    if (
      !Array.isArray(intervals) ||
      intervals.length !== 2 ||
      intervals.some(
        (dt) => !Number.isFinite(dt) || dt < this.MIN_INTERVAL_MS || dt > this.MAX_INTERVAL_MS
      )
    ) {
      return {
        passed: false,
        status: 'spoof_detected',
        rejectionReason: 'INVALID_INTER_FRAME_TIMING',
      };
    }

    const buffers = payload.burstFramesBase64.map((b64) => {
      const cleaned = b64.replace(/^data:image\/\w+;base64,/, '');
      return Buffer.from(cleaned, 'base64');
    }) as [Buffer, Buffer, Buffer];

    // 1. Decode all 3 frames & run YuNet face detection
    const detections: [YuNetDetection | null, YuNetDetection | null, YuNetDetection | null] = [
      await inferenceService.detectFaceYuNet(buffers[0]),
      await inferenceService.detectFaceYuNet(buffers[1]),
      await inferenceService.detectFaceYuNet(buffers[2]),
    ];

    if (!detections[0] || !detections[1] || !detections[2]) {
      return {
        passed: false,
        status: 'spoof_detected',
        rejectionReason: 'FACE_DETECTION_FAILED',
      };
    }

    // 2. Photometric Ambient Consistency across the 3 frames
    const lumaStats = await Promise.all(
      buffers.map((buf, idx) => this.computeFaceBoxLuma(buf, detections[idx]!))
    );
    const mu1 = lumaStats[0].mean;
    const mu2 = lumaStats[1].mean;
    const mu3 = lumaStats[2].mean;

    const lumaRelativeDelta13 = Math.abs(mu1 - mu3) / Math.max(mu1, mu3, 1.0);
    const lumaRelativeDelta12 = Math.abs(mu1 - mu2) / Math.max(mu1, mu2, 1.0);
    if (
      lumaRelativeDelta13 >= this.MAX_LUMA_REL_DELTA ||
      lumaRelativeDelta12 >= this.MAX_LUMA_REL_DELTA
    ) {
      return {
        passed: false,
        status: 'spoof_detected',
        rejectionReason: 'PHOTOMETRIC_STEP_JUMP',
      };
    }

    // 3. Ocular Closure Verification (Temporal Eyelid Aperture Delta)
    const [eyeH1, eyeH2, eyeH3] = await Promise.all([
      this.measureOcularVerticalAperture(buffers[0], detections[0]),
      this.measureOcularVerticalAperture(buffers[1], detections[1]),
      this.measureOcularVerticalAperture(buffers[2], detections[2]),
    ]);

    const eyeApertureRatioF2F1 = eyeH1 > 0 ? eyeH2 / eyeH1 : 1.0;
    const eyeApertureRatioF2F3 = eyeH3 > 0 ? eyeH2 / eyeH3 : 1.0;

    if (
      eyeApertureRatioF2F1 >= this.MAX_APEX_EYE_RATIO ||
      eyeApertureRatioF2F3 >= this.MAX_APEX_EYE_RATIO
    ) {
      return {
        passed: false,
        status: 'spoof_detected',
        rejectionReason: 'OCULAR_CLOSURE_MISSING',
      };
    }

    // 4. Frequency & Texture Analysis (2D Laplacian Variance on Aligned Crop 1)
    const alignedCrop1 = await inferenceService.alignFace112(buffers[0], detections[0]);
    const laplacianVarianceF1 = await this.computeLaplacianVariance112(alignedCrop1);
    if (
      laplacianVarianceF1 < this.MIN_LAPLACIAN_VAR ||
      laplacianVarianceF1 > this.MAX_LAPLACIAN_VAR
    ) {
      return {
        passed: false,
        status: 'spoof_detected',
        rejectionReason: 'LAPLACIAN_TEXTURE_OUT_OF_BOUNDS',
      };
    }

    // 5. Facial Identity Continuity: Sim(u1, u3) >= 0.85
    const alignedCrop3 = await inferenceService.alignFace112(buffers[2], detections[2]);
    const [u1, u3] = await Promise.all([
      inferenceService.extractEmbeddingFromAligned(alignedCrop1),
      inferenceService.extractEmbeddingFromAligned(alignedCrop3),
    ]);

    const identityContinuityCosine13 = this.cosineSimilarity(u1, u3);
    if (
      !Number.isFinite(identityContinuityCosine13) ||
      identityContinuityCosine13 < this.MIN_IDENTITY_COSINE
    ) {
      return {
        passed: false,
        status: 'spoof_detected',
        rejectionReason: 'IDENTITY_DISCONTINUITY',
      };
    }

    return {
      passed: true,
      status: 'live_verified',
      metrics: {
        lumaMeans: [mu1, mu2, mu3],
        lumaRelativeDelta13,
        eyeApertureRatioF2F1,
        eyeApertureRatioF2F3,
        identityContinuityCosine13,
        laplacianVarianceF1,
      },
      frame1Embedding: u1,
      frame3Embedding: u3,
    };
  }

  private static async computeFaceBoxLuma(
    imageBuffer: Buffer,
    det: YuNetDetection
  ): Promise<{ mean: number; std: number }> {
    const { data, info } = await sharp(imageBuffer)
      .grayscale()
      .raw()
      .toBuffer({ resolveWithObject: true });

    const x0 = Math.max(0, Math.floor(det.box.x));
    const y0 = Math.max(0, Math.floor(det.box.y));
    const x1 = Math.min(info.width - 1, Math.ceil(det.box.x + det.box.width));
    const y1 = Math.min(info.height - 1, Math.ceil(det.box.y + det.box.height));

    let sum = 0;
    let sumSq = 0;
    let count = 0;

    for (let y = y0; y <= y1; y++) {
      const rowOffset = y * info.width;
      for (let x = x0; x <= x1; x++) {
        const val = data[rowOffset + x];
        sum += val;
        sumSq += val * val;
        count++;
      }
    }

    if (count === 0) return { mean: 0, std: 0 };
    const mean = sum / count;
    const variance = Math.max(0, sumSq / count - mean * mean);
    return { mean, std: Math.sqrt(variance) };
  }

  /**
   * Computes vertical palpebral aperture height around YuNet's left and right eye landmarks
   * using vertical Sobel gradient energy projection.
   */
  public static async measureOcularVerticalAperture(
    imageBuffer: Buffer,
    det: YuNetDetection
  ): Promise<number> {
    const { data, info } = await sharp(imageBuffer)
      .grayscale()
      .raw()
      .toBuffer({ resolveWithObject: true });

    const ipd = Math.hypot(
      det.landmarks.leftEye.x - det.landmarks.rightEye.x,
      det.landmarks.leftEye.y - det.landmarks.rightEye.y
    );
    const halfW = Math.max(8, Math.round(ipd * 0.22));
    const halfH = Math.max(6, Math.round(ipd * 0.18));

    const measureSingleEye = (cx: number, cy: number): number => {
      const xStart = Math.max(1, Math.round(cx) - halfW);
      const xEnd = Math.min(info.width - 2, Math.round(cx) + halfW);
      const yStart = Math.max(1, Math.round(cy) - halfH);
      const yEnd = Math.min(info.height - 2, Math.round(cy) + halfH);

      const rowScores: number[] = [];
      for (let y = yStart; y <= yEnd; y++) {
        let rowEnergy = 0;
        for (let x = xStart; x <= xEnd; x++) {
          const idx = y * info.width + x;
          // Vertical gradient |I(y+1) - I(y-1)| + darkness weight (iris/pupil contrast)
          const gy = Math.abs(data[idx + info.width] - data[idx - info.width]);
          const darkness = 255 - data[idx];
          rowEnergy += gy * (1 + darkness / 255.0);
        }
        rowScores.push(rowEnergy / Math.max(1, xEnd - xStart + 1));
      }

      if (rowScores.length < 3) return 0;
      const peakEnergy = Math.max(...rowScores);
      const activeThreshold = peakEnergy * 0.42;

      let firstActiveRow = -1;
      let lastActiveRow = -1;
      for (let i = 0; i < rowScores.length; i++) {
        if (rowScores[i] >= activeThreshold) {
          if (firstActiveRow === -1) firstActiveRow = i;
          lastActiveRow = i;
        }
      }

      return firstActiveRow === -1 ? 1.0 : Math.max(1.0, lastActiveRow - firstActiveRow + 1);
    };

    const leftAperture = measureSingleEye(det.landmarks.leftEye.x, det.landmarks.leftEye.y);
    const rightAperture = measureSingleEye(det.landmarks.rightEye.x, det.landmarks.rightEye.y);
    return (leftAperture + rightAperture) * 0.5;
  }

  public static async computeLaplacianVariance112(alignedPngOrRaw: Buffer): Promise<number> {
    const { data, info } = await sharp(alignedPngOrRaw)
      .grayscale()
      .raw()
      .toBuffer({ resolveWithObject: true });

    const w = info.width;
    const h = info.height;
    let sum = 0;
    let sumSq = 0;
    let n = 0;

    for (let y = 1; y < h - 1; y++) {
      for (let x = 1; x < w - 1; x++) {
        const idx = y * w + x;
        const lap =
          data[idx - w] +
          data[idx + w] +
          data[idx - 1] +
          data[idx + 1] -
          4 * data[idx];
        sum += lap;
        sumSq += lap * lap;
        n++;
      }
    }

    if (n === 0) return 0;
    const mean = sum / n;
    return sumSq / n - mean * mean;
  }

  private static cosineSimilarity(a: Float32Array, b: Float32Array): number {
    if (a.length !== b.length || a.length === 0) return Number.NaN;
    let dot = 0;
    let normA = 0;
    let normB = 0;
    for (let i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    if (normA === 0 || normB === 0) return Number.NaN;
    return dot / (Math.sqrt(normA) * Math.sqrt(normB));
  }
}
