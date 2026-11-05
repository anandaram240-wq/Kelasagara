// backend/src/tests/v19_6_2_adversarial_liveness.test.ts
import { describe, it, beforeEach } from "node:test";
import assert from "node:assert";
import sharp from "sharp";
import {
  SessionChallengeService,
  ActiveChallengeAction,
} from "../services/session_challenge_service";
import {
  TemporalActionValidator,
  BurstFrameInput,
} from "../services/temporal_action_validator";
import {
  EnrollmentStateMachine,
  InvalidStateTransitionError,
} from "../services/enrollment_state_machine";

async function createSyntheticFrame(options: {
  baseLuma: number;
  eyeOpenHeightPx: number;
  noiseSeed?: number;
}): Promise<string> {
  const width = 112;
  const height = 112;
  const buf = Buffer.alloc(width * height, options.baseLuma);

  // Texture variation to ensure distinct non-identical frames
  const seed = options.noiseSeed || 1;
  for (let y = 10; y < 100; y++) {
    for (let x = 10; x < 100; x++) {
      const delta = ((x * seed + y * 7) % 19) - 9;
      buf[y * width + x] = Math.max(0, Math.min(255, options.baseLuma + delta));
    }
  }

  // Draw ocular band across y in [35, 65]
  const halfH = Math.max(1, Math.floor(options.eyeOpenHeightPx / 2));
  for (const eyeX of [38, 74]) {
    for (let y = 50 - halfH; y <= 50 + halfH; y++) {
      for (let x = eyeX - 8; x <= eyeX + 8; x++) {
        buf[y * width + x] = 20;
      }
    }
  }

  const jpeg = await sharp(buf, { raw: { width, height, channels: 1 } })
    .jpeg({ quality: 90 })
    .toBuffer();
  return jpeg.toString("base64");
}

