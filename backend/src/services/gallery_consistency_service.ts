// File: backend/src/services/gallery_consistency_service.ts
// KELASAGARA V18 — Gate G-04: Canonical SFace Gallery Consistency, Policy Separation & Security Service
// Release Status: CONTROLLED_TEST_BUILD_ONLY | productionBiometricCalibrationApproved = false

import {
  BiometricPlaintextSfacePayloadV3,
  CANONICAL_SFACE_MODEL_ID,
  CANONICAL_SFACE_MODEL_VERSION,
  CANONICAL_TEMPLATE_SCHEMA_VERSION,
  CanonicalAadContext,
  CloudKmsEnvelopeService,
  EncryptedBiometricEnvelopeV3,
  PRODUCTION_BIOMETRIC_CALIBRATION_APPROVED,
  RELEASE_STATUS,
  SFACE_EMBEDDING_DIMENSION,
  assertValidCanonicalSfaceEmbedding,
} from '../crypto/cloud_kms_envelope';
import {
  DuplicateCandidateMatchV3,
  EnrolledWorkerSfaceRecordV3,
  HighSpeedBiometricIndexV3,
} from './hnsw_biometric_matcher_v3';

export {
  DuplicateCandidateMatchV3,
  EnrolledWorkerSfaceRecordV3,
  HighSpeedBiometricIndexV3,
};

export interface Verification1to1PolicyConfig {
  readonly policyId: 'SFACE_1TO1_VERIFICATION_POLICY_V18';
  readonly matchThreshold: number; // Historical candidate: 0.363
  readonly minIsoQualityScore: number;
  readonly minPadLivenessScore: number;
}

export interface DuplicateScreening1toNPolicyConfig {
  readonly policyId: 'SFACE_1TON_DUPLICATE_POLICY_V18';
  readonly warningThreshold: number; // Historical candidate: 0.74
  readonly hardBlockThreshold: number; // Historical candidate: 0.90
  readonly minIsoQualityScore: number;
  readonly minPadLivenessScore: number;
}

export const DEFAULT_1TO1_VERIFICATION_POLICY: Verification1to1PolicyConfig = {
  policyId: 'SFACE_1TO1_VERIFICATION_POLICY_V18',
  matchThreshold: 0.363,
  minIsoQualityScore: 45.0,
  minPadLivenessScore: 0.50,
} as const;

export const DEFAULT_1TON_DUPLICATE_POLICY: DuplicateScreening1toNPolicyConfig = {
  policyId: 'SFACE_1TON_DUPLICATE_POLICY_V18',
  warningThreshold: 0.74,
  hardBlockThreshold: 0.90,
  minIsoQualityScore: 50.0,
  minPadLivenessScore: 0.55,
} as const;

export type DuplicateScreeningDecisionStatus =
  | 'CLEAN_APPROVED'
  | 'DUPLICATE_WARNING_FLAGGED'
  | 'HARD_DUPLICATE_BLOCKED';

export type Verification1to1DecisionStatus =
  | 'MATCH_CONFIRMED'
  | 'NON_MATCH_REJECTED'
  | 'CLAIMANT_TEMPLATE_NOT_FOUND'
  | 'QUALITY_OR_PAD_REJECTED';

export interface StoredVaultDocumentV3 {
  readonly uid: string;
  readonly tenantId: string;
  readonly maskedPhone: string;
  readonly modelId: string;
  readonly modelVersion: string;
  readonly templateSchemaVersion: number;
  readonly status: 'ACTIVE' | 'PENDING_AUDIT' | 'ERASED';
  readonly envelope: EncryptedBiometricEnvelopeV3;
  readonly idempotencyKey?: string;
  readonly updatedAtEpochMs: number;
}

export interface BiometricAuditTicketV3 {
  readonly ticketId: string;
  readonly candidateUid: string;
  readonly matchedUid: string;
  readonly matchedMaskedPhone: string;
  readonly cosineSimilarity: number;
  readonly policyId: string;
  readonly createdAtEpochMs: number;
}

export interface BiometricVaultPersistenceAdapter {
  getGlobalEpoch(): Promise<number>;
  incrementGlobalEpoch(expectedCurrentEpoch?: number): Promise<number>;
  fetchAllActiveTemplates(): Promise<StoredVaultDocumentV3[]>;
  getVaultDocumentByUid(uid: string): Promise<StoredVaultDocumentV3 | null>;
  saveVaultDocument(doc: StoredVaultDocumentV3): Promise<void>;
  deleteVaultDocument(uid: string): Promise<boolean>;
  enqueueAuditTicket(ticket: BiometricAuditTicketV3): Promise<void>;
}

