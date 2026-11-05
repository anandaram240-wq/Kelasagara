// backend/src/tests/quality_and_template_privacy.test.ts
/**
 * Track D Test Suite: Quality Assessment, Enrollment, Lifecycle, and Privacy (Tickets D-01..D-05)
 * Enforces Invariants I-01, I-04, I-05, I-07, I-12.
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import {
  BiometricQualityAssessment,
  FaceGeometry,
  ImageQualityMetrics,
} from "../services/biometric_quality_assessment";
import {
  MultiSampleEnrollmentService,
  EnrollmentCandidateFrame,
} from "../services/multi_sample_enrollment";
import {
  TemplateLifecycleService,
  BiometricTemplateRecord,
} from "../services/template_lifecycle";
import { TemplatePrivacyService } from "../services/template_privacy";

describe("TRACK D: QUALITY, TEMPLATES AND PRIVACY (D-01..D-05)", () => {
  it("D-01: assesses ISO/IEC 29794-5 quality gates and computes Error-vs-Reject curve", () => {
    // 1. Compliant high-quality frame
    const goodGeometry: FaceGeometry = {
      bbox: { width: 120, height: 120 },
      landmarks: {
        leftEye: { x: 38, y: 51 },
        rightEye: { x: 74, y: 51 },
        nose: { x: 56, y: 71 },
        leftMouth: { x: 41, y: 92 },
        rightMouth: { x: 71, y: 92 },
      },
    };
    const goodMetrics: ImageQualityMetrics = {
      laplacianVariance: 180.0,
      meanLuminance: 125.0,
      yawDegrees: 4.5,
      pitchDegrees: -3.0,
      rollDegrees: 1.2,
      interEyeDistancePx: 36.0, // landmark dx is 36
    };

    const goodRes = BiometricQualityAssessment.assessQuality(goodGeometry, goodMetrics);
    // Note: IOD is 36 < 40px hard gate
    assert.equal(goodRes.passed, false);
    assert.ok(goodRes.rejectionReasons.some((r) => r.includes("INTER_EYE_DISTANCE_DEFICIENT")));

    // Fix IOD to 48px
    const fullCompliantGeometry: FaceGeometry = {
      bbox: { width: 140, height: 140 },
      landmarks: {
        leftEye: { x: 30, y: 50 },
        rightEye: { x: 78, y: 50 }, // dx = 48px
        nose: { x: 54, y: 72 },
        leftMouth: { x: 35, y: 95 },
        rightMouth: { x: 73, y: 95 },
      },
    };
    const compliantMetrics: ImageQualityMetrics = {
      laplacianVariance: 220.0,
      meanLuminance: 120.0,
      yawDegrees: 2.0,
      pitchDegrees: 1.5,
      rollDegrees: 0.5,
      interEyeDistancePx: 48.0,
    };
    const compliantRes = BiometricQualityAssessment.assessQuality(fullCompliantGeometry, compliantMetrics);
    assert.equal(compliantRes.passed, true);
    assert.ok(compliantRes.compositeQualityScore >= 0.70, "High-quality sample must score >= 0.70");

    // 2. Error-vs-Reject Curve
    const simulatedPairs = [
      { genuine: true, score: 0.32, quality: 0.38 }, // low quality, would fail standard threshold
      { genuine: true, score: 0.35, quality: 0.45 },
      { genuine: true, score: 0.42, quality: 0.62 },
      { genuine: true, score: 0.55, quality: 0.75 },
      { genuine: true, score: 0.68, quality: 0.88 },
    ];
    const evr = BiometricQualityAssessment.computeErrorVsRejectCurve(simulatedPairs, 0.363, [0.0, 0.2, 0.4]);
    console.log(`[D-01 EVR Curve] Rejection fractions:`, evr);
    assert.equal(evr.length, 3);
    assert.ok(evr[2].fnmr <= evr[0].fnmr, "Rejecting lowest quality samples must monotonically reduce FNMR");
  });

  it("D-02: executes multi-sample enrollment with outlier pruning and centroid construction", () => {
    const dim = 128;
    const baseIdentity = new Array(dim).fill(0).map(() => 0.088);

    // 5 frames: 3 center, 1 left, 1 right, plus 1 outlier
    const frames: EnrollmentCandidateFrame[] = [
      {
        frameId: "f1",
        embedding: baseIdentity.map((x) => x + (Math.random() - 0.5) * 0.002),
        yawDegrees: 0.5,
        qualityScore: 0.85,
      },
      {
        frameId: "f2",
        embedding: baseIdentity.map((x) => x + (Math.random() - 0.5) * 0.002),
        yawDegrees: -14.0, // left yaw
        qualityScore: 0.82,
      },
      {
        frameId: "f3",
        embedding: baseIdentity.map((x) => x + (Math.random() - 0.5) * 0.002),
        yawDegrees: 16.0,  // right yaw
        qualityScore: 0.80,
      },
      {
        frameId: "f4",
        embedding: baseIdentity.map((x) => x + (Math.random() - 0.5) * 0.002),
        yawDegrees: 2.0,
        qualityScore: 0.88,
      },
      {
        frameId: "f5_outlier",
        embedding: new Array(dim).fill(0).map((_, i) => (i % 2 === 0 ? 0.1 : -0.1)), // outlier vector
        yawDegrees: -5.0,
        qualityScore: 0.75,
      },
    ];

    const template = MultiSampleEnrollmentService.enroll(frames);
    assert.equal(template.frameCount, 4, "Outlier frame must be pruned, leaving 4 coherent frames");
    assert.equal(template.exemplars.length, 2, "Must select 2 closest exemplars");
    assert.ok(template.meanCoherence >= 0.95, "Coherent frames must have mean coherence >= 0.95");

    // Empirical centroid gain
    const probe = [baseIdentity.map((x) => x + (Math.random() - 0.5) * 0.005)];
    const gain = MultiSampleEnrollmentService.evaluateCentroidGain(template, frames[0], probe);
    console.log(`[D-02 Centroid Gain] Centroid Sim: ${gain.centroidMeanSim} | Single Sim: ${gain.singleMeanSim} | Gain: +${gain.deltaGainPct}%`);
    assert.ok(gain.centroidMeanSim >= 0.98);
  });

  it("D-03: manages template lifecycle, dual-model migration, and prevents near-threshold drift", () => {
    const dim = 128;
    const baseIdentity = new Array(dim).fill(0).map(() => 0.088);

    // 1. Create sealed template
    const templateRecord = TemplateLifecycleService.createSealedTemplate(
      "user_karnataka_101",
      baseIdentity,
      "sface_opencv_zoo_v1_primary",
      "1.0.0",
      "0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79"
    );
    assert.equal(templateRecord.adaptationCount, 0);
    assert.ok(templateRecord.templateSha256.length === 64);

    // 2. Migration check
    const migCurrent = TemplateLifecycleService.evaluateMigrationStatus(templateRecord, "sface_opencv_zoo_v1_primary");
    assert.equal(migCurrent.migrationRequired, false);

    const migLegacy = TemplateLifecycleService.evaluateMigrationStatus(templateRecord, "legacy_model_v0");
    assert.equal(migLegacy.migrationRequired, true);

    // 3. Anti-drift test: near-threshold probe (0.40) must be BLOCKED
    const nearThresholdProbe = baseIdentity.map((x) => x + (Math.random() - 0.5) * 0.05);
    const driftAttempt = TemplateLifecycleService.updateTemplateAdaptively({
      currentTemplate: templateRecord,
      probeEmbedding: nearThresholdProbe,
      matchCosine: 0.40, // above 0.363 accept threshold, but far below 0.75 high-confidence
      livenessPassed: true,
      qualityPassed: true,
      qualityScore: 0.85,
    });
    assert.equal(driftAttempt.updated, false, "Near-threshold attacker probe must NEVER trigger template adaptation");
    assert.ok(driftAttempt.reason.includes("ADAPTATION_BLOCKED"));

    // 4. Safe high-confidence update (0.82)
    const highConfProbe = baseIdentity.map((x) => x + (Math.random() - 0.5) * 0.001);
    const validUpdate = TemplateLifecycleService.updateTemplateAdaptively({
      currentTemplate: templateRecord,
      probeEmbedding: highConfProbe,
      matchCosine: 0.82,
      livenessPassed: true,
      qualityPassed: true,
      qualityScore: 0.85,
    });
    assert.equal(validUpdate.updated, true);
    assert.equal(validUpdate.newTemplate?.adaptationCount, 1);
  });

  it("D-05: implements orthogonal rotation (cosine-preserving) and envelope encryption with crypto-shredding", () => {
    const dim = 128;
    const tenantSecret = "karnataka_sovereign_tenant_salt_2026";
    const masterKmsKey = "mock_cloud_kms_key_encryption_key_32b";

    // 1. Generate orthogonal matrix R
    const ortho = TemplatePrivacyService.generateOrthogonalMatrix(tenantSecret, dim);
    assert.equal(ortho.length, dim);
    assert.equal(ortho[0].length, dim);

    // 2. Inner product preservation test: <R*u, R*v> == <u, v>
    const u = new Array(dim).fill(0).map(() => (Math.random() - 0.5));
    const v = new Array(dim).fill(0).map(() => (Math.random() - 0.5));
    // Normalize u and v
    const uNorm = Math.sqrt(u.reduce((s, x) => s + x * x, 0));
    const vNorm = Math.sqrt(v.reduce((s, x) => s + x * x, 0));
    const uUnit = u.map((x) => x / uNorm);
    const vUnit = v.map((x) => x / vNorm);

    let originalDot = 0;
    for (let i = 0; i < dim; i++) originalDot += uUnit[i] * vUnit[i];

    const uRot = TemplatePrivacyService.rotateEmbedding(uUnit, ortho);
    const vRot = TemplatePrivacyService.rotateEmbedding(vUnit, ortho);

    let rotatedDot = 0;
    for (let i = 0; i < dim; i++) rotatedDot += uRot[i] * vRot[i];

    console.log(`[D-05 Orthogonal Transform] Original Cosine: ${originalDot.toFixed(6)} | Rotated Cosine: ${rotatedDot.toFixed(6)}`);
    assert.ok(
      Math.abs(originalDot - rotatedDot) < 1e-4,
      "Orthogonal transformation must preserve cosine similarity exactly"
    );

    // 3. Envelope Encryption & Decryption Round-Trip
    const envelope = TemplatePrivacyService.encryptTemplate(
      "user_bangalore_42",
      "tenant_karnataka_gov",
      uUnit,
      masterKmsKey,
      ortho
    );
    assert.ok(envelope.ciphertextHex.length > 0);
    assert.ok(envelope.ivHex.length === 24); // 12 bytes = 24 hex chars
    assert.ok(envelope.authTagHex.length === 32); // 16 bytes = 32 hex chars

    const decrypted = TemplatePrivacyService.decryptTemplate(
      envelope,
      masterKmsKey,
      ortho
    );

    // Verify decrypted matches uUnit exactly
    let maxDiff = 0;
    for (let i = 0; i < dim; i++) {
      maxDiff = Math.max(maxDiff, Math.abs(uUnit[i] - decrypted[i]));
    }
    assert.ok(maxDiff < 1e-4, `Decrypted vector must match original: max diff = ${maxDiff}`);

    // 4. DPDPA Crypto-Shredding Test:
    // With altered/deleted master key, decryption fails immediately
    assert.throws(() => {
      TemplatePrivacyService.decryptTemplate(envelope, "wrong_master_key_post_shredding", ortho);
    });
  });
});
