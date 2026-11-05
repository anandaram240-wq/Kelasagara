// FILE: backend/src/routes/face_v11_routes.ts

import { Router, Request, Response } from "express";
import crypto from "crypto";
import {
  Arcface512SessionPoolV11,
  QualityWeightedFrame,
  BiometricModelVersion,
} from "../biometrics/arcface_512_session_pool_v11";
import {
  PadLivenessFiqaGuardV11,
  FiqaEvaluationInput,
} from "../biometrics/pad_liveness_fiqa_guard_v11";
import {
  BiometricCryptographicVaultV11,
  EncryptedBiometricEnvelopeV11,
  HnswBiometricIndexV11,
} from "../biometrics/encrypted_hnsw_vault_v11";
import {
  EmpiricalRocCalibratorV11,
  ParticipantRecordV11,
  CalibrationCertificateV11,
  StepUpChallengeTokenV11,
  StepUpChallengeResponseV11,
} from "../biometrics/empirical_roc_calibrator_v11";

export interface EnrolledIdentityRecordV11 {
  uid: string;
  faceId: string;
  biometricLockToken: string;
  name: string;
  phone: string;
  primarySkill: string;
  dailyRate: number;
  envelope: EncryptedBiometricEnvelopeV11;
  modelVersion: BiometricModelVersion;
  dimension: 512 | 128;
  biometricStatus: "LOCKED_ACTIVE" | "UNLOCKED_FOR_ROTATION" | "STEP_UP_CHALLENGE_REQUIRED" | "PENDING_REVIEW";
  enrollmentVersion: number;
  averageFiqaQuality: number;
  updatedAtIso: string;
}

export interface FaceV11ControllerOptions {
  db?: any;
  masterKey?: string;
}

export class FaceV11ProductionController {
  public readonly router: Router = Router();
  public readonly hnswIndex = new HnswBiometricIndexV11();
  private readonly recordsMap = new Map<string, EnrolledIdentityRecordV11>();
  private readonly rawEmbeddingsCache = new Map<string, number[]>(); // In-memory plaintext cache for fast verification
  private readonly calibrationCorpus: ParticipantRecordV11[] = [];

  // Production calibrated operating thresholds
  public static readonly TAU_HIGH_512 = 0.62;
  public static readonly TAU_LOW_512 = 0.48;
  public static readonly TAU_HIGH_128 = 0.363;
  public static readonly TAU_LOW_128 = 0.320;
  public static readonly VERIFY_1TO1_512 = 0.60;
  public static readonly VERIFY_1TO1_128 = 0.40;

  constructor(private readonly options: FaceV11ControllerOptions = {}) {
    this.initializeRoutes();
  }

  private initializeRoutes(): void {
    this.router.get("/status", this.handleGetStatus.bind(this));
    this.router.post("/enroll", this.handleEnrollOrReRegister.bind(this));
    this.router.post("/verify-ekyc", this.handleOneToOneEkyc.bind(this));
    this.router.post("/challenge/request", this.handleRequestChallenge.bind(this));
    this.router.post("/challenge/verify", this.handleVerifyChallenge.bind(this));
    this.router.post("/calibrate", this.handleCalibrateCorpus.bind(this));
    this.router.post("/unlock-for-rotation", this.handleUnlockForRotation.bind(this));
  }

  /**
   * Helper to mask phone numbers (+919876543210 -> +91******3210)
   */
  private maskPhone(phone: string): string {
    if (phone.length <= 6) return phone;
    const prefix = phone.slice(0, 3);
    const suffix = phone.slice(-4);
    return `${prefix}${"*".repeat(phone.length - 7)}${suffix}`;
  }

  /**
   * GET /api/v11/biometrics/status
   */
  public handleGetStatus(_req: Request, res: Response): void {
    res.status(200).json({
      status: "ONLINE",
      version: "V11.0_PRODUCTION",
      embeddingBackbone: "ArcFace/AdaFace 512-D + Umeyama 5-Point Affine Alignment",
      encryptionCipher: "AES-256-GCM Envelope Encryption (DPDP Rules 2025 compliant)",
      indexer: "HNSW O(log N) Sub-Linear Cosine Graph Index",
      activeEnrolledIdentities: this.recordsMap.size,
      hnswIndexSize: this.hnswIndex.size,
      calibrationCorpusSize: this.calibrationCorpus.length,
      thresholds: {
        adaface512: {
          tauHigh: FaceV11ProductionController.TAU_HIGH_512,
          tauLow: FaceV11ProductionController.TAU_LOW_512,
          verify1to1: FaceV11ProductionController.VERIFY_1TO1_512,
        },
        sface128: {
          tauHigh: FaceV11ProductionController.TAU_HIGH_128,
          tauLow: FaceV11ProductionController.TAU_LOW_128,
          verify1to1: FaceV11ProductionController.VERIFY_1TO1_128,
        },
      },
    });
  }

