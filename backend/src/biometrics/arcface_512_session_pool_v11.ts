/**
 * KELASAGARA BIOMETRIC ENGINE V11.0 — PHASE 11.1
 * File: backend/src/biometrics/arcface_512_session_pool_v11.ts
 *
 * Zero-Allocation 512-D AdaFace/ArcFace ONNX Session Pool with:
 * - CPU Memory Arena Disabled (`enableCpuMemArena: false`)
 * - Pre-Allocated Static Float32Array(37632) Tensor Ring Buffers
 * - Full V10 (128-D SFace) Backward Compatibility & Lazy Vault Upgrade on 1:1 eKYC
 */

import {
  ALIGNED_FACE_SIZE,
  ALIGNED_TENSOR_ELEMENTS,
  DEFAULT_QUALITY_THRESHOLDS_V11,
  FivePointLandmarks,
  FrameQualityMetricsV11,
  QualityGateThresholdsV11,
  estimateUmeyamaTransformV11,
  evaluateFrameQualityV11,
  warpRgbToNormalizedNchwTensorV11,
} from './umeyama_aligner_v11';
import {
  CentroidFusionResultV11,
  WeightedEmbeddingCandidateV11,
  cosineSimilarityV11,
  fuseQualityWeightedCentroidV11,
  l2NormalizeEmbeddingV11,
} from './centroid_fusion_v11';

export type BiometricModelVersion = 'v10_sface_128' | 'v11_adaface_512';

export interface RawBurstFrameInputV11 {
  readonly pixels: Uint8Array | Uint8ClampedArray;
  readonly width: number;
  readonly height: number;
  readonly channels: 3 | 4;
  readonly landmarks: FivePointLandmarks;
}

export interface OnnxRuntimeSessionOptionsV11 {
  readonly enableCpuMemArena: false;
  readonly enableMemPattern: false;
  readonly intraOpNumThreads: number;
  readonly interOpNumThreads: number;
  readonly graphOptimizationLevel: 'all';
}

/**
 * Pluggable ONNX Execution Backend so production binds to `onnxruntime-node`
 * while unit tests can inject deterministic 512-D and 128-D neural fixtures.
 */
export interface OnnxInferenceBackendV11 {
  run512D(normalizedNchwTensor: Float32Array): Promise<Float32Array>;
  run128DLegacy?(normalizedNchwTensor: Float32Array): Promise<Float32Array>;
}

export interface SessionSlotV11 {
  readonly slotId: number;
  readonly staticInputTensorBuffer: Float32Array;
  inUse: boolean;
}

export interface BurstExtractionOutputV11 {
  readonly modelVersion: 'v11_adaface_512';
  readonly fusion: CentroidFusionResultV11;
  readonly perFrameQuality: readonly FrameQualityMetricsV11[];
  readonly medianFrameLatencyMs: number;
  readonly totalPipelineLatencyMs: number;
  readonly sessionOptions: OnnxRuntimeSessionOptionsV11;
}

export interface StoredVaultTemplateRecord {
  readonly uid: string;
  readonly faceId: string;
  readonly lockToken: string;
  readonly modelVersion: BiometricModelVersion;
  readonly embedding: Float32Array | readonly number[];
}

export interface DualVersionVerifyOutcomeV11 {
  readonly verified: boolean;
  readonly similarityScore: number;
  readonly appliedThreshold: number;
  readonly evaluatedModelVersion: BiometricModelVersion;
  readonly shouldUpgradeVaultToV11: boolean;
  readonly upgradedV11Centroid?: Float32Array;
}

export interface SessionPoolConfigV11 {
  readonly poolSize?: number;
  readonly v10LegacyVerifyThreshold?: number;
  readonly v11ProductionVerifyThreshold?: number;
  readonly qualityThresholds?: QualityGateThresholdsV11;
}

// Backward-compatibility interfaces
export interface QualityWeightedFrame {
  embedding: number[];
  qualityScore: number;
  timestampMs?: number;
}

export interface FusionResult {
  fusedEmbedding: number[];
  dimension: 512 | 128;
  averageQuality: number;
  frameCount: number;
  modelVersion: BiometricModelVersion;
}

export class ArcFace512SessionPoolV11 {
  public static readonly DIMENSION_V11 = 512;
  public static readonly DIMENSION_V10 = 128;

  public readonly sessionOptions: OnnxRuntimeSessionOptionsV11 = {
    enableCpuMemArena: false,
    enableMemPattern: false,
    intraOpNumThreads: 2,
    interOpNumThreads: 1,
    graphOptimizationLevel: 'all',
  };

  private readonly slots: SessionSlotV11[] = [];
  private readonly waitQueue: Array<(slot: SessionSlotV11) => void> = [];
  private readonly poolSize: number;
  private readonly v10Threshold: number;
  private readonly v11Threshold: number;
  private readonly qualityThresholds: QualityGateThresholdsV11;

