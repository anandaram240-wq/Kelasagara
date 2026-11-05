/**
 * KELASAGARA BIOMETRIC ENGINE V12.0 — PHASE 12.3 & ROUTE INTEGRATION TEST SUITE
 * File: backend/src/tests/biometric_v12_phase12_3_routes.test.ts
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import http from 'node:http';
import { AddressInfo } from 'node:net';
import {
  FairnessDriftMonitorV12,
  TelemetryObservationV12,
} from '../biometrics/fairness_drift_monitor_v12';
import { createFaceV12Router } from '../routes/face_v12_routes';

test('PHASE12.3-A: ISO/IEC 19795-10 Demographic Fairness & Drift Monitor calculates parity and triggers alerts', () => {
  const monitor = new FairnessDriftMonitorV12({
    windowCapacity: 100,
    minCohortSamplesForParity: 20,
    maxAllowedGreyZoneStepUpRate: 0.05,
    minIsoParityRatio: 0.80,
  });

  // Empty buffer base case
  const initialReport = monitor.evaluateFairnessAndDrift();
  assert.equal(initialReport.totalWindowSamples, 0);
  assert.equal(initialReport.passes80PercentParityRule, true);
  assert.equal(initialReport.driftAlertTriggered, false);

  // Group 1: ANDROID_BUDGET in BALANCED lighting (25 observations, 23 pass, 2 fail -> GAR = 23/25 = 0.92)
  for (let i = 0; i < 23; i++) {
    monitor.recordObservation({
      timestampMs: 1000 + i,
      luminanceMean: 120,
      sensorTier: 'ANDROID_BUDGET',
      regionCode: 'KA_BLR',
      similarityScore: 0.88,
      outcome: 'GENUINE_VERIFIED',
      latencyMs: 14.5,
    });
  }
  for (let i = 0; i < 2; i++) {
    monitor.recordObservation({
      timestampMs: 1025 + i,
      luminanceMean: 120,
      sensorTier: 'ANDROID_BUDGET',
      regionCode: 'KA_BLR',
      similarityScore: 0.42,
      outcome: 'GENUINE_FALSE_REJECT',
      latencyMs: 15.0,
    });
  }

  // Group 2: ANDROID_FLAGSHIP_OR_IOS in BALANCED lighting (25 observations, 24 pass, 1 fail -> GAR = 24/25 = 0.96)
  for (let i = 0; i < 24; i++) {
    monitor.recordObservation({
      timestampMs: 1100 + i,
      luminanceMean: 130,
      sensorTier: 'ANDROID_FLAGSHIP_OR_IOS',
      regionCode: 'KA_BLR',
      similarityScore: 0.92,
      outcome: 'GENUINE_VERIFIED',
      latencyMs: 8.5,
    });
  }
  monitor.recordObservation({
    timestampMs: 1125,
    luminanceMean: 130,
    sensorTier: 'ANDROID_FLAGSHIP_OR_IOS',
    regionCode: 'KA_BLR',
    similarityScore: 0.44,
    outcome: 'GENUINE_FALSE_REJECT',
    latencyMs: 9.0,
  });

  const balancedReport = monitor.evaluateFairnessAndDrift();
  assert.equal(balancedReport.totalWindowSamples, 50);
  // Parity ratio = 0.92 / 0.96 = 0.9583 >= 0.80
  assert.ok(balancedReport.iso19795DifferentialDisparityRatio >= 0.95);
  assert.equal(balancedReport.passes80PercentParityRule, true);
  assert.equal(balancedReport.driftAlertTriggered, false);

  // Group 3: Introduce Severe Grey-Zone Drift & Parity Breach in ANDROID_BUDGET / LOW_LIGHT
  // 20 samples with 6 GREY_ZONE_STEP_UP (30% > 5%) and 10 genuine false rejects
  for (let i = 0; i < 6; i++) {
    monitor.recordObservation({
      timestampMs: 1200 + i,
      luminanceMean: 50, // LOW_LIGHT_40_85
      sensorTier: 'ANDROID_BUDGET',
      regionCode: 'KA_MYS',
      similarityScore: 0.52,
      outcome: 'GREY_ZONE_STEP_UP',
      latencyMs: 18.0,
    });
  }
  for (let i = 0; i < 10; i++) {
    monitor.recordObservation({
      timestampMs: 1210 + i,
      luminanceMean: 50,
      sensorTier: 'ANDROID_BUDGET',
      regionCode: 'KA_MYS',
      similarityScore: 0.35,
      outcome: 'GENUINE_FALSE_REJECT',
      latencyMs: 19.0,
    });
  }
  for (let i = 0; i < 4; i++) {
    monitor.recordObservation({
      timestampMs: 1220 + i,
      luminanceMean: 50,
      sensorTier: 'ANDROID_BUDGET',
      regionCode: 'KA_MYS',
      similarityScore: 0.75,
      outcome: 'GENUINE_VERIFIED',
      latencyMs: 17.5,
    });
  }

  const driftedReport = monitor.evaluateFairnessAndDrift();
  assert.equal(driftedReport.totalWindowSamples, 70);
  // GAR for low-light budget = 4 / (4 + 10) = 0.2857. Parity = 0.2857 / 0.96 = 0.2976 < 0.80
  assert.equal(driftedReport.passes80PercentParityRule, false);
  assert.equal(driftedReport.driftAlertTriggered, true);
  assert.ok(
    driftedReport.alertReasons.some((r) => r.includes('COHORT_GREY_ZONE_DRIFT_EXCEEDED')),
    'Should flag grey zone rate exceeding threshold'
  );
  assert.ok(
    driftedReport.alertReasons.some((r) => r.includes('ISO_19795_10_DEMOGRAPHIC_PARITY_BREACH')),
    'Should flag parity breach'
  );
});

test('PHASE12.3-B: V12 Biometrics API Routes (/api/v12/biometrics) status, KMS epoch promotion, HNSW export/sync & telemetry', async () => {
  const app = express();
  app.use(express.json());
  app.use('/api/v12/biometrics', createFaceV12Router());

  const server = http.createServer(app);
  await new Promise<void>((resolve) => server.listen(0, resolve));
  const port = (server.address() as AddressInfo).port;
  const baseUrl = `http://127.0.0.1:${port}/api/v12/biometrics`;

  try {
    // 1. GET /status
    const statusRes = await fetch(`${baseUrl}/status`);
    assert.equal(statusRes.status, 200);
    const statusBody = (await statusRes.json()) as any;
    assert.equal(statusBody.engineVersion, 'V12.0_HYPERSCALE');
    assert.equal(statusBody.activeKmsKeyId, 'kms_v12_epoch_initial');
    assert.equal(typeof statusBody.hnswNodeCount, 'number');
    assert.equal(typeof statusBody.watermarkWalSeq, 'number');

    // 2. POST /kms/promote-epoch
    const promoteRes = await fetch(`${baseUrl}/kms/promote-epoch`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        keyId: 'kms_v12_epoch_2026_q4',
        aesKeySeed: 'test_aes_seed_2026_q4',
        hmacSaltSeed: 'test_hmac_salt_2026_q4',
      }),
    });
    assert.equal(promoteRes.status, 200);
    const promoteBody = (await promoteRes.json()) as any;
    assert.equal(promoteBody.status, 'KMS_EPOCH_PROMOTED_ZERO_DOWNTIME');
    assert.equal(promoteBody.activeKeyId, 'kms_v12_epoch_2026_q4');

    // Check status reflects the promoted active key
    const statusRes2 = await fetch(`${baseUrl}/status`);
    const statusBody2 = (await statusRes2.json()) as any;
    assert.equal(statusBody2.activeKmsKeyId, 'kms_v12_epoch_2026_q4');

    // 3. GET /hnsw/snapshot/export
    const exportRes = await fetch(`${baseUrl}/hnsw/snapshot/export`);
    assert.equal(exportRes.status, 200);
    const exportBody = (await exportRes.json()) as any;
    assert.equal(exportBody.status, 'SNAPSHOT_EXPORTED');
    assert.ok(exportBody.snapshotBase64.length > 0);
    assert.ok(exportBody.snapshotBytes > 32);

    // 4. POST /hnsw/sync (re-hydrate snapshot + apply delta)
    const syncRes = await fetch(`${baseUrl}/hnsw/sync`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        snapshotBase64: exportBody.snapshotBase64,
        walEntries: [
          {
            walSeq: 1,
            opType: 'UPSERT_NODE',
            uid: 'worker_delta_1',
            timestampMs: Date.now(),
            nodePayload: {
              uid: 'worker_delta_1',
              faceId: 'FACE_DELTA_1',
              keyId: 'kms_v12_epoch_2026_q4',
              modelVersion: 'v11_adaface_512',
              lockToken: 'KS_FTOK_DELTA_1',
              embedding: new Array(512).fill(0.04419), // norm ~ 1.0
              neighborsByLayer: [],
              updatedAtMs: Date.now(),
            },
          },
        ],
      }),
    });
    assert.equal(syncRes.status, 200);
    const syncBody = (await syncRes.json()) as any;
    assert.equal(syncBody.status, 'CLUSTER_NODE_SYNCHRONIZED');
    assert.equal(syncBody.deltaTelemetry.appliedEntries, 1);
    assert.equal(syncBody.deltaTelemetry.upsertedNodes, 1);

    // Verify status now reports nodeCount = 1
    const statusRes3 = await fetch(`${baseUrl}/status`);
    const statusBody3 = (await statusRes3.json()) as any;
    assert.equal(statusBody3.hnswNodeCount, 1);
    assert.equal(statusBody3.watermarkWalSeq, 1);

    // 5. POST /fairness/telemetry
    const telemetryRes = await fetch(`${baseUrl}/fairness/telemetry`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        observations: [
          {
            timestampMs: Date.now(),
            luminanceMean: 110,
            sensorTier: 'ANDROID_MIDRANGE',
            regionCode: 'KA_BLR',
            similarityScore: 0.94,
            outcome: 'GENUINE_VERIFIED',
            latencyMs: 12.0,
          },
        ],
      }),
    });
    assert.equal(telemetryRes.status, 200);
    const telemetryBody = (await telemetryRes.json()) as any;
    assert.equal(telemetryBody.totalWindowSamples, 1);
    assert.equal(telemetryBody.driftAlertTriggered, false);
  } finally {
    await new Promise<void>((resolve) => server.close(() => resolve()));
  }
});
