/**
 * KELASAGARA BIOMETRIC ENGINE V18.0 — STAGE 1–3 PIPELINE & HYPERSCALE ROUTES
 * File: backend/src/routes/face_v18_routes.ts
 */

import { Router, Request, Response } from 'express';
import path from 'path';
import admin from 'firebase-admin';
import {
  CloudKmsEnvelopeService,
  LocalDevKeyProvider,
  PRODUCTION_BIOMETRIC_CALIBRATION_APPROVED,
  RELEASE_STATUS,
} from '../crypto/cloud_kms_envelope';
import { CanonicalSFaceEngineV10 } from '../biometrics/canonical_sface_engine_v10';
import { FirestoreBiometricTransactionAdapterV18 } from '../services/firestore_transaction_adapter_v18';
import { TransactionalGalleryCoordinatorV18 } from '../services/transactional_gallery_coordinator_v18';
import {
  BiometricPipelineCoordinatorV18,
  PipelineEnrollmentInputV18,
  PipelineVerify1to1InputV18,
} from '../services/biometric_pipeline_coordinator_v18';
import { WalCompactorServiceV18 } from '../services/wal_compaction_and_gap_guard_v18';

export interface FaceV18RouterOptions {
  coordinator?: BiometricPipelineCoordinatorV18;
  db?: any;
  tenantId?: string;
  clusterId?: string;
  sfaceEngine?: CanonicalSFaceEngineV10;
}

