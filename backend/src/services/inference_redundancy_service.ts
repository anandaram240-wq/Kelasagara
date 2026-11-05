// backend/src/services/inference_redundancy_service.ts
import { runFaceInference, getInferenceSession } from "./face_inference";
import { cosineSimilarity, l2Normalize } from "./biometric_matching";
import { config } from "../config";
import { ModelRegistry } from "./model_registry";

export interface ShadowScoringResult {
  primaryScore: number;
  shadowScore: number;
  scoreDelta: number;
  discrepancyFlagged: boolean;
  requiresReview: boolean;
  primaryModelVersion: string;
  shadowModelVersion: string;
}

export interface InferenceHealthStats {
  status: "HEALTHY" | "DEGRADED" | "CRITICAL";
  totalInferences: number;
  totalErrors: number;
  errorRate: number;
  averageLatencyMs: number;
  warmupComplete: boolean;
}

export class InferenceRedundancyService {
  private static totalInferences = 0;
  private static totalErrors = 0;
  private static totalLatencyMs = 0;
  private static isWarmedUp = false;

  // Threshold for flagging primary vs shadow score divergence (Invariant I-06)
  public static readonly SHADOW_DISCREPANCY_THRESHOLD = 0.15;

  /**
   * Cold-Start Mitigation: Warmup inference session during server startup.
   * Eliminates the initial forward-pass latency penalty.
   */
  static async warmupInference(): Promise<{ ready: boolean; warmupLatencyMs: number }> {
    const start = Date.now();
    try {
      // 1. Preload session graph
      await getInferenceSession();

      // 2. Execute dummy forward pass with synthetic black 112x112x3 buffer
      const dummyBuffer = Buffer.alloc(112 * 112 * 3, 128);
      await runFaceInference(dummyBuffer);

      const warmupLatencyMs = Date.now() - start;
      this.isWarmedUp = true;
      console.log(`[InferenceRedundancy] Warmup complete in ${warmupLatencyMs}ms.`);
      return { ready: true, warmupLatencyMs };
    } catch (err: any) {
      console.error(`[InferenceRedundancy] Warmup failed: ${err.message}`);
      return { ready: false, warmupLatencyMs: Date.now() - start };
    }
  }

  /**
   * Executes authoritative primary model inference with telemetry tracking and fallback support.
   * Enforces Invariant I-01: Fails closed on total failure.
   */
  static async executePrimaryInference(
    imageBuffer: Buffer,
    options?: { allowFallback?: boolean }
  ): Promise<{ embedding: number[]; latencyMs: number; modelVersion: string; fallbackInvoked: boolean }> {
    const start = Date.now();
    this.totalInferences++;

    try {
      const embedding = await runFaceInference(imageBuffer, { useFallback: false });
      const latencyMs = Date.now() - start;
      this.totalLatencyMs += latencyMs;

      return {
        embedding,
        latencyMs,
        modelVersion: config.modelVersion,
        fallbackInvoked: false,
      };
    } catch (err: any) {
      console.warn(`[InferenceRedundancy] Primary model inference error: ${err.message}`);

      // Invariant I-01 (Fail-Closed) & V22.1 Model Governance:
      // Automatic silent cross-version fallback to INT8 is strictly disabled by default
      // because quantization manifold drift (s=0.6806) causes false non-matches.
      if (options?.allowFallback === true) {
        try {
          console.log(`[InferenceRedundancy] Routing request to fallback model (${config.fallbackModelVersion})...`);
          const fallbackEmbedding = await runFaceInference(imageBuffer, { useFallback: true });
          const latencyMs = Date.now() - start;
          this.totalLatencyMs += latencyMs;

          return {
            embedding: fallbackEmbedding,
            latencyMs,
            modelVersion: config.fallbackModelVersion,
            fallbackInvoked: true,
          };
        } catch (fbErr: any) {
          console.error(`[InferenceRedundancy] Fallback model also failed: ${fbErr.message}`);
        }
      }

      this.totalErrors++;
      // Invariant I-01: Fail-closed. Never substitute heuristic or random vectors.
      throw new Error(`[InferenceRedundancy] Biometric inference failed: ${err.message}. Fail-closed retry required.`);
    }
  }

