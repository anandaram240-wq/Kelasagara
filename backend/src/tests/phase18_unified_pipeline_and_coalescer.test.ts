// FILE: backend/src/tests/phase18_unified_pipeline_and_coalescer.test.ts

import assert from "node:assert/strict";
import { describe, test } from "node:test";
import { GroupCommitEpochSequencerV18 } from "../biometrics/group_commit_epoch_sequencer_v18";
import {
  GcsWormAuditAnchorV18,
  LockedGcsWormDriverSimulator,
} from "../biometrics/gcs_worm_audit_anchor_v18";
import { CloudKmsFailClosedGuardV18 } from "../biometrics/cloud_kms_fail_closed_guard_v18";
import { UnifiedBiometricPipelineV18 } from "../biometrics/unified_biometric_pipeline_v18";
import { OpticalFrameFiqaTelemetry } from "../biometrics/physical_camera_calibration_verifier_v18";

function makeDctOrthonormalVector128(personIdx: number, jitter = 0.0): Float32Array {
  const vec = new Float32Array(128);
  const k = personIdx % 128;
  let sumSq = 0;
  for (let n = 0; n < 128; n++) {
    const basis = Math.cos((Math.PI * (n + 0.5) * (k + 1)) / 128);
    const val = basis + Math.sin(n * 0.7) * jitter;
    vec[n] = val;
    sumSq += val * val;
  }
  const norm = Math.sqrt(sumSq);
  for (let n = 0; n < 128; n++) {
    vec[n] /= norm;
  }
  return vec;
}

const GOOD_FIQA: OpticalFrameFiqaTelemetry = {
  laplacianSharpnessScore: 85.0,
  highlightClippingFraction: 0.03,
  rollingShutterSkewDegrees: 1.1,
  highFreqSkinTextureEnergy: 0.35,
  ambientLuxEstimate: 30000,
};

describe("KELASAGARA BIOMETRIC ENGINE V18 — PHASE 18 UNIFIED PIPELINE & COALESCER SUITE", () => {
  test("PHASE18-01: 50 independent concurrent HTTP requests automatically coalesce into 1 single epoch transition and seal 1 WORM Merkle anchor", async () => {
    const sequencer = new GroupCommitEpochSequencerV18({ duplicateThreshold: 0.55 });
    const wormDriver = new LockedGcsWormDriverSimulator();
    const wormAudit = new GcsWormAuditAnchorV18({
      bucketName: "kelasagara-v18-worm-audit",
      wormDriver,
    });
    const kmsGuard = new CloudKmsFailClosedGuardV18({
      config: {
        gcpResourceName:
          "projects/kelasagara-prod/locations/asia-south1/keyRings/bio-kr/cryptoKeys/sface-hsm",
        protectionLevel: "HSM",
        activeKeyVersion: 1,
      },
      onEmergencyZeroizeArena: () => sequencer.zeroizeActiveArenaMemory(),
    });

    const pipeline = new UnifiedBiometricPipelineV18({
      sequencer,
      wormAudit,
      kmsGuard,
      maxBatchSize: 64,
      coalesceWindowMs: 5,
    });

    // Fire 48 distinct worker requests + 2 twin requests concurrently via Promise.all
    const promises = [];
    for (let i = 0; i < 48; i++) {
      promises.push(
        pipeline.submitEnrollmentHttp({
          requestId: `HTTP_REQ_${i}`,
          applicantUid: `WORKER_${i}`,
          normalizedEmbedding128: makeDctOrthonormalVector128(i),
          opticalFiqa: GOOD_FIQA,
        })
      );
    }

    // Twin attacker submitting 2 concurrent HTTP requests in the same millisecond
    const twinVec1 = makeDctOrthonormalVector128(105, 0.0);
    const twinVec2 = makeDctOrthonormalVector128(105, 0.01);
    promises.push(
      pipeline.submitEnrollmentHttp({
        requestId: "HTTP_TWIN_1",
        applicantUid: "TWIN_ACCT_A",
        normalizedEmbedding128: twinVec1,
        opticalFiqa: GOOD_FIQA,
      }),
      pipeline.submitEnrollmentHttp({
        requestId: "HTTP_TWIN_2",
        applicantUid: "TWIN_ACCT_B",
        normalizedEmbedding128: twinVec2,
        opticalFiqa: GOOD_FIQA,
      })
    );

    const results = await Promise.all(promises);

    const committed = results.filter((r) => r.httpStatus === 200);
    const duplicates = results.filter((r) => r.httpStatus === 409);

    assert.equal(committed.length, 49);
    assert.equal(duplicates.length, 1);

    // Every single one of the 50 concurrent HTTP requests must have been processed in Epoch 1!
    for (const res of committed) {
      if (res.httpStatus === 200) {
        assert.equal(res.outcome.committedEpoch, 1);
        assert.equal(res.batchTelemetry.batchSize, 50);
      }
    }

    // Verify exactly 1 WORM Merkle anchor was sealed for all 50 events
    const anchors = pipeline.getSealedWormAnchors();
    assert.equal(anchors.length, 1);
    assert.equal(anchors[0].startSequence, 1);
    assert.equal(anchors[0].endSequence, 50);
  });

  test("PHASE18-02: Blurry or sun-clipped frames are rejected with HTTP 422 before entering the group-commit sequencer", async () => {
    const sequencer = new GroupCommitEpochSequencerV18();
    const wormDriver = new LockedGcsWormDriverSimulator();
    const wormAudit = new GcsWormAuditAnchorV18({
      bucketName: "kelasagara-v18-worm-audit",
      wormDriver,
    });
    const kmsGuard = new CloudKmsFailClosedGuardV18({
      config: {
        gcpResourceName:
          "projects/kelasagara-prod/locations/asia-south1/keyRings/bio-kr/cryptoKeys/sface-hsm",
        protectionLevel: "HSM",
        activeKeyVersion: 1,
      },
      onEmergencyZeroizeArena: () => sequencer.zeroizeActiveArenaMemory(),
    });

    const pipeline = new UnifiedBiometricPipelineV18({
      sequencer,
      wormAudit,
      kmsGuard,
    });

    const blurryResult = await pipeline.submitEnrollmentHttp({
      requestId: "HTTP_BLUR_1",
      applicantUid: "WORKER_BLUR",
      normalizedEmbedding128: makeDctOrthonormalVector128(1),
      opticalFiqa: {
        ...GOOD_FIQA,
        laplacianSharpnessScore: 18.5, // Below 45.0 threshold
      },
    });

    assert.equal(blurryResult.httpStatus, 422);
    if (blurryResult.httpStatus === 422) {
      assert.equal(blurryResult.failureCode, "ERR_OPTICAL_MOTION_OR_LENS_BLUR");
    }
    assert.equal(pipeline.getSealedWormAnchors().length, 0);
  });
});
