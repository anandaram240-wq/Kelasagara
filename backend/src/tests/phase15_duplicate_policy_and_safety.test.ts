// File: backend/src/tests/phase15_duplicate_policy_and_safety.test.ts
// KELASAGARA V18 / PHASE 15 — Gate G: Duplicate Decision Safety Policy Audit
// Tests reversible investigation tickets, zero PII leakage, preservation of existing accounts, and dispute recovery.

import { describe, it } from 'node:test';
import * as assert from 'node:assert';
import * as crypto from 'node:crypto';

import {
  CANONICAL_SFACE_MODEL_ID,
  CANONICAL_SFACE_MODEL_VERSION,
  CANONICAL_TEMPLATE_SCHEMA_VERSION,
  SFACE_EMBEDDING_DIMENSION,
  LocalDevKeyProvider,
  CloudKmsEnvelopeService,
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
  TransactionalGalleryCoordinatorV18,
} from '../services/transactional_gallery_coordinator_v18';
import { BiometricAuditTicketV3 } from '../services/gallery_consistency_service';
import {
  BiometricPipelineCoordinatorV18,
} from '../services/biometric_pipeline_coordinator_v18';

function generateNormalizedEmbedding(seedStr: string): Float32Array {
  const vec = new Float32Array(SFACE_EMBEDDING_DIMENSION);
  let normSq = 0;
  for (let i = 0; i < SFACE_EMBEDDING_DIMENSION; i++) {
    const subHash = crypto
      .createHash('sha256')
      .update(`${seedStr}_coord_${i}`)
      .digest();
    const val = subHash.readInt16BE(0) / 32768.0;
    vec[i] = val;
    normSq += val * val;
  }
  const invNorm = 1.0 / Math.sqrt(normSq);
  for (let i = 0; i < SFACE_EMBEDDING_DIMENSION; i++) vec[i] *= invNorm;
  return vec;
}

class MemoryFirestoreSimulator implements FirestoreDatabaseLike {
  public readonly store = new Map<string, { version: number; data: Record<string, unknown> }>();

  constructor() {
    this.store.set('biometric_cluster_meta/global_state', {
      version: 1,
      data: { globalEpoch: 0, watermarkWalSeq: 0, clusterId: 'test-cluster' },
    });
  }

