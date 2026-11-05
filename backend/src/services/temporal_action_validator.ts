// backend/src/services/temporal_action_validator.ts
import sharp from "sharp";
import { runFaceInference } from "./face_inference";
import { cosineSimilarity, l2Normalize } from "./biometric_matching";
import { ActiveChallengeAction } from "./session_challenge_service";

export interface BurstFrameInput {
  sequenceIndex: number;
  capturedOffsetMs: number;
  jpegBase64: string;
}

export interface TemporalValidationResult {
  passed: boolean;
  status: "verified" | "rejected";
  rejectionReason?:
    | "INVALID_FRAME_COUNT"
    | "OUT_OF_ORDER_FRAME_SEQUENCE"
    | "INTER_FRAME_TIMING_OUT_OF_BOUNDS"
    | "MALFORMED_IMAGE_BUFFER"
    | "DUPLICATE_FRAME_REPLAY_DETECTED"
    | "PHOTOMETRIC_LUMA_STEP_ANOMALY"
    | "CROSS_FRAME_IDENTITY_SPLICE_DETECTED"
    | "BLINK_TRAJECTORY_NOT_SATISFIED"
    | "HEAD_MOVEMENT_TRAJECTORY_NOT_SATISFIED"
    | "HEAD_TURN_LEFT_TRAJECTORY_NOT_SATISFIED"
    | "HEAD_TURN_RIGHT_TRAJECTORY_NOT_SATISFIED"
    | "NOD_HEAD_TRAJECTORY_NOT_SATISFIED"
    | "INSUFFICIENT_TEXTURE_SHARPNESS";
  telemetry: {
    lumaValues: [number, number, number];
    lumaDelta02: number;
    anchorIdentitySimilarity02: number;
    actionApexMetric: number;
    interFrameIntervalsMs: number[];
    kinematicDisplacement?: { deltaX: number; deltaY: number };
  };
  authoritativeEmbedding?: Float32Array;
}

export class TemporalActionValidator {
  private static readonly MIN_INTER_FRAME_MS = 40;
  private static readonly MAX_INTER_FRAME_MS = 600;
  private static readonly MAX_LUMA_RELATIVE_DELTA = 0.18; // 18% max photometric shift
  private static readonly MIN_ANCHOR_SFACE_CONTINUITY = 0.80; // SFace sim(u0, u2) >= 0.80
  private static readonly MAX_BLINK_APEX_RATIO = 0.65; // Apex aperture <= 0.65 * open baseline
  private static readonly MIN_HEAD_TURN_DELTA_X = 0.035; // 3.5% horizontal normalized shift
  private static readonly MIN_HEAD_NOD_DELTA_Y = 0.035; // 3.5% vertical normalized pitch shift
  private static readonly MAX_RECOVERY_RESIDUAL = 0.030; // Return-to-center recovery threshold

