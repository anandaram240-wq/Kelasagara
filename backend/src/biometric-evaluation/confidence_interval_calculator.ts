/**
 * backend/src/biometric-evaluation/confidence_interval_calculator.ts
 *
 * Implements rigorous statistical confidence intervals according to
 * ISO/IEC 19795-1:2021 and NIST biometric evaluation standards:
 * - Exact Clopper-Pearson binomial confidence intervals.
 * - Rule of Three for zero-error observations.
 * - Subject-cluster variance inflation for non-independent pairwise comparisons.
 */

export interface ConfidenceInterval {
  readonly pointEstimate: number;
  readonly lowerBound: number;
  readonly upperBound: number;
  readonly oneSidedUpperBound?: number;
  readonly confidenceLevel: number;
  readonly sampleSize: number;
  readonly errorCount: number;
  readonly method: 'CLOPPER_PEARSON_EXACT' | 'RULE_OF_THREE' | 'CLUSTER_ADJUSTED';
}

/**
 * Standard 7-term Lanczos approximation for log-gamma function ln(Gamma(z)).
 * Machine-precision accurate for z > 0.
 */
function logGamma(z: number): number {
  const g = 7;
  const C = [
    0.99999999999980993,
    676.5203681218851,
    -1259.1392167224028,
    771.32342877765313,
    -176.61502916214059,
    12.507343278686905,
    -0.13857109585720557,
    9.9843695780195716e-6,
    1.5056327351493116e-7,
  ];
  if (z < 0.5) {
    return Math.log(Math.PI / Math.sin(Math.PI * z)) - logGamma(1 - z);
  }
  z -= 1;
  let x = C[0];
  for (let i = 1; i < g + 2; i++) {
    x += C[i] / (z + i);
  }
  const t = z + g + 0.5;
  return 0.5 * Math.log(2 * Math.PI) + (z + 0.5) * Math.log(t) - t + Math.log(x);
}

function betaContinuedFraction(a: number, b: number, x: number): number {
  const MAX_ITER = 200;
  const qab = a + b;
  const qap = a + 1;
  const qam = a - 1;
  let c = 1.0;
  let d = 1.0 - (qab * x) / qap;
  if (Math.abs(d) < 1e-30) d = 1e-30;
  d = 1.0 / d;
  let h = d;

  for (let m = 1; m <= MAX_ITER; m++) {
    const m2 = 2 * m;
    let aa = (m * (b - m) * x) / ((qam + m2) * (a + m2));
    d = 1.0 + aa * d;
    if (Math.abs(d) < 1e-30) d = 1e-30;
    c = 1.0 + aa / c;
    if (Math.abs(c) < 1e-30) c = 1e-30;
    d = 1.0 / d;
    h *= d * c;

    aa = (-(a + m) * (qab + m) * x) / ((a + m2) * (qap + m2));
    d = 1.0 + aa * d;
    if (Math.abs(d) < 1e-30) d = 1e-30;
    c = 1.0 + aa / c;
    if (Math.abs(c) < 1e-30) c = 1e-30;
    d = 1.0 / d;
    const del = d * c;
    h *= del;
    if (Math.abs(del - 1.0) < 1e-12) break;
  }
  return h;
}

function regularizedIncompleteBeta(x: number, a: number, b: number): number {
  if (x <= 0) return 0;
  if (x >= 1) return 1;
  const bt = Math.exp(logGamma(a + b) - logGamma(a) - logGamma(b) + a * Math.log(x) + b * Math.log(1 - x));
  if (x < (a + 1) / (a + b + 2)) {
    return (bt * betaContinuedFraction(a, b, x)) / a;
  }
  return 1.0 - (bt * betaContinuedFraction(b, a, 1 - x)) / b;
}

/**
 * Inverts the regularized incomplete beta function I_x(a, b) = p for x in [0, 1] using bisection.
 */
function inverseBeta(p: number, a: number, b: number): number {
  if (p <= 0) return 0;
  if (p >= 1) return 1;
  let low = 0.0;
  let high = 1.0;
  let guess = a / (a + b);
  for (let iter = 0; iter < 80; iter++) {
    const val = regularizedIncompleteBeta(guess, a, b);
    if (val < p) {
      low = guess;
    } else {
      high = guess;
    }
    guess = 0.5 * (low + high);
    if (high - low < 1e-10) break;
  }
  return guess;
}

export class ConfidenceIntervalCalculator {
  /**
   * Computes one-sided upper confidence bound: 1 - alpha^(1/trials) for zero errors,
   * or inverseBeta(1 - alpha, errors + 1, trials - errors) for non-zero errors.
   */
  public static calculateOneSidedUpperBound(
    errors: number,
    trials: number,
    confidenceLevel = 0.95
  ): number {
    if (trials <= 0) {
      throw new Error(`TRIALS_MUST_BE_POSITIVE: got ${trials}`);
    }
    if (errors < 0 || errors > trials) {
      throw new Error(`INVALID_ERROR_COUNT: ${errors} errors in ${trials} trials`);
    }

    const alpha = 1.0 - confidenceLevel;
    if (errors === 0) {
      const bound = 1.0 - Math.pow(alpha, 1.0 / trials);
      return Number(bound.toFixed(8));
    }
    const bound = inverseBeta(1.0 - alpha, errors + 1, trials - errors);
    return Number(bound.toFixed(8));
  }

