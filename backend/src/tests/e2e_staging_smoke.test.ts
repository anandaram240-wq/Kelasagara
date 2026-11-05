// File: backend/src/tests/e2e_staging_smoke.test.ts
// KELASAGARA V18 — Gate G-04 & G-06: Canonical SFace Gallery Integration & Security Regression Suite

import { describe, it, beforeEach } from 'node:test';
import assert from 'node:assert/strict';

import {
  BiometricPlaintextSfacePayloadV3,
  CANONICAL_SFACE_MODEL_ID,
  CANONICAL_SFACE_MODEL_VERSION,
  CANONICAL_TEMPLATE_SCHEMA_VERSION,
  CanonicalAadContext,
  CloudKmsEnvelopeService,
  LocalDevKeyProvider,
  PRODUCTION_BIOMETRIC_CALIBRATION_APPROVED,
  RELEASE_STATUS,
  SFACE_EMBEDDING_DIMENSION,
  SFACE_V3_BINARY_PAYLOAD_BYTES,
  assertValidCanonicalSfaceEmbedding,
  l2NormalizeSfaceVector,
  packSfacePayloadV3,
} from '../crypto/cloud_kms_envelope';

import {
  BiometricAuditTicketV3,
  BiometricVaultPersistenceAdapter,
  DEFAULT_1TO1_VERIFICATION_POLICY,
  DEFAULT_1TON_DUPLICATE_POLICY,
  GalleryConsistencyServiceV3,
  StoredVaultDocumentV3,
  assertNoClientSuppliedVectors,
} from '../services/gallery_consistency_service';

