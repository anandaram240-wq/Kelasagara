// backend/src/tests/threshold_governance.test.ts
/**
 * THRESHOLD GOVERNANCE & 1:1 VS 1:N BOUNDARY REGRESSION SUITE (V15.0)
 *
 * Verifies:
 * 1. 1:1 Decision Boundary around SFace reference threshold (0.363):
 *    - Score just below (0.362) -> REJECTED
 *    - Score equal to threshold (0.363) -> ACCEPTED
 *    - Score just above (0.364) -> ACCEPTED
 *    - Representative scores (0.40, 0.55, 0.65) -> ACCEPTED
 *    - Non-match (0.10, -0.20) -> REJECTED
 * 2. Independence of 1:1 Verification from 1:N Duplicate Screening:
 *    - Genuine verification (0.40 - 0.73) does NOT trigger duplicate flags (< 0.74)
 *    - Duplicate warning / flag (0.74 - 0.89) triggers review without hard block
 *    - Duplicate hard block (>= 0.90) triggers sybil block
 * 3. Configuration Safety & Validation Governance:
 *    - NaN, empty strings, infinite, negative out-of-range rejection
 *    - Inverted hierarchy prevention (verification < duplicate < hardBlock)
 *    - Production fail-safe: rejects automated identity gating without approved calibration
 * 4. Account Lifecycle Re-verification:
 *    - Uses verificationThreshold (0.363), not duplicateThreshold (0.74)
 */

import { describe, it, beforeEach } from "node:test";
import assert from "node:assert";
import { config, parseThreshold, validateThresholdGovernance } from "../config";
import {
  cosineSimilarity,
  evaluateMatch,
  evaluateVerification,
  l2Normalize,
} from "../services/biometric_matching";
import { AccountLifecycleService } from "../services/account_lifecycle";
import { FirestoreBiometricRepository } from "../services/firestore_biometric_repository";

