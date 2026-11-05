// backend/src/tests/inference_redundancy.test.ts
import assert from "assert";
import {
  InferenceRedundancyService,
} from "../services/inference_redundancy_service";

console.log("================================================================================");
console.log("   PHASE 10: INFERENCE REDUNDANCY & MODEL LIFECYCLE TEST SUITE                  ");
console.log("================================================================================\n");

async function runTests() {
  let passedCount = 0;
  InferenceRedundancyService.resetTelemetry();

  // ──────────────────────────────────────────────────────────────────────────
  // TEST 1: Cold-Start Warmup Preloading
  // ──────────────────────────────────────────────────────────────────────────
  console.log("TEST 1: Cold-start graph preloading and session warmup...");
  {
    const warmupResult = await InferenceRedundancyService.warmupInference();
    assert.strictEqual(warmupResult.ready, true);
    assert.ok(warmupResult.warmupLatencyMs > 0);

    const stats = InferenceRedundancyService.getHealthStats();
    assert.strictEqual(stats.warmupComplete, true);

    passedCount++;
    console.log(`  [PASS] Warmup completed in ${warmupResult.warmupLatencyMs}ms; session preloaded.\n`);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // TEST 2: Authoritative Primary Forward Inference
  // ──────────────────────────────────────────────────────────────────────────
  console.log("TEST 2: Authoritative primary forward inference execution...");
  {
    const syntheticBuffer = Buffer.alloc(112 * 112 * 3, 200);
    const result = await InferenceRedundancyService.executePrimaryInference(syntheticBuffer);

    assert.strictEqual(result.embedding.length, 128);
    assert.strictEqual(result.modelVersion, "sface_opencv_zoo_v1_primary");
    assert.strictEqual(result.fallbackInvoked, false);
    assert.ok(result.latencyMs >= 0);

    // Verify L2 norm
    const norm = Math.sqrt(result.embedding.reduce((sum, v) => sum + v * v, 0));
    assert.ok(Math.abs(norm - 1.0) < 1e-4, `Expected unit norm ~ 1.0, got ${norm}`);

    passedCount++;
    console.log(`  [PASS] 128-D SFace primary vector generated; unit L2 norm verified (${norm.toFixed(6)}).\n`);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // TEST 2B: Dual-Model Redundant Inference (FP32 Primary + INT8 Fallback)
  // ──────────────────────────────────────────────────────────────────────────
  console.log("TEST 2B: Dual-model redundant inference execution and cross-model correlation...");
  {
    const syntheticBuffer = Buffer.alloc(112 * 112 * 3, 160);
    const redundant = await InferenceRedundancyService.executeRedundantInference(syntheticBuffer);

    assert.strictEqual(redundant.primaryEmbedding.length, 128);
    assert.strictEqual(redundant.fallbackEmbedding.length, 128);
    assert.ok(redundant.correlation >= 0.50, `Expected correlation >= 0.50, got ${redundant.correlation}`);
    assert.strictEqual(redundant.discrepancyFlagged, false);

    passedCount++;
    console.log(`  [PASS] Redundant dual-inference succeeded: FP32 vs INT8 correlation = ${redundant.correlation.toFixed(4)} (>= 0.50 calibrated threshold).\n`);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // TEST 3: Shadow Scoring Discrepancy Detection (Invariant I-06)
  // ──────────────────────────────────────────────────────────────────────────
  console.log("TEST 3: Invariant I-06: Shadow scoring and divergence detection...");
  {
    const primaryVec = new Array(128).fill(1 / Math.sqrt(128));
    const enrolledVec = new Array(128).fill(1 / Math.sqrt(128));

    // Case A: Agreement
    const agreeShadowVec = new Array(128).fill(1 / Math.sqrt(128));
    const agreementResult = InferenceRedundancyService.evaluateShadowScoring({
      primaryVector: primaryVec,
      enrolledVector: enrolledVec,
      shadowVector: agreeShadowVec,
      enrolledShadowVector: agreeShadowVec,
    });

    assert.strictEqual(agreementResult.discrepancyFlagged, false);
    assert.strictEqual(agreementResult.requiresReview, false);
    assert.ok(agreementResult.scoreDelta < 0.05);

    // Case B: Divergence (|S_primary - S_shadow| > 0.15)
    // Create orthogonal shadow vector
    const divergeShadowVec = new Array(128).fill(0);
    divergeShadowVec[0] = 1.0;
    const enrolledShadowOrthogonal = new Array(128).fill(0);
    enrolledShadowOrthogonal[1] = 1.0; // Cosine similarity = 0.0

    const divergenceResult = InferenceRedundancyService.evaluateShadowScoring({
      primaryVector: primaryVec,
      enrolledVector: enrolledVec, // Cosine similarity = 1.0
      shadowVector: divergeShadowVec,
      enrolledShadowVector: enrolledShadowOrthogonal, // Cosine similarity = 0.0
    });

    assert.strictEqual(divergenceResult.discrepancyFlagged, true);
    assert.strictEqual(divergenceResult.requiresReview, true);
    assert.ok(
      divergenceResult.scoreDelta > InferenceRedundancyService.SHADOW_DISCREPANCY_THRESHOLD,
      `Expected scoreDelta > ${InferenceRedundancyService.SHADOW_DISCREPANCY_THRESHOLD}, got ${divergenceResult.scoreDelta}`
    );

    passedCount++;
    console.log(`  [PASS] Shadow discrepancy detection verified (Delta: ${divergenceResult.scoreDelta.toFixed(3)} flagged for review).\n`);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // TEST 4: Cross-Model Vector Space Incompatibility Defense
  // ──────────────────────────────────────────────────────────────────────────
  console.log("TEST 4: Multi-Model Gallery compatibility and cross-contamination defense...");
  {
    // Same model
    const sameModel = InferenceRedundancyService.checkModelCompatibility(
      "sface_opencv_zoo_v1_primary",
      "sface_opencv_zoo_v1_primary"
    );
    assert.strictEqual(sameModel.compatible, true);

    // Cross-architecture models (SFace vs MobileFaceNet)
    const crossModel = InferenceRedundancyService.checkModelCompatibility(
      "sface_opencv_zoo_v1_primary",
      "kelasagara_mobilefacenet_v1_arcface"
    );
    assert.strictEqual(crossModel.compatible, false);
    assert.ok(crossModel.reason?.includes("Incompatible vector spaces"));

    passedCount++;
    console.log("  [PASS] Cross-model vector contamination strictly prevented.\n");
  }

  // ──────────────────────────────────────────────────────────────────────────
  // TEST 5: Fail-Closed Behavior on Corrupted Buffer (Invariant I-01)
  // ──────────────────────────────────────────────────────────────────────────
  console.log("TEST 5: Invariant I-01: Fail-closed on corrupted input buffer...");
  {
    const corruptedBuffer = Buffer.from("not_a_valid_image_payload");
    let caughtError = false;

    try {
      await InferenceRedundancyService.executePrimaryInference(corruptedBuffer);
    } catch (err: any) {
      caughtError = true;
      assert.ok(
        err.message.includes("Fail-closed") || err.message.includes("failed"),
        `Expected fail-closed error message, got: ${err.message}`
      );
    }

    assert.strictEqual(caughtError, true, "Must throw fail-closed error on corrupt buffer");

    passedCount++;
    console.log("  [PASS] Corrupted image rejected cleanly with fail-closed error.\n");
  }

  // ──────────────────────────────────────────────────────────────────────────
  // TEST 6: Operational Health Telemetry
  // ──────────────────────────────────────────────────────────────────────────
  console.log("TEST 6: Telemetry and runtime health statistics...");
  {
    const stats = InferenceRedundancyService.getHealthStats();
    assert.ok(stats.totalInferences >= 2);
    assert.strictEqual(stats.totalErrors, 1);
    assert.ok(stats.averageLatencyMs >= 0);
    assert.ok(["HEALTHY", "DEGRADED", "CRITICAL"].includes(stats.status));

    passedCount++;
    console.log(`  [PASS] Health telemetry verified: ${stats.totalInferences} total calls, status: ${stats.status}.\n`);
  }

  console.log("================================================================================");
  console.log(`   PHASE 10 TESTS COMPLETE: ALL ${passedCount}/${passedCount} SUITES PASSED CLEANLY  `);
  console.log("================================================================================\n");
}

runTests().catch((err) => {
  console.error("Test execution failed:", err);
  process.exit(1);
});
