// backend/src/tests/server_landmark_liveness.test.ts
import assert from "assert";
import { describe, it } from "node:test";
import { ServerLandmarkExtractor } from "../services/server_landmark_extractor";
import { PresentationAttackDefenseService } from "../services/presentation_attack_defense";

describe("TICKET E-03: SERVER-SIDE LANDMARKS & ZERO CLIENT METADATA TRUST", () => {
  // ── TEST 1: Server-Side Landmark Extraction from Pixel Buffer ─────────────
  it("should extract valid facial landmarks directly from raw pixel buffer", async () => {
    // Synthetic 112x112x3 buffer with non-zero luminance
    const buf = Buffer.alloc(112 * 112 * 3);
    for (let i = 0; i < buf.length; i++) {
      buf[i] = (i % 256);
    }

    const landmarks = await ServerLandmarkExtractor.extractFromBuffer(buf, Date.now());
    assert.ok(landmarks.noseTip, "Landmarks must include noseTip");
    assert.ok(landmarks.leftEyeUpper, "Landmarks must include leftEyeUpper");
    assert.ok(landmarks.rightEyeUpper, "Landmarks must include rightEyeUpper");
    assert.ok(landmarks.leftMouthCorner, "Landmarks must include leftMouthCorner");
    assert.ok(typeof landmarks.yawDegrees === "number", "Yaw degrees must be calculated");
  });

  // ── TEST 2: Invariant I-03 / E-03: Fabricated Client Metadata Ignored ──────
  it("should ignore fabricated client coordinates when image burst has zero motion (Invariant I-03, I-30)", () => {
    PresentationAttackDefenseService.reset();
    const chal = PresentationAttackDefenseService.issueChallenge("victim_spoof_01");

    // Attacker crafts fabricated frames with large simulated head turn and eye blink
    const fabricatedClientFrames = [
      {
        timestampMs: 1000,
        noseTip: { x: 50, y: 50 },
        leftEyeUpper: { x: 30, y: 40 },
        leftEyeLower: { x: 30, y: 46 }, // open
        yawDegrees: 0,
      },
      {
        timestampMs: 1200,
        noseTip: { x: 80, y: 50 }, // Massive fabricated movement
        leftEyeUpper: { x: 30, y: 43 },
        leftEyeLower: { x: 30, y: 44 }, // closed
        yawDegrees: 25,
      },
      {
        timestampMs: 1400,
        noseTip: { x: 100, y: 50 },
        leftEyeUpper: { x: 30, y: 40 },
        leftEyeLower: { x: 30, y: 46 },
        yawDegrees: 45,
      },
    ];

    // But the attacker provides static identical photo frames in the actual pixel burst
    const staticPhotoBuf = Buffer.alloc(112 * 112 * 3, 140);
    const staticPhotoBase64 = staticPhotoBuf.toString("base64");
    const frameImagesBase64 = [staticPhotoBase64, staticPhotoBase64, staticPhotoBase64];

    // Submit both fabricated frames and static images
    const result = PresentationAttackDefenseService.verifyChallenge({
      challengeId: chal.challengeId,
      uid: "victim_spoof_01",
      frames: fabricatedClientFrames, // Fabricated client claims
      frameImagesBase64, // Actual static pixels
    });

    // The server MUST ignore fabricated client frames and detect the static photo!
    assert.strictEqual(
      result.passed,
      false,
      "Server must reject submission when underlying images have zero motion"
    );
    assert.strictEqual(
      result.attackTypeDetected,
      "STATIC_2D_PHOTO",
      "Server pixel extraction must detect STATIC_2D_PHOTO despite client claims"
    );
    assert.match(
      result.failureReason || "",
      /Zero physical motion detected|STATIC_2D_PHOTO/i
    );
  });

  // ── TEST 3: Genuine Pixel Motion Burst Processed Server-Side ──────────────
  it("should process genuine image burst with distinct server-detected moments", () => {
    PresentationAttackDefenseService.reset();
    const chal = PresentationAttackDefenseService.issueChallenge("legit_user_02");

    // Generate 3 distinct frames with shifting luminance centers (simulating physical movement)
    const frame1 = Buffer.alloc(112 * 112 * 3, 50);
    frame1.fill(220, 0, 10000); // Bright spot top-left

    const frame2 = Buffer.alloc(112 * 112 * 3, 50);
    frame2.fill(220, 10000, 20000); // Bright spot middle

    const frame3 = Buffer.alloc(112 * 112 * 3, 50);
    frame3.fill(220, 20000, 30000); // Bright spot bottom-right

    const frameImagesBase64 = [
      frame1.toString("base64"),
      frame2.toString("base64"),
      frame3.toString("base64"),
    ];

    const result = PresentationAttackDefenseService.verifyChallenge({
      challengeId: chal.challengeId,
      uid: "legit_user_02",
      frameImagesBase64,
    });

    // It should NOT be flagged as static 2D photo because server detected genuine motion!
    assert.notStrictEqual(
      result.attackTypeDetected,
      "STATIC_2D_PHOTO",
      "Dynamic pixel burst must not be flagged as static photo"
    );
  });
});
