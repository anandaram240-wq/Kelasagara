// FILE: backend/src/routes/face_v10_pilot_routes.ts

import { Router, Request, Response } from "express";
import { randomUUID } from "crypto";
import { SfaceOnnxSessionPoolV10 } from "../biometrics/sface_onnx_session_pool_v10";
import {
  EmpiricalCorpusEvaluatorV10,
  ParticipantCaptureRecord,
} from "../biometrics/empirical_corpus_evaluator_v10";
import {
  HumanReviewWorkflowServiceV10,
  ReviewDecisionOutcome,
} from "../biometrics/human_review_workflow_service_v10";
import { FieldStudyConsentLedgerV10 } from "../biometrics/field_study_consent_ledger_v10";
import { WriteThroughBiometricStoreV10 } from "../biometrics/pilot_gallery_persistence_v10";

export interface EnrolledIdentityRecord {
  uid: string;
  faceId: string;
  biometricLockToken: string;
  name: string;
  phone: string;
  primarySkill: string;
  dailyRate: number;
  embedding: number[]; // 128-D L2-normalized SFace vector
  biometricStatus: "LOCKED_ACTIVE" | "UNLOCKED_FOR_ROTATION" | "PENDING_REVIEW";
  enrollmentVersion: number;
  updatedAtIso: string;
}

export interface FaceV10PilotControllerOptions {
  db?: any; // Firestore instance if available
  onPersistRecord?: (record: EnrolledIdentityRecord) => Promise<void>;
  persistenceStore?: WriteThroughBiometricStoreV10;
}

export class FaceV10PilotController {
  public readonly router: Router = Router();
  public readonly reviewService = new HumanReviewWorkflowServiceV10();
  public readonly consentLedger = new FieldStudyConsentLedgerV10();
  public readonly persistenceStore: WriteThroughBiometricStoreV10;

  // In-memory / repository-backed active gallery & pilot study store
  private readonly gallery: Map<string, EnrolledIdentityRecord>;
  private readonly pilotCaptures: ParticipantCaptureRecord[] = [];

  public static readonly THRESHOLD_1TO1_EKYC = 0.40;
  public static readonly THRESHOLD_1TON_CLEAN = 0.363;
  public static readonly THRESHOLD_1TON_DUPLICATE = 0.55;

  constructor(private readonly options: FaceV10PilotControllerOptions = {}) {
    this.persistenceStore =
      options.persistenceStore ?? new WriteThroughBiometricStoreV10(options.db);
    this.gallery = this.persistenceStore.getMemoryCacheMap();
    this.initializeRoutes();
    if (this.options.db) {
      this.persistenceStore.warmupFromFirestore().catch((err: any) =>
        console.warn("WARN_PILOT_WARMUP_FROM_FIRESTORE:", err?.message ?? err)
      );
    }
  }

  private async persistEnrolledRecord(record: EnrolledIdentityRecord): Promise<void> {
    if (this.options.onPersistRecord) {
      await this.options.onPersistRecord(record);
      return;
    }
    await this.persistenceStore.saveEnrolledIdentity(record);
  }

  private initializeRoutes(): void {
    this.router.post("/enroll", this.handleEnrollOrReRegister.bind(this));
    this.router.post("/verify-ekyc", this.handleOneToOneEkyc.bind(this));
    this.router.post("/unlock-for-rotation", this.handleStepUpUnlock.bind(this));
    this.router.get("/reviews", this.handleListReviewCases.bind(this));
    this.router.post("/reviews/:caseId/adjudicate", this.handleAdjudicateCase.bind(this));
    this.router.post("/pilot/consent", this.handleGrantPilotConsent.bind(this));
    this.router.post("/pilot/consent/:consentReceiptId/withdraw", this.handleWithdrawConsent.bind(this));
    this.router.post("/pilot/capture", this.handleRecordPilotCapture.bind(this));
    this.router.get("/pilot/calibration-report", this.handleGetCalibrationReport.bind(this));
  }

