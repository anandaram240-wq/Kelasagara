// backend/src/evaluation/dedup_calculator.ts
/**
 * 1:N Deduplication Operating-Point Calculator (Ticket T-13).
 * Calculates cumulative platform false positive rate FMR_N across gallery sizes N.
 * Generates operating points for N in [500, 1000, 5000, 10000].
 */

export interface GalleryScaleRow {
  gallerySizeN: number;
  singlePairFmr1: number;
  cumulativePlatformFmrN: number; // 1 - (1 - FMR_1)^N
  expectedFalseAlarmsPer1000Enrollments: number;
  required1to1ThresholdApprox: number;
  operationalRecommendation: string;
}

export class DedupOperatingPointCalculator {
  /**
   * Calculates platform duplicate false match probability as gallery scales.
   * Formula: FMR_N = 1 - (1 - FMR_1)^N
   */
  static calculatePlatformFmr(fmr1: number, N: number): number {
    return 1 - Math.pow(1 - fmr1, N);
  }

  /**
   * Calculates required single-comparison FMR_1 to achieve target platform FMR_N.
   * Formula: FMR_1 = 1 - (1 - targetFmrN)^(1/N)
   */
  static calculateRequiredFmr1(targetFmrN: number, N: number): number {
    return 1 - Math.pow(1 - targetFmrN, 1 / N);
  }

  /**
   * Generates comprehensive gallery scaling projection table.
   */
  static generateScaleTable(
    gallerySizes: number[] = [500, 1000, 5000, 10000],
    baselineFmr1 = 0.001 // 1e-3 (SFace threshold ~ 0.428)
  ): GalleryScaleRow[] {
    return gallerySizes.map((N) => {
      const platformFmr = this.calculatePlatformFmr(baselineFmr1, N);
      const falseAlarmsPer1000 = Math.round(platformFmr * 1000);

      // To keep platform false alarms <= 1% (0.01)
      const requiredFmr1For1Pct = this.calculateRequiredFmr1(0.01, N);

      let recommendation = "";
      let approxThreshold = 0.428;

      if (N <= 500) {
        recommendation = "Spark free-tier bounded scan safe. Human review load manageable.";
        approxThreshold = 0.428;
      } else if (N <= 1000) {
        recommendation = "Elevate duplicate threshold to FMR 1e-4 (~0.495) to suppress gallery false matches.";
        approxThreshold = 0.495;
      } else if (N <= 5000) {
        recommendation = "Requires Blaze plan native KNN vector index (findNearest) + secondary document KYC cross-check.";
        approxThreshold = 0.535;
      } else {
        recommendation = "Full enterprise cluster with hierarchical HNSW index required. Strict FMR 1e-5 thresholding.";
        approxThreshold = 0.580;
      }

      return {
        gallerySizeN: N,
        singlePairFmr1: baselineFmr1,
        cumulativePlatformFmrN: Math.round(platformFmr * 10000) / 10000,
        expectedFalseAlarmsPer1000Enrollments: falseAlarmsPer1000,
        required1to1ThresholdApprox: approxThreshold,
        operationalRecommendation: recommendation,
      };
    });
  }

  /**
   * Formats the scaling projection as a Markdown table.
   */
  static formatMarkdownTable(rows: GalleryScaleRow[]): string {
    let md = "| Gallery Size ($N$) | Single Pair $FMR_1$ | Platform $FMR_N$ | False Matches / 1k Enrollments | Approx Threshold | Operational Strategy |\n";
    md += "|:---:|:---:|:---:|:---:|:---:|:---|\n";
    for (const r of rows) {
      md += `| ${r.gallerySizeN.toLocaleString()} | ${r.singlePairFmr1} | ${(r.cumulativePlatformFmrN * 100).toFixed(1)}% | ${r.expectedFalseAlarmsPer1000Enrollments} | ${r.required1to1ThresholdApprox.toFixed(3)} | ${r.operationalRecommendation} |\n`;
    }
    return md;
  }
}
