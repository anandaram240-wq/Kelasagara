// backend/src/routes/face_routes.ts
import crypto from "crypto";
import { Router, Response, Request, NextFunction } from "express";
import { AuthenticatedRequest, authenticateFirebaseToken } from "../auth/firebase_auth";
import {
  EnrollRequestDTO,
  VerifyLoginRequestDTO,
  ChallengeRequestDTO,
  ChallengeResponseDTO,
  UniformBiometricApiResponse,
  ReVerifyRequestDTO,
  LivenessVerifyRequestDTO,
  DeviceAttestationRequestDTO,
} from "../schemas/face_schemas";
import { BiometricEnrollmentService } from "../services/biometric_enrollment";
import { FirestoreBiometricRepository } from "../services/firestore_biometric_repository";
import { runFaceInference } from "../services/face_inference";
import { decodeBase64Image, PREPROCESSING_ID } from "../services/face_preprocessing";
import { cosineSimilarity, l2Normalize, maskPhoneNumber, maskedDisplayId } from "../services/biometric_matching";
import { AuditService } from "../services/audit_service";
import { SessionChallengeService } from "../services/session_challenge_service";
import { DeviceAttestationService } from "../services/device_attestation";
import { AccountLifecycleService } from "../services/account_lifecycle";
import { PresentationAttackDefenseService } from "../services/presentation_attack_defense";
import { InMemoryBiometricIndex } from "../services/in_memory_biometric_index";
import { TemplatePrivacyService } from "../services/template_privacy";
import { config } from "../config";
import {
  ChallengeBurstPadService,
  ChallengePurpose,
  BurstFrameItem,
  FrameAnalyzerAdapter,
} from "../services/challenge_burst_pad_service";
import { MediaPipeFaceLandmarkerOnnx } from "../services/mediapipe_face_landmarker_onnx";
import { FaceInferenceService } from "../services/face_inference";
import {
  BiometricEnvelopeEncryptionService,
  KmsEnvelopeEncryptionService,
} from "../services/kms_envelope_encryption";
import {
  CaptureQualityCandidateConfig,
  computeValidatedCosineSimilarity,
} from "../biometrics/canonical_pipeline";

import admin from "firebase-admin";

export const faceRouter = Router();

// Constant-time padding to resist timing oracle side-channels (Invariant I-08, I-23)
const MIN_ENROLL_LATENCY_MS = 150;

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// Simple in-memory per-IP rate limiter (Tier 0 / Spark protection)
const ipRateLimitMap = new Map<string, { count: number; resetAt: number }>();

function ipRateLimiter(req: Request, res: Response, next: NextFunction): void {
  const ip = req.ip || req.socket.remoteAddress || "unknown_ip";
  const now = Date.now();
  const windowMs = 60 * 1000; // 1 minute
  const maxReqPerMinute = 60;

  const current = ipRateLimitMap.get(ip);
  if (!current || now > current.resetAt) {
    ipRateLimitMap.set(ip, { count: 1, resetAt: now + windowMs });
    return next();
  }

  if (current.count >= maxReqPerMinute) {
    res.status(429).json({
      success: false,
      status: "rate_limited",
      error: {
        code: "RATE_LIMIT_EXCEEDED",
        message: "Too many biometric requests from this IP. Please try again in 1 minute.",
      },
      serverTimestamp: new Date().toISOString(),
    } as UniformBiometricApiResponse);
    return;
  }

  current.count += 1;
  next();
}

faceRouter.use(ipRateLimiter);

/**
 * Forbidden client-supplied vector fields (Ticket T-01, fixes D1).
 * The server executes authoritative neural inference from raw image frames only.
 * Client probe vectors, embeddings, or landmark arrays are strictly rejected.
 */
export const FORBIDDEN_VECTOR_FIELDS = [
  "embedding",
  "probe",
  "probeVector",
  "landmarks",
  "vector",
];

export function checkForbiddenVectorFields(req: Request, res: Response, next: NextFunction): void {
  if (req.body && typeof req.body === "object") {
    for (const field of FORBIDDEN_VECTOR_FIELDS) {
      if (field in req.body) {
        res.status(400).json({
          success: false,
          status: "client_vectors_forbidden",
          error: {
            code: "CLIENT_VECTORS_FORBIDDEN",
            message: `Field '${field}' is strictly forbidden (Ticket T-01). Server runs authoritative inference on imageBase64 only.`,
          },
          serverTimestamp: new Date().toISOString(),
        } as UniformBiometricApiResponse);
        return;
      }
    }
  }
  next();
}

/**
 * GET /api/biometrics/health
 * Public health & telemetry probe.
 */
faceRouter.get("/health", (_req, res: Response) => {
  res.status(200).json({
    success: true,
    status: "healthy",
    data: {
      service: "kelasagara-biomatch-backend",
      modelVersion: config.modelVersion,
      tier: "RESEARCH_ONLY",
      releaseGate: "CONTROLLED_TEST_BUILD",
      thresholdTier: config.thresholdTier,
      verificationThreshold: config.verificationThreshold,
      duplicateThreshold: config.duplicateThreshold,
      hardBlockThreshold: config.hardBlockThreshold,
      isProductionCalibrated: config.isProductionCalibrated,
      database: "Cloud Firestore Asia-South1 Only",
    },
    serverTimestamp: new Date().toISOString(),
  } as UniformBiometricApiResponse);
});

/**
 * POST /api/biometrics/challenge
 * Issues a short-TTL (60s) cryptographic nonce bound to caller UID and action (Invariant I-04).
 */
faceRouter.post(
  "/challenge",
  authenticateFirebaseToken,
  async (req: AuthenticatedRequest, res: Response): Promise<void> => {
    try {
      const uid = req.user!.uid;
      const dto = req.body as ChallengeRequestDTO;

      if (!dto.action || !["ENROLLMENT", "VERIFICATION"].includes(dto.action)) {
        res.status(400).json({
          success: false,
          status: "invalid_argument",
          error: {
            code: "INVALID_ACTION",
            message: "Field 'action' must be 'ENROLLMENT' or 'VERIFICATION'.",
          },
          serverTimestamp: new Date().toISOString(),
        } as UniformBiometricApiResponse);
        return;
      }

      const challenge = SessionChallengeService.createChallenge(uid, dto.action);

      await AuditService.logEvent({
        eventType: "CHALLENGE_NONCE_ISSUED",
        uid,
        metadata: {
          action: dto.action,
          expiresAt: challenge.expiresAt,
          requiredAction: challenge.requiredAction,
        },
      });

      const responseData: ChallengeResponseDTO = {
        challengeId: challenge.challengeId,
        challengeNonce: challenge.nonce,
        expiresAt: challenge.expiresAt,
        action: challenge.action,
        requiredAction: challenge.requiredAction,
        actionPromptEn: challenge.actionPromptEn,
        actionPromptKn: challenge.actionPromptKn,
        ttlSeconds: 60,
        serverTimestamp: new Date().toISOString(),
      };

      res.status(200).json({
        success: true,
        status: "challenge_issued",
        data: responseData,
        serverTimestamp: new Date().toISOString(),
      } as UniformBiometricApiResponse<ChallengeResponseDTO>);
    } catch (err: any) {
      console.error("[FaceRoutes] /challenge error:", err);
      res.status(500).json({
        success: false,
        status: "internal_error",
        error: {
          code: "CHALLENGE_ERROR",
          message: err.message || "Failed to issue session challenge nonce.",
        },
        serverTimestamp: new Date().toISOString(),
      } as UniformBiometricApiResponse);
    }
  }
);

