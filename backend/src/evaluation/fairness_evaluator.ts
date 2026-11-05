// backend/src/evaluation/fairness_evaluator.ts
/**
 * Track F: Fairness, Demographic Parity & Robustness Evaluator (Tickets F-01..F-05)
 * Enforces Invariants I-01, I-07, and Pre-Registration Gates GATE-06, GATE-07.
 */

export interface DemographicMetadata {
  id: string;
  gender: "MALE" | "FEMALE";
  ageBand: "18-30" | "31-50" | "51+";
  skinTone: "FITZPATRICK_III" | "FITZPATRICK_IV" | "FITZPATRICK_V";
  eyewear: boolean;
  beard: boolean;
}

export interface ComparisonPair {
  probeId: string;
  galleryId: string;
  genuine: boolean;
  score: number; // cosine similarity
  metadataProbe: DemographicMetadata;
  metadataGallery: DemographicMetadata;
}

export interface GroupFairnessMetrics {
  groupName: string;
  genuineCount: number;
  impostorCount: number;
  fnmr: number;
  ci95_fnmr: [number, number];
  fmr: number;
  ci95_fmr: [number, number];
  fnmrRatioToOverall: number;
  fmrRatioToOverall: number;
}

export interface RobustnessTestResult {
  condition: string;
  genuineSimMean: number;
  fnmrAtGlobalThreshold: number;
  relativeDegradationPct: number;
  status: "ROBUST" | "DEGRADED" | "CRITICAL";
}

function computeBootstrapCi(errors: number[], iterations = 1000): [number, number] {
  if (errors.length === 0) return [0, 0];
  const n = errors.length;
  const rates: number[] = [];
  for (let i = 0; i < iterations; i++) {
    let sum = 0;
    for (let j = 0; j < n; j++) {
      sum += errors[Math.floor(Math.random() * n)];
    }
    rates.push(sum / n);
  }
  rates.sort((a, b) => a - b);
  const lower = rates[Math.floor(iterations * 0.025)];
  const upper = rates[Math.floor(iterations * 0.975)];
  return [lower, upper];
}

export class FairnessEvaluator {
  /**
   * Evaluates demographic fairness with strictly DEMOGRAPHICALLY MATCHED impostor pairs.
   */
  static evaluateDemographicParity(
    pairs: ComparisonPair[],
    globalThreshold: number
  ): {
    overall: { fnmr: number; fmr: number };
    groups: GroupFairnessMetrics[];
    worstFnmrRatio: number;
    worstFmrRatio: number;
    gatesPassed: boolean;
  } {
    // 1. Overall population metrics
    const allGenuines = pairs.filter((p) => p.genuine);
    const allImpostors = pairs.filter((p) => !p.genuine);

    const overallFnmr =
      allGenuines.filter((p) => p.score < globalThreshold).length / Math.max(1, allGenuines.length);
    const overallFmr =
      allImpostors.filter((p) => p.score >= globalThreshold).length / Math.max(1, allImpostors.length);

    // 2. Partition by demographic group
    const groups: { name: string; filter: (m: DemographicMetadata) => boolean }[] = [
      { name: "Gender: Male", filter: (m) => m.gender === "MALE" },
      { name: "Gender: Female", filter: (m) => m.gender === "FEMALE" },
      { name: "Age: 18-30", filter: (m) => m.ageBand === "18-30" },
      { name: "Age: 31-50", filter: (m) => m.ageBand === "31-50" },
      { name: "Age: 51+", filter: (m) => m.ageBand === "51+" },
      { name: "SkinTone: Type III", filter: (m) => m.skinTone === "FITZPATRICK_III" },
      { name: "SkinTone: Type IV", filter: (m) => m.skinTone === "FITZPATRICK_IV" },
      { name: "SkinTone: Type V", filter: (m) => m.skinTone === "FITZPATRICK_V" },
      { name: "Eyewear: Present", filter: (m) => m.eyewear },
      { name: "FacialHair: Beard", filter: (m) => m.beard },
    ];

    const groupMetricsList: GroupFairnessMetrics[] = [];
    let maxFnmrRatio = 1.0;
    let maxFmrRatio = 1.0;

    for (const g of groups) {
      // Genuine pairs where both probe & gallery belong to group
      const genPairs = pairs.filter(
        (p) => p.genuine && g.filter(p.metadataProbe) && g.filter(p.metadataGallery)
      );

      // CRITICAL: Demographically MATCHED impostor pairs (both belong to same group)
      const impPairs = pairs.filter(
        (p) => !p.genuine && g.filter(p.metadataProbe) && g.filter(p.metadataGallery)
      );

      const genErrors = genPairs.map((p) => (p.score < globalThreshold ? 1 : 0));
      const impErrors = impPairs.map((p) => (p.score >= globalThreshold ? 1 : 0));

      const fnmr = genPairs.length > 0 ? genErrors.reduce((s: number, x: number) => s + x, 0) / genPairs.length : 0;
      const fmr = impPairs.length > 0 ? impErrors.reduce((s: number, x: number) => s + x, 0) / impPairs.length : 0;

      const ciFnmr =
        genPairs.length >= 10
          ? computeBootstrapCi(genErrors, 1000)
          : ([fnmr, fnmr] as [number, number]);
      const ciFmr =
        impPairs.length >= 10
          ? computeBootstrapCi(impErrors, 1000)
          : ([fmr, fmr] as [number, number]);

      const fnmrRatio = overallFnmr > 0 ? fnmr / overallFnmr : 1.0;
      const fmrRatio = overallFmr > 0 ? fmr / overallFmr : 1.0;

      if (fnmrRatio > maxFnmrRatio) maxFnmrRatio = fnmrRatio;
      if (fmrRatio > maxFmrRatio) maxFmrRatio = fmrRatio;

      groupMetricsList.push({
        groupName: g.name,
        genuineCount: genPairs.length,
        impostorCount: impPairs.length,
        fnmr: parseFloat(fnmr.toFixed(4)),
        ci95_fnmr: [parseFloat(ciFnmr[0].toFixed(4)), parseFloat(ciFnmr[1].toFixed(4))],
        fmr: parseFloat(fmr.toFixed(5)),
        ci95_fmr: [parseFloat(ciFmr[0].toFixed(5)), parseFloat(ciFmr[1].toFixed(5))],
        fnmrRatioToOverall: parseFloat(fnmrRatio.toFixed(2)),
        fmrRatioToOverall: parseFloat(fmrRatio.toFixed(2)),
      });
    }

    // Pre-registered gates: worst FNMR ratio <= 2.0, worst FMR ratio <= 3.0
    const gatesPassed = maxFnmrRatio <= 2.0 && maxFmrRatio <= 3.0;

    return {
      overall: {
        fnmr: parseFloat(overallFnmr.toFixed(4)),
        fmr: parseFloat(overallFmr.toFixed(5)),
      },
      groups: groupMetricsList,
      worstFnmrRatio: parseFloat(maxFnmrRatio.toFixed(2)),
      worstFmrRatio: parseFloat(maxFmrRatio.toFixed(2)),
      gatesPassed,
    };
  }