  constructor(
    private readonly backend: OnnxInferenceBackendV11,
    config: SessionPoolConfigV11 = {}
  ) {
    this.poolSize = config.poolSize ?? 4;
    this.v10Threshold = config.v10LegacyVerifyThreshold ?? 0.55;
    this.v11Threshold = config.v11ProductionVerifyThreshold ?? 0.62;
    this.qualityThresholds = config.qualityThresholds ?? DEFAULT_QUALITY_THRESHOLDS_V11;

    // Pre-allocate static Float32Array(37,632) tensor buffers once at startup
    for (let i = 0; i < this.poolSize; i++) {
      this.slots.push({
        slotId: i,
        staticInputTensorBuffer: new Float32Array(ALIGNED_TENSOR_ELEMENTS),
        inUse: false,
      });
    }
  }

  private async acquireSlot(): Promise<SessionSlotV11> {
    for (const slot of this.slots) {
      if (!slot.inUse) {
        slot.inUse = true;
        return slot;
      }
    }
    return new Promise<SessionSlotV11>((resolve) => {
      this.waitQueue.push(resolve);
    });
  }

  private releaseSlot(slot: SessionSlotV11): void {
    const nextResolver = this.waitQueue.shift();
    if (nextResolver) {
      nextResolver(slot);
    } else {
      slot.inUse = false;
    }
  }

  /**
   * Aligns a 1..3 frame capture burst via Umeyama 5-point similarity transform,
   * scores FIQA quality, executes 512-D inference using the pre-allocated static buffer,
   * and returns the quality-weighted L2 centroid.
   */
  public async extract512DBurstCentroid(
    frames: readonly RawBurstFrameInputV11[]
  ): Promise<BurstExtractionOutputV11> {
    if (frames.length === 0) {
      throw new Error('BIOMETRIC_V11_NO_FRAMES_PROVIDED');
    }

    const pipelineStart = performance.now();
    const slot = await this.acquireSlot();

    try {
      const perFrameQuality: FrameQualityMetricsV11[] = [];
      const weightedCandidates: WeightedEmbeddingCandidateV11[] = [];
      const frameLatencies: number[] = [];

      for (let i = 0; i < frames.length; i++) {
        const frameStart = performance.now();
        const frame = frames[i];

        // 1. Closed-form 5-point Umeyama similarity transform
        const alignment = estimateUmeyamaTransformV11(frame.landmarks);

        // 2. Zero-allocation bilinear warp into pre-allocated static tensor buffer
        warpRgbToNormalizedNchwTensorV11(
          frame.pixels,
          frame.width,
          frame.height,
          frame.channels,
          alignment.inverseMatrix,
          slot.staticInputTensorBuffer
        );

        // 3. Evaluate FIQA geometry and focus sharpness
        const quality = evaluateFrameQualityV11(
          alignment,
          slot.staticInputTensorBuffer,
          this.qualityThresholds
        );
        perFrameQuality.push(quality);

        if (!quality.passedQualityGate) {
          continue;
        }

        // 4. Execute 512-D ONNX backbone inference
        const raw512 = await this.backend.run512D(slot.staticInputTensorBuffer);
        if (raw512.length !== 512) {
          throw new Error(
            `BIOMETRIC_V11_INVALID_OUTPUT_DIM: Expected 512-D vector, got ${raw512.length}-D.`
          );
        }

        weightedCandidates.push({
          frameIndex: i,
          embedding: l2NormalizeEmbeddingV11(raw512),
          qualityWeight: quality.compositeQuality,
        });

        frameLatencies.push(performance.now() - frameStart);
      }

      if (weightedCandidates.length === 0) {
        const reasons = perFrameQuality
          .map((q) => q.rejectionReason ?? 'LOW_COMPOSITE_QUALITY')
          .join(',');
        throw new Error(`BIOMETRIC_V11_ALL_BURST_FRAMES_REJECTED_BY_FIQA:${reasons}`);
      }

      // 5. Fuse passing frames via quality-weighted centroid + outlier pruning
      const fusion = fuseQualityWeightedCentroidV11(weightedCandidates);

      frameLatencies.sort((a, b) => a - b);
      const medianFrameLatencyMs = Number(
        frameLatencies[Math.floor(frameLatencies.length / 2)].toFixed(3)
      );
      const totalPipelineLatencyMs = Number((performance.now() - pipelineStart).toFixed(3));

      return {
        modelVersion: 'v11_adaface_512',
        fusion,
        perFrameQuality,
        medianFrameLatencyMs,
        totalPipelineLatencyMs,
        sessionOptions: this.sessionOptions,
      };
    } finally {
      this.releaseSlot(slot);
    }
  }