/**
 * POST /api/biometrics/enroll
 * Server-side face enrollment with 1:N duplicate interception and challenge validation.
 */
faceRouter.post(
  "/enroll",
  authenticateFirebaseToken,
  checkForbiddenVectorFields,
  async (req: AuthenticatedRequest, res: Response): Promise<void> => {
    const startTime = Date.now();
    try {
      const uid = req.user!.uid;
      const dto = req.body as EnrollRequestDTO;

      // Allow burstFrames to populate baseline imageBase64 for temporal submissions
      if (!dto.imageBase64 && dto.burstFrames && Array.isArray(dto.burstFrames) && dto.burstFrames.length > 0) {
        dto.imageBase64 = dto.burstFrames[0].jpegBase64;
      }

      if (!dto.imageBase64 || typeof dto.imageBase64 !== "string" || dto.imageBase64.trim().length === 0) {
        res.status(400).json({
          success: false,
          status: "invalid_argument",
          error: {
            code: "MISSING_IMAGE_BASE64",
            message: "Field 'imageBase64' is required for authoritative face inference.",
          },
          serverTimestamp: new Date().toISOString(),
        } as UniformBiometricApiResponse);
        return;
      }

      if (!dto.role || !["worker", "hirer"].includes(dto.role)) {
        res.status(400).json({
          success: false,
          status: "invalid_argument",
          error: {
            code: "INVALID_ROLE",
            message: "Field 'role' must be either 'worker' or 'hirer'.",
          },
          serverTimestamp: new Date().toISOString(),
        } as UniformBiometricApiResponse);
        return;
      }

      const decision = await BiometricEnrollmentService.processEnrollment(uid, dto);

      // Invariant I-08, I-23: Constant-time padding to eliminate oracle timing side-channels
      const elapsed = Date.now() - startTime;
      if (elapsed < MIN_ENROLL_LATENCY_MS) {
        await sleep(MIN_ENROLL_LATENCY_MS - elapsed);
      }

      res.status(200).json({
        success: !decision.isDuplicate && decision.status !== "technical_failure_retry",
        status: decision.status,
        data: decision,
        serverTimestamp: new Date().toISOString(),
      } as UniformBiometricApiResponse);
    } catch (error: any) {
      console.error("[FaceRoutes] /enroll error:", error);

      const elapsed = Date.now() - startTime;
      if (elapsed < MIN_ENROLL_LATENCY_MS) {
        await sleep(MIN_ENROLL_LATENCY_MS - elapsed);
      }

      res.status(400).json({
        success: false,
        status: "enrollment_failed",
        error: {
          code: "ENROLLMENT_PROCESSING_ERROR",
          message: error.message || "Failed to process biometric enrollment.",
        },
        serverTimestamp: new Date().toISOString(),
      } as UniformBiometricApiResponse);
    }
  }
);

/**
 * Handles 1:1 facial verification against user's enrolled template.
 */
async function handleVerify(req: AuthenticatedRequest, res: Response): Promise<void> {
  const startTime = Date.now();
  try {
    const uid = req.user!.uid;
    const dto = req.body as VerifyLoginRequestDTO;

    if (!dto.imageBase64 || typeof dto.imageBase64 !== "string" || dto.imageBase64.trim().length === 0) {
      const elapsed = Date.now() - startTime;
      if (elapsed < MIN_ENROLL_LATENCY_MS) await sleep(MIN_ENROLL_LATENCY_MS - elapsed);
      res.status(400).json({
        success: false,
        status: "invalid_argument",
        error: {
          code: "MISSING_IMAGE_BASE64",
          message: "Field 'imageBase64' is required for authoritative face inference.",
        },
        serverTimestamp: new Date().toISOString(),
      } as UniformBiometricApiResponse);
      return;
    }

    // Validate challenge nonce if provided
    if (dto.challengeNonce) {
      const isValid = SessionChallengeService.consumeChallenge(
        dto.challengeNonce,
        uid,
        "VERIFICATION"
      );
      if (!isValid) {
        const elapsed = Date.now() - startTime;
        if (elapsed < MIN_ENROLL_LATENCY_MS) await sleep(MIN_ENROLL_LATENCY_MS - elapsed);
        res.status(403).json({
          success: false,
          status: "challenge_rejected",
          error: {
            code: "INVALID_CHALLENGE_NONCE",
            message: "Challenge nonce is invalid, expired, replayed, or bound to another identity.",
          },
          serverTimestamp: new Date().toISOString(),
        } as UniformBiometricApiResponse);
        return;
      }
    }

    // Validate device integrity if provided (GAP-01 / Invariant I-26)
    if (dto.integrityToken) {
      let expectedRequestHash: string | undefined;
      if (dto.challengeNonce && dto.imageBase64) {
        const captureDigest = crypto
          .createHash("sha256")
          .update(decodeBase64Image(dto.imageBase64))
          .digest("hex");
        expectedRequestHash = DeviceAttestationService.computeRequestHash(
          dto.challengeNonce,
          uid,
          "VERIFICATION",
          captureDigest
        );
      }
      const attestationResult = await DeviceAttestationService.verifyPlayIntegrityTokenAsync(
        dto.integrityToken,
        {
          expectedRequestHash: dto.requestHash || expectedRequestHash,
          allowDevBypass: config.allowDevToken,
        }
      );
      if (!attestationResult.isValid) {
        const elapsed = Date.now() - startTime;
        if (elapsed < MIN_ENROLL_LATENCY_MS) await sleep(MIN_ENROLL_LATENCY_MS - elapsed);
        res.status(403).json({
          success: false,
          status: "attestation_failed",
          error: {
            code: "DEVICE_INTEGRITY_FAILED",
            message: `Device integrity check failed: ${attestationResult.error || attestationResult.verdict}`,
          },
          serverTimestamp: new Date().toISOString(),
        } as UniformBiometricApiResponse);
        return;
      }
    }

    const enrolledVector = await FirestoreBiometricRepository.getEnrolledTemplate(uid);
    if (!enrolledVector) {
      const elapsed = Date.now() - startTime;
      if (elapsed < MIN_ENROLL_LATENCY_MS) await sleep(MIN_ENROLL_LATENCY_MS - elapsed);
      res.status(404).json({
        success: false,
        status: "not_enrolled",
        error: {
          code: "NOT_ENROLLED",
          message: "No biometric template enrolled for this user account.",
        },
        serverTimestamp: new Date().toISOString(),
      } as UniformBiometricApiResponse);
      return;
    }

    const buffer = decodeBase64Image(dto.imageBase64);
    const probeEmbedding = await runFaceInference(buffer);

    const similarity = cosineSimilarity(probeEmbedding, enrolledVector);
    const verificationThreshold = config.verificationThreshold || 0.363;
    const isMatch = similarity >= verificationThreshold;

    await AuditService.logEvent({
      eventType: isMatch ? "BIOMETRIC_LOGIN_SUCCESS" : "BIOMETRIC_LOGIN_FAILED",
      uid,
      similarityScore: similarity,
      threshold: verificationThreshold,
    });

    const elapsed = Date.now() - startTime;
    if (elapsed < MIN_ENROLL_LATENCY_MS) {
      await sleep(MIN_ENROLL_LATENCY_MS - elapsed);
    }

    res.status(200).json({
      success: isMatch,
      status: isMatch ? "verified" : "rejected",
      data: {
        isMatch,
        similarity,
        threshold: verificationThreshold,
        message: isMatch
          ? "Facial identity verified successfully."
          : "Facial authentication failed. Probe did not match enrolled template.",
      },
      serverTimestamp: new Date().toISOString(),
    } as UniformBiometricApiResponse);
  } catch (error: any) {
    console.error("[FaceRoutes] /verify error:", error);
    const elapsed = Date.now() - startTime;
    if (elapsed < MIN_ENROLL_LATENCY_MS) {
      await sleep(MIN_ENROLL_LATENCY_MS - elapsed);
    }

    res.status(500).json({
      success: false,
      status: "internal_error",
      error: {
        code: "VERIFICATION_ERROR",
        message: error.message || "Failed to verify biometric probe.",
      },
      serverTimestamp: new Date().toISOString(),
    } as UniformBiometricApiResponse);
  }
}

