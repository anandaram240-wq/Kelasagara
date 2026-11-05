// backend/src/tests/pad_software_adversarial.test.ts
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import * as crypto from 'crypto';

/**
 * 12-point Eyelid Landmark Coordinates extracted from MediaPipe 478-point Attention Mesh
 * for Soukupová & Čech (2016) Eye Aspect Ratio (EAR) calculation:
 *   EAR = (||p2 - p6|| + ||p3 - p5||) / (2 * ||p1 - p4||)
 */
export interface EyeContour6Pt {
  p1: [number, number]; // Lateral canthus
  p2: [number, number]; // Upper outer eyelid
  p3: [number, number]; // Upper inner eyelid
  p4: [number, number]; // Medial canthus
  p5: [number, number]; // Lower inner eyelid
  p6: [number, number]; // Lower outer eyelid
}

export interface BurstFrameTelemetry {
  frameIndex: 0 | 1 | 2;
  offsetMs: number;
  jpegBuffer: Buffer;
  meanLuminance: number; // [0..255]
  leftEye: EyeContour6Pt;
  rightEye: EyeContour6Pt;
  sfaceEmbedding128: Float32Array;
}

export interface ServerChallengeRecord {
  nonce: string;
  userId: string;
  issuedAtMs: number;
  ttlMs: number; // 120,000 ms (120s)
  consumed: boolean;
}

export interface PadBurstEvaluationOutcome {
  passed: boolean;
  rejectionCode:
    | 'NONE'
    | 'CHALLENGE_EXPIRED_OR_REPLAYED'
    | 'FRAME_REPLAY_INJECTION_DETECTED'
    | 'TEMPORAL_JITTER_OR_ORDER_VIOLATION'
    | 'PHOTOMETRIC_FLUX_EXCEEDED_18PCT'
    | 'OCULAR_CLOSURE_SPOOF_DETECTED'
    | 'CROSS_SUBJECT_SPLICE_DETECTED';
  computedEarTrajectory: [number, number, number];
  maxPhotometricFluxRatio: number;
  minCrossFrameCosine: number;
}

export function computeSoukupovaCechEar(eye: EyeContour6Pt): number {
  const dist = (a: [number, number], b: [number, number]): number =>
    Math.hypot(a[0] - b[0], a[1] - b[1]);

  const vert1 = dist(eye.p2, eye.p6);
  const vert2 = dist(eye.p3, eye.p5);
  const horiz = dist(eye.p1, eye.p4);
  if (horiz < 1e-5) return 0.0;
  return (vert1 + vert2) / (2.0 * horiz);
}

export function cosineSimilarity128(a: Float32Array, b: Float32Array): number {
  let dot = 0.0;
  let normA = 0.0;
  let normB = 0.0;
  for (let i = 0; i < 128; i++) {
    dot += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }
  const denom = Math.sqrt(normA) * Math.sqrt(normB);
  return denom > 1e-12 ? dot / denom : 0.0;
}

