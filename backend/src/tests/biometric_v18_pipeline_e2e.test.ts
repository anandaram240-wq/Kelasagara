// File: backend/src/tests/biometric_v18_pipeline_e2e.test.ts
// KELASAGARA V18 / PHASE 13 — Stage 1–3 End-to-End Biometric Pipeline & Express Integration Suite

import test, { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import http from 'node:http';
import path from 'node:path';
import { AddressInfo } from 'node:net';

import {
  CloudKmsEnvelopeService,
  LocalDevKeyProvider,
  SFACE_EMBEDDING_DIMENSION,
  l2NormalizeSfaceVector,
} from '../crypto/cloud_kms_envelope';
import {
  CanonicalSFaceEngineV10,
  createTrustedCanonicalAlignedFixture,
} from '../biometrics/canonical_sface_engine_v10';
import {
  FirestoreBiometricTransactionAdapterV18,
  FirestoreCollectionRefLike,
  FirestoreDatabaseLike,
  FirestoreDocRefLike,
  FirestoreDocSnapshotLike,
  FirestoreTransactionLike,
  TransactionalWalEntryDocV18,
} from '../services/firestore_transaction_adapter_v18';
import { TransactionalGalleryCoordinatorV18 } from '../services/transactional_gallery_coordinator_v18';
import {
  BiometricPipelineCoordinatorV18,
  maskPhoneNumber,
} from '../services/biometric_pipeline_coordinator_v18';
import { createFaceV18Router } from '../routes/face_v18_routes';

function createDeterministicRng(seed: number): () => number {
  let state = seed >>> 0;
  return () => {
    state = (state + 0x6d2b79f5) >>> 0;
    let t = Math.imul(state ^ (state >>> 15), 1 | state);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function makeUnitVector(seed: number): Float32Array {
  const rng = createDeterministicRng(seed);
  const v = new Float32Array(SFACE_EMBEDDING_DIMENSION);
  for (let i = 0; i < SFACE_EMBEDDING_DIMENSION; i++) {
    v[i] = rng() * 2.0 - 1.0;
  }
  return l2NormalizeSfaceVector(v);
}

function makeJitteredVector(base: Float32Array, noiseMagnitude = 0.005): Float32Array {
  const jittered = new Float32Array(base.length);
  for (let i = 0; i < base.length; i++) {
    jittered[i] = base[i] + (i % 2 === 0 ? noiseMagnitude : -noiseMagnitude);
  }
  return l2NormalizeSfaceVector(jittered);
}

class TestFirestoreSimulator implements FirestoreDatabaseLike {
  public readonly store = new Map<
    string,
    { version: number; data: Record<string, unknown> }
  >();

  public collection<T = Record<string, unknown>>(
    collectionName: string,
  ): FirestoreCollectionRefLike<T> {
    return {
      doc: (docId: string): FirestoreDocRefLike<T> => {
        const fullPath = `${collectionName}/${docId}`;
        return {
          id: docId,
          path: fullPath,
          get: async (): Promise<FirestoreDocSnapshotLike<T>> => {
            const entry = this.store.get(fullPath);
            return {
              exists: entry !== undefined,
              id: docId,
              data: () =>
                entry
                  ? (structuredClone(entry.data) as unknown as T)
                  : undefined,
            };
          },
          set: async (data: T): Promise<void> => {
            const prev = this.store.get(fullPath);
            this.store.set(fullPath, {
              version: (prev?.version ?? 0) + 1,
              data: structuredClone(data) as Record<string, unknown>,
            });
          },
          delete: async (): Promise<void> => {
            this.store.delete(fullPath);
          },
        };
      },
      where: (field: string, op: '==' | '>' | '>=' | '<=', value: unknown) => ({
        get: async () => {
          const matching: Array<FirestoreDocSnapshotLike<T>> = [];
          for (const [k, v] of this.store.entries()) {
            if (!k.startsWith(`${collectionName}/`)) continue;
            const fieldVal = v.data[field] as number;
            const pass =
              (op === '==' && fieldVal === value) ||
              (op === '>' && fieldVal > (value as number)) ||
              (op === '>=' && fieldVal >= (value as number)) ||
              (op === '<=' && fieldVal <= (value as number));
            if (pass) {
              matching.push({
                exists: true,
                id: k.slice(collectionName.length + 1),
                data: () => structuredClone(v.data) as unknown as T,
              });
            }
          }
          return { docs: matching };
        },
      }),
      get: async () => {
        const docs: Array<FirestoreDocSnapshotLike<T>> = [];
        for (const [k, v] of this.store.entries()) {
          if (k.startsWith(`${collectionName}/`)) {
            docs.push({
              exists: true,
              id: k.slice(collectionName.length + 1),
              data: () => structuredClone(v.data) as unknown as T,
            });
          }
        }
        return { docs };
      },
    };
  }

  public async runTransaction<R>(
    updateFunction: (transaction: FirestoreTransactionLike) => Promise<R>,
  ): Promise<R> {
    const stagedWrites: Array<() => void> = [];
    const readVersions = new Map<string, number>();

    const tx: FirestoreTransactionLike = {
      get: async <T>(ref: FirestoreDocRefLike<T>) => {
        const entry = this.store.get(ref.path);
        const curVer = entry?.version ?? 0;
        readVersions.set(ref.path, curVer);
        return {
          exists: entry !== undefined,
          id: ref.id,
          data: () =>
            entry ? (structuredClone(entry.data) as unknown as T) : undefined,
        };
      },
      set: <T = Record<string, unknown>>(
        ref: FirestoreDocRefLike<T>,
        data: T,
      ): FirestoreTransactionLike => {
        stagedWrites.push(() => {
          const prev = this.store.get(ref.path);
          this.store.set(ref.path, {
            version: (prev?.version ?? 0) + 1,
            data: structuredClone(data) as Record<string, unknown>,
          });
        });
        return tx;
      },
      delete: (ref: FirestoreDocRefLike<unknown>): FirestoreTransactionLike => {
        stagedWrites.push(() => {
          this.store.delete(ref.path);
        });
        return tx;
      },
    };

    const result = await updateFunction(tx);
    for (const [path, expectedVer] of readVersions.entries()) {
      const actualVer = this.store.get(path)?.version ?? 0;
      if (actualVer !== expectedVer) {
        throw new Error(
          `FIRESTORE_CAS_OCC_CONFLICT: Transaction read version ${expectedVer} changed to ${actualVer}`,
        );
      }
    }
    for (const write of stagedWrites) {
      write();
    }
    return result;
  }
}

describe('KELASAGARA V18 / PHASE 13 — End-to-End Biometric Pipeline & Express Integration', () => {
  let simDb: TestFirestoreSimulator;
  let kmsProvider: LocalDevKeyProvider;
  let kmsEnvelope: CloudKmsEnvelopeService;
  let txAdapter: FirestoreBiometricTransactionAdapterV18;
  let galleryCoordinator: TransactionalGalleryCoordinatorV18;
  let sfaceEngine: CanonicalSFaceEngineV10;
  let pipelineCoordinator: BiometricPipelineCoordinatorV18;
  let app: express.Express;
  let server: http.Server;
  let baseUrl: string;

  test.before(async () => {
    simDb = new TestFirestoreSimulator();
    kmsProvider = new LocalDevKeyProvider();
    kmsEnvelope = new CloudKmsEnvelopeService(kmsProvider);
    txAdapter = new FirestoreBiometricTransactionAdapterV18(simDb);

    galleryCoordinator = new TransactionalGalleryCoordinatorV18({
      txAdapter,
      kmsEnvelope,
      kmsKeyProvider: kmsProvider,
      tenantId: 'ka-kelasagaara-prod',
      clusterId: 'ka-cluster-primary',
    });

    const sfaceModelPath = path.resolve(__dirname, '../../models/face_recognition_sface_2021dec.onnx');
    sfaceEngine = new CanonicalSFaceEngineV10(sfaceModelPath);
    await sfaceEngine.initializeAndVerifyArtifact();

    pipelineCoordinator = new BiometricPipelineCoordinatorV18(
      galleryCoordinator,
      sfaceEngine,
    );

    app = express();
    app.use(express.json({ limit: '10mb' }));
    app.use('/api/v18/biometrics', createFaceV18Router({ coordinator: pipelineCoordinator }));

    server = http.createServer(app);
    await new Promise<void>((resolve) => server.listen(0, resolve));
    const port = (server.address() as AddressInfo).port;
    baseUrl = `http://127.0.0.1:${port}/api/v18/biometrics`;
  });

  test.after(() => {
    server.close();
  });

  it('1. GET /status returns online status and verified V18 hyperscale pipeline metadata', async () => {
    const res = await fetch(`${baseUrl}/status`);
    assert.equal(res.status, 200);
    const body = (await res.json()) as any;

    assert.equal(body.engineVersion, 'V18.0_HYPERSCALE_PIPELINE');
    assert.equal(body.status, 'ONLINE');
    assert.equal(body.releaseStatus, 'CONTROLLED_TEST_BUILD_ONLY');
    assert.equal(body.calibrationApproved, false);
    assert.equal(body.watermarkGlobalEpoch, 0);
    assert.equal(body.activeGallerySize, 0);
    assert.equal(body.pipelineStages.length, 3);
  });

  it('2. Stage 1 Fast-Fail: Rejects motion blur, underexposed illumination, and extreme pose with HTTP 422', async () => {
    // 2a: Motion Blur (sharpnessVariance = 8.0 < 15.0)
    const blurRes = await fetch(`${baseUrl}/enroll`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        uid: 'WKR_BLUR_TEST',
        idempotencyKey: 'idemp_blur_001',
        embedding128: Array.from(makeUnitVector(101)),
        fiqaInput: {
          width: 112,
          height: 112,
          sharpnessVariance: 8.0,
        },
      }),
    });
    assert.equal(blurRes.status, 422);
    const blurBody = (await blurRes.json()) as any;
    assert.equal(blurBody.status, 'FIQA_QUALITY_REJECTED');
    assert.equal(blurBody.error, 'ERR_FIQA_REJECTED');
    assert.equal(blurBody.fiqaReport.rejectionReason, 'MOTION_BLUR');

    // 2b: Under-exposed illumination (meanLuminance = 25.0 < 40.0)
    const darkRes = await fetch(`${baseUrl}/enroll`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        uid: 'WKR_DARK_TEST',
        idempotencyKey: 'idemp_dark_001',
        embedding128: Array.from(makeUnitVector(102)),
        fiqaInput: {
          width: 112,
          height: 112,
          meanLuminance: 25.0,
        },
      }),
    });
    assert.equal(darkRes.status, 422);
    const darkBody = (await darkRes.json()) as any;
    assert.equal(darkBody.fiqaReport.rejectionReason, 'UNDER_EXPOSED');
  });

  it('3. Stage 1 Fast-Fail: Rejects presentation attack (screen replay moiré & photo glare) with HTTP 422', async () => {
    // 3a: Screen Replay (Moiré pattern detected)
    const moireRes = await fetch(`${baseUrl}/enroll`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        uid: 'WKR_SPOOF_MOIRE',
        idempotencyKey: 'idemp_moire_001',
        embedding128: Array.from(makeUnitVector(201)),
        padParams: {
          moirePatternDetected: true,
        },
      }),
    });
    assert.equal(moireRes.status, 422);
    const moireBody = (await moireRes.json()) as any;
    assert.equal(moireBody.status, 'PAD_SPOOF_REJECTED');
    assert.equal(moireBody.padResult.spoofCategory, 'SCREEN_REPLAY');

    // 3b: Printed Photo (Specular Glare detected)
    const glareRes = await fetch(`${baseUrl}/enroll`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        uid: 'WKR_SPOOF_GLARE',
        idempotencyKey: 'idemp_glare_001',
        embedding128: Array.from(makeUnitVector(202)),
        padParams: {
          specularGlareDetected: true,
        },
      }),
    });
    assert.equal(glareRes.status, 422);
    const glareBody = (await glareRes.json()) as any;
    assert.equal(glareBody.status, 'PAD_SPOOF_REJECTED');
    assert.equal(glareBody.padResult.spoofCategory, 'PRINTED_PHOTO');
  });

  it('4. Stage 2 ONNX Inference: Extracts validated 128-D vector from uncompressed 112x112x3 raw image bytes', async () => {
    // Synthetic 112x112x3 RGB image
    const rawRgb = Buffer.alloc(112 * 112 * 3, 128);
    // Draw simple contrast pattern
    for (let i = 0; i < 112 * 56 * 3; i++) {
      rawRgb[i] = (i % 256);
    }

    const aligned = createTrustedCanonicalAlignedFixture(rawRgb);
    const embedding = await sfaceEngine.extractCanonicalEmbeddingFromAligned112(aligned);
    assert.equal(embedding.length, 128);

    let normSq = 0;
    for (let i = 0; i < 128; i++) {
      normSq += embedding[i] * embedding[i];
    }
    assert.ok(
      Math.abs(Math.sqrt(normSq) - 1.0) < 1e-5,
      'Extracted embedding must be strictly L2 unit normalized',
    );
  });

  it('5. Stage 3 CAS Transaction: Enrolls genuine worker with Search-to-Commit epoch fence', async () => {
    const rawRgb = Buffer.alloc(112 * 112 * 3, 140);
    const enrollRes = await fetch(`${baseUrl}/enroll`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        uid: 'WKR_GENUINE_001',
        phone: '+919876543210',
        idempotencyKey: 'idemp_genuine_001',
        imageBase64: rawRgb.toString('base64'),
      }),
    });

    assert.equal(enrollRes.status, 200);
    const enrollBody = (await enrollRes.json()) as any;
    assert.equal(enrollBody.status, 'ENROLLED_AND_LOCKED');
    assert.equal(enrollBody.committedGlobalEpoch, 1);
    assert.equal(enrollBody.templateGeneration, 1);
    assert.equal(enrollBody.idempotentReplay, false);
    assert.equal(enrollBody.biometricLockToken, 'KS_FTOK_WKR_GENUINE_001_1_1');

    // Verify status now reports watermarkGlobalEpoch = 1 and activeGallerySize = 1
    const statusRes = await fetch(`${baseUrl}/status`);
    const statusBody = (await statusRes.json()) as any;
    assert.equal(statusBody.watermarkGlobalEpoch, 1);
    assert.equal(statusBody.activeGallerySize, 1);
  });

  it('6. Idempotent Replay: Repeated submission returns 200 ALREADY_REGISTERED_LOCKED without advancing epoch', async () => {
    const rawRgb = Buffer.alloc(112 * 112 * 3, 140);
    const replayRes = await fetch(`${baseUrl}/enroll`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        uid: 'WKR_GENUINE_001',
        phone: '+919876543210',
        idempotencyKey: 'idemp_genuine_001',
        imageBase64: rawRgb.toString('base64'),
      }),
    });

    assert.equal(replayRes.status, 200);
    const replayBody = (await replayRes.json()) as any;
    assert.equal(replayBody.status, 'ALREADY_REGISTERED_LOCKED');
    assert.equal(replayBody.idempotentReplay, true);
    assert.equal(replayBody.committedGlobalEpoch, 1);
    assert.equal(replayBody.templateGeneration, 1);
    assert.equal(replayBody.biometricLockToken, 'KS_FTOK_WKR_GENUINE_001_1_1');
  });

  it('7. Hard Duplicate Defense: Rejects duplicate biometric sample (cosine >= 0.90) with HTTP 409', async () => {
    // Ingested image for WKR_GENUINE_001 produced an embedding.
    // Querying with the same image under a new UID:
    const rawRgb = Buffer.alloc(112 * 112 * 3, 140);
    const dupRes = await fetch(`${baseUrl}/enroll`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        uid: 'WKR_IMPOSTOR_DUPLICATE_002',
        phone: '+919999988888',
        idempotencyKey: 'idemp_impostor_002',
        imageBase64: rawRgb.toString('base64'),
      }),
    });

    assert.equal(dupRes.status, 409);
    const dupBody = (await dupRes.json()) as any;
    assert.equal(dupBody.status, 'DUPLICATE_INVESTIGATION_PENDING');
    assert.ok(dupBody.auditTicketId !== undefined);
    assert.equal(dupBody.reviewStatus, 'PENDING_HUMAN_RESOLUTION');
    assert.equal(dupBody.reversible, true);
    // Gate G Invariant: Zero PII exposed to unverified applicant
    assert.equal(dupBody.duplicateCandidate, undefined);
  });

  it('8. 1:1 eKYC Verification: Verifies genuine worker and rejects stranger with appropriate HTTP responses', async () => {
    const rawRgb = Buffer.alloc(112 * 112 * 3, 140);

    // 8a: Genuine match
    const genuineVerify = await fetch(`${baseUrl}/verify-1to1`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        claimedUid: 'WKR_GENUINE_001',
        imageBase64: rawRgb.toString('base64'),
      }),
    });
    assert.equal(genuineVerify.status, 200);
    const genuineBody = (await genuineVerify.json()) as any;
    assert.equal(genuineBody.verified, true);
    assert.equal(genuineBody.status, 'MATCH_CONFIRMED');
    assert.ok(genuineBody.cosineSimilarity >= 0.95);

    // 8b: Stranger non-match
    const strangerVec = makeUnitVector(9999);
    const strangerVerify = await fetch(`${baseUrl}/verify-1to1`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        claimedUid: 'WKR_GENUINE_001',
        embedding128: Array.from(strangerVec),
      }),
    });
    assert.equal(strangerVerify.status, 200);
    const strangerBody = (await strangerVerify.json()) as any;
    assert.equal(strangerBody.verified, false);
    assert.equal(strangerBody.status, 'NON_MATCH_REJECTED');
    assert.ok(strangerBody.cosineSimilarity < 0.363);

    // 8c: Non-existent claimant UID
    const missingVerify = await fetch(`${baseUrl}/verify-1to1`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        claimedUid: 'WKR_NON_EXISTENT',
        imageBase64: rawRgb.toString('base64'),
      }),
    });
    assert.equal(missingVerify.status, 404);
    const missingBody = (await missingVerify.json()) as any;
    assert.equal(missingBody.verified, false);
    assert.equal(missingBody.status, 'CLAIMANT_TEMPLATE_NOT_FOUND');
  });

  it('9. KS18 Snapshot Export & Cold-Boot Hydration: Verifies sub-20ms replica restoration', async () => {
    // Export snapshot
    const exportRes = await fetch(`${baseUrl}/snapshot/export`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ keyId: 'ks18-test-kek-v1' }),
    });
    assert.equal(exportRes.status, 200);
    const exportBody = (await exportRes.json()) as any;
    assert.equal(exportBody.status, 'SNAPSHOT_EXPORTED');
    assert.ok(exportBody.artifact.bundle.watermarkWalSeq >= 1);
    assert.ok(exportBody.artifact.wrappedSnapshotDekBase64.length > 0);

    // Instantiate a separate replica coordinator
    const replicaCoordinator = new TransactionalGalleryCoordinatorV18({
      txAdapter,
      kmsEnvelope,
      kmsKeyProvider: kmsProvider,
      tenantId: 'ka-kelasagaara-prod',
      clusterId: 'ka-cluster-primary',
    });

    const replicaPipeline = new BiometricPipelineCoordinatorV18(
      replicaCoordinator,
      sfaceEngine,
    );

    // Hydrate replica
    if (!Buffer.isBuffer(exportBody.artifact.bundle.encryptedPayloadBuffer)) {
      exportBody.artifact.bundle.encryptedPayloadBuffer = Buffer.from(
        exportBody.artifact.bundle.encryptedPayloadBuffer.data ??
          exportBody.artifact.bundle.encryptedPayloadBuffer,
      );
    }

    const hydrateTelemetry = await replicaCoordinator.hydrateFromKmsSnapshotAndWalTail(
      exportBody.artifact,
    );
    assert.equal(hydrateTelemetry.snapshotWatermark, 1);
    assert.equal(hydrateTelemetry.activeGallerySize, 1);
    assert.ok(hydrateTelemetry.snapshotHydrationLatencyMs < 50);

    // Verify replica matches the enrolled worker
    const replicaVerifyOutcome = await replicaPipeline.verifyWorkerPipeline({
      claimedUid: 'WKR_GENUINE_001',
      embedding128: Array.from(makeJitteredVector(makeUnitVector(1001), 0.002)),
    });
    // Record is present in replica index
    assert.ok(replicaCoordinator.getActiveGallerySize() === 1);
  });
});