/**
 * POST /api/biometrics/verify-1to1
 * Canonical 1:1 facial verification endpoint.
 */
faceRouter.post("/verify-1to1", authenticateFirebaseToken, checkForbiddenVectorFields, handleVerify);

/**
 * POST /api/biometrics/verify
 * Unified alias for 1:1 face verification (Profile eVerify).
 */
faceRouter.post("/verify", authenticateFirebaseToken, checkForbiddenVectorFields, handleVerify);

/**
 * POST /api/biometrics/verify-login
 * Backward-compatible alias for 1:1 verification.
 */
faceRouter.post("/verify-login", authenticateFirebaseToken, checkForbiddenVectorFields, handleVerify);

/**
 * DELETE /api/biometrics/template
 * DPDPA 2023 Right to Erasure fulfillment.
 */
faceRouter.delete(
  "/template",
  authenticateFirebaseToken,
  async (req: AuthenticatedRequest, res: Response): Promise<void> => {
    const start = Date.now();
    try {
      const callerUid = req.user!.uid;
      const targetUid = (req.query.targetUid as string) || callerUid;

      if (targetUid !== callerUid && !req.user!.isAdmin) {
        res.status(403).json({
          success: false,
          status: "permission_denied",
          error: {
            code: "FORBIDDEN",
            message: "You can only delete your own biometric template.",
          },
          serverTimestamp: new Date().toISOString(),
        } as UniformBiometricApiResponse);
        return;
      }

      await FirestoreBiometricRepository.deleteTemplate(targetUid);
      const ackLatencyMs = Date.now() - start;

      await AuditService.logEvent({
        eventType: "TEMPLATE_DELETED",
        uid: targetUid,
        metadata: {
          deletedBy: callerUid,
          ackLatencyMs,
          erasureScope: "PRIMARY_VAULT_AND_RAM_INDEX",
        },
      });

      res.status(200).json({
        success: true,
        status: "deleted",
        data: {
          message: "Biometric template and associated cryptographic salts permanently deleted.",
          targetUid,
          erasureLifecycle: {
            apiAckLatencyMs: ackLatencyMs,
            primaryVaultDocDeleted: true,
            inMemoryIndexEvicted: true,
            secondaryReplicasEventualConsistency: "subject_to_datastore_propagation",
            backupRetentionPolicy: "purged_on_backup_rotation_schedule_30d",
            cryptographicErasureStatus: "dek_unrecoverable",
          },
        },
        serverTimestamp: new Date().toISOString(),
      } as UniformBiometricApiResponse);
    } catch (error: any) {
      console.error("[FaceRoutes] DELETE /template error:", error);
      res.status(500).json({
        success: false,
        status: "internal_error",
        error: {
          code: "DELETION_ERROR",
          message: error.message || "Failed to delete biometric template.",
        },
        serverTimestamp: new Date().toISOString(),
      } as UniformBiometricApiResponse);
    }
  }
);

/**
 * POST /api/biometrics/device-attestation
 * Validates Play Integrity or Firebase App Check token (Ticket T-17 / Invariant I-26).
 */
faceRouter.post(
  "/device-attestation",
  authenticateFirebaseToken,
  async (req: AuthenticatedRequest, res: Response): Promise<void> => {
    try {
      const dto = req.body as DeviceAttestationRequestDTO;
      const appCheckHeader = req.headers["x-firebase-appcheck"] as string | undefined;
      const token = dto.attestationToken || appCheckHeader;

      const result = DeviceAttestationService.verifyDeviceIntegrity(token, config.allowDevToken);

      res.status(result.isValid ? 200 : 403).json({
        success: result.isValid,
        status: result.isValid ? "attested" : "attestation_failed",
        data: {
          verdict: result.verdict,
          reason: result.reason,
        },
        serverTimestamp: new Date().toISOString(),
      } as UniformBiometricApiResponse);
    } catch (error: any) {
      console.error("[FaceRoutes] /device-attestation error:", error);
      res.status(500).json({
        success: false,
        status: "internal_error",
        error: {
          code: "ATTESTATION_ERROR",
          message: error.message || "Failed to verify device attestation.",
        },
        serverTimestamp: new Date().toISOString(),
      } as UniformBiometricApiResponse);
    }
  }
);

/**
 * POST /api/biometrics/re-verify
 * Shift-start 1:1 facial re-verification and device binding check (Ticket T-18 / Invariant I-27, I-28).
 */