export function validateChallengeBurstPad(
  challenge: ServerChallengeRecord,
  requestUserId: string,
  nowMs: number,
  frames: [BurstFrameTelemetry, BurstFrameTelemetry, BurstFrameTelemetry]
): PadBurstEvaluationOutcome {
  // 1. 120s server-bound nonce check
  if (
    challenge.consumed ||
    challenge.userId !== requestUserId ||
    nowMs < challenge.issuedAtMs ||
    nowMs - challenge.issuedAtMs > challenge.ttlMs
  ) {
    return {
      passed: false,
      rejectionCode: 'CHALLENGE_EXPIRED_OR_REPLAYED',
      computedEarTrajectory: [0, 0, 0],
      maxPhotometricFluxRatio: 0,
      minCrossFrameCosine: 0,
    };
  }

  // 2. Replay attack resistance: SHA-256 digest check across all 3 frame buffers
  const digests = frames.map((f) =>
    crypto.createHash('sha256').update(f.jpegBuffer).digest('hex')
  );
  if (
    digests[0] === digests[1] ||
    digests[1] === digests[2] ||
    digests[0] === digests[2]
  ) {
    return {
      passed: false,
      rejectionCode: 'FRAME_REPLAY_INJECTION_DETECTED',
      computedEarTrajectory: [0, 0, 0],
      maxPhotometricFluxRatio: 0,
      minCrossFrameCosine: 0,
    };
  }

  // 3. Monotonic stopwatch offsets [0, dt1, dt1+dt2] and [40ms, 600ms] inter-frame window
  const [f0, f1, f2] = frames;
  const dt1 = f1.offsetMs - f0.offsetMs;
  const dt2 = f2.offsetMs - f1.offsetMs;
  if (
    f0.offsetMs !== 0 ||
    dt1 < 40 ||
    dt1 > 600 ||
    dt2 < 40 ||
    dt2 > 600
  ) {
    return {
      passed: false,
      rejectionCode: 'TEMPORAL_JITTER_OR_ORDER_VIOLATION',
      computedEarTrajectory: [0, 0, 0],
      maxPhotometricFluxRatio: 0,
      minCrossFrameCosine: 0,
    };
  }

  // 4. Photometric anomaly check (< 18% luminance shift across burst)
  const flux01 = Math.abs(f1.meanLuminance - f0.meanLuminance) / Math.max(f0.meanLuminance, 1.0);
  const flux12 = Math.abs(f2.meanLuminance - f1.meanLuminance) / Math.max(f1.meanLuminance, 1.0);
  const flux02 = Math.abs(f2.meanLuminance - f0.meanLuminance) / Math.max(f0.meanLuminance, 1.0);
  const maxFlux = Math.max(flux01, flux12, flux02);

  if (maxFlux >= 0.18) {
    return {
      passed: false,
      rejectionCode: 'PHOTOMETRIC_FLUX_EXCEEDED_18PCT',
      computedEarTrajectory: [0, 0, 0],
      maxPhotometricFluxRatio: maxFlux,
      minCrossFrameCosine: 0,
    };
  }

  // 5. Soukupová & Čech EAR blink state machine (EYES_OPEN -> EYES_CLOSED_APEX -> EYES_OPEN)
  const ear0 = (computeSoukupovaCechEar(f0.leftEye) + computeSoukupovaCechEar(f0.rightEye)) * 0.5;
  const ear1 = (computeSoukupovaCechEar(f1.leftEye) + computeSoukupovaCechEar(f1.rightEye)) * 0.5;
  const ear2 = (computeSoukupovaCechEar(f2.leftEye) + computeSoukupovaCechEar(f2.rightEye)) * 0.5;

  // Reject if apex frame has EAR > 0.18 (especially static spoof EAR > 0.28) or open frames < 0.24
  if (ear0 < 0.24 || ear1 > 0.18 || ear2 < 0.24 || ear0 - ear1 < 0.08 || ear2 - ear1 < 0.08) {
    return {
      passed: false,
      rejectionCode: 'OCULAR_CLOSURE_SPOOF_DETECTED',
      computedEarTrajectory: [ear0, ear1, ear2],
      maxPhotometricFluxRatio: maxFlux,
      minCrossFrameCosine: 0,
    };
  }

  // 6. SFace cross-frame identity continuity (>= 0.80)
  const sim01 = cosineSimilarity128(f0.sfaceEmbedding128, f1.sfaceEmbedding128);
  const sim12 = cosineSimilarity128(f1.sfaceEmbedding128, f2.sfaceEmbedding128);
  const sim02 = cosineSimilarity128(f0.sfaceEmbedding128, f2.sfaceEmbedding128);
  const minSim = Math.min(sim01, sim12, sim02);

  if (minSim < 0.80) {
    return {
      passed: false,
      rejectionCode: 'CROSS_SUBJECT_SPLICE_DETECTED',
      computedEarTrajectory: [ear0, ear1, ear2],
      maxPhotometricFluxRatio: maxFlux,
      minCrossFrameCosine: minSim,
    };
  }

  challenge.consumed = true;
  return {
    passed: true,
    rejectionCode: 'NONE',
    computedEarTrajectory: [ear0, ear1, ear2],
    maxPhotometricFluxRatio: maxFlux,
    minCrossFrameCosine: minSim,
  };
}

function buildEyeContour(verticalOpeningPx: number): EyeContour6Pt {
  // Horizontal width = 40px -> EAR = (v + v) / (2 * 40) = v / 40
  return {
    p1: [0, 0],
    p2: [12, verticalOpeningPx],
    p3: [28, verticalOpeningPx],
    p4: [40, 0],
    p5: [28, 0],
    p6: [12, 0],
  };
}

function buildEmbedding(primaryIndex: number, noise = 0.0): Float32Array {
  const vec = new Float32Array(128);
  vec[primaryIndex] = 1.0;
  vec[(primaryIndex + 1) % 128] = noise;
  let sumSq = 0;
  for (let i = 0; i < 128; i++) sumSq += vec[i] * vec[i];
  const inv = 1.0 / Math.sqrt(sumSq);
  for (let i = 0; i < 128; i++) vec[i] *= inv;
  return vec;
}