  /**
   * Validates a 3-frame temporal burst against server challenge invariants.
   * Runs authoritative server-side checks across:
   * 1. Frame ordering and monotonic inter-frame intervals
   * 2. Non-identical frame detection (anti-freeze replay)
   * 3. Photometric luma stability (anti-splicing)
   * 4. Identity continuity between anchor frames (anti-face-swap)
   * 5. Active kinematic movement verification (blink / head turn)
   */
  public static async validateBurst(
    frames: BurstFrameInput[],
    requiredAction: ActiveChallengeAction
  ): Promise<TemporalValidationResult> {
    // 1. Validate frame count
    if (!Array.isArray(frames) || frames.length !== 3) {
      return {
        passed: false,
        status: "rejected",
        rejectionReason: "INVALID_FRAME_COUNT",
        telemetry: {
          lumaValues: [0, 0, 0],
          lumaDelta02: 0,
          anchorIdentitySimilarity02: 0,
          actionApexMetric: 0,
          interFrameIntervalsMs: [],
        },
      };
    }

    // 2. Validate strict sequence order and monotonic timing
    const intervals: number[] = [];
    for (let i = 0; i < 3; i++) {
      const f = frames[i];
      if (!f || f.sequenceIndex !== i) {
        return {
          passed: false,
          status: "rejected",
          rejectionReason: "OUT_OF_ORDER_FRAME_SEQUENCE",
          telemetry: {
            lumaValues: [0, 0, 0],
            lumaDelta02: 0,
            anchorIdentitySimilarity02: 0,
            actionApexMetric: 0,
            interFrameIntervalsMs: intervals,
          },
        };
      }
      if (i > 0) {
        const dt = f.capturedOffsetMs - frames[i - 1].capturedOffsetMs;
        intervals.push(dt);
        if (dt < this.MIN_INTER_FRAME_MS || dt > this.MAX_INTER_FRAME_MS) {
          return {
            passed: false,
            status: "rejected",
            rejectionReason: "INTER_FRAME_TIMING_OUT_OF_BOUNDS",
            telemetry: {
              lumaValues: [0, 0, 0],
              lumaDelta02: 0,
              anchorIdentitySimilarity02: 0,
              actionApexMetric: 0,
              interFrameIntervalsMs: intervals,
            },
          };
        }
      }
    }

    // 3. Decode buffers and check byte-identical replay
    const buffers: Buffer[] = [];
    for (let i = 0; i < 3; i++) {
      const raw = frames[i].jpegBase64;
      if (!raw || typeof raw !== "string" || raw.length < 64) {
        return {
          passed: false,
          status: "rejected",
          rejectionReason: "MALFORMED_IMAGE_BUFFER",
          telemetry: {
            lumaValues: [0, 0, 0],
            lumaDelta02: 0,
            anchorIdentitySimilarity02: 0,
            actionApexMetric: 0,
            interFrameIntervalsMs: intervals,
          },
        };
      }
      const cleaned = raw.replace(/^data:image\/\w+;base64,/, "");
      buffers.push(Buffer.from(cleaned, "base64"));
    }

    // Anti-Freeze Replay Check: Reject duplicate identical frames
    if (
      buffers[0].equals(buffers[1]) ||
      buffers[1].equals(buffers[2]) ||
      buffers[0].equals(buffers[2])
    ) {
      return {
        passed: false,
        status: "rejected",
        rejectionReason: "DUPLICATE_FRAME_REPLAY_DETECTED",
        telemetry: {
          lumaValues: [0, 0, 0],
          lumaDelta02: 0,
          anchorIdentitySimilarity02: 0,
          actionApexMetric: 0,
          interFrameIntervalsMs: intervals,
        },
      };
    }

    // 4. Photometric Luma Stability Check
    const lumas = await Promise.all(buffers.map((b) => this.computeMeanLuma(b)));
    const luma0 = lumas[0];
    const luma1 = lumas[1];
    const luma2 = lumas[2];
    const lumaDelta02 = Math.abs(luma0 - luma2) / Math.max(luma0, luma2, 1.0);
    const lumaDelta01 = Math.abs(luma0 - luma1) / Math.max(luma0, luma1, 1.0);

    if (
      lumaDelta02 > this.MAX_LUMA_RELATIVE_DELTA ||
      lumaDelta01 > this.MAX_LUMA_RELATIVE_DELTA
    ) {
      return {
        passed: false,
        status: "rejected",
        rejectionReason: "PHOTOMETRIC_LUMA_STEP_ANOMALY",
        telemetry: {
          lumaValues: [luma0, luma1, luma2],
          lumaDelta02,
          anchorIdentitySimilarity02: 0,
          actionApexMetric: 0,
          interFrameIntervalsMs: intervals,
        },
      };
    }

    // 5. Authoritative SFace Identity Continuity Check between Frame 0 and Frame 2
    let emb0: number[];
    let emb2: number[];
    try {
      [emb0, emb2] = await Promise.all([
        runFaceInference(buffers[0]),
        runFaceInference(buffers[2]),
      ]);
    } catch {
      return {
        passed: false,
        status: "rejected",
        rejectionReason: "MALFORMED_IMAGE_BUFFER",
        telemetry: {
          lumaValues: [luma0, luma1, luma2],
          lumaDelta02,
          anchorIdentitySimilarity02: 0,
          actionApexMetric: 0,
          interFrameIntervalsMs: intervals,
        },
      };
    }

    const anchorSimilarity02 = cosineSimilarity(emb0, emb2);
    if (!Number.isFinite(anchorSimilarity02) || anchorSimilarity02 < this.MIN_ANCHOR_SFACE_CONTINUITY) {
      return {
        passed: false,
        status: "rejected",
        rejectionReason: "CROSS_FRAME_IDENTITY_SPLICE_DETECTED",
        telemetry: {
          lumaValues: [luma0, luma1, luma2],
          lumaDelta02,
          anchorIdentitySimilarity02: Number.isFinite(anchorSimilarity02) ? anchorSimilarity02 : 0,
          actionApexMetric: 0,
          interFrameIntervalsMs: intervals,
        },
      };
    }

    // 6. Server-Side Action Trajectory Verification
    let actionMetricApex = 0;
    let kinematicDelta: { deltaX: number; deltaY: number } | undefined;

    if (requiredAction === "BLINK") {
      const [aperture0, aperture1, aperture2] = await Promise.all([
        this.measureEyeAperture(buffers[0]),
        this.measureEyeAperture(buffers[1]),
        this.measureEyeAperture(buffers[2]),
      ]);

      const openBaseline = Math.max(aperture0, aperture2, 1.0);
      const apexRatio = aperture1 / openBaseline;
      actionMetricApex = apexRatio;

      if (apexRatio > this.MAX_BLINK_APEX_RATIO) {
        return {
          passed: false,
          status: "rejected",
          rejectionReason: "BLINK_TRAJECTORY_NOT_SATISFIED",
          telemetry: {
            lumaValues: [luma0, luma1, luma2],
            lumaDelta02,
            anchorIdentitySimilarity02: anchorSimilarity02,
            actionApexMetric: apexRatio,
            interFrameIntervalsMs: intervals,
          },
        };
      }
    } else if (requiredAction === "TURN_HEAD_LEFT") {
      const [com0, com1, com2] = await Promise.all([
        this.computeKinematicCenterOfMass(buffers[0]),
        this.computeKinematicCenterOfMass(buffers[1]),
        this.computeKinematicCenterOfMass(buffers[2]),
      ]);

      const deltaX01 = com1.normX - com0.normX;
      const deltaX02 = com2.normX - com0.normX;
      const deltaY01 = com1.normY - com0.normY;
      kinematicDelta = { deltaX: deltaX01, deltaY: deltaY01 };
      actionMetricApex = deltaX01;

      // Leftward turn must exhibit negative horizontal shift exceeding threshold
      // and must return towards baseline center in recovery Frame 2
      const isLeftward = deltaX01 <= -this.MIN_HEAD_TURN_DELTA_X;
      const returnsToCenter = Math.abs(deltaX02) < Math.abs(deltaX01) && Math.abs(deltaX02) <= this.MAX_RECOVERY_RESIDUAL;

      if (!isLeftward || !returnsToCenter) {
        return {
          passed: false,
          status: "rejected",
          rejectionReason: "HEAD_TURN_LEFT_TRAJECTORY_NOT_SATISFIED",
          telemetry: {
            lumaValues: [luma0, luma1, luma2],
            lumaDelta02,
            anchorIdentitySimilarity02: anchorSimilarity02,
            actionApexMetric: deltaX01,
            interFrameIntervalsMs: intervals,
            kinematicDisplacement: kinematicDelta,
          },
        };
      }
    } else if (requiredAction === "TURN_HEAD_RIGHT") {
      const [com0, com1, com2] = await Promise.all([
        this.computeKinematicCenterOfMass(buffers[0]),
        this.computeKinematicCenterOfMass(buffers[1]),
        this.computeKinematicCenterOfMass(buffers[2]),
      ]);

      const deltaX01 = com1.normX - com0.normX;
      const deltaX02 = com2.normX - com0.normX;
      const deltaY01 = com1.normY - com0.normY;
      kinematicDelta = { deltaX: deltaX01, deltaY: deltaY01 };
      actionMetricApex = deltaX01;

      // Rightward turn must exhibit positive horizontal shift exceeding threshold
      // and must return towards baseline center in recovery Frame 2
      const isRightward = deltaX01 >= this.MIN_HEAD_TURN_DELTA_X;
      const returnsToCenter = Math.abs(deltaX02) < Math.abs(deltaX01) && Math.abs(deltaX02) <= this.MAX_RECOVERY_RESIDUAL;

      if (!isRightward || !returnsToCenter) {
        return {
          passed: false,
          status: "rejected",
          rejectionReason: "HEAD_TURN_RIGHT_TRAJECTORY_NOT_SATISFIED",
          telemetry: {
            lumaValues: [luma0, luma1, luma2],
            lumaDelta02,
            anchorIdentitySimilarity02: anchorSimilarity02,
            actionApexMetric: deltaX01,
            interFrameIntervalsMs: intervals,
            kinematicDisplacement: kinematicDelta,
          },
        };
      }
    } else if (requiredAction === "NOD_HEAD") {
      const [com0, com1, com2] = await Promise.all([
        this.computeKinematicCenterOfMass(buffers[0]),
        this.computeKinematicCenterOfMass(buffers[1]),
        this.computeKinematicCenterOfMass(buffers[2]),
      ]);

      const deltaX01 = com1.normX - com0.normX;
      const deltaY01 = com1.normY - com0.normY;
      const deltaY02 = com2.normY - com0.normY;
      kinematicDelta = { deltaX: deltaX01, deltaY: deltaY01 };
      actionMetricApex = deltaY01;

      // Pitch nod down exhibits downward vertical gradient shift (deltaY >= threshold)
      // and returns towards baseline center in recovery Frame 2
      const isNodDown = deltaY01 >= this.MIN_HEAD_NOD_DELTA_Y;
      const returnsToCenter = Math.abs(deltaY02) < Math.abs(deltaY01) && Math.abs(deltaY02) <= this.MAX_RECOVERY_RESIDUAL;

      if (!isNodDown || !returnsToCenter) {
        return {
          passed: false,
          status: "rejected",
          rejectionReason: "NOD_HEAD_TRAJECTORY_NOT_SATISFIED",
          telemetry: {
            lumaValues: [luma0, luma1, luma2],
            lumaDelta02,
            anchorIdentitySimilarity02: anchorSimilarity02,
            actionApexMetric: deltaY01,
            interFrameIntervalsMs: intervals,
            kinematicDisplacement: kinematicDelta,
          },
        };
      }
    } else {
      // General movement validation fallback
      let emb1: number[];
      try {
        emb1 = await runFaceInference(buffers[1]);
      } catch {
        emb1 = emb0;
      }
      const sim01 = cosineSimilarity(emb0, emb1);
      actionMetricApex = sim01;

      if (sim01 > 0.985) {
        return {
          passed: false,
          status: "rejected",
          rejectionReason: "HEAD_MOVEMENT_TRAJECTORY_NOT_SATISFIED",
          telemetry: {
            lumaValues: [luma0, luma1, luma2],
            lumaDelta02,
            anchorIdentitySimilarity02: anchorSimilarity02,
            actionApexMetric: sim01,
            interFrameIntervalsMs: intervals,
          },
        };
      }
    }

    // 7. Merge Open Anchor Frames (Frame 0 and Frame 2) into Authoritative Template
    const merged = new Float32Array(128);
    let sumSq = 0;
    for (let i = 0; i < 128; i++) {
      merged[i] = 0.5 * (emb0[i] + emb2[i]);
      sumSq += merged[i] * merged[i];
    }
    const norm = Math.sqrt(sumSq) || 1.0;
    for (let i = 0; i < 128; i++) {
      merged[i] /= norm;
    }

    return {
      passed: true,
      status: "verified",
      telemetry: {
        lumaValues: [luma0, luma1, luma2],
        lumaDelta02,
        anchorIdentitySimilarity02: anchorSimilarity02,
        actionApexMetric: actionMetricApex,
        interFrameIntervalsMs: intervals,
        kinematicDisplacement: kinematicDelta,
      },
      authoritativeEmbedding: merged,
    };
  }

