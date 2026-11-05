// backend/src/tests/v19_6_4_replay_and_liveness_audit.test.ts
import { describe, it } from "node:test";
import assert from "node:assert";
import sharp from "sharp";
import { TemporalActionValidator } from "../services/temporal_action_validator";
import { SessionChallengeService } from "../services/session_challenge_service";
import { runFaceInference } from "../services/face_inference";
import { cosineSimilarity, evaluateVerification } from "../services/biometric_matching";

// Helper: Synthesize 112x112 grayscale face image with configurable features & non-identical noise
async function createSyntheticFaceBuffer(options?: {
  ocularGradient?: "open" | "closed" | "blurred" | "with_glasses";
  comOffset?: { dx: number; dy: number };
  luma?: number;
  seed?: number;
}): Promise<Buffer> {
  const width = 112;
  const height = 112;
  const luma = options?.luma ?? 128;
  const seed = options?.seed ?? 1;
  const img = Buffer.alloc(width * height, luma);

  const dx = options?.comOffset?.dx ?? 0;
  const dy = options?.comOffset?.dy ?? 0;

  // Add subtle sensor noise based on seed so distinct frames are not byte-identical
  for (let i = 0; i < width * height; i++) {
    img[i] = Math.max(0, Math.min(255, luma + ((i * seed) % 5) - 2));
  }

  // Draw face contour (high contrast boundary)
  for (let y = 15; y < 97; y++) {
    for (let x = 15; x < 97; x++) {
      const cx = 56 + dx;
      const cy = 56 + dy;
      const dist = Math.sqrt((x - cx) ** 2 + (y - cy) ** 2);
      if (dist < 40) {
        img[y * width + x] = Math.min(255, luma + 30);
      }
    }
  }

  // Draw mouth / lower face feature below y=70
  for (let y = 78 + dy; y < 86 + dy; y++) {
    for (let x = 36 + dx; x < 76 + dx; x++) {
      if (y >= 0 && y < height && x >= 0 && x < width) {
        img[y * width + x] = 40;
      }
    }
  }

  // Ocular band features (y in [35, 65])
  if (options?.ocularGradient === "open") {
    // Open eyes: multiple sharp horizontal edges
    for (let x = 25 + dx; x < 87 + dx; x++) {
      if (x >= 0 && x < width) {
        img[(42 + dy) * width + x] = 20; // Eyebrow
        img[(48 + dy) * width + x] = 240; // Upper eyelid
        img[(52 + dy) * width + x] = 30; // Pupil / Iris
        img[(56 + dy) * width + x] = 240; // Lower eyelid
      }
    }
  } else if (options?.ocularGradient === "closed") {
    // Closed eyes: single subtle crease
    for (let x = 25 + dx; x < 87 + dx; x++) {
      if (x >= 0 && x < width) {
        img[(42 + dy) * width + x] = 40; // Eyebrow remains
        img[(52 + dy) * width + x] = 90; // Subtle closed crease
      }
    }
  } else if (options?.ocularGradient === "blurred") {
    // Motion blur: diffuse transition, eyes open but blurred
    for (let x = 25 + dx; x < 87 + dx; x++) {
      if (x >= 0 && x < width) {
        img[(42 + dy) * width + x] = 80;
        img[(48 + dy) * width + x] = 130;
        img[(52 + dy) * width + x] = 110;
        img[(56 + dy) * width + x] = 130;
      }
    }
  } else if (options?.ocularGradient === "with_glasses") {
    // Heavy glasses frame: thick black horizontal rims dominating ocular band
    for (let x = 20 + dx; x < 92 + dx; x++) {
      if (x >= 0 && x < width) {
        img[(38 + dy) * width + x] = 10; // Upper rim
        img[(40 + dy) * width + x] = 10;
        img[(58 + dy) * width + x] = 10; // Lower rim
        img[(60 + dy) * width + x] = 10;
      }
    }
  }

  return sharp(img, { raw: { width, height, channels: 1 } })
    .jpeg({ quality: 85 })
    .toBuffer();
}

