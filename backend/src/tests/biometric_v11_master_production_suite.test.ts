// FILE: backend/src/tests/biometric_v11_master_production_suite.test.ts

import assert from "node:assert/strict";
import { describe, test } from "node:test";
import { UmeyamaAlignerV11, FiveLandmarks } from "../biometrics/umeyama_aligner_v11";
import { Arcface512SessionPoolV11 } from "../biometrics/arcface_512_session_pool_v11";
import { PadLivenessFiqaGuardV11 } from "../biometrics/pad_liveness_fiqa_guard_v11";
import {
  BiometricCryptographicVaultV11,
  HnswBiometricIndexV11,
} from "../biometrics/encrypted_hnsw_vault_v11";
import {
  EmpiricalRocCalibratorV11,
  ParticipantRecordV11,
} from "../biometrics/empirical_roc_calibrator_v11";
import { FaceV11ProductionController } from "../routes/face_v11_routes";

function makeMockRes() {
  const res: {
    statusCode: number;
    body: any;
    status: (code: number) => any;
    json: (payload: any) => any;
  } = {
    statusCode: 200,
    body: null,
    status(code: number) {
      this.statusCode = code;
      return this;
    },
    json(payload: any) {
      this.body = payload;
      return this;
    },
  };
  return res;
}

function makeUnitVector512(seedIndex: number, noise = 0.0): number[] {
  const v = new Array<number>(512);
  let sumSq = 0;
  for (let i = 0; i < 512; i++) {
    let h = (seedIndex * 15485863 + i * 2038074743) | 0;
    h = Math.imul(h ^ (h >>> 16), 2246822507);
    h = Math.imul(h ^ (h >>> 13), 3266489909);
    const baseVal = ((h >>> 0) / 4294967296) * 2 - 1;
    const finalVal = baseVal + Math.sin(i * 0.5) * noise;
    v[i] = finalVal;
    sumSq += finalVal * finalVal;
  }
  const norm = Math.sqrt(sumSq);
  return v.map((x) => Number((x / norm).toFixed(6)));
}

