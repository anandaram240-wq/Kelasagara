/**
 * KELASAGARA BIOMETRIC ENGINE V12.0 — HYPERSCALE & EDGE ROUTES
 * File: backend/src/routes/face_v12_routes.ts
 */

import { Router, Request, Response } from 'express';
import crypto from 'node:crypto';
import { KmsKeyRotatorV12 } from '../biometrics/kms_key_rotator_v12';
import { HnswClusterSyncCoordinatorV12, HnswWalEntryV12 } from '../biometrics/hnsw_cluster_sync_v12';
import { FairnessDriftMonitorV12, TelemetryObservationV12 } from '../biometrics/fairness_drift_monitor_v12';
import { createFaceV18Router } from './face_v18_routes';

export function createFaceV12Router(): Router {
  const router = Router();

  const kmsRotator = new KmsKeyRotatorV12({
    keyId: 'kms_v12_epoch_initial',
    aesKey256: crypto.createHash('sha256').update('ks_v12_default_aes_key').digest(),
    hmacSalt256: crypto.createHash('sha256').update('ks_v12_default_hmac_salt').digest(),
  });

  const snapshotSecret = crypto.createHash('sha256').update('ks_v12_snapshot_hmac_secret').digest();
  const hnswSync = new HnswClusterSyncCoordinatorV12(snapshotSecret);
  const fairnessMonitor = new FairnessDriftMonitorV12();

  // 1. Cluster Health, Active KMS Epoch & HNSW Watermark
  router.get('/status', (_req: Request, res: Response) => {
    res.status(200).json({
      engineVersion: 'V12.0_HYPERSCALE',
      activeKmsKeyId: kmsRotator.getActiveKeyId(),
      hnswNodeCount: hnswSync.getNodeCount(),
      watermarkWalSeq: hnswSync.getWatermarkWalSeq(),
      fairnessSummary: fairnessMonitor.evaluateFairnessAndDrift(),
    });
  });

  // 2. Zero-Downtime KMS Key Epoch Promotion (Pillar 12.1)
  router.post('/kms/promote-epoch', (req: Request, res: Response) => {
    const { keyId, aesKeySeed, hmacSaltSeed } = req.body ?? {};
    if (!keyId || !aesKeySeed || !hmacSaltSeed) {
      res.status(400).json({ error: 'ERR_MISSING_KMS_EPOCH_PARAMS' });
      return;
    }

    kmsRotator.promoteNewActiveEpoch({
      keyId: String(keyId),
      aesKey256: crypto.createHash('sha256').update(String(aesKeySeed)).digest(),
      hmacSalt256: crypto.createHash('sha256').update(String(hmacSaltSeed)).digest(),
    });

    res.status(200).json({
      status: 'KMS_EPOCH_PROMOTED_ZERO_DOWNTIME',
      activeKeyId: kmsRotator.getActiveKeyId(),
    });
  });

  // 3. Export Signed Binary HNSW Snapshot (Pillar 12.2)
  router.get('/hnsw/snapshot/export', (_req: Request, res: Response) => {
    const snapshotBuf = hnswSync.exportSignedBinarySnapshot();
    res.status(200).json({
      status: 'SNAPSHOT_EXPORTED',
      snapshotBase64: snapshotBuf.toString('base64'),
      snapshotBytes: snapshotBuf.byteLength,
      watermarkWalSeq: hnswSync.getWatermarkWalSeq(),
    });
  });

  // 4. Hydrate Binary HNSW Snapshot & Apply Incremental WAL Delta (Pillar 12.2)
  router.post('/hnsw/sync', (req: Request, res: Response) => {
    const { snapshotBase64, walEntries } = req.body ?? {};
    let hydrationTelemetry = null;
    if (snapshotBase64) {
      hydrationTelemetry = hnswSync.hydrateFromBinarySnapshot(
        Buffer.from(String(snapshotBase64), 'base64')
      );
    }
    const deltaTelemetry = Array.isArray(walEntries)
      ? hnswSync.applyIncrementalWalDelta(walEntries as HnswWalEntryV12[])
      : null;

    res.status(200).json({
      status: 'CLUSTER_NODE_SYNCHRONIZED',
      hydrationTelemetry,
      deltaTelemetry,
    });
  });

  // 5. Record & Audit ISO/IEC 19795-10 Demographic Fairness Telemetry (Pillar 12.3)
  router.post('/fairness/telemetry', (req: Request, res: Response) => {
    const observations: TelemetryObservationV12[] = Array.isArray(req.body?.observations)
      ? req.body.observations
      : [req.body];

    for (const obs of observations) {
      if (obs && typeof obs.luminanceMean === 'number') {
        fairnessMonitor.recordObservation(obs);
      }
    }

    const report = fairnessMonitor.evaluateFairnessAndDrift();
    res.status(200).json(report);
  });

  // 6. Subroute alias for V18 Hyperscale Pipeline
  router.use('/v18', createFaceV18Router());

  return router;
}