  /**
   * 1. POST /api/v10/biometrics/enroll
   * Handles both INITIAL_ENROLLMENT and AUTHORIZED_RE_REGISTRATION with strict self-exclusion,
   * one-time lock token enforcement, and Masked Original Account Proof on duplicate detection.
   */
  public async handleEnrollOrReRegister(req: Request, res: Response): Promise<void> {
    try {
      const {
        uid,
        name = "Worker",
        phone = "+910000000000",
        primarySkill = "Service Partner",
        dailyRate = 800,
        mode = "INITIAL_ENROLLMENT",
        embedding,
        rgbFloat32Tensor,
      } = req.body;

      if (!uid || typeof uid !== "string") {
        res.status(400).json({ success: false, error: "ERR_MISSING_UID" });
        return;
      }

      const existingOwnRecord = this.gallery.get(uid);

      // Gate A: Block duplicate initial registration on an already locked account
      if (
        mode === "INITIAL_ENROLLMENT" &&
        existingOwnRecord &&
        existingOwnRecord.biometricStatus === "LOCKED_ACTIVE"
      ) {
        res.status(200).json({
          success: false,
          status: "ALREADY_REGISTERED_LOCKED",
          uid,
          faceId: existingOwnRecord.faceId,
          biometricLockToken: existingOwnRecord.biometricLockToken,
          faceVerified: true,
          accountStatus: "approved",
          message:
            "This account already has a permanently locked Face ID. Re-registration is disabled.",
        });
        return;
      }

      // Gate B: Require explicit step-up unlock before AUTHORIZED_RE_REGISTRATION
      if (
        mode === "AUTHORIZED_RE_REGISTRATION" &&
        existingOwnRecord &&
        existingOwnRecord.biometricStatus === "LOCKED_ACTIVE"
      ) {
        res.status(403).json({
          success: false,
          status: "ERR_BIOMETRIC_LOCKED",
          uid,
          faceId: existingOwnRecord.faceId,
          biometricLockToken: existingOwnRecord.biometricLockToken,
          message:
            "Account Face ID is locked. Complete 1:1 step-up verification (/unlock-for-rotation) before updating face.",
        });
        return;
      }

      // Step 1: Extract or validate 128-D L2-normalized SFace embedding
      const liveEmbedding = await this.resolveNormalizedSfaceVector(embedding, rgbFloat32Tensor);

      // Step 2: 1:N Search across all OTHER accounts (Strictly excluding caller's own UID!)
      let bestCandidate: EnrolledIdentityRecord | null = null;
      let maxSim = -1.0;

      for (const [candidateUid, record] of this.gallery.entries()) {
        // CRITICAL SELF-EXCLUSION: Prevents "You Already Exist" when re-registering!
        if (candidateUid === uid) continue;
        if (record.biometricStatus === "PENDING_REVIEW") continue;

        const sim = EmpiricalCorpusEvaluatorV10.cosineSimilarity(liveEmbedding, record.embedding);
        if (sim > maxSim) {
          maxSim = sim;
          bestCandidate = record;
        }
      }

      // Step 3: Zone 3/4 Duplicate Caught -> Return generic privacy-preserving error with opaque caseReference
      if (bestCandidate && maxSim >= FaceV10PilotController.THRESHOLD_1TON_DUPLICATE) {
        const caseReference = `CASE-${randomUUID().slice(0, 8).toUpperCase()}`;
        res.status(409).json({
          success: false,
          status: "DUPLICATE_ACCOUNT_DETECTED",
          uid,
          faceVerified: false,
          existingAccountLocked: false, // Safety invariant: never lock the matched worker!
          caseReference,
          message:
            `Duplicate Account Creation Detected: This biometric profile matches an existing registered account. Please sign in to your original account or contact support with reference ${caseReference}.`,
        });
        return;
      }

      // Step 4: Zone 2 Ambiguous Match (0.363 <= Sim < 0.550) -> Open Operational Human Review Case
      if (bestCandidate && maxSim >= FaceV10PilotController.THRESHOLD_1TON_CLEAN) {
        const reviewCase = this.reviewService.openReviewCase({
          applicantUid: uid,
          matchedCandidateUid: bestCandidate.uid,
          matchedCandidateName: bestCandidate.name,
          matchedCandidatePhone: bestCandidate.phone,
          matchedCandidateRole: bestCandidate.primarySkill,
          stage1CosineScore: maxSim,
          stage2CosineScore: null,
          applicantEmbedding: liveEmbedding,
        });

        res.status(202).json({
          success: false,
          status: "AMBIGUOUS_PENDING_REVIEW",
          uid,
          faceVerified: false,
          accountStatus: "pending_review",
          reviewCaseId: reviewCase.caseId,
          existingAccountLocked: false,
          candidateEvidence: reviewCase.candidateEvidence,
          message: "Biometric capture routed to human review queue for verification.",
        });
        return;
      }

      // Step 5: Zone 1 Clean Identity (< 0.363) -> Bind UID <-> FaceID & Mint Lock Token
      const nextVersion = (existingOwnRecord?.enrollmentVersion ?? 0) + 1;
      const faceId = existingOwnRecord?.faceId ?? `KS_FACE_${uid.slice(-6).toUpperCase()}`;
      const lockToken = `KS_FTOK_${Buffer.from(
        `v${nextVersion}:${Date.now()}:${uid}:${faceId}`
      )
        .toString("base64url")
        .slice(0, 20)
        .toUpperCase()}`;

      const enrolled: EnrolledIdentityRecord = {
        uid,
        faceId,
        biometricLockToken: lockToken,
        name,
        phone,
        primarySkill,
        dailyRate: Number(dailyRate),
        embedding: liveEmbedding,
        biometricStatus: "LOCKED_ACTIVE",
        enrollmentVersion: nextVersion,
        updatedAtIso: new Date().toISOString(),
      };

      this.gallery.set(uid, enrolled);
      await this.persistEnrolledRecord(enrolled);

      res.status(200).json({
        success: true,
        status:
          mode === "AUTHORIZED_RE_REGISTRATION"
            ? "RE_REGISTERED_AND_LOCKED"
            : "ENROLLED_AND_LOCKED",
        uid,
        faceId,
        biometricLockToken: lockToken,
        enrollmentVersion: nextVersion,
        faceVerified: true,
        accountStatus: "approved",
        message: "Face ID registered and permanently locked to your primary account.",
      });
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : "UNKNOWN_BIOMETRIC_ERROR";
      res.status(400).json({ success: false, error: msg });
    }
  }

