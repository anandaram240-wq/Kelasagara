// backend/src/services/session_challenge_service.ts
import crypto from "crypto";

export type ActiveChallengeAction =
  | "BLINK"
  | "TURN_HEAD_LEFT"
  | "TURN_HEAD_RIGHT"
  | "NOD_HEAD";

export interface SessionChallenge {
  challengeId: string;
  nonce: string;
  uid: string;
  action: "enrollment" | "verification" | "step_up";
  requiredAction: ActiveChallengeAction;
  expectedSequence: string[];
  expectedFrameCount: number;
  actionPromptEn: string;
  actionPromptKn: string;
  clientSessionId?: string;
  attemptCount: number;
  createdAt: number;
  expiresAt: number;
  consumed: boolean;
  consumedAt?: number;
  appCheckVerified: boolean;
}

export const ACTION_PROMPTS: Record<
  ActiveChallengeAction,
  { en: string; kn: string }
> = {
  BLINK: {
    en: "Please blink your eyes naturally",
    kn: "ದಯವಿಟ್ಟು ನಿಮ್ಮ ಕಣ್ಣುಗಳನ್ನು ನೈಸರ್ಗಿಕವಾಗಿ ಮಿಟುಕಿಸಿ",
  },
  TURN_HEAD_LEFT: {
    en: "Slowly turn your head slightly to the left",
    kn: "ನಿಮ್ಮ ತಲೆಯನ್ನು ನಿಧಾನವಾಗಿ ಎಡಕ್ಕೆ ತಿರುಗಿಸಿ",
  },
  TURN_HEAD_RIGHT: {
    en: "Slowly turn your head slightly to the right",
    kn: "ನಿಮ್ಮ ತಲೆಯನ್ನು ನಿಧಾನವಾಗಿ ಬಲಕ್ಕೆ ತಿರುಗಿಸಿ",
  },
  NOD_HEAD: {
    en: "Slowly nod your head down and up",
    kn: "ನಿಮ್ಮ ತಲೆಯನ್ನು ನಿಧಾನವಾಗಿ ಮೇಲಕ್ಕೆ ಮತ್ತು ಕೆಳಕ್ಕೆ ಅಲ್ಲಾಡಿಸಿ",
  },
};

export const ACTION_SEQUENCES: Record<ActiveChallengeAction, string[]> = {
  BLINK: ["EYES_OPEN", "EYES_CLOSED_APEX", "EYES_OPEN"],
  TURN_HEAD_LEFT: ["FRONTAL", "HEAD_TURN_LEFT", "FRONTAL"],
  TURN_HEAD_RIGHT: ["FRONTAL", "HEAD_TURN_RIGHT", "FRONTAL"],
  NOD_HEAD: ["FRONTAL", "PITCH_DOWN", "FRONTAL"],
};

/**
 * Validated actions supported by end-to-end mobile capture loop and backend validator.
 * In production, only VERIFIED_CHALLENGE_ACTIONS are issued by default to prevent client soft-locks.
 */
export const VERIFIED_CHALLENGE_ACTIONS: ActiveChallengeAction[] = ["BLINK"];
export const EXPERIMENTAL_CHALLENGE_ACTIONS: ActiveChallengeAction[] = [
  "TURN_HEAD_LEFT",
  "TURN_HEAD_RIGHT",
  "NOD_HEAD",
];

export class SessionChallengeService {
  private static challenges: Map<string, SessionChallenge> = new Map();
  private static readonly TTL_MS = 60 * 1000; // 60 seconds TTL (Invariant I-05)

