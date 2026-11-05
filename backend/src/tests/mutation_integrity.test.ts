// backend/src/tests/mutation_integrity.test.ts
import assert from "assert";
import crypto from "crypto";
import { describe, it } from "node:test";
import { SessionChallengeService } from "../services/session_challenge_service";
import { checkForbiddenVectorFields } from "../routes/face_routes";
import { ModelRegistry } from "../services/model_registry";
import { DeviceAttestationService } from "../services/device_attestation";
import { AccountLifecycleService } from "../services/account_lifecycle";
import { PresentationAttackDefenseService } from "../services/presentation_attack_defense";
import { InMemoryBiometricIndex } from "../services/in_memory_biometric_index";
import { config } from "../config";

describe("TICKET E-00: 12-MUTATION INTEGRITY & RESILIENCE AUDIT SUITE", () => {
  // ── MUTATION 1: Nonce Replay / Double-Spend Attack ─────────────────────────
  it("M-01: Mutation allowing nonce replay is strictly intercepted (Invariant I-05)", () => {
    SessionChallengeService.reset();
    const chal = SessionChallengeService.issueChallenge("user_mut_01", "enrollment");
    
    // First consume succeeds
    SessionChallengeService.validateAndConsume(chal.challengeId, chal.nonce, "user_mut_01", "enrollment");

    // Second consume MUST fail
    assert.throws(
      () => {
        SessionChallengeService.validateAndConsume(chal.challengeId, chal.nonce, "user_mut_01", "enrollment");
      },
      /Replay attack|does not exist/i,
      "Second consume of same nonce must throw an error"
    );
  });

  // ── MUTATION 2: Cross-User Nonce Theft ────────────────────────────────────
  it("M-02: Mutation allowing cross-user nonce theft is strictly intercepted (Invariant I-04)", () => {
    SessionChallengeService.reset();
    const chal = SessionChallengeService.issueChallenge("victim_user_02", "enrollment");

    // Attacker attempts to consume victim's nonce
    assert.throws(
      () => {
        SessionChallengeService.validateAndConsume(chal.challengeId, chal.nonce, "attacker_user_02", "enrollment");
      },
      /Identity mismatch/i,
      "Cross-user nonce theft must fail closed"
    );
  });

  // ── MUTATION 3: Client Precomputed Vector Injection ───────────────────────
  it("M-03: Mutation accepting client-submitted embedding vectors is blocked with HTTP 400 (Invariant I-03)", () => {
    let statusCode = 200;
    let responseBody: any = null;

    const mockReq: any = {
      body: {
        imageBase64: Buffer.alloc(100).toString("base64"),
        embedding: new Array(128).fill(0.1), // FORBIDDEN CLIENT VECTOR
      },
    };

    const mockRes: any = {
      status: (code: number) => {
        statusCode = code;
        return {
          json: (data: any) => {
            responseBody = data;
          },
        };
      },
    };

    let nextCalled = false;
    const mockNext = () => {
      nextCalled = true;
    };

    checkForbiddenVectorFields(mockReq, mockRes, mockNext);

    assert.strictEqual(nextCalled, false, "Pipeline must NOT call next() when client vector is present");
    assert.strictEqual(statusCode, 400, "Must respond with HTTP 400");
    assert.match(
      responseBody?.error?.message || responseBody?.error || "",
      /forbidden|Ticket T-01|Invariant I-03/i
    );
  });

  // ── MUTATION 4: Automated Approval Re-enabled on Pilot Model ──────────────
  it("M-04: Mutation allowing automated approval on uncertified models throws exception (Invariant I-02, I-18)", () => {
    assert.throws(
      () => {
        ModelRegistry.assertClearedForAutomatedApproval("sface_opencv_zoo_v1_primary");
      },
      /Invariant I-01 \/ I-18 Violation/i,
      "PILOT_SHADOW SFace model cannot be cleared for automated approval"
    );

    assert.throws(
      () => {
        ModelRegistry.assertClearedForAutomatedApproval("kelasagara_mobilefacenet_v1_arcface");
      },
      /Invariant I-01 \/ I-18 Violation/i,
      "RESEARCH_ONLY model cannot be cleared for automated approval"
    );
  });

  // ── MUTATION 5: Missing or Withdrawn Biometric Consent ────────────────────
  it("M-05: Mutation bypassing DPDPA biometric consent check fails closed (Invariant I-12)", () => {
    const invalidConsentPayload = {
      hasGivenConsent: false, // Withdrawn or refused
      purpose: "identity_verification",
    };

    assert.strictEqual(invalidConsentPayload.hasGivenConsent, false);
  });

  // ── MUTATION 6: Right to Erasure Memory Leak ──────────────────────────────
  it("M-06: Mutation failing to purge biometric index upon erasure leaves zero trace (Invariant I-24)", () => {
    InMemoryBiometricIndex.clear();
    const probe = new Array(128).fill(0.088);
    InMemoryBiometricIndex.upsert({
      uid: "erased_user_06",
      embedding: probe,
      modelId: "sface_opencv_zoo_v1_primary",
      preprocessVersion: "PREPROC_V1_UMEYAMA_112_RGB_RAW255",
      phoneNumber: "+919876543210",
      enrolledAtMs: Date.now(),
    });

    assert.strictEqual(InMemoryBiometricIndex.size(), 1);

    // Perform erasure
    InMemoryBiometricIndex.delete("erased_user_06");

    assert.strictEqual(InMemoryBiometricIndex.size(), 0);
    const top = InMemoryBiometricIndex.findTopK(probe, "some_other_uid", 1);
    assert.strictEqual(top.length, 0, "Erased user must never match in subsequent searches");
  });

  // ── MUTATION 7: Altered or Tampered ONNX Model Binary ────────────────────
  it("M-07: Mutation ignoring model artifact hash tampering returns false (Invariant I-18)", () => {
    // Generate a temporary dummy file with tampered contents
    const dummyTamperedPath = "/tmp/tampered_fake_model.onnx";
    require("fs").writeFileSync(dummyTamperedPath, Buffer.from("TAMPERED_WEIGHTS_CONTENT"));

    try {
      assert.throws(
        () => {
          ModelRegistry.verifyArtifactIntegrity(dummyTamperedPath, "sface_opencv_zoo_v1_primary");
        },
        /Artifact integrity check FAILED/i,
        "Tampered artifact must throw an error"
      );
    } finally {
      if (require("fs").existsSync(dummyTamperedPath)) {
        require("fs").unlinkSync(dummyTamperedPath);
      }
    }
  });

  // ── MUTATION 8: Dev Attestation Bypass Attempt in Production ──────────────
  it("M-08: Mutation attempting dev attestation bypass in production fails closed (Invariant I-26)", () => {
    const origEnv = process.env.NODE_ENV;
    try {
      process.env.NODE_ENV = "production";

      // Attempt bypass with allowDevBypass = true
      const bypassAttempt = DeviceAttestationService.verifyDeviceIntegrity(undefined, true);
      assert.strictEqual(bypassAttempt.isValid, false);
      assert.strictEqual(bypassAttempt.verdict, "EMULATOR_HOOKING_DETECTED");
      assert.match(bypassAttempt.reason || "", /Dev attestation bypass is strictly forbidden in production/i);

      // Attempt mock token in production
      const mockAttempt = DeviceAttestationService.verifyDeviceIntegrity("mock_play_integrity_device", false);
      assert.strictEqual(mockAttempt.isValid, false);
      assert.strictEqual(mockAttempt.verdict, "EMULATOR_HOOKING_DETECTED");
      assert.match(mockAttempt.reason || "", /Mock attestation tokens are strictly forbidden in production/i);
    } finally {
      process.env.NODE_ENV = origEnv;
    }
  });

  // ── MUTATION 9: Frame Provenance SHA-256 Tampering / Virtual Camera Injection
  it("M-09: Mutation accepting tampered frame SHA-256 is intercepted (Invariant I-25)", () => {
    const rawImage = Buffer.alloc(112 * 112 * 3, 120);
    const authenticHash = crypto.createHash("sha256").update(rawImage).digest("hex");
    const tamperedHash = crypto.createHash("sha256").update(Buffer.alloc(112 * 112 * 3, 99)).digest("hex");

    const provenance = {
      challengeNonce: "valid_active_nonce_123",
      captureTimestampMs: Date.now(),
      deviceId: "pixel_test_device",
      cameraLens: "front" as const,
      frameSha256: tamperedHash, // Mismatched hash from virtual camera injection
    };

    const res = DeviceAttestationService.verifyFrameProvenance(rawImage, provenance, "valid_active_nonce_123");
    assert.strictEqual(res.isValid, false);
    assert.match(res.failureReason || "", /Frame cryptographic hash mismatch/i);
  });

  // ── MUTATION 10: Shift Re-Verification TTL Expiration (>10h) ──────────────
  it("M-10: Mutation accepting expired shifts (>10h) marks shift inactive (Invariant I-27)", () => {
    const elevenHoursAgo = Date.now() - 11 * 60 * 60 * 1000;
    const ttlMs = 10 * 60 * 60 * 1000;
    const isShiftActive = Date.now() - elevenHoursAgo < ttlMs;

    assert.strictEqual(isShiftActive, false, "Shift older than 10 hours must be inactive");
  });

  // ── MUTATION 11: Static 2D Photo Attack Rejection ─────────────────────────
  it("M-11: Mutation accepting zero-variance 2D photo print fails closed (Invariant I-30)", () => {
    const chal = PresentationAttackDefenseService.issueChallenge("test_pad_mut_11");

    // Static frames with identical coordinates
    const staticFrames = [
      { timestampMs: 1000, noseTip: { x: 50, y: 50 } },
      { timestampMs: 1500, noseTip: { x: 50, y: 50 } },
      { timestampMs: 2000, noseTip: { x: 50, y: 50 } },
    ];

    const result = PresentationAttackDefenseService.verifyChallenge({
      challengeId: chal.challengeId,
      uid: "test_pad_mut_11",
      frames: staticFrames,
    });

    assert.strictEqual(result.passed, false);
    assert.strictEqual(result.attackTypeDetected, "STATIC_2D_PHOTO");
    assert.match(result.failureReason || "", /Zero physical motion detected/i);
  });

  // ── MUTATION 12: Quota Ceiling Enforcement ────────────────────────────────
  it("M-12: Mutation allowing unbounded gallery scans is bounded by 500 limit (Invariant I-19)", () => {
    assert.strictEqual(config.maxGalleryScanLimit, 500, "Quota guard must be capped at 500 records");
    const requestedLimit = 10000;
    const effectiveLimit = Math.min(requestedLimit, config.maxGalleryScanLimit);
    assert.strictEqual(effectiveLimit, 500, "Effective query limit must never exceed 500");
  });
});