  private static async computeMeanLuma(buffer: Buffer): Promise<number> {
    try {
      const { data } = await sharp(buffer).grayscale().raw().toBuffer({ resolveWithObject: true });
      if (data.length === 0) return 0;
      let sum = 0;
      for (let i = 0; i < data.length; i++) sum += data[i];
      return sum / data.length;
    } catch {
      return 128;
    }
  }

  /**
   * Fast server-side ocular aperture estimator using central vertical gradient energy.
   * Open eyes exhibit strong horizontal eyelid boundaries with high vertical gradients.
   * Closed eyes compress the palpebral fissure, reducing vertical edge height.
   */
  private static async measureEyeAperture(buffer: Buffer): Promise<number> {
    try {
      const { data, info } = await sharp(buffer)
        .resize(112, 112)
        .grayscale()
        .raw()
        .toBuffer({ resolveWithObject: true });

      // Ocular band roughly across y in [35, 65]
      const yStart = 35;
      const yEnd = 65;
      let verticalEdgeEnergy = 0;

      for (let y = yStart; y < yEnd; y++) {
        for (let x = 15; x < 97; x++) {
          const idx = y * info.width + x;
          const gy = Math.abs(data[idx + info.width] - data[idx - info.width]);
          verticalEdgeEnergy += gy;
        }
      }
      return verticalEdgeEnergy / ((yEnd - yStart) * 82);
    } catch {
      return 1.0;
    }
  }

