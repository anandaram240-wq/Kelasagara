// backend/src/evaluation/bootstrap_statistics.ts
/**
 * Rigorous Statistical Engine for Biometric Evaluations (Ticket G-04).
 * Enforces identity-level cluster bootstrap (>= 2000 resamples),
 * paired model-vs-model comparisons, Holm-Bonferroni family-wise error control,
 * and Rule-of-Three error bounds.
 */

export interface SubjectTrial {
  subjectId: string;
  comparisonId: string;
  similarity: number;
  isGenuine: boolean;
  group?: string; // Demographic or quality grouping
}

export interface BootstrapConfidenceInterval {
  pointEstimate: number;
  ciLower95: number;
  ciUpper95: number;
  resamples: number;
  sampleCount: number;
  ruleOfThreeUpperBound?: number;
}

export interface PairedComparisonResult {
  metricName: string;
  modelAEstimate: number;
  modelBEstimate: number;
  deltaEstimate: number;
  deltaCiLower95: number;
  deltaCiUpper95: number;
  pValue: number;
  isStatisticallySignificant: boolean;
}

export class BootstrapStatisticsEngine {
  /**
   * Rule of Three: Upper bound for 0 observed errors at 95% confidence.
   * If k = 0 errors observed in N independent trials, True Rate <= 3 / N.
   */
  static ruleOfThreeBound(trials: number): number {
    if (trials <= 0) return 1.0;
    return 3.0 / trials;
  }

  /**
   * Performs identity-level cluster bootstrap for a single model's metric.
   * Resamples unique subject IDs with replacement to account for intra-subject correlation.
   */
  static computeIdentityBootstrapCi(
    trials: SubjectTrial[],
    metricFn: (sampledTrials: SubjectTrial[]) => number,
    iterations = 2000
  ): BootstrapConfidenceInterval {
    if (trials.length === 0) {
      throw new Error("Cannot run bootstrap on empty trials.");
    }

    // 1. Group trials by subject ID
    const subjectMap = new Map<string, SubjectTrial[]>();
    for (const t of trials) {
      const arr = subjectMap.get(t.subjectId) || [];
      arr.push(t);
      subjectMap.set(t.subjectId, arr);
    }

    const uniqueSubjects = Array.from(subjectMap.keys());
    const N = uniqueSubjects.length;

    // 2. Point estimate
    const pointEstimate = metricFn(trials);

    // 3. Resample subjects with replacement
    const bootstrapDist: number[] = [];
    for (let b = 0; b < iterations; b++) {
      const resampledTrials: SubjectTrial[] = [];
      for (let s = 0; s < N; s++) {
        const pickedSubject = uniqueSubjects[Math.floor(Math.random() * N)];
        const subTrials = subjectMap.get(pickedSubject)!;
        for (const t of subTrials) {
          resampledTrials.push(t);
        }
      }
      bootstrapDist.push(metricFn(resampledTrials));
    }

    bootstrapDist.sort((a, b) => a - b);
    const lowerIdx = Math.floor(iterations * 0.025);
    const upperIdx = Math.floor(iterations * 0.975);

    return {
      pointEstimate,
      ciLower95: bootstrapDist[lowerIdx],
      ciUpper95: bootstrapDist[upperIdx],
      resamples: iterations,
      sampleCount: trials.length,
      ruleOfThreeUpperBound: this.ruleOfThreeBound(trials.length),
    };
  }

  /**
   * Performs paired identity-level cluster bootstrap for Model A vs Model B.
   */
  static computePairedBootstrapComparison(
    trialsA: SubjectTrial[],
    trialsB: SubjectTrial[],
    metricFn: (sampledTrials: SubjectTrial[]) => number,
    metricName = "TAR",
    iterations = 2000
  ): PairedComparisonResult {
    const estA = metricFn(trialsA);
    const estB = metricFn(trialsB);
    const deltaEst = estA - estB;

    // Map by subject ID
    const subMapA = new Map<string, SubjectTrial[]>();
    for (const t of trialsA) {
      const arr = subMapA.get(t.subjectId) || [];
      arr.push(t);
      subMapA.set(t.subjectId, arr);
    }

    const subMapB = new Map<string, SubjectTrial[]>();
    for (const t of trialsB) {
      const arr = subMapB.get(t.subjectId) || [];
      arr.push(t);
      subMapB.set(t.subjectId, arr);
    }

    const commonSubjects = Array.from(subMapA.keys()).filter((s) => subMapB.has(s));
    const N = commonSubjects.length;

    const deltaDist: number[] = [];
    let zeroCrossings = 0;

    for (let b = 0; b < iterations; b++) {
      const sampledA: SubjectTrial[] = [];
      const sampledB: SubjectTrial[] = [];

      for (let s = 0; s < N; s++) {
        const pickedSub = commonSubjects[Math.floor(Math.random() * N)];
        for (const t of subMapA.get(pickedSub)!) sampledA.push(t);
        for (const t of subMapB.get(pickedSub)!) sampledB.push(t);
      }

      const valA = metricFn(sampledA);
      const valB = metricFn(sampledB);
      const diff = valA - valB;
      deltaDist.push(diff);

      if (deltaEst > 0 && diff <= 0) zeroCrossings++;
      if (deltaEst < 0 && diff >= 0) zeroCrossings++;
    }

    deltaDist.sort((a, b) => a - b);
    const lowerIdx = Math.floor(iterations * 0.025);
    const upperIdx = Math.floor(iterations * 0.975);
    const pValue = (2.0 * zeroCrossings) / iterations; // Two-sided empirical p-value

    return {
      metricName,
      modelAEstimate: estA,
      modelBEstimate: estB,
      deltaEstimate: deltaEst,
      deltaCiLower95: deltaDist[lowerIdx],
      deltaCiUpper95: deltaDist[upperIdx],
      pValue: Math.min(1.0, pValue),
      isStatisticallySignificant: deltaDist[lowerIdx] > 0 || deltaDist[upperIdx] < 0,
    };
  }

  /**
   * Applies Holm-Bonferroni correction to an array of p-values.
   * Controls family-wise error rate across multiple candidate models.
   */
  static applyHolmBonferroni(
    pValues: { id: string; pValue: number }[],
    alpha = 0.05
  ): { id: string; originalP: number; adjustedAlpha: number; isSignificant: boolean }[] {
    const sorted = [...pValues].sort((a, b) => a.pValue - b.pValue);
    const m = sorted.length;
    const results = [];

    let isPreviousSignificant = true;
    for (let k = 0; k < m; k++) {
      const adjustedAlpha = alpha / (m - k);
      const significant = isPreviousSignificant && sorted[k].pValue <= adjustedAlpha;
      if (!significant) isPreviousSignificant = false;

      results.push({
        id: sorted[k].id,
        originalP: sorted[k].pValue,
        adjustedAlpha,
        isSignificant: significant,
      });
    }

    return results;
  }
}
