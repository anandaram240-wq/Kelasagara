// FILE: backend/src/routes/face_v18_unified_routes.ts

import { Router, Request, Response } from "express";
import { execSync } from "node:child_process";
import { GroupCommitEpochSequencerV18 } from "../biometrics/group_commit_epoch_sequencer_v18";
import {
  GcsWormAuditAnchorV18,
  LockedGcsWormDriverSimulator,
} from "../biometrics/gcs_worm_audit_anchor_v18";
import { CloudKmsFailClosedGuardV18 } from "../biometrics/cloud_kms_fail_closed_guard_v18";
import {
  PhysicalCameraCalibrationVerifierV18,
  PhysicalDeviceCalibrationCapture,
  OpticalFrameFiqaTelemetry,
  AndroidHardwareTier,
} from "../biometrics/physical_camera_calibration_verifier_v18";
import { UnifiedBiometricPipelineV18 } from "../biometrics/unified_biometric_pipeline_v18";

export class FaceV18UnifiedController {
  public readonly router: Router = Router();
  public readonly sequencer: GroupCommitEpochSequencerV18;
  public readonly wormDriver: LockedGcsWormDriverSimulator;
  public readonly wormAudit: GcsWormAuditAnchorV18;
  public readonly kmsGuard: CloudKmsFailClosedGuardV18;
  public readonly pipeline: UnifiedBiometricPipelineV18;

  private readonly calibrationCaptures: PhysicalDeviceCalibrationCapture[] = [];
  private manualAdbSerialsOverride: string[] | null = null;

  constructor(options?: { duplicateThreshold?: number; coalesceWindowMs?: number }) {
    this.sequencer = new GroupCommitEpochSequencerV18({
      duplicateThreshold: options?.duplicateThreshold ?? 0.55,
    });

    this.wormDriver = new LockedGcsWormDriverSimulator();
    this.wormAudit = new GcsWormAuditAnchorV18({
      bucketName:
        process.env.GCS_WORM_AUDIT_BUCKET || "kelasagara-v18-worm-audit-lock",
      retentionDays: 365,
      wormDriver: this.wormDriver,
    });

    this.kmsGuard = new CloudKmsFailClosedGuardV18({
      config: {
        gcpResourceName:
          process.env.GCP_KMS_KEY_RESOURCE ||
          "projects/kelasagara-prod/locations/asia-south1/keyRings/biometric-kr/cryptoKeys/sface-hsm-key",
        protectionLevel: "HSM",
        activeKeyVersion: 1,
      },
      onEmergencyZeroizeArena: () => this.sequencer.zeroizeActiveArenaMemory(),
    });

    this.pipeline = new UnifiedBiometricPipelineV18({
      sequencer: this.sequencer,
      wormAudit: this.wormAudit,
      kmsGuard: this.kmsGuard,
      maxBatchSize: 64,
      coalesceWindowMs: options?.coalesceWindowMs ?? 4,
    });

    this.initializeRoutes();
  }

  private initializeRoutes(): void {
    this.router.get("/health", (_req: Request, res: Response) => {
      res.status(200).json({
        success: true,
        status: "healthy",
        subsystem: "v18_unified_pipeline",
        timestamp: new Date().toISOString(),
      });
    });
    this.router.post("/enroll", this.handleEnrollHttp.bind(this));
    this.router.post(
      "/calibration/capture",
      this.handleRecordCalibrationCapture.bind(this)
    );
    this.router.get(
      "/calibration/gate-h-status",
      this.handleGetGateHStatus.bind(this)
    );
    this.router.get(
      "/audit/worm-anchors",
      this.handleListWormAnchors.bind(this)
    );
    this.router.post(
      "/security/revoke-sa-iam",
      this.handleEmergencyRevokeSaIam.bind(this)
    );
  }

