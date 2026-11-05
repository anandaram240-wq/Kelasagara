// backend/src/tests/v19_6_5_real_burst_integration.test.ts
//
// KELASAGARA BIOMATCH V19.6.5
// Real Flutter Camera Burst Integration, Server-Side Liveness Validation & Route Verification
// Standards: ISO/IEC 30107-3:2023, ISO/IEC 19794-5:2025, ISO/IEC 24745:2022

process.env.ALLOW_DEV_TOKEN = "true";

import { describe, it, beforeEach } from "node:test";
import assert from "node:assert";
import sharp from "sharp";
import { faceRouter } from "../routes/face_routes";
import { SessionChallengeService } from "../services/session_challenge_service";
import { TemporalActionValidator, BurstFrameInput } from "../services/temporal_action_validator";
import { cosineSimilarity } from "../services/biometric_matching";

// Helper: Synthesize compliant 112x112 grayscale face image with configurable eye aperture & seed
async function createSyntheticFaceBuffer(options: {
  ocularState: "open" | "closed";
  seed?: number;
  baseLuma?: number;
  comOffset?: { dx: number; dy: number };
}): Promise<Buffer> {
  const width = 112;
  const height = 112;
  const luma = options.baseLuma ?? 140;
  const seed = options.seed ?? 1;
  const buf = Buffer.alloc(width * height, luma);

  const dx = options.comOffset?.dx ?? 0;
  const dy = options.comOffset?.dy ?? 0;

  // Add subtle pseudo-random noise so distinct frames are not byte-identical
  for (let i = 0; i < width * height; i++) {
    buf[i] = Math.max(0, Math.min(255, luma + ((i * seed) % 7) - 3));
  }

  // Draw face contour boundary
  for (let y = 15; y < 97; y++) {
    for (let x = 15; x < 97; x++) {
      const cx = 56 + dx;
      const cy = 56 + dy;
      const dist = Math.sqrt((x - cx) ** 2 + (y - cy) ** 2);
      if (dist < 38) {
        buf[y * width + x] = Math.min(255, luma + 30);
      }
    }
  }

  // Draw mouth / lower feature below y=75
  for (let y = 78 + dy; y < 86 + dy; y++) {
    for (let x = 38 + dx; x < 74 + dx; x++) {
      if (y >= 0 && y < height && x >= 0 && x < width) {
        buf[y * width + x] = 35;
      }
    }
  }

  // Ocular band features across y in [35, 65]
  if (options.ocularState === "open") {
    // Open eyes: sharp horizontal eyelid boundaries producing high vertical Sobel energy
    for (let x = 25 + dx; x < 87 + dx; x++) {
      if (x >= 0 && x < width) {
        buf[(42 + dy) * width + x] = 20;  // Eyebrow
        buf[(48 + dy) * width + x] = 240; // Upper eyelid
        buf[(52 + dy) * width + x] = 30;  // Pupil / Iris
        buf[(56 + dy) * width + x] = 240; // Lower eyelid
      }
    }
  } else {
    // Closed eyes: eyelid crease compressed, smooth gradient
    for (let x = 25 + dx; x < 87 + dx; x++) {
      if (x >= 0 && x < width) {
        buf[(42 + dy) * width + x] = 25;  // Eyebrow
        buf[(50 + dy) * width + x] = 120; // Soft closed eyelid slit
      }
    }
  }

  return sharp(buf, { raw: { width, height, channels: 1 } })
    .jpeg({ quality: 85 })
    .toBuffer();
}

