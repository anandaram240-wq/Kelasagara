// FILE: backend/src/biometrics/human_review_workflow_service_v10.ts

import crypto from "crypto";

export type ReviewDecisionOutcome =
  | "APPROVE_AS_DISTINCT_PERSON"
  | "CONFIRM_DUPLICATE_ROUTE_TO_RECOVERY"
  | "REQUEST_FRESH_RECAPTURE";

export type CaseLifecycleStatus =
  | "CREATED"
  | "OWNERSHIP_VERIFICATION_PENDING"
  | "VERIFIED"
  | "UNDER_REVIEW"
  | "RESOLVED"
  | "EXPIRED"
  | "CANCELLED"
  | "REJECTED";

export interface MaskedCandidateEvidence {
  maskedCandidateUid: string;
  maskedCandidateName: string;
  maskedCandidatePhone: string;
  candidateRole: string;
  stage1CosineScore: number;
  stage2CosineScore: number | null;
  modelIdentifier: string;
}

export interface BiometricHumanReviewCase {
  caseId: string;
  caseReference?: string;
  caseReferenceHash?: string;
  applicantUid: string;
  status: "OPEN_PENDING_REVIEW" | "RESOLVED_APPROVED" | "RESOLVED_DUPLICATE" | "RECAPTURE_REQUIRED" | CaseLifecycleStatus;
  lifecycleStatus?: CaseLifecycleStatus;
  existingAccountLocked: false; // IMMUTABLE SAFETY RULE: Never lock the existing matched worker!
  candidateEvidence: MaskedCandidateEvidence;
  applicantEmbedding: number[];
  createdAtIso: string;
  createdAtMs?: number;
  expiresAtMs?: number;
  resolvedAtIso: string | null;
  resolvedByReviewerId: string | null;
  decisionOutcome: ReviewDecisionOutcome | null;
  decisionNotes: string | null;
  auditLogHash: string | null;
  ownershipVerified?: boolean;
  ownershipVerifiedAtMs?: number | null;
  ownershipVerificationMethod?: string | null;
}

export interface ReviewAuditLogEntry {
  auditId: string;
  caseId: string;
  applicantUid: string;
  reviewerId: string;
  decisionOutcome: ReviewDecisionOutcome;
  justification: string;
  previousChainHash: string;
  entryHash: string;
  timestampIso: string;
}

export interface PublicCaseStatusView {
  valid: boolean;
  status?: CaseLifecycleStatus | string;
  expiresAtMs?: number;
  nextStep?: string;
  error?: string;
}

export class HumanReviewWorkflowServiceV10 {
  public static readonly CASE_REFERENCE_PREFIX = "CASE-";
  public static readonly CASE_REFERENCE_HEX_LENGTH = 32;
  public static readonly CASE_REFERENCE_TOTAL_LENGTH = 37; // "CASE-" (5) + 32 hex chars
  public static readonly DEFAULT_CASE_TTL_MS = 30 * 24 * 60 * 60 * 1000; // 30 days
  public static readonly RATE_LIMIT_WINDOW_MS = 60 * 1000; // 1 minute
  public static readonly MAX_LOOKUPS_PER_WINDOW = 10;

  private readonly cases = new Map<string, BiometricHumanReviewCase>();
  private readonly caseHashIndex = new Map<string, string>(); // caseReferenceHash -> caseId
  private readonly auditLedger: ReviewAuditLogEntry[] = [];
  private readonly lookupRateLimiter = new Map<string, number[]>(); // clientIp -> timestamps

  public static maskUid(uid: string): string {
    const clean = uid.trim();
    return clean.length <= 4 ? `KS-••••-${clean}` : `KS-••••-${clean.slice(-4).toUpperCase()}`;
  }

  public static maskName(name: string): string {
    return name
      .trim()
      .split(/\s+/)
      .map((part) => (part.length <= 2 ? `${part[0] ?? "U"}•` : `${part.slice(0, 2)}•••`))
      .join(" ");
  }

  public static maskPhone(phone: string): string {
    const digits = phone.replace(/\D/g, "");
    return digits.length < 4 ? "+91 ••••••0000" : `+91 ••••••${digits.slice(-4)}`;
  }

