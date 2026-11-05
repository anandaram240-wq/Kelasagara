// FILE: backend/src/tests/biometric_v10_phase9_e2e_pilot_routes.test.ts

import assert from "node:assert/strict";
import { describe, test } from "node:test";
import { FaceV10PilotController } from "../routes/face_v10_pilot_routes";

function makeMockRes() {
  const res: {
    statusCode: number;
    body: any;
    status: (code: number) => any;
    json: (payload: any) => any;
  } = {
    statusCode: 200,
    body: null,
    status(code: number) {
      this.statusCode = code;
      return this;
    },
    json(payload: any) {
      this.body = payload;
      return this;
    },
  };
  return res;
}

function makeUnitEmbedding(seedIndex: number, noise = 0.0): number[] {
  const raw = new Array<number>(128);
  let sumSq = 0;
  for (let i = 0; i < 128; i++) {
    raw[i] = Math.sin((seedIndex + 1) * 0.91 + i * 0.43) + Math.cos(i) * noise;
    sumSq += raw[i] * raw[i];
  }
  const norm = Math.sqrt(sumSq);
  return raw.map((v) => v / norm);
}

describe("KELASAGARA BIOMETRIC V10.0 — PHASE 9 END-TO-END PILOT CONTROLLER SUITE", () => {
  test("PHASE9-A: First-time enrollment locks account with KS_FTOK token and blocks redundant initial re-registration", async () => {
    const controller = new FaceV10PilotController();
    const rameshFace = makeUnitEmbedding(1, 0.0);

    // 1. First-time enrollment succeeds and locks
    const res1 = makeMockRes();
    await controller.handleEnrollOrReRegister(
      {
        body: {
          uid: "KS_USR_RAMESH_8821",
          name: "Ramesh Kumar",
          phone: "+919845012345",
          primarySkill: "Electrician",
          dailyRate: 850,
          mode: "INITIAL_ENROLLMENT",
          embedding: rameshFace,
        },
      } as any,
      res1 as any
    );

    assert.equal(res1.statusCode, 200);
    assert.equal(res1.body.status, "ENROLLED_AND_LOCKED");
    assert.equal(res1.body.faceVerified, true);
    assert.match(res1.body.biometricLockToken, /^KS_FTOK_/);

    // 2. Trying initial enrollment again on the same account is blocked by the lock token
    const res2 = makeMockRes();
    await controller.handleEnrollOrReRegister(
      {
        body: {
          uid: "KS_USR_RAMESH_8821",
          mode: "INITIAL_ENROLLMENT",
          embedding: rameshFace,
        },
      } as any,
      res2 as any
    );

    assert.equal(res2.statusCode, 200);
    assert.equal(res2.body.status, "ALREADY_REGISTERED_LOCKED");
    assert.equal(res2.body.biometricLockToken, res1.body.biometricLockToken);
  });

  test("PHASE9-B: Same person trying to create a 2nd account is blocked with Masked Original Account Details", async () => {
    const controller = new FaceV10PilotController();
    const originalScan = makeUnitEmbedding(5, 0.0);
    const secondAccountScan = makeUnitEmbedding(5, 0.04); // Same person, slight camera noise

    // 1. Register original account
    await controller.handleEnrollOrReRegister(
      {
        body: {
          uid: "KS_USR_ORIG_4910",
          name: "Suresh Gowda",
          phone: "+919900112233",
          primarySkill: "Plumber",
          dailyRate: 900,
          mode: "INITIAL_ENROLLMENT",
          embedding: originalScan,
        },
      } as any,
      makeMockRes() as any
    );

    // 2. Attempt to register a second account with a new UID using the same face
    const dupRes = makeMockRes();
    await controller.handleEnrollOrReRegister(
      {
        body: {
          uid: "KS_USR_FAKE_9999",
          name: "Fake Name",
          phone: "+918888888888",
          primarySkill: "Carpenter",
          mode: "INITIAL_ENROLLMENT",
          embedding: secondAccountScan,
        },
      } as any,
      dupRes as any
    );

    assert.equal(dupRes.statusCode, 409);
    assert.equal(dupRes.body.status, "DUPLICATE_ACCOUNT_DETECTED");
    assert.equal(dupRes.body.existingAccountLocked, false);
    assert.ok(dupRes.body.caseReference && dupRes.body.caseReference.startsWith("CASE-"));
    // Privacy invariant: zero PII disclosed to applicant
    assert.strictEqual(dupRes.body.duplicateAccountDetails, undefined);
  });

  test("PHASE9-C: Existing user can run 1:1 Re-eKYC and Step-Up Authorized Re-Registration without self-collision", async () => {
    const controller = new FaceV10PilotController();
    const scanV1 = makeUnitEmbedding(12, 0.0);
    const scanV2 = makeUnitEmbedding(12, 0.05);

    // 1. Initial Enrollment
    const resEnroll = makeMockRes();
    await controller.handleEnrollOrReRegister(
      {
        body: {
          uid: "KS_USR_ANANDA_0001",
          name: "Ananda V",
          phone: "+919740098765",
          primarySkill: "Mason",
          mode: "INITIAL_ENROLLMENT",
          embedding: scanV1,
        },
      } as any,
      resEnroll as any
    );
    const tokenV1 = resEnroll.body.biometricLockToken;

    // 2. 1:1 Re-eKYC passes without running 1:N duplicate check
    const resEkyc = makeMockRes();
    await controller.handleOneToOneEkyc(
      {
        body: {
          uid: "KS_USR_ANANDA_0001",
          embedding: scanV2,
        },
      } as any,
      resEkyc as any
    );
    assert.equal(resEkyc.body.status, "EKYC_1TO1_VERIFIED");
    assert.equal(resEkyc.body.faceVerified, true);

    // 3. Step-Up Unlock -> Authorized Re-Registration succeeds (self-exclusion prevents "Already Existed")
    const resUnlock = makeMockRes();
    await controller.handleStepUpUnlock(
      {
        body: {
          uid: "KS_USR_ANANDA_0001",
          embedding: scanV2,
        },
      } as any,
      resUnlock as any
    );
    assert.equal(resUnlock.body.status, "UNLOCKED_FOR_ROTATION");

    const resReReg = makeMockRes();
    await controller.handleEnrollOrReRegister(
      {
        body: {
          uid: "KS_USR_ANANDA_0001",
          name: "Ananda V",
          phone: "+919740098765",
          primarySkill: "Mason",
          mode: "AUTHORIZED_RE_REGISTRATION",
          embedding: scanV2,
        },
      } as any,
      resReReg as any
    );

    assert.equal(resReReg.statusCode, 200);
    assert.equal(resReReg.body.status, "RE_REGISTERED_AND_LOCKED");
    assert.equal(resReReg.body.enrollmentVersion, 2);
    assert.notEqual(resReReg.body.biometricLockToken, tokenV1);
  });
});