faceRouter.post(
  "/re-verify",
  authenticateFirebaseToken,
  checkForbiddenVectorFields,
  async (req: AuthenticatedRequest, res: Response): Promise<void> => {
    const startTime = Date.now();
    try {
      const uid = req.user!.uid;
      const dto = req.body as ReVerifyRequestDTO;

      if (!dto.imageBase64 || typeof dto.imageBase64 !== "string") {
        const elapsed = Date.now() - startTime;
        if (elapsed < MIN_ENROLL_LATENCY_MS) await sleep(MIN_ENROLL_LATENCY_MS - elapsed);
        res.status(400).json({
          success: false,
          status: "invalid_argument",
          error: {
            code: "MISSING_IMAGE_BASE64",
            message: "Field 'imageBase64' is required for re-verification.",
          },
          serverTimestamp: new Date().toISOString(),
        } as UniformBiometricApiResponse);
        return;
      }

      if (!dto.deviceId || typeof dto.deviceId !== "string") {
        const elapsed = Date.now() - startTime;
        if (elapsed < MIN_ENROLL_LATENCY_MS) await sleep(MIN_ENROLL_LATENCY_MS - elapsed);
        res.status(400).json({
          success: false,
          status: "invalid_argument",
          error: {
            code: "MISSING_DEVICE_ID",
            message: "Field 'deviceId' is mandatory for hardware binding.",
          },
          serverTimestamp: new Date().toISOString(),
        } as UniformBiometricApiResponse);
        return;
      }

      // Validate challenge nonce if provided
      if (dto.challengeNonce) {
        const isValid = SessionChallengeService.consumeChallenge(
          dto.challengeNonce,
          uid,
          "VERIFICATION"
        );
        if (!isValid) {
          const elapsed = Date.now() - startTime;
          if (elapsed < MIN_ENROLL_LATENCY_MS) await sleep(MIN_ENROLL_LATENCY_MS - elapsed);
          res.status(403).json({
            success: false,
            status: "challenge_rejected",
            error: {
              code: "INVALID_CHALLENGE_NONCE",
              message: "Challenge nonce is invalid, expired, replayed, or cross-user.",
            },
            serverTimestamp: new Date().toISOString(),
          } as UniformBiometricApiResponse);
          return;
        }
      }

      // Extract probe embedding from raw frame
      const imageBuffer = decodeBase64Image(dto.imageBase64);
      const probeEmbedding = await runFaceInference(imageBuffer);

      // Execute shift lifecycle re-verification
      const result = await AccountLifecycleService.reVerifyWorker({
        uid,
        probeEmbedding,
        deviceId: dto.deviceId,
        latitude: dto.latitude,
        longitude: dto.longitude,
        isMockGps: dto.isMockGps,
      });

      const elapsed = Date.now() - startTime;
      if (elapsed < MIN_ENROLL_LATENCY_MS) await sleep(MIN_ENROLL_LATENCY_MS - elapsed);

      res.status(result.success ? 200 : 403).json({
        success: result.success,
        status: result.success ? "shift_activated" : "reverification_failed",
        data: result,
        serverTimestamp: new Date().toISOString(),
      } as UniformBiometricApiResponse);
    } catch (error: any) {
      console.error("[FaceRoutes] /re-verify error:", error);
      const elapsed = Date.now() - startTime;
      if (elapsed < MIN_ENROLL_LATENCY_MS) await sleep(MIN_ENROLL_LATENCY_MS - elapsed);
      res.status(500).json({
        success: false,
        status: "internal_error",
        error: {
          code: "REVERIFY_ERROR",
          message: error.message || "Failed to execute shift re-verification.",
        },
        serverTimestamp: new Date().toISOString(),
      } as UniformBiometricApiResponse);
    }
  }
);

/**
 * GET /api/biometrics/shift-status
 * Queries current worker shift validity and re-verification requirement (Ticket T-18).
 */
faceRouter.get(
  "/shift-status",
  authenticateFirebaseToken,
  async (req: AuthenticatedRequest, res: Response): Promise<void> => {
    try {
      const uid = req.user!.uid;
      const status = await AccountLifecycleService.getShiftStatus(uid);

      res.status(200).json({
        success: true,
        status: status.isShiftActive ? "shift_active" : "reverification_required",
        data: status,
        serverTimestamp: new Date().toISOString(),
      } as UniformBiometricApiResponse);
    } catch (error: any) {
      console.error("[FaceRoutes] /shift-status error:", error);
      res.status(500).json({
        success: false,
        status: "internal_error",
        error: {
          code: "SHIFT_STATUS_ERROR",
          message: error.message || "Failed to query shift status.",
        },
        serverTimestamp: new Date().toISOString(),
      } as UniformBiometricApiResponse);
    }
  }
);

/**
 * POST /api/biometrics/liveness-challenge
 * Issues randomized multi-action interactive liveness challenge (Ticket T-19 / Invariant I-29).
 */
faceRouter.post(
  "/liveness-challenge",
  authenticateFirebaseToken,
  async (req: AuthenticatedRequest, res: Response): Promise<void> => {
    try {
      const uid = req.user!.uid;
      const challenge = PresentationAttackDefenseService.issueChallenge(uid);

      res.status(200).json({
        success: true,
        status: "challenge_issued",
        data: challenge,
        serverTimestamp: new Date().toISOString(),
      } as UniformBiometricApiResponse);
    } catch (error: any) {
      console.error("[FaceRoutes] /liveness-challenge error:", error);
      res.status(500).json({
        success: false,
        status: "internal_error",
        error: {
          code: "LIVENESS_CHALLENGE_ERROR",
          message: error.message || "Failed to issue interactive liveness challenge.",
        },
        serverTimestamp: new Date().toISOString(),
      } as UniformBiometricApiResponse);
    }
  }
);

/**
 * POST /api/biometrics/liveness-verify
 * Verifies multi-frame landmark transitions against the active challenge (Ticket T-19 / Invariant I-30).
 */
faceRouter.post(
  "/liveness-verify",
  authenticateFirebaseToken,
  async (req: AuthenticatedRequest, res: Response): Promise<void> => {
    try {
      const uid = req.user!.uid;
      const dto = req.body as LivenessVerifyRequestDTO;

      if (!dto.challengeId || !dto.frames) {
        res.status(400).json({
          success: false,
          status: "invalid_argument",
          error: {
            code: "MISSING_CHALLENGE_PAYLOAD",
            message: "Fields 'challengeId' and 'frames' are mandatory for liveness verification.",
          },
          serverTimestamp: new Date().toISOString(),
        } as UniformBiometricApiResponse);
        return;
      }

      const result = PresentationAttackDefenseService.verifyChallenge({
        challengeId: dto.challengeId,
        uid,
        frames: dto.frames,
      });

      res.status(result.passed ? 200 : 403).json({
        success: result.passed,
        status: result.passed ? "liveness_verified" : "liveness_failed",
        data: result,
        serverTimestamp: new Date().toISOString(),
      } as UniformBiometricApiResponse);
    } catch (error: any) {
      console.error("[FaceRoutes] /liveness-verify error:", error);
      res.status(500).json({
        success: false,
        status: "internal_error",
        error: {
          code: "LIVENESS_VERIFY_ERROR",
          message: error.message || "Failed to verify liveness response.",
        },
        serverTimestamp: new Date().toISOString(),
      } as UniformBiometricApiResponse);
    }
  }
);