function dispatchFaceRouter(options: {
  method: string;
  url: string;
  uid?: string;
  headers?: Record<string, string>;
  body?: any;
}): Promise<{ status: number; body: any }> {
  return new Promise((resolve, reject) => {
    const callerUid = options.uid || "test_worker_v19_6_5";
    const req: any = {
      method: options.method,
      url: options.url,
      originalUrl: `/api/biometrics${options.url}`,
      user: { uid: callerUid },
      headers: {
        authorization: `Bearer dev-mock-token-${callerUid}`,
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

describe("KELASAGARA BIOMATCH V19.6.5: Real Burst Integration & Server Liveness Suite", () => {
  const uid = "worker_v19_6_5_sub1";

  it("STEP 1: POST /challenge issues valid active challenge with action=BLINK", async () => {
    const res = await dispatchFaceRouter({
      method: "POST",
      url: "/challenge",
      uid,
      body: { action: "ENROLLMENT" },
    });

    assert.strictEqual(res.status, 200);
    assert.strictEqual(res.body.success, true);
    assert.strictEqual(res.body.status, "challenge_issued");

    const data = res.body.data;
    assert.ok(data.challengeId && data.challengeId.startsWith("chal_"));
    assert.ok(data.challengeNonce && data.challengeNonce.length >= 32);
    assert.strictEqual(data.requiredAction, "BLINK");
    assert.strictEqual(data.ttlSeconds, 60);
    assert.ok(data.actionPromptEn.includes("blink"));
    assert.ok(data.actionPromptKn.length > 5);
  });

  it("STEP 2: TemporalActionValidator accepts genuine 3-frame blink trajectory [open, closed, open]", async () => {
    const now = Date.now();
    const f0 = await createSyntheticFaceBuffer({ ocularState: "open", seed: 10 });
    const f1 = await createSyntheticFaceBuffer({ ocularState: "closed", seed: 11 });
    const f2 = await createSyntheticFaceBuffer({ ocularState: "open", seed: 12 });

    const burst: BurstFrameInput[] = [
      { sequenceIndex: 0, capturedOffsetMs: now + 50, jpegBase64: f0.toString("base64") },
      { sequenceIndex: 1, capturedOffsetMs: now + 200, jpegBase64: f1.toString("base64") },
      { sequenceIndex: 2, capturedOffsetMs: now + 350, jpegBase64: f2.toString("base64") },
    ];

    const result = await TemporalActionValidator.validateBurst(burst, "BLINK");
    assert.strictEqual(result.passed, true, `Blink validation failed: ${result.rejectionReason}`);
    assert.strictEqual(result.status, "verified");
    assert.ok(result.authoritativeEmbedding !== undefined);
    assert.strictEqual(result.authoritativeEmbedding.length, 128);
    // Aperture apex ratio must be <= 0.65
    assert.ok(result.telemetry.actionApexMetric <= 0.65);
    // Identity similarity between anchor frames must be >= 0.80
    assert.ok(result.telemetry.anchorIdentitySimilarity02 >= 0.80);
  });

  it("STEP 3: TemporalActionValidator supports relative timestamps [0, 150, 300] ms", async () => {
    const f0 = await createSyntheticFaceBuffer({ ocularState: "open", seed: 20 });
    const f1 = await createSyntheticFaceBuffer({ ocularState: "closed", seed: 21 });
    const f2 = await createSyntheticFaceBuffer({ ocularState: "open", seed: 22 });

    const burst: BurstFrameInput[] = [
      { sequenceIndex: 0, capturedOffsetMs: 0, jpegBase64: f0.toString("base64") },
      { sequenceIndex: 1, capturedOffsetMs: 150, jpegBase64: f1.toString("base64") },
      { sequenceIndex: 2, capturedOffsetMs: 300, jpegBase64: f2.toString("base64") },
    ];

    const result = await TemporalActionValidator.validateBurst(burst, "BLINK");
    assert.strictEqual(result.passed, true);
    assert.deepStrictEqual(result.telemetry.interFrameIntervalsMs, [150, 150]);
  });

  it("STEP 4: Rejects out-of-order sequence index [0, 2, 1]", async () => {
    const f0 = await createSyntheticFaceBuffer({ ocularState: "open", seed: 30 });
    const f1 = await createSyntheticFaceBuffer({ ocularState: "closed", seed: 31 });
    const f2 = await createSyntheticFaceBuffer({ ocularState: "open", seed: 32 });

    const burst: BurstFrameInput[] = [
      { sequenceIndex: 0, capturedOffsetMs: 0, jpegBase64: f0.toString("base64") },
      { sequenceIndex: 2, capturedOffsetMs: 150, jpegBase64: f1.toString("base64") },
      { sequenceIndex: 1, capturedOffsetMs: 300, jpegBase64: f2.toString("base64") },
    ];

    const result = await TemporalActionValidator.validateBurst(burst, "BLINK");
    assert.strictEqual(result.passed, false);
    assert.strictEqual(result.rejectionReason, "OUT_OF_ORDER_FRAME_SEQUENCE");
  });

  it("STEP 5: Rejects anti-freeze duplicate byte-identical frames", async () => {
    const f0 = await createSyntheticFaceBuffer({ ocularState: "open", seed: 40 });
    const f1 = await createSyntheticFaceBuffer({ ocularState: "closed", seed: 41 });

    const burst: BurstFrameInput[] = [
      { sequenceIndex: 0, capturedOffsetMs: 0, jpegBase64: f0.toString("base64") },
      { sequenceIndex: 1, capturedOffsetMs: 150, jpegBase64: f1.toString("base64") },
      { sequenceIndex: 2, capturedOffsetMs: 300, jpegBase64: f0.toString("base64") }, // Frame 2 byte-identical to Frame 0
    ];

    const result = await TemporalActionValidator.validateBurst(burst, "BLINK");
    assert.strictEqual(result.passed, false);
    assert.strictEqual(result.rejectionReason, "DUPLICATE_FRAME_REPLAY_DETECTED");
  });

  it("STEP 6: Rejects timing violations (dt < 40ms or dt > 600ms)", async () => {
    const f0 = await createSyntheticFaceBuffer({ ocularState: "open", seed: 50 });
    const f1 = await createSyntheticFaceBuffer({ ocularState: "closed", seed: 51 });
    const f2 = await createSyntheticFaceBuffer({ ocularState: "open", seed: 52 });

    // dt01 = 20ms (too fast)
    const tooFast: BurstFrameInput[] = [
      { sequenceIndex: 0, capturedOffsetMs: 0, jpegBase64: f0.toString("base64") },
      { sequenceIndex: 1, capturedOffsetMs: 20, jpegBase64: f1.toString("base64") },
      { sequenceIndex: 2, capturedOffsetMs: 180, jpegBase64: f2.toString("base64") },
    ];
    const fastRes = await TemporalActionValidator.validateBurst(tooFast, "BLINK");
    assert.strictEqual(fastRes.passed, false);
    assert.strictEqual(fastRes.rejectionReason, "INTER_FRAME_TIMING_OUT_OF_BOUNDS");

    // dt12 = 800ms (too slow)
    const tooSlow: BurstFrameInput[] = [
      { sequenceIndex: 0, capturedOffsetMs: 0, jpegBase64: f0.toString("base64") },
      { sequenceIndex: 1, capturedOffsetMs: 150, jpegBase64: f1.toString("base64") },
      { sequenceIndex: 2, capturedOffsetMs: 950, jpegBase64: f2.toString("base64") },
    ];
    const slowRes = await TemporalActionValidator.validateBurst(tooSlow, "BLINK");
    assert.strictEqual(slowRes.passed, false);
    assert.strictEqual(slowRes.rejectionReason, "INTER_FRAME_TIMING_OUT_OF_BOUNDS");
  });

  it("STEP 7: Single-use challenge consumption is atomic and blocks replay", async () => {
    const chalUid = "atomic_consumer_test_user";
    const chal = SessionChallengeService.issueChallenge(chalUid, "enrollment", true, "BLINK");

    // First consumption succeeds
    const firstConsume = SessionChallengeService.consumeChallenge(
      chal.nonce,
      chalUid,
      "ENROLLMENT",
      "BLINK",
      { framesCapturedAtMs: [chal.createdAt + 100, chal.createdAt + 250, chal.createdAt + 400] }
    );
    assert.strictEqual(firstConsume, true);

    // Second consumption strictly blocked (already consumed)
    const secondConsume = SessionChallengeService.consumeChallenge(
      chal.nonce,
      chalUid,
      "ENROLLMENT",
      "BLINK",
      { framesCapturedAtMs: [chal.createdAt + 100, chal.createdAt + 250, chal.createdAt + 400] }
    );
    assert.strictEqual(secondConsume, false, "Replayed challenge must be rejected");
  });

  it("STEP 8: Two concurrent requests attempting to consume the same challenge race safely", async () => {
    const raceUid = "concurrency_race_user";
    const chal = SessionChallengeService.issueChallenge(raceUid, "enrollment", true, "BLINK");

    const [res1, res2] = await Promise.all([
      Promise.resolve(SessionChallengeService.consumeChallenge(chal.nonce, raceUid, "ENROLLMENT", "BLINK")),
      Promise.resolve(SessionChallengeService.consumeChallenge(chal.nonce, raceUid, "ENROLLMENT", "BLINK")),
    ]);

    // Exactly one winner, one loser
    const successes = [res1, res2].filter((v) => v === true).length;
    const failures = [res1, res2].filter((v) => v === false).length;
    assert.strictEqual(successes, 1, "Exactly one concurrent caller must consume challenge");
    assert.strictEqual(failures, 1, "Competing caller must be rejected");
  });

  it("STEP 9: Cross-account challenge theft is strictly blocked (Invariant I-04)", async () => {
    const aliceUid = "user_alice_v19_6_5";
    const malloryUid = "user_mallory_v19_6_5";
    const chal = SessionChallengeService.issueChallenge(aliceUid, "enrollment", true, "BLINK");

    // Mallory tries to use Alice's challenge
    const theftAttempt = SessionChallengeService.consumeChallenge(
      chal.nonce,
      malloryUid,
      "ENROLLMENT",
      "BLINK"
    );
    assert.strictEqual(theftAttempt, false, "Cross-account challenge consumption must be rejected");
  });

  it("STEP 10: Stale frame submission (timestamps before challenge issuance) is rejected", async () => {
    const freshUid = "fresh_submission_user";
    const chal = SessionChallengeService.issueChallenge(freshUid, "enrollment", true, "BLINK");

    assert.throws(
      () => {
        SessionChallengeService.validateAndConsume(
          chal.challengeId,
          chal.nonce,
          freshUid,
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
      /Stale frame submission/,
      "Must reject timestamps captured prior to challenge issuance"
    );
  });
});