describe("KELASAGARA BIOMETRIC ENGINE V11.0 — MASTER PRODUCTION TEST SUITE", () => {
  // -------------------------------------------------------------------------
  // PILLAR 1: UMEYAMA ALIGNMENT & ARCFACE 512-D CENTROID FUSION
  // -------------------------------------------------------------------------
  describe("Pillar 1: 5-Point Umeyama Affine Alignment & 512-D Centroid Fusion", () => {
    test("V11-P1-01: Umeyama computes similarity transform matrix to 112x112 ArcFace landmarks", () => {
      const detectedLandmarks: FiveLandmarks = {
        leftEye: { x: 40.0, y: 50.0 },
        rightEye: { x: 75.0, y: 50.0 },
        noseTip: { x: 57.0, y: 70.0 },
        leftMouth: { x: 42.0, y: 90.0 },
        rightMouth: { x: 72.0, y: 90.0 },
      };

      const matrix = UmeyamaAlignerV11.computeSimilarityTransform(detectedLandmarks);
      assert.ok(matrix.a !== undefined && matrix.b !== undefined, "Matrix scale/rotation components present");
      assert.ok(typeof matrix.tx === "number" && typeof matrix.ty === "number", "Translations computed");

      // Verify frontal pose angle estimation
      const pose = UmeyamaAlignerV11.estimatePoseAngles(detectedLandmarks);
      assert.equal(pose.isPoseAcceptable, true, "Frontal pose is acceptable");
      assert.ok(Math.abs(pose.yawDeg) <= 18.0, "Yaw within +/-18 deg tolerance");
      assert.ok(Math.abs(pose.pitchDeg) <= 18.0, "Pitch within +/-18 deg tolerance");
    });

    test("V11-P1-02: Umeyama flags extreme head pose (yaw > 18 deg) as unacceptable", () => {
      const turnedLandmarks: FiveLandmarks = {
        leftEye: { x: 10.0, y: 50.0 }, // Strongly shifted to side
        rightEye: { x: 55.0, y: 48.0 },
        noseTip: { x: 50.0, y: 70.0 },
        leftMouth: { x: 18.0, y: 92.0 },
        rightMouth: { x: 52.0, y: 90.0 },
      };

      const pose = UmeyamaAlignerV11.estimatePoseAngles(turnedLandmarks);
      assert.equal(pose.isPoseAcceptable, false, "Extreme head pose rejected");
      assert.ok(Math.abs(pose.yawDeg) > 18.0, `Yaw=${pose.yawDeg} exceeds 18 deg threshold`);
    });

    test("V11-P1-03: 3-Frame quality-weighted centroid fusion produces unit 512-D vector", () => {
      const v1 = makeUnitVector512(1, 0.0);
      const v2 = makeUnitVector512(1, 0.05);
      const v3 = makeUnitVector512(1, 0.10);

      const fusion = Arcface512SessionPoolV11.fuseQualityWeightedCentroid([
        { embedding: v1, qualityScore: 0.95 },
        { embedding: v2, qualityScore: 0.88 },
        { embedding: v3, qualityScore: 0.76 },
      ]);

      assert.equal(fusion.dimension, 512);
      assert.equal(fusion.modelVersion, "v11_adaface_512");
      assert.equal(fusion.frameCount, 3);
      assert.equal(fusion.fusedEmbedding.length, 512);

      // Verify L2 norm of fused vector is 1.0
      let sumSq = 0;
      for (const val of fusion.fusedEmbedding) sumSq += val * val;
      const norm = Math.sqrt(sumSq);
      assert.ok(Math.abs(norm - 1.0) < 1e-4, `Norm must be 1.0, got ${norm}`);

      // Verify cosine similarity against source frames is very high (> 0.95)
      const sim1 = Arcface512SessionPoolV11.computeCosineSimilarity(fusion.fusedEmbedding, v1);
      assert.ok(sim1 > 0.95, `Fused vector must strongly represent primary frame, got ${sim1}`);
    });
  });

  // -------------------------------------------------------------------------
  // PILLAR 2: PRE-INFERENCE FIQA & PASSIVE ANTI-SPOOFING (PAD)
  // -------------------------------------------------------------------------
  describe("Pillar 2: Pre-Inference FIQA & Passive Anti-Spoofing (PAD)", () => {
    test("V11-P2-01: FIQA rejects motion blur (sharpness variance < 15.0)", () => {
      const report = PadLivenessFiqaGuardV11.evaluateFrameQuality({
        width: 640,
        height: 480,
        sharpnessVariance: 8.5,
        meanLuminance: 125,
      });

      assert.equal(report.isAcceptable, false);
      assert.equal(report.rejectionReason, "MOTION_BLUR");
    });

    test("V11-P2-02: FIQA rejects underexposed or harsh lighting conditions", () => {
      const darkReport = PadLivenessFiqaGuardV11.evaluateFrameQuality({
        width: 640,
        height: 480,
        sharpnessVariance: 45.0,
        meanLuminance: 25.0, // too dark (< 40)
      });
      assert.equal(darkReport.isAcceptable, false);
      assert.equal(darkReport.rejectionReason, "UNDER_EXPOSED");

      const harshReport = PadLivenessFiqaGuardV11.evaluateFrameQuality({
        width: 640,
        height: 480,
        sharpnessVariance: 45.0,
        meanLuminance: 130.0,
        hemifaceDelta: 80.0, // harsh direct shadow (> 65)
      });
      assert.equal(harshReport.isAcceptable, false);
      assert.equal(harshReport.rejectionReason, "HARSH_LIGHTING");
    });

    test("V11-P2-03: Passive PAD detects screen replay and printed photo attacks", () => {
      // Screen replay (moiré)
      const screenReplay = PadLivenessFiqaGuardV11.evaluatePassiveLiveness({
        moirePatternDetected: true,
      });
      assert.equal(screenReplay.isLive, false);
      assert.equal(screenReplay.spoofCategory, "SCREEN_REPLAY");
      assert.equal(screenReplay.rejectionCode, "ERR_PAD_SPOOF_DETECTED");

      // Printed photo (specular glare or paper texture)
      const photoAttack = PadLivenessFiqaGuardV11.evaluatePassiveLiveness({
        specularGlareDetected: true,
      });
      assert.equal(photoAttack.isLive, false);
      assert.equal(photoAttack.spoofCategory, "PRINTED_PHOTO");

      // Genuine live face
      const liveFace = PadLivenessFiqaGuardV11.evaluatePassiveLiveness({
        highFrequencyTextureRatio: 0.92,
        moirePatternDetected: false,
        specularGlareDetected: false,
      });
      assert.equal(liveFace.isLive, true);
      assert.ok(liveFace.livenessProbability >= 0.85);
    });
  });

  // -------------------------------------------------------------------------
  // PILLAR 3: AES-256-GCM ENVELOPE ENCRYPTION & HNSW SUB-LINEAR INDEX
  // -------------------------------------------------------------------------
  describe("Pillar 3: DPDP Rules 2025 AES-256-GCM Vault & HNSW Sub-Linear Deduplication", () => {
    test("V11-P3-01: Encrypts 512-D embedding with AAD binding and recovers plaintext via AES-256-GCM", () => {
      const v = makeUnitVector512(42, 0.0);
      const envelope = BiometricCryptographicVaultV11.encryptEmbedding({
        uid: "KS_WORKER_AES_01",
        faceId: "ks_face_test_01",
        embedding: v,
        modelVersion: "v11_adaface_512",
      });

      assert.ok(envelope.encryptedCiphertextBase64.length > 0);
      assert.ok(envelope.authTagBase64.length > 0);
      assert.ok(envelope.ivBase64.length > 0);
      assert.ok(envelope.cancelableBiometricHash.length > 0);

      // Decrypt
      const decrypted = BiometricCryptographicVaultV11.decryptEmbedding({ envelope });
      assert.equal(decrypted.length, 512);

      // Verify decrypted values match original floats
      for (let i = 0; i < 512; i++) {
        assert.ok(Math.abs(decrypted[i] - v[i]) < 1e-5, `Dim ${i} match`);
      }
    });

    test("V11-P3-02: Cryptographic tamper detection rejects ciphertext corruption or cross-UID context splicing", () => {
      const v = makeUnitVector512(43, 0.0);
      const envelope = BiometricCryptographicVaultV11.encryptEmbedding({
        uid: "KS_WORKER_VICTIM",
        faceId: "ks_face_victim",
        embedding: v,
      });

      // 1. Splicing attempt: change uid in AAD context
      const splicedEnvelope = { ...envelope, uid: "KS_WORKER_ATTACKER" };
      assert.throws(() => {
        BiometricCryptographicVaultV11.decryptEmbedding({ envelope: splicedEnvelope });
      }, /ERR_BIOMETRIC_AUTH_TAG_FAILED/);

      // 2. Ciphertext corruption
      const corruptedEnvelope = {
        ...envelope,
        encryptedCiphertextBase64: Buffer.from("corrupted_ciphertext").toString("base64"),
      };
      assert.throws(() => {
        BiometricCryptographicVaultV11.decryptEmbedding({ envelope: corruptedEnvelope });
      }, /ERR_BIOMETRIC_AUTH_TAG_FAILED/);
    });

    test("V11-P3-03: HNSW index provides sub-linear nearest-neighbor search with self-exclusion", () => {
      const index = new HnswBiometricIndexV11();
      const userA = makeUnitVector512(10, 0.0);
      const userB = makeUnitVector512(20, 0.0);
      const userC = makeUnitVector512(30, 0.0);

      index.insert("UID_A", userA);
      index.insert("UID_B", userB);
      index.insert("UID_C", userC);

      assert.equal(index.size, 3);

      // Query with a noisy variant of userB
      const noisyB = makeUnitVector512(20, 0.03);
      const topMatch = index.searchKnn({ query: noisyB, k: 1 });
      assert.equal(topMatch.length, 1);
      assert.equal(topMatch[0].uid, "UID_B");
      assert.ok(topMatch[0].similarity > 0.95);

      // Self-exclusion test: exclude UID_B during re-registration search
      const excludedMatch = index.searchKnn({ query: noisyB, k: 1, excludeUid: "UID_B" });
      assert.equal(excludedMatch.length, 1);
      assert.notEqual(excludedMatch[0].uid, "UID_B", "UID_B was self-excluded");
    });
  });

  // -------------------------------------------------------------------------
  // PILLAR 4: EMPIRICAL ROC AUTO-CALIBRATOR & STEP-UP ACTIVE CHALLENGE
  // -------------------------------------------------------------------------
  describe("Pillar 4: Empirical ROC Calibrator, Decidability d', and Active Step-Up", () => {
    test("V11-P4-01: Decidability Index d' computes exact biometric separation", () => {
      // Well separated distributions
      const dPrimeHigh = EmpiricalRocCalibratorV11.computeDecidabilityDPrime(0.85, 0.05, 0.15, 0.06);
      assert.ok(dPrimeHigh >= 10.0, `High separation d' should be > 10, got ${dPrimeHigh}`);

      // Overlapping distributions
      const dPrimeLow = EmpiricalRocCalibratorV11.computeDecidabilityDPrime(0.40, 0.10, 0.35, 0.10);
      assert.ok(dPrimeLow < 1.0, `Low separation d' should be < 1.0, got ${dPrimeLow}`);
    });

    test("V11-P4-02: Corpus with N >= 30 participants and d' >= 4.5 unlocks GENERAL_PRODUCTION_APPROVED", () => {
      const records: ParticipantRecordV11[] = [];

      // Generate 32 distinct participants with 2 captures each (high intra-person similarity, low inter-person)
      for (let p = 0; p < 32; p++) {
        const pId = `PARTICIPANT_${p}`;
        const baseEmbedding = makeUnitVector512(p * 10, 0.0);
        const secondEmbedding = makeUnitVector512(p * 10, 0.04); // high similarity ~0.98

        records.push({
          participantId: pId,
          sessionNumber: 1,
          captureIndex: 1,
          embedding: baseEmbedding,
          qualityScore: 0.95,
        });
        records.push({
          participantId: pId,
          sessionNumber: 2,
          captureIndex: 2,
          embedding: secondEmbedding,
          qualityScore: 0.94,
        });
      }

      const cert = EmpiricalRocCalibratorV11.calibrateFromCorpus(records, "v11_adaface_512");

      assert.equal(cert.datasetParticipantCount, 32);
      assert.equal(cert.genuineComparisonCount, 32);
      assert.ok(cert.impostorComparisonCount > 100);
      assert.ok(cert.decidabilityDPrime >= 4.5, `d'=${cert.decidabilityDPrime} must be >= 4.5`);
      assert.ok(cert.equalErrorRate <= 0.015, `EER=${cert.equalErrorRate} must be <= 1.5%`);
      assert.equal(cert.isEmpiricallyValidatedForProduction, true);
      assert.equal(cert.releaseGateStatus, "GENERAL_PRODUCTION_APPROVED");
      assert.ok(cert.validationHash.length === 64, "HMAC-SHA256 validation hash generated");
    });

    test("V11-P4-03: Corpus with N < 30 enforces CONTROLLED_PILOT_ONLY release gate", () => {
      const records: ParticipantRecordV11[] = [];
      for (let p = 0; p < 10; p++) {
        const pId = `PILOT_PARTICIPANT_${p}`;
        records.push({
          participantId: pId,
          sessionNumber: 1,
          captureIndex: 1,
          embedding: makeUnitVector512(p * 10, 0.0),
          qualityScore: 0.95,
        });
        records.push({
          participantId: pId,
          sessionNumber: 2,
          captureIndex: 2,
          embedding: makeUnitVector512(p * 10, 0.04),
          qualityScore: 0.95,
        });
      }

      const cert = EmpiricalRocCalibratorV11.calibrateFromCorpus(records, "v11_adaface_512");
      assert.equal(cert.isEmpiricallyValidatedForProduction, false);
      assert.equal(cert.releaseGateStatus, "CONTROLLED_PILOT_ONLY");
    });

    test("V11-P4-04: Active liveness step-up challenge mints signed token and verifies valid client action", () => {
      const token = EmpiricalRocCalibratorV11.createStepUpChallenge("KS_WORKER_STEP_UP_1", "BLINK");
      assert.equal(token.action, "BLINK");
      assert.ok(token.expiresAtMs > Date.now());

      // Valid response
      const validResp = EmpiricalRocCalibratorV11.verifyStepUpChallenge({
        ...token,
        observedAction: "BLINK",
        actionMagnitude: 0.85,
        livenessConfidence: 0.92,
      });
      assert.equal(validResp.isValid, true);

      // Action mismatch
      const mismatchResp = EmpiricalRocCalibratorV11.verifyStepUpChallenge({
        ...token,
        observedAction: "TURN_LEFT",
        actionMagnitude: 20.0,
        livenessConfidence: 0.92,
      });
      assert.equal(mismatchResp.isValid, false);
      assert.ok(mismatchResp.reason?.includes("ERR_CHALLENGE_ACTION_MISMATCH"));

      // Expired token
      const expiredResp = EmpiricalRocCalibratorV11.verifyStepUpChallenge({
        ...token,
        expiresAtMs: Date.now() - 5000,
        observedAction: "BLINK",
        actionMagnitude: 0.85,
        livenessConfidence: 0.92,
      });
      assert.equal(expiredResp.isValid, false);
      assert.ok(expiredResp.reason?.includes("ERR_CHALLENGE_EXPIRED"));
    });
  });

  // -------------------------------------------------------------------------
  // PILLAR 5 & END-TO-END HTTP API CONTROLLER
  // -------------------------------------------------------------------------
  describe("Pillar 5: Production HTTP Controller Endpoints", () => {
    test("V11-API-01: GET /api/v11/biometrics/status returns 200 with production status", () => {
      const controller = new FaceV11ProductionController();
      const res = makeMockRes();
      controller.handleGetStatus({} as any, res as any);

      assert.equal(res.statusCode, 200);
      assert.equal(res.body.status, "ONLINE");
      assert.equal(res.body.version, "V11.0_PRODUCTION");
      assert.equal(res.body.thresholds.adaface512.tauHigh, 0.62);
      assert.equal(res.body.thresholds.adaface512.tauLow, 0.48);
    });

    test("V11-API-02: POST /enroll rejects motion blur with HTTP 422 before touching the gallery", async () => {
      const controller = new FaceV11ProductionController();
      const res = makeMockRes();

      await controller.handleEnrollOrReRegister(
        {
          body: {
            uid: "KS_USR_BLUR_TEST",
            embedding: makeUnitVector512(100),
            fiqaInput: {
              width: 640,
              height: 480,
              sharpnessVariance: 5.0, // blurred!
            },
          },
        } as any,
        res as any
      );

      assert.equal(res.statusCode, 422);
      assert.equal(res.body.error, "ERR_FIQA_REJECTED");
      assert.equal(res.body.fiqaReport.rejectionReason, "MOTION_BLUR");
    });

    test("V11-API-03: POST /enroll rejects presentation attack (screen replay) with HTTP 422", async () => {
      const controller = new FaceV11ProductionController();
      const res = makeMockRes();

      await controller.handleEnrollOrReRegister(
        {
          body: {
            uid: "KS_USR_SPOOF_TEST",
            embedding: makeUnitVector512(101),
            padTextureMap: {
              moirePatternDetected: true,
            },
          },
        } as any,
        res as any
      );

      assert.equal(res.statusCode, 422);
      assert.equal(res.body.error, "ERR_PAD_SPOOF_DETECTED");
      assert.equal(res.body.padResult.spoofCategory, "SCREEN_REPLAY");
    });

    test("V11-API-04: First-time enrollment succeeds with 200, encrypts vector, mints KS_FTOK_V11 token", async () => {
      const controller = new FaceV11ProductionController();
      const res = makeMockRes();
      const workerEmbedding = makeUnitVector512(200);

      await controller.handleEnrollOrReRegister(
        {
          body: {
            uid: "KS_WORKER_PROD_1",
            name: "Anand R",
            phone: "+919876543210",
            primarySkill: "Carpentry",
            dailyRate: 900,
            embedding: workerEmbedding,
          },
        } as any,
        res as any
      );

      assert.equal(res.statusCode, 200);
      assert.equal(res.body.status, "ENROLLED_AND_LOCKED");
      assert.ok(res.body.biometricLockToken.startsWith("KS_FTOK_V11_"));
      assert.equal(res.body.dimension, 512);
      assert.equal(res.body.modelVersion, "v11_adaface_512");
      assert.ok(res.body.cancelableBiometricHash.length > 0);
    });

    test("V11-API-05: Duplicate registration detects identical/high-similarity worker and returns HTTP 409", async () => {
      const controller = new FaceV11ProductionController();
      const faceVec = makeUnitVector512(300);

      // 1. Enroll Worker A
      const res1 = makeMockRes();
      await controller.handleEnrollOrReRegister(
        {
          body: {
            uid: "KS_ORIGINAL_WORKER",
            name: "Sunil V",
            phone: "+919123456789",
            embedding: faceVec,
          },
        } as any,
        res1 as any
      );
      assert.equal(res1.statusCode, 200);

      // 2. Impostor attempts to enroll with same face under different UID
      const res2 = makeMockRes();
      await controller.handleEnrollOrReRegister(
        {
          body: {
            uid: "KS_DUPLICATE_IMPOSTOR",
            name: "Syndicate Clone",
            phone: "+919999888877",
            embedding: faceVec,
          },
        } as any,
        res2 as any
      );

      assert.equal(res2.statusCode, 409);
      assert.equal(res2.body.status, "DUPLICATE_ACCOUNT_DETECTED");
      assert.ok(res2.body.duplicateAccountDetails.maskedUid.includes("***"));
      assert.ok(res2.body.duplicateAccountDetails.maskedPhone.includes("***"));
      assert.ok(res2.body.duplicateAccountDetails.cosineSimilarity >= 0.62);
    });

    test("V11-API-06: 1:1 e-KYC verification succeeds for enrolled face and fails for mismatch", async () => {
      const controller = new FaceV11ProductionController();
      const faceVec = makeUnitVector512(400);

      // Enroll
      const resEnroll = makeMockRes();
      await controller.handleEnrollOrReRegister(
        {
          body: {
            uid: "KS_EKYC_WORKER",
            name: "Deepak S",
            phone: "+919876500112",
            embedding: faceVec,
          },
        } as any,
        resEnroll as any
      );
      assert.equal(resEnroll.statusCode, 200);

      // Genuine verify
      const resVerify = makeMockRes();
      await controller.handleOneToOneEkyc(
        {
          body: {
            uid: "KS_EKYC_WORKER",
            embedding: makeUnitVector512(400, 0.02), // slight noise
          },
        } as any,
        resVerify as any
      );
      assert.equal(resVerify.statusCode, 200);
      assert.equal(resVerify.body.isMatch, true);
      assert.ok(resVerify.body.similarityScore >= 0.60);

      // Impostor verify
      const resImpostor = makeMockRes();
      await controller.handleOneToOneEkyc(
        {
          body: {
            uid: "KS_EKYC_WORKER",
            embedding: makeUnitVector512(999), // completely different face
          },
        } as any,
        resImpostor as any
      );
      assert.equal(resImpostor.statusCode, 401);
      assert.equal(resImpostor.body.isMatch, false);
    });

    test("V11-API-07: Authorized face rotation requires unlock-for-rotation step-up", async () => {
      const controller = new FaceV11ProductionController();
      const face1 = makeUnitVector512(500);
      const face2 = makeUnitVector512(501);

      // 1. Initial enroll
      const res1 = makeMockRes();
      await controller.handleEnrollOrReRegister(
        {
          body: {
            uid: "KS_ROTATION_WORKER",
            name: "Pooja M",
            phone: "+919988776655",
            embedding: face1,
          },
        } as any,
        res1 as any
      );
      assert.equal(res1.statusCode, 200);

      // 2. Attempt re-enroll without unlock -> 403 Forbidden
      const res2 = makeMockRes();
      await controller.handleEnrollOrReRegister(
        {
          body: {
            uid: "KS_ROTATION_WORKER",
            embedding: face2,
          },
        } as any,
        res2 as any
      );
      assert.equal(res2.statusCode, 403);
      assert.equal(res2.body.error, "ERR_BIOMETRIC_LOCKED");

      // 3. Unlock for rotation
      const resUnlock = makeMockRes();
      controller.handleUnlockForRotation(
        {
          body: {
            uid: "KS_ROTATION_WORKER",
            authReason: "LOST_PHONE_RECOVERY",
          },
        } as any,
        resUnlock as any
      );
      assert.equal(resUnlock.statusCode, 200);
      assert.equal(resUnlock.body.status, "UNLOCKED_FOR_ROTATION");

      // 4. Re-enroll succeeds now!
      const res3 = makeMockRes();
      await controller.handleEnrollOrReRegister(
        {
          body: {
            uid: "KS_ROTATION_WORKER",
            mode: "AUTHORIZED_RE_REGISTRATION",
            embedding: face2,
          },
        } as any,
        res3 as any
      );
      assert.equal(res3.statusCode, 200);
      assert.equal(res3.body.status, "RE_ENROLLED_AND_LOCKED");
      assert.equal(res3.body.enrollmentVersion, 2);
    });
  });
});