describe('Gate G-02: Software Adversarial PAD Suite (node:test)', () => {
  const createValidFixture = () => {
    const challenge: ServerChallengeRecord = {
      nonce: 'nonce_120s_valid',
      userId: 'worker_karnataka_01',
      issuedAtMs: 1_000_000,
      ttlMs: 120_000,
      consumed: false,
    };

    const frames: [BurstFrameTelemetry, BurstFrameTelemetry, BurstFrameTelemetry] = [
      {
        frameIndex: 0,
        offsetMs: 0,
        jpegBuffer: Buffer.from('FFD8FFE0_FRAME_0_UNIQUE', 'utf8'),
        meanLuminance: 140.0,
        leftEye: buildEyeContour(12.8), // EAR = 12.8 / 40 = 0.32
        rightEye: buildEyeContour(12.8),
        sfaceEmbedding128: buildEmbedding(0, 0.05),
      },
      {
        frameIndex: 1,
        offsetMs: 165,
        jpegBuffer: Buffer.from('FFD8FFE0_FRAME_1_UNIQUE', 'utf8'),
        meanLuminance: 138.5,
        leftEye: buildEyeContour(4.0), // EAR = 4.0 / 40 = 0.10 (CLOSED APEX)
        rightEye: buildEyeContour(4.0),
        sfaceEmbedding128: buildEmbedding(0, 0.08),
      },
      {
        frameIndex: 2,
        offsetMs: 340,
        jpegBuffer: Buffer.from('FFD8FFE0_FRAME_2_UNIQUE', 'utf8'),
        meanLuminance: 141.2,
        leftEye: buildEyeContour(12.4), // EAR = 12.4 / 40 = 0.31
        rightEye: buildEyeContour(12.4),
        sfaceEmbedding128: buildEmbedding(0, 0.06),
      },
    ];

    return { challenge, frames };
  };

  it('approves a valid 3-frame blink burst with EAR (0.32 -> 0.10 -> 0.31), <18% luma flux, and SFace >= 0.80', () => {
    const { challenge, frames } = createValidFixture();
    const res = validateChallengeBurstPad(challenge, 'worker_karnataka_01', 1_005_000, frames);
    assert.equal(res.passed, true);
    assert.equal(res.rejectionCode, 'NONE');
    assert.ok(res.minCrossFrameCosine >= 0.80);
  });

  it('blocks identical frame replay attack across frames', () => {
    const { challenge, frames } = createValidFixture();
    frames[2].jpegBuffer = Buffer.from(frames[0].jpegBuffer);
    const res = validateChallengeBurstPad(challenge, 'worker_karnataka_01', 1_005_000, frames);
    assert.equal(res.passed, false);
    assert.equal(res.rejectionCode, 'FRAME_REPLAY_INJECTION_DETECTED');
  });

  it('blocks inter-frame temporal jitter (< 40ms or > 600ms) and out-of-order timestamps', () => {
    const { challenge, frames } = createValidFixture();
    frames[1].offsetMs = 25; // Too fast (< 40ms)
    const fastRes = validateChallengeBurstPad(challenge, 'worker_karnataka_01', 1_005_000, frames);
    assert.equal(fastRes.passed, false);
    assert.equal(fastRes.rejectionCode, 'TEMPORAL_JITTER_OR_ORDER_VIOLATION');

    // Out-of-order timestamp injection (dt2 < 0)
    frames[1].offsetMs = 300;
    frames[2].offsetMs = 220;
    const orderRes = validateChallengeBurstPad(challenge, 'worker_karnataka_01', 1_005_000, frames);
    assert.equal(orderRes.passed, false);
    assert.equal(orderRes.rejectionCode, 'TEMPORAL_JITTER_OR_ORDER_VIOLATION');
  });

  it('blocks sudden photometric flux (> 18% luminance shift between Frame 1 and Frame 3)', () => {
    const { challenge, frames } = createValidFixture();
    frames[0].meanLuminance = 120.0;
    frames[2].meanLuminance = 150.0; // (150 - 120) / 120 = 25.0% > 18%
    const res = validateChallengeBurstPad(challenge, 'worker_karnataka_01', 1_005_000, frames);
    assert.equal(res.passed, false);
    assert.equal(res.rejectionCode, 'PHOTOMETRIC_FLUX_EXCEEDED_18PCT');
  });

  it('blocks ocular closure spoof when apex Frame 2 has EAR > 0.28', () => {
    const { challenge, frames } = createValidFixture();
    // Static photo spoof: apex frame eyes remain wide open (12.0 / 40 = 0.30 > 0.28)
    frames[1].leftEye = buildEyeContour(12.0);
    frames[1].rightEye = buildEyeContour(12.0);
    const res = validateChallengeBurstPad(challenge, 'worker_karnataka_01', 1_005_000, frames);
    assert.equal(res.passed, false);
    assert.equal(res.rejectionCode, 'OCULAR_CLOSURE_SPOOF_DETECTED');
  });

  it('blocks cross-subject face splice injection when Frame 1 and Frame 3 SFace similarity < 0.80', () => {
    const { challenge, frames } = createValidFixture();
    // Frame 3 comes from a different person (orthogonal basis index 10 -> similarity = 0.0)
    frames[2].sfaceEmbedding128 = buildEmbedding(10, 0.0);
    const res = validateChallengeBurstPad(challenge, 'worker_karnataka_01', 1_005_000, frames);
    assert.equal(res.passed, false);
    assert.equal(res.rejectionCode, 'CROSS_SUBJECT_SPLICE_DETECTED');
  });
});
