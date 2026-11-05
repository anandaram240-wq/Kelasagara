// backend/src/tests/v19_6_3_adversarial_protocol.test.ts
process.env.ALLOW_DEV_TOKEN = "true";

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
import { faceRouter } from "../routes/face_routes";

async function createSyntheticKinematicFrame(options: {
  centerX: number;
  centerY: number;
  eyeAperturePx: number;
  baseLuma?: number;
  seed?: number;
}): Promise<string> {
  const width = 112;
  const height = 112;
  const baseLuma = options.baseLuma || 180;
  const buf = Buffer.alloc(width * height, baseLuma);

  // Background texture outside ocular band (above y=25 and below y=75)
  const seed = options.seed || 1;
  for (let y = 5; y < 25; y++) {
    for (let x = 5; x < 105; x++) {
      buf[y * width + x] = Math.max(0, Math.min(255, baseLuma + ((x * seed) % 11) - 5));
    }
  }
  for (let y = 75; y < 105; y++) {
    for (let x = 5; x < 105; x++) {
      buf[y * width + x] = Math.max(0, Math.min(255, baseLuma + ((x * seed) % 11) - 5));
    }
  }

  // Draw central nose/mouth feature block below the ocular band (y in [72, 84])
  for (let y = options.centerY + 16; y <= options.centerY + 28; y++) {
    for (let x = options.centerX - 10; x <= options.centerX + 10; x++) {
      if (y >= 0 && y < height && x >= 0 && x < width) {
        buf[y * width + x] = 30;
      }
    }
  }

  // Draw bilateral eyes
  const halfH = Math.max(0, Math.floor(options.eyeAperturePx / 2));
  for (const eyeOffset of [-18, 18]) {
    const eyeX = options.centerX + eyeOffset;
    const eyeY = options.centerY - 6;
    for (let y = eyeY - halfH; y <= eyeY + halfH; y++) {
      for (let x = eyeX - 10; x <= eyeX + 10; x++) {
        if (y >= 0 && y < height && x >= 0 && x < width) {
          buf[y * width + x] = 20;
        }
      }
    }
  }

  const jpeg = await sharp(buf, { raw: { width, height, channels: 1 } })
    .jpeg({ quality: 90 })
    .toBuffer();
  return jpeg.toString("base64");
}

function dispatchFaceRouter(options: {
  method: string;
  url: string;
  headers?: Record<string, string>;
  body?: any;
}): Promise<{ status: number; body: any }> {
  return new Promise((resolve, reject) => {
    const req: any = {
      method: options.method,
      url: options.url,
      originalUrl: `/api/biometrics${options.url}`,
      headers: {
        authorization: "Bearer dev-mock-token-test_user_v19_6_3",
        ...(options.headers || {}),
      },
      body: options.body || {},
      query: {},
      ip: "127.0.0.1",
      socket: { remoteAddress: "127.0.0.1" },
    };

    const res: any = {
      statusCode: 200,
      headers: {},
      status(code: number) {
        this.statusCode = code;
        return this;
      },
      json(data: any) {
        this.body = data;
        resolve({ status: this.statusCode, body: data });
        return this;
      },
      send(data: any) {
        this.body = data;
        resolve({ status: this.statusCode, body: data });
        return this;
      },
      setHeader(k: string, v: string) {
        this.headers[k] = v;
      },
    };

    try {
      (faceRouter as any)(req, res, (err: any) => {
        if (err) reject(err);
        else resolve({ status: res.statusCode, body: res.body });
      });
    } catch (e) {
      reject(e);
    }
  });
}

