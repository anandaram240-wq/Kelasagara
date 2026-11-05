// backend/src/schemas/data_architecture_schemas.ts
/**
 * Authoritative Firestore Document Schemas and State Types for BioMatch V7.
 * Conforms to ADR-001 (Sole Persistent Database: Cloud Firestore asia-south1).
 */

export type BiometricEnrollmentState =
  | "INITIAL"
  | "PENDING_FACE"
  | "CHALLENGE_ISSUED"
  | "IN_PROGRESS"
  | "QUALITY_REJECTED"
  | "SCREENING_UNAVAILABLE"
  | "POTENTIAL_DUPLICATE"
  | "PENDING_REVIEW"
  | "ENROLLED"
  | "ACTIVE"
  | "REJECTED_DUPLICATE"
  | "TECHNICAL_FAILURE_RETRY";

export type BiometricAuditEventType =
  | "DUPLICATE_REGISTRATION_INTERCEPTED"
  | "ENROLLMENT_AMBIGUITY_FLAGGED"
  | "ENROLLMENT_SUCCESS"
  | "ENROLLMENT_HELD_RESEARCH_MODEL"
  | "TECHNICAL_FAILURE_RECORDED"
  | "BIOMETRIC_LOGIN_SUCCESS"
  | "BIOMETRIC_LOGIN_FAILED"
  | "TEMPLATE_DELETED"
  | "STATE_RECONCILIATION_FLAGGED"
  | "CHALLENGE_NONCE_ISSUED"
  | "CHALLENGE_NONCE_VERIFIED"
  | "CONSENT_V2_GRANTED"
  | "CONSENT_V2_WITHDRAWN"
  | "CROSS_ACCOUNT_HARD_BLOCK"
  | "CROSS_ACCOUNT_FLAG"
  | "COMPLIANCE_OFFICER_PROOF_ISSUED"
  | "DUAL_ROLE_LINKED_SUCCESS"
  | "SCREENING_UNAVAILABLE_FLAGGED"
  | "CAPTURE_QUALITY_REJECTED"
  | "ACTIVE_CHALLENGE_VERIFIED"
  | "TEMPORAL_BURST_LIVENESS_VERIFIED"
  | "UNVERIFIED_SINGLE_FRAME_LIVENESS_RECORDED"
  | "RECOVERY_SESSION_ISSUED";

/**
 * Schema for /biometric_consent/{userId} (Ticket T-07: Consent V2)
 * Compliant with DPDPA 2023 Section 6(1) & 6(2) Granular Notice & Consent.
 */
export interface BiometricConsentV2Doc {
  consentId: string;
  userId: string;
  version: "v2.0";
  purposes: {
    verification: boolean; // Voluntary 1:N duplicate prevention and 1:1 authentication
    research: boolean;     // Opt-in algorithm calibration & shadow benchmarking (default false)
  };
  language: "kn" | "en";
  timestamp: string; // ISO 8601
  appVersion: string;
  withdrawnAt?: string | null;
  counselReviewNotice: "FOR COUNSEL REVIEW - DPDPA 2023 COMPLIANT DRAFT";
}

/**
 * Schema for /biometric_vault/{uid}
 * Access restricted: Client access completely denied via firestore.rules.
 * Only accessible via Server Admin SDK with service account credentials.
 */
export interface BiometricVaultDoc {
  uid: string;
  phoneNumber: string;
  phoneNumberMasked: string;
  role: "worker" | "hirer";
  embedding: number[]; // Stored as admin.firestore.FieldValue.vector in Firestore
  embeddingDim: number;
  modelVersion: string;
  tier: "RESEARCH_ONLY" | "PRODUCTION_CLEARED";
  enrolledAt: any; // Firestore Timestamp
  updatedAt: any; // Firestore Timestamp
  livenessAudit: {
    blinkVerified?: boolean;
    headEulerYaw?: number;
    headEulerRoll?: number;
    method?: string;
    timestamp?: string;
    challengeNonce?: string;
    [key: string]: any;
  };
  requiresReview: boolean;
  serviceVersion: string;
  salt: string; // Per-subject salt for template hashing/envelope encryption
  integrityHash: string; // SHA-256 integrity hash of template fields
}

/**
 * Schema for /biometric_audit_logs/{eventId}
 * Tamper-evident hash-chained append-only ledger (Invariant I-17).
 */
export interface BiometricAuditLogDoc {
  eventId: string;
  sequenceNumber: number;
  previousLogHash: string;
  currentLogHash: string;
  timestamp: any; // Firestore Timestamp / ISO String
  eventType: BiometricAuditEventType;
  uid: string;
  matchedUid?: string;
  attemptingPhone?: string;
  similarityScore?: number;
  threshold?: number;
  service: string;
  version: string;
  metadata?: Record<string, any>;
}

/**
 * Schema for /biometric_rate_limits/{uid}
 * Enforces sliding window daily attempt limits (Max 3 attempts per 24 hours).
 */
export interface BiometricRateLimitDoc {
  uid: string;
  attempts24h: number;
  firstAttemptTimestamp: number;
  lastAttemptTimestamp: number;
  lockoutUntil?: number;
}

/**
 * Schema for /biometric_enrollment_sessions/{uid}
 * Concurrency reservation session for pending-inclusive duplicate search (ADR-001).
 */
export interface BiometricEnrollmentSessionDoc {
  sessionId: string;
  uid: string;
  status: "PENDING" | "PROCESSING" | "COMPLETED" | "FAILED" | "EXPIRED";
  probeVector: number[];
  clientSessionId: string;
  createdAt: number;
  expiresAt: number;
  leaseExpiresAt: number;
  sequenceNumber: number;
}

/**
 * Partial schema for biometric fields in /users/{uid}
 */
export interface UserBiometricFields {
  accountStatus:
    | "initial"
    | "pending_face"
    | "pending_review"
    | "approved"
    | "rejected_duplicate"
    | "suspended";
  faceVerified: boolean;
  faceVerifiedAt?: any;
  verificationStatus: "none" | "pending_manual_review" | "face_done";
  faceVerificationMethod?: string;
  biometricEnrollmentState: BiometricEnrollmentState;
  updatedAt: any;
}