  /**
   * Generates a 128-bit cryptographically secure case reference and its SHA-256 hash.
   * Format: CASE- followed by 32 uppercase hexadecimal characters.
   */
  public static generate128BitCaseReference(): { caseReference: string; caseReferenceHash: string } {
    const hex = crypto.randomBytes(16).toString("hex").toUpperCase();
    const caseReference = `${HumanReviewWorkflowServiceV10.CASE_REFERENCE_PREFIX}${hex}`;
    const caseReferenceHash = crypto.createHash("sha256").update(caseReference).digest("hex");
    return { caseReference, caseReferenceHash };
  }

  /**
   * Validates case reference format: must start with CASE-, exactly 37 characters, uppercase hex only.
   */
  public static validateCaseReferenceFormat(caseReference: string): boolean {
    if (!caseReference || typeof caseReference !== "string") {
      return false;
    }
    if (caseReference.length !== HumanReviewWorkflowServiceV10.CASE_REFERENCE_TOTAL_LENGTH) {
      return false;
    }
    if (!caseReference.startsWith(HumanReviewWorkflowServiceV10.CASE_REFERENCE_PREFIX)) {
      return false;
    }
    const hexPart = caseReference.substring(HumanReviewWorkflowServiceV10.CASE_REFERENCE_PREFIX.length);
    return /^[0-9A-F]{32}$/.test(hexPart);
  }

  /**
   * Computes SHA-256 hash of a case reference for constant-time / blind lookup.
   */
  public static hashCaseReference(caseReference: string): string {
    return crypto.createHash("sha256").update(caseReference).digest("hex");
  }

  /**
   * 1. Opens a new Human Review case with 128-bit reference entropy.
   */
  public openReviewCase(params: {
    applicantUid: string;
    matchedCandidateUid: string;
    matchedCandidateName: string;
    matchedCandidatePhone: string;
    matchedCandidateRole: string;
    stage1CosineScore: number;
    stage2CosineScore: number | null;
    applicantEmbedding: number[];
    nowMs?: number;
  }): BiometricHumanReviewCase {
    if (params.applicantUid === params.matchedCandidateUid) {
      throw new Error("ERR_SELF_COLLISION_IN_REVIEW: Applicant cannot be queued against own UID.");
    }

    const { caseReference, caseReferenceHash } = HumanReviewWorkflowServiceV10.generate128BitCaseReference();
    const caseId = caseReference;
    const nowMs = params.nowMs ?? Date.now();
    const createdAtIso = new Date(nowMs).toISOString();

    const reviewCase: BiometricHumanReviewCase = {
      caseId,
      caseReference,
      caseReferenceHash,
      applicantUid: params.applicantUid,
      status: "OPEN_PENDING_REVIEW",
      lifecycleStatus: "CREATED",
      existingAccountLocked: false, // Enforces Gate 1/8 safety invariant
      candidateEvidence: {
        maskedCandidateUid: HumanReviewWorkflowServiceV10.maskUid(params.matchedCandidateUid),
        maskedCandidateName: HumanReviewWorkflowServiceV10.maskName(params.matchedCandidateName),
        maskedCandidatePhone: HumanReviewWorkflowServiceV10.maskPhone(params.matchedCandidatePhone),
        candidateRole: params.matchedCandidateRole,
        stage1CosineScore: Number(params.stage1CosineScore.toFixed(4)),
        stage2CosineScore:
          params.stage2CosineScore != null
            ? Number(params.stage2CosineScore.toFixed(4))
            : null,
        modelIdentifier: "sface_opencv_zoo_v1_primary",
      },
      applicantEmbedding: params.applicantEmbedding,
      createdAtIso,
      createdAtMs: nowMs,
      expiresAtMs: nowMs + HumanReviewWorkflowServiceV10.DEFAULT_CASE_TTL_MS,
      resolvedAtIso: null,
      resolvedByReviewerId: null,
      decisionOutcome: null,
      decisionNotes: null,
      auditLogHash: null,
      ownershipVerified: false,
      ownershipVerifiedAtMs: null,
      ownershipVerificationMethod: null,
    };

    this.cases.set(caseId, reviewCase);
    this.caseHashIndex.set(caseReferenceHash, caseId);
    return reviewCase;
  }