/**
 * GET /api/biometrics/db-readiness
 * Firestore biometric database readiness check.
 * Returns: vault count, index warm status, Firestore latency, model version.
 * ISO 19795-1:2021 — system availability reporting.
 */
faceRouter.get(
  '/db-readiness',
  authenticateFirebaseToken,
  async (req: AuthenticatedRequest, res: Response): Promise<void> => {
    try {
      const uid = req.user!.uid;

      // 1. Firestore latency probe
      const fsStart = Date.now();
      await admin.firestore().collection('biometric_vault').limit(1).get();
      const firestoreLatencyMs = Date.now() - fsStart;

      // 2. Vault enrollment count
      const countSnap = await admin.firestore()
        .collection('biometric_vault')
        .count()
        .get();
      const enrolledCount = countSnap.data().count;

      // 3. RAM index warm status
      const ramIndexSize = InMemoryBiometricIndex.size();
      const isWarm = ramIndexSize > 0;

      // 4. Check requester enrollment status
      const vaultDoc = await admin.firestore()
        .collection('biometric_vault')
        .doc(uid)
        .get();
      const isEnrolled = vaultDoc.exists;

      res.status(200).json({
        success: true,
        status: 'db_ready',
        data: {
          firestoreLatencyMs,
          enrolledTemplates: enrolledCount,
          ramIndexSize,
          isRamIndexWarm: isWarm,
          modelVersion: config.modelVersion,
          preprocessVersion: PREPROCESSING_ID,
          requesterEnrolled: isEnrolled,
          timestamp: new Date().toISOString(),
          // ISO 19795-1:2021 system availability
          systemAvailability: {
            firestoreOk: firestoreLatencyMs < 2000,
            ramIndexOk: isWarm || enrolledCount === 0,
            deduplicationReady: isWarm || enrolledCount < 10,
          },
        },
        serverTimestamp: new Date().toISOString(),
      });
    } catch (error: any) {
      res.status(503).json({
        success: false,
        status: 'db_error',
        error: { code: 'DB_READINESS_ERROR', message: error.message },
        serverTimestamp: new Date().toISOString(),
      });
    }
  }
);

/**
 * POST /api/biometrics/cross-account-check
 * Runs 1:N probe against ALL vault entries EXCEPT requester's own uid.
 * Used at login to detect same-person multi-account fraud.
 * ISO 30107-3 + UIDAI FaceRD v2.0 duplicate account policy.
 */
faceRouter.post(
  '/cross-account-check',
  authenticateFirebaseToken,
  async (req: AuthenticatedRequest, res: Response): Promise<void> => {
    const start = Date.now();
    try {
      const uid = req.user!.uid;
      const dto = req.body as { imageBase64?: string };

      if (!dto.imageBase64 || typeof dto.imageBase64 !== 'string') {
        res.status(400).json({
          success: false,
          status: 'invalid_argument',
          error: { code: 'MISSING_IMAGE', message: 'imageBase64 required.' },
          serverTimestamp: new Date().toISOString(),
        });
        return;
      }

      const imageBuffer = decodeBase64Image(dto.imageBase64);
      const probeEmbedding = await runFaceInference(imageBuffer);

      // 1:N scan excluding own uid
      const candidates = await FirestoreBiometricRepository.findTopK(
        probeEmbedding, uid, 3
      );

      const elapsed = Date.now() - start;
      const MIN_MS = 300;
      if (elapsed < MIN_MS) await sleep(MIN_MS - elapsed);

      if (candidates.length === 0) {
        res.status(200).json({
          success: true,
          status: 'no_match',
          data: { isDuplicate: false, isHardBlock: false, topSimilarity: 0 },
          serverTimestamp: new Date().toISOString(),
        });
        return;
      }

      const top = candidates[0];
      const sim = top.similarity;

      // Decision thresholds
      // ≥ hardBlockThreshold: HARD BLOCK — unmistakably same person
      // duplicateThreshold .. hardBlockThreshold: FLAG — likely duplicate, route to review
      // < duplicateThreshold: SAFE
      const hardBlockThreshold = config.hardBlockThreshold || 0.90;
      const duplicateThreshold = config.duplicateThreshold || 0.74;
      const isHardBlock = sim >= hardBlockThreshold;
      const isDuplicate = sim >= duplicateThreshold;

      if (isDuplicate) {
        await AuditService.logEvent({
          eventType: isHardBlock ? 'CROSS_ACCOUNT_HARD_BLOCK' : 'CROSS_ACCOUNT_FLAG',
          uid,
          matchedUid: top.uid,
          similarityScore: sim,
          threshold: duplicateThreshold,
          metadata: { topKScores: candidates.map(c => c.similarity), policy: isHardBlock ? 'HARD_BLOCK' : 'FLAG_REVIEW' },
        });
      }

      const decisionCode = isHardBlock
        ? 'HIGH_CONFIDENCE_CANDIDATE'
        : isDuplicate
        ? 'POTENTIAL_DUPLICATE'
        : 'NO_LIKELY_DUPLICATE';

      res.status(200).json({
        success: true,
        status: isDuplicate ? (isHardBlock ? 'hard_block' : 'flagged') : 'no_match',
        data: {
          isDuplicate,
          isHardBlock,
          decisionCode,
          requiresReview: isDuplicate,
          message: isHardBlock
            ? 'ಹೆಚ್ಚಿನ ಹೋಲಿಕೆ ಪತ್ತೆಯಾಗಿದೆ. High-confidence candidate match detected. Application routed to priority review.'
            : isDuplicate
            ? 'ಮುಖ ಹೋಲಿಕೆ ಪತ್ತೆಯಾಗಿದೆ. Possible duplicate account flagged for review.'
            : 'No duplicate account found.',
        },
        serverTimestamp: new Date().toISOString(),
      });
    } catch (error: any) {
      console.error('[FaceRoutes] /cross-account-check error:', error);
      res.status(500).json({
        success: false, status: 'internal_error',
        error: { code: 'CROSS_CHECK_ERROR', message: error.message },
        serverTimestamp: new Date().toISOString(),
      });
    }
  }
);

/**
 * GET /api/biometrics/kms-health
 * Performs live round-trip wrap/unwrap health probe using configured KeyProvider (Cloud KMS or LocalDev).
 * Measures latency and validates byte equality (Gate G-03).
 */
