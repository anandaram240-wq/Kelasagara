// File: backend/src/tests/biometric_pipeline_coordinator_v18.test.ts
// KELASAGARA V18 — Unit & Regression Tests for BiometricPipelineCoordinatorV18

import { describe, it, beforeEach } from 'node:test';
import assert from 'node:assert/strict';

import {
  CANONICAL_SFACE_MODEL_ID,
  CANONICAL_SFACE_MODEL_VERSION,
  CloudKmsEnvelopeService,
  LocalDevKeyProvider,
  SFACE_EMBEDDING_DIMENSION,
  l2NormalizeSfaceVector,
} from '../crypto/cloud_kms_envelope';

import {
  BiometricAuditTicketV3,
  BiometricVaultPersistenceAdapter,
  GalleryConsistencyServiceV3,
  StoredVaultDocumentV3,
} from '../services/gallery_consistency_service';

import {
  BiometricBurstCaptureRequestV18,
  BiometricPipelineCoordinatorV18,
  BurstFrameInputV18,
  CanonicalSface5PointAnchors,
  CanonicalSfaceOnnxExtractor,
  Dense500LandmarkQualityPadGateV18,
  Point3D,
  ServerDenseLandmarkDetector,
} from '../services/biometric_pipeline_coordinator_v18';

function createDeterministicRng(seed: number): () => number {
  let state = seed >>> 0;
  return () => {
    state = (state + 0x6d2b79f5) >>> 0;
    let t = Math.imul(state ^ (state >>> 15), 1 | state);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function makeUnitSface128(seed: number): Float32Array {
  const rng = createDeterministicRng(seed);
  const v = new Float32Array(SFACE_EMBEDDING_DIMENSION);
  for (let i = 0; i < SFACE_EMBEDDING_DIMENSION; i++) {
    v[i] = rng() * 2.0 - 1.0;
  }
  return l2NormalizeSfaceVector(v);
}

/**
 * Builds a synthetic 478-point 3D facial mesh with configurable yaw, camera scale (IPD),
 * flat 2D spoof mode, and beard/turban occlusion.
 */
function build3DMesh478(options: {
  yawDeg?: number;
  ipdPixels?: number;
  flatten2DSpoof?: boolean;
  applyThickBeard?: boolean;
  applyTurban?: boolean;
  occludePeriocularCore?: boolean;
}): Point3D[] {
  const yawRad = ((options.yawDeg ?? 0.0) * Math.PI) / 180.0;
  const scale = options.ipdPixels ?? 120.0;
  const cosY = Math.cos(yawRad);
  const sinY = Math.sin(yawRad);

  const canonical = new Array<Point3D>(478);
  for (let i = 0; i < 478; i++) {
    const u = (i / 478.0) * 2.0 * Math.PI;
    const v = ((i * 13) % 478) / 478.0;
    const x = 0.65 * Math.cos(u) * (0.65 + 0.35 * v);
    const y = (v - 0.42) * 1.65;
    const z = -0.22 * (x * x + y * y);

    let conf = 0.98;
    if (options.applyTurban && i < 150) {
      conf = 0.12; // Forehead occluded by turban
    }
    if (options.applyThickBeard && i >= 150 && i < 468) {
      conf = 0.15; // Lower jaw occluded by thick beard
    }
    canonical[i] = { x, y, z, confidence: conf };
  }

  const coreConf = options.occludePeriocularCore ? 0.30 : 0.99;

  canonical[Dense500LandmarkQualityPadGateV18.kLeftPupilIdx] = {
    x: -0.5,
    y: 0.0,
    z: 0.0,
    confidence: coreConf,
  };
  canonical[Dense500LandmarkQualityPadGateV18.kRightPupilIdx] = {
    x: 0.5,
    y: 0.0,
    z: 0.0,
    confidence: coreConf,
  };
  canonical[Dense500LandmarkQualityPadGateV18.kNasionBridgeIdx] = {
    x: 0.0,
    y: -0.06,
    z: 0.14,
    confidence: coreConf,
  };
  canonical[Dense500LandmarkQualityPadGateV18.kNoseTipIdx] = {
    x: 0.0,
    y: 0.34,
    z: 0.42,
    confidence: coreConf,
  };
  canonical[Dense500LandmarkQualityPadGateV18.kSubnasaleIdx] = {
    x: 0.0,
    y: 0.46,
    z: 0.18,
    confidence: coreConf,
  };
  canonical[Dense500LandmarkQualityPadGateV18.kForeheadGlabellaIdx] = {
    x: 0.0,
    y: -0.52,
    z: 0.06,
    confidence: options.applyTurban ? 0.12 : 0.96,
  };
  canonical[Dense500LandmarkQualityPadGateV18.kChinGnathionIdx] = {
    x: 0.0,
    y: 1.12,
    z: 0.04,
    confidence: options.applyThickBeard ? 0.15 : 0.96,
  };
  canonical[Dense500LandmarkQualityPadGateV18.kLeftCheekZygomaIdx] = {
    x: -0.68,
    y: 0.24,
    z: -0.18,
    confidence: coreConf,
  };
  canonical[Dense500LandmarkQualityPadGateV18.kRightCheekZygomaIdx] = {
    x: 0.68,
    y: 0.24,
    z: -0.18,
    confidence: coreConf,
  };
  canonical[Dense500LandmarkQualityPadGateV18.kMouthLeftIdx] = {
    x: -0.32,
    y: 0.72,
    z: 0.08,
    confidence: options.applyThickBeard ? 0.20 : 0.97,
  };
  canonical[Dense500LandmarkQualityPadGateV18.kMouthRightIdx] = {
    x: 0.32,
    y: 0.72,
    z: 0.08,
    confidence: options.applyThickBeard ? 0.20 : 0.97,
  };

  return canonical.map((pt) => {
    const rx = pt.x * cosY - pt.z * sinY;
    const ry = pt.y;
    const rz = options.flatten2DSpoof ? 0.0 : pt.x * sinY + pt.z * cosY;
    return {
      x: rx * scale + 240.0,
      y: ry * scale + 320.0,
      z: rz * scale,
      confidence: pt.confidence,
    };
  });
}

class InMemoryVaultAdapter implements BiometricVaultPersistenceAdapter {
  public globalEpoch = 0;
  public readonly vault = new Map<string, StoredVaultDocumentV3>();
  public readonly audits: BiometricAuditTicketV3[] = [];

  public async getGlobalEpoch(): Promise<number> {
    return this.globalEpoch;
  }
  public async incrementGlobalEpoch(): Promise<number> {
    this.globalEpoch += 1;
    return this.globalEpoch;
  }
  public async fetchAllActiveTemplates(): Promise<StoredVaultDocumentV3[]> {
    return Array.from(this.vault.values());
  }
  public async getVaultDocumentByUid(
    uid: string,
  ): Promise<StoredVaultDocumentV3 | null> {
    return this.vault.get(uid) ?? null;
  }
  public async saveVaultDocument(doc: StoredVaultDocumentV3): Promise<void> {
    this.vault.set(doc.uid, doc);
  }
  public async deleteVaultDocument(uid: string): Promise<boolean> {
    return this.vault.delete(uid);
  }
  public async enqueueAuditTicket(ticket: BiometricAuditTicketV3): Promise<void> {
    this.audits.push(ticket);
  }
}

describe('KELASAGARA V18 — BiometricPipelineCoordinatorV18 (Strict Pre-SFace Landmark Gate)', () => {
  let vaultAdapter: InMemoryVaultAdapter;
  let galleryService: GalleryConsistencyServiceV3;
  let sfaceCallCount: number;
  let lastAnchorsPassedToSface: CanonicalSface5PointAnchors | null;
  let mockMeshesByFrame: Point3D[][];
  let mockSfaceOutput: Float32Array;
  let coordinator: BiometricPipelineCoordinatorV18;

  beforeEach(() => {
    vaultAdapter = new InMemoryVaultAdapter();
    const kms = new CloudKmsEnvelopeService(new LocalDevKeyProvider());
    galleryService = new GalleryConsistencyServiceV3(vaultAdapter, kms);
    sfaceCallCount = 0;
    lastAnchorsPassedToSface = null;
    mockSfaceOutput = makeUnitSface128(1001);

    // Default: 3-frame live 3D burst with natural micro-yaw (-3.5° -> 0° -> +3.5°)
    mockMeshesByFrame = [
      build3DMesh478({ yawDeg: -3.5 }),
      build3DMesh478({ yawDeg: 0.0 }),
      build3DMesh478({ yawDeg: 3.5 }),
    ];

    const detector: ServerDenseLandmarkDetector = {
      detectDenseMesh: async (rawBytes: Uint8Array) => {
        const frameIdx = rawBytes[0] ?? 0;
        return mockMeshesByFrame[frameIdx];
      },
    };

    const sfaceExtractor: CanonicalSfaceOnnxExtractor = {
      modelId: CANONICAL_SFACE_MODEL_ID,
      modelVersion: CANONICAL_SFACE_MODEL_VERSION,
      extract128dEmbedding: async (params: {
        rawBytes: Uint8Array;
        anchors5Point: CanonicalSface5PointAnchors;
      }) => {
        sfaceCallCount += 1;
        lastAnchorsPassedToSface = params.anchors5Point;
        return mockSfaceOutput;
      },
    };

    coordinator = new BiometricPipelineCoordinatorV18({
      landmarkDetector: detector,
      sfaceExtractor,
      galleryService,
    });
  });

  function makeBurstRequest(uid = 'KLS-WKR-001'): BiometricBurstCaptureRequestV18 {
    const frames: BurstFrameInputV18[] = [
      {
        frameIndex: 0,
        timestampMs: 1000,
        rawImageBytes: new Uint8Array([0, 10, 20]),
        meanLuminance: 128.0,
      },
      {
        frameIndex: 1,
        timestampMs: 1120,
        rawImageBytes: new Uint8Array([1, 10, 20]),
        meanLuminance: 130.0,
      },
      {
        frameIndex: 2,
        timestampMs: 1240,
        rawImageBytes: new Uint8Array([2, 10, 20]),
        meanLuminance: 129.0,
      },
    ];
    return {
      uid,
      maskedPhone: '******5177',
      sessionNonce: 'nonce_v18_live_001',
      frames,
    };
  }

  it('1. Rejects flat 2D printed photo spoof at Stage 1 (ISO 30107-3 Parallax Gate) without invoking SFace', async () => {
    mockMeshesByFrame = [
      build3DMesh478({ flatten2DSpoof: true }),
      build3DMesh478({ flatten2DSpoof: true }),
      build3DMesh478({ flatten2DSpoof: true }),
    ];

    const res = await coordinator.processEnrollmentBurst(makeBurstRequest());

    assert.equal(res.ok, false);
    assert.equal(res.stageReached, 'STAGE_1_LANDMARK_PAD_GATE');
    assert.equal(
      res.landmarkGate.rejectionCode,
      'PAD_3D_PARALLAX_SPOOF_REJECTED',
    );
    assert.equal(res.galleryOutcome, null);
    // Crucial: Authoritative SFace model was NEVER invoked on the spoofed burst
    assert.equal(sfaceCallCount, 0);
    assert.equal(galleryService.getActiveGallerySize(), 0);
  });

  it('2. Rejects extreme head yaw (> 22 deg) and low IPD resolution (< 60 px) at Stage 1 without invoking SFace', async () => {
    // Case A: Extreme head yaw (32 degrees)
    mockMeshesByFrame = [
      build3DMesh478({ yawDeg: 30.0 }),
      build3DMesh478({ yawDeg: 32.0 }),
      build3DMesh478({ yawDeg: 34.0 }),
    ];
    const yawRes = await coordinator.processEnrollmentBurst(makeBurstRequest());
    assert.equal(yawRes.ok, false);
    assert.equal(yawRes.landmarkGate.rejectionCode, 'HEAD_POSE_OUT_OF_BOUNDS');
    assert.equal(sfaceCallCount, 0);

    // Case B: Camera too far away (IPD = 42 pixels < 60 pixels minimum)
    mockMeshesByFrame = [
      build3DMesh478({ yawDeg: -3.0, ipdPixels: 42.0 }),
      build3DMesh478({ yawDeg: 0.0, ipdPixels: 42.0 }),
      build3DMesh478({ yawDeg: 3.0, ipdPixels: 42.0 }),
    ];
    const ipdRes = await coordinator.processEnrollmentBurst(makeBurstRequest());
    assert.equal(ipdRes.ok, false);
    assert.equal(
      ipdRes.landmarkGate.rejectionCode,
      'INSUFFICIENT_IPD_RESOLUTION',
    );
    assert.equal(sfaceCallCount, 0);
  });

  it('3. Permits worker with thick beard + turban through Stage 1 (periocular intact) and matches via 128-D SFace in Stage 2/3', async () => {
    mockMeshesByFrame = [
      build3DMesh478({ yawDeg: -4.0, applyThickBeard: true, applyTurban: true }),
      build3DMesh478({ yawDeg: 0.0, applyThickBeard: true, applyTurban: true }),
      build3DMesh478({ yawDeg: 4.0, applyThickBeard: true, applyTurban: true }),
    ];

    const enrollRes = await coordinator.processEnrollmentBurst(
      makeBurstRequest('KLS-WKR-BEARD-TURBAN'),
    );

    assert.equal(enrollRes.ok, true);
    assert.equal(enrollRes.stageReached, 'STAGE_3_GALLERY_COMMIT');
    assert.equal(enrollRes.landmarkGate.gatePassed, true);
    assert.ok(enrollRes.landmarkGate.foreheadOcclusionRatio > 0.80);
    assert.ok(enrollRes.landmarkGate.jawOcclusionRatio > 0.80);
    assert.ok(enrollRes.landmarkGate.periocularCoreConfidence >= 0.95);

    // Verify 5-point anchors were extracted and passed to SFace
    assert.equal(sfaceCallCount, 1);
    assert.ok(lastAnchorsPassedToSface !== null);
    assert.equal(galleryService.getActiveGallerySize(), 1);

    // Verify 1:1 login succeeds via canonical 128-D SFace at 0.363 threshold
    const verifyRes = await coordinator.processVerification1to1Burst(
      makeBurstRequest('KLS-WKR-BEARD-TURBAN'),
    );
    assert.equal(verifyRes.ok, true);
    assert.equal(
      verifyRes.verificationOutcome?.decisionStatus,
      'MATCH_CONFIRMED',
    );
    assert.equal(sfaceCallCount, 2);
  });

  it('4. Rejects client request containing smuggled precomputed vectors before running any detector', async () => {
    const poisonedRequest = {
      ...makeBurstRequest(),
      sfaceEmbedding128: new Array(128).fill(0.1),
    };

    await assert.rejects(
      async () => coordinator.processEnrollmentBurst(poisonedRequest),
      /SECURITY_VIOLATION_CLIENT_VECTOR_FORBIDDEN/,
    );
    assert.equal(sfaceCallCount, 0);
  });
});