  /**
   * Transitions a case through the formal lifecycle state machine.
   * CREATED -> OWNERSHIP_VERIFICATION_PENDING -> VERIFIED -> UNDER_REVIEW -> RESOLVED
   * Terminal states: EXPIRED, CANCELLED, REJECTED
   */
  public transitionLifecycle(params: {
    caseId: string;
    targetStatus: CaseLifecycleStatus;
    actorUid: string;
    actorRole: "SYSTEM" | "USER" | "BIOMETRIC_AUDITOR" | "TRUST_AND_SAFETY_ADMIN";
    verificationDetails?: {
      method: "SMS_OTP" | "AADHAAR_OFFLINE_XML" | "GOVERNMENT_ID" | "MANUAL_CALL";
      verifiedAtMs: number;
    };
    nowMs?: number;
  }): BiometricHumanReviewCase {
    const existing = this.cases.get(params.caseId);
    if (!existing) {
      throw new Error(`ERR_REVIEW_CASE_NOT_FOUND: ${params.caseId}`);
    }

    const currentStatus = existing.lifecycleStatus ?? "CREATED";
    const nowMs = params.nowMs ?? Date.now();

    // Check expiration
    if (existing.expiresAtMs && nowMs > existing.expiresAtMs && currentStatus !== "EXPIRED") {
      existing.lifecycleStatus = "EXPIRED";
      existing.status = "EXPIRED";
      if (params.targetStatus !== "EXPIRED") {
        throw new Error(`ERR_CASE_EXPIRED: Case ${params.caseId} expired at ${existing.expiresAtMs}`);
      }
      return existing;
    }

    // Terminal states cannot transition further
    if (["RESOLVED", "EXPIRED", "CANCELLED", "REJECTED"].includes(currentStatus)) {
      throw new Error(`ERR_ILLEGAL_STATE_TRANSITION: Case is in terminal state ${currentStatus}`);
    }

    // Validate valid transitions
    const validTransitions: Record<CaseLifecycleStatus, CaseLifecycleStatus[]> = {
      CREATED: ["OWNERSHIP_VERIFICATION_PENDING", "CANCELLED", "EXPIRED"],
      OWNERSHIP_VERIFICATION_PENDING: ["VERIFIED", "CANCELLED", "EXPIRED"],
      VERIFIED: ["UNDER_REVIEW", "CANCELLED", "EXPIRED"],
      UNDER_REVIEW: ["RESOLVED", "REJECTED", "CANCELLED", "EXPIRED"],
      RESOLVED: [],
      EXPIRED: [],
      CANCELLED: [],
      REJECTED: [],
    };

    const allowed = validTransitions[currentStatus] || [];
    if (!allowed.includes(params.targetStatus)) {
      throw new Error(
        `ERR_ILLEGAL_STATE_TRANSITION: Cannot transition from ${currentStatus} to ${params.targetStatus}`
      );
    }

    // Ownership verification guard: cannot transition to VERIFIED without verification details
    if (params.targetStatus === "VERIFIED") {
      if (!params.verificationDetails) {
        throw new Error("ERR_OWNERSHIP_VERIFICATION_REQUIRED: Cannot transition to VERIFIED without verification details.");
      }
      existing.ownershipVerified = true;
      existing.ownershipVerifiedAtMs = params.verificationDetails.verifiedAtMs;
      existing.ownershipVerificationMethod = params.verificationDetails.method;
    }

    // Guard: cannot resolve without verified ownership
    if (params.targetStatus === "RESOLVED" && !existing.ownershipVerified) {
      throw new Error("ERR_OWNERSHIP_NOT_VERIFIED: Cannot resolve case without prior ownership verification.");
    }

    existing.lifecycleStatus = params.targetStatus;
    return existing;
  }