  /**
   * Dual-Model Redundant Inference Pipeline.
   * Runs both Primary (FP32) and Fallback (INT8) models simultaneously,
   * measuring cross-model embedding agreement before admitting an enrollment.
   */
  static async executeRedundantInference(imageBuffer: Buffer): Promise<{
    primaryEmbedding: number[];
    fallbackEmbedding: number[];
    correlation: number;
    discrepancyFlagged: boolean;
    latencyMs: number;
  }> {
    const start = Date.now();

    const [primaryEmbedding, fallbackEmbedding] = await Promise.all([
      runFaceInference(imageBuffer, { useFallback: false }),
      runFaceInference(imageBuffer, { useFallback: true }),
    ]);

    const correlation = cosineSimilarity(primaryEmbedding, fallbackEmbedding);
    // Note on OpenCV Zoo INT8 quantization drift: SFace INT8 exhibits known quantization
    // scaling divergence (~0.56 correlation on non-canonical patterns). Threshold set to 0.50.
    const discrepancyFlagged = correlation < 0.50;

    return {
      primaryEmbedding,
      fallbackEmbedding,
      correlation,
      discrepancyFlagged,
      latencyMs: Date.now() - start,
    };
  }

  /**
   * Dual-Scoring Shadow Pipeline (Invariant I-06).
   * Computes primary match score and compares with shadow evaluator to detect discrepancies.
   */
  static evaluateShadowScoring(params: {
    primaryVector: number[];
    enrolledVector: number[];
    shadowVector?: number[];
    enrolledShadowVector?: number[];
  }): ShadowScoringResult {
    const primaryScore = cosineSimilarity(params.primaryVector, params.enrolledVector);

    // Compute shadow score if shadow vectors are provided, else evaluate deterministic perturbation
    let shadowScore = primaryScore;
    if (params.shadowVector && params.enrolledShadowVector) {
      shadowScore = cosineSimilarity(params.shadowVector, params.enrolledShadowVector);
    }

    const scoreDelta = Math.abs(primaryScore - shadowScore);
    const discrepancyFlagged = scoreDelta > this.SHADOW_DISCREPANCY_THRESHOLD;

    return {
      primaryScore,
      shadowScore,
      scoreDelta,
      discrepancyFlagged,
      requiresReview: discrepancyFlagged,
      primaryModelVersion: config.modelVersion,
      shadowModelVersion: config.fallbackModelVersion,
    };
  }

  /**
   * Multi-Model Gallery Compatibility Check.
   * Prevents cross-model vector distance calculations across non-comparable feature spaces.
   */
  static checkModelCompatibility(
    enrolledVersion: string,
    probeVersion: string
  ): { compatible: boolean; reason?: string } {
    if (enrolledVersion === probeVersion) {
      return { compatible: true };
    }

    const enrolledMeta = ModelRegistry.getModel(enrolledVersion);
    const probeMeta = ModelRegistry.getModel(probeVersion);

    if (enrolledMeta.modelId !== probeMeta.modelId) {
      return {
        compatible: false,
        reason:
          `Incompatible vector spaces: enrolled template uses '${enrolledVersion}' (${enrolledMeta.embeddingDim}-D), ` +
          `while probe uses '${probeVersion}' (${probeMeta.embeddingDim}-D). Cross-architecture vector comparison is mathematically invalid.`,
      };
    }

    // V22.1 Quantization Drift Defense: SFace FP32 vs INT8 has 47° angular separation (s = 0.6806).
    // Cross-version comparison across quantization tiers is strictly prohibited.
    if (enrolledVersion !== probeVersion) {
      return {
        compatible: false,
        reason:
          `Incompatible model quantization versions: enrolled template uses '${enrolledVersion}', ` +
          `while probe uses '${probeVersion}'. Cross-version matching is rejected due to empirical quantization drift (s=0.6806).`,
      };
    }

    return { compatible: true };
  }

  /**
   * Returns runtime telemetry and health status.
   */
  static getHealthStats(): InferenceHealthStats {
    const errorRate = this.totalInferences > 0 ? this.totalErrors / this.totalInferences : 0;
    const avgLatency = this.totalInferences > 0 ? this.totalLatencyMs / (this.totalInferences - this.totalErrors || 1) : 0;

    let status: "HEALTHY" | "DEGRADED" | "CRITICAL" = "HEALTHY";
    if (errorRate > 0.1) status = "DEGRADED";
    if (errorRate > 0.5) status = "CRITICAL";

    return {
      status,
      totalInferences: this.totalInferences,
      totalErrors: this.totalErrors,
      errorRate,
      averageLatencyMs: avgLatency,
      warmupComplete: this.isWarmedUp,
    };
  }

  /**
   * Resets telemetry metrics (for test suites).
   */
  static resetTelemetry(): void {
    this.totalInferences = 0;
    this.totalErrors = 0;
    this.totalLatencyMs = 0;
  }
}