  /**
   * 1. POST /api/v18/biometrics/enroll
   * Coalesces concurrent mobile HTTP requests into a single GroupCommitEpochSequencerV18 batch,
   * pre-filters optical FIQA, seals a GCS WORM Merkle anchor, and strips all candidate PII on 409.
   */
  public async handleEnrollHttp(req: Request, res: Response): Promise<void> {
    try {
      const { requestId, applicantUid, embedding128, opticalFiqa } = req.body;

      if (!requestId || !applicantUid || !Array.isArray(embedding128)) {
        res.status(400).json({
          success: false,
          error: "ERR_INVALID_V18_ENROLL_PAYLOAD",
        });
        return;
      }

      if (embedding128.length !== 128) {
        res.status(400).json({
          success: false,
          error: `ERR_INVALID_EMBEDDING_DIM: Expected 128, got ${embedding128.length}`,
        });
        return;
      }

      // Normalize vector to unit hypersphere S^127
      const floatVec = new Float32Array(128);
      let sumSq = 0;
      for (let i = 0; i < 128; i++) {
        const val = Number(embedding128[i]);
        if (!Number.isFinite(val)) {
          res.status(400).json({
            success: false,
            error: "ERR_NON_FINITE_EMBEDDING_VALUE",
          });
          return;
        }
        floatVec[i] = val;
        sumSq += val * val;
      }
      const norm = Math.sqrt(sumSq);
      if (norm < 1e-8) {
        res.status(400).json({
          success: false,
          error: "ERR_ZERO_NORM_EMBEDDING",
        });
        return;
      }
      for (let i = 0; i < 128; i++) {
        floatVec[i] /= norm;
      }

      const normalizedFiqa: OpticalFrameFiqaTelemetry = {
        laplacianSharpnessScore: Number(
          opticalFiqa?.laplacianSharpnessScore ?? 80.0
        ),
        highlightClippingFraction: Number(
          opticalFiqa?.highlightClippingFraction ?? 0.04
        ),
        rollingShutterSkewDegrees: Number(
          opticalFiqa?.rollingShutterSkewDegrees ?? 1.2
        ),
        highFreqSkinTextureEnergy: Number(
          opticalFiqa?.highFreqSkinTextureEnergy ?? 0.32
        ),
        ambientLuxEstimate: Number(opticalFiqa?.ambientLuxEstimate ?? 25000),
      };

      const result = await this.pipeline.submitEnrollmentHttp({
        requestId: String(requestId),
        applicantUid: String(applicantUid),
        normalizedEmbedding128: floatVec,
        opticalFiqa: normalizedFiqa,
      });

      if (result.httpStatus === 422) {
        res.status(422).json({
          success: false,
          status: result.status,
          applicantUid: result.applicantUid,
          failureCode: result.failureCode,
        });
        return;
      }

      if (result.httpStatus === 409) {
        // Gate G Privacy Sanitization: Zero candidate UID, phone, or similarity floats leaked!
        res.status(409).json({
          success: false,
          status: result.outcome.status,
          applicantUid: result.outcome.applicantUid,
          collisionSource: result.outcome.collisionSource,
          auditTicketId: result.outcome.auditTicketId,
          existingAccountLocked: false,
          wormAnchorPath: result.wormAnchorPath,
        });
        return;
      }

      res.status(200).json({
        success: true,
        status: result.outcome.status,
        applicantUid: result.outcome.applicantUid,
        committedEpoch: result.outcome.committedEpoch,
        walSequenceNumber: result.outcome.walSequenceNumber,
        wormAnchorPath: result.wormAnchorPath,
        batchSizeCoalesced: result.batchTelemetry.batchSize,
      });
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : "ERR_V18_PIPELINE_FAULT";
      const status = msg.includes("ERR_HSM_LOCKDOWN_ACTIVE") ? 503 : 500;
      res.status(status).json({
        success: false,
        error: msg,
        kmsCircuitState: this.kmsGuard.getCircuitState(),
      });
    }
  }