/**
 * Authoritative server-side SFace inference interface.
 * Converts raw aligned image bytes into a canonical 128-D L2-normalized SFace vector on the backend.
 */
export interface AuthoritativeSfaceInferenceService {
  readonly modelId: typeof CANONICAL_SFACE_MODEL_ID;
  readonly modelVersion: typeof CANONICAL_SFACE_MODEL_VERSION;
  extractCanonicalSfaceFromImage(
    imageBytes: Uint8Array,
    captureContext: { readonly uid: string; readonly sessionNonce: string },
  ): Promise<BiometricPlaintextSfacePayloadV3>;
}

export interface EnrollWorkerOutcomeV3 {
  readonly enrolled: boolean;
  readonly isReEnrollment: boolean;
  readonly decisionStatus: DuplicateScreeningDecisionStatus;
  readonly policyApplied: string;
  readonly globalEpoch: number;
  readonly duplicateSearch: DuplicateCandidateMatchV3;
  readonly auditTicketId?: string;
  readonly releaseStatus: typeof RELEASE_STATUS;
  readonly calibrationApproved: typeof PRODUCTION_BIOMETRIC_CALIBRATION_APPROVED;
}

export interface Verify1to1OutcomeV3 {
  readonly verified: boolean;
  readonly decisionStatus: Verification1to1DecisionStatus;
  readonly policyApplied: string;
  readonly cosineSimilarity: number | null;
  readonly thresholdApplied: number;
}

const PROHIBITED_CLIENT_VECTOR_KEYS = new Set<string>([
  'embedding',
  'embedding128',
  'sfaceembedding',
  'sfaceembedding128',
  'fullembedding512',
  'periocularembedding256',
  'embedding512',
  'periocular256',
  'vector',
  'biometricvector',
  'rawtemplate',
  'templatebytes',
  'wrappeddekbase64',
  'ciphertextbase64',
  'isverified',
  'verificationstatus',
]);

/**
 * Security Guard (Phase 4): Rejects any external client request body that attempts to supply
 * precomputed biometric vectors, raw templates, or self-asserted verification flags.
 */
export function assertNoClientSuppliedVectors(
  clientRequestPayload: unknown,
  pathContext = '$',
): void {
  if (clientRequestPayload === null || typeof clientRequestPayload !== 'object') {
    return;
  }
  if (Array.isArray(clientRequestPayload)) {
    for (let i = 0; i < clientRequestPayload.length; i++) {
      assertNoClientSuppliedVectors(clientRequestPayload[i], `${pathContext}[${i}]`);
    }
    return;
  }

  const record = clientRequestPayload as Record<string, unknown>;
  for (const key of Object.keys(record)) {
    const normalized = key.replace(/[\s_-]/g, '').toLowerCase();
    if (PROHIBITED_CLIENT_VECTOR_KEYS.has(normalized)) {
      throw new Error(
        `SECURITY_VIOLATION_CLIENT_VECTOR_FORBIDDEN: Client payload at ${pathContext}.${key} attempted to submit a prohibited vector or status field.`,
      );
    }
    assertNoClientSuppliedVectors(record[key], `${pathContext}.${key}`);
  }
}

export class GalleryConsistencyServiceV3 {
  private readonly persistence: BiometricVaultPersistenceAdapter;
  private readonly kmsEnvelope: CloudKmsEnvelopeService;
  private readonly tenantId: string;
  private readonly maxArenaCapacity: number;
  private readonly verifyPolicy: Verification1to1PolicyConfig;
  private readonly duplicatePolicy: DuplicateScreening1toNPolicyConfig;
  private readonly maxStaleAgeMs: number;

  private activeIndex: HighSpeedBiometricIndexV3;
  private localEpoch = -1;
  private lastSyncedAtMs = 0;
  private isIndexHealthy = false;
  private reconcileInFlight: Promise<void> | null = null;
  private mutationQueue: Promise<unknown> = Promise.resolve();
  private readonly processedIdempotencyKeys = new Map<string, EnrollWorkerOutcomeV3>();

