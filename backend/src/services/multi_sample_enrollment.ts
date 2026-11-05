// backend/src/services/multi_sample_enrollment.ts
/**
 * Track D: Multi-Sample Biometric Enrollment Engine (Ticket D-02).
 * Constructs high-stability centroid templates with yaw diversity and outlier pruning.
 * Enforces Invariants I-01 (Fail-Closed) and I-12 (Quality Gates).
 */

export interface EnrollmentCandidateFrame {
  frameId: string;
  embedding: number[];
  yawDegrees: number;
  qualityScore: number;
}

export interface MultiSampleEnrollmentTemplate {
  centroid: number[];
  exemplars: number[][];
  frameCount: number;
  meanCoherence: number;
  enrolledAt: string;
}

export class MultiSampleEnrollmentService {
  private static readonly MIN_FRAMES = 5;
  private static readonly OUTLIER_COSINE_THRESHOLD = 0.65;
  private static readonly MIN_COHERENCE_THRESHOLD = 0.70;

  private static cosine(a: number[], b: number[]): number {
    let dot = 0;
    for (let i = 0; i < a.length; i++) dot += a[i] * b[i];
    return dot;
  }

  private static l2Normalize(v: number[]): number[] {
    let sum = 0;
    for (let i = 0; i < v.length; i++) sum += v[i] * v[i];
    const norm = Math.max(1e-12, Math.sqrt(sum));
    return v.map((x) => x / norm);
  }

  /**
   * Enrolls a subject using at least 5 candidate frames.
   */
  static enroll(frames: EnrollmentCandidateFrame[]): MultiSampleEnrollmentTemplate {
    if (frames.length < this.MIN_FRAMES) {
      throw new Error(
        `[MultiSampleEnrollment] Insufficient frames: received ${frames.length}, required >= ${this.MIN_FRAMES}`
      );
    }

    // 1. Yaw diversity check
    const yaws = frames.map((f) => f.yawDegrees);
    const hasCenter = yaws.some((y) => Math.abs(y) <= 10.0);
    const hasLeftOrRight = yaws.some((y) => Math.abs(y) > 10.0);

    if (!hasCenter || !hasLeftOrRight) {
      throw new Error(
        `[MultiSampleEnrollment] Yaw diversity failure: frames lack required angular coverage (center + angled)`
      );
    }

    // 2. Outlier Rejection via Mean Cosine
    const validFrames: EnrollmentCandidateFrame[] = [];
    for (let i = 0; i < frames.length; i++) {
      let sumCosine = 0;
      let count = 0;
      for (let j = 0; j < frames.length; j++) {
        if (i !== j) {
          sumCosine += this.cosine(frames[i].embedding, frames[j].embedding);
          count++;
        }
      }
      const meanSim = count > 0 ? sumCosine / count : 1.0;
      if (meanSim >= this.OUTLIER_COSINE_THRESHOLD) {
        validFrames.push(frames[i]);
      }
    }

    if (validFrames.length < 3) {
      throw new Error(
        `[MultiSampleEnrollment] Invariant I-01 Fail-Closed: High intra-frame divergence (${validFrames.length} valid frames remaining after outlier pruning)`
      );
    }

    // 3. Compute L2-Normalized Centroid
    const dim = validFrames[0].embedding.length;
    const centroidAccumulator = new Array(dim).fill(0);
    for (const f of validFrames) {
      for (let d = 0; d < dim; d++) {
        centroidAccumulator[d] += f.embedding[d];
      }
    }
    const centroid = this.l2Normalize(centroidAccumulator);

    // 4. Compute Mean Coherence to Centroid
    let coherenceSum = 0;
    const scoredExemplars = validFrames.map((f) => {
      const sim = this.cosine(f.embedding, centroid);
      coherenceSum += sim;
      return { frame: f, sim };
    });
    const meanCoherence = coherenceSum / validFrames.length;

    if (meanCoherence < this.MIN_COHERENCE_THRESHOLD) {
      throw new Error(
        `[MultiSampleEnrollment] Mean coherence ${meanCoherence.toFixed(3)} < ${this.MIN_COHERENCE_THRESHOLD}. Subject identity inconsistent.`
      );
    }

    // 5. Select 2 highest-quality exemplars closest to centroid
    scoredExemplars.sort((a, b) => b.sim - a.sim);
    const exemplars = scoredExemplars.slice(0, 2).map((e) => e.frame.embedding);

    return {
      centroid,
      exemplars,
      frameCount: validFrames.length,
      meanCoherence: parseFloat(meanCoherence.toFixed(4)),
      enrolledAt: new Date().toISOString(),
    };
  }

  /**
   * Evaluates empirical gain of multi-sample centroid over 1-sample enrollment.
   */
  static evaluateCentroidGain(
    multiTemplate: MultiSampleEnrollmentTemplate,
    singleFrame: EnrollmentCandidateFrame,
    probes: number[][]
  ): { centroidMeanSim: number; singleMeanSim: number; deltaGainPct: number } {
    const cSims = probes.map((p) => this.cosine(p, multiTemplate.centroid));
    const sSims = probes.map((p) => this.cosine(p, singleFrame.embedding));

    const cMean = cSims.reduce((s, x) => s + x, 0) / probes.length;
    const sMean = sSims.reduce((s, x) => s + x, 0) / probes.length;
    const gain = ((cMean - sMean) / sMean) * 100.0;

    return {
      centroidMeanSim: parseFloat(cMean.toFixed(4)),
      singleMeanSim: parseFloat(sMean.toFixed(4)),
      deltaGainPct: parseFloat(gain.toFixed(2)),
    };
  }
}
