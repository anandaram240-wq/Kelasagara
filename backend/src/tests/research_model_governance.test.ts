// backend/src/tests/research_model_governance.test.ts
//
// TEST SUITE: Invariants I-01, I-07, and I-18
// Proves that when using an uncalibrated / RESEARCH_ONLY model (such as kelasagara_mobilefacenet.onnx):
// 1. ModelRegistry identifies the model as RESEARCH_ONLY and clearedForAutomatedApproval === false.
// 2. ModelRegistry.assertClearedForAutomatedApproval() throws an invariant violation.
// 3. Artifact integrity check verifies expected SHA-256 (cde3799f041eca6a6a99bfac53d9e97eb81ff34ac450d519aa41a9c99bef7d7c).
// 4. BiometricEnrollmentService resolves unique enrollments to 'pending_review' with isApproved === false.
// 5. The backend CANNOT return 'approved', 'CLEAR', or 'VERIFIED' under this model.
// 6. Fail-closed behavior: technical failures resolve to 'technical_failure_retry' with isApproved === false.

import assert from "assert";
import path from "path";
import { ModelRegistry } from "../services/model_registry";
import { config } from "../config";
import { BiometricEnrollmentService } from "../services/biometric_enrollment";
import { FirestoreBiometricRepository } from "../services/firestore_biometric_repository";