function createSeededPrng(seed: number): () => number {
  let state = seed >>> 0;
  return () => {
    state = (state + 0x6d2b79f5) >>> 0;
    let t = Math.imul(state ^ (state >>> 15), 1 | state);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function generateCanonicalSfaceVec128(seed: number): Float32Array {
  const rng = createSeededPrng(seed);
  const vec = new Float32Array(SFACE_EMBEDDING_DIMENSION);
  let mean = 0.0;
  for (let i = 0; i < SFACE_EMBEDDING_DIMENSION; i++) {
    const u1 = Math.max(1e-7, rng());
    const u2 = rng();
    const z = Math.sqrt(-2.0 * Math.log(u1)) * Math.cos(2.0 * Math.PI * u2);
    vec[i] = z;
    mean += z;
  }
  mean /= SFACE_EMBEDDING_DIMENSION;
  for (let i = 0; i < SFACE_EMBEDDING_DIMENSION; i++) {
    vec[i] -= mean;
  }
  return l2NormalizeSfaceVector(vec);
}

function perturbSfaceToExactCosine(
  baseVec128: Float32Array,
  targetCosine: number,
  noiseSeed: number,
): Float32Array {
  const clampedCos = Math.max(-1.0, Math.min(1.0, targetCosine));
  const randomDir = generateCanonicalSfaceVec128(noiseSeed);

  let dot = 0.0;
  for (let i = 0; i < SFACE_EMBEDDING_DIMENSION; i++) {
    dot += randomDir[i] * baseVec128[i];
  }

  const ortho = new Float32Array(SFACE_EMBEDDING_DIMENSION);
  let orthoNormSq = 0.0;
  for (let i = 0; i < SFACE_EMBEDDING_DIMENSION; i++) {
    const val = randomDir[i] - dot * baseVec128[i];
    ortho[i] = val;
    orthoNormSq += val * val;
  }

  const invOrtho = 1.0 / Math.sqrt(Math.max(orthoNormSq, 1e-12));
  const sinTheta = Math.sqrt(Math.max(0.0, 1.0 - clampedCos * clampedCos));

  const out = new Float32Array(SFACE_EMBEDDING_DIMENSION);
  for (let i = 0; i < SFACE_EMBEDDING_DIMENSION; i++) {
    out[i] = clampedCos * baseVec128[i] + sinTheta * (ortho[i] * invOrtho);
  }
  return l2NormalizeSfaceVector(out);
}

function createSfacePayload(
  seed: number,
  isoQualityScore = 90.0,
  padLivenessScore = 0.94,
): BiometricPlaintextSfacePayloadV3 {
  return {
    sfaceEmbedding128: generateCanonicalSfaceVec128(seed),
    isoQualityScore,
    padLivenessScore,
  };
}

class InMemoryCasVaultAdapter implements BiometricVaultPersistenceAdapter {
  public globalEpoch = 0;
  public readonly biometricVault = new Map<string, StoredVaultDocumentV3>();
  public readonly auditQueue: BiometricAuditTicketV3[] = [];
  public simulateEpochCommitFailure = false;
  public simulateReadFailure = false;
  public watcherSnapshotCountOnLastBump = -1;

  public async getGlobalEpoch(): Promise<number> {
    if (this.simulateReadFailure) {
      throw new Error('SIMULATED_FIRESTORE_READ_OUTAGE');
    }
    return this.globalEpoch;
  }

  public async incrementGlobalEpoch(expectedCurrentEpoch?: number): Promise<number> {
    if (this.simulateEpochCommitFailure) {
      throw new Error('SIMULATED_EPOCH_CAS_CONFLICT');
    }
    if (
      expectedCurrentEpoch !== undefined &&
      expectedCurrentEpoch >= 0 &&
      this.globalEpoch !== expectedCurrentEpoch
    ) {
      throw new Error(
        `CAS_EPOCH_MISMATCH: Expected ${expectedCurrentEpoch}, actual ${this.globalEpoch}`,
      );
    }
    this.globalEpoch += 1;
    const active = await this.fetchAllActiveTemplates();
    this.watcherSnapshotCountOnLastBump = active.length;
    return this.globalEpoch;
  }

  public async fetchAllActiveTemplates(): Promise<StoredVaultDocumentV3[]> {
    if (this.simulateReadFailure) {
      throw new Error('SIMULATED_FIRESTORE_READ_OUTAGE');
    }
    return Array.from(this.biometricVault.values()).filter(
      (doc) => doc.status !== 'ERASED',
    );
  }

  public async getVaultDocumentByUid(
    uid: string,
  ): Promise<StoredVaultDocumentV3 | null> {
    return this.biometricVault.get(uid) ?? null;
  }

  public async saveVaultDocument(doc: StoredVaultDocumentV3): Promise<void> {
    this.biometricVault.set(doc.uid, doc);
  }

  public async deleteVaultDocument(uid: string): Promise<boolean> {
    return this.biometricVault.delete(uid);
  }

  public async enqueueAuditTicket(ticket: BiometricAuditTicketV3): Promise<void> {
    this.auditQueue.push(ticket);
  }
}

describe('KELASAGARA V18 — Canonical SFace Gallery Integration & Regression Suite', () => {
  const TENANT_ID = 'karnataka-kelasagaara-staging';
  let vaultAdapter: InMemoryCasVaultAdapter;
  let kmsEnvelope: CloudKmsEnvelopeService;
  let galleryService: GalleryConsistencyServiceV3;

  beforeEach(() => {
    vaultAdapter = new InMemoryCasVaultAdapter();
    kmsEnvelope = new CloudKmsEnvelopeService(new LocalDevKeyProvider());
    galleryService = new GalleryConsistencyServiceV3(vaultAdapter, kmsEnvelope, {
      tenantId: TENANT_ID,
      maxArenaCapacity: 10000,
    });
  });

  it('1. Vector Compatibility: Accepts 128-D unit SFace vectors and rejects 512-D/256-D landmark vectors, NaN, Infinity, and unnormalized inputs', () => {
    assert.equal(PRODUCTION_BIOMETRIC_CALIBRATION_APPROVED, false);
    assert.equal(RELEASE_STATUS, 'CONTROLLED_TEST_BUILD_ONLY');

    const valid128 = generateCanonicalSfaceVec128(101);
    const checked = assertValidCanonicalSfaceEmbedding(valid128);
    assert.equal(checked.length, 128);

    // Reject 512-D Dense500LandmarkEngineV3 vector
    const landmark512 = new Float32Array(512).fill(1 / Math.sqrt(512));
    assert.throws(
      () => assertValidCanonicalSfaceEmbedding(landmark512),
      /INVALID_SFACE_DIMENSION: .* expected 128 dimensions, got 512/,
    );

    // Reject 256-D periocular landmark vector
    const landmark256 = new Float32Array(256).fill(1 / Math.sqrt(256));
    assert.throws(
      () => assertValidCanonicalSfaceEmbedding(landmark256),
      /INVALID_SFACE_DIMENSION: .* expected 128 dimensions, got 256/,
    );

    // Reject empty vector
    assert.throws(
      () => assertValidCanonicalSfaceEmbedding(new Float32Array(0)),
      /INVALID_SFACE_DIMENSION/,
    );

    // Reject NaN and Infinity
    const nanVec = new Float32Array(valid128);
    nanVec[5] = Number.NaN;
    assert.throws(
      () => assertValidCanonicalSfaceEmbedding(nanVec),
      /NON_FINITE_SFACE_VALUE/,
    );

    const infVec = new Float32Array(valid128);
    infVec[12] = Number.POSITIVE_INFINITY;
    assert.throws(
      () => assertValidCanonicalSfaceEmbedding(infVec),
      /NON_FINITE_SFACE_VALUE/,
    );

    // Reject unnormalized vector (L2 norm = 2.5)
    const unnormalized = new Float32Array(valid128).map((v) => v * 2.5);
    assert.throws(
      () => assertValidCanonicalSfaceEmbedding(unnormalized),
      /UNNORMALIZED_SFACE_VECTOR/,
    );
  });

  it('2. Decision Policy Separation: 1:1 verification uses 0.363 while 1:N uses 0.74 warning and 0.90 hard-block', async () => {
    const worker1 = createSfacePayload(201);
    const enrollRes = await galleryService.enrollWithGlobalEpochBump({
      uid: 'KLS-WKR-0001',
      maskedPhone: '******5177',
      payload: worker1,
    });
    assert.equal(enrollRes.enrolled, true);
    assert.equal(enrollRes.decisionStatus, 'CLEAN_APPROVED');
    assert.equal(packSfacePayloadV3(worker1).byteLength, SFACE_V3_BINARY_PAYLOAD_BYTES);

    // Probe with cosine = 0.45:
    // Must PASS 1:1 verification (0.45 >= 0.363), proving 1:1 does NOT accidentally use 0.74!
    const probeAt045: BiometricPlaintextSfacePayloadV3 = {
      sfaceEmbedding128: perturbSfaceToExactCosine(worker1.sfaceEmbedding128, 0.45, 901),
      isoQualityScore: 88.0,
      padLivenessScore: 0.92,
    };
    const verifyPass = await galleryService.verifyWorker1to1('KLS-WKR-0001', probeAt045);
    assert.equal(verifyPass.verified, true);
    assert.equal(verifyPass.decisionStatus, 'MATCH_CONFIRMED');
    assert.equal(verifyPass.thresholdApplied, DEFAULT_1TO1_VERIFICATION_POLICY.matchThreshold);

    // Probe with cosine = 0.30 (< 0.363): Must FAIL 1:1 verification
    const probeAt030: BiometricPlaintextSfacePayloadV3 = {
      sfaceEmbedding128: perturbSfaceToExactCosine(worker1.sfaceEmbedding128, 0.30, 902),
      isoQualityScore: 88.0,
      padLivenessScore: 0.92,
    };
    const verifyFail = await galleryService.verifyWorker1to1('KLS-WKR-0001', probeAt030);
    assert.equal(verifyFail.verified, false);
    assert.equal(verifyFail.decisionStatus, 'NON_MATCH_REJECTED');
  });

  it('3. Warning vs Hard-Block Separation: 0.74 <= score < 0.90 flags warning & audit ticket without hard rejection, while >= 0.90 blocks', async () => {
    const owner = createSfacePayload(301);
    await galleryService.enrollWithGlobalEpochBump({
      uid: 'KLS-WKR-OWNER',
      maskedPhone: '******5177',
      payload: owner,
    });

    // Candidate A: cosine = 0.80 (in warning band [0.74, 0.90))
    // Must NOT be hard-rejected; must enroll with DUPLICATE_WARNING_FLAGGED and enqueue audit ticket
    const warningCandidate: BiometricPlaintextSfacePayloadV3 = {
      sfaceEmbedding128: perturbSfaceToExactCosine(owner.sfaceEmbedding128, 0.80, 1101),
      isoQualityScore: 91.0,
      padLivenessScore: 0.95,
    };
    const warnOutcome = await galleryService.enrollWithGlobalEpochBump({
      uid: 'KLS-WKR-WARN',
      maskedPhone: '******6100',
      payload: warningCandidate,
    });
    assert.equal(warnOutcome.enrolled, true);
    assert.equal(warnOutcome.decisionStatus, 'DUPLICATE_WARNING_FLAGGED');
    assert.ok(warnOutcome.auditTicketId);
    assert.equal(vaultAdapter.auditQueue.length, 1);
    assert.equal(vaultAdapter.biometricVault.get('KLS-WKR-WARN')?.status, 'PENDING_AUDIT');

    // Candidate B: cosine = 0.94 (>= 0.90 hardBlockThreshold)
    // Must be HARD_DUPLICATE_BLOCKED and not written to vault
    const hardDupCandidate: BiometricPlaintextSfacePayloadV3 = {
      sfaceEmbedding128: perturbSfaceToExactCosine(owner.sfaceEmbedding128, 0.94, 1102),
      isoQualityScore: 91.0,
      padLivenessScore: 0.95,
    };
    const blockOutcome = await galleryService.enrollWithGlobalEpochBump({
      uid: 'KLS-WKR-BLOCKED',
      maskedPhone: '******6200',
      payload: hardDupCandidate,
    });
    assert.equal(blockOutcome.enrolled, false);
    assert.equal(blockOutcome.decisionStatus, 'HARD_DUPLICATE_BLOCKED');
    assert.equal(blockOutcome.duplicateSearch.matchedUid, 'KLS-WKR-OWNER');
    assert.equal(vaultAdapter.biometricVault.has('KLS-WKR-BLOCKED'), false);
  });

  it('4. Gallery Lifecycle: Re-enrollment, DPDPA §12 deletion, cold-start initialization, and legacy template isolation', async () => {
    const initialPayload = createSfacePayload(401);
    await galleryService.enrollWithGlobalEpochBump({
      uid: 'KLS-WKR-LIFE',
      maskedPhone: '******4010',
      payload: initialPayload,
    });

    // Duplicate enrollment of same UID without allowReEnrollment must fail
    await assert.rejects(
      async () =>
        galleryService.enrollWithGlobalEpochBump({
          uid: 'KLS-WKR-LIFE',
          maskedPhone: '******4010',
          payload: initialPayload,
          allowReEnrollment: false,
        }),
      /ALREADY_ENROLLED_ERROR/,
    );

    // Approved re-enrollment updates template in place
    const updatedPayload = createSfacePayload(402);
    const reEnrollRes = await galleryService.enrollWithGlobalEpochBump({
      uid: 'KLS-WKR-LIFE',
      maskedPhone: '******4010',
      payload: updatedPayload,
      allowReEnrollment: true,
    });
    assert.equal(reEnrollRes.enrolled, true);
    assert.equal(reEnrollRes.isReEnrollment, true);
    assert.equal(galleryService.getActiveGallerySize(), 1);

    // Inject a legacy v2_whitened document and a v3_dense512 landmark document into persistence
    const validDoc = vaultAdapter.biometricVault.get('KLS-WKR-LIFE')!;
    vaultAdapter.biometricVault.set('KLS-LEGACY-V2', {
      ...validDoc,
      uid: 'KLS-LEGACY-V2',
      modelVersion: 'kelasagara_biomatch_v2_whitened',
    });
    vaultAdapter.biometricVault.set('KLS-LEGACY-LANDMARK-512', {
      ...validDoc,
      uid: 'KLS-LEGACY-LANDMARK-512',
      modelVersion: 'kelasagara_biomatch_v3_dense512',
    });
    await vaultAdapter.incrementGlobalEpoch();

    // Cold-start instance must load only the canonical SFace template and skip incompatible templates
    const coldInstance = new GalleryConsistencyServiceV3(vaultAdapter, kmsEnvelope, {
      tenantId: TENANT_ID,
    });
    await coldInstance.ensureSynchronized();
    assert.equal(coldInstance.getActiveGallerySize(), 1);

    // DPDPA §12 Deletion removes template from vault and CoW RAM index
    const eraseRes = await coldInstance.eraseWorkerBiometrics('KLS-WKR-LIFE');
    assert.equal(eraseRes.erased, true);
    assert.equal(coldInstance.getActiveGallerySize(), 0);
  });

  it('5. Concurrency, Idempotency & Partial Persistence Failure Rollback', async () => {
    const duplicateFacePayload = createSfacePayload(501);
    const nearlyIdenticalPayload: BiometricPlaintextSfacePayloadV3 = {
      sfaceEmbedding128: perturbSfaceToExactCosine(
        duplicateFacePayload.sfaceEmbedding128,
        0.95,
        502,
      ),
      isoQualityScore: 92.0,
      padLivenessScore: 0.96,
    };

    // Submit two concurrent enrollments for the same person under different UIDs simultaneously
    const [resA, resB] = await Promise.all([
      galleryService.enrollWithGlobalEpochBump({
        uid: 'KLS-CONCURRENT-A',
        maskedPhone: '******5001',
        payload: duplicateFacePayload,
        idempotencyKey: 'idem-key-001',
      }),
      galleryService.enrollWithGlobalEpochBump({
        uid: 'KLS-CONCURRENT-B',
        maskedPhone: '******5002',
        payload: nearlyIdenticalPayload,
      }),
    ]);

    // Exactly one must succeed and the second must be HARD_DUPLICATE_BLOCKED
    assert.equal(resA.enrolled, true);
    assert.equal(resB.enrolled, false);
    assert.equal(resB.decisionStatus, 'HARD_DUPLICATE_BLOCKED');
    assert.equal(galleryService.getActiveGallerySize(), 1);

    // Retry with same idempotencyKey returns cached outcome without re-running or throwing
    const retryResA = await galleryService.enrollWithGlobalEpochBump({
      uid: 'KLS-CONCURRENT-A',
      maskedPhone: '******5001',
      payload: duplicateFacePayload,
      idempotencyKey: 'idem-key-001',
    });
    const retryResA2 = await galleryService.enrollWithGlobalEpochBump({
      uid: 'KLS-CONCURRENT-A',
      maskedPhone: '******5001',
      payload: duplicateFacePayload,
      idempotencyKey: 'idem-key-001',
    });
    assert.deepEqual(retryResA, retryResA2);

    // Simulate partial persistence failure (epoch CAS failure after saveVaultDocument)
    vaultAdapter.simulateEpochCommitFailure = true;
    await assert.rejects(
      async () =>
        galleryService.enrollWithGlobalEpochBump({
          uid: 'KLS-ROLLBACK-USER',
          maskedPhone: '******5099',
          payload: createSfacePayload(599),
        }),
      /EPOCH_COMMIT_FAILURE_ROLLED_BACK/,
    );
    // Document must have been rolled back from vault
    assert.equal(vaultAdapter.biometricVault.has('KLS-ROLLBACK-USER'), false);
    vaultAdapter.simulateEpochCommitFailure = false;
  });

  it('6. Security & Fail-Closed Semantics: Rejects client-supplied vectors and fails closed on KMS/DB errors', async () => {
    // Client attempts to submit a precomputed vector in request body
    assert.throws(
      () =>
        assertNoClientSuppliedVectors({
          uid: 'KLS-ATTACKER',
          captureMetadata: {
            sfaceEmbedding128: [0.1, 0.2, 0.3],
          },
        }),
      /SECURITY_VIOLATION_CLIENT_VECTOR_FORBIDDEN/,
    );

    // Simulate Firestore outage: must fail closed and never approve enrollment or verification
    vaultAdapter.simulateReadFailure = true;
    await assert.rejects(
      async () =>
        galleryService.enrollWithGlobalEpochBump({
          uid: 'KLS-FAIL-CLOSED',
          maskedPhone: '******9000',
          payload: createSfacePayload(601),
        }),
      /GALLERY_UNAVAILABLE_FAIL_CLOSED/,
    );
    await assert.rejects(
      async () =>
        galleryService.verifyWorker1to1('KLS-FAIL-CLOSED', createSfacePayload(601)),
      /GALLERY_UNAVAILABLE_FAIL_CLOSED/,
    );
    vaultAdapter.simulateReadFailure = false;

    // Verify KMS cross-UID AAD tampering fails closed
    const validPayload = createSfacePayload(602);
    const aad: CanonicalAadContext = {
      uid: 'KLS-VALID-USER',
      modelVersion: CANONICAL_SFACE_MODEL_VERSION,
      templateSchemaVersion: CANONICAL_TEMPLATE_SCHEMA_VERSION,
      tenantId: TENANT_ID,
      purpose: 'BIOMETRIC_VAULT_SFACE_V3',
    };
    const env = await kmsEnvelope.sealTemplateV3(validPayload, aad);
    await assert.rejects(
      async () =>
        kmsEnvelope.unsealTemplateV3(env, { ...aad, uid: 'KLS-SPOOFED-UID' }),
      /Unsupported state or unable to authenticate data/,
    );
  });
});

