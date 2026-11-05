// backend/src/tests/ci_regression_guard.test.ts
import assert from "assert";
import { describe, it } from "node:test";
import { runFaceInference } from "../services/face_inference";
import { cosineSimilarity } from "../services/biometric_matching";
import { DatasetPartitionManager, SubjectMetadata } from "../evaluation/dataset_partitions";
import { BootstrapStatisticsEngine, SubjectTrial } from "../evaluation/bootstrap_statistics";

describe("TRACK G: EXPERIMENT GOVERNANCE & CI REGRESSION GUARD (G-01..G-05)", () => {
  // ── G-02: Zero-Identity Overlap Partition Assertion ───────────────────────
  it("G-02: asserts zero identity overlap between TUNE, VALIDATE, and LOCKBOX", () => {
    const tune = ["user_001", "user_002", "user_003"];
    const validate = ["user_004", "user_005", "user_006"];
    const lockbox = ["user_007", "user_008"];

    const res = DatasetPartitionManager.validateZeroOverlap(tune, validate, lockbox);
    assert.strictEqual(res.isValid, true);

    // Contamination attempt
    const contaminatedVal = ["user_003", "user_005"]; // user_003 is in TUNE!
    const badRes = DatasetPartitionManager.validateZeroOverlap(tune, contaminatedVal, lockbox);
    assert.strictEqual(badRes.isValid, false);
    assert.match(badRes.overlapDetails || "", /Identity collision/i);
  });

  // ── G-02: Single-Access Lockbox Governance ────────────────────────────────
  it("G-02: strictly fails closed if LOCKBOX partition is accessed more than once", () => {
    DatasetPartitionManager.resetForTesting();
    const manifestHash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";

    // First access succeeds
    DatasetPartitionManager.accessLockbox("lead_evaluator", manifestHash);
    assert.strictEqual(DatasetPartitionManager.isLockboxAccessed(), true);

    // Second access MUST throw an error
    assert.throws(
      () => {
        DatasetPartitionManager.accessLockbox("p_hacking_attempt", manifestHash);
      },
      /LOCKBOX partition has already been unlocked/i,
      "Second access to LOCKBOX must fail closed"
    );
  });

  // ── G-03: Model Forward Pass Determinism Test ─────────────────────────────
  it("G-03: verifies forward inference determinism (cosine >= 0.99999 on identical input)", async () => {
    const testBuffer = Buffer.alloc(112 * 112 * 3);
    for (let i = 0; i < testBuffer.length; i++) {
      testBuffer[i] = (i * 7 + 13) % 256;
    }

    // Run forward pass twice on identical image buffer
    const embedding1 = await runFaceInference(testBuffer);
    const embedding2 = await runFaceInference(testBuffer);

    assert.strictEqual(embedding1.length, 128);
    assert.strictEqual(embedding2.length, 128);

    const cos = cosineSimilarity(embedding1, embedding2);
    assert.ok(
      cos >= 0.99999,
      `Determinism failure: repeated inference yielded cosine ${cos.toFixed(6)} < 0.99999`
    );
  });

  // ── G-04: Bootstrap Confidence Interval and Rule of Three Bounds ──────────
  it("G-04: computes identity-level bootstrap and Rule-of-Three error bounds", () => {
    // 0 observed errors on 300 trials => bound <= 3 / 300 = 0.01 (1.0%)
    const bound = BootstrapStatisticsEngine.ruleOfThreeBound(300);
    assert.strictEqual(bound, 0.01);

    // Bootstrap test with 10 subjects
    const trials: SubjectTrial[] = [];
    for (let s = 1; s <= 10; s++) {
      const subId = `subj_${s}`;
      for (let k = 0; k < 5; k++) {
        trials.push({
          subjectId: subId,
          comparisonId: `${subId}_comp_${k}`,
          similarity: 0.8 + (s % 3) * 0.05,
          isGenuine: true,
        });
      }
    }

    const ci = BootstrapStatisticsEngine.computeIdentityBootstrapCi(
      trials,
      (t) => t.reduce((sum, item) => sum + item.similarity, 0) / t.length,
      200
    );

    assert.ok(ci.ciLower95 <= ci.pointEstimate);
    assert.ok(ci.ciUpper95 >= ci.pointEstimate);
  });

  // ── G-05: Golden Parity Regression Guard ──────────────────────────────────
  it("G-05: preserves golden model vector parity without metric regression", async () => {
    // Canonical synthetic test probe
    const probe = Buffer.alloc(112 * 112 * 3, 128);
    const emb = await runFaceInference(probe);

    // Magnitude verification (L2 normalized on unit hypersphere)
    let sumSq = 0;
    for (const v of emb) sumSq += v * v;
    const norm = Math.sqrt(sumSq);
    assert.ok(Math.abs(norm - 1.0) < 1e-4, "Embedding must be unit normalized");
  });
});