  /**
   * 2. POST /api/v10/biometrics/verify-ekyc
   * Runs 1:1 verification against the user's own locked Face ID (never triggers 1:N duplicate blocks).
   */
  public async handleOneToOneEkyc(req: Request, res: Response): Promise<void> {
    try {
      const { uid, embedding, rgbFloat32Tensor } = req.body;
      const record = this.gallery.get(uid);
      if (!record) {
        res.status(404).json({
          success: false,
          status: "ERR_NO_ENROLLED_FACE",
          message: "No enrolled Face ID found for this account.",
        });
        return;
      }

      const liveEmbedding = await this.resolveNormalizedSfaceVector(embedding, rgbFloat32Tensor);
      const sim1to1 = EmpiricalCorpusEvaluatorV10.cosineSimilarity(
        liveEmbedding,
        record.embedding
      );
      const verified = sim1to1 >= FaceV10PilotController.THRESHOLD_1TO1_EKYC;

      res.status(200).json({
        success: verified,
        status: verified ? "EKYC_1TO1_VERIFIED" : "EKYC_1TO1_FAILED",
        uid,
        faceId: record.faceId,
        biometricLockToken: record.biometricLockToken,
        faceVerified: verified,
        similarityScore: Number(sim1to1.toFixed(4)),
        message: verified
          ? "1:1 Biometric eKYC verification passed."
          : "Live face does not match the registered account owner.",
      });
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : "UNKNOWN_EKYC_ERROR";
      res.status(400).json({ success: false, error: msg });
    }
  }

  /**
   * 3. POST /api/v10/biometrics/unlock-for-rotation
   * Unlocks a locked account for one-time AUTHORIZED_RE_REGISTRATION after verifying 1:1 match.
   */
  public async handleStepUpUnlock(req: Request, res: Response): Promise<void> {
    try {
      const { uid, embedding, rgbFloat32Tensor } = req.body;
      const record = this.gallery.get(uid);
      if (!record) {
        res.status(404).json({ success: false, error: "ERR_NO_ENROLLED_FACE" });
        return;
      }

      const liveEmbedding = await this.resolveNormalizedSfaceVector(embedding, rgbFloat32Tensor);
      const sim = EmpiricalCorpusEvaluatorV10.cosineSimilarity(liveEmbedding, record.embedding);

      if (sim < FaceV10PilotController.THRESHOLD_1TO1_EKYC) {
        res.status(403).json({
          success: false,
          status: "STEP_UP_1TO1_FAILED",
          similarityScore: Number(sim.toFixed(4)),
          message: "Cannot unlock Face ID: live scan did not match existing registered face.",
        });
        return;
      }

      record.biometricStatus = "UNLOCKED_FOR_ROTATION";
      await this.persistEnrolledRecord(record);
      res.status(200).json({
        success: true,
        status: "UNLOCKED_FOR_ROTATION",
        uid,
        faceId: record.faceId,
        message: "Account unlocked for one-time authorized face re-registration.",
      });
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : "UNKNOWN_UNLOCK_ERROR";
      res.status(400).json({ success: false, error: msg });
    }
  }

  /**
   * 4. Human Review Endpoints (Gate 7 Operational Workflow)
   */
  public handleListReviewCases(_req: Request, res: Response): void {
    res.status(200).json({
      success: true,
      auditChainIntact: this.reviewService.verifyAuditChainIntegrity(),
    });
  }