  /**
   * 1:1 eKYC Verification with V10 (128-D) -> V11 (512-D) Backward Compatibility & Lazy Upgrade.
   *
   * - If the user's vault template is already `v11_adaface_512`, compares 512-D centroids directly.
   * - If the user's vault template is `v10_sface_128`, evaluates the legacy 128-D model for
   *   verification AND extracts the new 512-D centroid so the caller can atomically upgrade
   *   `biometric_vault/{uid}` upon a successful match.
   */
  public async verifyWithBackwardCompatibility(
    storedRecord: StoredVaultTemplateRecord,
    liveFrames: readonly RawBurstFrameInputV11[]
  ): Promise<DualVersionVerifyOutcomeV11> {
    const storedVec =
      storedRecord.embedding instanceof Float32Array
        ? storedRecord.embedding
        : new Float32Array(storedRecord.embedding);

    // Always extract the V11 512-D burst centroid from the live capture
    const liveV11 = await this.extract512DBurstCentroid(liveFrames);

    if (storedRecord.modelVersion === 'v11_adaface_512' || storedVec.length === 512) {
      const similarityScore = Number(
        cosineSimilarityV11(l2NormalizeEmbeddingV11(storedVec), liveV11.fusion.centroid).toFixed(6)
      );
      return {
        verified: similarityScore >= this.v11Threshold,
        similarityScore,
        appliedThreshold: this.v11Threshold,
        evaluatedModelVersion: 'v11_adaface_512',
        shouldUpgradeVaultToV11: false,
      };
    }

    // Legacy V10 (128-D SFace) verification path
    if (!this.backend.run128DLegacy) {
      throw new Error('BIOMETRIC_V11_LEGACY_V10_BACKEND_NOT_CONFIGURED');
    }

    const slot = await this.acquireSlot();
    let v10LegacyVector: Float32Array;
    try {
      const anchorIdx = liveV11.fusion.anchorFrameIndex;
      const anchorFrame = liveFrames[anchorIdx];
      const alignment = estimateUmeyamaTransformV11(anchorFrame.landmarks);

      warpRgbToNormalizedNchwTensorV11(
        anchorFrame.pixels,
        anchorFrame.width,
        anchorFrame.height,
        anchorFrame.channels,
        alignment.inverseMatrix,
        slot.staticInputTensorBuffer
      );

      v10LegacyVector = l2NormalizeEmbeddingV11(
        await this.backend.run128DLegacy(slot.staticInputTensorBuffer)
      );
    } finally {
      this.releaseSlot(slot);
    }

    const similarityScore = Number(
      cosineSimilarityV11(l2NormalizeEmbeddingV11(storedVec), v10LegacyVector).toFixed(6)
    );
    const verified = similarityScore >= this.v10Threshold;

    return {
      verified,
      similarityScore,
      appliedThreshold: this.v10Threshold,
      evaluatedModelVersion: 'v10_sface_128',
      shouldUpgradeVaultToV11: verified,
      upgradedV11Centroid: verified ? liveV11.fusion.centroid : undefined,
    };
  }

  public getPoolDiagnostics(): {
    poolSize: number;
    activeSlots: number;
    queuedWaiters: number;
    staticBufferBytesPerSlot: number;
  } {
    return {
      poolSize: this.poolSize,
      activeSlots: this.slots.filter((s) => s.inUse).length,
      queuedWaiters: this.waitQueue.length,
      staticBufferBytesPerSlot: ALIGNED_FACE_SIZE * ALIGNED_FACE_SIZE * 3 * 4,
    };
  }

  // ========================================================================
  // STATIC HELPER METHODS FOR V11 BACKWARD COMPATIBILITY
  // ========================================================================

  public static computeCosineSimilarity(
    a: number[] | Float32Array,
    b: number[] | Float32Array
  ): number {
    const arrA = a instanceof Float32Array ? a : new Float32Array(a);
    const arrB = b instanceof Float32Array ? b : new Float32Array(b);
    return cosineSimilarityV11(arrA, arrB);
  }

  public static fuseQualityWeightedCentroid(frames: QualityWeightedFrame[]): FusionResult {
    if (!frames || frames.length === 0) {
      throw new Error("ERR_EMPTY_FUSION_FRAMES: At least 1 frame required for centroid fusion.");
    }
    const targetDim = frames[0].embedding.length as 128 | 512;
    if (targetDim !== 512 && targetDim !== 128) {
      throw new Error(`ERR_INVALID_EMBEDDING_DIM: Expected 128 or 512 dimensions, got ${targetDim}`);
    }

    const candidates: WeightedEmbeddingCandidateV11[] = frames.map((f, i) => ({
      frameIndex: i,
      embedding: new Float32Array(f.embedding),
      qualityWeight: f.qualityScore,
    }));

    const result = fuseQualityWeightedCentroidV11(candidates);
    return {
      fusedEmbedding: Array.from(result.centroid).map((v) => Number(v.toFixed(6))),
      dimension: result.dimension,
      averageQuality: result.aggregateQualityScore,
      frameCount: result.retainedFrameIndices.length,
      modelVersion: result.dimension === 512 ? "v11_adaface_512" : "v10_sface_128",
    };
  }
}

export const Arcface512SessionPoolV11 = ArcFace512SessionPoolV11;
export type Arcface512SessionPoolV11 = ArcFace512SessionPoolV11;
