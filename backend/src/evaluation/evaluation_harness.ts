// backend/src/evaluation/evaluation_harness.ts
/**
 * Authoritative Biometric Evaluation Harness (Ticket T-11).
 * Calculates DET / ROC metrics, FNMR at FMR 1e-3 and 1e-4, AUC,
 * and 95% non-parametric bootstrap confidence intervals.
 */

export interface PairwiseComparison {
  similarity: number;
  isGenuine: boolean; // true = same person, false = different person (impostor)
}

export interface OperatingPoint {
  threshold: number;
  fmr: number;
  fnmr: number;
}

export interface EvaluationReport {
  totalComparisons: number;
  genuineCount: number;
  impostorCount: number;
  auc: number;
  isModelDiscriminating: boolean; // AUC >= 0.75
  operatingPointFmr1e3: OperatingPoint; // At or below FMR 0.001 (1e-3)
  operatingPointFmr1e4: OperatingPoint; // At or below FMR 0.0001 (1e-4)
  bootstrapCi95: {
    aucLower: number;
    aucUpper: number;
    fnmrAt1e3Lower: number;
    fnmrAt1e3Upper: number;
  };
  eer: number; // Equal Error Rate
}

export class BiometricEvaluationHarness {
  /**
   * Evaluates pairwise similarity scores to produce comprehensive DET/ROC metrics.
   */
  static evaluate(
    pairs: PairwiseComparison[],
    bootstrapIterations = 500
  ): EvaluationReport {
    const genuineScores = pairs.filter((p) => p.isGenuine).map((p) => p.similarity);
    const impostorScores = pairs.filter((p) => !p.isGenuine).map((p) => p.similarity);

    if (genuineScores.length === 0 || impostorScores.length === 0) {
      throw new Error("Evaluation requires both genuine and impostor comparisons.");
    }

    genuineScores.sort((a, b) => a - b);
    impostorScores.sort((a, b) => a - b);

    // 1. Calculate AUC via Mann-Whitney U statistic
    const auc = this.calculateAuc(genuineScores, impostorScores);

    // 2. Scan thresholds from 0.0 to 1.0 with step 0.005
    const thresholds: number[] = [];
    for (let t = 0; t <= 1.0001; t += 0.005) {
      thresholds.push(Math.round(t * 1000) / 1000);
    }

    let op1e3: OperatingPoint = { threshold: 1.0, fmr: 0, fnmr: 1.0 };
    let op1e4: OperatingPoint = { threshold: 1.0, fmr: 0, fnmr: 1.0 };
    let minEerDiff = Infinity;
    let eer = 0.5;

    for (const t of thresholds) {
      const fmr = this.computeFmr(impostorScores, t);
      const fnmr = this.computeFnmr(genuineScores, t);

      // EER search
      const diff = Math.abs(fmr - fnmr);
      if (diff < minEerDiff) {
        minEerDiff = diff;
        eer = (fmr + fnmr) / 2;
      }

      // FMR <= 1e-3 operating point
      if (fmr <= 0.001 && t < op1e3.threshold) {
        op1e3 = { threshold: t, fmr, fnmr };
      }

      // FMR <= 1e-4 operating point
      if (fmr <= 0.0001 && t < op1e4.threshold) {
        op1e4 = { threshold: t, fmr, fnmr };
      }
    }

    // 3. Non-parametric Bootstrap Confidence Intervals
    const bootstrapCi = this.computeBootstrapCi(
      genuineScores,
      impostorScores,
      op1e3.threshold,
      bootstrapIterations
    );

    return {
      totalComparisons: pairs.length,
      genuineCount: genuineScores.length,
      impostorCount: impostorScores.length,
      auc,
      isModelDiscriminating: auc >= 0.75,
      operatingPointFmr1e3: op1e3,
      operatingPointFmr1e4: op1e4,
      bootstrapCi95: bootstrapCi,
      eer,
    };
  }

  private static computeFmr(sortedImpostorScores: number[], threshold: number): number {
    const N = sortedImpostorScores.length;
    // Count scores >= threshold
    let count = 0;
    for (let i = N - 1; i >= 0; i--) {
      if (sortedImpostorScores[i] >= threshold) {
        count++;
      } else {
        break;
      }
    }
    return count / N;
  }

  private static computeFnmr(sortedGenuineScores: number[], threshold: number): number {
    const N = sortedGenuineScores.length;
    // Count scores < threshold
    let count = 0;
    for (let i = 0; i < N; i++) {
      if (sortedGenuineScores[i] < threshold) {
        count++;
      } else {
        break;
      }
    }
    return count / N;
  }

  public static calculateAuc(genuine: number[], impostor: number[]): number {
    let rankSum = 0;
    const all = [
      ...genuine.map((s) => ({ s, isGen: 1 })),
      ...impostor.map((s) => ({ s, isGen: 0 })),
    ];
    all.sort((a, b) => a.s - b.s);

    for (let i = 0; i < all.length; i++) {
      if (all[i].isGen === 1) {
        rankSum += i + 1;
      }
    }

    const nG = genuine.length;
    const nI = impostor.length;
    const U = rankSum - (nG * (nG + 1)) / 2;
    return U / (nG * nI);
  }

  private static computeBootstrapCi(
    genuine: number[],
    impostor: number[],
    threshold1e3: number,
    B: number
  ): { aucLower: number; aucUpper: number; fnmrAt1e3Lower: number; fnmrAt1e3Upper: number } {
    const aucSamples: number[] = [];
    const fnmrSamples: number[] = [];

    const nG = genuine.length;
    const nI = impostor.length;

    for (let b = 0; b < B; b++) {
      const resampledGen = Array.from({ length: nG }, () => genuine[Math.floor(Math.random() * nG)]).sort((x, y) => x - y);
      const resampledImp = Array.from({ length: nI }, () => impostor[Math.floor(Math.random() * nI)]).sort((x, y) => x - y);

      aucSamples.push(this.calculateAuc(resampledGen, resampledImp));
      fnmrSamples.push(this.computeFnmr(resampledGen, threshold1e3));
    }

    aucSamples.sort((a, b) => a - b);
    fnmrSamples.sort((a, b) => a - b);

    const lowerIdx = Math.floor(B * 0.025);
    const upperIdx = Math.floor(B * 0.975);

    return {
      aucLower: aucSamples[lowerIdx],
      aucUpper: aucSamples[upperIdx],
      fnmrAt1e3Lower: fnmrSamples[lowerIdx],
      fnmrAt1e3Upper: fnmrSamples[upperIdx],
    };
  }
}