  /**
   * 2. POST /api/v18/biometrics/calibration/capture
   * Records a physical Android device capture for Gate H (BLK-01) release evaluation.
   */
  public handleRecordCalibrationCapture(req: Request, res: Response): void {
    try {
      const {
        participantId,
        isAdultConsentVerified,
        adbHardwareSerial,
        deviceModel,
        hardwareTier,
        sessionNumber,
        opticalFiqa,
        embedding128,
      } = req.body;

      const capture: PhysicalDeviceCalibrationCapture = {
        participantId: String(participantId),
        isAdultConsentVerified: Boolean(isAdultConsentVerified),
        adbHardwareSerial: String(adbHardwareSerial || ""),
        deviceModel: String(deviceModel || "Unknown"),
        hardwareTier: (hardwareTier as AndroidHardwareTier) || "TIER_1_ENTRY_CMOS",
        sessionNumber: sessionNumber === 2 ? 2 : 1,
        opticalFiqa: {
          laplacianSharpnessScore: Number(
            opticalFiqa?.laplacianSharpnessScore ?? 0
          ),
          highlightClippingFraction: Number(
            opticalFiqa?.highlightClippingFraction ?? 1
          ),
          rollingShutterSkewDegrees: Number(
            opticalFiqa?.rollingShutterSkewDegrees ?? 90
          ),
          highFreqSkinTextureEnergy: Number(
            opticalFiqa?.highFreqSkinTextureEnergy ?? 0
          ),
          ambientLuxEstimate: Number(opticalFiqa?.ambientLuxEstimate ?? 0),
        },
        embedding128: Array.isArray(embedding128)
          ? embedding128.map((n: unknown) => Number(n))
          : null,
      };

      // Validate consent and reject synthetic emulator serials immediately
      PhysicalCameraCalibrationVerifierV18.evaluateGateHReleaseReadiness({
        adbConnectedSerials: [capture.adbHardwareSerial],
        captures: [capture],
      });

      this.calibrationCaptures.push(capture);

      res.status(201).json({
        success: true,
        totalCalibrationCaptures: this.calibrationCaptures.length,
      });
    } catch (err: unknown) {
      const msg =
        err instanceof Error ? err.message : "ERR_CALIBRATION_CAPTURE_REJECTED";
      res.status(400).json({ success: false, error: msg });
    }
  }

  /**
   * 3. GET /api/v18/biometrics/calibration/gate-h-status
   * Queries connected physical ADB devices (or test override) and returns Gate H release verdict.
   */
  public handleGetGateHStatus(_req: Request, res: Response): void {
    const adbSerials =
      this.manualAdbSerialsOverride ?? this.detectLiveAdbPhysicalSerials();

    const verdict =
      PhysicalCameraCalibrationVerifierV18.evaluateGateHReleaseReadiness({
        adbConnectedSerials: adbSerials,
        captures: this.calibrationCaptures,
      });

    res.status(200).json({
      success: true,
      adbConnectedSerials: adbSerials,
      verdict,
    });
  }

  /**
   * 4. GET /api/v18/biometrics/audit/worm-anchors
   */
  public handleListWormAnchors(_req: Request, res: Response): void {
    const anchors = this.pipeline.getSealedWormAnchors();
    res.status(200).json({
      success: true,
      totalSealedAnchors: anchors.length,
      anchors,
      auditQueueCount: this.sequencer.getAuditQueueCount(),
      kmsCircuitState: this.kmsGuard.getCircuitState(),
    });
  }

  /**
   * 5. POST /api/v18/biometrics/security/revoke-sa-iam
   * Simulates or executes IAM revocation and triggers fail-closed arena zeroization.
   */
  public handleEmergencyRevokeSaIam(req: Request, res: Response): void {
    const { serviceAccountEmail = "matcher-sa@kelasagara-prod.iam.gserviceaccount.com" } =
      req.body || {};

    this.kmsGuard.revokeServiceAccountIam(String(serviceAccountEmail));

    // Attempt an unwrap to trip the fail-closed circuit breaker and zeroize sfaceArena128
    try {
      this.kmsGuard.unwrapDekAndExecute({
        callerServiceAccount: String(serviceAccountEmail),
        callerRole: "MATCHER_UNWRAP_ONLY",
        wrappedDekCiphertext: Buffer.alloc(60),
        keyVersion: 1,
        useDekCallback: () => null,
      });
    } catch {
      // Expected fail-closed lockdown trip
    }

    const rawArena = this.sequencer.getRawArenaBufferForTest();
    const isArenaZeroized = rawArena.every((v) => v === 0);

    res.status(200).json({
      success: true,
      kmsCircuitState: this.kmsGuard.getCircuitState(),
      isArenaZeroized,
    });
  }

  public setAdbSerialsOverrideForTest(serials: string[] | null): void {
    this.manualAdbSerialsOverride = serials;
  }

  private detectLiveAdbPhysicalSerials(): string[] {
    try {
      const output = execSync("adb devices", {
        encoding: "utf8",
        timeout: 1500,
      });
      const lines = output
        .split("\n")
        .map((l) => l.trim())
        .filter((l) => l.length > 0 && !l.startsWith("List of devices"));

      const serials: string[] = [];
      for (const line of lines) {
        const parts = line.split(/\s+/);
        if (parts.length >= 2 && parts[1] === "device") {
          serials.push(parts[0]);
        }
      }
      return serials;
    } catch {
      return [];
    }
  }
}