  constructor(
    persistence: BiometricVaultPersistenceAdapter,
    kmsEnvelope: CloudKmsEnvelopeService,
    options?: {
      tenantId?: string;
      maxArenaCapacity?: number;
      verify1to1Policy?: Verification1to1PolicyConfig;
      duplicate1toNPolicy?: DuplicateScreening1toNPolicyConfig;
      maxStaleAgeMs?: number;
    },
  ) {
    this.persistence = persistence;
    this.kmsEnvelope = kmsEnvelope;
    this.tenantId = options?.tenantId ?? 'karnataka-kelasagaara-prod';
    this.maxArenaCapacity = options?.maxArenaCapacity ?? 50000;
    this.verifyPolicy = options?.verify1to1Policy ?? DEFAULT_1TO1_VERIFICATION_POLICY;
    this.duplicatePolicy = options?.duplicate1toNPolicy ?? DEFAULT_1TON_DUPLICATE_POLICY;
    this.maxStaleAgeMs = options?.maxStaleAgeMs ?? 300_000;

    this.validatePolicySeparation(this.verifyPolicy, this.duplicatePolicy);
    this.activeIndex = new HighSpeedBiometricIndexV3(this.maxArenaCapacity);
  }

  private validatePolicySeparation(
    vPol: Verification1to1PolicyConfig,
    dPol: DuplicateScreening1toNPolicyConfig,
  ): void {
    if (
      !Number.isFinite(vPol.matchThreshold) ||
      vPol.matchThreshold <= 0.0 ||
      vPol.matchThreshold >= 1.0
    ) {
      throw new Error('INVALID_1TO1_POLICY: matchThreshold must be in (0.0, 1.0).');
    }
    if (
      !Number.isFinite(dPol.warningThreshold) ||
      !Number.isFinite(dPol.hardBlockThreshold) ||
      dPol.warningThreshold <= 0.0 ||
      dPol.hardBlockThreshold > 1.0 ||
      dPol.warningThreshold >= dPol.hardBlockThreshold
    ) {
      throw new Error(
        'INVALID_1TON_POLICY: warningThreshold must be strictly less than hardBlockThreshold.',
      );
    }
    if (vPol.matchThreshold >= dPol.warningThreshold) {
      throw new Error(
        `POLICY_SEPARATION_VIOLATION: 1:1 threshold (${vPol.matchThreshold}) must be strictly lower than 1:N duplicate warning threshold (${dPol.warningThreshold}).`,
      );
    }
  }

  public getCurrentEpoch(): number {
    return this.localEpoch;
  }

  public getActiveGallerySize(): number {
    return this.activeIndex.size;
  }

  public getGalleryHealthStatus(): {
    readonly initialized: boolean;
    readonly healthy: boolean;
    readonly stale: boolean;
    readonly localEpoch: number;
    readonly activeCount: number;
  } {
    const stale =
      this.localEpoch < 0 ||
      !this.isIndexHealthy ||
      Date.now() - this.lastSyncedAtMs > this.maxStaleAgeMs;
    return {
      initialized: this.localEpoch >= 0,
      healthy: this.isIndexHealthy,
      stale,
      localEpoch: this.localEpoch,
      activeCount: this.activeIndex.size,
    };
  }

  /**
   * Forces a full rebuild of the Copy-on-Write index from the encrypted vault.
   * Fails closed if persistence or KMS decryption fails.
   */
  public async forceRebuildIndex(): Promise<void> {
    this.localEpoch = -1;
    await this.ensureSynchronized();
  }

  /**
   * Single-flight synchronization check against the durable global epoch.
   * Fails closed if the remote epoch cannot be read or if any active canonical v3 template fails to unseal.
   */
  public async ensureSynchronized(): Promise<void> {
    let remoteEpoch: number;
    try {
      remoteEpoch = await this.persistence.getGlobalEpoch();
    } catch (err) {
      this.isIndexHealthy = false;
      throw new Error(
        `GALLERY_UNAVAILABLE_FAIL_CLOSED: Failed to read global epoch (${(err as Error).message}).`,
      );
    }

    const isStaleByClock = Date.now() - this.lastSyncedAtMs > this.maxStaleAgeMs;
    if (
      this.isIndexHealthy &&
      this.localEpoch === remoteEpoch &&
      this.localEpoch >= 0 &&
      !isStaleByClock
    ) {
      return;
    }

    if (this.reconcileInFlight !== null) {
      await this.reconcileInFlight;
      return;
    }

    this.reconcileInFlight = this.rebuildCowSnapshotFromVault().finally(() => {
      this.reconcileInFlight = null;
    });

    await this.reconcileInFlight;
  }