describe("V15.0 Threshold Governance & Regression Suite", () => {
  // ── 1. 1:1 VERIFICATION BOUNDARY TESTS ─────────────────────────────────────
  describe("1. 1:1 Verification Decision Boundary (OpenCV SFace Reference = 0.363)", () => {
    const threshold = config.verificationThreshold; // 0.363

    it("REJECTS score just below threshold (0.362)", () => {
      const decision = evaluateVerification(0.362, threshold);
      assert.strictEqual(decision.isMatch, false, "Score 0.362 must be rejected fail-closed");
      assert.strictEqual(decision.threshold, 0.363);
    });

    it("ACCEPTS score exactly at threshold (0.363)", () => {
      const decision = evaluateVerification(0.363, threshold);
      assert.strictEqual(decision.isMatch, true, "Score 0.363 exactly at threshold must match");
    });

    it("ACCEPTS score just above threshold (0.364)", () => {
      const decision = evaluateVerification(0.364, threshold);
      assert.strictEqual(decision.isMatch, true, "Score 0.364 above threshold must match");
    });

    it("ACCEPTS representative mid-range genuine scores (0.45, 0.55, 0.65)", () => {
      for (const sim of [0.45, 0.55, 0.65]) {
        const decision = evaluateVerification(sim, threshold);
        assert.strictEqual(decision.isMatch, true, `Score ${sim} must match`);
      }
    });

    it("ACCEPTS strong high-confidence matches (0.85, 0.95)", () => {
      for (const sim of [0.85, 0.95]) {
        const decision = evaluateVerification(sim, threshold);
        assert.strictEqual(decision.isMatch, true, `Strong score ${sim} must match`);
      }
    });

    it("REJECTS unmistakable non-matches (0.10, 0.0, -0.20)", () => {
      for (const sim of [0.10, 0.0, -0.20]) {
        const decision = evaluateVerification(sim, threshold);
        assert.strictEqual(decision.isMatch, false, `Non-match ${sim} must be rejected`);
      }
    });

    it("Handles vector dimension mismatch and empty vectors fail-safe", () => {
      const v1 = [1, 0, 0];
      const v2 = [1, 0];
      assert.strictEqual(cosineSimilarity(v1, v2), 0.0, "Dimension mismatch must yield 0.0");
      assert.strictEqual(cosineSimilarity([], []), 0.0, "Empty vectors must yield 0.0");
      assert.strictEqual(cosineSimilarity(null as any, v1), 0.0, "Null vector must yield 0.0");
    });
  });

  // ── 2. SEPARATION OF 1:1 AND 1:N DECISION PATHS ────────────────────────────
  describe("2. Separation Proof: 1:1 Verification vs 1:N Duplicate Screening", () => {
    it("PROVES genuine 1:1 verify match (0.50) is NOT flagged as 1:N duplicate", () => {
      const sim = 0.50;
      const verifyDecision = evaluateVerification(sim);
      const dedupDecision = evaluateMatch(sim);

      assert.strictEqual(verifyDecision.isMatch, true, "0.50 is genuine 1:1 match");
      assert.strictEqual(dedupDecision.isDuplicate, false, "0.50 must NEVER be flagged as duplicate");
      assert.strictEqual(dedupDecision.isHardBlock, false);
      assert.strictEqual(dedupDecision.decision, "unique");
    });

    it("PROVES ambiguous score (0.68) is accepted for 1:1 verify but flagged for review in 1:N dedup", () => {
      const sim = 0.68;
      const verifyDecision = evaluateVerification(sim);
      const dedupDecision = evaluateMatch(sim);

      assert.strictEqual(verifyDecision.isMatch, true, "0.68 is valid 1:1 verify match");
      assert.strictEqual(dedupDecision.isDuplicate, false, "0.68 is not duplicate");
      assert.strictEqual(dedupDecision.decision, "ambiguity", "0.68 routes to manual review");
    });

    it("PROVES duplicate score (0.75) is classified as duplicate review without hard block", () => {
      const sim = 0.75;
      const dedupDecision = evaluateMatch(sim);

      assert.strictEqual(dedupDecision.isDuplicate, true, "0.75 is duplicate");
      assert.strictEqual(dedupDecision.isHardBlock, false, "0.75 is NOT hard-blocked (flagged for review)");
      assert.strictEqual(dedupDecision.decision, "duplicate");
    });

    it("PROVES high-confidence duplicate (0.92) triggers HARD BLOCK", () => {
      const sim = 0.92;
      const dedupDecision = evaluateMatch(sim);

      assert.strictEqual(dedupDecision.isDuplicate, true);
      assert.strictEqual(dedupDecision.isHardBlock, true, "0.92 exceeds hardBlockThreshold (0.90)");
      assert.strictEqual(dedupDecision.decision, "duplicate");
    });
  });

  // ── 3. CONFIGURATION PARSING & GOVERNANCE SAFETY ──────────────────────────
  describe("3. Configuration Validation & Fail-Safe Governance", () => {
    it("parses valid float within range successfully", () => {
      assert.strictEqual(parseThreshold("TEST_T", "0.45", 0.363, 0.1, 0.8), 0.45);
      assert.strictEqual(parseThreshold("TEST_T", undefined, 0.363, 0.1, 0.8), 0.363);
    });

    it("throws on empty string environment variable", () => {
      assert.throws(
        () => parseThreshold("EMPTY_T", "   ", 0.363),
        /cannot be an empty string/
      );
    });

    it("throws on non-numeric or NaN strings", () => {
      assert.throws(
        () => parseThreshold("NAN_T", "not_a_number", 0.363),
        /must be a valid finite number/
      );
      assert.throws(
        () => parseThreshold("NAN_T", "NaN", 0.363),
        /must be a valid finite number/
      );
    });

    it("throws on Infinity or -Infinity", () => {
      assert.throws(
        () => parseThreshold("INF_T", "Infinity", 0.363),
        /must be a valid finite number/
      );
    });

    it("throws on out-of-bounds values", () => {
      assert.throws(
        () => parseThreshold("OUT_OF_BOUNDS", "1.5", 0.363, -1.0, 1.0),
        /must be between -1 and 1/
      );
      assert.throws(
        () => parseThreshold("OUT_OF_BOUNDS", "-1.2", 0.363, -1.0, 1.0),
        /must be between -1 and 1/
      );
    });

    it("enforces strict monotonic hierarchy: verification < duplicate < hardBlock", () => {
      // Inverted verification >= duplicate
      assert.throws(
        () =>
          validateThresholdGovernance({
            verificationThreshold: 0.75,
            duplicateThreshold: 0.74,
            hardBlockThreshold: 0.90,
            ambiguityThreshold: 0.65,
            advisoryFloorThreshold: 0.363,
          }),
        /verificationThreshold \(0.75\) must be strictly less than duplicateThreshold \(0.74\)/
      );

      // Inverted duplicate >= hardBlock
      assert.throws(
        () =>
          validateThresholdGovernance({
            verificationThreshold: 0.363,
            duplicateThreshold: 0.95,
            hardBlockThreshold: 0.90,
            ambiguityThreshold: 0.65,
            advisoryFloorThreshold: 0.363,
          }),
        /duplicateThreshold \(0.95\) must be strictly less than hardBlockThreshold \(0.9\)/
      );
    });

    it("enforces production release gate: blocks identity gating without approved calibration", () => {
      assert.throws(
        () =>
          validateThresholdGovernance({
            verificationThreshold: 0.363,
            duplicateThreshold: 0.74,
            hardBlockThreshold: 0.90,
            ambiguityThreshold: 0.65,
            advisoryFloorThreshold: 0.363,
            nodeEnv: "production",
            enableBiometricIdentityGating: true,
            productionCalibrationApproved: false,
          }),
        /CRITICAL RELEASE BLOCKER: Biometric identity gating is enabled in production without approved calibration manifest/
      );
    });

    it("allows production startup if biometric identity gating is NOT enabled", () => {
      assert.doesNotThrow(() =>
        validateThresholdGovernance({
          verificationThreshold: 0.363,
          duplicateThreshold: 0.74,
          hardBlockThreshold: 0.90,
          ambiguityThreshold: 0.65,
          advisoryFloorThreshold: 0.363,
          nodeEnv: "production",
          enableBiometricIdentityGating: false,
          productionCalibrationApproved: false,
        })
      );
    });
  });

  // ── 4. ACCOUNT LIFECYCLE RE-VERIFICATION INTEGRATION ───────────────────────
  describe("4. Account Lifecycle Re-verification (Bug Remediation Proof)", () => {
    it("successfully re-verifies worker when similarity is genuine (0.50) above verificationThreshold (0.363)", async () => {
      const mockUid = "worker_reverify_v15_test";
      const enrolled = l2Normalize(Array.from({ length: 128 }, (_, i) => Math.sin(i + 1)));

      // Mock getEnrolledTemplate
      const origGetEnrolled = FirestoreBiometricRepository.getEnrolledTemplate;
      FirestoreBiometricRepository.getEnrolledTemplate = async (uid: string) => enrolled;

      // Mock Firestore users collection via property override
      const mockDoc = {
        get: async () => ({
          exists: true,
          data: () => ({ boundDeviceId: "pixel_test_dev_01" }),
        }),
        update: async () => {},
      };
      const mockDb = {
        collection: (_col: string) => ({
          doc: (_id: string) => mockDoc,
        }),
      };

      Object.defineProperty(AccountLifecycleService, "db", {
        get: () => mockDb,
        configurable: true,
      });

      try {
        // Construct a probe vector that has similarity ~0.50 with enrolled vector
        const ortho = Array.from({ length: 128 }, (_, i) => Math.cos(i + 1));
        const orthoNorm = l2Normalize(ortho);
        const probe: number[] = [];
        for (let i = 0; i < 128; i++) {
          probe.push(0.50 * enrolled[i] + Math.sqrt(0.75) * orthoNorm[i]);
        }
        const normalizedProbe = l2Normalize(probe);
        const actualSim = cosineSimilarity(normalizedProbe, enrolled);
        assert.ok(Math.abs(actualSim - 0.50) < 0.05, `Constructed sim should be ~0.50, was ${actualSim}`);

        // Prior to V15 fix, this would fail because AccountLifecycleService checked >= duplicateThreshold (0.74)
        // Now it must succeed because actualSim >= verificationThreshold (0.363)!
        const res = await AccountLifecycleService.reVerifyWorker({
          uid: mockUid,
          probeEmbedding: normalizedProbe,
          deviceId: "pixel_test_dev_01",
        });

        assert.strictEqual(res.success, true, "Worker with sim ~0.50 must be verified under 0.363 threshold");
        assert.strictEqual(res.isMatch, true);
        assert.strictEqual(res.threshold, 0.363, "Threshold returned must be verificationThreshold (0.363)");
      } finally {
        FirestoreBiometricRepository.getEnrolledTemplate = origGetEnrolled;
      }
    });
  });
});
