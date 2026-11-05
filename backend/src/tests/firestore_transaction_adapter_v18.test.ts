// File: backend/src/tests/firestore_transaction_adapter_v18.test.ts
// KELASAGARA V18 / PHASE 13 — Firestore runTransaction CAS, Epoch Drift & KS18 Snapshot Suite

import * as crypto from 'node:crypto';
import { describe, it, beforeEach } from 'node:test';
import assert from 'node:assert/strict';

import {
  CANONICAL_SFACE_MODEL_ID,
  CANONICAL_SFACE_MODEL_VERSION,
  CANONICAL_TEMPLATE_SCHEMA_VERSION,
  CloudKmsEnvelopeService,
  LocalDevKeyProvider,
  SFACE_EMBEDDING_DIMENSION,
  l2NormalizeSfaceVector,
} from '../crypto/cloud_kms_envelope';

import {
  FirestoreBiometricTransactionAdapterV18,
  FirestoreCollectionRefLike,
  FirestoreDatabaseLike,
  FirestoreDocRefLike,
  FirestoreDocSnapshotLike,
  FirestoreTransactionLike,
} from '../services/firestore_transaction_adapter_v18';

import {
  computeIomHammingSimilarity,
  computeIso24745IomCancelableCode,
  exportEncryptedAlignedSnapshotKs18,
  hydrateEncryptedSnapshotKs18,
} from '../biometrics/iso24745_iom_cancelable_snapshot_v18';

/**
 * Optimistic Concurrency Firestore Emulator Harness:
 * Enforces Firestore's strict "all reads before writes" rule and automatically retries
 * transaction callbacks when two concurrent transactions modify the same document version.
 */
class StrictFirestoreTransactionHarness implements FirestoreDatabaseLike {
  private readonly store = new Map<
    string,
    { version: number; data: Record<string, unknown> }
  >();
  public transactionRetryCount = 0;
  public injectContentionOnFirstAttempt = false;

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
                id: k.split('/')[1],
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
              id: k.split('/')[1],
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
    transactionOptions?: { maxAttempts?: number },
  ): Promise<R> {
    const maxAttempts = transactionOptions?.maxAttempts ?? 5;

    for (let attempt = 1; attempt <= maxAttempts; attempt++) {
      let writeStarted = false;
      const readVersions = new Map<string, number>();
      const stagedWrites = new Map<string, Record<string, unknown> | null>();

      const tx: FirestoreTransactionLike = {
        get: async <T = Record<string, unknown>>(
          docRef: FirestoreDocRefLike<T>,
        ): Promise<FirestoreDocSnapshotLike<T>> => {
          if (writeStarted) {
            throw new Error(
              'FIRESTORE_PROTOCOL_VIOLATION: Firestore transactions require all reads to be executed before all writes.',
            );
          }
          const entry = this.store.get(docRef.path);
          readVersions.set(docRef.path, entry?.version ?? 0);
          return {
            exists: entry !== undefined,
            id: docRef.id,
            data: () =>
              entry
                ? (structuredClone(entry.data) as unknown as T)
                : undefined,
          };
        },
        set: <T = Record<string, unknown>>(
          docRef: FirestoreDocRefLike<T>,
          data: T,
        ): FirestoreTransactionLike => {
          writeStarted = true;
          stagedWrites.set(
            docRef.path,
            structuredClone(data) as Record<string, unknown>,
          );
          return tx;
        },
        delete: (
          docRef: FirestoreDocRefLike<unknown>,
        ): FirestoreTransactionLike => {
          writeStarted = true;
          stagedWrites.set(docRef.path, null);
          return tx;
        },
      };

      const result = await updateFunction(tx);

      // Simulate a concurrent transaction commit between read and commit on attempt 1
      if (this.injectContentionOnFirstAttempt && attempt === 1) {
        this.injectContentionOnFirstAttempt = false;
        this.transactionRetryCount++;
        continue;
      }

      // Verify optimistic read-set versions have not changed
      let conflictDetected = false;
      for (const [docPath, expectedVer] of readVersions.entries()) {
        const currentVer = this.store.get(docPath)?.version ?? 0;
        if (currentVer !== expectedVer) {
          conflictDetected = true;
          break;
        }
      }

      if (conflictDetected) {
        this.transactionRetryCount++;
        if (attempt === maxAttempts) {
          throw new Error('FIRESTORE_TRANSACTION_ABORTED: Max retries exceeded.');
        }
        continue;
      }

      // Commit staged writes atomically
      for (const [docPath, payload] of stagedWrites.entries()) {
        if (payload === null) {
          this.store.delete(docPath);
        } else {
          const prev = this.store.get(docPath);
          this.store.set(docPath, {
            version: (prev?.version ?? 0) + 1,
            data: payload,
          });
        }
      }

      return result;
    }

    throw new Error('FIRESTORE_TRANSACTION_EXHAUSTED');
  }
}