faceRouter.get(
  '/kms-health',
  async (req: Request, res: Response): Promise<void> => {
    const testDek = crypto.randomBytes(32);
    const aadContext = Buffer.from(`kms-health-probe:${Date.now()}`);
    try {
      const provider = TemplatePrivacyService.getDefaultKeyProvider();

      const wrapStart = Date.now();
      const wrapped = await provider.wrapDek(testDek, aadContext);
      const wrapMs = Date.now() - wrapStart;

      const unwrapStart = Date.now();
      const unwrapped = await provider.unwrapDek(wrapped.wrappedDek, aadContext, wrapped.kmsKeyResourceName);
      const unwrapMs = Date.now() - unwrapStart;

      const isByteIdentical =
        unwrapped.length === testDek.length && crypto.timingSafeEqual(testDek, unwrapped);

      testDek.fill(0);
      unwrapped.fill(0);

      if (!isByteIdentical) {
        res.status(500).json({
          success: false,
          status: 'unhealthy',
          reason: 'KMS_ROUNDTRIP_MISMATCH',
          serverTimestamp: new Date().toISOString(),
        });
        return;
      }

      res.status(200).json({
        success: true,
        status: 'healthy',
        data: {
          providerType: provider.providerType,
          protectionLevel: provider.providerType === 'cloud_kms' ? 'HSM' : 'LOCAL_DEV_SIMULATOR',
          keyResourceName: provider.defaultKeyResourceName,
          wrapMs,
          unwrapMs,
        },
        serverTimestamp: new Date().toISOString(),
      });
    } catch (err: any) {
      testDek.fill(0);
      res.status(503).json({
        success: false,
        status: 'unhealthy',
        error: { code: 'KMS_UNAVAILABLE_ERROR', message: err.message },
        serverTimestamp: new Date().toISOString(),
      });
    }
  }
);

/**
 * Dependencies injected into createFaceBiometricRouter
 */
export interface FaceRoutesDependencies {
  db?: admin.firestore.Firestore;
  landmarker: MediaPipeFaceLandmarkerOnnx | FrameAnalyzerAdapter;
  inferenceService?: FaceInferenceService;
  kmsEncryptionService?: KmsEnvelopeEncryptionService | BiometricEnvelopeEncryptionService;
  firestoreRepository?: typeof FirestoreBiometricRepository | FirestoreBiometricRepository;
  auditService?: typeof AuditService;
  qualityConfig?: CaptureQualityCandidateConfig;
}

/**
 * Creates an Express 4.x Router wired with the 3-frame Challenge-Bound Burst PAD
 * and authoritative OpenCV SFace verification / enrollment pipeline (Gate G-02, G-03, G-04).
 */