  /**
   * Public, rate-limited, generic case lookup that returns zero PII.
   * Rate limited to max 10 requests per minute per identifier/IP.
   */
  public safePublicLookup(params: {
    caseReferenceOrHash: string;
    clientId: string; // IP address or client session identifier
    nowMs?: number;
  }): PublicCaseStatusView {
    const nowMs = params.nowMs ?? Date.now();

    // 1. Rate Limiting Check
    const history = this.lookupRateLimiter.get(params.clientId) || [];
    const validWindow = history.filter((ts) => nowMs - ts < HumanReviewWorkflowServiceV10.RATE_LIMIT_WINDOW_MS);
    if (validWindow.length >= HumanReviewWorkflowServiceV10.MAX_LOOKUPS_PER_WINDOW) {
      return {
        valid: false,
        error: "ERR_RATE_LIMIT_EXCEEDED: Too many lookups. Please retry after 1 minute.",
      };
    }
    validWindow.push(nowMs);
    this.lookupRateLimiter.set(params.clientId, validWindow);

    // 2. Validate input and resolve case
    let targetCaseId: string | undefined;
    const input = params.caseReferenceOrHash.trim();

    if (HumanReviewWorkflowServiceV10.validateCaseReferenceFormat(input)) {
      targetCaseId = input;
    } else if (/^[0-9a-fA-F]{64}$/.test(input)) {
      targetCaseId = this.caseHashIndex.get(input.toLowerCase());
    } else {
      // Return generic not found to avoid leaking format expectations
      return {
        valid: false,
        error: "CASE_NOT_FOUND_OR_INVALID",
      };
    }

    const reviewCase = targetCaseId ? this.cases.get(targetCaseId) : undefined;
    if (!reviewCase) {
      return {
        valid: false,
        error: "CASE_NOT_FOUND_OR_EXPIRED",
      };
    }

    // Check expiration
    if (reviewCase.expiresAtMs && nowMs > reviewCase.expiresAtMs) {
      reviewCase.lifecycleStatus = "EXPIRED";
      reviewCase.status = "EXPIRED";
      return {
        valid: false,
        error: "CASE_EXPIRED",
      };
    }

    // Determine next step string based on status
    let nextStep = "Case is currently being processed.";
    const status = reviewCase.lifecycleStatus ?? reviewCase.status;
    if (status === "CREATED" || status === "OWNERSHIP_VERIFICATION_PENDING") {
      nextStep = "Please complete phone/identity verification to proceed with review.";
    } else if (status === "VERIFIED" || status === "UNDER_REVIEW" || status === "OPEN_PENDING_REVIEW") {
      nextStep = "Your case is under review by biometric trust & safety specialists.";
    } else if (status === "RESOLVED" || status === "RESOLVED_APPROVED") {
      nextStep = "Review completed. You may now log in or complete enrollment.";
    } else if (status === "RESOLVED_DUPLICATE") {
      nextStep = "Duplicate confirmed. Please log in using your registered phone number.";
    }

    // Return strictly non-PII status
    return {
      valid: true,
      status,
      expiresAtMs: reviewCase.expiresAtMs,
      nextStep,
    };
  }