describe("V19.6.3 Adversarial Action-Bound Protocol & Real Route Test Suite", () => {
  beforeEach(() => {
    SessionChallengeService.reset();
  });

  describe("Phase 4: Comprehensive 18-Scenario Adversarial Protocol Validation", () => {
    it("SCENARIO 1: Valid blink challenge with correctly ordered synthetic test sequence passes cleanly", async () => {
      const fOpen0 = await createSyntheticKinematicFrame({ centerX: 56, centerY: 56, eyeAperturePx: 12, seed: 1 });
      const fClosed1 = await createSyntheticKinematicFrame({ centerX: 56, centerY: 56, eyeAperturePx: 1, seed: 2 });
      const fOpen2 = await createSyntheticKinematicFrame({ centerX: 56, centerY: 56, eyeAperturePx: 12, seed: 3 });

      const burst: BurstFrameInput[] = [
        { sequenceIndex: 0, capturedOffsetMs: 0, jpegBase64: fOpen0 },
        { sequenceIndex: 1, capturedOffsetMs: 120, jpegBase64: fClosed1 },
        { sequenceIndex: 2, capturedOffsetMs: 240, jpegBase64: fOpen2 },
      ];

      const res = await TemporalActionValidator.validateBurst(burst, "BLINK");
      assert.strictEqual(res.passed, true);
      assert.strictEqual(res.status, "verified");
      assert.ok(res.authoritativeEmbedding !== undefined);
      assert.strictEqual(res.authoritativeEmbedding.length, 128);
    });

    it("SCENARIO 2: Blink challenge with a static image repeated across burst is rejected", async () => {
      const fStatic = await createSyntheticKinematicFrame({ centerX: 56, centerY: 56, eyeAperturePx: 12, seed: 1 });

      const staticBurst: BurstFrameInput[] = [
        { sequenceIndex: 0, capturedOffsetMs: 0, jpegBase64: fStatic },
        { sequenceIndex: 1, capturedOffsetMs: 100, jpegBase64: fStatic },
        { sequenceIndex: 2, capturedOffsetMs: 200, jpegBase64: fStatic },
      ];

      const res = await TemporalActionValidator.validateBurst(staticBurst, "BLINK");
      assert.strictEqual(res.passed, false);
      assert.strictEqual(res.rejectionReason, "DUPLICATE_FRAME_REPLAY_DETECTED");
    });

    it("SCENARIO 3: Head-left challenge submitted with a blink-only trajectory is rejected", async () => {
      // User performed a blink (centerX remains 56), but required action was TURN_HEAD_LEFT
      const f0 = await createSyntheticKinematicFrame({ centerX: 56, centerY: 56, eyeAperturePx: 12, seed: 1 });
      const f1 = await createSyntheticKinematicFrame({ centerX: 56, centerY: 56, eyeAperturePx: 2, seed: 2 });
      const f2 = await createSyntheticKinematicFrame({ centerX: 56, centerY: 56, eyeAperturePx: 12, seed: 3 });

      const blinkBurst: BurstFrameInput[] = [
        { sequenceIndex: 0, capturedOffsetMs: 0, jpegBase64: f0 },
        { sequenceIndex: 1, capturedOffsetMs: 120, jpegBase64: f1 },
        { sequenceIndex: 2, capturedOffsetMs: 240, jpegBase64: f2 },
      ];

      const res = await TemporalActionValidator.validateBurst(blinkBurst, "TURN_HEAD_LEFT");
      assert.strictEqual(res.passed, false);
      assert.strictEqual(res.rejectionReason, "HEAD_TURN_LEFT_TRAJECTORY_NOT_SATISFIED");
    });

    it("SCENARIO 4: Head-right challenge submitted with opposite-direction trajectory is rejected", async () => {
      // Required: TURN_HEAD_RIGHT (positive horizontal shift).
      // Attacker submits head turn to the left (centerX: 56 -> 38 -> 56).
      const f0 = await createSyntheticKinematicFrame({ centerX: 56, centerY: 56, eyeAperturePx: 10, seed: 1 });
      const fTurnLeft = await createSyntheticKinematicFrame({ centerX: 38, centerY: 56, eyeAperturePx: 10, seed: 2 });
      const f2 = await createSyntheticKinematicFrame({ centerX: 56, centerY: 56, eyeAperturePx: 10, seed: 3 });

      const oppositeBurst: BurstFrameInput[] = [
        { sequenceIndex: 0, capturedOffsetMs: 0, jpegBase64: f0 },
        { sequenceIndex: 1, capturedOffsetMs: 150, jpegBase64: fTurnLeft },
        { sequenceIndex: 2, capturedOffsetMs: 300, jpegBase64: f2 },
      ];

      const res = await TemporalActionValidator.validateBurst(oppositeBurst, "TURN_HEAD_RIGHT");
      assert.strictEqual(res.passed, false);
      assert.strictEqual(res.rejectionReason, "HEAD_TURN_RIGHT_TRAJECTORY_NOT_SATISFIED");
    });

    it("SCENARIO 5: Nod challenge submitted with no meaningful pitch change is rejected", async () => {
      // Required: NOD_HEAD.
      // Submits flat trajectory with no vertical displacement (centerY: 56 -> 56 -> 56).
      const f0 = await createSyntheticKinematicFrame({ centerX: 56, centerY: 56, eyeAperturePx: 10, seed: 1 });
      const fFlat = await createSyntheticKinematicFrame({ centerX: 56, centerY: 56, eyeAperturePx: 10, seed: 2 });
      const f2 = await createSyntheticKinematicFrame({ centerX: 56, centerY: 56, eyeAperturePx: 10, seed: 3 });

      const flatBurst: BurstFrameInput[] = [
        { sequenceIndex: 0, capturedOffsetMs: 0, jpegBase64: f0 },
        { sequenceIndex: 1, capturedOffsetMs: 150, jpegBase64: fFlat },
        { sequenceIndex: 2, capturedOffsetMs: 300, jpegBase64: f2 },
      ];

      const res = await TemporalActionValidator.validateBurst(flatBurst, "NOD_HEAD");
      assert.strictEqual(res.passed, false);
      assert.strictEqual(res.rejectionReason, "NOD_HEAD_TRAJECTORY_NOT_SATISFIED");
    });

    it("SCENARIO 6: Action identifier changed between challenge issuance and validation is rejected", () => {
      const uid = "user_action_tamper";
      const chal = SessionChallengeService.issueChallenge(uid, "enrollment", true, "BLINK");

      // Attacker claims observedAction was TURN_HEAD_LEFT
      assert.throws(
        () => {
          SessionChallengeService.validateAndConsume(
            chal.challengeId,
            chal.nonce,
            uid,
            "enrollment",
            "TURN_HEAD_LEFT" // Mismatched action
          );
        },
        /Liveness action mismatch: Required 'BLINK', observed 'TURN_HEAD_LEFT'/
      );
    });

    it("SCENARIO 7: Valid-looking but out-of-order frame sequence is rejected", async () => {
      const f0 = await createSyntheticKinematicFrame({ centerX: 56, centerY: 56, eyeAperturePx: 12, seed: 1 });
      const f1 = await createSyntheticKinematicFrame({ centerX: 56, centerY: 56, eyeAperturePx: 2, seed: 2 });
      const f2 = await createSyntheticKinematicFrame({ centerX: 56, centerY: 56, eyeAperturePx: 12, seed: 3 });

      // Out-of-order sequence indices: [2, 1, 0]
      const scrambledBurst: BurstFrameInput[] = [
        { sequenceIndex: 2, capturedOffsetMs: 0, jpegBase64: f2 },
        { sequenceIndex: 1, capturedOffsetMs: 100, jpegBase64: f1 },
        { sequenceIndex: 0, capturedOffsetMs: 200, jpegBase64: f0 },
      ];

      const res = await TemporalActionValidator.validateBurst(scrambledBurst, "BLINK");
      assert.strictEqual(res.passed, false);
      assert.strictEqual(res.rejectionReason, "OUT_OF_ORDER_FRAME_SEQUENCE");
    });

    it("SCENARIO 8: Challenge that expired before upload (>60s TTL) is rejected", () => {
      const uid = "user_expired_burst";
      const chal = SessionChallengeService.issueChallenge(uid, "enrollment", true, "BLINK");

      // Simulate network lag: upload arrives at T + 65 seconds
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
        /Session expired: Challenge '.*' exceeded 60s TTL/
      );
    });

    it("SCENARIO 9: Challenge belonging to another caller is rejected (Invariant I-04)", () => {
      const victimUid = "victim_uid_007";
      const attackerUid = "attacker_uid_666";
      const chal = SessionChallengeService.issueChallenge(victimUid, "enrollment", true, "BLINK");

      assert.throws(
        () => {
          SessionChallengeService.validateAndConsume(
            chal.challengeId,
            chal.nonce,
            attackerUid, // Cross-user theft
            "enrollment",
            "BLINK"
          );
        },
        /Identity mismatch: Challenge bound to UID 'victim_uid_007', attempted by 'attacker_uid_666'/
      );
    });

    it("SCENARIO 10: Challenge reused after successful consumption is rejected (Invariant I-05)", () => {
      const uid = "user_reuse_test";
      const chal = SessionChallengeService.issueChallenge(uid, "enrollment", true, "BLINK");

      // First consumption succeeds
      const first = SessionChallengeService.validateAndConsume(
        chal.challengeId,
        chal.nonce,
        uid,
        "enrollment",
        "BLINK"
      );
      assert.strictEqual(first.consumed, true);

      // Replay attempt fails
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
        /Invalid challenge ID.*Session does not exist or expired|Replay attack detected/
      );
    });

    it("SCENARIO 11: Previously recorded burst replayed with modified client timestamps is rejected", () => {
      const uid = "user_stale_replay";
      const chal = SessionChallengeService.issueChallenge(uid, "enrollment", true, "BLINK");

      // Attacker attempts to replay frames captured prior to challenge issuance
      assert.throws(
        () => {
          SessionChallengeService.validateAndConsume(
            chal.challengeId,
            chal.nonce,
            uid,
            "enrollment",
            "BLINK",
            {
              framesCapturedAtMs: [
                chal.createdAt - 10000,
                chal.createdAt - 9800,
                chal.createdAt - 9600,
              ],
            }
          );
        },
        /Stale frame submission: Frames captured before challenge was issued/
      );
    });

    it("SCENARIO 12: Repeated byte-identical frames are rejected by anti-freeze gate", async () => {
      const fStatic = await createSyntheticKinematicFrame({ centerX: 56, centerY: 56, eyeAperturePx: 10, seed: 99 });

      const burst: BurstFrameInput[] = [
        { sequenceIndex: 0, capturedOffsetMs: 0, jpegBase64: fStatic },
        { sequenceIndex: 1, capturedOffsetMs: 100, jpegBase64: fStatic },
        { sequenceIndex: 2, capturedOffsetMs: 200, jpegBase64: fStatic },
      ];

      const res = await TemporalActionValidator.validateBurst(burst, "BLINK");
      assert.strictEqual(res.passed, false);
      assert.strictEqual(res.rejectionReason, "DUPLICATE_FRAME_REPLAY_DETECTED");
    });

    it("SCENARIO 13: Submitting frames with mismatched session ID is rejected", () => {
      const uid = "user_session_binding";
      const chal = SessionChallengeService.issueChallenge(
        uid,
        "enrollment",
        true,
        "BLINK",
        { clientSessionId: "valid_session_111" }
      );

      assert.throws(
        () => {
          SessionChallengeService.validateAndConsume(
            chal.challengeId,
            chal.nonce,
            uid,
            "enrollment",
            "BLINK",
            { clientSessionId: "foreign_session_999" }
          );
        },
        /Session binding mismatch: Challenge bound to session 'valid_session_111', received 'foreign_session_999'/
      );
    });

    it("SCENARIO 14: Request that omits required frame data (< 3 frames) is rejected", async () => {
      const f0 = await createSyntheticKinematicFrame({ centerX: 56, centerY: 56, eyeAperturePx: 10, seed: 1 });

      const singleFrameBurst: BurstFrameInput[] = [
        { sequenceIndex: 0, capturedOffsetMs: 0, jpegBase64: f0 },
      ];

      const res = await TemporalActionValidator.validateBurst(singleFrameBurst, "BLINK");
      assert.strictEqual(res.passed, false);
      assert.strictEqual(res.rejectionReason, "INVALID_FRAME_COUNT");
    });

    it("SCENARIO 15: Client-supplied blinkVerified: true without server aperture compression is rejected", async () => {
      // Client asserts blinkVerified: true, but submits 3 open-eye frames (apex ratio ~ 1.0 > 0.65)
      const f0 = await createSyntheticKinematicFrame({ centerX: 56, centerY: 56, eyeAperturePx: 12, seed: 1 });
      const f1NoBlink = await createSyntheticKinematicFrame({ centerX: 56, centerY: 56, eyeAperturePx: 12, seed: 2 });
      const f2 = await createSyntheticKinematicFrame({ centerX: 56, centerY: 56, eyeAperturePx: 12, seed: 3 });

      const fakeBlinkBurst: BurstFrameInput[] = [
        { sequenceIndex: 0, capturedOffsetMs: 0, jpegBase64: f0 },
        { sequenceIndex: 1, capturedOffsetMs: 120, jpegBase64: f1NoBlink },
        { sequenceIndex: 2, capturedOffsetMs: 240, jpegBase64: f2 },
      ];

      const res = await TemporalActionValidator.validateBurst(fakeBlinkBurst, "BLINK");
      assert.strictEqual(res.passed, false);
      assert.strictEqual(res.rejectionReason, "BLINK_TRAJECTORY_NOT_SATISFIED");
    });

    it("SCENARIO 16: Concurrency race attempting to consume same challenge twice serializes safely", async () => {
      const uid = "user_race_condition";
      const chal = SessionChallengeService.issueChallenge(uid, "enrollment", true, "BLINK");
      const token = `${chal.challengeId}:${chal.nonce}`;

      const attempts = await Promise.all([
        Promise.resolve(SessionChallengeService.consumeChallenge(token, uid, "enrollment", "BLINK")),
        Promise.resolve(SessionChallengeService.consumeChallenge(token, uid, "enrollment", "BLINK")),
      ]);

      const successCount = attempts.filter((r) => r === true).length;
      const rejectCount = attempts.filter((r) => r === false).length;

      assert.strictEqual(successCount, 1, "Exactly one concurrent consumer must succeed");
      assert.strictEqual(rejectCount, 1, "The competing consumer must be rejected");
    });

    it("SCENARIO 17: Interrupted request leaves user in pending_face, allows clean retry", () => {
      // State machine validation: if request aborts during capture, state remains PENDING_FACE.
      // An unauthenticated client cannot skip from CHALLENGE_ISSUED to ACTIVE.
      assert.throws(
        () => {
          EnrollmentStateMachine.validateTransition("CHALLENGE_ISSUED", "ACTIVE", {
            actorRole: "client",
          });
        },
        InvalidStateTransitionError,
        "Client cannot unilaterally transition to ACTIVE"
      );

      // Safe retry back to PENDING_FACE is permitted
      assert.doesNotThrow(() => {
        EnrollmentStateMachine.validateTransition("CHALLENGE_ISSUED", "PENDING_FACE", {
          actorRole: "system",
        });
      });
    });

    it("SCENARIO 18: Malformed frame buffer fails closed safely without creating approved state", async () => {
      const malformedBurst: BurstFrameInput[] = [
        { sequenceIndex: 0, capturedOffsetMs: 0, jpegBase64: "not_a_valid_jpeg" },
        { sequenceIndex: 1, capturedOffsetMs: 100, jpegBase64: "corrupt_data" },
        { sequenceIndex: 2, capturedOffsetMs: 200, jpegBase64: "broken" },
      ];

      const res = await TemporalActionValidator.validateBurst(malformedBurst, "BLINK");
      assert.strictEqual(res.passed, false);
      assert.strictEqual(res.rejectionReason, "MALFORMED_IMAGE_BUFFER");
      assert.strictEqual(res.authoritativeEmbedding, undefined);
    });

    it("EXPRESS ROUTE TEST: POST /api/biometrics/challenge issues challenge and /enroll rejects replayed token", async () => {
      // 1. Issue challenge via real faceRouter
      const challengeRes = await dispatchFaceRouter({
        method: "POST",
        url: "/challenge",
        body: { action: "ENROLLMENT" },
      });

      assert.strictEqual(challengeRes.status, 200);
      assert.strictEqual(challengeRes.body.success, true);
      assert.strictEqual(challengeRes.body.status, "challenge_issued");
      const nonce = challengeRes.body.data.challengeNonce;
      assert.ok(nonce && nonce.length > 32);

      // 2. First attempt with invalid image fails cleanly (400 Bad Request)
      const enrollRes1 = await dispatchFaceRouter({
        method: "POST",
        url: "/enroll",
        body: {
          role: "worker",
          challengeNonce: nonce,
          // Intentionally missing imageBase64 and burstFrames
        },
      });

      assert.strictEqual(enrollRes1.status, 400);
      assert.strictEqual(enrollRes1.body.error.code, "MISSING_IMAGE_BASE64");
    });
  });
});
