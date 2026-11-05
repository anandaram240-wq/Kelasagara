/**
 * KELASAGARA BIOMETRIC ENGINE V11.0 — PHASE 11.1
 * File: backend/src/biometrics/centroid_fusion_v11.ts
 *
 * 3-Frame Quality-Weighted Centroid Fusion with Intra-Burst Outlier Pruning
 * and strict L2 Hypersphere Normalization.
 */

export interface WeightedEmbeddingCandidateV11 {
  readonly frameIndex: number;
  readonly embedding: Float32Array;
  readonly qualityWeight: number; // q_i in [0, 1]
}

export interface CentroidFusionPolicyV11 {
  readonly minIntraBurstCosine: number; // Frames below this cosine vs. anchor are pruned
  readonly minRetainedFrames: number;
}

export const DEFAULT_CENTROID_FUSION_POLICY_V11: CentroidFusionPolicyV11 = {
  minIntraBurstCosine: 0.45,
  minRetainedFrames: 1,
};

export interface CentroidFusionResultV11 {
  readonly centroid: Float32Array;
  readonly dimension: 128 | 512;
  readonly totalInputFrames: number;
  readonly retainedFrameIndices: readonly number[];
  readonly droppedOutlierIndices: readonly number[];
  readonly anchorFrameIndex: number;
  readonly intraBurstMinCosine: number;
  readonly intraBurstMeanCosine: number;
  readonly aggregateQualityScore: number;
}

/**
 * Normalizes a vector in-place or into a new Float32Array onto the unit L2 hypersphere.
 */
export function l2NormalizeEmbeddingV11(input: Float32Array): Float32Array {
  let sumSq = 0;
  for (let i = 0; i < input.length; i++) {
    sumSq += input[i] * input[i];
  }
  const norm = Math.sqrt(sumSq);
  if (norm < 1e-12) {
    throw new Error('BIOMETRIC_V11_ZERO_NORM_EMBEDDING: Cannot L2-normalize a zero vector.');
  }
  const invNorm = 1.0 / norm;
  const out = new Float32Array(input.length);
  for (let i = 0; i < input.length; i++) {
    out[i] = input[i] * invNorm;
  }
  return out;
}

/**
 * Computes cosine similarity between two unit-normalized embeddings of matching dimension.
 */
export function cosineSimilarityV11(a: Float32Array, b: Float32Array): number {
  if (a.length !== b.length) {
    throw new Error(
      `BIOMETRIC_V11_DIMENSION_MISMATCH: Cannot compare ${a.length}-D and ${b.length}-D vectors.`
    );
  }
  let dot = 0;
  let normA = 0;
  let normB = 0;
  for (let i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }
  const denom = Math.sqrt(normA * normB);
  if (denom < 1e-12) return 0;
  return Math.max(-1.0, Math.min(1.0, dot / denom));
}

/**
 * Fuses 1..N (standard k=3) burst frame embeddings into a single L2-normalized centroid:
 * 1. L2-normalizes each individual frame embedding.
 * 2. Selects the highest-quality frame as the burst anchor.
 * 3. Prunes any frame whose cosine similarity to the anchor is below `minIntraBurstCosine`.
 * 4. Computes the quality-weighted sum and projects the centroid back onto the unit hypersphere.
 */
export function fuseQualityWeightedCentroidV11(
  candidates: readonly WeightedEmbeddingCandidateV11[],
  policy: CentroidFusionPolicyV11 = DEFAULT_CENTROID_FUSION_POLICY_V11
): CentroidFusionResultV11 {
  if (candidates.length === 0) {
    throw new Error('BIOMETRIC_V11_EMPTY_BURST: At least one frame candidate is required.');
  }

  const dim = candidates[0].embedding.length;
  if (dim !== 128 && dim !== 512) {
    throw new Error(`BIOMETRIC_V11_UNSUPPORTED_DIM: Expected 128 or 512, received ${dim}.`);
  }

  // Normalize all candidate vectors and locate the highest-quality anchor frame
  const normalizedCandidates = candidates.map((c) => {
    if (c.embedding.length !== dim) {
      throw new Error('BIOMETRIC_V11_INCONSISTENT_BURST_DIMENSIONS');
    }
    return {
      frameIndex: c.frameIndex,
      embedding: l2NormalizeEmbeddingV11(c.embedding),
      qualityWeight: Math.max(0.01, Math.min(1.0, c.qualityWeight)),
    };
  });

  let anchorIdx = 0;
  for (let i = 1; i < normalizedCandidates.length; i++) {
    if (normalizedCandidates[i].qualityWeight > normalizedCandidates[anchorIdx].qualityWeight) {
      anchorIdx = i;
    }
  }
  const anchor = normalizedCandidates[anchorIdx];

  const retained: typeof normalizedCandidates = [];
  const retainedFrameIndices: number[] = [];
  const droppedOutlierIndices: number[] = [];

  for (const cand of normalizedCandidates) {
    const simToAnchor = cosineSimilarityV11(anchor.embedding, cand.embedding);
    if (simToAnchor >= policy.minIntraBurstCosine) {
      retained.push(cand);
      retainedFrameIndices.push(cand.frameIndex);
    } else {
      droppedOutlierIndices.push(cand.frameIndex);
    }
  }

  if (retained.length < policy.minRetainedFrames) {
    throw new Error(
      `BIOMETRIC_V11_BURST_CONSISTENCY_FAILURE: Only ${retained.length} frames passed consistency check.`
    );
  }

  // Compute quality-weighted centroid vector
  const rawCentroid = new Float32Array(dim);
  let weightSum = 0;

  for (const item of retained) {
    const w = item.qualityWeight;
    weightSum += w;
    for (let d = 0; d < dim; d++) {
      rawCentroid[d] += w * item.embedding[d];
    }
  }

  const centroid = l2NormalizeEmbeddingV11(rawCentroid);

  // Compute intra-burst stability telemetry against final centroid
  let minCosine = 1.0;
  let sumCosine = 0;
  for (const item of retained) {
    const sim = cosineSimilarityV11(centroid, item.embedding);
    if (sim < minCosine) minCosine = sim;
    sumCosine += sim;
  }

  const intraBurstMeanCosine = Number((sumCosine / retained.length).toFixed(6));
  const intraBurstMinCosine = Number(minCosine.toFixed(6));
  const aggregateQualityScore = Number((weightSum / retained.length).toFixed(6));

  return {
    centroid,
    dimension: dim,
    totalInputFrames: candidates.length,
    retainedFrameIndices,
    droppedOutlierIndices,
    anchorFrameIndex: anchor.frameIndex,
    intraBurstMinCosine,
    intraBurstMeanCosine,
    aggregateQualityScore,
  };
}