  /**
   * 2. Operationally resolves an open review case by an authorized human reviewer
   *    and appends a tamper-evident hash-chained audit entry.
   */
  public adjudicateCase(params: {
    caseId: string;
    reviewerId: string;
    reviewerRole: "BIOMETRIC_AUDITOR" | "TRUST_AND_SAFETY_ADMIN";
    decision: ReviewDecisionOutcome;
    justification: string;
    nowMs?: number;
  }): {
    updatedCase: BiometricHumanReviewCase;
    auditEntry: ReviewAuditLogEntry;
    applicantNextState: {
      faceVerified: boolean;
      accountStatus: "approved" | "recovery_required" | "pending_face";
      biometricLockToken: string | null;
    };
  } {
    const existing = this.cases.get(params.caseId);
    if (!existing) {
      throw new Error(`ERR_REVIEW_CASE_NOT_FOUND: ${params.caseId}`);
    }

    if (params.reviewerRole !== "BIOMETRIC_AUDITOR" && params.reviewerRole !== "TRUST_AND_SAFETY_ADMIN") {
      throw new Error(`ERR_UNAUTHORIZED_REVIEWER_ROLE: Role ${params.reviewerRole} is not authorized to adjudicate biometric cases.`);
    }

    const nowMs = params.nowMs ?? Date.now();
    if (existing.expiresAtMs && nowMs > existing.expiresAtMs) {
      existing.lifecycleStatus = "EXPIRED";
      existing.status = "EXPIRED";
      throw new Error(`ERR_CASE_EXPIRED: Case ${params.caseId} has expired.`);
    }

    if (
      existing.status !== "OPEN_PENDING_REVIEW" &&
      existing.lifecycleStatus !== "UNDER_REVIEW" &&
      existing.lifecycleStatus !== "VERIFIED"
    ) {
      throw new Error(`ERR_CASE_ALREADY_RESOLVED: Case ${params.caseId} is ${existing.status}`);
    }
    if (params.justification.trim().length < 10) {
      throw new Error("ERR_AUDIT_JUSTIFICATION_TOO_SHORT: Minimum 10 characters required.");
    }

    const timestampIso = new Date(nowMs).toISOString();
    const prevHash =
      this.auditLedger.length > 0
        ? this.auditLedger[this.auditLedger.length - 1].entryHash
        : "GENESIS_HASH_KS_V10";

    const payloadToHash = `${params.caseId}|${existing.applicantUid}|${params.reviewerId}|${params.decision}|${params.justification.trim()}|${prevHash}|${timestampIso}`;
    const entryHash = crypto.createHash("sha256").update(payloadToHash).digest("hex");

    const auditEntry: ReviewAuditLogEntry = {
      auditId: `AUD_${crypto.randomBytes(5).toString("hex").toUpperCase()}`,
      caseId: params.caseId,
      applicantUid: existing.applicantUid,
      reviewerId: params.reviewerId,
      decisionOutcome: params.decision,
      justification: params.justification.trim(),
      previousChainHash: prevHash,
      entryHash,
      timestampIso,
    };

    this.auditLedger.push(auditEntry);

    if (params.decision === "APPROVE_AS_DISTINCT_PERSON") {
      existing.status = "RESOLVED_APPROVED";
      existing.lifecycleStatus = "RESOLVED";
    } else if (params.decision === "CONFIRM_DUPLICATE_ROUTE_TO_RECOVERY") {
      existing.status = "RESOLVED_DUPLICATE";
      existing.lifecycleStatus = "RESOLVED";
    } else {
      existing.status = "RECAPTURE_REQUIRED";
      existing.lifecycleStatus = "RESOLVED";
    }

    existing.resolvedAtIso = timestampIso;
    existing.resolvedByReviewerId = params.reviewerId;
    existing.decisionOutcome = params.decision;
    existing.decisionNotes = params.justification.trim();
    existing.auditLogHash = entryHash;

    const lockToken =
      params.decision === "APPROVE_AS_DISTINCT_PERSON"
        ? `KS_FTOK_${entryHash.slice(0, 16).toUpperCase()}`
        : null;

    return {
      updatedCase: existing,
      auditEntry,
      applicantNextState: {
        faceVerified: params.decision === "APPROVE_AS_DISTINCT_PERSON",
        accountStatus:
          params.decision === "APPROVE_AS_DISTINCT_PERSON"
            ? "approved"
            : params.decision === "CONFIRM_DUPLICATE_ROUTE_TO_RECOVERY"
            ? "recovery_required"
            : "pending_face",
        biometricLockToken: lockToken,
      },
    };
  }

  /**
   * 3. Verifies the cryptographic integrity of the entire audit chain.
   */
  public verifyAuditChainIntegrity(): boolean {
    let expectedPrev = "GENESIS_HASH_KS_V10";
    for (const entry of this.auditLedger) {
      if (entry.previousChainHash !== expectedPrev) return false;
      const recomputed = crypto
        .createHash("sha256")
        .update(
          `${entry.caseId}|${entry.applicantUid}|${entry.reviewerId}|${entry.decisionOutcome}|${entry.justification}|${entry.previousChainHash}|${entry.timestampIso}`
        )
        .digest("hex");
      if (recomputed !== entry.entryHash) return false;
      expectedPrev = entry.entryHash;
    }
    return true;
  }

  /**
   * Clears rate limit state (useful in test harnesses).
   */
  public resetRateLimits(): void {
    this.lookupRateLimiter.clear();
  }
}