  /**
   * Standalone 1:N Duplicate Screening using the 1:N policy (warning = 0.74, hardBlock = 0.90).
   */
  public async screenForDuplicates1toN(params: {
    readonly candidateUid: string;
    readonly payload: BiometricPlaintextSfacePayloadV3;
  }): Promise<{
    readonly decisionStatus: DuplicateScreeningDecisionStatus;
    readonly policyApplied: string;
    readonly warningThreshold: number;
    readonly hardBlockThreshold: number;
    readonly duplicateSearch: DuplicateCandidateMatchV3;
  }> {
    const validatedVec = assertValidCanonicalSfaceEmbedding(
      params.payload.sfaceEmbedding128,
      `screenForDuplicates1toN(${params.candidateUid})`,
    );

    if (
      params.payload.isoQualityScore < this.duplicatePolicy.minIsoQualityScore ||
      params.payload.padLivenessScore < this.duplicatePolicy.minPadLivenessScore
    ) {
      throw new Error(
        'QUALITY_OR_PAD_BELOW_POLICY_MINIMUM: Probe sample failed capture-quality or presentation-attack gating.',
      );
    }

    await this.ensureSynchronized();
    if (!this.isIndexHealthy || this.localEpoch < 0) {
      throw new Error('GALLERY_UNAVAILABLE_FAIL_CLOSED: Gallery index is not synchronized.');
    }

    const searchResult = this.activeIndex.search1toN(
      params.candidateUid,
      validatedVec,
    );

    let decisionStatus: DuplicateScreeningDecisionStatus = 'CLEAN_APPROVED';
    if (
      searchResult.matchedUid !== null &&
      searchResult.maxCosineSimilarity >= this.duplicatePolicy.hardBlockThreshold
    ) {
      decisionStatus = 'HARD_DUPLICATE_BLOCKED';
    } else if (
      searchResult.matchedUid !== null &&
      searchResult.maxCosineSimilarity >= this.duplicatePolicy.warningThreshold
    ) {
      decisionStatus = 'DUPLICATE_WARNING_FLAGGED';
    }

    return {
      decisionStatus,
      policyApplied: this.duplicatePolicy.policyId,
      warningThreshold: this.duplicatePolicy.warningThreshold,
      hardBlockThreshold: this.duplicatePolicy.hardBlockThreshold,
      duplicateSearch: searchResult,
    };
  }