  /**
   * POST /api/v11/biometrics/enroll
   * Production-grade enrollment:
   * 1. FIQA gate (sharpness, illumination, pose)
   * 2. Passive PAD anti-spoof check
   * 3. 3-Frame quality-weighted centroid fusion
   * 4. HNSW sub-linear 1:N deduplication
   * 5. Grey-Zone ambiguity step-up challenge routing
   * 6. AES-256-GCM envelope encryption at rest
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
        frames,
        embedding,
        fiqaInput,
        padTextureMap,
      } = req.body;

      if (!uid || typeof uid !== "string") {
        res.status(400).json({ error: "ERR_MISSING_UID: uid is required." });
        return;
      }

      // Step 1: Pre-Inference FIQA Gate
      if (fiqaInput) {
        const fiqaReport = PadLivenessFiqaGuardV11.evaluateFrameQuality(fiqaInput as FiqaEvaluationInput);
        if (!fiqaReport.isAcceptable) {
          res.status(422).json({
            error: "ERR_FIQA_REJECTED",
            message: `Face capture failed quality check: ${fiqaReport.rejectionReason}`,
            fiqaReport,
          });
          return;
        }
      }

      // Step 2: Passive Anti-Spoofing (PAD) Check
      if (padTextureMap) {
        const padResult = PadLivenessFiqaGuardV11.evaluatePassiveLiveness(padTextureMap);
        if (!padResult.isLive) {
          res.status(422).json({
            error: padResult.rejectionCode || "ERR_PAD_SPOOF_DETECTED",
            message: `Presentation attack detected: ${padResult.spoofCategory}`,
            padResult,
          });
          return;
        }
      }

      // Step 3: Multi-Frame Quality Centroid Fusion
      let fusedEmbedding: number[];
      let averageQuality = 0.95;
      let modelVersion: BiometricModelVersion = "v11_adaface_512";
      let dimension: 512 | 128 = 512;

      if (frames && Array.isArray(frames) && frames.length > 0) {
        const fusionResult = Arcface512SessionPoolV11.fuseQualityWeightedCentroid(frames as QualityWeightedFrame[]);
        fusedEmbedding = fusionResult.fusedEmbedding;
        averageQuality = fusionResult.averageQuality;
        modelVersion = fusionResult.modelVersion;
        dimension = fusionResult.dimension;
      } else if (embedding && Array.isArray(embedding)) {
        fusedEmbedding = embedding;
        dimension = embedding.length === 512 ? 512 : 128;
        modelVersion = dimension === 512 ? "v11_adaface_512" : "v10_sface_128";
      } else {
        res.status(400).json({
          error: "ERR_MISSING_EMBEDDING: 'frames' burst array or single 'embedding' is required.",
        });
        return;
      }

      const existingRecord = this.recordsMap.get(uid);
      const isReRegistration = mode === "AUTHORIZED_RE_REGISTRATION" || Boolean(existingRecord);

      // Handle re-registration authorization
      if (isReRegistration) {
        if (!existingRecord) {
          res.status(404).json({ error: "ERR_RECORD_NOT_FOUND: Cannot re-register non-existent account." });
          return;
        }
        if (existingRecord.biometricStatus !== "UNLOCKED_FOR_ROTATION") {
          res.status(403).json({
            error: "ERR_BIOMETRIC_LOCKED",
            message: "Biometric profile is currently locked. Step-up authorization required before rotating face.",
          });
          return;
        }
      }

      // Step 4: Sub-Linear HNSW 1:N Deduplication Search
      const tauHigh = dimension === 512 ? FaceV11ProductionController.TAU_HIGH_512 : FaceV11ProductionController.TAU_HIGH_128;
      const tauLow = dimension === 512 ? FaceV11ProductionController.TAU_LOW_512 : FaceV11ProductionController.TAU_LOW_128;

      const knnResults = this.hnswIndex.searchKnn({
        query: fusedEmbedding,
        k: 3,
        excludeUid: uid,
      });
      const topMatch = knnResults.length > 0 ? knnResults[0] : null;

      // Duplicate detection
      if (topMatch && topMatch.similarity >= tauHigh) {
        const matchedRecord = this.recordsMap.get(topMatch.uid);
        res.status(409).json({
          status: "DUPLICATE_ACCOUNT_DETECTED",
          message: "A registered account with this biometric identity already exists on Kelasagara.",
          duplicateAccountDetails: {
            maskedUid: `${topMatch.uid.slice(0, 4)}***${topMatch.uid.slice(-4)}`,
            maskedPhone: matchedRecord ? this.maskPhone(matchedRecord.phone) : "+91******0000",
            matchConfidence: Number((topMatch.similarity * 100).toFixed(1)),
            cosineSimilarity: topMatch.similarity,
          },
        });
        return;
      }

      // Grey-Zone Ambiguity Band Step-Up Challenge (Worker Safety Guard)
      if (topMatch && topMatch.similarity >= tauLow && topMatch.similarity < tauHigh) {
        const challenge = EmpiricalRocCalibratorV11.createStepUpChallenge(uid, "BLINK");
        res.status(202).json({
          status: "GREY_ZONE_AMBIGUITY_STEP_UP_REQUIRED",
          message: "Borderline facial similarity detected. Interactive liveness step-up challenge required to prevent false duplication.",
          stepUpChallenge: challenge,
          candidateSimilarity: topMatch.similarity,
          existingAccountLocked: false,
        });
        return;
      }

      // Step 5: AES-256-GCM Envelope Encryption at Rest
      const faceId = `ks_face_${crypto.randomBytes(8).toString("hex")}`;
      const envelope = BiometricCryptographicVaultV11.encryptEmbedding({
        uid,
        faceId,
        embedding: fusedEmbedding,
        modelVersion,
        masterKey: this.options.masterKey,
      });

      // Mint high-security lock token
      const nextVersion = existingRecord ? existingRecord.enrollmentVersion + 1 : 1;
      const lockTokenPayload = `v11:${nextVersion}:${Date.now()}:${uid}:${envelope.cancelableBiometricHash}`;
      const biometricLockToken = `KS_FTOK_V11_${crypto.createHash("sha256").update(lockTokenPayload).digest("hex").slice(0, 32)}`;

      const newRecord: EnrolledIdentityRecordV11 = {
        uid,
        faceId,
        biometricLockToken,
        name,
        phone,
        primarySkill,
        dailyRate,
        envelope,
        modelVersion,
        dimension,
        biometricStatus: "LOCKED_ACTIVE",
        enrollmentVersion: nextVersion,
        averageFiqaQuality: averageQuality,
        updatedAtIso: new Date().toISOString(),
      };

      // Persist in records and insert/update in HNSW index
      this.recordsMap.set(uid, newRecord);
      this.rawEmbeddingsCache.set(uid, fusedEmbedding);
      this.hnswIndex.insert(uid, fusedEmbedding);

      res.status(200).json({
        status: isReRegistration ? "RE_ENROLLED_AND_LOCKED" : "ENROLLED_AND_LOCKED",
        uid,
        faceId,
        biometricLockToken,
        modelVersion,
        dimension,
        enrollmentVersion: nextVersion,
        encryptedVaultKeyId: envelope.keyId,
        cancelableBiometricHash: envelope.cancelableBiometricHash,
        message: "Biometric profile successfully encrypted with AES-256-GCM and indexed into sub-linear HNSW vault.",
      });
    } catch (err: any) {
      res.status(500).json({ error: "ERR_ENROLLMENT_FAILED", message: err?.message ?? String(err) });
    }
  }

  /**
   * POST /api/v11/biometrics/verify-ekyc
   * 1:1 e-KYC Verification
   */
  public async handleOneToOneEkyc(req: Request, res: Response): Promise<void> {
    try {
      const { uid, embedding, fiqaInput, padTextureMap } = req.body;

      if (!uid || !embedding || !Array.isArray(embedding)) {
        res.status(400).json({ error: "ERR_INVALID_REQUEST: uid and embedding array required." });
        return;
      }

      const record = this.recordsMap.get(uid);
      if (!record) {
        res.status(404).json({ error: "ERR_USER_NOT_ENROLLED: No biometric record found for uid." });
        return;
      }

      // FIQA & PAD Verification
      if (fiqaInput) {
        const fiqaReport = PadLivenessFiqaGuardV11.evaluateFrameQuality(fiqaInput as FiqaEvaluationInput);
        if (!fiqaReport.isAcceptable) {
          res.status(422).json({
            error: "ERR_FIQA_REJECTED",
            message: `Verification image failed FIQA: ${fiqaReport.rejectionReason}`,
          });
          return;
        }
      }

      if (padTextureMap) {
        const padResult = PadLivenessFiqaGuardV11.evaluatePassiveLiveness(padTextureMap);
        if (!padResult.isLive) {
          res.status(422).json({
            error: "ERR_PAD_SPOOF_DETECTED",
            message: "Presentation attack detected during 1:1 verification.",
          });
          return;
        }
      }

      // Retrieve enrolled embedding (from plaintext cache or decrypted envelope)
      let enrolledEmbedding = this.rawEmbeddingsCache.get(uid);
      if (!enrolledEmbedding) {
        enrolledEmbedding = BiometricCryptographicVaultV11.decryptEmbedding({
          envelope: record.envelope,
          masterKey: this.options.masterKey,
        });
        this.rawEmbeddingsCache.set(uid, enrolledEmbedding);
      }

      const similarity = Arcface512SessionPoolV11.computeCosineSimilarity(enrolledEmbedding, embedding);
      const threshold = record.dimension === 512
        ? FaceV11ProductionController.VERIFY_1TO1_512
        : FaceV11ProductionController.VERIFY_1TO1_128;

      const isMatch = similarity >= threshold;

      if (isMatch) {
        res.status(200).json({
          status: "VERIFIED",
          uid,
          isMatch: true,
          similarityScore: Number(similarity.toFixed(4)),
          confidencePercentage: Number((similarity * 100).toFixed(1)),
          biometricLockToken: record.biometricLockToken,
        });
      } else {
        res.status(401).json({
          status: "FAILED_MISMATCH",
          uid,
          isMatch: false,
          similarityScore: Number(similarity.toFixed(4)),
          message: "Facial identity did not match enrolled template.",
        });
      }
    } catch (err: any) {
      res.status(500).json({ error: "ERR_VERIFICATION_FAILED", message: err?.message ?? String(err) });
    }
  }

