import assert from "node:assert/strict";
import { describe, test } from "node:test";
import {
  GroupCommitEpochSequencerV18,
  SequencerEnrollmentItem,
} from "../biometrics/group_commit_epoch_sequencer_v18";
import {
  GcsWormAuditAnchorV18,
  LockedGcsWormDriverSimulator,
} from "../biometrics/gcs_worm_audit_anchor_v18";
import { CloudKmsFailClosedGuardV18 } from "../biometrics/cloud_kms_fail_closed_guard_v18";
import {
  PhysicalCameraCalibrationVerifierV18,
  PhysicalDeviceCalibrationCapture,
} from "../biometrics/physical_camera_calibration_verifier_v18";

function makeOrthogonalBasisVector128(index: number, slightJitter = 0.0): Float32Array {
  const arr = new Float32Array(128);
  let sumSq = 0;
  for (let d = 0; d < 128; d++) {
    const val =
      Math.cos((Math.PI * (d + 0.5) * ((index % 126) + 1)) / 128) +
      (d % 2 === 0 ? slightJitter : -slightJitter);
    arr[d] = val;
    sumSq += val * val;
  }
  const norm = Math.sqrt(sumSq);
  for (let d = 0; d < 128; d++) {
    arr[d] /= norm;
  }
  return arr;
}