  /**
   * Issues a new single-use cryptographic challenge for a verified UID
   * with randomized active liveness action binding.
   */
  static issueChallenge(
    uid: string,
    action: "enrollment" | "verification" | "step_up",
    appCheckVerified = true,
    forcedAction?: ActiveChallengeAction,
    options?: {
      clientSessionId?: string;
      attemptCount?: number;
      allowedActions?: ActiveChallengeAction[];
      enableExperimentalActions?: boolean;
    }
  ): SessionChallenge {
    if (!uid || uid.trim().length === 0) {
      throw new Error("Cannot issue challenge without a valid UID");
    }

    const challengeId = `chal_${crypto.randomBytes(16).toString("hex")}`;
    const nonce = crypto.randomBytes(32).toString("hex");
    const now = Date.now();

    const candidateActions: ActiveChallengeAction[] =
      options?.allowedActions && options.allowedActions.length > 0
        ? options.allowedActions
        : options?.enableExperimentalActions === true ||
          process.env.ENABLE_EXPERIMENTAL_CHALLENGE_ACTIONS === "true"
        ? [...VERIFIED_CHALLENGE_ACTIONS, ...EXPERIMENTAL_CHALLENGE_ACTIONS]
        : VERIFIED_CHALLENGE_ACTIONS;

    const requiredAction =
      forcedAction || candidateActions[crypto.randomInt(0, candidateActions.length)];
    const prompts = ACTION_PROMPTS[requiredAction];
    const expectedSequence = ACTION_SEQUENCES[requiredAction];

    const challenge: SessionChallenge = {
      challengeId,
      nonce,
      uid,
      action,
      requiredAction,
      expectedSequence,
      expectedFrameCount: 3,
      actionPromptEn: prompts.en,
      actionPromptKn: prompts.kn,
      clientSessionId: options?.clientSessionId,
      attemptCount: options?.attemptCount || 1,
      createdAt: now,
      expiresAt: now + this.TTL_MS,
      consumed: false,
      appCheckVerified,
    };

    this.challenges.set(challengeId, challenge);
    this.cleanExpired();

    return challenge;
  }

  /**
   * Creates a challenge returning combined token format for API endpoints.
   */
  static createChallenge(
    uid: string,
    action: string,
    forcedAction?: ActiveChallengeAction,
    options?: {
      clientSessionId?: string;
      attemptCount?: number;
      allowedActions?: ActiveChallengeAction[];
      enableExperimentalActions?: boolean;
    }
  ): {
    challengeId: string;
    nonce: string;
    token: string;
    expiresAt: number;
    action: "ENROLLMENT" | "VERIFICATION";
    requiredAction: ActiveChallengeAction;
    expectedSequence: string[];
    expectedFrameCount: number;
    actionPromptEn: string;
    actionPromptKn: string;
  } {
    const act = (action.toLowerCase() === "verification"
      ? "verification"
      : "enrollment") as "enrollment" | "verification";

    const challenge = this.issueChallenge(uid, act, true, forcedAction, options);
    const combinedToken = `${challenge.challengeId}:${challenge.nonce}`;

    return {
      challengeId: challenge.challengeId,
      nonce: combinedToken,
      token: combinedToken,
      expiresAt: challenge.expiresAt,
      action: act === "verification" ? "VERIFICATION" : "ENROLLMENT",
      requiredAction: challenge.requiredAction,
      expectedSequence: challenge.expectedSequence,
      expectedFrameCount: challenge.expectedFrameCount,
      actionPromptEn: challenge.actionPromptEn,
      actionPromptKn: challenge.actionPromptKn,
    };
  }

  /**
   * Retrieves active challenge metadata if extant and not expired.
   */
  static getChallenge(challengeId: string): SessionChallenge | undefined {
    return this.challenges.get(challengeId);
  }

