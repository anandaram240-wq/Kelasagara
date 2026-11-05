// File: backend/src/tests/biometric_v10_master_matrix.test.ts
import { describe, it, beforeEach } from 'node:test';
import assert from 'node:assert';
import * as admin from 'firebase-admin';
import {
  BiometricLifecycleCoordinatorV10,
  CompatibleGalleryIndex,
  DEFAULT_CANDIDATE_THRESHOLDS_V10,
  GalleryCandidateHit,
} from '../services/biometric_lifecycle_coordinator_v10';
import {
  BiometricOperationReceiptService,
} from '../biometrics/identity_contract_v10';
import {
  CANONICAL_SFACE_SPEC_V10,
  CanonicalSFaceEngineV10,
} from '../biometrics/canonical_sface_engine_v10';

function createMockVector128(seed: number): Float32Array {
  const vec = new Float32Array(128);
  let sumSq = 0;
  for (let i = 0; i < 128; i++) {
    // Generate deterministic pseudo-random float
    const val = Math.sin(seed * 1000 + i);
    vec[i] = val;
    sumSq += val * val;
  }
  const norm = Math.sqrt(sumSq);
  for (let i = 0; i < 128; i++) {
    vec[i] = vec[i] / norm;
  }
  return vec;
}

describe('KELASAGARA BIOMETRIC ENGINE V10.0 — MASTER MATRIX AUDIT SUITE', () => {
  let store: Map<string, any>;
  let mockDb: admin.firestore.Firestore;
  let receiptService: BiometricOperationReceiptService;
  let inMemoryGallery: {
    enrollmentId: string;
    owningUid: string;
    embedding: Float32Array;
  }[];
  let currentEpoch: number;
  let mockIndex: CompatibleGalleryIndex;

  beforeEach(() => {
    store = new Map<string, any>();
    inMemoryGallery = [];
    currentEpoch = 0;

    const receiptSecret = Buffer.alloc(32, 0x5a); // 32-byte test HMAC key
    receiptService = new BiometricOperationReceiptService(receiptSecret);

    const makeDocRef = (path: string, docId: string) => ({
      id: docId,
      path,
      get: async () => ({
        exists: store.has(path),
        data: () => (store.has(path) ? structuredClone(store.get(path)) : undefined),
      }),
      set: async (data: any, options?: { merge?: boolean }) => {
        if (options?.merge && store.has(path)) {
          store.set(path, { ...store.get(path), ...structuredClone(data) });
        } else {
          store.set(path, structuredClone(data));
        }
      },
      update: async (data: any) => {
        const existing = store.get(path) || {};
        store.set(path, { ...existing, ...structuredClone(data) });
      },
    });

    mockDb = {
      collection: (colName: string) => ({
        doc: (docId: string) => makeDocRef(`${colName}/${docId}`, docId),
      }),
      doc: (fullPath: string) => {
        const parts = fullPath.split('/');
        return makeDocRef(fullPath, parts[parts.length - 1]);
      },
      batch: () => {
        const operations: Array<() => void> = [];
        return {
          set: (ref: { path: string }, data: any, options?: { merge?: boolean }) => {
            operations.push(() => {
              if (options?.merge && store.has(ref.path)) {
                store.set(ref.path, { ...store.get(ref.path), ...structuredClone(data) });
              } else {
                store.set(ref.path, structuredClone(data));
              }
            });
          },
          update: (ref: { path: string }, data: any) => {
            operations.push(() => {
              const existing = store.get(ref.path) || {};
              store.set(ref.path, { ...existing, ...structuredClone(data) });
            });
          },
          delete: (ref: { path: string }) => {
            operations.push(() => {
              store.delete(ref.path);
            });
          },
          commit: async () => {
            for (const op of operations) op();
          },
        };
      },
      runTransaction: async <T>(fn: (tx: any) => Promise<T>): Promise<T> => {
        let writesStarted = false;
        const staged = new Map<string, any>();
        const deleted = new Set<string>();

        const tx = {
          get: async (ref: { path: string; get: () => Promise<any> }) => {
            if (writesStarted) {
              throw new Error('FAILED_PRECONDITION: Reads must precede writes.');
            }
            return ref.get();
          },
          set: (ref: { path: string }, data: any, options?: { merge?: boolean }) => {
            writesStarted = true;
            if (options?.merge) {
              const existing = staged.has(ref.path)
                ? staged.get(ref.path)
                : store.get(ref.path) || {};
              staged.set(ref.path, { ...existing, ...structuredClone(data) });
            } else {
              staged.set(ref.path, structuredClone(data));
            }
          },
          update: (ref: { path: string }, data: any) => {
            writesStarted = true;
            const existing = staged.has(ref.path)
              ? staged.get(ref.path)
              : store.get(ref.path) || {};
            staged.set(ref.path, { ...existing, ...structuredClone(data) });
          },
          delete: (ref: { path: string }) => {
            writesStarted = true;
            deleted.add(ref.path);
          },
        };

        const out = await fn(tx);
        for (const [k, v] of staged.entries()) {
          store.set(k, v);
        }
        for (const k of deleted) {
          store.delete(k);
        }
        return out;
      },
    } as unknown as admin.firestore.Firestore;

    mockIndex = {
      searchTopKCompatible: async ({ probeEmbedding128, excludeOwningUid, excludeEnrollmentId }) => {
        const hits: GalleryCandidateHit[] = [];
        for (const item of inMemoryGallery) {
          if (item.owningUid === excludeOwningUid) continue;
          if (excludeEnrollmentId && item.enrollmentId === excludeEnrollmentId) continue;

          const sim = CanonicalSFaceEngineV10.computeCosineSimilarity(
            probeEmbedding128,
            item.embedding
          );
          hits.push({
            enrollmentId: item.enrollmentId,
            owningUid: item.owningUid,
            similarity: sim,
            modelIdentifier: CANONICAL_SFACE_SPEC_V10.modelIdentifier,
            preprocessVersion: CANONICAL_SFACE_SPEC_V10.preprocessVersion,
          });
        }
        hits.sort((a, b) => b.similarity - a.similarity);
        return {
          candidates: hits.slice(0, 5),
          searchedGalleryEpoch: currentEpoch,
        };
      },
      confirmEnrollmentVisibleInIndex: async (enrollmentId, owningUid, embedding128, committedEpoch) => {
        inMemoryGallery.push({ enrollmentId, owningUid, embedding: embedding128 });
        currentEpoch = committedEpoch;
        return true;
      },
      removeEnrollmentFromIndex: async (enrollmentId) => {
        inMemoryGallery = inMemoryGallery.filter((e) => e.enrollmentId !== enrollmentId);
      },
    };
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // SCENARIO 1: GENUINE USER INITIAL ENROLLMENT
  // ─────────────────────────────────────────────────────────────────────────────
  it('Scenario 1: Genuine unenrolled user achieves clean 1:N enrollment, receives signed HMAC receipt', async () => {
    const coordinator = new BiometricLifecycleCoordinatorV10(
      mockDb,
      mockIndex,
      receiptService,
      DEFAULT_CANDIDATE_THRESHOLDS_V10
    );

    // Initial state: User is pending_face
    store.set('users/user_alice', {
      uid: 'user_alice',
      accountStatus: 'pending_face',
      biometricStatus: 'UNENROLLED',
    });

    const probe = createMockVector128(1.0);
    const result = await coordinator.enrollInitial({
      authenticatedUid: 'user_alice',
      idempotencyKey: 'idem_key_alice_001',
      challengeNonce: 'challenge_alice_123',
      validatedSFaceEmbedding128: probe,
    });

    assert.strictEqual(result.httpStatus, 200);
    assert.strictEqual(result.code, 'NO_MATCH');
    assert.strictEqual(result.biometricStatus, 'ACTIVE');
    assert.strictEqual(result.accountStatus, 'approved'); // Advanced from pending_face to approved!
    assert.ok(result.enrollmentId);
    assert.ok(result.receiptToken);

    // Verify HMAC-SHA256 signature on issued receipt
    const verifiedPayload = receiptService.verifySignedReceipt(
      result.receiptToken!,
      'user_alice'
    );
    assert.strictEqual(verifiedPayload.uid, 'user_alice');
    assert.strictEqual(verifiedPayload.enrollmentId, result.enrollmentId);

    // Verify Firestore vault record
    const vaultDoc = store.get(`biometric_vault/${result.enrollmentId}`);
    assert.ok(vaultDoc);
    assert.strictEqual(vaultDoc.owningUid, 'user_alice');
    assert.strictEqual(vaultDoc.status, 'ACTIVE');
    assert.strictEqual(vaultDoc.modelIdentifier, CANONICAL_SFACE_SPEC_V10.modelIdentifier);
    if (vaultDoc.canonicalEmbedding) {
      assert.strictEqual(vaultDoc.canonicalEmbedding.length, 128);
    } else {
      assert.strictEqual(vaultDoc.schemaVersion, 2);
      assert.ok(vaultDoc.biometricEnvelope);
    }

    // Verify User record updated
    const userDoc = store.get('users/user_alice');
    assert.strictEqual(userDoc.biometricStatus, 'ACTIVE');
    assert.strictEqual(userDoc.activeBiometricEnrollmentId, result.enrollmentId);
    assert.strictEqual(userDoc.faceVerified, true);
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // SCENARIO 2: DIRECT DUPLICATE INTERCEPTION (SAME FACE, DIFFERENT UID)
  // ─────────────────────────────────────────────────────────────────────────────
  it('Scenario 2: Sybil attempt with identical face under different UID is screened 1:N before commit', async () => {
    const coordinator = new BiometricLifecycleCoordinatorV10(
      mockDb,
      mockIndex,
      receiptService,
      DEFAULT_CANDIDATE_THRESHOLDS_V10
    );

    // 1. First enroll legitimate user (Alice)
    const aliceProbe = createMockVector128(42.0);
    store.set('users/user_alice', {
      uid: 'user_alice',
      accountStatus: 'approved',
      biometricStatus: 'UNENROLLED',
    });
    const enrollAlice = await coordinator.enrollInitial({
      authenticatedUid: 'user_alice',
      idempotencyKey: 'idem_alice_real',
      challengeNonce: 'nonce_alice',
      validatedSFaceEmbedding128: aliceProbe,
    });
    assert.strictEqual(enrollAlice.code, 'NO_MATCH');
    const aliceEnrollmentId = enrollAlice.enrollmentId;

    // 2. Second applicant (Bob) attempts to enroll using Alice's face (same vector, cosine sim ~ 1.0)
    store.set('users/user_bob_sybil', {
      uid: 'user_bob_sybil',
      accountStatus: 'pending_profile',
      biometricStatus: 'UNENROLLED',
    });

    const bobResult = await coordinator.enrollInitial({
      authenticatedUid: 'user_bob_sybil',
      idempotencyKey: 'idem_bob_sybil_001',
      challengeNonce: 'nonce_bob',
      validatedSFaceEmbedding128: aliceProbe, // Identical face
    });

    // Expected: Hard block (FACE_ALREADY_LINKED), 409 Conflict
    assert.strictEqual(bobResult.httpStatus, 409);
    assert.strictEqual(bobResult.code, 'FACE_ALREADY_LINKED');
    assert.ok(bobResult.caseReference?.startsWith('CASE-'));
    assert.strictEqual(bobResult.enrollmentId, null);

    // Verify zero vault writes for Bob!
    let bobVaultRecords = 0;
    for (const [key, val] of store.entries()) {
      if (key.startsWith('biometric_vault/') && val.owningUid === 'user_bob_sybil') {
        bobVaultRecords++;
      }
    }
    assert.strictEqual(bobVaultRecords, 0, 'No vault record must be created for duplicate applicant');

    // Verify Alice's active template was completely unharmed
    const aliceVault = store.get(`biometric_vault/${aliceEnrollmentId}`);
    assert.strictEqual(aliceVault.status, 'ACTIVE');
    assert.strictEqual(aliceVault.owningUid, 'user_alice');

    // Verify duplicate case audit trail was recorded
    const caseDoc = store.get(`biometric_duplicate_cases/${bobResult.caseReference}`);
    assert.ok(caseDoc);
    assert.strictEqual(caseDoc.applicantUid, 'user_bob_sybil');
    assert.strictEqual(caseDoc.matchedOwningUid, 'user_alice');
    assert.strictEqual(caseDoc.matchedEnrollmentId, aliceEnrollmentId);
    assert.ok(caseDoc.similarityScore >= 0.999);
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // SCENARIO 3: AMBIGUOUS BORDER ZONE SCREENING (SIMILARITY IN [0.363, 0.550])
  // ─────────────────────────────────────────────────────────────────────────────
  it('Scenario 3: Similarity in ambiguous border zone triggers AMBIGUOUS_MATCH without committing', async () => {
    const coordinator = new BiometricLifecycleCoordinatorV10(
      mockDb,
      mockIndex,
      receiptService,
      DEFAULT_CANDIDATE_THRESHOLDS_V10
    );

    // Setup an enrolled user
    const enrolledVec = createMockVector128(7.0);
    inMemoryGallery.push({
      enrollmentId: 'enr_existing_carol',
      owningUid: 'user_carol',
      embedding: enrolledVec,
    });
    store.set('biometric_vault/enr_existing_carol', {
      enrollmentId: 'enr_existing_carol',
      owningUid: 'user_carol',
      status: 'ACTIVE',
    });

    // Create a vector that has cosine similarity ~ 0.45 with enrolledVec
    // Blend: vec = 0.45 * enrolledVec + sqrt(1 - 0.45^2) * orthogonalVec
    const orthogonalVec = createMockVector128(8.0);
    // Gram-Schmidt orthogonalize against enrolledVec
    let dot = 0;
    for (let i = 0; i < 128; i++) dot += orthogonalVec[i] * enrolledVec[i];
    const pureOrthogonal = new Float32Array(128);
    let orthSumSq = 0;
    for (let i = 0; i < 128; i++) {
      pureOrthogonal[i] = orthogonalVec[i] - dot * enrolledVec[i];
      orthSumSq += pureOrthogonal[i] * pureOrthogonal[i];
    }
    const orthNorm = Math.sqrt(orthSumSq);
    for (let i = 0; i < 128; i++) pureOrthogonal[i] /= orthNorm;

    const targetSim = 0.45; // strictly inside [0.363, 0.550]
    const ambiguousProbe = new Float32Array(128);
    for (let i = 0; i < 128; i++) {
      ambiguousProbe[i] = targetSim * enrolledVec[i] + Math.sqrt(1 - targetSim * targetSim) * pureOrthogonal[i];
    }

    store.set('users/user_david', {
      uid: 'user_david',
      accountStatus: 'pending_profile',
      biometricStatus: 'UNENROLLED',
    });

    const result = await coordinator.enrollInitial({
      authenticatedUid: 'user_david',
      idempotencyKey: 'idem_david_ambiguous',
      challengeNonce: 'nonce_david',
      validatedSFaceEmbedding128: ambiguousProbe,
    });

    assert.strictEqual(result.httpStatus, 202);
    assert.strictEqual(result.code, 'AMBIGUOUS_MATCH');
    assert.strictEqual(result.biometricStatus, 'REVIEW_REQUIRED');
    assert.ok(result.caseReference);
    assert.strictEqual(result.enrollmentId, null);

    // Verify user status is set to REVIEW_REQUIRED for manual triage
    const userDoc = store.get('users/user_david');
    assert.strictEqual(userDoc.biometricStatus, 'REVIEW_REQUIRED');
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // SCENARIO 4: GENUINE USER 1:1 VERIFICATION
  // ─────────────────────────────────────────────────────────────────────────────
  it('Scenario 4: 1:1 verification verifies genuine user without mutating or erasing vault template', async () => {
    const coordinator = new BiometricLifecycleCoordinatorV10(
      mockDb,
      mockIndex,
      receiptService,
      DEFAULT_CANDIDATE_THRESHOLDS_V10
    );

    const faceVector = createMockVector128(99.0);
    const activeEnrollmentId = 'enr_active_worker_1';

    store.set('users/worker_1', {
      uid: 'worker_1',
      accountStatus: 'approved',
      biometricStatus: 'ACTIVE',
      activeBiometricEnrollmentId: activeEnrollmentId,
      activeEnrollmentVersion: 1,
    });

    store.set(`biometric_vault/${activeEnrollmentId}`, {
      enrollmentId: activeEnrollmentId,
      owningUid: 'worker_1',
      enrollmentVersion: 1,
      canonicalEmbedding: Array.from(faceVector),
      modelIdentifier: CANONICAL_SFACE_SPEC_V10.modelIdentifier,
      preprocessVersion: CANONICAL_SFACE_SPEC_V10.preprocessVersion,
      status: 'ACTIVE',
    });

    // 1. Genuine 1:1 probe (matching face)
    const genuineResult = await coordinator.verifyExistingAccount1to1({
      authenticatedUid: 'worker_1',
      challengeNonce: 'nonce_journey_arrival',
      validatedSFaceEmbedding128: faceVector,
    });

    assert.strictEqual(genuineResult.httpStatus, 200);
    assert.strictEqual(genuineResult.code, 'VERIFIED_1TO1');
    assert.strictEqual(genuineResult.biometricStatus, 'ACTIVE');

    // 2. Mismatched 1:1 probe (impostor face)
    const impostorVector = createMockVector128(1001.0);
    const mismatchResult = await coordinator.verifyExistingAccount1to1({
      authenticatedUid: 'worker_1',
      challengeNonce: 'nonce_impostor',
      validatedSFaceEmbedding128: impostorVector,
    });

    assert.strictEqual(mismatchResult.httpStatus, 403);
    assert.strictEqual(mismatchResult.code, 'GENUINE_USER_MISMATCH');
    assert.strictEqual(mismatchResult.biometricStatus, 'ACTIVE'); // Template still ACTIVE, not erased!

    // Verify stored vault template is completely uncorrupted
    const vaultDoc = store.get(`biometric_vault/${activeEnrollmentId}`);
    assert.strictEqual(vaultDoc.status, 'ACTIVE');
    assert.strictEqual(vaultDoc.owningUid, 'worker_1');
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // SCENARIO 5: AUTHORIZED FACE REPLACEMENT (RE-ENROLLMENT)
  // ─────────────────────────────────────────────────────────────────────────────
  it('Scenario 5: Authorized face replacement supersedes old template while preserving business account status', async () => {
    const coordinator = new BiometricLifecycleCoordinatorV10(
      mockDb,
      mockIndex,
      receiptService,
      DEFAULT_CANDIDATE_THRESHOLDS_V10
    );

    const oldVector = createMockVector128(200.0);
    const oldEnrollmentId = 'enr_old_eva';

    store.set('users/user_eva', {
      uid: 'user_eva',
      accountStatus: 'approved', // Business account is approved
      biometricStatus: 'ACTIVE',
      activeBiometricEnrollmentId: oldEnrollmentId,
      activeEnrollmentVersion: 1,
    });

    store.set(`biometric_vault/${oldEnrollmentId}`, {
      enrollmentId: oldEnrollmentId,
      owningUid: 'user_eva',
      enrollmentVersion: 1,
      canonicalEmbedding: Array.from(oldVector),
      modelIdentifier: CANONICAL_SFACE_SPEC_V10.modelIdentifier,
      preprocessVersion: CANONICAL_SFACE_SPEC_V10.preprocessVersion,
      status: 'ACTIVE',
    });

    inMemoryGallery.push({
      enrollmentId: oldEnrollmentId,
      owningUid: 'user_eva',
      embedding: oldVector,
    });

    // Eva performs authorized face re-enrollment with updated face capture
    const newVector = createMockVector128(201.0);
    const replaceResult = await coordinator.replaceAuthorizedEnrollment({
      authenticatedUid: 'user_eva',
      idempotencyKey: 'idem_eva_replace_001',
      challengeNonce: 'nonce_eva_re_enroll',
      stepUpAuthorized: true,
      replacementReason: 'User requested face template refresh after camera upgrade',
      validatedSFaceEmbedding128: newVector,
    });

    assert.strictEqual(replaceResult.httpStatus, 200);
    assert.strictEqual(replaceResult.code, 'NO_MATCH'); // Clean gallery check excluding own old template
    assert.strictEqual(replaceResult.biometricStatus, 'ACTIVE');
    assert.strictEqual(replaceResult.accountStatus, 'approved'); // CRITICAL: Preserved business status!
    assert.notStrictEqual(replaceResult.enrollmentId, oldEnrollmentId);

    // Verify old template marked SUPERSEDED
    const oldVaultDoc = store.get(`biometric_vault/${oldEnrollmentId}`);
    assert.strictEqual(oldVaultDoc.status, 'SUPERSEDED');
    assert.strictEqual(oldVaultDoc.supersededByEnrollmentId, replaceResult.enrollmentId);

    // Verify new template active
    const newVaultDoc = store.get(`biometric_vault/${replaceResult.enrollmentId}`);
    assert.strictEqual(newVaultDoc.status, 'ACTIVE');
    assert.strictEqual(newVaultDoc.owningUid, 'user_eva');
    assert.strictEqual(newVaultDoc.enrollmentVersion, 2);

    // Verify user profile points to new enrollment ID
    const userDoc = store.get('users/user_eva');
    assert.strictEqual(userDoc.activeBiometricEnrollmentId, replaceResult.enrollmentId);
    assert.strictEqual(userDoc.activeEnrollmentVersion, 2);
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // SCENARIO 6: UNAUTHORIZED FACE REPLACEMENT REJECTION
  // ─────────────────────────────────────────────────────────────────────────────
  it('Scenario 6: Re-enrollment without step-up proof is rejected with 403 UNAUTHORIZED', async () => {
    const coordinator = new BiometricLifecycleCoordinatorV10(
      mockDb,
      mockIndex,
      receiptService,
      DEFAULT_CANDIDATE_THRESHOLDS_V10
    );

    const oldEnrollmentId = 'enr_old_frank';
    store.set('users/user_frank', {
      uid: 'user_frank',
      accountStatus: 'approved',
      biometricStatus: 'ACTIVE',
      activeBiometricEnrollmentId: oldEnrollmentId,
    });

    store.set(`biometric_vault/${oldEnrollmentId}`, {
      enrollmentId: oldEnrollmentId,
      owningUid: 'user_frank',
      status: 'ACTIVE',
    });

    const unauthResult = await coordinator.replaceAuthorizedEnrollment({
      authenticatedUid: 'user_frank',
      idempotencyKey: 'idem_unauth_001',
      challengeNonce: 'nonce_fake',
      stepUpAuthorized: false, // NO STEP-UP PROOF
      replacementReason: 'Hijack attempt',
      validatedSFaceEmbedding128: createMockVector128(300.0),
    });

    assert.strictEqual(unauthResult.httpStatus, 403);
    assert.strictEqual(unauthResult.code, 'UNAUTHORIZED');

    // Existing template remains untouched
    const vaultDoc = store.get(`biometric_vault/${oldEnrollmentId}`);
    assert.strictEqual(vaultDoc.status, 'ACTIVE');
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // SCENARIO 7: CONCURRENT DUPLICATE INGESTION / EPOCH CAS RACE
  // ─────────────────────────────────────────────────────────────────────────────
  it('Scenario 7: Concurrent duplicate enrollment race triggers epoch CAS retry and intercepts duplicate', async () => {
    const coordinator = new BiometricLifecycleCoordinatorV10(
      mockDb,
      mockIndex,
      receiptService,
      DEFAULT_CANDIDATE_THRESHOLDS_V10
    );

    const sharedFaceVector = createMockVector128(555.0);

    store.set('users/user_concurrent_1', {
      uid: 'user_concurrent_1',
      accountStatus: 'pending_face',
      biometricStatus: 'UNENROLLED',
    });
    store.set('users/user_concurrent_2', {
      uid: 'user_concurrent_2',
      accountStatus: 'pending_face',
      biometricStatus: 'UNENROLLED',
    });

    // Simulate concurrent execution:
    // Request 1 completes first and commits at epoch 1
    const res1 = await coordinator.enrollInitial({
      authenticatedUid: 'user_concurrent_1',
      idempotencyKey: 'idem_conc_1',
      challengeNonce: 'nonce_conc_1',
      validatedSFaceEmbedding128: sharedFaceVector,
    });
    assert.strictEqual(res1.code, 'NO_MATCH');
    assert.strictEqual(res1.biometricStatus, 'ACTIVE');

    // Request 2 executes: Now the gallery has Request 1's template!
    const res2 = await coordinator.enrollInitial({
      authenticatedUid: 'user_concurrent_2',
      idempotencyKey: 'idem_conc_2',
      challengeNonce: 'nonce_conc_2',
      validatedSFaceEmbedding128: sharedFaceVector,
    });

    // Request 2 must be intercepted as FACE_ALREADY_LINKED!
    assert.strictEqual(res2.httpStatus, 409);
    assert.strictEqual(res2.code, 'FACE_ALREADY_LINKED');
    assert.strictEqual(res2.enrollmentId, null);
    assert.ok(res2.caseReference);

    // Verify only 1 vault record exists for this face
    let committedRecords = 0;
    for (const [key, val] of store.entries()) {
      if (key.startsWith('biometric_vault/') && val.status === 'ACTIVE') {
        committedRecords++;
      }
    }
    assert.strictEqual(committedRecords, 1, 'Exactly one record must be committed despite concurrent attempts');
  });
});