describe("KELASAGARA BIOMATCH V19.6.4: Deep Scientific Liveness & Replay Audit", () => {
  // =========================================================================
  // SECTION 1: SCIENTIFIC AUDIT OF THE SOBEL APERTURE BLINK VALIDATOR
  // =========================================================================
  describe("Phase 2: Scientific Evaluation of Sobel Aperture Proxy", () => {
    it("DEMONSTRATES DEFECT: Camera motion blur mimics a genuine blink without eye closure", async () => {
      // Frame 0: Sharp open eye
      const f0 = await createSyntheticFaceBuffer({ ocularGradient: "open", seed: 1 });
      // Frame 1: Eyes still open, but camera moved / blurred during capture
      const f1 = await createSyntheticFaceBuffer({ ocularGradient: "blurred", seed: 2 });
      // Frame 2: Sharp open eye
      const f2 = await createSyntheticFaceBuffer({ ocularGradient: "open", seed: 3 });

      const burst = [
        { sequenceIndex: 0, capturedOffsetMs: 0, jpegBase64: f0.toString("base64") },
        { sequenceIndex: 1, capturedOffsetMs: 150, jpegBase64: f1.toString("base64") },
        { sequenceIndex: 2, capturedOffsetMs: 300, jpegBase64: f2.toString("base64") },
      ];

      // Execute validator
      const result = await TemporalActionValidator.validateBurst(burst, "BLINK");

      // SCIENTIFIC FINDING: The validator declares a blink occurred because high-frequency
      // edge energy dropped (motion blur), even though the eyes never closed!
      assert.strictEqual(
        result.passed,
        true,
        "VULNERABILITY: Motion blur reduces Sobel gradient energy, falsely passing blink validation"
      );
      assert.ok(
        result.telemetry.actionApexMetric <= 0.65,
        `Apex metric (${result.telemetry.actionApexMetric.toFixed(3)}) fell below 0.65 due to blur alone`
      );
    });

    it("DEMONSTRATES DEFECT: Eyeglasses with dark frames can prevent bona fide blink detection", async () => {
      // In a glasses-wearing subject, eyeglass frames produce dominant horizontal bars
      // across y in [35, 65] that do not compress when eyelids close.
      const f0 = await createSyntheticFaceBuffer({ ocularGradient: "with_glasses", seed: 1 });
      const f1 = await createSyntheticFaceBuffer({ ocularGradient: "with_glasses", seed: 2 });
      const f2 = await createSyntheticFaceBuffer({ ocularGradient: "with_glasses", seed: 3 });

      const burst = [
        { sequenceIndex: 0, capturedOffsetMs: 0, jpegBase64: f0.toString("base64") },
        { sequenceIndex: 1, capturedOffsetMs: 150, jpegBase64: f1.toString("base64") },
        { sequenceIndex: 2, capturedOffsetMs: 300, jpegBase64: f2.toString("base64") },
      ];

      const result = await TemporalActionValidator.validateBurst(burst, "BLINK");

      // The dark frames keep edge energy high throughout, so ApexRatio remains ~1.00
      assert.strictEqual(
        result.passed,
        false,
        "LIMITATION: Fixed ocular band Sobel metric cannot isolate eyelids when glasses frames dominate"
      );
      assert.strictEqual(result.rejectionReason, "BLINK_TRAJECTORY_NOT_SATISFIED");
    });
  });

  // =========================================================================
  // SECTION 2: SCIENTIFIC AUDIT OF 2D GRADIENT COM HEAD POSE VALIDATOR
  // =========================================================================
  describe("Phase 3: Scientific Evaluation of 2D Gradient COM", () => {
    it("DEMONSTRATES DEFECT: Camera translation (phone panning) falsely mimics TURN_HEAD_LEFT", async () => {
      // Static face, but the phone was panned 6 pixels to the left in Frame 1
      const f0 = await createSyntheticFaceBuffer({ ocularGradient: "open", comOffset: { dx: 0, dy: 0 }, seed: 1 });
      const f1 = await createSyntheticFaceBuffer({ ocularGradient: "open", comOffset: { dx: -7, dy: 0 }, seed: 2 });
      const f2 = await createSyntheticFaceBuffer({ ocularGradient: "open", comOffset: { dx: 0, dy: 0 }, seed: 3 });

      const burst = [
        { sequenceIndex: 0, capturedOffsetMs: 0, jpegBase64: f0.toString("base64") },
        { sequenceIndex: 1, capturedOffsetMs: 150, jpegBase64: f1.toString("base64") },
        { sequenceIndex: 2, capturedOffsetMs: 300, jpegBase64: f2.toString("base64") },
      ];

      const result = await TemporalActionValidator.validateBurst(burst, "TURN_HEAD_LEFT");

      // SCIENTIFIC FINDING: 2D gradient COM cannot distinguish between 3D head yaw rotation
      // and lateral 2D camera panning!
      assert.strictEqual(
        result.passed,
        true,
        "VULNERABILITY: Lateral camera translation triggers TURN_HEAD_LEFT without 3D head yaw rotation"
      );
    });

    it("DEMONSTRATES DEFECT: Hand tremor pitch translation falsely mimics NOD_HEAD", async () => {
      // Static face, phone tilted down 6 pixels in Frame 1
      const f0 = await createSyntheticFaceBuffer({ ocularGradient: "open", comOffset: { dx: 0, dy: 0 }, seed: 1 });
      const f1 = await createSyntheticFaceBuffer({ ocularGradient: "open", comOffset: { dx: 0, dy: 7 }, seed: 2 });
      const f2 = await createSyntheticFaceBuffer({ ocularGradient: "open", comOffset: { dx: 0, dy: 0 }, seed: 3 });

      const burst = [
        { sequenceIndex: 0, capturedOffsetMs: 0, jpegBase64: f0.toString("base64") },
        { sequenceIndex: 1, capturedOffsetMs: 150, jpegBase64: f1.toString("base64") },
        { sequenceIndex: 2, capturedOffsetMs: 300, jpegBase64: f2.toString("base64") },
      ];

      const result = await TemporalActionValidator.validateBurst(burst, "NOD_HEAD");

      assert.strictEqual(
        result.passed,
        true,
        "VULNERABILITY: Vertical camera translation triggers NOD_HEAD without true pitch rotation"
      );
    });
  });

  // =========================================================================
  // SECTION 3: REALISTIC REPLAY ATTACK SUITE (10 SCENARIOS)
  // =========================================================================
  describe("Phase 4: Realistic Replay Attack Scenarios", () => {
    it("REPLAY SCENARIO R1: Prerecorded video of same person blinking replayed with fresh timestamps", async () => {
      const uid = "user_victim_r1";
      const chal = SessionChallengeService.issueChallenge(uid, "enrollment", true, "BLINK");

      // Attacker recorded a genuine blink yesterday.
      // Now, attacker submits the prerecorded frames, but overwrites client timestamps to be NOW:
      const now = Date.now();
      const f0 = await createSyntheticFaceBuffer({ ocularGradient: "open", seed: 1 });
      const f1 = await createSyntheticFaceBuffer({ ocularGradient: "closed", seed: 2 });
      const f2 = await createSyntheticFaceBuffer({ ocularGradient: "open", seed: 3 });

      const burst = [
        { sequenceIndex: 0, capturedOffsetMs: now + 50, jpegBase64: f0.toString("base64") },
        { sequenceIndex: 1, capturedOffsetMs: now + 200, jpegBase64: f1.toString("base64") },
        { sequenceIndex: 2, capturedOffsetMs: now + 350, jpegBase64: f2.toString("base64") },
      ];

      // Validate session challenge
      const chalRecord = SessionChallengeService.validateAndConsume(
        chal.challengeId,
        chal.nonce,
        uid,
        "enrollment",
        "BLINK",
        { framesCapturedAtMs: burst.map((b) => b.capturedOffsetMs) }
      );
      assert.ok(chalRecord, "Challenge consumed because timestamps fall after issuance");

      // Validate burst motion
      const livenessResult = await TemporalActionValidator.validateBurst(burst, "BLINK");

      // CRITICAL SCIENTIFIC PROOF:
      // The software pipeline ACCEPTS the prerecorded video because metadata timestamps
      // and aperture compression cannot prove physical camera photon origin!
      assert.strictEqual(
        livenessResult.passed,
        true,
        "VULNERABILITY CONFIRMED: Prerecorded video replay with synthesized timestamps is ACCEPTED by software validators"
      );
    });

    it("REPLAY SCENARIO R2: Prerecorded head turn replayed with fresh timestamps", async () => {
      const uid = "user_victim_r2";
      const chal = SessionChallengeService.issueChallenge(uid, "enrollment", true, "TURN_HEAD_LEFT", {
        enableExperimentalActions: true,
      });

      const now = Date.now();
      const f0 = await createSyntheticFaceBuffer({ comOffset: { dx: 0, dy: 0 }, seed: 1 });
      const f1 = await createSyntheticFaceBuffer({ comOffset: { dx: -7, dy: 0 }, seed: 2 });
      const f2 = await createSyntheticFaceBuffer({ comOffset: { dx: 0, dy: 0 }, seed: 3 });

      const burst = [
        { sequenceIndex: 0, capturedOffsetMs: now + 50, jpegBase64: f0.toString("base64") },
        { sequenceIndex: 1, capturedOffsetMs: now + 200, jpegBase64: f1.toString("base64") },
        { sequenceIndex: 2, capturedOffsetMs: now + 350, jpegBase64: f2.toString("base64") },
      ];

      const chalRecord = SessionChallengeService.validateAndConsume(
        chal.challengeId,
        chal.nonce,
        uid,
        "enrollment",
        "TURN_HEAD_LEFT",
        { framesCapturedAtMs: burst.map((b) => b.capturedOffsetMs) }
      );
      assert.ok(chalRecord);

      const liveness = await TemporalActionValidator.validateBurst(burst, "TURN_HEAD_LEFT");
      assert.strictEqual(
        liveness.passed,
        true,
        "VULNERABILITY CONFIRMED: Prerecorded head movement replay with fresh timestamps is ACCEPTED"
      );
    });

    it("REPLAY SCENARIO R3: Resampled / reordered frames from earlier capture", async () => {
      const f0 = await createSyntheticFaceBuffer({ ocularGradient: "open", seed: 1 });
      const f1 = await createSyntheticFaceBuffer({ ocularGradient: "closed", seed: 2 });
      const f2 = await createSyntheticFaceBuffer({ ocularGradient: "open", seed: 3 });

      // Attacker scrambled frames: [closed, open, open]
      const scrambledBurst = [
        { sequenceIndex: 0, capturedOffsetMs: 100, jpegBase64: f1.toString("base64") },
        { sequenceIndex: 1, capturedOffsetMs: 250, jpegBase64: f0.toString("base64") },
        { sequenceIndex: 2, capturedOffsetMs: 400, jpegBase64: f2.toString("base64") },
      ];

      const res = await TemporalActionValidator.validateBurst(scrambledBurst, "BLINK");
      assert.strictEqual(res.passed, false, "Scrambled apex frame fails aperture ratio");
      assert.strictEqual(res.rejectionReason, "BLINK_TRAJECTORY_NOT_SATISFIED");
    });

    it("REPLAY SCENARIO R4: Previously recorded frames assigned fresh sequence indices [0, 1, 2]", async () => {
      // Re-indexing frames does not bypass trajectory check if sequence is not a true open-closed-open
      const f0 = await createSyntheticFaceBuffer({ ocularGradient: "open", seed: 1 });
      const f1 = await createSyntheticFaceBuffer({ ocularGradient: "open", seed: 2 });
      const f2 = await createSyntheticFaceBuffer({ ocularGradient: "open", seed: 3 });

      const burst = [
        { sequenceIndex: 0, capturedOffsetMs: 100, jpegBase64: f0.toString("base64") },
        { sequenceIndex: 1, capturedOffsetMs: 250, jpegBase64: f1.toString("base64") },
        { sequenceIndex: 2, capturedOffsetMs: 400, jpegBase64: f2.toString("base64") },
      ];

      const res = await TemporalActionValidator.validateBurst(burst, "BLINK");
      assert.strictEqual(res.passed, false, "Static burst fails regardless of fresh indices");
    });

    it("REPLAY SCENARIO R5: Modified timestamps appearing after challenge issuance", async () => {
      const uid = "user_ts_mod";
      const chal = SessionChallengeService.issueChallenge(uid, "enrollment", true, "BLINK");

      // Synthesized timestamps strictly > createdAt:
      const framesCapturedAtMs = [chal.createdAt + 100, chal.createdAt + 250, chal.createdAt + 400];
      const valid = SessionChallengeService.consumeChallenge(
        chal.nonce,
        uid,
        "ENROLLMENT",
        "BLINK",
        { framesCapturedAtMs }
      );
      assert.strictEqual(valid, true, "Software timestamp check cannot detect falsified device timestamps");
    });

    it("REPLAY SCENARIO R6: Near-identical frames with 1-pixel perturbation (anti-freeze bypass test)", async () => {
      const f0 = await createSyntheticFaceBuffer({ ocularGradient: "open", seed: 1 });
      // Modify 1 pixel to bypass exact buffer.equals() check
      const rawBuf = Buffer.from(f0);
      rawBuf[rawBuf.length - 10] ^= 0x01; // flip 1 bit in JPEG payload

      const burst = [
        { sequenceIndex: 0, capturedOffsetMs: 0, jpegBase64: f0.toString("base64") },
        { sequenceIndex: 1, capturedOffsetMs: 150, jpegBase64: rawBuf.toString("base64") },
        { sequenceIndex: 2, capturedOffsetMs: 300, jpegBase64: f0.toString("base64") },
      ];

      const res = await TemporalActionValidator.validateBurst(burst, "BLINK");
      // Even if buffer byte equality is bypassed, the aperture ratio or cosine sim check catches it
      assert.strictEqual(res.passed, false);
    });

    it("REPLAY SCENARIO R7: Interpolated frames providing no real capture evidence", async () => {
      const f0 = await createSyntheticFaceBuffer({ ocularGradient: "open", seed: 1 });
      const f1 = await createSyntheticFaceBuffer({ ocularGradient: "open", seed: 2 });
      const f2 = await createSyntheticFaceBuffer({ ocularGradient: "open", seed: 3 });

      const burst = [
        { sequenceIndex: 0, capturedOffsetMs: 0, jpegBase64: f0.toString("base64") },
        { sequenceIndex: 1, capturedOffsetMs: 150, jpegBase64: f1.toString("base64") },
        { sequenceIndex: 2, capturedOffsetMs: 300, jpegBase64: f2.toString("base64") },
      ];

      const res = await TemporalActionValidator.validateBurst(burst, "BLINK");
      assert.strictEqual(res.passed, false, "Interpolated static frames fail aperture ratio");
    });

    it("REPLAY SCENARIO R8: Valid challenge paired with frames from different session", async () => {
      const uid = "user_cross_sess";
      const chal = SessionChallengeService.issueChallenge(uid, "enrollment", true, "BLINK", {
        clientSessionId: "session_original",
      });

      assert.throws(
        () => {
          SessionChallengeService.validateAndConsume(
            chal.challengeId,
            chal.nonce,
            uid,
            "enrollment",
            "BLINK",
            { clientSessionId: "session_stolen" }
          );
        },
        /Session binding mismatch/
      );
    });

    it("REPLAY SCENARIO R9: Challenge consumed before submission", async () => {
      const uid = "user_consumed_r9";
      const chal = SessionChallengeService.issueChallenge(uid, "enrollment", true, "BLINK");

      // First consumption
      SessionChallengeService.validateAndConsume(chal.challengeId, chal.nonce, uid, "enrollment", "BLINK");

      // Attempt second consumption throws because session was deleted / consumed
      assert.throws(
        () => {
          SessionChallengeService.validateAndConsume(chal.challengeId, chal.nonce, uid, "enrollment", "BLINK");
        },
        /does not exist or expired/
      );
    });

    it("REPLAY SCENARIO R10: Repeated submission after successful completion", async () => {
      const uid = "user_repeated_r10";
      const chal = SessionChallengeService.issueChallenge(uid, "enrollment", true, "BLINK");

      SessionChallengeService.validateAndConsume(chal.challengeId, chal.nonce, uid, "enrollment", "BLINK");

      assert.throws(
        () => {
          SessionChallengeService.validateAndConsume(chal.challengeId, chal.nonce, uid, "enrollment", "BLINK");
        },
        /does not exist or expired/
      );
    });
  });

  // =========================================================================
  // SECTION 4: SFACE THRESHOLD SEMANTICS AUDIT
  // =========================================================================
  describe("Phase 6: SFace Threshold Semantics Audit", () => {
    it("PROVES SEMANTICS: Code implements Cosine Similarity (Higher = More Similar), NOT Cosine Distance", () => {
      const vA = new Float32Array([1, 0, 0]);
      const vSame = new Float32Array([1, 0, 0]);
      const vOrth = new Float32Array([0, 1, 0]);
      const vOpp = new Float32Array([-1, 0, 0]);

      const simIdentical = cosineSimilarity(vA, vSame);
      const simOrthogonal = cosineSimilarity(vA, vOrth);
      const simOpposite = cosineSimilarity(vA, vOpp);

      assert.strictEqual(simIdentical, 1.0, "Identical vectors yield similarity = 1.0");
      assert.strictEqual(simOrthogonal, 0.0, "Orthogonal vectors yield similarity = 0.0");
      assert.strictEqual(simOpposite, -1.0, "Opposite vectors yield similarity = -1.0");

      // Evaluate verification decision
      const threshold = 0.363;
      const genuineMatch = evaluateVerification(0.50, threshold);
      const impostorReject = evaluateVerification(0.20, threshold);

      assert.strictEqual(genuineMatch.isMatch, true, "Cosine similarity 0.50 >= 0.363 is ACCEPTED as match");
      assert.strictEqual(impostorReject.isMatch, false, "Cosine similarity 0.20 < 0.363 is REJECTED as impostor");

      // SCIENTIFIC CONCLUSION: Prior reports labeling 0.363 as 'cosine distance' were an
      // egregious documentation error. In cosine distance (1 - sim), 0.50 would be distance 0.50
      // which would be > 0.363 (rejected!). The code operates strictly on COSINE SIMILARITY.
    });
  });

  // =========================================================================
  // SECTION 5: REPRODUCIBLE LOCAL LATENCY BENCHMARK (50 ITERATIONS)
  // =========================================================================
  describe("Phase 8: Reproducible Latency Profiling", () => {
    it("BENCHMARK: Measures component latencies across 50 iterations with percentiles", async () => {
      const iterations = 50;
      const f0 = await createSyntheticFaceBuffer({ ocularGradient: "open", seed: 1 });
      const f1 = await createSyntheticFaceBuffer({ ocularGradient: "closed", seed: 2 });
      const f2 = await createSyntheticFaceBuffer({ ocularGradient: "open", seed: 3 });

      const burst = [
        { sequenceIndex: 0, capturedOffsetMs: 0, jpegBase64: f0.toString("base64") },
        { sequenceIndex: 1, capturedOffsetMs: 150, jpegBase64: f1.toString("base64") },
        { sequenceIndex: 2, capturedOffsetMs: 300, jpegBase64: f2.toString("base64") },
      ];

      const validatorLatencies: number[] = [];
      const inferenceLatencies: number[] = [];

      // Warmup
      await TemporalActionValidator.validateBurst(burst, "BLINK");
      await runFaceInference(f0);

      // Measure iterations
      for (let i = 0; i < iterations; i++) {
        const t0 = performance.now();
        await TemporalActionValidator.validateBurst(burst, "BLINK");
        validatorLatencies.push(performance.now() - t0);

        const t1 = performance.now();
        await runFaceInference(f0);
        inferenceLatencies.push(performance.now() - t1);
      }

      validatorLatencies.sort((a, b) => a - b);
      inferenceLatencies.sort((a, b) => a - b);

      const mean = (arr: number[]) => arr.reduce((s, v) => s + v, 0) / arr.length;
      const p50 = (arr: number[]) => arr[Math.floor(arr.length * 0.5)];
      const p95 = (arr: number[]) => arr[Math.floor(arr.length * 0.95)];

      console.log(`\n======================================================`);
      console.log(`[V19.6.4 LATENCY BENCHMARK EVIDENCE] (Iterations: ${iterations})`);
      console.log(`======================================================`);
      console.log(
        `[TemporalActionValidator (Sharp decode + Sobel)]\n  Mean: ${mean(validatorLatencies).toFixed(2)} ms | p50: ${p50(validatorLatencies).toFixed(2)} ms | p95: ${p95(validatorLatencies).toFixed(2)} ms`
      );
      console.log(
        `[FaceInference (SFace ONNX Model Forward Pass)]\n  Mean: ${mean(inferenceLatencies).toFixed(2)} ms | p50: ${p50(inferenceLatencies).toFixed(2)} ms | p95: ${p95(inferenceLatencies).toFixed(2)} ms`
      );
      console.log(`======================================================\n`);

      assert.ok(validatorLatencies.length === iterations);
      assert.ok(inferenceLatencies.length === iterations);
    });
  });
});