  /**
   * Enrolls or re-enrolls a worker using a serialized critical section, 1:N duplicate screening,
   * Cloud KMS envelope sealing, and optimistic epoch compare-and-swap (CAS).
   */
  public async enrollWithGlobalEpochBump(params: {
    readonly uid: string;
    readonly maskedPhone: string;
    readonly payload: BiometricPlaintextSfacePayloadV3;
    readonly allowReEnrollment?: boolean;
    readonly idempotencyKey?: string;
  }): Promise<EnrollWorkerOutcomeV3> {
    if (
      params.idempotencyKey &&
      this.processedIdempotencyKeys.has(params.idempotencyKey)
    ) {
      return this.processedIdempotencyKeys.get(params.idempotencyKey)!;
    }

    return this.enqueueSerializedMutation(async () => {
      if (
        params.idempotencyKey &&
        this.processedIdempotencyKeys.has(params.idempotencyKey)
      ) {
        return this.processedIdempotencyKeys.get(params.idempotencyKey)!;
      }

      const validatedVec = assertValidCanonicalSfaceEmbedding(
        params.payload.sfaceEmbedding128,
        `enrollWithGlobalEpochBump(${params.uid})`,
      );

      if (
        params.payload.isoQualityScore < this.duplicatePolicy.minIsoQualityScore ||
        params.payload.padLivenessScore < this.duplicatePolicy.minPadLivenessScore
      ) {
        throw new Error(
          'QUALITY_OR_PAD_BELOW_POLICY_MINIMUM: Sample rejected prior to enrollment.',
        );
      }

      await this.ensureSynchronized();
      const epochBeforeEnroll = this.localEpoch;

      const existingRecord = this.activeIndex.getRecordByUid(params.uid);
      if (existingRecord !== null && !params.allowReEnrollment) {
        throw new Error(
          `ALREADY_ENROLLED_ERROR: Account ${params.uid} already has an active biometric template and allowReEnrollment is false.`,
        );
      }

      // 1. Run 1:N Duplicate Screening against all other accounts
      const screening = await this.screenForDuplicates1toN({
        candidateUid: params.uid,
        payload: {
          ...params.payload,
          sfaceEmbedding128: validatedVec,
        },
      });

      // 2. Hard Duplicate Block (>= 0.90): Reject enrollment immediately without writing to vault
      if (screening.decisionStatus === 'HARD_DUPLICATE_BLOCKED') {
        const blockedOutcome: EnrollWorkerOutcomeV3 = {
          enrolled: false,
          isReEnrollment: existingRecord !== null,
          decisionStatus: 'HARD_DUPLICATE_BLOCKED',
          policyApplied: this.duplicatePolicy.policyId,
          globalEpoch: this.localEpoch,
          duplicateSearch: screening.duplicateSearch,
          releaseStatus: RELEASE_STATUS,
          calibrationApproved: PRODUCTION_BIOMETRIC_CALIBRATION_APPROVED,
        };
        if (params.idempotencyKey) {
          this.processedIdempotencyKeys.set(params.idempotencyKey, blockedOutcome);
        }
        return blockedOutcome;
      }

      // 3. Seal canonical 128-D SFace template via Cloud KMS HSM envelope
      const aadContext: CanonicalAadContext = {
        uid: params.uid,
        modelVersion: CANONICAL_SFACE_MODEL_VERSION,
        templateSchemaVersion: CANONICAL_TEMPLATE_SCHEMA_VERSION,
        tenantId: this.tenantId,
        purpose: 'BIOMETRIC_VAULT_SFACE_V3',
      };

      const envelope = await this.kmsEnvelope.sealTemplateV3(
        {
          sfaceEmbedding128: validatedVec,
          isoQualityScore: params.payload.isoQualityScore,
          padLivenessScore: params.payload.padLivenessScore,
        },
        aadContext,
      );

      // 4. Duplicate Warning (0.74 <= score < 0.90): Flag as PENDING_AUDIT and enqueue ticket
      let auditTicketId: string | undefined;
      const docStatus =
        screening.decisionStatus === 'DUPLICATE_WARNING_FLAGGED'
          ? 'PENDING_AUDIT'
          : 'ACTIVE';

      if (
        screening.decisionStatus === 'DUPLICATE_WARNING_FLAGGED' &&
        screening.duplicateSearch.matchedUid &&
        screening.duplicateSearch.matchedMaskedPhone
      ) {
        auditTicketId = `audit_${params.uid}_${Date.now()}`;
        await this.persistence.enqueueAuditTicket({
          ticketId: auditTicketId,
          candidateUid: params.uid,
          matchedUid: screening.duplicateSearch.matchedUid,
          matchedMaskedPhone: screening.duplicateSearch.matchedMaskedPhone,
          cosineSimilarity: screening.duplicateSearch.maxCosineSimilarity,
          policyId: this.duplicatePolicy.policyId,
          createdAtEpochMs: Date.now(),
        });
      }

      const vaultDoc: StoredVaultDocumentV3 = {
        uid: params.uid,
        tenantId: this.tenantId,
        maskedPhone: params.maskedPhone,
        modelId: CANONICAL_SFACE_MODEL_ID,
        modelVersion: CANONICAL_SFACE_MODEL_VERSION,
        templateSchemaVersion: CANONICAL_TEMPLATE_SCHEMA_VERSION,
        status: docStatus,
        envelope,
        idempotencyKey: params.idempotencyKey,
        updatedAtEpochMs: Date.now(),
      };

      // 5. Persist document, then atomically bump epoch with optimistic CAS check.
      // If epoch bump fails (e.g., concurrent cross-instance write or DB failure), roll back vault write.
      await this.persistence.saveVaultDocument(vaultDoc);
      let nextEpoch: number;
      try {
        nextEpoch = await this.persistence.incrementGlobalEpoch(epochBeforeEnroll);
      } catch (epochErr) {
        // Rollback partial persistence so vault and epoch stay consistent
        if (existingRecord === null) {
          await this.persistence.deleteVaultDocument(params.uid).catch(() => {});
        }
        this.isIndexHealthy = false;
        throw new Error(
          `EPOCH_COMMIT_FAILURE_ROLLED_BACK: Failed to commit epoch after saving template (${(epochErr as Error).message}).`,
        );
      }

      const enrolledRecord: EnrolledWorkerSfaceRecordV3 = {
        uid: params.uid,
        maskedPhone: params.maskedPhone,
        modelId: CANONICAL_SFACE_MODEL_ID,
        modelVersion: CANONICAL_SFACE_MODEL_VERSION,
        templateSchemaVersion: CANONICAL_TEMPLATE_SCHEMA_VERSION,
        sfaceEmbedding128: validatedVec,
        isoQualityScore: params.payload.isoQualityScore,
        padLivenessScore: params.payload.padLivenessScore,
        enrolledAtEpochMs: vaultDoc.updatedAtEpochMs,
      };

      this.activeIndex = this.activeIndex.cloneWithUpsert(enrolledRecord);
      this.localEpoch = nextEpoch;
      this.lastSyncedAtMs = Date.now();
      this.isIndexHealthy = true;

      const outcome: EnrollWorkerOutcomeV3 = {
        enrolled: true,
        isReEnrollment: existingRecord !== null,
        decisionStatus: screening.decisionStatus,
        policyApplied: this.duplicatePolicy.policyId,
        globalEpoch: nextEpoch,
        duplicateSearch: screening.duplicateSearch,
        auditTicketId,
        releaseStatus: RELEASE_STATUS,
        calibrationApproved: PRODUCTION_BIOMETRIC_CALIBRATION_APPROVED,
      };

      if (params.idempotencyKey) {
        this.processedIdempotencyKeys.set(params.idempotencyKey, outcome);
      }
      return outcome;
    });
  }