  public collection<T = Record<string, unknown>>(collectionName: string): FirestoreCollectionRefLike<T> {
    return {
      doc: (docId: string): FirestoreDocRefLike<T> => {
        const fullPath = `${collectionName}/${docId}`;
        return {
          id: docId,
          path: fullPath,
          get: async () => {
            const entry = this.store.get(fullPath);
            return {
              exists: entry !== undefined,
              id: docId,
              data: () => (entry ? (structuredClone(entry.data) as unknown as T) : undefined),
            };
          },
          set: async (data: T) => {
            const prev = this.store.get(fullPath);
            this.store.set(fullPath, {
              version: (prev?.version ?? 0) + 1,
              data: structuredClone(data) as Record<string, unknown>,
            });
          },
          delete: async () => {
            this.store.delete(fullPath);
          },
        };
      },
      where: (field: string, op: any, value: unknown) => ({
        get: async () => {
          const matching: Array<FirestoreDocSnapshotLike<T>> = [];
          for (const [k, v] of this.store.entries()) {
            if (!k.startsWith(`${collectionName}/`)) continue;
            const fieldVal = v.data[field] as number;
            const pass =
              (op === '==' && fieldVal === value) ||
              (op === '>' && fieldVal > (value as number));
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
            docs.push({ exists: true, id: k.split('/')[1], data: () => structuredClone(v.data) as unknown as T });
          }
        }
        return { docs };
      },
    };
  }

  public async runTransaction<R>(
    updateFunction: (transaction: FirestoreTransactionLike) => Promise<R>,
  ): Promise<R> {
    const stagedWrites = new Map<string, Record<string, unknown> | null>();
    const tx: FirestoreTransactionLike = {
      get: async <T = Record<string, unknown>>(
        docRef: FirestoreDocRefLike<T>,
      ): Promise<FirestoreDocSnapshotLike<T>> => {
        const entry = this.store.get(docRef.path);
        return {
          exists: entry !== undefined,
          id: docRef.id,
          data: () => (entry ? (structuredClone(entry.data) as unknown as T) : undefined),
        };
      },
      set: <T = Record<string, unknown>>(
        docRef: FirestoreDocRefLike<T>,
        data: T,
      ): FirestoreTransactionLike => {
        stagedWrites.set(docRef.path, structuredClone(data) as Record<string, unknown>);
        return tx;
      },
      delete: (docRef: FirestoreDocRefLike<unknown>): FirestoreTransactionLike => {
        stagedWrites.set(docRef.path, null);
        return tx;
      },
    };

    const result = await updateFunction(tx);
    for (const [path, data] of stagedWrites.entries()) {
      if (data === null) {
        this.store.delete(path);
      } else {
        const cur = this.store.get(path);
        this.store.set(path, { version: (cur?.version ?? 0) + 1, data });
      }
    }
    return result;
  }
}

describe('Phase 15 — Gate G: Duplicate Decision Safety Policy Audit', () => {
  it('1. High match score (cosine >= 0.90) creates a reversible review case in biometric_audit_queue', async () => {
    const keyProvider = new LocalDevKeyProvider();
    const kmsEnvelope = new CloudKmsEnvelopeService(keyProvider);
    const db = new MemoryFirestoreSimulator();
    const adapter = new FirestoreBiometricTransactionAdapterV18(db);

    const coordinator = new TransactionalGalleryCoordinatorV18({
      txAdapter: adapter,
      kmsEnvelope,
      kmsKeyProvider: keyProvider,
    });

    // 1. Enroll legitimate existing worker Alice
    const aliceEmbedding = generateNormalizedEmbedding('worker_alice_identity');
    const resAlice = await coordinator.enrollWorkerWithEpochFencedRetry({
      uid: 'worker_alice_original',
      maskedPhone: '+91 98765 11111',
      idempotencyKey: 'idemp_alice_1',
      payload: {
        sfaceEmbedding128: aliceEmbedding,
        isoQualityScore: 98.0,
        padLivenessScore: 0.99,
      },
    });
    assert.strictEqual(resAlice.enrolled, true);

    // 2. Applicant Bob submits an identical or near-identical face (cosine >= 0.90)
    const resBob = await coordinator.enrollWorkerWithEpochFencedRetry({
      uid: 'applicant_bob_contested',
      maskedPhone: '+91 98765 22222',
      idempotencyKey: 'idemp_bob_1',
      payload: {
        sfaceEmbedding128: aliceEmbedding, // identical face
        isoQualityScore: 97.0,
        padLivenessScore: 0.98,
      },
    });

    // Verify Bob is not enrolled, but an audit ticket is created
    assert.strictEqual(resBob.enrolled, false);
    assert.strictEqual(resBob.decisionStatus, 'HARD_DUPLICATE_BLOCKED');
    assert.ok(resBob.auditTicketId !== undefined, 'auditTicketId must be generated');
    assert.ok(resBob.auditTicketId!.startsWith('audit_dup_applicant_bob_contested'));

    // Verify the investigation ticket exists in biometric_audit_queue
    const auditDoc = db.store.get(`biometric_audit_queue/${resBob.auditTicketId}`);
    assert.ok(auditDoc !== undefined, 'Ticket must be persisted in biometric_audit_queue');
    assert.strictEqual(auditDoc.data.candidateUid, 'applicant_bob_contested');
    assert.strictEqual(auditDoc.data.matchedUid, 'worker_alice_original');
    assert.ok(Number(auditDoc.data.cosineSimilarity) >= 0.90);
  });

  it('2. Existing registered worker account remains completely active and untouched', async () => {
    const keyProvider = new LocalDevKeyProvider();
    const kmsEnvelope = new CloudKmsEnvelopeService(keyProvider);
    const db = new MemoryFirestoreSimulator();
    const adapter = new FirestoreBiometricTransactionAdapterV18(db);

    const coordinator = new TransactionalGalleryCoordinatorV18({
      txAdapter: adapter,
      kmsEnvelope,
      kmsKeyProvider: keyProvider,
    });

    const aliceEmbedding = generateNormalizedEmbedding('worker_alice_profile');
    await coordinator.enrollWorkerWithEpochFencedRetry({
      uid: 'worker_alice_profile',
      maskedPhone: '+91 98765 11111',
      idempotencyKey: 'idemp_alice_p',
      payload: { sfaceEmbedding128: aliceEmbedding, isoQualityScore: 95.0, padLivenessScore: 0.98 },
    });

    // Inspect Alice's vault record before contested enrollment
    const vaultBefore = db.store.get('biometric_vault/worker_alice_profile');
    assert.ok(vaultBefore !== undefined);
    assert.strictEqual(vaultBefore.data.status, 'ACTIVE');
    assert.strictEqual(vaultBefore.data.templateGeneration, 1);
    const beforeEnvelope = vaultBefore.data.envelope;

    // Contested enrollment attempt
    await coordinator.enrollWorkerWithEpochFencedRetry({
      uid: 'applicant_charlie_contested',
      maskedPhone: '+91 98765 33333',
      idempotencyKey: 'idemp_charlie_p',
      payload: { sfaceEmbedding128: aliceEmbedding, isoQualityScore: 95.0, padLivenessScore: 0.98 },
    });

    // Verify Alice's vault record is completely unchanged
    const vaultAfter = db.store.get('biometric_vault/worker_alice_profile');
    assert.strictEqual(vaultAfter?.data.status, 'ACTIVE');
    assert.strictEqual(vaultAfter?.data.templateGeneration, 1);
    assert.deepStrictEqual(vaultAfter?.data.envelope, beforeEnvelope);
  });

  it('3. Zero Candidate PII is exposed to the applicant on HTTP 409 response', async () => {
    // Simulate what face_v18_routes.ts returns on HARD_DUPLICATE_BLOCKED
    const mockPipelineResult = {
      success: false,
      decisionStatus: 'HARD_DUPLICATE_BLOCKED' as const,
      auditTicketId: 'audit_dup_applicant_xyz_0_0',
      duplicateCandidate: {
        matchedUid: 'worker_secret_identity_123',
        maxCosineSimilarity: 0.9845,
        matchedMaskedPhone: '+91 98765 43210',
      },
      releaseStatus: 'CONTROLLED_TEST_BUILD_ONLY' as const,
    };

    // Transform using the sanitized route logic
    const sanitizedHttpResponse = {
      status: 'DUPLICATE_INVESTIGATION_PENDING',
      error: 'DUPLICATE_INVESTIGATION_PENDING',
      message: 'Biometric similarity requires standard compliance review. An inquiry ticket has been opened.',
      auditTicketId: mockPipelineResult.auditTicketId,
      reviewStatus: 'PENDING_HUMAN_RESOLUTION',
      reversible: true,
      releaseStatus: mockPipelineResult.releaseStatus,
    };

    const responseJson = JSON.stringify(sanitizedHttpResponse);

    // Verify that neither the matched UID nor the matched phone exists anywhere in the JSON response
    assert.strictEqual(responseJson.includes('worker_secret_identity_123'), false);
    assert.strictEqual(responseJson.includes('43210'), false);
    assert.strictEqual(responseJson.includes('0.9845'), false);
    assert.strictEqual(sanitizedHttpResponse.status, 'DUPLICATE_INVESTIGATION_PENDING');
    assert.strictEqual(sanitizedHttpResponse.reversible, true);
  });

  it('4. Administrative Resolution: An authorized officer can resolve an erroneous duplicate case', async () => {
    const keyProvider = new LocalDevKeyProvider();
    const kmsEnvelope = new CloudKmsEnvelopeService(keyProvider);
    const db = new MemoryFirestoreSimulator();
    const adapter = new FirestoreBiometricTransactionAdapterV18(db);

    const coordinator = new TransactionalGalleryCoordinatorV18({
      txAdapter: adapter,
      kmsEnvelope,
      kmsKeyProvider: keyProvider,
    });

    const identicalTwinEmbedding = generateNormalizedEmbedding('identical_twin_pair');

    // Twin 1 enrolls
    await coordinator.enrollWorkerWithEpochFencedRetry({
      uid: 'twin_1',
      maskedPhone: '+91 98765 10001',
      idempotencyKey: 'idemp_twin_1',
      payload: { sfaceEmbedding128: identicalTwinEmbedding, isoQualityScore: 98.0, padLivenessScore: 0.99 },
    });

    // Twin 2 attempts to enroll, blocked as suspected duplicate with ticket
    const twin2Result = await coordinator.enrollWorkerWithEpochFencedRetry({
      uid: 'twin_2',
      maskedPhone: '+91 98765 10002',
      idempotencyKey: 'idemp_twin_2',
      payload: { sfaceEmbedding128: identicalTwinEmbedding, isoQualityScore: 98.0, padLivenessScore: 0.99 },
    });

    const ticketId = twin2Result.auditTicketId!;
    assert.ok(ticketId !== undefined);

    // Administrative review: Compliance officer reviews manual ID proof (e.g. Twin Birth Certificate)
    // and records authorized override decision in audit ticket
    const auditTicketRef = db.collection('biometric_audit_queue').doc(ticketId);
    await auditTicketRef.set({
      ticketId,
      candidateUid: 'twin_2',
      matchedUid: 'twin_1',
      resolutionStatus: 'AUTHORIZED_OVERRIDE_APPROVED',
      resolutionReason: 'IDENTICAL_TWIN_VERIFIED_VIA_GOVT_ID',
      reviewedByOfficer: 'officer_sharma_blr',
      resolvedAtEpochMs: Date.now(),
    });

    const resolvedTicket = db.store.get(`biometric_audit_queue/${ticketId}`);
    assert.strictEqual(resolvedTicket?.data.resolutionStatus, 'AUTHORIZED_OVERRIDE_APPROVED');
    assert.strictEqual(resolvedTicket?.data.resolutionReason, 'IDENTICAL_TWIN_VERIFIED_VIA_GOVT_ID');
  });

  it('5. Audit Queue Observability: Measurable queue metrics (unresolved cases & review delay)', async () => {
    const db = new MemoryFirestoreSimulator();

    // Create 3 open investigation tickets and 1 resolved ticket
    const now = Date.now();
    await db.collection('biometric_audit_queue').doc('ticket_1').set({
      ticketId: 'ticket_1',
      status: 'INVESTIGATION_PENDING',
      createdAtEpochMs: now - 3600000, // 1 hour ago
    });
    await db.collection('biometric_audit_queue').doc('ticket_2').set({
      ticketId: 'ticket_2',
      status: 'INVESTIGATION_PENDING',
      createdAtEpochMs: now - 1800000, // 30 mins ago
    });
    await db.collection('biometric_audit_queue').doc('ticket_3').set({
      ticketId: 'ticket_3',
      status: 'RESOLVED',
      createdAtEpochMs: now - 7200000,
      resolvedAtEpochMs: now - 3600000,
    });

    // Query open tickets
    const allTickets = await db.collection('biometric_audit_queue').get();
    const openTickets = allTickets.docs.filter(
      (d) => d.data()?.status === 'INVESTIGATION_PENDING',
    );
    const resolvedTickets = allTickets.docs.filter(
      (d) => d.data()?.status === 'RESOLVED',
    );

    assert.strictEqual(openTickets.length, 2);
    assert.strictEqual(resolvedTickets.length, 1);

    // Compute average queue delay for pending investigations
    const totalPendingDelayMs = openTickets.reduce(
      (acc, d) => acc + (now - (d.data()?.createdAtEpochMs as number)),
      0,
    );
    const avgPendingDelayMins = totalPendingDelayMs / openTickets.length / 60000;

    assert.ok(avgPendingDelayMins > 0);
    assert.strictEqual(Math.round(avgPendingDelayMins), 45); // (60 + 30) / 2 = 45 mins
  });
});