describe("KELASAGARA BIOMETRIC ENGINE V18 — PHASE 17 RELEASE BLOCKER & GROUP COMMIT SUITE", () => {
  test("PHASE17-01 (Gate F): GroupCommitEpochSequencerV18 processes C=50 concurrent enrollments in <50ms and catches in-flight split-brain duplicates", () => {
    const sequencer = new GroupCommitEpochSequencerV18({ duplicateThreshold: 0.55 });
    const batch: SequencerEnrollmentItem[] = [];

    // 48 distinct workers + 2 simultaneous submissions of the SAME person in the same C=50 batch
    for (let i = 0; i < 48; i++) {
      batch.push({
        requestId: `REQ_UNIQUE_${i}`,
        applicantUid: `USR_UNIQUE_${i}`,
        normalizedEmbedding128: makeOrthogonalBasisVector128(i),
      });
    }

    const twinVecA = makeOrthogonalBasisVector128(99, 0.0);
    const twinVecB = makeOrthogonalBasisVector128(99, 0.01); // Same person submitting concurrently!
    batch.push({
      requestId: "REQ_RACE_FIRST",
      applicantUid: "USR_ATTACKER_ACCT_1",
      normalizedEmbedding128: twinVecA,
    });
    batch.push({
      requestId: "REQ_RACE_SECOND",
      applicantUid: "USR_ATTACKER_ACCT_2",
      normalizedEmbedding128: twinVecB,
    });

    const { outcomes, telemetry } = sequencer.executeGroupCommitBatch(batch);

    assert.equal(telemetry.batchSize, 50);
    assert.equal(telemetry.committedCount, 49);
    assert.equal(telemetry.inFlightDuplicateCount, 1);
    assert.ok(
      telemetry.batchExecutionMs < 50,
      `Expected C=50 group commit < 50ms, got ${telemetry.batchExecutionMs}ms`
    );

    const firstRace = outcomes.get("REQ_RACE_FIRST")!;
    const secondRace = outcomes.get("REQ_RACE_SECOND")!;
    assert.equal(firstRace.status, "COMMITTED");
    assert.equal(secondRace.status, "DUPLICATE_INVESTIGATION_PENDING");
    if (secondRace.status === "DUPLICATE_INVESTIGATION_PENDING") {
      assert.equal(secondRace.collisionSource, "IN_FLIGHT_BATCH_CONTENTION");
      assert.equal(secondRace.existingAccountLocked, false);
      assert.match(secondRace.auditTicketId, /^AUD_TKT_/);
    }
  });

  test("PHASE17-02 (BLK-03 / Gate D): GcsWormAuditAnchorV18 locks Merkle roots in WORM storage and detects Admin SDK Firestore tampering", async () => {
    const wormDriver = new LockedGcsWormDriverSimulator();
    const auditAnchor = new GcsWormAuditAnchorV18({
      bucketName: "kelasagara-v18-worm-audit-lock",
      retentionDays: 365,
      wormDriver,
    });

    const e1 = auditAnchor.appendEvent({
      eventType: "ENROLLMENT_COMMITTED",
      actorId: "SYSTEM_SEQUENCER",
      payloadObject: { uid: "USR_1", epoch: 1 },
    });
    const e2 = auditAnchor.appendEvent({
      eventType: "DUPLICATE_INVESTIGATION_QUEUED",
      actorId: "SYSTEM_SEQUENCER",
      payloadObject: { ticketId: "AUD_TKT_99", existingAccountLocked: false },
    });

    const sealed = await auditAnchor.sealAnchorToWormBucket(1, 2);
    assert.equal(sealed.retentionMode, "Locked");
    assert.equal(sealed.ifGenerationMatch, 0);

    // 1. Even a Project Owner cannot delete the WORM object before retainUntilIso
    assert.throws(
      () => wormDriver.attemptPrivilegedDelete(sealed.objectPath, new Date()),
      /ERR_GCS_OBJECT_RETENTION_LOCKED/
    );

    // 2. Genuine Firestore slice verifies cleanly
    const cleanCheck = await auditAnchor.verifyFirestoreEventsAgainstWormAnchor(
      sealed.objectPath,
      [e1, e2]
    );
    assert.equal(cleanCheck.verified, true);

    // 3. Simulate rogue Admin SDK rewriting e1 and recomputing chainHash in Firestore
    const tamperedE1 = { ...e1, chainHash: "ff".repeat(32) };
    const tamperCheck = await auditAnchor.verifyFirestoreEventsAgainstWormAnchor(
      sealed.objectPath,
      [tamperedE1, e2]
    );
    assert.equal(tamperCheck.verified, false);
    assert.match(tamperCheck.reason!, /ERR_ADMIN_SDK_TAMPER_DETECTED/);
  });

  test("PHASE17-03 (BLK-02 / Gate C): CloudKmsFailClosedGuardV18 enforces asia-south1 HSM path, zeros DEK, and wipes sfaceArena128 on SA IAM revocation", () => {
    const sequencer = new GroupCommitEpochSequencerV18();
    sequencer.executeGroupCommitBatch([
      {
        requestId: "REQ_1",
        applicantUid: "USR_1",
        normalizedEmbedding128: makeOrthogonalBasisVector128(1),
      },
    ]);

    const guard = new CloudKmsFailClosedGuardV18({
      config: {
        gcpResourceName:
          "projects/kelasagara-prod/locations/asia-south1/keyRings/biometric-kr/cryptoKeys/sface-hsm-key",
        protectionLevel: "HSM",
        activeKeyVersion: 1,
      },
      onEmergencyZeroizeArena: () => sequencer.zeroizeActiveArenaMemory(),
    });

    const rawDek = Buffer.alloc(32, 0xaa);
    const { wrappedDekCiphertext, keyVersion } = guard.wrapEphemeralDek({
      callerServiceAccount: "enroller-sa@kelasagara-prod.iam.gserviceaccount.com",
      callerRole: "ENROLLER_WRAP_ONLY",
      ephemeralDek: rawDek,
    });

    // Verify caller's plaintext DEK was zeroed in `finally`
    assert.equal(
      rawDek.every((b) => b === 0),
      true,
      "Plaintext ephemeral DEK must be filled with zeros after wrapping"
    );

    // Revoke Matcher SA IAM role -> next unwrap must trigger fail-closed arena zeroization!
    guard.revokeServiceAccountIam("matcher-sa@kelasagara-prod.iam.gserviceaccount.com");

    assert.throws(
      () =>
        guard.unwrapDekAndExecute({
          callerServiceAccount: "matcher-sa@kelasagara-prod.iam.gserviceaccount.com",
          callerRole: "MATCHER_UNWRAP_ONLY",
          wrappedDekCiphertext,
          keyVersion,
          useDekCallback: () => true,
        }),
      /ERR_KMS_IAM_REVOKED_FAIL_CLOSED/
    );

    assert.equal(guard.getCircuitState(), "HSM_REVOKED_LOCKDOWN");
    const arenaAfterRevocation = sequencer.getRawArenaBufferForTest();
    assert.equal(
      arenaAfterRevocation.every((v) => v === 0),
      true,
      "sfaceArena128 must be completely zeroized upon KMS IAM revocation"
    );
  });

  test("PHASE17-04 (BLK-01 / Gate H): PhysicalCameraCalibrationVerifierV18 blocks when adb is empty and unlocks only when 30 multi-tier physical captures pass optical FIQA", () => {
    // 1. Empty ADB -> BLOCKED_NO_PHYSICAL_DEVICE
    const blockedVerdict = PhysicalCameraCalibrationVerifierV18.evaluateGateHReleaseReadiness({
      adbConnectedSerials: [],
      captures: [],
    });
    assert.equal(blockedVerdict.gateStatus, "BLOCKED_NO_PHYSICAL_DEVICE");
    assert.equal(blockedVerdict.productionBiometricCalibrationApproved, false);

    // 2. Full 30-participant cohort across Tier 1 (Redmi A2), Tier 2 (Galaxy M14), Tier 3 (Pixel 7a)
    const tiers = ["TIER_1_ENTRY_CMOS", "TIER_2_MID_RANGE", "TIER_3_REFERENCE"] as const;
    const validCaptures: PhysicalDeviceCalibrationCapture[] = [];

    for (let p = 0; p < 30; p++) {
      const tier = tiers[p % 3];
      for (const session of [1, 2] as const) {
        validCaptures.push({
          participantId: `PARTICIPANT_${p}`,
          isAdultConsentVerified: true,
          adbHardwareSerial: `R9W_PHYS_SN_${1000 + p}`,
          deviceModel:
            tier === "TIER_1_ENTRY_CMOS"
              ? "Redmi A2"
              : tier === "TIER_2_MID_RANGE"
              ? "Galaxy M14"
              : "Pixel 7a",
          hardwareTier: tier,
          sessionNumber: session,
          opticalFiqa: {
            laplacianSharpnessScore: 82.5,
            highlightClippingFraction: 0.04,
            rollingShutterSkewDegrees: 1.2,
            highFreqSkinTextureEnergy: 0.34,
            ambientLuxEstimate: 45000,
          },
          embedding128: Array.from(makeOrthogonalBasisVector128(p, session === 1 ? 0.0 : 0.02)),
        });
      }
    }

    const passedVerdict = PhysicalCameraCalibrationVerifierV18.evaluateGateHReleaseReadiness({
      adbConnectedSerials: ["R9W_PHYS_SN_1000"],
      captures: validCaptures,
      operatingThreshold: 0.55,
    });

    assert.equal(passedVerdict.gateStatus, "PASS_CALIBRATED");
    assert.equal(passedVerdict.productionBiometricCalibrationApproved, true);
    assert.equal(passedVerdict.consentedParticipantCount, 30);
    assert.equal(passedVerdict.failureToAcquireRatePct, 0);
    assert.equal(passedVerdict.genuineAcceptanceRatePct, 100);
    assert.equal(passedVerdict.measuredFarAtThreshold, 0);
  });
});