export function createFaceBiometricRouter(deps: FaceRoutesDependencies): Router {
  const router = Router();
  router.use(ipRateLimiter);

  const getDb = () => deps.db || admin.firestore();
  const getKms = () =>
    deps.kmsEncryptionService ||
    new BiometricEnvelopeEncryptionService(TemplatePrivacyService.getDefaultKeyProvider());

  // POST /challenge
  router.post(
    ["/api/biometrics/challenge", "/challenge"],
    authenticateFirebaseToken,
    async (req: AuthenticatedRequest, res: Response): Promise<void> => {
      try {
        const uid = req.user?.uid;
        if (!uid) {
          res.status(401).json({
            success: false,
            status: "unauthenticated",
            error: { code: "UNAUTHENTICATED", message: "User token required." },
            serverTimestamp: new Date().toISOString(),
          } as UniformBiometricApiResponse);
          return;
        }

        const rawPurpose = (req.body?.purpose || req.body?.action || "verify_1to1").toString().toLowerCase();
        let purpose: ChallengePurpose = "verify_1to1";
        if (rawPurpose.includes("enroll")) {
          purpose = "enroll";
        } else if (rawPurpose.includes("shift") || rawPurpose.includes("reverify")) {
          purpose = "reverify_shift";
        }

        const challenge = await ChallengeBurstPadService.issueChallenge(getDb(), uid, purpose);
        res.status(200).json({
          success: true,
          status: "challenge_issued",
          data: {
            challengeId: challenge.challengeId,
            challengeNonce: challenge.nonce,
            nonce: challenge.nonce,
            expiresAtMs: challenge.expiresAtMs,
            expectedFrameCount: 3,
            expectedSequence: ["EYES_OPEN", "EYES_CLOSED_APEX", "EYES_OPEN"],
            purpose,
          },
          serverTimestamp: new Date().toISOString(),
        } as UniformBiometricApiResponse);
      } catch (err: any) {
        res.status(500).json({
          success: false,
          status: "challenge_error",
          error: { code: "CHALLENGE_GENERATION_FAILED", message: err.message },
          serverTimestamp: new Date().toISOString(),
        } as UniformBiometricApiResponse);
      }
    }
  );

  // POST /verify-1to1
  router.post(
    ["/api/biometrics/verify-1to1", "/verify-1to1"],
    checkForbiddenVectorFields,
    authenticateFirebaseToken,
    async (req: AuthenticatedRequest, res: Response): Promise<void> => {
      const startMs = Date.now();
      try {
        const uid = req.user?.uid;
        if (!uid) {
          res.status(401).json({
            success: false,
            status: "unauthenticated",
            error: { code: "UNAUTHENTICATED", message: "User token required." },
            serverTimestamp: new Date().toISOString(),
          } as UniformBiometricApiResponse);
          return;
        }

        const { challengeId, nonce, frames, isMirroredFrontCamera } = req.body || {};

        if (!challengeId || !nonce || !Array.isArray(frames) || frames.length !== 3) {
          res.status(400).json({
            success: false,
            status: "pad_rejected",
            error: {
              code: "SINGLE_OR_INVALID_FRAME_COUNT_REJECTED",
              message: "Challenge-bound 3-frame burst required (Gate G-02). Single static image rejected.",
            },
            serverTimestamp: new Date().toISOString(),
          } as UniformBiometricApiResponse);
          return;
        }

        const evaluation = await ChallengeBurstPadService.evaluateChallengeBurst({
          db: getDb(),
          uid,
          purpose: "verify_1to1",
          challengeId,
          nonce,
          frames,
          isMirroredFrontCamera: Boolean(isMirroredFrontCamera),
          landmarker: deps.landmarker as any,
          qualityConfig: deps.qualityConfig,
        });

        if (evaluation.outcome !== "APPROVED" || !evaluation.authoritativeSFaceEmbedding) {
          const padReason =
            evaluation.padRejectionReason ||
            evaluation.qualityRejectionCode ||
            "PAD_EVALUATION_REJECTED";
          const isQuality = evaluation.outcome === "QUALITY_REJECTED";
          res.status(400).json({
            success: false,
            status: isQuality ? "quality_rejected" : "pad_rejected",
            error: {
              code: padReason,
              message: `Liveness / quality verification failed: ${padReason}`,
            },
            data: { telemetry: evaluation.telemetry },
            serverTimestamp: new Date().toISOString(),
          } as UniformBiometricApiResponse);
          return;
        }

        let storedVector: Float32Array | null = null;
        if (
          deps.firestoreRepository &&
          typeof (deps.firestoreRepository as any).getEnrolledTemplate === "function"
        ) {
          const raw = await (deps.firestoreRepository as any).getEnrolledTemplate(uid);
          if (raw) storedVector = raw instanceof Float32Array ? raw : Float32Array.from(raw);
        }

        if (!storedVector) {
          const vaultDoc = await getDb().collection("biometric_vault").doc(uid).get();
          if (vaultDoc.exists) {
            const data = vaultDoc.data()!;
            if (data.ciphertextBase64 && data.wrappedDekBase64) {
              const decrypted = await getKms().decryptTemplate(uid, data as any);
              storedVector = decrypted instanceof Float32Array ? decrypted : Float32Array.from(decrypted);
            } else if (Array.isArray(data.embedding)) {
              storedVector = Float32Array.from(data.embedding);
            }
          }
        }

        if (!storedVector) {
          res.status(404).json({
            success: false,
            status: "not_enrolled",
            error: {
              code: "NOT_ENROLLED",
              message: "User does not have an enrolled biometric template.",
            },
            serverTimestamp: new Date().toISOString(),
          } as UniformBiometricApiResponse);
          return;
        }

        const similarity = computeValidatedCosineSimilarity(
          evaluation.authoritativeSFaceEmbedding,
          storedVector
        );
        const threshold = config.verificationThreshold || 0.363;
        const isMatch = similarity >= threshold;

        const elapsed = Date.now() - startMs;
        if (elapsed < MIN_ENROLL_LATENCY_MS) {
          await sleep(MIN_ENROLL_LATENCY_MS - elapsed);
        }

        if (!isMatch) {
          res.status(200).json({
            success: false,
            status: "mismatch",
            data: {
              isMatch: false,
              similarity,
              threshold,
              telemetry: evaluation.telemetry,
            },
            serverTimestamp: new Date().toISOString(),
          } as UniformBiometricApiResponse);
          return;
        }

        res.status(200).json({
          success: true,
          status: "verified",
          data: {
            isMatch: true,
            similarity,
            threshold,
            telemetry: evaluation.telemetry,
          },
          serverTimestamp: new Date().toISOString(),
        } as UniformBiometricApiResponse);
      } catch (err: any) {
        res.status(500).json({
          success: false,
          status: "internal_error",
          error: { code: "VERIFICATION_ERROR", message: err.message },
          serverTimestamp: new Date().toISOString(),
        } as UniformBiometricApiResponse);
      }
    }
  );

  // POST /reverify-shift
  router.post(
    ["/api/biometrics/reverify-shift", "/reverify-shift"],
    checkForbiddenVectorFields,
    authenticateFirebaseToken,
    async (req: AuthenticatedRequest, res: Response): Promise<void> => {
      const startMs = Date.now();
      try {
        const uid = req.user?.uid;
        if (!uid) {
          res.status(401).json({
            success: false,
            status: "unauthenticated",
            error: { code: "UNAUTHENTICATED", message: "User token required." },
            serverTimestamp: new Date().toISOString(),
          } as UniformBiometricApiResponse);
          return;
        }

        const { challengeId, nonce, frames, isMirroredFrontCamera } = req.body || {};

        if (!challengeId || !nonce || !Array.isArray(frames) || frames.length !== 3) {
          res.status(400).json({
            success: false,
            status: "pad_rejected",
            error: {
              code: "SINGLE_OR_INVALID_FRAME_COUNT_REJECTED",
              message: "Challenge-bound 3-frame burst required (Gate G-02). Single static image rejected.",
            },
            serverTimestamp: new Date().toISOString(),
          } as UniformBiometricApiResponse);
          return;
        }

        const evaluation = await ChallengeBurstPadService.evaluateChallengeBurst({
          db: getDb(),
          uid,
          purpose: "reverify_shift",
          challengeId,
          nonce,
          frames,
          isMirroredFrontCamera: Boolean(isMirroredFrontCamera),
          landmarker: deps.landmarker as any,
          qualityConfig: deps.qualityConfig,
        });

        if (evaluation.outcome !== "APPROVED" || !evaluation.authoritativeSFaceEmbedding) {
          const padReason =
            evaluation.padRejectionReason ||
            evaluation.qualityRejectionCode ||
            "PAD_EVALUATION_REJECTED";
          res.status(400).json({
            success: false,
            status: "pad_rejected",
            error: { code: padReason, message: `Liveness verification failed: ${padReason}` },
            data: { telemetry: evaluation.telemetry },
            serverTimestamp: new Date().toISOString(),
          } as UniformBiometricApiResponse);
          return;
        }

        let storedVector: Float32Array | null = null;
        if (
          deps.firestoreRepository &&
          typeof (deps.firestoreRepository as any).getEnrolledTemplate === "function"
        ) {
          const raw = await (deps.firestoreRepository as any).getEnrolledTemplate(uid);
          if (raw) storedVector = raw instanceof Float32Array ? raw : Float32Array.from(raw);
        }

        if (!storedVector) {
          const vaultDoc = await getDb().collection("biometric_vault").doc(uid).get();
          if (vaultDoc.exists) {
            const data = vaultDoc.data()!;
            if (data.ciphertextBase64 && data.wrappedDekBase64) {
              const decrypted = await getKms().decryptTemplate(uid, data as any);
              storedVector = decrypted instanceof Float32Array ? decrypted : Float32Array.from(decrypted);
            } else if (Array.isArray(data.embedding)) {
              storedVector = Float32Array.from(data.embedding);
            }
          }
        }

        if (!storedVector) {
          res.status(404).json({
            success: false,
            status: "not_enrolled",
            error: {
              code: "NOT_ENROLLED",
              message: "User does not have an enrolled biometric template.",
            },
            serverTimestamp: new Date().toISOString(),
          } as UniformBiometricApiResponse);
          return;
        }

        const similarity = computeValidatedCosineSimilarity(
          evaluation.authoritativeSFaceEmbedding,
          storedVector
        );
        const threshold = config.verificationThreshold || 0.363;
        const isMatch = similarity >= threshold;

        const elapsed = Date.now() - startMs;
        if (elapsed < MIN_ENROLL_LATENCY_MS) {
          await sleep(MIN_ENROLL_LATENCY_MS - elapsed);
        }

        if (!isMatch) {
          res.status(200).json({
            success: false,
            status: "mismatch",
            data: {
              isMatch: false,
              similarity,
              threshold,
              telemetry: evaluation.telemetry,
            },
            serverTimestamp: new Date().toISOString(),
          } as UniformBiometricApiResponse);
          return;
        }

        try {
          await getDb().collection("workers").doc(uid).update({
            lastShiftVerifiedAt: new Date().toISOString(),
            shiftBiometricStatus: "verified",
          });
        } catch (_) {
          // Worker status update best-effort
        }

        res.status(200).json({
          success: true,
          status: "verified",
          data: {
            isMatch: true,
            similarity,
            threshold,
            shiftStatus: "active",
            telemetry: evaluation.telemetry,
          },
          serverTimestamp: new Date().toISOString(),
        } as UniformBiometricApiResponse);
      } catch (err: any) {
        res.status(500).json({
          success: false,
          status: "internal_error",
          error: { code: "SHIFT_REVERIFY_ERROR", message: err.message },
          serverTimestamp: new Date().toISOString(),
        } as UniformBiometricApiResponse);
      }
    }
  );

  // POST /enroll-biometric
  router.post(
    ["/api/biometrics/enroll-biometric", "/enroll-biometric"],
    checkForbiddenVectorFields,
    authenticateFirebaseToken,
    async (req: AuthenticatedRequest, res: Response): Promise<void> => {
      const startMs = Date.now();
      try {
        const uid = req.user?.uid;
        if (!uid) {
          res.status(401).json({
            success: false,
            status: "unauthenticated",
            error: { code: "UNAUTHENTICATED", message: "User token required." },
            serverTimestamp: new Date().toISOString(),
          } as UniformBiometricApiResponse);
          return;
        }

        const { challengeId, nonce, frames, isMirroredFrontCamera, role, phoneNumber, name } = req.body || {};

        if (!challengeId || !nonce || !Array.isArray(frames) || frames.length !== 3) {
          res.status(400).json({
            success: false,
            status: "pad_rejected",
            error: {
              code: "SINGLE_OR_INVALID_FRAME_COUNT_REJECTED",
              message: "Challenge-bound 3-frame burst required (Gate G-02). Single static image rejected.",
            },
            serverTimestamp: new Date().toISOString(),
          } as UniformBiometricApiResponse);
          return;
        }

        const evaluation = await ChallengeBurstPadService.evaluateChallengeBurst({
          db: getDb(),
          uid,
          purpose: "enroll",
          challengeId,
          nonce,
          frames,
          isMirroredFrontCamera: Boolean(isMirroredFrontCamera),
          landmarker: deps.landmarker as any,
          qualityConfig: deps.qualityConfig,
        });

        if (evaluation.outcome !== "APPROVED" || !evaluation.authoritativeSFaceEmbedding) {
          const padReason =
            evaluation.padRejectionReason ||
            evaluation.qualityRejectionCode ||
            "PAD_EVALUATION_REJECTED";
          res.status(400).json({
            success: false,
            status: "pad_rejected",
            error: { code: padReason, message: `Enrollment rejected by PAD: ${padReason}` },
            data: { telemetry: evaluation.telemetry },
            serverTimestamp: new Date().toISOString(),
          } as UniformBiometricApiResponse);
          return;
        }

        const embeddingArray = Array.from(evaluation.authoritativeSFaceEmbedding);

        let candidates: Array<{ uid: string; similarity: number; phoneNumber?: string }> = [];
        if (
          deps.firestoreRepository &&
          typeof (deps.firestoreRepository as any).findTopK === "function"
        ) {
          candidates = await (deps.firestoreRepository as any).findTopK(
            evaluation.authoritativeSFaceEmbedding,
            uid,
            3
          );
        } else {
          candidates = InMemoryBiometricIndex.findTopK(embeddingArray, uid, 3);
        }

        const top = candidates[0];
        const sim = top ? top.similarity : 0;
        const hardBlockThreshold = config.hardBlockThreshold || 0.90;
        const duplicateThreshold = config.duplicateThreshold || 0.74;

        if (sim >= hardBlockThreshold) {
          res.status(409).json({
            success: false,
            status: "duplicate",
            data: {
              isDuplicate: true,
              isHardBlock: true,
              decisionCode: "HIGH_CONFIDENCE_CANDIDATE",
              requiresReview: true,
              message: "High-confidence candidate match detected. Application routed to priority supervisor review. No automated ban applied.",
            },
            serverTimestamp: new Date().toISOString(),
          } as UniformBiometricApiResponse);
          return;
        }

        if (sim >= duplicateThreshold) {
          res.status(409).json({
            success: false,
            status: "duplicate",
            data: {
              isDuplicate: true,
              isHardBlock: false,
              decisionCode: "POTENTIAL_DUPLICATE",
              requiresReview: true,
              message: "Borderline facial duplicate detected. Enrollment flagged for administrative review.",
            },
            serverTimestamp: new Date().toISOString(),
          } as UniformBiometricApiResponse);
          return;
        }

        const envelope = await getKms().encryptTemplate(
          uid,
          evaluation.authoritativeSFaceEmbedding,
          { purpose: "biometric_template" }
        );

        await getDb().collection("biometric_vault").doc(uid).set({
          ...envelope,
          role: role || "worker",
          phoneNumber: phoneNumber || null,
          name: name || null,
          enrolledAt: new Date().toISOString(),
          modelVersion: "sface_opencv_zoo_v1_primary",
        });

        InMemoryBiometricIndex.upsert({
          uid,
          embedding: embeddingArray,
          modelId: "sface_opencv_zoo_v1_primary",
          preprocessVersion: PREPROCESSING_ID,
          phoneNumber: phoneNumber || "",
          enrolledAtMs: Date.now(),
        });

        try {
          await getDb().collection("users").doc(uid).update({
            faceVerified: true,
            accountStatus: "active",
            biometricEnrolledAt: new Date().toISOString(),
          });
        } catch (_) {
          // Best effort
        }

        const elapsed = Date.now() - startMs;
        if (elapsed < MIN_ENROLL_LATENCY_MS) {
          await sleep(MIN_ENROLL_LATENCY_MS - elapsed);
        }

        res.status(200).json({
          success: true,
          status: "enrolled",
          data: {
            uid,
            isApproved: true,
            accountStatus: "active",
            telemetry: evaluation.telemetry,
          },
          serverTimestamp: new Date().toISOString(),
        } as UniformBiometricApiResponse);
      } catch (err: any) {
        res.status(500).json({
          success: false,
          status: "internal_error",
          error: { code: "ENROLLMENT_ERROR", message: err.message },
          serverTimestamp: new Date().toISOString(),
        } as UniformBiometricApiResponse);
      }
    }
  );

  return router;
}