  /**
   * 1:1 Claimed-Account Verification using the separate 1:1 policy (threshold = 0.363).
   * Never reuses the 1:N duplicate threshold (0.74 or 0.90).
   */
  public async verifyWorker1to1(
    claimedUid: string,
    probePayload: BiometricPlaintextSfacePayloadV3,
  ): Promise<Verify1to1OutcomeV3> {
    const validatedProbe = assertValidCanonicalSfaceEmbedding(
      probePayload.sfaceEmbedding128,
      `verifyWorker1to1(${claimedUid})`,
    );

    if (
      probePayload.isoQualityScore < this.verifyPolicy.minIsoQualityScore ||
      probePayload.padLivenessScore < this.verifyPolicy.minPadLivenessScore
    ) {
      return {
        verified: false,
        decisionStatus: 'QUALITY_OR_PAD_REJECTED',
        policyApplied: this.verifyPolicy.policyId,
        cosineSimilarity: null,
        thresholdApplied: this.verifyPolicy.matchThreshold,
      };
    }

    await this.ensureSynchronized();
    if (!this.isIndexHealthy || this.localEpoch < 0) {
      throw new Error('GALLERY_UNAVAILABLE_FAIL_CLOSED: Gallery index is not healthy.');
    }

    const storedRecord = this.activeIndex.getRecordByUid(claimedUid);
    if (!storedRecord) {
      return {
        verified: false,
        decisionStatus: 'CLAIMANT_TEMPLATE_NOT_FOUND',
        policyApplied: this.verifyPolicy.policyId,
        cosineSimilarity: null,
        thresholdApplied: this.verifyPolicy.matchThreshold,
      };
    }

    const cos = GalleryConsistencyServiceV3.cosine128(
      validatedProbe,
      storedRecord.sfaceEmbedding128,
    );
    if (!Number.isFinite(cos)) {
      throw new Error('NON_FINITE_VERIFICATION_SCORE: Score computation failed.');
    }

    const verified = cos >= this.verifyPolicy.matchThreshold;
    return {
      verified,
      decisionStatus: verified ? 'MATCH_CONFIRMED' : 'NON_MATCH_REJECTED',
      policyApplied: this.verifyPolicy.policyId,
      cosineSimilarity: Number(cos.toFixed(6)),
      thresholdApplied: this.verifyPolicy.matchThreshold,
    };
  }

