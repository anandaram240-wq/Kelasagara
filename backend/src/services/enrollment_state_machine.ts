// backend/src/services/enrollment_state_machine.ts
import { BiometricEnrollmentState } from "../schemas/data_architecture_schemas";

export class InvalidStateTransitionError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "InvalidStateTransitionError";
  }
}

export interface TransitionContext {
  modelTier?: "RESEARCH_ONLY" | "PRODUCTION_CLEARED" | "PILOT_SHADOW";
  isDuplicate?: boolean;
  requiresReview?: boolean;
  screeningUnavailable?: boolean;
  qualityRejected?: boolean;
  actorRole: "system" | "admin" | "client";
  reason?: string;
}

export interface SplitBrainReconciliationResult {
  isConsistent: boolean;
  flag?: "ORPHANED_VAULT_TEMPLATE" | "USER_VERIFIED_WITHOUT_VAULT" | "STATE_DESYNCHRONIZED";
  recommendedState: BiometricEnrollmentState;
  recommendedFaceVerified: boolean;
  actionRequired: "NONE" | "REVOKE_VERIFICATION" | "ROUTE_TO_MANUAL_REVIEW" | "RE_ENROLL";
  message: string;
}

export class EnrollmentStateMachine {
  /**
   * Allowed state transitions map covering formal BioMatch V19.6 lifecycle.
   */
  private static readonly VALID_TRANSITIONS: Record<
    BiometricEnrollmentState,
    BiometricEnrollmentState[]
  > = {
    INITIAL: ["PENDING_FACE"],
    PENDING_FACE: ["CHALLENGE_ISSUED", "IN_PROGRESS"],
    CHALLENGE_ISSUED: [
      "IN_PROGRESS",
      "QUALITY_REJECTED",
      "TECHNICAL_FAILURE_RETRY",
      "PENDING_FACE",
    ],
    IN_PROGRESS: [
      "QUALITY_REJECTED",
      "SCREENING_UNAVAILABLE",
      "POTENTIAL_DUPLICATE",
      "PENDING_REVIEW",
      "ENROLLED",
      "ACTIVE", // Only permissible with PRODUCTION_CLEARED model tier and clean screening
      "REJECTED_DUPLICATE",
      "TECHNICAL_FAILURE_RETRY",
    ],
    QUALITY_REJECTED: ["IN_PROGRESS", "PENDING_FACE", "TECHNICAL_FAILURE_RETRY"],
    SCREENING_UNAVAILABLE: ["IN_PROGRESS", "PENDING_REVIEW", "TECHNICAL_FAILURE_RETRY"],
    POTENTIAL_DUPLICATE: ["REJECTED_DUPLICATE", "PENDING_REVIEW", "PENDING_FACE"],
    PENDING_REVIEW: ["ACTIVE", "REJECTED_DUPLICATE", "ENROLLED"],
    ENROLLED: ["ACTIVE", "PENDING_REVIEW"],
    TECHNICAL_FAILURE_RETRY: ["IN_PROGRESS", "PENDING_FACE", "CHALLENGE_ISSUED"],
    ACTIVE: [], // Terminal success: immutable
    REJECTED_DUPLICATE: [], // Terminal failure: immutable
  };