  /**
   * Computes Clopper-Pearson exact binomial confidence interval.
   * @param errors Number of observed errors (false matches or false non-matches)
   * @param trials Total number of trials / comparisons
   * @param confidenceLevel Confidence level, default 0.95 (95%)
   */
  public static calculateClopperPearson(
    errors: number,
    trials: number,
    confidenceLevel = 0.95
  ): ConfidenceInterval {
    if (trials <= 0) {
      throw new Error(`TRIALS_MUST_BE_POSITIVE: got ${trials}`);
    }
    if (errors < 0 || errors > trials) {
      throw new Error(`INVALID_ERROR_COUNT: ${errors} errors in ${trials} trials`);
    }

    const alpha = 1.0 - confidenceLevel;
    const point = errors / trials;
    const oneSided = this.calculateOneSidedUpperBound(errors, trials, confidenceLevel);

    // Boundary case: 0 errors
    if (errors === 0) {
      const upper = 1.0 - Math.pow(alpha / 2, 1.0 / trials);
      return {
        pointEstimate: 0.0,
        lowerBound: 0.0,
        upperBound: Number(upper.toFixed(8)),
        oneSidedUpperBound: oneSided,
        confidenceLevel,
        sampleSize: trials,
        errorCount: 0,
        method: 'RULE_OF_THREE',
      };
    }

    // Boundary case: all errors
    if (errors === trials) {
      const lower = Math.pow(alpha / 2, 1.0 / trials);
      return {
        pointEstimate: 1.0,
        lowerBound: Number(lower.toFixed(8)),
        upperBound: 1.0,
        oneSidedUpperBound: 1.0,
        confidenceLevel,
        sampleSize: trials,
        errorCount: trials,
        method: 'CLOPPER_PEARSON_EXACT',
      };
    }

    // Exact Clopper-Pearson:
    // Lower = B(alpha/2; errors, trials - errors + 1)
    // Upper = B(1 - alpha/2; errors + 1, trials - errors)
    const lower = inverseBeta(alpha / 2, errors, trials - errors + 1);
    const upper = inverseBeta(1.0 - alpha / 2, errors + 1, trials - errors);

    return {
      pointEstimate: Number(point.toFixed(8)),
      lowerBound: Number(lower.toFixed(8)),
      upperBound: Number(upper.toFixed(8)),
      oneSidedUpperBound: oneSided,
      confidenceLevel,
      sampleSize: trials,
      errorCount: errors,
      method: 'CLOPPER_PEARSON_EXACT',
    };
  }

  /**
   * Computes cluster-adjusted confidence interval to account for pairwise correlation
   * when multiple comparisons share the same subjects (ISO/IEC 19795-1 §9.3.2).
   */
  public static calculateClusterAdjusted(
    errors: number,
    pairwiseComparisons: number,
    uniqueSubjects: number,
    intraClassCorrelation = 0.15,
    confidenceLevel = 0.95
  ): ConfidenceInterval {
    if (uniqueSubjects <= 1) {
      throw new Error(`UNIQUE_SUBJECTS_MUST_EXCEED_ONE: got ${uniqueSubjects}`);
    }
    const m = pairwiseComparisons / uniqueSubjects;
    const designEffect = 1.0 + (m - 1.0) * intraClassCorrelation;
    const effectiveSampleSize = Math.max(uniqueSubjects, Math.round(pairwiseComparisons / designEffect));
    const effectiveErrors = Math.round((errors / pairwiseComparisons) * effectiveSampleSize);

    const baseCi = this.calculateClopperPearson(effectiveErrors, effectiveSampleSize, confidenceLevel);
    return {
      pointEstimate: Number((errors / pairwiseComparisons).toFixed(8)),
      lowerBound: baseCi.lowerBound,
      upperBound: baseCi.upperBound,
      confidenceLevel,
      sampleSize: pairwiseComparisons,
      errorCount: errors,
      method: 'CLUSTER_ADJUSTED',
    };
  }

  /**
   * Calculates required independent comparisons to demonstrate a target FMR at 95% confidence
   * with zero observed errors.
   */
  public static calculateRequiredSampleForTarget(targetFmr: number, confidenceLevel = 0.95): number {
    if (targetFmr <= 0 || targetFmr >= 1) {
      throw new Error(`TARGET_FMR_OUT_OF_RANGE: ${targetFmr}`);
    }
    const alpha = 1.0 - confidenceLevel;
    return Math.ceil(Math.log(alpha) / Math.log(1.0 - targetFmr));
  }
}
