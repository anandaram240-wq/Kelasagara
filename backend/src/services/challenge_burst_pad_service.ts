import * as admin from 'firebase-admin';
import { randomBytes } from 'crypto';
import {
  BiometricOperationOutcome,
  QualityRejectionCode,
  CaptureQualityCandidateConfig,
  DEFAULT_CANDIDATE_QUALITY_CONFIG,
  computeValidatedCosineSimilarity,
} from '../biometrics/canonical_pipeline';
import {
  MediaPipeFaceLandmarkerOnnx,
  FrameLandmarkAndQualityAnalysis,
  Point2D,
  SixPointEyeContour,
} from './mediapipe_face_landmarker_onnx';

export { Point2D, SixPointEyeContour, FrameLandmarkAndQualityAnalysis as FrameAnalysisOutput };

export interface FrameAnalyzerAdapter {
  analyzeFrame(
    jpegBuffer: Buffer,
    options?: { isMirroredFrontCamera?: boolean }
  ): Promise<FrameLandmarkAndQualityAnalysis>;
}

export type ChallengePurpose = 'enroll' | 'verify_1to1' | 'reverify_shift';

export interface BurstFrameItem {
  sequenceIndex: number; // Must be strictly 0, 1, 2
  capturedOffsetMs: number; // Strictly monotonic offset from frame 0
  jpegBase64: string;
}

export interface ChallengeBurstEvaluation {
  outcome: BiometricOperationOutcome;
  qualityRejectionCode?: QualityRejectionCode;
  padRejectionReason?: string;
  telemetry?: {
    earTrajectory: [number, number, number];
    anchorIdentitySimilarity02: number;
    meanLuma02: number;
  };
  /** Canonical L2-normalized 128-D OpenCV SFace vector from the open-eye anchor frames */
  authoritativeSFaceEmbedding?: Float32Array;
}

export class ChallengeBurstPadService {
  private static readonly CHALLENGE_TTL_MS = 120_000;
  private static readonly MAX_SINGLE_FRAME_BYTES = 550 * 1024; // 550 KB max per frame
  private static readonly MIN_INTER_FRAME_MS = 40;
  private static readonly MAX_INTER_FRAME_MS = 600;
  private static readonly MIN_OPEN_EAR = 0.22;
  private static readonly MAX_CLOSED_TO_OPEN_RATIO = 0.65; // Apex EAR <= 0.65 * open baseline
  private static readonly MAX_BILATERAL_EAR_ASYMMETRY = 0.14; // Guards against single-eye wink spoofs
  private static readonly MIN_ANCHOR_SFACE_CONTINUITY = 0.80;

  public static computeMeanEar(contours: {
    left?: SixPointEyeContour;
    right?: SixPointEyeContour;
    viewerLeftEye?: SixPointEyeContour;
    viewerRightEye?: SixPointEyeContour;
  }): number {
    const leftContour = contours.viewerLeftEye || contours.left;
    const rightContour = contours.viewerRightEye || contours.right;
    if (!leftContour || !rightContour) return 0;
    const singleEar = (c: SixPointEyeContour): number => {
      const v1 = Math.hypot(c.p2.x - c.p6.x, c.p2.y - c.p6.y);
      const v2 = Math.hypot(c.p3.x - c.p5.x, c.p3.y - c.p5.y);
      const horiz = Math.hypot(c.p1.x - c.p4.x, c.p1.y - c.p4.y);
      return horiz > 1e-4 ? (v1 + v2) / (2.0 * horiz) : 0;
    };
    return 0.5 * (singleEar(leftContour) + singleEar(rightContour));
  }

  public static async issueChallenge(
    db: admin.firestore.Firestore,
    uid: string,
    purpose: ChallengePurpose
  ) {
    const challengeId = randomBytes(16).toString('hex');
    const nonce = randomBytes(32).toString('base64url');
    const nowMs = Date.now();
    const expiresAtMs = nowMs + this.CHALLENGE_TTL_MS;

    await db.collection('biometric_challenges').doc(challengeId).set({
      challengeId,
      uid,
      purpose,
      nonce,
      expectedFrameCount: 3,
      expectedSequence: ['EYES_OPEN', 'EYES_CLOSED_APEX', 'EYES_OPEN'],
      issuedAtMs: nowMs,
      expiresAtMs,
      consumed: false,
    });

    return {
      challengeId,
      nonce,
      expiresAtMs,
      expectedFrameCount: 3,
      expectedSequence: ['EYES_OPEN', 'EYES_CLOSED_APEX', 'EYES_OPEN'],
    };
  }