describe("V19.6.2 Server-Verifiable Liveness & Adversarial Capture Validation Suite", () => {
  beforeEach(() => {
    SessionChallengeService.reset();
  });

  describe("Phase 4: Challenge Freshness, Binding & Replay Defense", () => {
    it("ADV-01: Reusing a previously consumed nonce is rejected (Single-Use Invariant I-05)", () => {
      const uid = "user_victim_1";
      const chal = SessionChallengeService.createChallenge(uid, "ENROLLMENT", "BLINK");
      const [cId, nonce] = chal.nonce.split(":");

      // First consumption succeeds
      const firstResult = SessionChallengeService.validateAndConsume(
        cId,
        nonce,
        uid,
        "enrollment",
        "BLINK"
      );
      assert.strictEqual(firstResult.consumed, true);

      // Replay attempt fails with explicit replay detection
      assert.throws(
        () => {
          SessionChallengeService.validateAndConsume(
            cId,
            nonce,
            uid,
            "enrollment",
            "BLINK"
          );
        },
        /Invalid challenge ID|Replay attack detected/,
        "Must strictly reject previously consumed nonce"
      );
    });

    it("ADV-02: Submitting an expired challenge (>60s TTL) is rejected", () => {
      const uid = "user_expired_test";
      const chal = SessionChallengeService.issueChallenge(uid, "enrollment", true, "BLINK");

      // Artificially age the challenge past TTL
      chal.expiresAt = Date.now() - 5000;

      assert.throws(
        () => {
          SessionChallengeService.validateAndConsume(
            chal.challengeId,
            chal.nonce,
            uid,
            "enrollment",
            "BLINK"
          );
        },
        /Session expired/,
        "Must reject challenge exceeding TTL"
      );
    });

    it("ADV-03: Submitting a challenge for another caller UID (cross-user theft) is blocked (Invariant I-04)", () => {
      const victimUid = "user_victim_99";
      const attackerUid = "user_attacker_01";
      const chal = SessionChallengeService.issueChallenge(victimUid, "enrollment", true, "BLINK");

      assert.throws(
        () => {
          SessionChallengeService.validateAndConsume(
            chal.challengeId,
            chal.nonce,
            attackerUid, // Malicious attacker attempting to consume victim's challenge
            "enrollment",
            "BLINK"
          );
        },
        /Identity mismatch: Challenge bound to UID 'user_victim_99', attempted by 'user_attacker_01'/,
        "Must reject cross-user challenge theft"
      );
    });

    it("ADV-04: Submitting a challenge for another session / action is rejected", () => {
      const uid = "user_mismatch_test";
      const chal = SessionChallengeService.issueChallenge(
        uid,
        "enrollment",
        true,
        "BLINK",
        { clientSessionId: "session_original_abc" }
      );

      // Action mismatch: registered for enrollment, attempted for verification
      assert.throws(
        () => {
          SessionChallengeService.validateAndConsume(
            chal.challengeId,
            chal.nonce,
            uid,
            "verification",
            "BLINK"
          );
        },
        /Action mismatch/,
        "Must reject challenge operation mismatch"
      );

      // Session ID mismatch
      assert.throws(
        () => {
          SessionChallengeService.validateAndConsume(
            chal.challengeId,
            chal.nonce,
            uid,
            "enrollment",
            "BLINK",
            { clientSessionId: "session_forged_xyz" }
          );
        },
        /Session binding mismatch/,
        "Must reject challenge session ID mismatch"
      );
    });

    it("ADV-05: Submitting frames captured before challenge issuance is rejected", () => {
      const uid = "user_stale_frames";
      const chal = SessionChallengeService.issueChallenge(uid, "enrollment", true, "BLINK");
      const issueTime = chal.createdAt;

      // Attacker submits pre-recorded frames captured 10 seconds before challenge issuance
      assert.throws(
        () => {
          SessionChallengeService.validateAndConsume(
            chal.challengeId,
            chal.nonce,
            uid,
            "enrollment",
            "BLINK",
            {
              framesCapturedAtMs: [issueTime - 10000, issueTime - 9800, issueTime - 9600],
            }
          );
        },
        /Stale frame submission: Frames captured before challenge was issued/,
        "Must reject frames captured prior to challenge issuance"
      );
    });

    it("ADV-06: Omitting required sequence frames (< 3 frames) is rejected", async () => {
      const f0 = await createSyntheticFrame({ baseLuma: 128, eyeOpenHeightPx: 10, noiseSeed: 1 });
      const f1 = await createSyntheticFrame({ baseLuma: 128, eyeOpenHeightPx: 2, noiseSeed: 2 });

      const twoFrames: BurstFrameInput[] = [
        { sequenceIndex: 0, capturedOffsetMs: 0, jpegBase64: f0 },
        { sequenceIndex: 1, capturedOffsetMs: 120, jpegBase64: f1 },
      ];

      const res = await TemporalActionValidator.validateBurst(twoFrames, "BLINK");
      assert.strictEqual(res.passed, false);
      assert.strictEqual(res.rejectionReason, "INVALID_FRAME_COUNT");
    });

    it("ADV-07: Reordered frames are rejected", async () => {
      const f0 = await createSyntheticFrame({ baseLuma: 128, eyeOpenHeightPx: 10, noiseSeed: 1 });
      const f1 = await createSyntheticFrame({ baseLuma: 128, eyeOpenHeightPx: 2, noiseSeed: 2 });
      const f2 = await createSyntheticFrame({ baseLuma: 128, eyeOpenHeightPx: 10, noiseSeed: 3 });

      // Out-of-order sequence index: [1, 0, 2]
      const outOfOrderFrames: BurstFrameInput[] = [
        { sequenceIndex: 1, capturedOffsetMs: 0, jpegBase64: f1 },
        { sequenceIndex: 0, capturedOffsetMs: 100, jpegBase64: f0 },
        { sequenceIndex: 2, capturedOffsetMs: 200, jpegBase64: f2 },
      ];

      const res = await TemporalActionValidator.validateBurst(outOfOrderFrames, "BLINK");
      assert.strictEqual(res.passed, false);
      assert.strictEqual(res.rejectionReason, "OUT_OF_ORDER_FRAME_SEQUENCE");

      // Non-monotonic timestamp verification
      const uid = "user_non_monotonic";
      const chal = SessionChallengeService.issueChallenge(uid, "enrollment", true, "BLINK");
      assert.throws(
        () => {
          SessionChallengeService.validateAndConsume(
            chal.challengeId,
            chal.nonce,
            uid,
            "enrollment",
            "BLINK",
            {
              framesCapturedAtMs: [chal.createdAt + 100, chal.createdAt + 80, chal.createdAt + 200],
            }
          );
        },
        /Out of order frame sequence/,
        "Must reject non-monotonic frame capture timestamps"
      );
    });

    it("ADV-08: Repeating identical frames (static replay/freeze-frame) is rejected", async () => {
      const fStatic = await createSyntheticFrame({ baseLuma: 128, eyeOpenHeightPx: 10, noiseSeed: 1 });

      const staticBurst: BurstFrameInput[] = [
        { sequenceIndex: 0, capturedOffsetMs: 0, jpegBase64: fStatic },
        { sequenceIndex: 1, capturedOffsetMs: 100, jpegBase64: fStatic },
        { sequenceIndex: 2, capturedOffsetMs: 200, jpegBase64: fStatic },
      ];

      const res = await TemporalActionValidator.validateBurst(staticBurst, "BLINK");
      assert.strictEqual(res.passed, false);
      assert.strictEqual(res.rejectionReason, "DUPLICATE_FRAME_REPLAY_DETECTED");
    });

    it("ADV-09: Client reporting blinkVerified: true without actual ocular compression is rejected", async () => {
      // Create 3 open frames with slight noise difference so they are not byte-identical,
      // but all 3 have wide open eyes (no ocular compression in Frame 1)
      const fOpen0 = await createSyntheticFrame({ baseLuma: 128, eyeOpenHeightPx: 12, noiseSeed: 1 });
      const fOpen1 = await createSyntheticFrame({ baseLuma: 128, eyeOpenHeightPx: 12, noiseSeed: 2 });
      const fOpen2 = await createSyntheticFrame({ baseLuma: 128, eyeOpenHeightPx: 12, noiseSeed: 3 });

      const fakeBlinkBurst: BurstFrameInput[] = [
        { sequenceIndex: 0, capturedOffsetMs: 0, jpegBase64: fOpen0 },
        { sequenceIndex: 1, capturedOffsetMs: 120, jpegBase64: fOpen1 },
        { sequenceIndex: 2, capturedOffsetMs: 240, jpegBase64: fOpen2 },
      ];

      const res = await TemporalActionValidator.validateBurst(fakeBlinkBurst, "BLINK");
      assert.strictEqual(res.passed, false);
      assert.strictEqual(res.rejectionReason, "BLINK_TRAJECTORY_NOT_SATISFIED");
      assert.ok(
        res.telemetry.actionApexMetric > 0.65,
        `Apex metric (${res.telemetry.actionApexMetric}) must fail threshold 0.65`
      );
    });

    it("ADV-10: Photometric luma step anomaly (video splice) is rejected", async () => {
      // Frame 0 is normal (128), Frame 1 has massive flash/luma jump (220), Frame 2 is normal (128)
      const f0 = await createSyntheticFrame({ baseLuma: 128, eyeOpenHeightPx: 10, noiseSeed: 1 });
      const fFlash = await createSyntheticFrame({ baseLuma: 220, eyeOpenHeightPx: 2, noiseSeed: 2 });
      const f2 = await createSyntheticFrame({ baseLuma: 128, eyeOpenHeightPx: 10, noiseSeed: 3 });

      const splicedBurst: BurstFrameInput[] = [
        { sequenceIndex: 0, capturedOffsetMs: 0, jpegBase64: f0 },
        { sequenceIndex: 1, capturedOffsetMs: 120, jpegBase64: fFlash },
        { sequenceIndex: 2, capturedOffsetMs: 240, jpegBase64: f2 },
      ];

      const res = await TemporalActionValidator.validateBurst(splicedBurst, "BLINK");
      assert.strictEqual(res.passed, false);
      assert.strictEqual(res.rejectionReason, "PHOTOMETRIC_LUMA_STEP_ANOMALY");
    });

    it("ADV-11: Concurrent attempts to consume the same challenge serialize safely (exactly 1 succeeds)", async () => {
      const uid = "user_race_test";
      const chal = SessionChallengeService.issueChallenge(uid, "enrollment", true, "BLINK");
      const token = `${chal.challengeId}:${chal.nonce}`;

      // Simulate 5 simultaneous requests attempting to consume the same single-use challenge
      const attempts = await Promise.all([
        Promise.resolve(SessionChallengeService.consumeChallenge(token, uid, "enrollment", "BLINK")),
        Promise.resolve(SessionChallengeService.consumeChallenge(token, uid, "enrollment", "BLINK")),
        Promise.resolve(SessionChallengeService.consumeChallenge(token, uid, "enrollment", "BLINK")),
        Promise.resolve(SessionChallengeService.consumeChallenge(token, uid, "enrollment", "BLINK")),
        Promise.resolve(SessionChallengeService.consumeChallenge(token, uid, "enrollment", "BLINK")),
      ]);

      const successCount = attempts.filter((r) => r === true).length;
      const failureCount = attempts.filter((r) => r === false).length;

      assert.strictEqual(successCount, 1, "Exactly one concurrent attempt must succeed");
      assert.strictEqual(failureCount, 4, "All other concurrent attempts must be rejected");
    });

    it("ADV-12: Interrupted requests leave user in pending_face, never approved or active", () => {
      // Invariant I-02 & State Machine: If capture fails or is aborted mid-sequence,
      // the system can transition to QUALITY_REJECTED or remain PENDING_FACE.
      // Attempting to skip directly to ACTIVE without verified enrollment throws.
      assert.throws(
        () => {
          EnrollmentStateMachine.validateTransition("CHALLENGE_ISSUED", "ACTIVE", {
            actorRole: "client",
          });
        },
        InvalidStateTransitionError,
        "Cannot jump from CHALLENGE_ISSUED to ACTIVE"
      );

      assert.throws(
        () => {
          EnrollmentStateMachine.validateTransition("IN_PROGRESS", "ACTIVE", {
            actorRole: "client",
          });
        },
        InvalidStateTransitionError,
        "Cannot jump from IN_PROGRESS to ACTIVE"
      );

      // Safe fallback transitions are valid
      assert.doesNotThrow(() => {
        EnrollmentStateMachine.validateTransition("CHALLENGE_ISSUED", "PENDING_FACE", {
          actorRole: "system",
        });
      });
    });
  });
});