  /**
   * Validates if a state transition is legal under BioMatch invariants.
   * Throws InvalidStateTransitionError if illegal.
   */
  static validateTransition(
    current: BiometricEnrollmentState,
    target: BiometricEnrollmentState,
    context: TransitionContext
  ): void {
    // 1. Check basic adjacency
    const allowedTargets = this.VALID_TRANSITIONS[current] || [];
    if (!allowedTargets.includes(target)) {
      throw new InvalidStateTransitionError(
        `Illegal transition from '${current}' to '${target}'. Allowed next states: [${allowedTargets.join(
          ", "
        )}].`
      );
    }

    // 2. Client role restriction (Invariant I-02)
    if (
      ["ACTIVE", "ENROLLED", "REJECTED_DUPLICATE", "POTENTIAL_DUPLICATE", "PENDING_REVIEW"].includes(target) &&
      context.actorRole === "client"
    ) {
      throw new InvalidStateTransitionError(
        `Client is prohibited from advancing biometric enrollment to '${target}'. Requires server authority.`
      );
    }

    // 3. Research Model Governance Gate & Screening Verification (Invariants I-01, I-07, I-18)
    if (target === "ACTIVE") {
      if (context.modelTier === "RESEARCH_ONLY" || context.modelTier === "PILOT_SHADOW") {
        throw new InvalidStateTransitionError(
          `Cannot advance to 'ACTIVE' status using a ${context.modelTier} model. All uncalibrated enrollments must transition to 'PENDING_REVIEW'.`
        );
      }
      if (context.requiresReview) {
        throw new InvalidStateTransitionError(
          `Cannot advance to 'ACTIVE' status when profile requires manual review. Must transition to 'PENDING_REVIEW'.`
        );
      }
      if (context.isDuplicate) {
        throw new InvalidStateTransitionError(
          `Cannot advance duplicate face match to 'ACTIVE'. Must transition to 'REJECTED_DUPLICATE'.`
        );
      }
      if (context.screeningUnavailable) {
        throw new InvalidStateTransitionError(
          `Cannot advance to 'ACTIVE' status when duplicate screening is unavailable. Fail-closed policy enforced.`
        );
      }
    }

    // 4. Duplicate match transition verification
    if (
      (target === "REJECTED_DUPLICATE" || target === "POTENTIAL_DUPLICATE") &&
      !context.isDuplicate &&
      context.actorRole !== "admin"
    ) {
      throw new InvalidStateTransitionError(
        `Cannot transition to '${target}' without an authoritative duplicate match or admin verdict.`
      );
    }
  }

  /**
   * Invariant I-16: Detects and reconciles split-brain inconsistencies
   * between the users document and biometric_vault document.
   */
  static reconcileState(
    userDoc: { accountStatus?: string; faceVerified?: boolean; biometricEnrollmentState?: BiometricEnrollmentState } | null,
    vaultDoc: { uid?: string; tier?: string } | null
  ): SplitBrainReconciliationResult {
    const userFaceVerified = userDoc?.faceVerified === true;
    const hasVault = vaultDoc !== null && !!vaultDoc.uid;

    // Case 1: Healthy verified state
    if (userFaceVerified && hasVault) {
      return {
        isConsistent: true,
        recommendedState: "ACTIVE",
        recommendedFaceVerified: true,
        actionRequired: "NONE",
        message: "Consistent active state: user is marked verified and biometric vault template exists.",
      };
    }

    // Case 2: Healthy un-enrolled state
    if (!userFaceVerified && !hasVault) {
      const currentState = userDoc?.biometricEnrollmentState || "INITIAL";
      return {
        isConsistent: true,
        recommendedState: currentState === "INITIAL" ? "INITIAL" : "PENDING_FACE",
        recommendedFaceVerified: false,
        actionRequired: "NONE",
        message: "Consistent initial state: user unverified and no vault template present.",
      };
    }

    // Case 3: Split-brain: User doc claims faceVerified=true, but NO vault template exists!
    // Catastrophic inconsistency: faceVerified flag without backing template.
    if (userFaceVerified && !hasVault) {
      return {
        isConsistent: false,
        flag: "USER_VERIFIED_WITHOUT_VAULT",
        recommendedState: "PENDING_FACE",
        recommendedFaceVerified: false,
        actionRequired: "REVOKE_VERIFICATION",
        message:
          "INCONSISTENCY DETECTED: User profile claims faceVerified=true, but biometric_vault template is missing. " +
          "Fail-closed policy enforced: verification revoked, user must re-enroll.",
      };
    }

    // Case 4: Split-brain: Vault template exists, but user doc claims faceVerified=false or pending!
    // Orphaned template or incomplete transaction.
    return {
      isConsistent: false,
      flag: "ORPHANED_VAULT_TEMPLATE",
      recommendedState: "PENDING_REVIEW",
      recommendedFaceVerified: false,
      actionRequired: "ROUTE_TO_MANUAL_REVIEW",
      message:
        "INCONSISTENCY DETECTED: biometric_vault template exists, but user profile does not reflect approved verification. " +
        "Profile routed to administrative review for manual reconciliation.",
    };
  }
}
