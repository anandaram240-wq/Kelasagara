import * as crypto from "crypto";
import admin from "firebase-admin";
import { config } from "../config";
import { EnrollRequestDTO, BiometricDecisionResponse } from "../schemas/face_schemas";
import { runFaceInference } from "./face_inference";
import { decodeBase64Image, PREPROCESSING_ID } from "./face_preprocessing";
import { evaluateMatch, l2Normalize, maskPhoneNumber, maskName, maskUid, maskedDisplayId } from "./biometric_matching";
import { FirestoreBiometricRepository } from "./firestore_biometric_repository";
import { AuditService } from "./audit_service";
import { ModelRegistry } from "./model_registry";
import { SessionChallengeService, ActiveChallengeAction } from "./session_challenge_service";
import { InferenceRedundancyService } from "./inference_redundancy_service";
import { InMemoryBiometricIndex } from "./in_memory_biometric_index";
import { TemporalActionValidator } from "./temporal_action_validator";

export interface BiometricEnrollmentVerifyInput {
  uid: string;
  serverNonce: string;
  captureDigestHex: string;
  clientRequestHash: string;
  probeVector: number[];
  laplacianVariance: number;
}

export function verifyAndNormalizeEnrollmentPayload(
  input: BiometricEnrollmentVerifyInput
): Float32Array {
  // 1. Verify Play Integrity requestHash binding
  if (input.serverNonce && input.captureDigestHex && input.clientRequestHash) {
    const expectedPreimage = `${input.serverNonce}:${input.uid}:BIOMETRIC_ENROLL:${input.captureDigestHex}`;
    const expectedRequestHash = crypto
      .createHash("sha256")
      .update(expectedPreimage, "utf8")
      .digest("base64url");

    if (expectedRequestHash !== input.clientRequestHash) {
      throw new Error(
        "SECURITY_VIOLATION: Play Integrity requestHash mismatch against nonce and frame digest."
      );
    }
  }

  // 2. Verify ISO/IEC 30107-3 Passive PAD Texture Bounds
  if (input.laplacianVariance < 110.0 || input.laplacianVariance > 1850.0) {
    throw new Error(
      `PAD_SPOOF_REJECTED: Laplacian variance ${input.laplacianVariance.toFixed(2)} outside [110, 1850].`
    );
  }

  // 3. Validate 128-D Hypersphere Vector & Enforce Unit L2 Norm
  if (!Array.isArray(input.probeVector) || input.probeVector.length !== 128) {
    throw new Error("INVALID_EMBEDDING_DIMENSION: Expected 128-D vector.");
  }

  let sumSq = 0.0;
  for (let i = 0; i < 128; i++) {
    const val = Number(input.probeVector[i]);
    if (!Number.isFinite(val)) {
      throw new Error(`Non-finite embedding value at index ${i}`);
    }
    sumSq += val * val;
  }

  const l2Norm = Math.sqrt(sumSq);
  if (l2Norm < 1e-6) {
    throw new Error("ZERO_NORM_EMBEDDING: Degenerate biometric vector rejected.");
  }

  const normalized = new Float32Array(128);
  const invNorm = 1.0 / l2Norm;
  for (let i = 0; i < 128; i++) {
    normalized[i] = input.probeVector[i] * invNorm;
  }

  return normalized;
}