  public static async evaluateChallengeBurst(params: {
    db: admin.firestore.Firestore;
    uid: string;
    purpose: ChallengePurpose;
    challengeId: string;
    nonce: string;
    frames: BurstFrameItem[];
    isMirroredFrontCamera?: boolean;
    landmarker: MediaPipeFaceLandmarkerOnnx;
    qualityConfig?: CaptureQualityCandidateConfig;
  }): Promise<ChallengeBurstEvaluation> {
    const {
      db,
      uid,
      purpose,
      challengeId,
      nonce,
      frames,
      isMirroredFrontCamera = false,
      landmarker,
      qualityConfig = DEFAULT_CANDIDATE_QUALITY_CONFIG,
    } = params;

    // 1. Validate frame count (Explicitly reject single static JPEGs or wrong counts)
    if (!Array.isArray(frames) || frames.length !== 3) {
      return {
        outcome: 'PAD_REJECTED',
        padRejectionReason: 'SINGLE_OR_INVALID_FRAME_COUNT_REJECTED',
      };
    }

    // 2. Validate strict frame ordering (0, 1, 2) and inter-frame timing constraints
    for (let i = 0; i < 3; i++) {
      const f = frames[i];
      if (!f || typeof f.sequenceIndex !== 'number' || f.sequenceIndex !== i) {
        return {
          outcome: 'PAD_REJECTED',
          padRejectionReason: 'OUT_OF_ORDER_FRAME_SEQUENCE',
        };
      }
      if (typeof f.capturedOffsetMs !== 'number' || !Number.isFinite(f.capturedOffsetMs)) {
        return {
          outcome: 'PAD_REJECTED',
          padRejectionReason: 'INVALID_FRAME_TIMING_METADATA',
        };
      }
      if (i > 0) {
        const dt = f.capturedOffsetMs - frames[i - 1].capturedOffsetMs;
        if (dt < this.MIN_INTER_FRAME_MS || dt > this.MAX_INTER_FRAME_MS) {
          return {
            outcome: 'PAD_REJECTED',
            padRejectionReason: 'INTER_FRAME_TIMING_OUT_OF_BOUNDS',
          };
        }
      }
    }

    // 3. Decode base64 buffers & enforce payload byte caps
    const buffers: [Buffer, Buffer, Buffer] = [
      Buffer.alloc(0),
      Buffer.alloc(0),
      Buffer.alloc(0),
    ];
    for (let i = 0; i < 3; i++) {
      const rawStr = frames[i].jpegBase64;
      if (typeof rawStr !== 'string' || rawStr.length < 128) {
        return {
          outcome: 'QUALITY_REJECTED',
          qualityRejectionCode: 'MALFORMED_IMAGE',
        };
      }
      const cleaned = rawStr.replace(/^data:image\/\w+;base64,/, '');
      const buf = Buffer.from(cleaned, 'base64');
      if (buf.byteLength < 64 || buf.byteLength > this.MAX_SINGLE_FRAME_BYTES) {
        return {
          outcome: 'QUALITY_REJECTED',
          qualityRejectionCode: 'MALFORMED_IMAGE',
        };
      }
      buffers[i] = buf;
    }

    // 4. Reject byte-identical frame replay before touching Firestore or ONNX
    if (
      buffers[0].equals(buffers[1]) ||
      buffers[1].equals(buffers[2]) ||
      buffers[0].equals(buffers[2])
    ) {
      return {
        outcome: 'PAD_REJECTED',
        padRejectionReason: 'DUPLICATE_FRAME_REPLAY_DETECTED',
      };
    }

    // 5. Atomically consume single-use challenge in Firestore
    const challengeRef = db.collection('biometric_challenges').doc(challengeId);
    try {
      await db.runTransaction(async (tx) => {
        const snap = await tx.get(challengeRef);
        if (!snap.exists) throw new Error('CHALLENGE_NOT_FOUND');
        const data = snap.data()!;
        if (data.consumed === true) throw new Error('CHALLENGE_REPLAY_DETECTED');
        if (data.uid !== uid || data.purpose !== purpose || data.nonce !== nonce) {
          throw new Error('CHALLENGE_BINDING_MISMATCH');
        }
        if (Date.now() > Number(data.expiresAtMs)) {
          throw new Error('CHALLENGE_EXPIRED');
        }
        tx.update(challengeRef, {
          consumed: true,
          consumedAtMs: Date.now(),
        });
      });
    } catch (err: any) {
      return {
        outcome: 'PAD_REJECTED',
        padRejectionReason: String(err?.message || 'CHALLENGE_VERIFICATION_FAILED'),
      };
    }

    // 6. Run MediaPipe FaceLandmarker + SFace across all 3 frames
    let frameAnalyses: [
      FrameLandmarkAndQualityAnalysis,
      FrameLandmarkAndQualityAnalysis,
      FrameLandmarkAndQualityAnalysis
    ];
    try {
      frameAnalyses = (await Promise.all(
        buffers.map((buf) =>
          landmarker.analyzeFrame(buf, { isMirroredFrontCamera })
        )
      )) as [
        FrameLandmarkAndQualityAnalysis,
        FrameLandmarkAndQualityAnalysis,
        FrameLandmarkAndQualityAnalysis
      ];
    } catch (err: any) {
      const msg = String(err?.message || '');
      if (
        msg.includes('MALFORMED') ||
        msg.includes('DIMENSIONS_TOO_SMALL') ||
        msg.includes('Input buffer contains unsupported image format')
      ) {
        return { outcome: 'QUALITY_REJECTED', qualityRejectionCode: 'MALFORMED_IMAGE' };
      }
      if (
        msg.includes('DEGENERATE_EYE_CONTOUR') ||
        msg.includes('INVERTED_EYE_TOPOLOGY') ||
        msg.includes('OUT_OF_BOUNDS_LANDMARK') ||
        msg.includes('PRESENCE_BELOW_THRESHOLD')
      ) {
        return { outcome: 'PAD_INCONCLUSIVE', padRejectionReason: msg };
      }
      return { outcome: 'TECHNICAL_FAILURE', padRejectionReason: msg };
    }

    // 7. Validate capture quality on all 3 frames
    for (const analysis of frameAnalyses) {
      if (analysis.faceCount === 0) {
        return { outcome: 'QUALITY_REJECTED', qualityRejectionCode: 'NO_FACE_DETECTED' };
      }
      if (analysis.faceCount > 1) {
        return {
          outcome: 'QUALITY_REJECTED',
          qualityRejectionCode: 'MULTIPLE_FACES_DETECTED',
        };
      }
      if (analysis.interocularDistancePx < qualityConfig.minInterocularDistancePx) {
        return { outcome: 'QUALITY_REJECTED', qualityRejectionCode: 'FACE_TOO_SMALL' };
      }
      if (
        Math.abs(analysis.yawDeg) > qualityConfig.maxAbsYawDeg ||
        Math.abs(analysis.pitchDeg) > qualityConfig.maxAbsPitchDeg ||
        Math.abs(analysis.rollDeg) > qualityConfig.maxAbsRollDeg
      ) {
        return { outcome: 'QUALITY_REJECTED', qualityRejectionCode: 'EXTREME_POSE' };
      }
      if (analysis.meanFaceLuma < qualityConfig.minFaceLuma) {
        return { outcome: 'QUALITY_REJECTED', qualityRejectionCode: 'UNDEREXPOSED' };
      }
      if (analysis.meanFaceLuma > qualityConfig.maxFaceLuma) {
        return { outcome: 'QUALITY_REJECTED', qualityRejectionCode: 'OVEREXPOSED' };
      }
      if (analysis.laplacianSharpness < qualityConfig.minLaplacianSharpness) {
        return { outcome: 'QUALITY_REJECTED', qualityRejectionCode: 'SEVERE_BLUR' };
      }
    }

    // 8. Validate Photometric Luma Stability across the burst (< 18% relative jump)
    const luma0 = frameAnalyses[0].meanFaceLuma;
    const luma1 = frameAnalyses[1].meanFaceLuma;
    const luma2 = frameAnalyses[2].meanFaceLuma;
    const relLumaJump02 = Math.abs(luma0 - luma2) / Math.max(luma0, luma2, 1.0);
    const relLumaJump01 = Math.abs(luma0 - luma1) / Math.max(luma0, luma1, 1.0);
    if (relLumaJump02 > 0.18 || relLumaJump01 > 0.18) {
      return {
        outcome: 'PAD_REJECTED',
        padRejectionReason: 'PHOTOMETRIC_LUMA_STEP_ANOMALY',
      };
    }

    // 9. Validate Bilateral Eye Aspect Ratio (EAR) Blink Trajectory (Open -> Closed -> Open)
    const ear0 = frameAnalyses[0].earBilateralMean;
    const ear1 = frameAnalyses[1].earBilateralMean;
    const ear2 = frameAnalyses[2].earBilateralMean;

    // Check bilateral symmetry on open frames so an asymmetric occlusion isn't misread
    const asym0 = Math.abs(
      frameAnalyses[0].earViewerLeft - frameAnalyses[0].earViewerRight
    );
    const asym2 = Math.abs(
      frameAnalyses[2].earViewerLeft - frameAnalyses[2].earViewerRight
    );
    if (asym0 > this.MAX_BILATERAL_EAR_ASYMMETRY || asym2 > this.MAX_BILATERAL_EAR_ASYMMETRY) {
      return {
        outcome: 'PAD_INCONCLUSIVE',
        padRejectionReason: 'EXCESSIVE_BILATERAL_EYE_ASYMMETRY',
      };
    }

    const anchorsOpen = ear0 >= this.MIN_OPEN_EAR && ear2 >= this.MIN_OPEN_EAR;
    const apexCompressed =
      ear1 <= ear0 * this.MAX_CLOSED_TO_OPEN_RATIO &&
      ear1 <= ear2 * this.MAX_CLOSED_TO_OPEN_RATIO;

    if (!anchorsOpen || !apexCompressed) {
      return {
        outcome: 'PAD_REJECTED',
        padRejectionReason: 'BLINK_TRAJECTORY_NOT_SATISFIED',
        telemetry: {
          earTrajectory: [ear0, ear1, ear2],
          anchorIdentitySimilarity02: 0,
          meanLuma02: 0.5 * (luma0 + luma2),
        },
      };
    }

    // 10. Validate SFace Identity Continuity between Frame 0 and Frame 2
    const sim02 = computeValidatedCosineSimilarity(
      frameAnalyses[0].sfaceEmbedding128,
      frameAnalyses[2].sfaceEmbedding128
    );
    if (sim02 < this.MIN_ANCHOR_SFACE_CONTINUITY) {
      return {
        outcome: 'PAD_REJECTED',
        padRejectionReason: 'CROSS_FRAME_IDENTITY_SPLICE_DETECTED',
      };
    }

    // 11. Merge open-eye SFace anchor embeddings (Frame 0 & Frame 2) and L2-normalize
    const merged = new Float32Array(128);
    let sumSq = 0;
    for (let i = 0; i < 128; i++) {
      merged[i] =
        0.5 *
        (frameAnalyses[0].sfaceEmbedding128[i] + frameAnalyses[2].sfaceEmbedding128[i]);
      sumSq += merged[i] * merged[i];
    }
    const norm = Math.sqrt(sumSq);
    for (let i = 0; i < 128; i++) {
      merged[i] /= norm;
    }

    return {
      outcome: 'APPROVED',
      telemetry: {
        earTrajectory: [ear0, ear1, ear2],
        anchorIdentitySimilarity02: sim02,
        meanLuma02: 0.5 * (luma0 + luma2),
      },
      authoritativeSFaceEmbedding: merged,
    };
  }
}