  /**
   * Validates and immediately consumes a challenge nonce (Single-use, Replay-resistant).
   * Throws on invalid, expired, already-consumed, or mismatched challenge.
   */
  static validateAndConsume(
    challengeId: string,
    nonce: string,
    uid: string,
    action: string,
    observedAction?: string,
    metadata?: {
      clientSessionId?: string;
      framesCapturedAtMs?: number[];
    }
  ): SessionChallenge {
    const challenge = this.challenges.get(challengeId);

    if (!challenge) {
      throw new Error(`Invalid challenge ID: '${challengeId}'. Session does not exist or expired.`);
    }

    if (challenge.consumed) {
      throw new Error(`Replay attack detected: Challenge '${challengeId}' was already consumed.`);
    }

    if (Date.now() > challenge.expiresAt) {
      this.challenges.delete(challengeId);
      throw new Error(`Session expired: Challenge '${challengeId}' exceeded 60s TTL.`);
    }

    if (challenge.nonce !== nonce) {
      throw new Error(`Cryptographic nonce mismatch for challenge '${challengeId}'.`);
    }

    if (challenge.uid !== uid) {
      throw new Error(
        `Identity mismatch: Challenge bound to UID '${challenge.uid}', attempted by '${uid}'.`
      );
    }

    const normAction = action.toLowerCase();
    if (challenge.action !== normAction) {
      throw new Error(
        `Action mismatch: Challenge bound to '${challenge.action}', attempted '${action}'.`
      );
    }

    if (
      metadata?.clientSessionId &&
      challenge.clientSessionId &&
      metadata.clientSessionId !== challenge.clientSessionId
    ) {
      throw new Error(
        `Session binding mismatch: Challenge bound to session '${challenge.clientSessionId}', received '${metadata.clientSessionId}'.`
      );
    }

    if (metadata?.framesCapturedAtMs && Array.isArray(metadata.framesCapturedAtMs)) {
      const timestamps = metadata.framesCapturedAtMs;
      if (timestamps.length > 0) {
        // Frame sequence order check
        for (let i = 1; i < timestamps.length; i++) {
          if (timestamps[i] <= timestamps[i - 1]) {
            throw new Error(
              `Out of order frame sequence: Frame ${i} (${timestamps[i]}ms) captured before or at frame ${i - 1} (${timestamps[i - 1]}ms).`
            );
          }
        }
        // Frame freshness check: must not be captured before challenge was issued (allow 500ms client clock skew)
        // If timestamps are absolute epoch timestamps (> 1e12 ms, post-2001), verify against challenge creation and expiry
        if (timestamps[0] >= 1000000000000) {
          if (timestamps[0] < challenge.createdAt - 500) {
            throw new Error(
              `Stale frame submission: Frames captured before challenge was issued (issued at ${challenge.createdAt}, frame at ${timestamps[0]}).`
            );
          }
          // Expiry check
          if (timestamps[timestamps.length - 1] > challenge.expiresAt) {
            throw new Error(`Expired frame submission: Frames captured after challenge expired.`);
          }
        } else {
          // Relative offsets: ensure burst window does not exceed challenge TTL
          const relativeSpan = timestamps[timestamps.length - 1] - timestamps[0];
          if (relativeSpan > this.TTL_MS) {
            throw new Error(`Expired frame submission: Relative burst duration ${relativeSpan}ms exceeded challenge TTL.`);
          }
        }
      }
    }

    if (observedAction && observedAction.toUpperCase() !== challenge.requiredAction) {
      throw new Error(
        `Liveness action mismatch: Required '${challenge.requiredAction}', observed '${observedAction}'.`
      );
    }

    // Single-use: Mark consumed immediately
    challenge.consumed = true;
    challenge.consumedAt = Date.now();
    this.challenges.delete(challengeId);

    return challenge;
  }

  /**
   * Safe consumer returning boolean status for API middleware/controllers.
   */
  static consumeChallenge(
    token: string,
    uid: string,
    action: string,
    observedAction?: string,
    metadata?: { clientSessionId?: string; framesCapturedAtMs?: number[] }
  ): boolean {
    if (!token) return false;
    const normAction = action.toLowerCase();

    // Case 1: Combined token "chal_...:nonce"
    if (token.includes(":")) {
      const [cId, nVal] = token.split(":");
      try {
        this.validateAndConsume(cId, nVal, uid, normAction, observedAction, metadata);
        return true;
      } catch {
        return false;
      }
    }

    // Case 2: Matching challengeId directly
    if (this.challenges.has(token)) {
      const chal = this.challenges.get(token)!;
      try {
        this.validateAndConsume(token, chal.nonce, uid, normAction, observedAction, metadata);
        return true;
      } catch {
        return false;
      }
    }

    // Case 3: Matching nonce across challenges
    for (const [cId, chal] of this.challenges.entries()) {
      if (chal.nonce === token) {
        try {
          this.validateAndConsume(cId, token, uid, normAction, observedAction, metadata);
          return true;
        } catch {
          return false;
        }
      }
    }

    return false;
  }

  /**
   * Cleanup expired challenges.
   */
  private static cleanExpired(): void {
    const now = Date.now();
    for (const [id, chal] of this.challenges.entries()) {
      if (now > chal.expiresAt || chal.consumed) {
        this.challenges.delete(id);
      }
    }
  }

  /**
   * Clears all session challenges (testing only).
   */
  static reset(): void {
    this.challenges.clear();
  }
}