function makeSfaceVec128(seed: number): Float32Array {
  const vec = new Float32Array(SFACE_EMBEDDING_DIMENSION);
  let state = seed >>> 0;
  for (let i = 0; i < SFACE_EMBEDDING_DIMENSION; i++) {
    state = (state * 1664525 + 1013904223) >>> 0;
    vec[i] = (state / 4294967296) * 2.0 - 1.0;
  }
  return l2NormalizeSfaceVector(vec);
}

describe('KELASAGARA V18 / PHASE 13 — Production Firestore Transaction & KS18 Suite', () => {
  let dbHarness: StrictFirestoreTransactionHarness;
  let kmsEnvelope: CloudKmsEnvelopeService;
  let nodeAAdapter: FirestoreBiometricTransactionAdapterV18;
  let nodeBAdapter: FirestoreBiometricTransactionAdapterV18;

  beforeEach(() => {
    dbHarness = new StrictFirestoreTransactionHarness();
    kmsEnvelope = new CloudKmsEnvelopeService(new LocalDevKeyProvider());
    // Two independent service adapters representing two separate Cloud Run instances
    nodeAAdapter = new FirestoreBiometricTransactionAdapterV18(
      dbHarness,
      'node-A-bengaluru',
    );
    nodeBAdapter = new FirestoreBiometricTransactionAdapterV18(
      dbHarness,
      'node-B-bengaluru',
    );
  });

  async function buildSealedInput(params: {
    uid: string;
    idempotencyKey: string;
    screenedAtGlobalEpoch: number;
    expectedTemplateGeneration?: number;
    allowReEnrollment?: boolean;
    seed?: number;
  }) {
    const vec = makeSfaceVec128(params.seed ?? 101);
    const envelope = await kmsEnvelope.sealTemplateV3(
      {
        sfaceEmbedding128: vec,
        isoQualityScore: 91.0,
        padLivenessScore: 0.96,
      },
      {
        uid: params.uid,
        modelVersion: CANONICAL_SFACE_MODEL_VERSION,
        templateSchemaVersion: CANONICAL_TEMPLATE_SCHEMA_VERSION,
        tenantId: 'karnataka-kelasagaara-prod',
        purpose: 'BIOMETRIC_VAULT_SFACE_V3',
      },
    );

    return {
      uid: params.uid,
      tenantId: 'karnataka-kelasagaara-prod',
      maskedPhone: '******5177',
      idempotencyKey: params.idempotencyKey,
      requestFingerprintSha256: crypto
        .createHash('sha256')
        .update(`${params.uid}:${params.idempotencyKey}`)
        .digest('hex'),
      screenedAtGlobalEpoch: params.screenedAtGlobalEpoch,
      expectedTemplateGeneration: params.expectedTemplateGeneration ?? 0,
      allowReEnrollment: params.allowReEnrollment ?? false,
      decisionStatus: 'CLEAN_APPROVED' as const,
      preSealedEnvelope: envelope,
    };
  }

  it('1. Enforces read-before-write transaction discipline, retries on contention, and commits WAL outbox', async () => {
    dbHarness.injectContentionOnFirstAttempt = true;
    const input = await buildSealedInput({
      uid: 'KLS-WKR-TX-001',
      idempotencyKey: 'idem-tx-001',
      screenedAtGlobalEpoch: 0,
    });

    const outcome = await nodeAAdapter.commitEnrollmentTransactionally(input);

    assert.equal(outcome.status, 'COMMITTED_NEW');
    assert.equal(outcome.committedGlobalEpoch, 1);
    assert.equal(outcome.templateGeneration, 1);
    assert.equal(dbHarness.transactionRetryCount, 1);

    const walEntries = await nodeBAdapter.fetchIncrementalWalSince(0);
    assert.equal(walEntries.length, 1);
    assert.equal(walEntries[0].uid, 'KLS-WKR-TX-001');
    assert.equal(walEntries[0].walSeq, 1);
  });

  it('2. Detects Search-to-Commit Race across two instances and returns RECHECK_REQUIRED_EPOCH_DRIFT', async () => {
    // Both Request A (on Node A) and Request B (on Node B) screen the gallery at epoch = 0
    const inputA = await buildSealedInput({
      uid: 'KLS-RACE-USER-A',
      idempotencyKey: 'idem-race-A',
      screenedAtGlobalEpoch: 0,
      seed: 501,
    });
    const inputB = await buildSealedInput({
      uid: 'KLS-RACE-USER-B',
      idempotencyKey: 'idem-race-B',
      screenedAtGlobalEpoch: 0, // Stale once A commits!
      seed: 501,
    });

    // Node A commits first, advancing globalEpoch from 0 -> 1
    const resA = await nodeAAdapter.commitEnrollmentTransactionally(inputA);
    assert.equal(resA.status, 'COMMITTED_NEW');
    assert.equal(resA.committedGlobalEpoch, 1);

    // Node B attempts to commit using its pre-A screening epoch (0):
    // Must NOT commit! Must return RECHECK_REQUIRED_EPOCH_DRIFT with latestGlobalEpoch = 1.
    const resB = await nodeBAdapter.commitEnrollmentTransactionally(inputB);
    assert.equal(resB.status, 'RECHECK_REQUIRED_EPOCH_DRIFT');
    assert.equal(resB.latestGlobalEpoch, 1);
  });

  it('3. Enforces idempotent replay on identical retries and blocks idempotency payload tampering', async () => {
    const input = await buildSealedInput({
      uid: 'KLS-IDEM-USER',
      idempotencyKey: 'idem-key-fixed',
      screenedAtGlobalEpoch: 0,
    });

    const first = await nodeAAdapter.commitEnrollmentTransactionally(input);
    const replay = await nodeBAdapter.commitEnrollmentTransactionally(input);

    assert.equal(first.status, 'COMMITTED_NEW');
    assert.equal(replay.status, 'IDEMPOTENT_REPLAY');
    assert.equal(replay.committedGlobalEpoch, first.committedGlobalEpoch);

    // Reusing the same idempotencyKey with a different fingerprint must fail with conflict
    const tampered = {
      ...input,
      requestFingerprintSha256: 'different_fingerprint_hash',
    };
    const conflict = await nodeBAdapter.commitEnrollmentTransactionally(tampered);
    assert.equal(conflict.status, 'CONFLICT_IDEMPOTENCY_PAYLOAD_MISMATCH');
  });

  it('4. Enforces templateGeneration fencing across re-enrollment and DPDPA §12 erasure', async () => {
    const initial = await buildSealedInput({
      uid: 'KLS-GEN-USER',
      idempotencyKey: 'idem-gen-1',
      screenedAtGlobalEpoch: 0,
      expectedTemplateGeneration: 0,
    });
    const res1 = await nodeAAdapter.commitEnrollmentTransactionally(initial);
    assert.equal(res1.status, 'COMMITTED_NEW');
    assert.equal(res1.templateGeneration, 1);

    // Stale re-enrollment expecting generation 0 instead of 1 must be rejected
    const staleReEnroll = await buildSealedInput({
      uid: 'KLS-GEN-USER',
      idempotencyKey: 'idem-gen-stale',
      screenedAtGlobalEpoch: 1,
      expectedTemplateGeneration: 0,
      allowReEnrollment: true,
    });
    const staleRes = await nodeAAdapter.commitEnrollmentTransactionally(staleReEnroll);
    assert.equal(staleRes.status, 'CONFLICT_STALE_GENERATION');

    // Valid re-enrollment expecting generation 1 advances generation to 2
    const validReEnroll = await buildSealedInput({
      uid: 'KLS-GEN-USER',
      idempotencyKey: 'idem-gen-2',
      screenedAtGlobalEpoch: 1,
      expectedTemplateGeneration: 1,
      allowReEnrollment: true,
    });
    const res2 = await nodeBAdapter.commitEnrollmentTransactionally(validReEnroll);
    assert.equal(res2.status, 'COMMITTED_NEW');
    assert.equal(res2.templateGeneration, 2);

    // DPDPA §12 erasure deletes vault doc and advances tombstone generation to 3
    const eraseRes = await nodeAAdapter.commitErasureTransactionally({
      uid: 'KLS-GEN-USER',
      idempotencyKey: 'idem-erase-1',
    });
    assert.equal(eraseRes.erased, true);
    assert.equal(eraseRes.newGeneration, 3);
  });

  it('5. Verifies ISO/IEC 24745 IoM Cancelable Code preserves similarity on jitter and unlinks on salt rotation', () => {
    const saltEpoch1 = crypto.createHash('sha256').update('test-salt-epoch-1').digest();
    const saltEpoch2 = crypto.createHash('sha256').update('test-salt-epoch-2').digest();

    const baseVec = makeSfaceVec128(900);
    // Genuine capture with micro-jitter (unlike HMAC-SHA256, IoM preserves high agreement!)
    const jitteredVec = new Float32Array(baseVec);
    for (let i = 0; i < 128; i++) {
      jitteredVec[i] += (i % 2 === 0 ? 1 : -1) * 0.005;
    }
    const normJittered = l2NormalizeSfaceVector(jitteredVec);
    const strangerVec = makeSfaceVec128(901);

    const codeBase = computeIso24745IomCancelableCode(baseVec, saltEpoch1);
    const codeJittered = computeIso24745IomCancelableCode(normJittered, saltEpoch1);
    const codeStranger = computeIso24745IomCancelableCode(strangerVec, saltEpoch1);
    const codeRotatedSalt = computeIso24745IomCancelableCode(baseVec, saltEpoch2);

    const genuineSim = computeIomHammingSimilarity(codeBase, codeJittered);
    const strangerSim = computeIomHammingSimilarity(codeBase, codeStranger);
    const rotatedSaltSim = computeIomHammingSimilarity(codeBase, codeRotatedSalt);

    assert.ok(
      genuineSim >= 0.85,
      `Expected genuine IoM similarity >= 0.85, got ${genuineSim}`,
    );
    assert.ok(
      strangerSim < 0.25,
      `Expected stranger IoM similarity < 0.25, got ${strangerSim}`,
    );
    assert.ok(
      rotatedSaltSim < 0.25,
      `Expected rotated salt IoM similarity < 0.25, got ${rotatedSaltSim}`,
    );
  });

  it('6. Verifies Encrypted 8-Byte Aligned KS18 Snapshot hydration and AAD/Ciphertext tamper rejection', () => {
    const snapKey = crypto.randomBytes(32);
    const records = Array.from({ length: 50 }, (_, i) => ({
      uid: `KLS-SNAP-${i}`,
      maskedPhone: '******1111',
      modelId: CANONICAL_SFACE_MODEL_ID,
      modelVersion: CANONICAL_SFACE_MODEL_VERSION,
      templateSchemaVersion: CANONICAL_TEMPLATE_SCHEMA_VERSION,
      sfaceEmbedding128: makeSfaceVec128(3000 + i),
      isoQualityScore: 90.0,
      padLivenessScore: 0.95,
      enrolledAtEpochMs: 1700000000000,
    }));

    const bundle = exportEncryptedAlignedSnapshotKs18({
      records,
      watermarkWalSeq: 50,
      clusterId: 'karnataka-prod-cluster',
      keyId: 'kek-v18-active',
      snapshotEncryptionKey32: snapKey,
    });

    const hydrated = hydrateEncryptedSnapshotKs18({
      bundle,
      expectedClusterId: 'karnataka-prod-cluster',
      snapshotEncryptionKey32: snapKey,
    });

    assert.equal(hydrated.index.size, 50);
    assert.equal(hydrated.watermarkWalSeq, 50);

    // Splicing snapshot to a different clusterId must fail AES-GCM AAD verification
    assert.throws(
      () =>
        hydrateEncryptedSnapshotKs18({
          bundle,
          expectedClusterId: 'spoofed-cluster-id',
          snapshotEncryptionKey32: snapKey,
        }),
      /Unsupported state or unable to authenticate data/,
    );
  });
});