  /**
   * F-05: Clusters worst 1% genuine and top 1% impostor pairs for root-cause error analysis.
   */
  static clusterErrorExtremes(pairs: ComparisonPair[]): {
    worstGenuineCount: number;
    worstGenuineFactors: Record<string, number>;
    topImpostorCount: number;
    topImpostorFactors: Record<string, number>;
  } {
    const genuines = pairs.filter((p) => p.genuine).sort((a, b) => a.score - b.score);
    const impostors = pairs.filter((p) => !p.genuine).sort((a, b) => b.score - a.score);

    const worstGenCount = Math.max(1, Math.floor(genuines.length * 0.05));
    const topImpCount = Math.max(1, Math.floor(impostors.length * 0.05));

    const worstGenuines = genuines.slice(0, worstGenCount);
    const topImpostors = impostors.slice(0, topImpCount);

    const genFactors: Record<string, number> = {
      eyewear: 0,
      beard: 0,
      seniorAge: 0,
      skinToneV: 0,
    };
    for (const p of worstGenuines) {
      if (p.metadataProbe.eyewear) genFactors.eyewear++;
      if (p.metadataProbe.beard) genFactors.beard++;
      if (p.metadataProbe.ageBand === "51+") genFactors.seniorAge++;
      if (p.metadataProbe.skinTone === "FITZPATRICK_V") genFactors.skinToneV++;
    }

    const impFactors: Record<string, number> = {
      sameGender: 0,
      sameAgeBand: 0,
      sameSkinTone: 0,
    };
    for (const p of topImpostors) {
      if (p.metadataProbe.gender === p.metadataGallery.gender) impFactors.sameGender++;
      if (p.metadataProbe.ageBand === p.metadataGallery.ageBand) impFactors.sameAgeBand++;
      if (p.metadataProbe.skinTone === p.metadataGallery.skinTone) impFactors.sameSkinTone++;
    }

    return {
      worstGenuineCount: worstGenuines.length,
      worstGenuineFactors: genFactors,
      topImpostorCount: topImpostors.length,
      topImpostorFactors: impFactors,
    };
  }
}