  /**
   * Fast server-side 2D facial kinematic center-of-mass estimator.
   * Tracks directional shift of facial gradient energy across yaw (horizontal deltaX)
   * and pitch (vertical deltaY) trajectories without client trust.
   */
  private static async computeKinematicCenterOfMass(
    buffer: Buffer
  ): Promise<{ normX: number; normY: number }> {
    try {
      const { data, info } = await sharp(buffer)
        .resize(112, 112)
        .grayscale()
        .raw()
        .toBuffer({ resolveWithObject: true });

      let sumWeight = 0;
      let sumX = 0;
      let sumY = 0;

      for (let y = 1; y < info.height - 1; y++) {
        const row = y * info.width;
        for (let x = 1; x < info.width - 1; x++) {
          const idx = row + x;
          const gx = Math.abs(data[idx + 1] - data[idx - 1]);
          const gy = Math.abs(data[idx + info.width] - data[idx - info.width]);
          const g = gx + gy;
          sumWeight += g;
          sumX += x * g;
          sumY += y * g;
        }
      }

      if (sumWeight === 0) return { normX: 0.5, normY: 0.5 };
      return {
        normX: sumX / (sumWeight * info.width),
        normY: sumY / (sumWeight * info.height),
      };
    } catch {
      return { normX: 0.5, normY: 0.5 };
    }
  }
}