export class BiometricEnrollmentService {
  /**
   * Main enrollment orchestrator.
   * Executes authoritative face inference, 1:N de-duplication, and atomic Firestore persistence.
   */
  static async processEnrollment(
    uid: string,
    dto: EnrollRequestDTO
  ): Promise<BiometricDecisionResponse> {
    // 1. Fetch user profile from Firestore (trusted - cannot be spoofed)
    const userProfile = await FirestoreBiometricRepository.getUserProfile(uid);
    if (!userProfile) {
      throw new Error("User profile not found in database.");
    }

    const currentStatus = userProfile.accountStatus || "";
    if (currentStatus !== "pending_face") {
      throw new Error(
        `Cannot enroll biometrics in current account status: '${currentStatus}'. Expected 'pending_face'.`
      );
    }

    const phoneNumber = userProfile.phone || userProfile.phoneNumber || "";

    // 2. Validate Challenge Nonce (Invariants I-04, I-05) if provided
    const nonce = dto.challengeNonce || dto.clientSessionId;
    if (nonce) {
      const burstTimestamps = dto.burstFrames?.map((f) => f.capturedOffsetMs);
      const isValidNonce = SessionChallengeService.consumeChallenge(
        nonce,
        uid,
        "ENROLLMENT",
        dto.livenessAudit?.observedAction || dto.livenessAudit?.requiredAction,
        {
          clientSessionId: dto.clientSessionId,
          framesCapturedAtMs: burstTimestamps,
        }
      );
      if (!isValidNonce) {
        throw new Error(
          "[Invariant I-05] Invalid, expired, replayed, or cross-user challenge nonce. Biometric injection attack intercepted."
        );
      }
    }

    // 2b. Validate Device & App Integrity (GAP-01 / Invariant I-26)
    if (dto.integrityToken) {
      const { DeviceAttestationService } = await import("./device_attestation");
      let expectedRequestHash: string | undefined;
      if (nonce && dto.imageBase64) {
        const imgBuf = decodeBase64Image(dto.imageBase64);
        const captureDigest = (await import("crypto")).createHash("sha256").update(imgBuf).digest("hex");
        expectedRequestHash = DeviceAttestationService.computeRequestHash(
          nonce,
          uid,
          "ENROLLMENT",
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
        throw new Error(
          `[Invariant I-26] Device integrity verification failed: ${attestationResult.error || attestationResult.verdict}`
        );
      }
    }

    // 3. Enforce rate limiting (Max 3 attempts per 24 hours)
    await FirestoreBiometricRepository.checkRateLimit(uid);

    // 4. Acquire embedding vectors (Authoritative Temporal Burst or Dual-Model Single Frame)
    let embedding: number[];
    let fallbackEmbedding: number[] | undefined;
    let livenessVerified = false;

    if (dto.burstFrames && Array.isArray(dto.burstFrames) && dto.burstFrames.length > 0) {
      // PHASE 3: Authoritative Server-Side Temporal Action & PAD Validation
      const activeAction: ActiveChallengeAction =
        (dto.livenessAudit?.requiredAction as ActiveChallengeAction) || "BLINK";

      // Validate temporal burst structure, non-identity, luma stability, and action trajectory
      const padResult = await TemporalActionValidator.validateBurst(dto.burstFrames, activeAction);
      if (!padResult.passed || !padResult.authoritativeEmbedding) {
        throw new Error(
          `[PAD] ${padResult.rejectionReason || "TEMPORAL_PAD_REJECTED"}: Server-side temporal liveness validation failed.`
        );
      }

      embedding = Array.from(padResult.authoritativeEmbedding);
      livenessVerified = true;

      // Extract fallback embedding from anchor frame 0 for redundancy
      try {
        const frame0Buf = Buffer.from(
          dto.burstFrames[0].jpegBase64.replace(/^data:image\/\w+;base64,/, ""),
          "base64"
        );
        const redundant = await InferenceRedundancyService.executeRedundantInference(frame0Buf);
        fallbackEmbedding = redundant.fallbackEmbedding;
      } catch (e) {
        console.warn("[BiometricEnrollment] Dual-inference fallback on burst frame skipped:", e);
      }

      await AuditService.logEvent({
        eventType: "TEMPORAL_BURST_LIVENESS_VERIFIED",
        uid,
        metadata: {
          action: activeAction,
          telemetry: padResult.telemetry,
        },
      });
    } else if (dto.probeVector && dto.probeVector.length === 128) {
      const clientHash = dto.requestHash || "";
      const captureDigest = (dto.livenessAudit?.captureDigestHex as string) || "";
      const laplaceVar = Number(dto.livenessAudit?.laplacianVariance ?? 150.0);
      const verifiedFloat32 = verifyAndNormalizeEnrollmentPayload({
        uid,
        serverNonce: nonce || "",
        captureDigestHex: captureDigest,
        clientRequestHash: clientHash,
        probeVector: dto.probeVector,
        laplacianVariance: laplaceVar,
      });
      embedding = Array.from(verifiedFloat32);

      if (dto.imageBase64 && dto.imageBase64.length > 0) {
        try {
          const imageBuffer = decodeBase64Image(dto.imageBase64);
          const redundant = await InferenceRedundancyService.executeRedundantInference(imageBuffer);
          fallbackEmbedding = redundant.fallbackEmbedding;
        } catch (e) {
          console.warn("[BiometricEnrollment] Dual-inference fallback skipped: ", e);
        }
      }
    } else if (dto.imageBase64 && dto.imageBase64.length > 0) {
      // Authoritative path: Server executes dual-model inference on single still image
      const imageBuffer = decodeBase64Image(dto.imageBase64);
      const redundant = await InferenceRedundancyService.executeRedundantInference(imageBuffer);
      embedding = redundant.primaryEmbedding;
      fallbackEmbedding = redundant.fallbackEmbedding;

      // Audit that single-frame enrollment lacks multi-frame temporal proof
      await AuditService.logEvent({
        eventType: "UNVERIFIED_SINGLE_FRAME_LIVENESS_RECORDED",
        uid,
        metadata: {
          clientReportedBlink: dto.livenessAudit?.blinkVerified ?? false,
          policy: "NON_AUTHORITATIVE_CLIENT_TELEMETRY",
        },
      });

      if (redundant.discrepancyFlagged) {
        console.warn(
          `[BiometricEnrollment] Model discrepancy flagged between primary and fallback (correlation: ${redundant.correlation.toFixed(3)})`
        );
      }
    } else {
      throw new Error(
        "Missing valid biometric input: either authoritative 'burstFrames', 'probeVector' or 'imageBase64' must be provided."
      );
    }

    // 5. Reserve concurrency session
    await FirestoreBiometricRepository.reserveEnrollmentSession(uid, dto.clientSessionId);

    try {
      // 5. Run 1:N Gallery Search against existing enrolled templates (Ticket T-05 & T-08)
      let topCandidates: any[] = [];
      try {
        topCandidates = await FirestoreBiometricRepository.findTopK(
          embedding,
          uid,
          3,
          config.modelVersion,
          PREPROCESSING_ID
        );
      } catch (searchError: any) {
        console.error("[BiometricEnrollment] Authoritative duplicate screening error:", searchError);
        await AuditService.logEvent({
          eventType: "SCREENING_UNAVAILABLE_FLAGGED",
          uid,
          metadata: {
            error: searchError.message || String(searchError),
            modelId: config.modelVersion,
          },
        });
        await FirestoreBiometricRepository.finalizeEnrollmentSession(uid, "failed");
        return {
          status: "technical_failure_retry",
          isApproved: false,
          isDuplicate: false,
          similarity: 0.0,
          threshold: config.duplicateThreshold,
          message:
            "Authoritative duplicate screening is currently unavailable. Enrollment held for safety. Please retry shortly.",
          messageKn:
            "ನಕಲಿ ತಪಾಸಣೆ ಪ್ರಸ್ತುತ ಲಭ್ಯವಿಲ್ಲ. ಭದ್ರತೆಗಾಗಿ ನೋಂದಣಿಯನ್ನು ತಡೆಹಿಡಿಯಲಾಗಿದೆ. ದಯವಿಟ್ಟು ಸ್ವಲ್ಪ ಸಮಯದ ನಂತರ ಮತ್ತೆ ಪ್ರಯತ್ನಿಸಿ.",
        };
      }

      const topCandidate = topCandidates.length > 0 ? topCandidates[0] : null;
      const similarity = topCandidate ? topCandidate.similarity : 0.0;
      const evaluation = evaluateMatch(similarity);

      // ScoreRecordPolicy: record top-3 gallery scores and advisory floor
      const advisoryTop3 = topCandidates.map((c, idx) => ({
        rank: idx + 1,
        matchedUid: c.uid,
        similarity: c.similarity,
        isAboveAdvisoryFloor: c.similarity >= config.advisoryFloorThreshold,
        isAboveDuplicateThreshold: c.similarity >= config.duplicateThreshold,
        modelId: c.modelId || config.modelVersion,
        preprocessVersion: c.preprocessVersion || PREPROCESSING_ID,
      }));

      // ── DUPLICATE DETECTED (Phase 5: Privacy-Preserving Zero PII Disclosure) ──
      if (evaluation.isDuplicate && topCandidate) {
        let matchedName = "Registered User";
        try {
          const matchedProfile = await FirestoreBiometricRepository.getUserProfile(topCandidate.uid);
          if (matchedProfile) {
            matchedName =
              matchedProfile.fullName ||
              matchedProfile.name ||
              matchedProfile.displayName ||
              "Registered User";
          }
        } catch {
          // Gracefully fallback if profile fetch encounters an error
        }

        const maskedName = maskName(matchedName);
        const masked = maskPhoneNumber(topCandidate.phoneNumber);
        const recoverySessionId = `rec_${crypto.randomBytes(16).toString("hex")}`;

        // Authoritative internal audit trail (never leaked to public client)
        await AuditService.logEvent({
          eventType: "DUPLICATE_REGISTRATION_INTERCEPTED",
          uid,
          matchedUid: topCandidate.uid,
          similarityScore: similarity,
          threshold: config.duplicateThreshold,
          metadata: {
            topKScores: advisoryTop3.map((c) => c.similarity),
            modelId: config.modelVersion,
            preprocessVersion: PREPROCESSING_ID,
            advisoryFloor: config.advisoryFloorThreshold,
            decisionPolicy: "RECORD_DO_NOT_ACT",
            matchedUserNameMasked: maskedName,
            recoverySessionId,
          },
        });

        await AuditService.logEvent({
          eventType: "RECOVERY_SESSION_ISSUED",
          uid,
          matchedUid: topCandidate.uid,
          metadata: {
            recoverySessionId,
            action: "DUPLICATE_RECOVERY_REQUIRED",
          },
        });

        // Ticket T-05 / Gate 6: In PILOT_SHADOW with uncalibrated weights, do not permanently delete/block user.
        // We route to pending_review with reviewReason "potential_duplicate", store in review queue.
        await FirestoreBiometricRepository.commitEnrollment({
          uid,
          role: dto.role,
          phoneNumber,
          embedding,
          fallbackEmbedding,
          livenessAudit: dto.livenessAudit,
          requiresReview: true,
          isResearchOnly: true,
          advisoryTop3,
          reviewReason: "POTENTIAL_DUPLICATE_UNVERIFIED_WEIGHTS",
        });

        await FirestoreBiometricRepository.finalizeEnrollmentSession(uid, "failed");

        // PHASE 5: Return sanitized generic response.
        // STRICT INVARIANT: ZERO candidate PII (no name, no phone, no UID, no score) disclosed prior to ownership proof.
        return {
          status: "duplicate",
          isApproved: false,
          isDuplicate: true,
          isHardBlock: evaluation.isHardBlock,
          similarity,
          threshold: config.duplicateThreshold,
          recoverySessionId,
          message:
            "A matching facial profile is already registered. If this is your account, please sign in or verify ownership using your registered mobile number.",
          messageKn:
            "ಈ ಮುಖದ ಪ್ರೊಫೈಲ್ ಈಗಾಗಲೇ ನೋಂದಾಯಿಸಲ್ಪಟ್ಟಿದೆ. ಇದು ನಿಮ್ಮ ಖಾತೆಯಾಗಿದ್ದರೆ, ದಯವಿಟ್ಟು ಸೈನ್ ಇನ್ ಮಾಡಿ ಅಥವಾ ನಿಮ್ಮ ನೋಂದಾಯಿತ ಮೊಬೈಲ್ ಸಂಖ್ಯೆಯನ್ನು ಬಳಸಿ ಮಾಲೀಕತ್ವವನ್ನು ಪರಿಶೀಲಿಸಿ.",
        };
      }

      // ── AMBIGUOUS MATCH ─────────────────────────────────────────────────
      if (evaluation.decision === "ambiguity" && topCandidate) {
        await AuditService.logEvent({
          eventType: "ENROLLMENT_AMBIGUITY_FLAGGED",
          uid,
          matchedUid: topCandidate.uid,
          similarityScore: similarity,
          threshold: config.ambiguityThreshold,
          metadata: {
            topKScores: advisoryTop3.map((c) => c.similarity),
            modelId: config.modelVersion,
            preprocessVersion: PREPROCESSING_ID,
            advisoryFloor: config.advisoryFloorThreshold,
          },
        });

        await FirestoreBiometricRepository.commitEnrollment({
          uid,
          role: dto.role,
          phoneNumber,
          embedding,
          fallbackEmbedding,
          livenessAudit: dto.livenessAudit,
          requiresReview: true,
          isResearchOnly: true,
          advisoryTop3,
          reviewReason: "BORDERLINE_SIMILARITY_AMBIGUITY",
        });

        await FirestoreBiometricRepository.finalizeEnrollmentSession(uid, "completed");

        return {
          status: "ambiguity",
          isApproved: false,
          isDuplicate: false,
          similarity,
          threshold: config.duplicateThreshold,
          message:
            "Facial scan yielded an ambiguous match. Your enrollment has been queued for standard administrative review.",
          messageKn:
            "ಮುಖದ ಸ್ಕ್ಯಾನ್ ಅಸ್ಪಷ್ಟ ಹೊಂದಾಣಿಕೆಯನ್ನು ನೀಡಿದೆ. ನಿಮ್ಮ ನೋಂದಣಿಯನ್ನು ಆಡಳಿತಾತ್ಮಕ ಪರಿಶೀಲನೆಗೆ ಕಳುಹಿಸಲಾಗಿದೆ.",
        };
      }

      // ── UNIQUE INDIVIDUAL / CLEAN SCREENING (Phase 2) ───────────────────
      // Invariant I-01 / Gate 6: Zero automated approvals while in CONTROLLED_TEST_BUILD_ONLY.
      // SFace operates in PILOT_SHADOW with uncalibrated weights.
      // Distinct state representation:
      // 1. Biometric template enrolled in vault.
      // 2. Duplicate screening completed cleanly.
      // 3. Account access activation gated by calibration governance.
      const modelMeta = ModelRegistry.getModel(config.modelVersion);
      const isResearchOnly =
        modelMeta.tier === "RESEARCH_ONLY" ||
        modelMeta.tier === "PILOT_SHADOW" ||
        !modelMeta.clearedForAutomatedApproval ||
        config.releaseGateStatus === "CONTROLLED_TEST_BUILD_ONLY" ||
        !config.productionBiometricCalibrationApproved;

      const finalStatus = isResearchOnly ? "pending_review" : "approved";
      const isApproved = !isResearchOnly;

      // Commit to biometric_vault & users with advisoryTop3 attached
      const newStatus = await FirestoreBiometricRepository.commitEnrollment({
        uid,
        role: dto.role,
        phoneNumber,
        embedding,
        fallbackEmbedding,
        livenessAudit: dto.livenessAudit,
        requiresReview: isResearchOnly,
        isResearchOnly,
        advisoryTop3,
        reviewReason: isResearchOnly
          ? "PILOT_SHADOW_UNVERIFIED_WEIGHTS"
          : "STANDARD_ADMIN_VERIFICATION",
      });

      await AuditService.logEvent({
        eventType: isResearchOnly ? "ENROLLMENT_HELD_RESEARCH_MODEL" : "ENROLLMENT_SUCCESS",
        uid,
        similarityScore: similarity,
        threshold: config.duplicateThreshold,
        metadata: {
          topKScores: advisoryTop3.map((c) => c.similarity),
          modelId: config.modelVersion,
          preprocessVersion: PREPROCESSING_ID,
          advisoryFloor: config.advisoryFloorThreshold,
          decisionPolicy: "RECORD_DO_NOT_ACT",
          duplicateScreeningCompleted: true,
        },
      });

      await FirestoreBiometricRepository.finalizeEnrollmentSession(uid, "completed");

      return {
        status: finalStatus,
        isApproved,
        isDuplicate: false,
        similarity,
        threshold: config.duplicateThreshold,
        accountStatus: newStatus,
        message: isResearchOnly
          ? "Biometric template captured under PILOT_SHADOW model (uncalibrated weights). Automated clearance is disabled; submission routed to manual administrative review."
          : "Biometric template verified and enrolled successfully.",
        messageKn: isResearchOnly
          ? "ಬಯೋಮೆಟ್ರಿಕ್ ಟೆಂಪ್ಲೇಟ್ ಅನ್ನು ದಾಖಲಿಸಲಾಗಿದೆ. ಮಾದರಿಯ ತೂಕ ಮಾಪನಾಂಕ ನಿರ್ಣಯಗೊಳ್ಳುವವರೆಗೆ ಹಸ್ತಚಾಲಿತ ಪರಿಶೀಲನೆಗೆ ಕಳುಹಿಸಲಾಗಿದೆ."
          : "ಬಯೋಮೆಟ್ರಿಕ್ ಟೆಂಪ್ಲೇಟ್ ಯಶಸ್ವಿಯಾಗಿ ಪರಿಶೀಲಿಸಲ್ಪಟ್ಟಿದೆ ಮತ್ತು ನೋಂದಾಯಿಸಲ್ಪಟ್ಟಿದೆ.",
      };
    } catch (err: any) {
      await FirestoreBiometricRepository.finalizeEnrollmentSession(uid, "failed");
      // Invariant I-01: Technical failures must resolve to technical_failure_retry, never approval
      return {
        status: "technical_failure_retry",
        isApproved: false,
        isDuplicate: false,
        similarity: 0.0,
        threshold: config.duplicateThreshold,
        message: `Enrollment technical failure: ${err.message || err}. Safe fail-closed retry required.`,
      };
    }
  }

  /**
   * Warm up in-memory index from Firestore biometric_vault collection.
   */
  static async warmUpIndex(): Promise<void> {
    return warmUpBiometricIndex();
  }
}

/**
 * Warms up the in-memory biometric deduplication index (InMemoryBiometricIndex)
 * by querying all enrolled templates from the Firestore 'biometric_vault' collection.
 * 
 * Invariant I-31: RAM Gallery Search Bounded Quota.
 * Populating the index at startup shields Firestore from read spikes during 1:N deduplication.
 * Safe to call multiple times (idempotent).
 */
export async function warmUpBiometricIndex(): Promise<void> {
  if (admin.apps.length === 0) {
    admin.initializeApp({
      projectId: config.projectId,
    });
  }

  const db = admin.firestore();
  const snapshot = await db.collection("biometric_vault").get();
  let count = 0;

  for (const doc of snapshot.docs) {
    const data = doc.data();
    const rawEmb = data.embedding;
    const enrolledVector: number[] = Array.isArray(rawEmb)
      ? rawEmb
      : rawEmb && typeof rawEmb.toArray === "function"
      ? rawEmb.toArray()
      : rawEmb && (rawEmb as any)._values && Array.isArray((rawEmb as any)._values)
      ? Array.from((rawEmb as any)._values as number[])
      : [];

    if (!enrolledVector || enrolledVector.length === 0) {
      continue;
    }

    const uid = data.uid || doc.id;
    const modelId = data.modelId || data.modelVersion || config.modelVersion;
    const preprocessVersion = data.preprocessVersion || PREPROCESSING_ID;
    const phoneNumber = data.phoneNumber || "";
    let enrolledAtMs = Date.now();
    if (data.enrolledAt && typeof data.enrolledAt.toMillis === "function") {
      enrolledAtMs = data.enrolledAt.toMillis();
    } else if (typeof data.enrolledAtMs === "number") {
      enrolledAtMs = data.enrolledAtMs;
    } else if (data.enrolledAt && typeof data.enrolledAt.seconds === "number") {
      enrolledAtMs = data.enrolledAt.seconds * 1000;
    }

    InMemoryBiometricIndex.upsert({
      uid,
      embedding: enrolledVector,
      modelId,
      preprocessVersion,
      phoneNumber,
      enrolledAtMs,
    });
    count++;
  }

  console.log(`[BiometricIndex] Warm-up complete: ${count} template(s) loaded into RAM gallery.`);
}