export function createFaceV18Router(options: FaceV18RouterOptions = {}): Router {
  const router = Router();

  let pipeline: BiometricPipelineCoordinatorV18;

  if (options.coordinator) {
    pipeline = options.coordinator;
  } else {
    const firestoreDb = options.db ?? (admin.apps.length > 0 ? admin.firestore() : undefined);
    const kmsKeyProvider = new LocalDevKeyProvider();
    const kmsEnvelope = new CloudKmsEnvelopeService(kmsKeyProvider);
    const txAdapter = new FirestoreBiometricTransactionAdapterV18(firestoreDb);
    const galleryCoordinator = new TransactionalGalleryCoordinatorV18({
      txAdapter,
      kmsEnvelope,
      kmsKeyProvider,
      tenantId: options.tenantId ?? 'karnataka-kelasagaara-prod',
      clusterId: options.clusterId ?? 'karnataka-kelasagaara-primary',
    });

    let sfaceEngine = options.sfaceEngine;
    if (!sfaceEngine) {
      const sfaceModelPath = path.resolve(__dirname, '../../models/face_recognition_sface_2021dec.onnx');
      sfaceEngine = new CanonicalSFaceEngineV10(sfaceModelPath);
    }

    pipeline = new BiometricPipelineCoordinatorV18(galleryCoordinator, sfaceEngine);
  }

  // 1. GET /status — Cluster & Pipeline Health Status
  router.get('/status', (_req: Request, res: Response) => {
    const gallery = pipeline.getGalleryCoordinator();
    res.status(200).json({
      engineVersion: 'V18.0_HYPERSCALE_PIPELINE',
      status: 'ONLINE',
      watermarkGlobalEpoch: gallery.getLocalWatermarkEpoch(),
      activeGallerySize: gallery.getActiveGallerySize(),
      releaseStatus: RELEASE_STATUS,
      calibrationApproved: PRODUCTION_BIOMETRIC_CALIBRATION_APPROVED,
      pipelineStages: [
        'Stage 1: Passive PAD (ISO/IEC 30107-3) & FIQA Quality Gate',
        'Stage 2: Canonical ONNX SFace 128-D Embedding Inference',
        'Stage 3: Epoch-Fenced CAS Gallery Screening & Transactional WAL Outbox',
      ],
    });
  });

  // 2. POST /enroll — Stage 1–3 End-to-End Enrollment Endpoint
  router.post('/enroll', async (req: Request, res: Response): Promise<void> => {
    try {
      const {
        uid,
        phone,
        idempotencyKey,
        allowReEnrollment,
        imageBase64,
        imageBuffer,
        embedding128,
        fiqaInput,
        padParams,
      } = req.body ?? {};

      if (!uid || typeof uid !== 'string') {
        res.status(400).json({
          error: 'ERR_MISSING_UID',
          message: 'uid is required for enrollment.',
        });
        return;
      }

      if (!idempotencyKey || typeof idempotencyKey !== 'string') {
        res.status(400).json({
          error: 'ERR_MISSING_IDEMPOTENCY_KEY',
          message: 'idempotencyKey is required for enrollment.',
        });
        return;
      }

      const input: PipelineEnrollmentInputV18 = {
        uid,
        phone: typeof phone === 'string' ? phone : undefined,
        idempotencyKey,
        allowReEnrollment: Boolean(allowReEnrollment),
        imageBase64: typeof imageBase64 === 'string' ? imageBase64 : undefined,
        imageBuffer: Buffer.isBuffer(imageBuffer) ? imageBuffer : undefined,
        embedding128: Array.isArray(embedding128) || embedding128 instanceof Float32Array ? embedding128 : undefined,
        fiqaInput,
        padParams,
      };

      const result = await pipeline.enrollWorkerPipeline(input);

      if (result.decisionStatus === 'FIQA_QUALITY_REJECTED') {
        res.status(422).json({
          status: 'FIQA_QUALITY_REJECTED',
          error: 'ERR_FIQA_REJECTED',
          rejectionReason: result.rejectionReason,
          fiqaReport: result.fiqa,
        });
        return;
      }

      if (result.decisionStatus === 'PAD_SPOOF_REJECTED') {
        res.status(422).json({
          status: 'PAD_SPOOF_REJECTED',
          error: 'ERR_PAD_SPOOF_DETECTED',
          rejectionReason: result.rejectionReason,
          padResult: result.pad,
        });
        return;
      }

      if (result.decisionStatus === 'HARD_DUPLICATE_BLOCKED') {
        res.status(409).json({
          status: 'DUPLICATE_INVESTIGATION_PENDING',
          error: 'DUPLICATE_INVESTIGATION_PENDING',
          message:
            'Biometric similarity requires standard compliance review. An inquiry ticket has been opened.',
          auditTicketId: result.auditTicketId,
          reviewStatus: 'PENDING_HUMAN_RESOLUTION',
          reversible: true,
          releaseStatus: result.releaseStatus,
        });
        return;
      }

      if (result.decisionStatus === 'DUPLICATE_WARNING_FLAGGED') {
        res.status(202).json({
          status: 'AMBIGUOUS_PENDING_REVIEW',
          message: 'Biometric similarity in grey-zone; flagged for compliance review.',
          auditTicketId: result.auditTicketId,
          committedGlobalEpoch: result.committedGlobalEpoch,
          templateGeneration: result.templateGeneration,
          biometricLockToken: result.biometricLockToken,
          releaseStatus: result.releaseStatus,
        });
        return;
      }

      // Success (Clean Approved or Idempotent Replay)
      const httpStatus = result.idempotentReplay ? 200 : 200;
      res.status(httpStatus).json({
        status: result.idempotentReplay ? 'ALREADY_REGISTERED_LOCKED' : 'ENROLLED_AND_LOCKED',
        idempotentReplay: result.idempotentReplay ?? false,
        biometricLockToken: result.biometricLockToken,
        committedGlobalEpoch: result.committedGlobalEpoch,
        templateGeneration: result.templateGeneration,
        epochDriftRetriesUsed: result.epochDriftRetriesUsed,
        fiqaReport: result.fiqa,
        padResult: result.pad,
        releaseStatus: result.releaseStatus,
        calibrationApproved: result.calibrationApproved,
      });
    } catch (err: any) {
      console.error('[FaceV18Routes:enroll] Error:', err);
      res.status(500).json({
        error: 'INTERNAL_PIPELINE_ERROR',
        message: err?.message ?? 'Unknown pipeline error.',
      });
    }
  });

  // 3. POST /verify-1to1 — 1:1 eKYC Biometric Verification Endpoint
  router.post('/verify-1to1', async (req: Request, res: Response): Promise<void> => {
    try {
      const {
        claimedUid,
        imageBase64,
        imageBuffer,
        embedding128,
        fiqaInput,
        padParams,
      } = req.body ?? {};

      if (!claimedUid || typeof claimedUid !== 'string') {
        res.status(400).json({
          error: 'ERR_MISSING_CLAIMED_UID',
          message: 'claimedUid is required for 1:1 verification.',
        });
        return;
      }

      const input: PipelineVerify1to1InputV18 = {
        claimedUid,
        imageBase64: typeof imageBase64 === 'string' ? imageBase64 : undefined,
        imageBuffer: Buffer.isBuffer(imageBuffer) ? imageBuffer : undefined,
        embedding128: Array.isArray(embedding128) || embedding128 instanceof Float32Array ? embedding128 : undefined,
        fiqaInput,
        padParams,
      };

      const result = await pipeline.verifyWorkerPipeline(input);

      if (result.decisionStatus === 'FIQA_QUALITY_REJECTED') {
        res.status(422).json({
          status: 'FIQA_QUALITY_REJECTED',
          error: 'ERR_FIQA_REJECTED',
          rejectionReason: result.rejectionReason,
          fiqaReport: result.fiqa,
        });
        return;
      }

      if (result.decisionStatus === 'PAD_SPOOF_REJECTED') {
        res.status(422).json({
          status: 'PAD_SPOOF_REJECTED',
          error: 'ERR_PAD_SPOOF_DETECTED',
          rejectionReason: result.rejectionReason,
          padResult: result.pad,
        });
        return;
      }

      if (result.decisionStatus === 'CLAIMANT_TEMPLATE_NOT_FOUND') {
        res.status(404).json({
          verified: false,
          status: 'CLAIMANT_TEMPLATE_NOT_FOUND',
          error: 'CLAIMANT_TEMPLATE_NOT_FOUND',
          message: 'No enrolled biometric template found for claimant UID.',
        });
        return;
      }

      res.status(200).json({
        verified: result.verified,
        status: result.decisionStatus,
        cosineSimilarity: result.cosineSimilarity,
        thresholdApplied: result.thresholdApplied,
      });
    } catch (err: any) {
      console.error('[FaceV18Routes:verify-1to1] Error:', err);
      res.status(500).json({
        error: 'INTERNAL_VERIFY_ERROR',
        message: err?.message ?? 'Unknown 1:1 verify error.',
      });
    }
  });

  // 4. POST /snapshot/export — Export KMS-Wrapped KS18 Snapshot
  router.post('/snapshot/export', async (req: Request, res: Response): Promise<void> => {
    try {
      const keyId = typeof req.body?.keyId === 'string' ? req.body.keyId : 'ks18-snapshot-kek-v1';
      const artifact = await pipeline.getGalleryCoordinator().exportKmsWrappedSnapshotKs18(keyId);
      res.status(200).json({
        status: 'SNAPSHOT_EXPORTED',
        artifact,
      });
    } catch (err: any) {
      console.error('[FaceV18Routes:snapshot:export] Error:', err);
      res.status(500).json({
        error: 'SNAPSHOT_EXPORT_FAILED',
        message: err?.message ?? 'Failed to export snapshot.',
      });
    }
  });

  // 5. POST /snapshot/hydrate — Cold-Boot Hydrate from KMS Snapshot & WAL Tail
  router.post('/snapshot/hydrate', async (req: Request, res: Response): Promise<void> => {
    try {
      const { artifact } = req.body ?? {};
      if (!artifact || !artifact.bundle || !artifact.wrappedSnapshotDekBase64) {
        res.status(400).json({
          error: 'ERR_INVALID_SNAPSHOT_ARTIFACT',
          message: 'artifact with bundle and wrappedSnapshotDekBase64 required.',
        });
        return;
      }

      if (artifact.bundle && artifact.bundle.encryptedPayloadBuffer) {
        if (!Buffer.isBuffer(artifact.bundle.encryptedPayloadBuffer)) {
          artifact.bundle.encryptedPayloadBuffer = Buffer.from(
            (artifact.bundle.encryptedPayloadBuffer as any).data ??
              artifact.bundle.encryptedPayloadBuffer,
          );
        }
      }

      const telemetry = await pipeline.getGalleryCoordinator().hydrateFromKmsSnapshotAndWalTail(artifact);
      res.status(200).json({
        status: 'SNAPSHOT_HYDRATED',
        telemetry,
      });
    } catch (err: any) {
      console.error('[FaceV18Routes:snapshot:hydrate] Error:', err);
      res.status(500).json({
        error: 'SNAPSHOT_HYDRATION_FAILED',
        message: err?.message ?? 'Failed to hydrate snapshot.',
      });
    }
  });

  // 6. POST /wal/compact — Compaction & Safety Window Pruning
  router.post('/wal/compact', async (req: Request, res: Response): Promise<void> => {
    try {
      const { snapshotWatermark, retainSafetyWindowEntries } = req.body ?? {};
      if (typeof snapshotWatermark !== 'number' || snapshotWatermark <= 0) {
        res.status(400).json({
          error: 'ERR_INVALID_WATERMARK',
          message: 'snapshotWatermark must be a positive integer.',
        });
        return;
      }

      // If a Firestore db is attached, run compactor
      const firestoreDb = options.db ?? (admin.apps.length > 0 ? admin.firestore() : null);
      if (!firestoreDb) {
        res.status(200).json({
          status: 'SKIPPED_NO_FIRESTORE_INSTANCE',
          snapshotWatermark,
        });
        return;
      }

      const compactor = new WalCompactorServiceV18(firestoreDb, retainSafetyWindowEntries ?? 10);
      const pruneSummary = await compactor.compactWalEntriesBeforeWatermark(snapshotWatermark);
      res.status(200).json({
        status: 'WAL_COMPACTED',
        pruneSummary,
      });
    } catch (err: any) {
      console.error('[FaceV18Routes:wal:compact] Error:', err);
      res.status(500).json({
        error: 'WAL_COMPACTION_FAILED',
        message: err?.message ?? 'Failed to compact WAL.',
      });
    }
  });

  return router;
}