  public handleAdjudicateCase(req: Request, res: Response): void {
    try {
      const { caseId } = req.params;
      const { reviewerId, reviewerRole, decision, justification } = req.body;

      const result = this.reviewService.adjudicateCase({
        caseId,
        reviewerId,
        reviewerRole,
        decision: decision as ReviewDecisionOutcome,
        justification,
      });

      res.status(200).json({
        success: true,
        ...result,
        auditChainIntact: this.reviewService.verifyAuditChainIntegrity(),
      });
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : "ERR_ADJUDICATION_FAILED";
      res.status(400).json({ success: false, error: msg });
    }
  }

  /**
   * 5. Field Pilot Calibration Study Endpoints (Gate 3 & Gate 5: N >= 30 Real Participants)
   */
  public handleGrantPilotConsent(req: Request, res: Response): void {
    try {
      const { participantId, isAdult18PlusConfirmed } = req.body;
      const record = this.consentLedger.grantConsent({
        participantId,
        isAdult18PlusConfirmed: Boolean(isAdult18PlusConfirmed),
      });
      res.status(201).json({ success: true, consent: record });
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : "ERR_CONSENT_FAILED";
      res.status(400).json({ success: false, error: msg });
    }
  }

  public handleWithdrawConsent(req: Request, res: Response): void {
    try {
      const { consentReceiptId } = req.params;
      const withdrawn = this.consentLedger.withdrawConsentAndPurge(
        consentReceiptId,
        (purgedParticipantId) => {
          for (let i = this.pilotCaptures.length - 1; i >= 0; i--) {
            if (this.pilotCaptures[i].participantId === purgedParticipantId) {
              this.pilotCaptures.splice(i, 1);
            }
          }
        }
      );
      res.status(200).json({ success: true, withdrawn });
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : "ERR_WITHDRAW_FAILED";
      res.status(400).json({ success: false, error: msg });
    }
  }

  public async handleRecordPilotCapture(req: Request, res: Response): Promise<void> {
    try {
      const {
        participantId,
        consentReceiptId,
        sessionNumber,
        captureIndex,
        embedding,
        rgbFloat32Tensor,
        deviceModel = "ANDROID_ARM64",
      } = req.body;

      const vec = await this.resolveNormalizedSfaceVector(embedding, rgbFloat32Tensor);
      const record: ParticipantCaptureRecord = {
        participantId,
        consentReceiptId,
        sessionNumber: sessionNumber === 2 ? 2 : 1,
        captureIndex: Number(captureIndex) || 1,
        embedding: vec,
        capturedAtIso: new Date().toISOString(),
        deviceModel,
      };

      this.pilotCaptures.push(record);
      res.status(201).json({
        success: true,
        totalCapturesRecorded: this.pilotCaptures.length,
      });
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : "ERR_CAPTURE_FAILED";
      res.status(400).json({ success: false, error: msg });
    }
  }

  public handleGetCalibrationReport(_req: Request, res: Response): void {
    try {
      const report = EmpiricalCorpusEvaluatorV10.evaluateRealCorpus({
        captures: this.pilotCaptures,
        verifiedConsentIds: this.consentLedger.getActiveConsentReceiptIds(),
      });
      res.status(200).json({ success: true, report });
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : "ERR_REPORT_FAILED";
      res.status(400).json({ success: false, error: msg });
    }
  }

  private async resolveNormalizedSfaceVector(
    precomputedEmbedding?: number[] | Float32Array,
    rgbFloat32Tensor?: number[] | Float32Array
  ): Promise<number[]> {
    if (
      (Array.isArray(precomputedEmbedding) || ArrayBuffer.isView(precomputedEmbedding)) &&
      (precomputedEmbedding as any).length === 128
    ) {
      let sumSq = 0;
      for (const v of precomputedEmbedding as any) sumSq += v * v;
      const norm = Math.sqrt(sumSq);
      if (norm < 1e-8) throw new Error("ERR_ZERO_NORM_EMBEDDING");
      return Array.from(precomputedEmbedding as any).map((v: any) => v / norm);
    }

    if (
      (Array.isArray(rgbFloat32Tensor) || rgbFloat32Tensor instanceof Float32Array) &&
      (rgbFloat32Tensor as any).length === 1 * 3 * 112 * 112
    ) {
      const floatArr =
        rgbFloat32Tensor instanceof Float32Array
          ? rgbFloat32Tensor
          : new Float32Array(rgbFloat32Tensor);
      const { embedding } = await SfaceOnnxSessionPoolV10.inferNormalizedEmbedding(floatArr);
      return embedding;
    }

    throw new Error(
      "ERR_INVALID_BIOMETRIC_PAYLOAD: Provide either a 128-D SFace embedding or a 1x3x112x112 RGB Float32 tensor."
    );
  }
}
