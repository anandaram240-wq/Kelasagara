// backend/src/tests/calibration_decision_engine.test.ts
/**
 * Track C Test Suite: Calibration and Decision Engine (Tickets C-01..C-06)
 * Enforces Invariants I-01, I-07, I-27, I-28.
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import {
  ScoreCalibrationEngine,
  QualityConditionedThresholdEngine,
  ScoreNormalizationEngine,
  TriStateDecisionEngine,
  SequentialMultiFrameEngine,
  IntraSessionLivenessBinding,
} from "../services/score_calibration";

describe("TRACK C: CALIBRATION AND DECISION ENGINE (C-01..C-06)", () => {
  it("C-01: maps cosine to calibrated LLR and computes Cllr and minCllr", () => {
    // Simulated realistic genuine scores (mean ~ 0.58) and impostor scores (mean ~ 0.12)
    const genuineScores = [0.45, 0.52, 0.58, 0.62, 0.70, 0.75, 0.81];
    const impostorScores = [0.05, 0.08, 0.12, 0.15, 0.18, 0.22, 0.25];

    const { cLLR, minCLLR } = ScoreCalibrationEngine.computeCllr(genuineScores, impostorScores);
    console.log(`[C-01 Calibration] Cllr: ${cLLR.toFixed(4)} | minCllr: ${minCLLR.toFixed(4)}`);

    assert.ok(cLLR > 0, "Cllr must be strictly positive");
    assert.ok(minCLLR <= cLLR, "minCllr must be <= Cllr (PAV lower bound)");
    assert.ok(cLLR < 0.25, "Well-calibrated system must achieve Cllr < 0.25 on distinct genuine/impostor distributions");

    // Test cosine to LLR mapping
    const lowScoreLLR = ScoreCalibrationEngine.cosineToLLR(0.10);
    const midScoreLLR = ScoreCalibrationEngine.cosineToLLR(0.363);
    const highScoreLLR = ScoreCalibrationEngine.cosineToLLR(0.70);

    assert.ok(lowScoreLLR < midScoreLLR, "LLR mapping must be strictly monotonic");
    assert.ok(midScoreLLR < highScoreLLR, "LLR mapping must be strictly monotonic");
    assert.ok(midScoreLLR >= 2.0, "Cosine 0.363 must yield LLR >= 2.0 for FMR 1e-4");
  });

  it("C-02: dynamically conditions thresholds on pair quality bins", () => {
    const baseLLR = 9.21;

    // High quality (0.85, 0.80)
    const highQ = QualityConditionedThresholdEngine.getQualityAdjustedThreshold(baseLLR, 0.85, 0.80);
    assert.equal(highQ.qualityBin, "HIGH");
    assert.equal(highQ.adjustedLLR, baseLLR, "High quality must not inflate threshold");

    // Medium quality (0.60, 0.55)
    const medQ = QualityConditionedThresholdEngine.getQualityAdjustedThreshold(baseLLR, 0.60, 0.55);
    assert.equal(medQ.qualityBin, "MEDIUM");
    assert.ok(medQ.adjustedLLR > baseLLR, "Medium quality must require higher LLR margin");

    // Low quality (0.42, 0.40)
    const lowQ = QualityConditionedThresholdEngine.getQualityAdjustedThreshold(baseLLR, 0.42, 0.40);
    assert.equal(lowQ.qualityBin, "LOW");
    assert.ok(lowQ.adjustedLLR >= baseLLR + 1.0, "Low quality must require +1.0 LLR margin");
  });

  it("C-03: computes Symmetric Score Normalization (S-Norm) with background cohort", () => {
    // Generate dummy 128-dim normalized cohort
    const dim = 128;
    const cohort: number[][] = [];
    for (let c = 0; c < 10; c++) {
      const v = new Array(dim).fill(0).map(() => (Math.random() - 0.5) * 0.1);
      const norm = Math.sqrt(v.reduce((s, x) => s + x * x, 0));
      cohort.push(v.map((x) => x / norm));
    }

    const sNormEngine = new ScoreNormalizationEngine(cohort);

    // Create probe and gallery vectors
    const probe = cohort[0].map((x) => x + (Math.random() - 0.5) * 0.01);
    const pNorm = Math.sqrt(probe.reduce((s, x) => s + x * x, 0));
    const probeNorm = probe.map((x) => x / pNorm);

    const normScore = sNormEngine.normalizeScore(probeNorm, cohort[0]);
    assert.ok(Number.isFinite(normScore), "S-Norm score must be finite number");
    console.log(`[C-03 S-Norm] Normalized Score for genuine reference: ${normScore.toFixed(4)}`);
  });

  it("C-04: evaluates tri-state decisions (ACCEPT / REJECT / STEP-UP) across risk tiers and cost models", () => {
    // 1. High cosine (0.75) -> ACCEPT
    const resAccept = TriStateDecisionEngine.evaluateDecision(0.75, "STANDARD");
    assert.equal(resAccept.outcome, "ACCEPT");
    assert.equal(resAccept.stepUpTriggered, false);
    assert.equal(resAccept.reasonCode, "MATCH_CONFIRMED");

    // 2. Marginal cosine (0.33) -> STEP_UP
    const resStepUp = TriStateDecisionEngine.evaluateDecision(0.33, "STANDARD");
    assert.equal(resStepUp.outcome, "STEP_UP");
    assert.equal(resStepUp.stepUpTriggered, true);
    assert.equal(resStepUp.reasonCode, "MARGINAL_CONFIDENCE_REQUIRES_STEP_UP");

    // 3. Low cosine (0.15) -> REJECT
    const resReject = TriStateDecisionEngine.evaluateDecision(0.15, "STANDARD");
    assert.equal(resReject.outcome, "REJECT");
    assert.equal(resReject.stepUpTriggered, false);
    assert.equal(resReject.reasonCode, "MATCH_BELOW_REJECTION_THRESHOLD");

    // 4. Expected Cost Comparison
    const costStandard = TriStateDecisionEngine.computeExpectedCost(1e-4, 0.02, 0.05);
    console.log(`[C-04 Expected Cost] Standard policy expected cost: ${costStandard.toFixed(4)}`);
    assert.ok(costStandard < 1.0, "Expected operational cost must be bounded below 1.0");
  });

  it("C-05: derives single-frame FMR budget for multi-frame attempts and enforces session attempt quotas", () => {
    // With 3 attempts, target session FMR = 1e-4
    const singleTarget = SequentialMultiFrameEngine.deriveSingleFrameFMRTarget(1e-4, 3);
    console.log(`[C-05 Budget] Single-frame target for session FMR 1e-4 across 3 looks: ${singleTarget.toExponential(3)}`);
    assert.ok(singleTarget < 3.5e-5, "Single frame target must be <= 3.5e-5 to guarantee session FMR <= 1e-4");

    // Attempt quota check
    const quota1 = SequentialMultiFrameEngine.evaluateAttemptQuota(1, 3);
    assert.equal(quota1.allowed, true);
    assert.equal(quota1.remainingAttempts, 2);

    const quota3 = SequentialMultiFrameEngine.evaluateAttemptQuota(3, 3);
    assert.equal(quota3.allowed, false, "3 attempts must exhaust quota");
    assert.equal(quota3.remainingAttempts, 0);
  });

  it("C-06: detects mid-session face swap (fail-closed) and prevents hill-climbing score leaks", () => {
    const dim = 128;
    const baseVector = new Array(dim).fill(0).map(() => 0.088); // norm ~ 1.0

    // Frame 1 and Frame 2: same identity with minor noise (cosine ~ 0.98)
    const frame1 = baseVector.slice();
    const frame2 = baseVector.map((x) => x + (Math.random() - 0.5) * 0.005);
    const f2Norm = Math.sqrt(frame2.reduce((s, x) => s + x * x, 0));
    const frame2Norm = frame2.map((x) => x / f2Norm);

    // Frame 3 (injected attacker swap): orthogonal face vector
    const frame3Attacker = new Array(dim).fill(0).map((_, i) => (i % 2 === 0 ? 0.125 : -0.125));

    // 1. Genuine session check
    const genuineBinding = IntraSessionLivenessBinding.verifyInterFrameConsistency([frame1, frame2Norm]);
    assert.equal(genuineBinding.consistent, true);
    assert.equal(genuineBinding.violationDetected, false);

    // 2. Adversarial face swap session check
    const swapBinding = IntraSessionLivenessBinding.verifyInterFrameConsistency([frame1, frame2Norm, frame3Attacker]);
    assert.equal(swapBinding.consistent, false, "Injected swapped face must violate intra-session binding");
    assert.equal(swapBinding.violationDetected, true, "Violation must be flagged");
    console.log(`[C-06 Anti-Swap] Min pairwise cosine on swap attempt: ${swapBinding.minPairwiseCosine.toFixed(4)}`);

    // 3. Anti-Hill-Climbing response check
    const sanitizedAccept = IntraSessionLivenessBinding.sanitizeClientResponse({
      outcome: "ACCEPT",
      riskTier: "STANDARD",
      calibratedLLR: 12.4,
      requiredLLR: 9.21,
      stepUpTriggered: false,
      reasonCode: "MATCH_CONFIRMED",
    });
    assert.equal(sanitizedAccept.status, "SUCCESS");
    assert.ok(sanitizedAccept.authTicket, "Auth ticket issued");
    // Ensure no score leakage:
    assert.equal((sanitizedAccept as any).calibratedLLR, undefined);
    assert.equal((sanitizedAccept as any).score, undefined);
    assert.equal((sanitizedAccept as any).cosine, undefined);
  });
});
