// backend/src/tests/phase_b_measurements.test.ts
import assert from "assert";
import path from "path";
import { BiometricEvaluationHarness, PairwiseComparison } from "../evaluation/evaluation_harness";
import { CalibrationGuard } from "../services/calibration_guard";
import { DedupOperatingPointCalculator } from "../evaluation/dedup_calculator";
import { QualityGateService } from "../services/quality_gate";
import { QuotaMonitorService } from "../services/quota_monitor";

async function runPhaseBMeasurementSuite() {
  console.log("================================================================================");
  console.log("🧪 RUNNING PHASE B MEASUREMENT SUITE (TICKETS T-11 THROUGH T-15)");
  console.log("================================================================================\n");

  // ──────────────────────────────────────────────────────────────────────────
  // TEST 1: Ticket T-11: Evaluation Harness & DET/ROC Discrimination Test
  // ──────────────────────────────────────────────────────────────────────────
  console.log("TEST 1: Ticket T-11: Evaluation Harness, AUC & Bootstrap CIs...");
  {
    // Generate synthetic genuine pairs (high similarity ~ 0.70 - 0.95)
    const genuinePairs: PairwiseComparison[] = Array.from({ length: 200 }, () => ({
      similarity: 0.70 + Math.random() * 0.25,
      isGenuine: true,
    }));

    // Generate synthetic impostor pairs (low similarity ~ 0.05 - 0.35)
    const impostorPairs: PairwiseComparison[] = Array.from({ length: 800 }, () => ({
      similarity: 0.05 + Math.random() * 0.30,
      isGenuine: false,
    }));

    const report = BiometricEvaluationHarness.evaluate(
      [...genuinePairs, ...impostorPairs],
      200 // 200 bootstrap iterations for test speed
    );

    assert.ok(report.auc > 0.95, `Expected AUC > 0.95, got ${report.auc}`);
    assert.strictEqual(report.isModelDiscriminating, true);
    assert.ok(report.operatingPointFmr1e3.threshold > 0.30);
    assert.ok(report.bootstrapCi95.aucLower > 0.90);
    assert.ok(report.bootstrapCi95.aucUpper <= 1.0);
    console.log(`  [PASS] Well-separated model: AUC = ${report.auc.toFixed(4)}, EER = ${(report.eer * 100).toFixed(2)}%, FMR 1e-3 threshold = ${report.operatingPointFmr1e3.threshold}`);

    // Test Degenerate Random Model: Uniform random scores across both sets
    const randomPairs: PairwiseComparison[] = [
      ...Array.from({ length: 200 }, () => ({ similarity: Math.random(), isGenuine: true })),
      ...Array.from({ length: 200 }, () => ({ similarity: Math.random(), isGenuine: false })),
    ];

    const randomReport = BiometricEvaluationHarness.evaluate(randomPairs, 50);
    assert.ok(Math.abs(randomReport.auc - 0.50) < 0.15, `Expected random AUC ~0.50, got ${randomReport.auc}`);
    assert.strictEqual(randomReport.isModelDiscriminating, false, "Random model must fail discrimination check");
    console.log(`  [PASS] Random model flagged: AUC = ${randomReport.auc.toFixed(4)} (< 0.75 discrimination floor).\n`);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // TEST 2: Ticket T-12: Calibration Artifact & Ed25519 Startup Guard
  // ──────────────────────────────────────────────────────────────────────────
  console.log("TEST 2: Ticket T-12: Calibration File & Ed25519 Startup Guard...");
  {
    const calibPath = path.resolve(__dirname, "../../calibration/calibration.json");
    const verified = CalibrationGuard.loadAndVerify(calibPath);

    assert.strictEqual(verified.modelId, "sface_opencv_zoo_v1_primary");
    assert.strictEqual(verified.calibrationRunId, "sface_calib_run_20261010_v1");
    assert.strictEqual(verified.metrics.auc, 0.9942);
    assert.strictEqual(verified.metrics.advisoryFloorThreshold, 0.363);
    console.log(`  [PASS] Ed25519 signature validated for calibration run: ${verified.calibrationRunId}`);

    // Tampered payload verification failure
    let tamperedThrew = false;
    try {
      const fs = require("fs");
      const validDoc = JSON.parse(fs.readFileSync(calibPath, "utf8"));
      const tamperedDoc = {
        ...validDoc,
        payload: { ...validDoc.payload, modelSha256: "00000000000000000000000000000000" },
      };
      const tmpPath = path.resolve(__dirname, "../../calibration/tampered.json");
      fs.writeFileSync(tmpPath, JSON.stringify(tamperedDoc));
      try {
        (CalibrationGuard as any).cachedCalibration = null;
        CalibrationGuard.loadAndVerify(tmpPath);
      } finally {
        fs.unlinkSync(tmpPath);
        (CalibrationGuard as any).cachedCalibration = verified;
      }
    } catch (err: any) {
      tamperedThrew = true;
      assert.ok(err.message.includes("signature mismatch") || err.message.includes("Tampering intercepted"));
    }
    assert.strictEqual(tamperedThrew, true, "Tampered calibration payload must fail closed");
    console.log("  [PASS] Tampered calibration payload rejected cleanly (Fail-closed).\n");
  }

  // ──────────────────────────────────────────────────────────────────────────
  // TEST 3: Ticket T-13: 1:N Deduplication Operating-Point Calculator
  // ──────────────────────────────────────────────────────────────────────────
  console.log("TEST 3: Ticket T-13: Dedup Operating-Point Scale Calculator...");
  {
    const rows = DedupOperatingPointCalculator.generateScaleTable([500, 1000, 5000, 10000], 0.001);
    assert.strictEqual(rows.length, 4);
    assert.strictEqual(rows[0].gallerySizeN, 500);
    // At N=500 and FMR1=0.001: platform FMR = 1 - (1 - 0.001)^500 = ~0.393 (39.3%)
    assert.ok(rows[0].cumulativePlatformFmrN > 0.35 && rows[0].cumulativePlatformFmrN < 0.45);

    // Markdown table generation
    const md = DedupOperatingPointCalculator.formatMarkdownTable(rows);
    assert.ok(md.includes("Gallery Size ($N$)"));
    assert.ok(md.includes("Spark free-tier"));
    console.log("  [PASS] Dedup scaling projections generated successfully across N=500 to 10,000.\n");
  }

  // ──────────────────────────────────────────────────────────────────────────
  // TEST 4: Ticket T-14: ISO/IEC 29794-5 Quality Gate Service
  // ──────────────────────────────────────────────────────────────────────────
  console.log("TEST 4: Ticket T-14: ISO/IEC 29794-5 OFIQ Quality Gating...");
  {
    // High-quality face
    const cleanFace = QualityGateService.evaluate({
      width: 224,
      height: 224,
      leftEye: { x: 75, y: 100 },
      rightEye: { x: 145, y: 100 }, // IPD = 70px >= 35px
      yawDegrees: 4.2,
      pitchDegrees: 2.1,
      rollDegrees: 1.0,
      laplacianBlurScore: 145.0, // >= 60
      meanLuminance: 128.0,      // in [40, 220]
      faceConfidence: 0.98,
    });
    assert.strictEqual(cleanFace.passed, true);
    assert.strictEqual(cleanFace.score, 100);

    // Defective face: Low IPD (< 35px), severe blur (< 60), high yaw (> 25 deg)
    const badFace = QualityGateService.evaluate({
      width: 90, // < 112
      height: 90,
      leftEye: { x: 30, y: 40 },
      rightEye: { x: 50, y: 40 }, // IPD = 20px < 35px
      yawDegrees: 35.0,           // > 25 deg
      laplacianBlurScore: 25.0,   // < 60
      meanLuminance: 20.0,        // < 40
    });
    assert.strictEqual(badFace.passed, false);
    assert.ok(badFace.failureReasons.length >= 4);
    assert.ok(badFace.score < 50);
    console.log(`  [PASS] Quality gate passed clean frame (100/100) and rejected degraded frame (${badFace.score}/100).\n`);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // TEST 5: Ticket T-15: Firestore Spark Quota Instrumentation
  // ──────────────────────────────────────────────────────────────────────────
  console.log("TEST 5: Ticket T-15: Firestore Spark Quota Monitor...");
  {
    QuotaMonitorService.resetForTesting();
    assert.strictEqual(QuotaMonitorService.getAlarmLevel(), "NORMAL");

    // Record operations to 75%
    QuotaMonitorService.recordOperation(38000, 1000, 0);
    assert.strictEqual(QuotaMonitorService.getAlarmLevel(), "WARNING");

    // Record operations to 88%
    QuotaMonitorService.recordOperation(6500, 0, 0);
    assert.strictEqual(QuotaMonitorService.getAlarmLevel(), "CRITICAL");

    // Record operations to 96%
    QuotaMonitorService.recordOperation(4000, 0, 0);
    assert.strictEqual(QuotaMonitorService.getAlarmLevel(), "THROTTLED");

    // Assert safe to read throws on throttled
    let throttledThrew = false;
    try {
      QuotaMonitorService.assertSafeToRead(10);
    } catch (err: any) {
      throttledThrew = true;
      assert.ok(err.message.includes("throttled to protect database availability"));
    }
    assert.strictEqual(throttledThrew, true, "Quota throttling must block reads at 95%+ usage");
    console.log("  [PASS] Spark quota alarms (NORMAL -> WARNING -> CRITICAL -> THROTTLED) validated.\n");
  }

  console.log("================================================================================");
  console.log("   PHASE B TESTS COMPLETE: ALL 5/5 MEASUREMENT SUITES PASSED CLEANLY            ");
  console.log("================================================================================\n");
}

runPhaseBMeasurementSuite().catch((err) => {
  console.error("Phase B suite failed:", err);
  process.exit(1);
});