async function runResearchModelGovernanceTests() {
  console.log("====================================================");
  console.log("🧪 TESTING INVARIANTS I-01 / I-07 / I-18 (MODEL GOVERNANCE)");
  console.log("====================================================");

  // Test 1: Model Registration for Primary and Fallback Production Models (Ticket T-02)
  const primaryMeta = ModelRegistry.getModel("sface_opencv_zoo_v1_primary");
  assert.strictEqual(
    primaryMeta.tier,
    "PILOT_SHADOW",
    "Primary SFace model must be registered as PILOT_SHADOW (Ticket T-02)"
  );
  assert.strictEqual(
    primaryMeta.clearedForAutomatedApproval,
    false,
    "clearedForAutomatedApproval must be false for pilot shadow SFace model (Gate 6)"
  );

  const fallbackMeta = ModelRegistry.getModel("sface_opencv_zoo_v1_fallback_int8");
  assert.strictEqual(
    fallbackMeta.tier,
    "PILOT_SHADOW",
    "Fallback SFace INT8 model must be registered as PILOT_SHADOW (Ticket T-02)"
  );
  assert.strictEqual(
    fallbackMeta.clearedForAutomatedApproval,
    false,
    "clearedForAutomatedApproval must be false for fallback SFace INT8 model"
  );

  const researchMeta = ModelRegistry.getModel("kelasagara_mobilefacenet_v1_arcface");
  assert.strictEqual(
    researchMeta.tier,
    "RESEARCH_ONLY",
    "Legacy MobileFaceNet must remain RESEARCH_ONLY"
  );
  assert.strictEqual(
    researchMeta.clearedForAutomatedApproval,
    false,
    "clearedForAutomatedApproval must be false for uncalibrated research model"
  );
  console.log("✔ Test 1: Model metadata correctly tagged (SFace in PILOT_SHADOW, auto-approval strictly false)");

  // Test 2: Invariant I-18 Artifact SHA-256 Integrity Verification
  const sfacePath = path.resolve(__dirname, "../../models/face_recognition_sface_2021dec.onnx");
  const sfaceIntegrityOk = ModelRegistry.verifyArtifactIntegrity(sfacePath, "sface_opencv_zoo_v1_primary");
  assert.strictEqual(sfaceIntegrityOk, true, "Artifact integrity check must pass for SFace FP32 binary");

  const sfaceInt8Path = path.resolve(__dirname, "../../models/face_recognition_sface_2021dec_int8.onnx");
  const sfaceInt8IntegrityOk = ModelRegistry.verifyArtifactIntegrity(sfaceInt8Path, "sface_opencv_zoo_v1_fallback_int8");
  assert.strictEqual(sfaceInt8IntegrityOk, true, "Artifact integrity check must pass for SFace INT8 binary");

  const mobileFaceNetPath = path.resolve(__dirname, "../../models/kelasagara_mobilefacenet.onnx");
  const mfnIntegrityOk = ModelRegistry.verifyArtifactIntegrity(mobileFaceNetPath, "kelasagara_mobilefacenet_v1_arcface");
  assert.strictEqual(mfnIntegrityOk, true, "Artifact integrity check must pass for MobileFaceNet binary");
  console.log("✔ Test 2: Invariant I-18 artifact checksum matches golden SHA-256 across all registered models");

  // Test 3: Automated Approval Block assertion throws on PILOT_SHADOW and RESEARCH_ONLY models
  assert.throws(
    () => {
      ModelRegistry.assertClearedForAutomatedApproval("sface_opencv_zoo_v1_primary");
    },
    /Invariant I-01 \/ I-18 Violation/,
    "assertClearedForAutomatedApproval must throw on PILOT_SHADOW models"
  );

  assert.throws(
    () => {
      ModelRegistry.assertClearedForAutomatedApproval("kelasagara_mobilefacenet_v1_arcface");
    },
    /Invariant I-01 \/ I-18 Violation/,
    "assertClearedForAutomatedApproval must throw on RESEARCH_ONLY models"
  );
  console.log("✔ Test 3: ModelRegistry.assertClearedForAutomatedApproval strictly denies unapproved models");

  // Test 4: BiometricEnrollmentService behavior: Zero automated approvals (Ticket T-02)
  // Mock repository methods for unit testing isolation
  const originalGetUserProfile = FirestoreBiometricRepository.getUserProfile;
  const originalCheckRateLimit = FirestoreBiometricRepository.checkRateLimit;
  const originalReserveSession = FirestoreBiometricRepository.reserveEnrollmentSession;
  const originalFindNearest = FirestoreBiometricRepository.findNearest;
  const originalCommitEnrollment = FirestoreBiometricRepository.commitEnrollment;
  const originalFinalizeSession = FirestoreBiometricRepository.finalizeEnrollmentSession;

  try {
    FirestoreBiometricRepository.getUserProfile = async () => ({
      accountStatus: "pending_face",
      phone: "+919876543210",
    });
    FirestoreBiometricRepository.checkRateLimit = async () => {};
    FirestoreBiometricRepository.reserveEnrollmentSession = async () => {};
    FirestoreBiometricRepository.findNearest = async () => null; // Unique human
    FirestoreBiometricRepository.finalizeEnrollmentSession = async () => {};

    let committedParams: any = null;
    FirestoreBiometricRepository.commitEnrollment = async (params: any) => {
      committedParams = params;
      return "pending_review";
    };

    const dummyImageBase64 = Buffer.alloc(112 * 112 * 3, 128).toString("base64");

    // 4A: Under PILOT_SHADOW SFace Model: Zero auto-approval, strictly pending_review
    const prodResult = await BiometricEnrollmentService.processEnrollment("test_uid_prod_001", {
      imageBase64: dummyImageBase64,
      role: "hirer",
    });
    assert.strictEqual(prodResult.status, "pending_review", "Pilot shadow model must route to pending_review (Ticket T-02)");
    assert.strictEqual(prodResult.isApproved, false, "isApproved must be false (zero automated approval)");
    assert.strictEqual(committedParams.isResearchOnly, true);
    console.log("✔ Test 4A: Unique enrollment under PILOT_SHADOW model strictly routes to 'pending_review' (Ticket T-02)");

    // 4B: Under RESEARCH_ONLY model: Approval is FORBIDDEN and resolves to pending_review
    const originalVersion = config.modelVersion;
    try {
      (config as any).modelVersion = "kelasagara_mobilefacenet_v1_arcface";

      const researchResult = await BiometricEnrollmentService.processEnrollment("test_uid_research_002", {
        imageBase64: dummyImageBase64,
        role: "hirer",
      });

      assert.notStrictEqual(researchResult.status, "approved", "Research model CANNOT return 'approved'");
      assert.strictEqual(researchResult.status, "pending_review", "Status must be 'pending_review'");
      assert.strictEqual(researchResult.isApproved, false, "isApproved must be false");
      assert.strictEqual(committedParams.isResearchOnly, true);
      console.log("✔ Test 4B: Unique enrollment under RESEARCH_ONLY model strictly resolves to 'pending_review'");
    } finally {
      (config as any).modelVersion = originalVersion;
    }

    // Test 5: Invariant I-01 Fail-Closed (Technical failure resolves to technical_failure_retry)
    FirestoreBiometricRepository.findNearest = async () => {
      throw new Error("Simulated transient network timeout");
    };

    const failResult = await BiometricEnrollmentService.processEnrollment("test_uid_002", {
      imageBase64: dummyImageBase64,
      role: "worker",
    });

    assert.strictEqual(failResult.status, "technical_failure_retry", "Failure must return technical_failure_retry");
    assert.strictEqual(failResult.isApproved, false, "Failure must never result in approval");
    assert.strictEqual(failResult.isDuplicate, false);
    console.log("✔ Test 5: Invariant I-01 fail-closed enforced: pipeline failure yields 'technical_failure_retry'");

  } finally {
    // Restore mocks
    FirestoreBiometricRepository.getUserProfile = originalGetUserProfile;
    FirestoreBiometricRepository.checkRateLimit = originalCheckRateLimit;
    FirestoreBiometricRepository.reserveEnrollmentSession = originalReserveSession;
    FirestoreBiometricRepository.findNearest = originalFindNearest;
    FirestoreBiometricRepository.commitEnrollment = originalCommitEnrollment;
    FirestoreBiometricRepository.finalizeEnrollmentSession = originalFinalizeSession;
  }

  console.log("====================================================");
  console.log("🎉 ALL INVARIANT I-01 / I-07 / I-18 GOVERNANCE TESTS PASSED!");
  console.log("====================================================");
}

runResearchModelGovernanceTests().catch((err) => {
  console.error("❌ Test Suite Failed:", err);
  process.exit(1);
});