  /**
   * POST /api/v11/biometrics/challenge/request
   */
  public handleRequestChallenge(req: Request, res: Response): void {
    const { uid, action = "BLINK" } = req.body;
    if (!uid) {
      res.status(400).json({ error: "ERR_MISSING_UID: uid is required." });
      return;
    }
    const challenge = EmpiricalRocCalibratorV11.createStepUpChallenge(uid, action);
    res.status(200).json({ challenge });
  }

  /**
   * POST /api/v11/biometrics/challenge/verify
   */
  public handleVerifyChallenge(req: Request, res: Response): void {
    const response = req.body as StepUpChallengeResponseV11;
    if (!response || !response.challengeId || !response.signature) {
      res.status(400).json({ error: "ERR_INVALID_CHALLENGE_PAYLOAD" });
      return;
    }

    const verification = EmpiricalRocCalibratorV11.verifyStepUpChallenge(response);
    if (verification.isValid) {
      res.status(200).json({
        status: "CHALLENGE_PASSED",
        uid: response.uid,
        action: response.action,
        livenessConfirmed: true,
      });
    } else {
      res.status(422).json({
        status: "CHALLENGE_FAILED",
        reason: verification.reason,
        livenessConfirmed: false,
      });
    }
  }

  /**
   * POST /api/v11/biometrics/unlock-for-rotation
   */
  public handleUnlockForRotation(req: Request, res: Response): void {
    const { uid, authReason = "USER_REQUESTED_RE_ENROLLMENT" } = req.body;
    const record = this.recordsMap.get(uid);
    if (!record) {
      res.status(404).json({ error: "ERR_NOT_FOUND: User not enrolled." });
      return;
    }

    record.biometricStatus = "UNLOCKED_FOR_ROTATION";
    record.updatedAtIso = new Date().toISOString();

    res.status(200).json({
      status: "UNLOCKED_FOR_ROTATION",
      uid,
      authReason,
      message: "Biometric identity profile successfully unlocked for authorized face re-enrollment.",
    });
  }

  /**
   * POST /api/v11/biometrics/calibrate
   * Ingests participant records, computes empirical ROC curve, and issues signed certificate.
   */
  public handleCalibrateCorpus(req: Request, res: Response): void {
    try {
      const { corpus, modelVersion = "v11_adaface_512" } = req.body;
      const recordsToCalibrate = (corpus && Array.isArray(corpus)) ? corpus : this.calibrationCorpus;

      if (!recordsToCalibrate || recordsToCalibrate.length === 0) {
        res.status(400).json({ error: "ERR_EMPTY_CORPUS: No participant records provided." });
        return;
      }

      const certificate = EmpiricalRocCalibratorV11.calibrateFromCorpus(
        recordsToCalibrate as ParticipantRecordV11[],
        modelVersion as BiometricModelVersion
      );

      res.status(200).json({ certificate });
    } catch (err: any) {
      res.status(500).json({ error: "ERR_CALIBRATION_FAILED", message: err?.message ?? String(err) });
    }
  }
}