  /**
   * India DPDPA 2023 §12 Right to Erasure: purges the encrypted document and atomically swaps the CoW arena.
   */
  public async eraseWorkerBiometrics(
    uid: string,
  ): Promise<{ erased: boolean; newEpoch: number }> {
    return this.enqueueSerializedMutation(async () => {
      await this.ensureSynchronized();
      const deleted = await this.persistence.deleteVaultDocument(uid);
      if (!deleted) {
        return { erased: false, newEpoch: this.localEpoch };
      }

      const nextEpoch = await this.persistence.incrementGlobalEpoch(this.localEpoch);
      this.activeIndex = this.activeIndex.cloneWithoutUid(uid);
      this.localEpoch = nextEpoch;
      this.lastSyncedAtMs = Date.now();
      return { erased: true, newEpoch: nextEpoch };
    });
  }

  /**
   * Rebuilds a fresh Copy-on-Write HighSpeedBiometricIndexV3 snapshot from Firestore.
   * Rejects or skips legacy incompatible templates without assigning artificial scores.
   * Fails closed if any active canonical SFace v3 template fails KMS authentication.
   */
  private async rebuildCowSnapshotFromVault(): Promise<void> {
    try {
      const targetEpoch = await this.persistence.getGlobalEpoch();
      const docs = await this.persistence.fetchAllActiveTemplates();
      const shadowIndex = new HighSpeedBiometricIndexV3(
        Math.max(this.maxArenaCapacity, docs.length + 1024),
      );

      for (const doc of docs) {
        if (doc.status === 'ERASED') {
          continue;
        }
        // Skip legacy v1_geometric or v2_whitened or experimental v3_dense512 landmark templates cleanly
        if (
          doc.modelVersion !== CANONICAL_SFACE_MODEL_VERSION ||
          doc.modelId !== CANONICAL_SFACE_MODEL_ID ||
          doc.templateSchemaVersion !== CANONICAL_TEMPLATE_SCHEMA_VERSION
        ) {
          continue;
        }

        const aadContext: CanonicalAadContext = {
          uid: doc.uid,
          modelVersion: CANONICAL_SFACE_MODEL_VERSION,
          templateSchemaVersion: CANONICAL_TEMPLATE_SCHEMA_VERSION,
          tenantId: doc.tenantId,
          purpose: 'BIOMETRIC_VAULT_SFACE_V3',
        };

        const unsealed = await this.kmsEnvelope.unsealTemplateV3(
          doc.envelope,
          aadContext,
        );

        shadowIndex.upsertTemplate({
          uid: doc.uid,
          maskedPhone: doc.maskedPhone,
          modelId: CANONICAL_SFACE_MODEL_ID,
          modelVersion: CANONICAL_SFACE_MODEL_VERSION,
          templateSchemaVersion: CANONICAL_TEMPLATE_SCHEMA_VERSION,
          sfaceEmbedding128: unsealed.sfaceEmbedding128,
          isoQualityScore: unsealed.isoQualityScore,
          padLivenessScore: unsealed.padLivenessScore,
          enrolledAtEpochMs: doc.updatedAtEpochMs,
        });
      }

      this.activeIndex = shadowIndex;
      this.localEpoch = targetEpoch;
      this.lastSyncedAtMs = Date.now();
      this.isIndexHealthy = true;
    } catch (err) {
      this.isIndexHealthy = false;
      throw new Error(
        `GALLERY_REBUILD_FAIL_CLOSED: Failed to synchronize gallery from vault (${(err as Error).message}).`,
      );
    }
  }

  private enqueueSerializedMutation<T>(fn: () => Promise<T>): Promise<T> {
    const next = this.mutationQueue.then(fn, fn);
    this.mutationQueue = next.then(
      () => undefined,
      () => undefined,
    );
    return next;
  }

  private static cosine128(a: Float32Array, b: Float32Array): number {
    if (a.length !== SFACE_EMBEDDING_DIMENSION || b.length !== SFACE_EMBEDDING_DIMENSION) {
      throw new Error('Incompatible vector dimensions in cosine128.');
    }
    let dot = 0.0;
    let normA = 0.0;
    let normB = 0.0;
    for (let i = 0; i < SFACE_EMBEDDING_DIMENSION; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    const denom = Math.sqrt(normA) * Math.sqrt(normB);
    if (denom < 1e-12 || !Number.isFinite(denom)) {
      throw new Error('Degenerate vector norm in cosine128.');
    }
    return Math.max(-1.0, Math.min(1.0, dot / denom));
  }
}

