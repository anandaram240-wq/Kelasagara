// backend/src/tests/data_architecture_state_machine.test.ts
import assert from "assert";
import {
  EnrollmentStateMachine,
  InvalidStateTransitionError,
} from "../services/enrollment_state_machine";
import {
  TamperEvidentAuditService,
  AuditIntegrityViolationError,
  canonicalJsonStringify,
  computeAuditLogHash,
  GENESIS_PREVIOUS_HASH,
} from "../services/tamper_evident_audit";

console.log("================================================================================");
console.log("   PHASE 8: DATA ARCHITECTURE, STATE MACHINE & TAMPER-EVIDENT AUDIT TEST SUITE   ");
console.log("================================================================================\n");

async function runTests() {
  let passedCount = 0;

  // ──────────────────────────────────────────────────────────────────────────
  // TEST 1: Legal State Transitions in 6-State Enrollment Machine
  // ──────────────────────────────────────────────────────────────────────────
  console.log("TEST 1: Valid 6-State Enrollment Transitions...");
  {
    // INITIAL -> PENDING_FACE
    assert.doesNotThrow(() => {
      EnrollmentStateMachine.validateTransition("INITIAL", "PENDING_FACE", {
        actorRole: "client",
      });
    }, "INITIAL -> PENDING_FACE must be allowed");

    // PENDING_FACE -> IN_PROGRESS
    assert.doesNotThrow(() => {
      EnrollmentStateMachine.validateTransition("PENDING_FACE", "IN_PROGRESS", {
        actorRole: "system",
      });
    }, "PENDING_FACE -> IN_PROGRESS must be allowed");

    // IN_PROGRESS -> PENDING_REVIEW
    assert.doesNotThrow(() => {
      EnrollmentStateMachine.validateTransition("IN_PROGRESS", "PENDING_REVIEW", {
        actorRole: "system",
        modelTier: "RESEARCH_ONLY",
      });
    }, "IN_PROGRESS -> PENDING_REVIEW must be allowed");

    // IN_PROGRESS -> REJECTED_DUPLICATE
    assert.doesNotThrow(() => {
      EnrollmentStateMachine.validateTransition("IN_PROGRESS", "REJECTED_DUPLICATE", {
        actorRole: "system",
        isDuplicate: true,
      });
    }, "IN_PROGRESS -> REJECTED_DUPLICATE must be allowed when isDuplicate=true");

    // IN_PROGRESS -> TECHNICAL_FAILURE_RETRY
    assert.doesNotThrow(() => {
      EnrollmentStateMachine.validateTransition("IN_PROGRESS", "TECHNICAL_FAILURE_RETRY", {
        actorRole: "system",
      });
    }, "IN_PROGRESS -> TECHNICAL_FAILURE_RETRY must be allowed");

    // TECHNICAL_FAILURE_RETRY -> IN_PROGRESS
    assert.doesNotThrow(() => {
      EnrollmentStateMachine.validateTransition("TECHNICAL_FAILURE_RETRY", "IN_PROGRESS", {
        actorRole: "system",
      });
    }, "TECHNICAL_FAILURE_RETRY -> IN_PROGRESS must be allowed on retry");

    // PENDING_REVIEW -> ACTIVE (Manual Admin approval with cleared model)
    assert.doesNotThrow(() => {
      EnrollmentStateMachine.validateTransition("PENDING_REVIEW", "ACTIVE", {
        actorRole: "admin",
        modelTier: "PRODUCTION_CLEARED",
      });
    }, "PENDING_REVIEW -> ACTIVE must be allowed for admin with cleared tier");

    passedCount++;
    console.log("  [PASS] All legal transitions validated cleanly.\n");
  }

  // ──────────────────────────────────────────────────────────────────────────
  // TEST 2: Invariant I-01 / I-18: RESEARCH_ONLY Model Governance Gate
  // ──────────────────────────────────────────────────────────────────────────
  console.log("TEST 2: Invariants I-01 / I-18: Block automated ACTIVE under RESEARCH_ONLY...");
  {
    assert.throws(
      () => {
        EnrollmentStateMachine.validateTransition("IN_PROGRESS", "ACTIVE", {
          actorRole: "system",
          modelTier: "RESEARCH_ONLY",
        });
      },
      (err: any) => {
        return (
          err instanceof InvalidStateTransitionError &&
          err.message.includes("Cannot advance to 'ACTIVE' status using a RESEARCH_ONLY model")
        );
      },
      "Must throw InvalidStateTransitionError when advancing to ACTIVE under RESEARCH_ONLY"
    );

    assert.throws(
      () => {
        EnrollmentStateMachine.validateTransition("IN_PROGRESS", "ACTIVE", {
          actorRole: "system",
          modelTier: "PRODUCTION_CLEARED",
          requiresReview: true,
        });
      },
      (err: any) => {
        return (
          err instanceof InvalidStateTransitionError &&
          err.message.includes("requires manual review")
        );
      },
      "Must throw when requiresReview is true"
    );

    passedCount++;
    console.log("  [PASS] Research model governance gates verified: automated ACTIVE strictly blocked.\n");
  }

  // ──────────────────────────────────────────────────────────────────────────
  // TEST 3: Terminal State Immutability & Illegal Shortcut Rejections
  // ──────────────────────────────────────────────────────────────────────────
  console.log("TEST 3: Terminal Immutability & Illegal State Shortcuts...");
  {
    // ACTIVE is terminal
    assert.throws(
      () => {
        EnrollmentStateMachine.validateTransition("ACTIVE", "PENDING_FACE", {
          actorRole: "admin",
        });
      },
      InvalidStateTransitionError,
      "ACTIVE cannot transition to PENDING_FACE"
    );

    // REJECTED_DUPLICATE is terminal
    assert.throws(
      () => {
        EnrollmentStateMachine.validateTransition("REJECTED_DUPLICATE", "PENDING_FACE", {
          actorRole: "admin",
        });
      },
      InvalidStateTransitionError,
      "REJECTED_DUPLICATE cannot transition to PENDING_FACE"
    );

    // Illegal shortcut: INITIAL -> ACTIVE
    assert.throws(
      () => {
        EnrollmentStateMachine.validateTransition("INITIAL", "ACTIVE", {
          actorRole: "system",
          modelTier: "PRODUCTION_CLEARED",
        });
      },
      InvalidStateTransitionError,
      "INITIAL -> ACTIVE must be rejected"
    );

    // Client role attempting ACTIVE
    assert.throws(
      () => {
        EnrollmentStateMachine.validateTransition("IN_PROGRESS", "ACTIVE", {
          actorRole: "client",
          modelTier: "PRODUCTION_CLEARED",
        });
      },
      (err: any) => {
        return (
          err instanceof InvalidStateTransitionError &&
          err.message.includes("Client is prohibited from advancing")
        );
      },
      "Client cannot advance to ACTIVE"
    );

    passedCount++;
    console.log("  [PASS] Terminal immutability and illegal shortcut rejections verified.\n");
  }

  // ──────────────────────────────────────────────────────────────────────────
  // TEST 4: Split-Brain Inconsistency Detection & Fail-Closed Reconciliation
  // ──────────────────────────────────────────────────────────────────────────
  console.log("TEST 4: Invariant I-16: Split-Brain Inconsistency Reconciliation...");
  {
    // Case 1: Healthy verified state
    const healthyVerified = EnrollmentStateMachine.reconcileState(
      { accountStatus: "approved", faceVerified: true, biometricEnrollmentState: "ACTIVE" },
      { uid: "user_123", tier: "PRODUCTION_CLEARED" }
    );
    assert.strictEqual(healthyVerified.isConsistent, true);
    assert.strictEqual(healthyVerified.recommendedState, "ACTIVE");
    assert.strictEqual(healthyVerified.actionRequired, "NONE");

    // Case 2: Healthy un-enrolled state
    const healthyUnenrolled = EnrollmentStateMachine.reconcileState(
      { accountStatus: "initial", faceVerified: false, biometricEnrollmentState: "INITIAL" },
      null
    );
    assert.strictEqual(healthyUnenrolled.isConsistent, true);
    assert.strictEqual(healthyUnenrolled.recommendedState, "INITIAL");
    assert.strictEqual(healthyUnenrolled.actionRequired, "NONE");

    // Case 3: Split-brain: User claims faceVerified=true, but vault template is missing!
    const missingVault = EnrollmentStateMachine.reconcileState(
      { accountStatus: "approved", faceVerified: true, biometricEnrollmentState: "ACTIVE" },
      null // No vault document!
    );
    assert.strictEqual(missingVault.isConsistent, false);
    assert.strictEqual(missingVault.flag, "USER_VERIFIED_WITHOUT_VAULT");
    assert.strictEqual(missingVault.recommendedFaceVerified, false);
    assert.strictEqual(missingVault.recommendedState, "PENDING_FACE");
    assert.strictEqual(missingVault.actionRequired, "REVOKE_VERIFICATION");

    // Case 4: Split-brain: Vault template exists, but user doc claims faceVerified=false!
    const orphanedVault = EnrollmentStateMachine.reconcileState(
      { accountStatus: "pending_face", faceVerified: false, biometricEnrollmentState: "PENDING_FACE" },
      { uid: "user_456", tier: "RESEARCH_ONLY" }
    );
    assert.strictEqual(orphanedVault.isConsistent, false);
    assert.strictEqual(orphanedVault.flag, "ORPHANED_VAULT_TEMPLATE");
    assert.strictEqual(orphanedVault.recommendedState, "PENDING_REVIEW");
    assert.strictEqual(orphanedVault.actionRequired, "ROUTE_TO_MANUAL_REVIEW");

    passedCount++;
    console.log("  [PASS] Split-brain inconsistency detection verified; fail-closed self-healing confirmed.\n");
  }

  // ──────────────────────────────────────────────────────────────────────────
  // TEST 5: Tamper-Evident SHA-256 Hash Chain Integrity (Invariant I-17)
  // ──────────────────────────────────────────────────────────────────────────
  console.log("TEST 5: Invariant I-17: Tamper-Evident Audit Logging Chain...");
  {
    const auditService = new TamperEvidentAuditService();

    // Add 4 events to the chain
    const ev1 = auditService.createChainedEvent({
      eventId: "evt_001",
      eventType: "CHALLENGE_NONCE_ISSUED",
      uid: "user_alpha",
      metadata: { nonceId: "nonce_123" },
      customTimestamp: "2026-10-10T03:00:00.000Z",
    });

    const ev2 = auditService.createChainedEvent({
      eventId: "evt_002",
      eventType: "DUPLICATE_REGISTRATION_INTERCEPTED",
      uid: "user_beta",
      matchedUid: "user_alpha",
      similarityScore: 0.892,
      threshold: 0.74,
      customTimestamp: "2026-10-10T03:00:15.000Z",
    });

    const ev3 = auditService.createChainedEvent({
      eventId: "evt_003",
      eventType: "ENROLLMENT_HELD_RESEARCH_MODEL",
      uid: "user_gamma",
      similarityScore: 0.412,
      threshold: 0.74,
      customTimestamp: "2026-10-10T03:00:30.000Z",
    });

    const ev4 = auditService.createChainedEvent({
      eventId: "evt_004",
      eventType: "TEMPLATE_DELETED",
      uid: "user_delta",
      customTimestamp: "2026-10-10T03:00:45.000Z",
    });

    // Verify initial chain integrity
    const chain = auditService.getChain();
    assert.strictEqual(chain.length, 4);
    assert.strictEqual(ev1.previousLogHash, GENESIS_PREVIOUS_HASH);
    assert.strictEqual(ev2.previousLogHash, ev1.currentLogHash);
    assert.strictEqual(ev3.previousLogHash, ev2.currentLogHash);
    assert.strictEqual(ev4.previousLogHash, ev3.currentLogHash);

    const verificationResult = TamperEvidentAuditService.verifyChainIntegrity(chain);
    assert.strictEqual(verificationResult.isValid, true);
    assert.strictEqual(verificationResult.recordsVerified, 4);

    // Attack A: Alter a field in an event (modify similarityScore)
    const tamperedChainPayload = JSON.parse(JSON.stringify(chain));
    tamperedChainPayload[1].similarityScore = 0.555; // Tamper with ev2

    assert.throws(
      () => {
        TamperEvidentAuditService.verifyChainIntegrity(tamperedChainPayload);
      },
      (err: any) => {
        return (
          err instanceof AuditIntegrityViolationError &&
          err.message.includes("Record content tampered at sequence 2")
        );
      },
      "Must detect payload field tampering in event #2"
    );

    // Attack B: Delete an event from the middle of the chain
    const deletedChain = [chain[0], chain[2], chain[3]]; // Removed event #2
    assert.throws(
      () => {
        TamperEvidentAuditService.verifyChainIntegrity(deletedChain);
      },
      (err: any) => {
        return (
          err instanceof AuditIntegrityViolationError &&
          err.message.includes("Sequence break at index 1")
        );
      },
      "Must detect record deletion from sequence"
    );

    // Attack C: Reorder / splice events
    const reorderedChain = [chain[0], chain[1], chain[3], chain[2]]; // Swapped 3 and 4
    assert.throws(
      () => {
        TamperEvidentAuditService.verifyChainIntegrity(reorderedChain);
      },
      (err: any) => {
        return err instanceof AuditIntegrityViolationError;
      },
      "Must detect record reordering"
    );

    passedCount++;
    console.log("  [PASS] Tamper-evident SHA-256 chain verified: field tampering, deletion, and splicing reliably detected.\n");
  }

  // ──────────────────────────────────────────────────────────────────────────
  // TEST 6: Canonical JSON Determinism
  // ──────────────────────────────────────────────────────────────────────────
  console.log("TEST 6: Canonical JSON Stringification Determinism...");
  {
    const objA = { z: 1, a: 2, m: { nestedB: "val", nestedA: 10 } };
    const objB = { a: 2, m: { nestedA: 10, nestedB: "val" }, z: 1 };

    const canonicalA = canonicalJsonStringify(objA);
    const canonicalB = canonicalJsonStringify(objB);

    assert.strictEqual(canonicalA, canonicalB, "Key order must not alter canonical JSON output");

    const hashA = computeAuditLogHash({
      sequenceNumber: 1,
      previousLogHash: GENESIS_PREVIOUS_HASH,
      eventType: "ENROLLMENT_SUCCESS",
      uid: "uid_1",
      timestamp: "2026-10-10T00:00:00Z",
      metadata: objA,
    });

    const hashB = computeAuditLogHash({
      sequenceNumber: 1,
      previousLogHash: GENESIS_PREVIOUS_HASH,
      eventType: "ENROLLMENT_SUCCESS",
      uid: "uid_1",
      timestamp: "2026-10-10T00:00:00Z",
      metadata: objB,
    });

    assert.strictEqual(hashA, hashB, "Audit log hashes must be identical regardless of key order");

    passedCount++;
    console.log("  [PASS] Canonical serialization determinism verified: hash invariance guaranteed.\n");
  }

  console.log("================================================================================");
  console.log(`   PHASE 8 TESTS COMPLETE: ALL ${passedCount}/${passedCount} SUITES PASSED CLEANLY   `);
  console.log("================================================================================\n");
}

runTests().catch((err) => {
  console.error("Test execution failed:", err);
  process.exit(1);
});
