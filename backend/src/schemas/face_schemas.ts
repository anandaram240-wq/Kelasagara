// backend/src/schemas/face_schemas.ts

export type ActiveChallengeAction =
  | "BLINK"
  | "TURN_HEAD_LEFT"
  | "TURN_HEAD_RIGHT"
  | "NOD_HEAD";

export interface ChallengeRequestDTO {
  action: "ENROLLMENT" | "VERIFICATION";
}

export interface ChallengeResponseDTO {
  challengeId?: string;
  challengeNonce: string;
  expiresAt: number;
  action: "ENROLLMENT" | "VERIFICATION";
  requiredAction?: ActiveChallengeAction;
  actionPromptEn?: string;
  actionPromptKn?: string;
  ttlSeconds: number;
  serverTimestamp: string;
}

export interface EnrollRequestDTO {
  /**
   * Base64-encoded cropped face image (112x112 RGB or raw JPEG/PNG).
   */
  imageBase64?: string;

  /**
   * Challenge-bound temporal burst frames (Gate G-02: 3-frame sequence).
   * Used for server-verifiable active liveness validation without client trust.
   */
  burstFrames?: Array<{
    sequenceIndex: number;
    capturedOffsetMs: number;
    jpegBase64: string;
  }>;

  /**
   * Authoritative 128-D Unit Hypersphere Vector from C++17 Umeyama ONNX engine.
   * Cryptographically verified against Play Integrity requestHash.
   */
  probeVector?: number[];

  /**
   * User role in Kelasagara ('worker' or 'hirer').
   */
  role: "worker" | "hirer";

  /**
   * Single-use cryptographic challenge nonce (Invariant I-04, I-05).
   */
  challengeNonce?: string;

  /**
   * Unique client session ID to prevent replay / concurrency issues.
   */
  clientSessionId?: string;

  /**
   * Google Play Integrity or hardware attestation token (GAP-01 / Invariant I-26).
   */
  integrityToken?: string;

  /**
   * Cryptographic requestHash computed by client: SHA-256(nonce || uid || action || captureDigest)
   */
  requestHash?: string;

  /**
   * Non-authoritative client liveness metadata.
   */
  livenessAudit?: {
    blinkVerified?: boolean;
    headEulerYaw?: number;
    headEulerRoll?: number;
    method?: string;
    timestamp?: string;
    [key: string]: any;
  };
}

export interface VerifyLoginRequestDTO {
  /**
   * Base64-encoded cropped face image for 1:1 neural verification.
   */
  imageBase64: string;
  role: "worker" | "hirer";
  challengeNonce?: string;

  /**
   * Google Play Integrity or hardware attestation token (GAP-01 / Invariant I-26).
   */
  integrityToken?: string;

  /**
   * Cryptographic requestHash computed by client: SHA-256(nonce || uid || action || captureDigest)
   */
  requestHash?: string;
}

export interface ReVerifyRequestDTO {
  imageBase64: string;
  deviceId: string;
  latitude?: number;
  longitude?: number;
  isMockGps?: boolean;
  challengeNonce?: string;
}

export interface LivenessVerifyRequestDTO {
  challengeId: string;
  frames: Array<{
    timestampMs: number;
    leftEyeUpper?: { x: number; y: number };
    leftEyeLower?: { x: number; y: number };
    rightEyeUpper?: { x: number; y: number };
    rightEyeLower?: { x: number; y: number };
    leftMouthCorner?: { x: number; y: number };
    rightMouthCorner?: { x: number; y: number };
    upperLip?: { x: number; y: number };
    lowerLip?: { x: number; y: number };
    noseTip?: { x: number; y: number };
    yawDegrees?: number;
    pitchDegrees?: number;
  }>;
}

export interface DeviceAttestationRequestDTO {
  attestationToken?: string;
  deviceId?: string;
}

export interface BiometricDecisionResponse {
  status:
    | "approved"
    | "duplicate"
    | "ambiguity"
    | "pending_review"
    | "technical_failure_retry"
    | "rejected"
    | "error"
    | "screening_unavailable"
    | "quality_rejected";
  isApproved: boolean;
  isDuplicate: boolean;
  isHardBlock?: boolean;
  matchedUid?: string;
  maskedPhone?: string;
  maskedName?: string;
  /** KLS-{masked_uid}-{last4_phone} — DPDPA 2023 §8(3) compliant masked display ID (only populated after authorized ownership proof) */
  maskedUserId?: string;
  /** Integer 0–100 similarity percentage for display (only after authorized ownership proof) */
  similarityPercent?: number;
  similarity: number;
  threshold: number;
  accountStatus?: string;
  recoverySessionId?: string;
  message: string;
  messageKn?: string;
}

export interface UniformBiometricApiResponse<T = any> {
  success: boolean;
  status: string;
  data?: T;
  error?: {
    code: string;
    message: string;
  };
  serverTimestamp: string;
}
