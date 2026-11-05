// FILE: backend/src/tests/phase19_v18_express_routes_and_gate_h.test.ts

import assert from "node:assert/strict";
import { describe, test } from "node:test";
import { FaceV18UnifiedController } from "../routes/face_v18_unified_routes";

function makeMockRes() {
  const res: {
    statusCode: number;
    body: any;
    status: (c: number) => any;
    json: (b: any) => any;
  } = {
    statusCode: 200,
    body: null,
    status(c: number) {
      this.statusCode = c;
      return this;
    },
    json(b: any) {
      this.body = b;
      return this;
    },
  };
  return res;
}

function makeDctBasis128(personIdx: number, jitter = 0.0): number[] {
  const vec = new Array<number>(128);
  const k = personIdx % 128;
  let sumSq = 0;
  for (let n = 0; n < 128; n++) {
    const basis = Math.cos((Math.PI * (n + 0.5) * (k + 1)) / 128);
    const val = basis + Math.sin(n * 0.7) * jitter;
    vec[n] = val;
    sumSq += val * val;
  }
  const norm = Math.sqrt(sumSq);
  return vec.map((v) => v / norm);
}

describe("KELASAGARA BIOMETRIC ENGINE V18 — PHASE 19 EXPRESS ROUTES & GATE H BRIDGE SUITE", () => {
  test("PHASE19-01: Concurrent /api/v18/biometrics/enroll calls coalesce into 1 epoch, seal WORM anchor, and sanitize PII on 409 duplicate", async () => {
    const controller = new FaceV18UnifiedController({
      duplicateThreshold: 0.55,
      coalesceWindowMs: 5,
    });

    const reqs = [];
    const responses = [];

    // 20 unique workers + 1 twin duplicate fired concurrently at handleEnrollHttp
    for (let i = 0; i < 20; i++) {
      const r = makeMockRes();
      responses.push(r);
      reqs.push(
        controller.handleEnrollHttp(
          {
            body: {
              requestId: `V18_HTTP_${i}`,
              applicantUid: `WORKER_V18_${i}`,
              embedding128: makeDctBasis128(i),
              opticalFiqa: {
                laplacianSharpnessScore: 88.0,
                highlightClippingFraction: 0.02,
                rollingShutterSkewDegrees: 1.0,
                highFreqSkinTextureEnergy: 0.36,
                ambientLuxEstimate: 32000,
              },
            },
          } as any,
          r as any
        )
      );
    }

    // Twin colliding with WORKER_V18_0 in the same batch
    const dupRes = makeMockRes();
    responses.push(dupRes);
    reqs.push(
      controller.handleEnrollHttp(
        {
          body: {
            requestId: "V18_HTTP_DUP",
            applicantUid: "WORKER_FAKE_DUP",
            embedding128: makeDctBasis128(0, 0.01),
            opticalFiqa: {
              laplacianSharpnessScore: 88.0,
              highlightClippingFraction: 0.02,
              rollingShutterSkewDegrees: 1.0,
              highFreqSkinTextureEnergy: 0.36,
              ambientLuxEstimate: 32000,
            },
          },
        } as any,
        dupRes as any
      )
    );

    await Promise.all(reqs);

    assert.equal(responses[0].statusCode, 200);
    assert.equal(responses[0].body.status, "COMMITTED");
    assert.equal(responses[0].body.committedEpoch, 1);
    assert.equal(responses[0].body.batchSizeCoalesced, 21);

    // Check Gate G privacy sanitization on HTTP 409
    assert.equal(dupRes.statusCode, 409);
    assert.equal(dupRes.body.status, "DUPLICATE_INVESTIGATION_PENDING");
    assert.equal(dupRes.body.existingAccountLocked, false);
    assert.match(dupRes.body.auditTicketId, /^AUD_TKT_/);
    assert.equal(dupRes.body.matchedUid, undefined);
    assert.equal(dupRes.body.similarityScore, undefined);
  });

  test("PHASE19-02: /calibration/gate-h-status reports BLOCKED_NO_PHYSICAL_DEVICE when ADB is empty and rejects emulator serials", () => {
    const controller = new FaceV18UnifiedController();
    controller.setAdbSerialsOverrideForTest([]);

    const statusRes = makeMockRes();
    controller.handleGetGateHStatus({} as any, statusRes as any);

    assert.equal(statusRes.statusCode, 200);
    assert.equal(
      statusRes.body.verdict.gateStatus,
      "BLOCKED_NO_PHYSICAL_DEVICE"
    );
    assert.equal(
      statusRes.body.verdict.productionBiometricCalibrationApproved,
      false
    );

    // Attempt to upload an emulator capture -> must be rejected with HTTP 400
    const emuRes = makeMockRes();
    controller.handleRecordCalibrationCapture(
      {
        body: {
          participantId: "PARTICIPANT_1",
          isAdultConsentVerified: true,
          adbHardwareSerial: "emulator-5554",
          deviceModel: "sdk_gphone64_arm64",
          hardwareTier: "TIER_1_ENTRY_CMOS",
          sessionNumber: 1,
          opticalFiqa: {
            laplacianSharpnessScore: 90,
            highlightClippingFraction: 0.01,
            rollingShutterSkewDegrees: 0.5,
            highFreqSkinTextureEnergy: 0.4,
            ambientLuxEstimate: 10000,
          },
          embedding128: makeDctBasis128(1),
        },
      } as any,
      emuRes as any
    );

    assert.equal(emuRes.statusCode, 400);
    assert.match(emuRes.body.error, /ERR_SYNTHETIC_EMULATOR_REJECTED/);
  });

  test("PHASE19-03: /security/revoke-sa-iam trips KMS lockdown, zeroes sfaceArena128, and blocks subsequent /enroll calls with HTTP 503", async () => {
    const controller = new FaceV18UnifiedController();

    // Enroll 1 user so arena has non-zero float data
    const enroll1 = makeMockRes();
    await controller.handleEnrollHttp(
      {
        body: {
          requestId: "REQ_INIT",
          applicantUid: "WORKER_INIT",
          embedding128: makeDctBasis128(3),
        },
      } as any,
      enroll1 as any
    );
    assert.equal(enroll1.statusCode, 200);

    // Trigger emergency KMS SA IAM revocation
    const revokeRes = makeMockRes();
    controller.handleEmergencyRevokeSaIam({ body: {} } as any, revokeRes as any);
    assert.equal(revokeRes.statusCode, 200);
    assert.equal(revokeRes.body.kmsCircuitState, "HSM_REVOKED_LOCKDOWN");
    assert.equal(revokeRes.body.isArenaZeroized, true);

    // Next enrollment attempt must fail-close with HTTP 503
    const enrollAfter = makeMockRes();
    await controller.handleEnrollHttp(
      {
        body: {
          requestId: "REQ_AFTER_LOCKDOWN",
          applicantUid: "WORKER_2",
          embedding128: makeDctBasis128(4),
        },
      } as any,
      enrollAfter as any
    );
    assert.equal(enrollAfter.statusCode, 503);
    assert.match(enrollAfter.body.error, /ERR_HSM_LOCKDOWN_ACTIVE/);
  });
});
