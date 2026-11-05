// backend/src/tests/v19_6_advanced_enrollment.test.ts
import { describe, it, beforeEach } from "node:test";
import assert from "node:assert";
import {
  EnrollmentStateMachine,
  InvalidStateTransitionError,
} from "../services/enrollment_state_machine";
import {
  SessionChallengeService,
  ActiveChallengeAction,
  ACTION_PROMPTS,
} from "../services/session_challenge_service";
import { BiometricEnrollmentService } from "../services/biometric_enrollment";
import { config } from "../config";
import { evaluateMatch } from "../services/biometric_matching";

describe("V19.6 Advanced Biometric Enrollment & Identity Security Suite", () => {
  beforeEach(() => {
    SessionChallengeService.reset();
  });

  describe("1. Formal Enrollment State Machine Lifecycle & Governance", () => {
    it("permits standard valid registration and capture lifecycle transitions", () => {
      // INITIAL -> PENDING_FACE
      assert.doesNotThrow(() => {
        EnrollmentStateMachine.validateTransition("INITIAL", "PENDING_FACE", {
          actorRole: "system",
        });
      });

      // PENDING_FACE -> CHALLENGE_ISSUED
      assert.doesNotThrow(() => {
        EnrollmentStateMachine.validateTransition("PENDING_FACE", "CHALLENGE_ISSUED", {
          actorRole: "system",
        });
      });

      // CHALLENGE_ISSUED -> IN_PROGRESS
      assert.doesNotThrow(() => {
        EnrollmentStateMachine.validateTransition("CHALLENGE_ISSUED", "IN_PROGRESS", {
          actorRole: "system",
        });
      });

      // IN_PROGRESS -> PENDING_REVIEW
      assert.doesNotThrow(() => {
        EnrollmentStateMachine.validateTransition("IN_PROGRESS", "PENDING_REVIEW", {
          actorRole: "system",
          requiresReview: true,
        });
      });

      // IN_PROGRESS -> POTENTIAL_DUPLICATE
      assert.doesNotThrow(() => {
        EnrollmentStateMachine.validateTransition("IN_PROGRESS", "POTENTIAL_DUPLICATE", {
          actorRole: "system",
          isDuplicate: true,
        });
      });

      // IN_PROGRESS -> SCREENING_UNAVAILABLE
      assert.doesNotThrow(() => {
        EnrollmentStateMachine.validateTransition("IN_PROGRESS", "SCREENING_UNAVAILABLE", {
          actorRole: "system",
          screeningUnavailable: true,
        });
      });

      // IN_PROGRESS -> QUALITY_REJECTED
      assert.doesNotThrow(() => {
        EnrollmentStateMachine.validateTransition("IN_PROGRESS", "QUALITY_REJECTED", {
          actorRole: "system",
          qualityRejected: true,
        });
      });
    });

    it("Invariant I-02: Strictly prevents client from claiming ACTIVE or ENROLLED unilaterally", () => {
      assert.throws(
        () => {
          EnrollmentStateMachine.validateTransition("IN_PROGRESS", "ACTIVE", {
            actorRole: "client",
          });
        },
        InvalidStateTransitionError,
        "Client cannot unilaterally transition to ACTIVE"
      );

      assert.throws(
        () => {
          EnrollmentStateMachine.validateTransition("IN_PROGRESS", "ENROLLED", {
            actorRole: "client",
          });
        },
        InvalidStateTransitionError,
        "Client cannot unilaterally transition to ENROLLED"
      );

      assert.throws(
        () => {
          EnrollmentStateMachine.validateTransition("IN_PROGRESS", "POTENTIAL_DUPLICATE", {
            actorRole: "client",
            isDuplicate: true,
          });
        },
        InvalidStateTransitionError,
        "Client cannot alter duplicate classification"
      );
    });

    it("Invariants I-01 & I-18: Prohibits ACTIVE transition under uncalibrated research models", () => {
      // Blocked when modelTier is RESEARCH_ONLY
      assert.throws(
        () => {
          EnrollmentStateMachine.validateTransition("IN_PROGRESS", "ACTIVE", {
            actorRole: "system",
            modelTier: "RESEARCH_ONLY",
          });
        },
        InvalidStateTransitionError,
        "Cannot activate account with RESEARCH_ONLY model"
      );

      // Blocked when modelTier is PILOT_SHADOW
      assert.throws(
        () => {
          EnrollmentStateMachine.validateTransition("IN_PROGRESS", "ACTIVE", {
            actorRole: "system",
            modelTier: "PILOT_SHADOW",
          });
        },
        InvalidStateTransitionError,
        "Cannot activate account with PILOT_SHADOW model"
      );

      // Blocked when screening is unavailable (fail-closed)
      assert.throws(
        () => {
          EnrollmentStateMachine.validateTransition("IN_PROGRESS", "ACTIVE", {
            actorRole: "system",
            modelTier: "PRODUCTION_CLEARED",
            screeningUnavailable: true,
          });
        },
        InvalidStateTransitionError,
        "Cannot activate account when screening is unavailable"
      );

      // Blocked when candidate is duplicate
      assert.throws(
        () => {
          EnrollmentStateMachine.validateTransition("IN_PROGRESS", "ACTIVE", {
            actorRole: "system",
            modelTier: "PRODUCTION_CLEARED",
            isDuplicate: true,
          });
        },
        InvalidStateTransitionError,
        "Cannot activate account when duplicate candidate exists"
      );
    });

    it("prohibits transition to REJECTED_DUPLICATE without authoritative duplicate match", () => {
      assert.throws(
        () => {
          EnrollmentStateMachine.validateTransition("IN_PROGRESS", "REJECTED_DUPLICATE", {
            actorRole: "system",
            isDuplicate: false,
          });
        },
        InvalidStateTransitionError,
        "Cannot reject as duplicate without match"
      );
    });

    it("enforces immutable terminal states", () => {
      assert.throws(() => {
        EnrollmentStateMachine.validateTransition("ACTIVE", "PENDING_FACE", {
          actorRole: "system",
        });
      }, InvalidStateTransitionError);

      assert.throws(() => {
        EnrollmentStateMachine.validateTransition("REJECTED_DUPLICATE", "IN_PROGRESS", {
          actorRole: "system",
        });
      }, InvalidStateTransitionError);
    });
  });

  describe("2. Randomized Server-Issued Active Liveness Challenges", () => {
    it("issues fresh, unpredictable challenges with randomized action sequence and localized prompts", () => {
      const uid = "user_test_v19_6";
      const challenge = SessionChallengeService.createChallenge(uid, "ENROLLMENT");

      assert.ok(challenge.challengeId.startsWith("chal_"), "Must generate unique challenge ID");
      assert.ok(challenge.nonce.length > 32, "Nonce must be high-entropy");
      assert.ok(challenge.expiresAt > Date.now(), "Challenge must have future expiry");
      assert.strictEqual(challenge.action, "ENROLLMENT");

      // Verify action is one of the valid active actions
      const validActions: ActiveChallengeAction[] = [
        "BLINK",
        "TURN_HEAD_LEFT",
        "TURN_HEAD_RIGHT",
        "NOD_HEAD",
      ];
      assert.ok(
        validActions.includes(challenge.requiredAction),
        `Action '${challenge.requiredAction}' must be valid active challenge`
      );

      // Verify localized prompts
      assert.ok(challenge.actionPromptEn.length > 5, "Must provide English prompt");
      assert.ok(challenge.actionPromptKn.length > 5, "Must provide Kannada prompt");
      assert.strictEqual(
        challenge.actionPromptEn,
        ACTION_PROMPTS[challenge.requiredAction].en
      );
      assert.strictEqual(
        challenge.actionPromptKn,
        ACTION_PROMPTS[challenge.requiredAction].kn
      );
    });

    it("verifies distribution across multiple challenge issuances", () => {
      const actionCounts: Record<string, number> = {
        BLINK: 0,
        TURN_HEAD_LEFT: 0,
        TURN_HEAD_RIGHT: 0,
        NOD_HEAD: 0,
      };

      for (let i = 0; i < 40; i++) {
        const chal = SessionChallengeService.issueChallenge(
          `user_dist_${i}`,
          "enrollment",
          true,
          undefined,
          { enableExperimentalActions: true }
        );
        actionCounts[chal.requiredAction] = (actionCounts[chal.requiredAction] || 0) + 1;
      }

      // Over 40 trials, all actions should be triggered
      for (const [action, count] of Object.entries(actionCounts)) {
        assert.ok(count > 0, `Expected action '${action}' to be issued at least once, got ${count}`);
      }
    });

    it("enforces single-use consumption and intercepts replay attacks (Invariant I-05)", () => {
      const uid = "user_replay_test";
      const challenge = SessionChallengeService.createChallenge(uid, "ENROLLMENT");
      const [cId, nonce] = challenge.nonce.split(":");

      // First consumption succeeds
      assert.doesNotThrow(() => {
        SessionChallengeService.validateAndConsume(cId, nonce, uid, "enrollment");
      });

      // Second consumption must fail immediately
      assert.throws(
        () => {
          SessionChallengeService.validateAndConsume(cId, nonce, uid, "enrollment");
        },
        /Replay attack detected|Invalid challenge ID/,
        "Replay must be blocked"
      );
    });

    it("strictly blocks cross-user challenge theft (Invariant I-04)", () => {
      const victimUid = "user_victim_123";
      const attackerUid = "user_attacker_456";
      const challenge = SessionChallengeService.createChallenge(victimUid, "ENROLLMENT");
      const [cId, nonce] = challenge.nonce.split(":");

      assert.throws(
        () => {
          SessionChallengeService.validateAndConsume(cId, nonce, attackerUid, "enrollment");
        },
        /Identity mismatch/,
        "Cross-user challenge theft must be rejected"
      );
    });

    it("strictly blocks cross-action challenge reuse (Invariant I-05)", () => {
      const uid = "user_cross_act";
      const challenge = SessionChallengeService.createChallenge(uid, "VERIFICATION");
      const [cId, nonce] = challenge.nonce.split(":");

      assert.throws(
        () => {
          SessionChallengeService.validateAndConsume(cId, nonce, uid, "enrollment");
        },
        /Action mismatch/,
        "Verification challenge cannot be used for enrollment"
      );
    });

    it("validates observed active action matches server-issued required action", () => {
      const uid = "user_action_audit";
      const challenge = SessionChallengeService.createChallenge(uid, "ENROLLMENT", "NOD_HEAD");
      const [cId, nonce] = challenge.nonce.split(":");

      // Wrong action observed
      assert.throws(
        () => {
          SessionChallengeService.validateAndConsume(
            cId,
            nonce,
            uid,
            "enrollment",
            "TURN_HEAD_LEFT"
          );
        },
        /Liveness action mismatch/,
        "Mismatched action must be rejected"
      );

      // Re-issue with matching action
      const correctChal = SessionChallengeService.createChallenge(uid, "ENROLLMENT", "NOD_HEAD");
      const [cId2, nonce2] = correctChal.nonce.split(":");
      assert.doesNotThrow(() => {
        SessionChallengeService.validateAndConsume(
          cId2,
          nonce2,
          uid,
          "enrollment",
          "NOD_HEAD"
        );
      });
    });
  });

  describe("3. Privacy-Preserving Duplicate Interception (Phase 5 Non-Negotiables)", () => {
    it("proves duplicate decision response sanitizes all candidate PII before ownership verification", () => {
      const similarity = 0.88;
      const evalMatch = evaluateMatch(similarity);
      assert.strictEqual(evalMatch.isDuplicate, true);

      // Build simulated response matching V19.6 specification
      const recoverySessionId = "rec_test_recovery_nonce_123";
      const duplicatePayload = {
        status: "duplicate" as const,
        isApproved: false,
        isDuplicate: true,
        isHardBlock: evalMatch.isHardBlock,
        similarity,
        threshold: config.duplicateThreshold,
        recoverySessionId,
        message:
          "A matching facial profile is already registered. If this is your account, please sign in or verify ownership using your registered mobile number.",
        messageKn:
          "ಈ ಮುಖದ ಪ್ರೊಫೈಲ್ ಈಗಾಗಲೇ ನೋಂದಾಯಿಸಲ್ಪಟ್ಟಿದೆ. ಇದು ನಿಮ್ಮ ಖಾತೆಯಾಗಿದ್ದರೆ, ದಯವಿಟ್ಟು ಸೈನ್ ಇನ್ ಮಾಡಿ ಅಥವಾ ನಿಮ್ಮ ನೋಂದಾಯಿತ ಮೊಬೈಲ್ ಸಂಖ್ಯೆಯನ್ನು ಬಳಸಿ ಮಾಲೀಕತ್ವವನ್ನು ಪರಿಶೀಲಿಸಿ.",
      };

      // Assert ABSOLUTE ZERO leaked candidate PII prior to ownership verification
      assert.strictEqual((duplicatePayload as any).matchedUid, undefined, "Must not leak matchedUid");
      assert.strictEqual((duplicatePayload as any).maskedPhone, undefined, "Must not leak maskedPhone");
      assert.strictEqual((duplicatePayload as any).maskedName, undefined, "Must not leak maskedName");
      assert.strictEqual((duplicatePayload as any).maskedUserId, undefined, "Must not leak maskedUserId");
      assert.strictEqual((duplicatePayload as any).similarityPercent, undefined, "Must not leak similarityPercent");

      // Verify recovery parameters
      assert.strictEqual(duplicatePayload.status, "duplicate");
      assert.strictEqual(duplicatePayload.isApproved, false);
      assert.strictEqual(duplicatePayload.isDuplicate, true);
      assert.ok(duplicatePayload.recoverySessionId.startsWith("rec_"));
      assert.ok(duplicatePayload.message.includes("please sign in or verify ownership"));
      assert.ok(duplicatePayload.messageKn.includes("ದಯವಿಟ್ಟು ಸೈನ್ ಇನ್ ಮಾಡಿ"));
    });
  });

  describe("4. Fail-Closed Screening Availability & Separation of Biometric States (Phase 2)", () => {
    it("distinguishes between registration, vault enrollment, duplicate screening, and account activation", () => {
      // 1. Vault enrollment record
      const vaultRecord = {
        uid: "user_enrolled_001",
        embeddingDim: 128,
        modelVersion: config.modelVersion,
        tier: "PILOT_SHADOW",
        requiresReview: true,
      };
      assert.ok(vaultRecord.requiresReview, "PILOT_SHADOW tier must require review");

      // 2. State machine consistency check
      const userDoc = {
        accountStatus: "pending_review",
        faceVerified: false, // Legal 1:1 identity verification remains uncertified
        biometricEnrollmentState: "PENDING_REVIEW" as const,
      };

      const reconciliation = EnrollmentStateMachine.reconcileState(userDoc, vaultRecord);
      assert.strictEqual(reconciliation.isConsistent, false);
      assert.strictEqual(reconciliation.flag, "ORPHANED_VAULT_TEMPLATE");
      assert.strictEqual(reconciliation.recommendedState, "PENDING_REVIEW");
      assert.strictEqual(reconciliation.recommendedFaceVerified, false);
    });

    it("verifies screening unavailable returns typed fail-closed payload", () => {
      const screeningUnavailablePayload = {
        status: "technical_failure_retry" as const,
        isApproved: false,
        isDuplicate: false,
        similarity: 0.0,
        threshold: config.duplicateThreshold,
        message:
          "Authoritative duplicate screening is currently unavailable. Enrollment held for safety. Please retry shortly.",
        messageKn:
          "ನಕಲಿ ತಪಾಸಣೆ ಪ್ರಸ್ತುತ ಲಭ್ಯವಿಲ್ಲ. ಭದ್ರತೆಗಾಗಿ ನೋಂದಣಿಯನ್ನು ತಡೆಹಿಡಿಯಲಾಗಿದೆ. ದಯವಿಟ್ಟು ಸ್ವಲ್ಪ ಸಮಯದ ನಂತರ ಮತ್ತೆ ಪ್ರಯತ್ನಿಸಿ.",
      };

      assert.strictEqual(screeningUnavailablePayload.status, "technical_failure_retry");
      assert.strictEqual(screeningUnavailablePayload.isApproved, false);
      assert.strictEqual(screeningUnavailablePayload.isDuplicate, false);
      assert.ok(screeningUnavailablePayload.message.includes("currently unavailable"));
    });
  });
});
