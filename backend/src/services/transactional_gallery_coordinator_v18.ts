// File: backend/src/services/transactional_gallery_coordinator_v18.ts
// KELASAGARA V18 / PHASE 13.3 — Self-Healing Multi-Node Transactional Gallery Coordinator
// Implements automatic WAL delta catch-up, re-screening on RECHECK_REQUIRED_EPOCH_DRIFT,
// and KMS-wrapped KS18 binary snapshot cold-boot hydration.
// Release Posture: CONTROLLED_TEST_BUILD_ONLY | productionBiometricCalibrationApproved = false

import * as crypto from 'node:crypto';
import {
  BiometricPlaintextSfacePayloadV3,
  CANONICAL_SFACE_MODEL_ID,
  CANONICAL_SFACE_MODEL_VERSION,
  CANONICAL_TEMPLATE_SCHEMA_VERSION,
  CanonicalAadContext,
  CloudKmsEnvelopeService,
  KmsKeyProvider,
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
import {
  BiometricAuditTicketV3,
  DEFAULT_1TO1_VERIFICATION_POLICY,
  DEFAULT_1TON_DUPLICATE_POLICY,
  DuplicateScreening1toNPolicyConfig,
  DuplicateScreeningDecisionStatus,
  Verification1to1PolicyConfig,
  Verify1to1OutcomeV3,
} from './gallery_consistency_service';
import {
  FirestoreBiometricTransactionAdapterV18,
  TransactionalWalEntryDocV18,
} from './firestore_transaction_adapter_v18';
import {
  Ks18EncryptedSnapshotBundle,
  encodeSnapshotCanonicalAad,
  exportEncryptedAlignedSnapshotKs18,
  hydrateEncryptedSnapshotKs18,
} from '../biometrics/iso24745_iom_cancelable_snapshot_v18';
import { verifyContiguousWalSequence } from './wal_compaction_and_gap_guard_v18';

export interface KmsWrappedKs18SnapshotArtifact {
  readonly bundle: Ks18EncryptedSnapshotBundle;
  readonly kmsKeyVersionName: string;
  readonly wrappedSnapshotDekBase64: string;
}

export interface CoordinatedEnrollmentOutcomeV18 {
  readonly enrolled: boolean;
  readonly decisionStatus: DuplicateScreeningDecisionStatus;
  readonly committedGlobalEpoch: number;
  readonly templateGeneration: number;
  readonly epochDriftRetriesUsed: number;
  readonly idempotentReplay: boolean;
  readonly duplicateSearch: DuplicateCandidateMatchV3;
  readonly auditTicketId?: string;
  readonly releaseStatus: typeof RELEASE_STATUS;
  readonly calibrationApproved: typeof PRODUCTION_BIOMETRIC_CALIBRATION_APPROVED;
}

export class TransactionalGalleryCoordinatorV18 {
  private readonly txAdapter: FirestoreBiometricTransactionAdapterV18;
  private readonly kmsEnvelope: CloudKmsEnvelopeService;
  private readonly kmsKeyProvider: KmsKeyProvider;
  private readonly tenantId: string;
  private readonly clusterId: string;
  private readonly verifyPolicy: Verification1to1PolicyConfig;
  private readonly duplicatePolicy: DuplicateScreening1toNPolicyConfig;
  private readonly maxEpochDriftRetries: number;
  private readonly maxArenaCapacity: number;

  private activeIndex: HighSpeedBiometricIndexV3;
  private activeRecordsMap = new Map<string, EnrolledWorkerSfaceRecordV3>();
  private uidGenerations = new Map<string, number>();
  private localWatermarkEpoch = 0;
  private catchUpInFlight: Promise<number> | null = null;

  constructor(params: {
    readonly txAdapter: FirestoreBiometricTransactionAdapterV18;
    readonly kmsEnvelope: CloudKmsEnvelopeService;
    readonly kmsKeyProvider: KmsKeyProvider;
    readonly tenantId?: string;
    readonly clusterId?: string;
    readonly verify1to1Policy?: Verification1to1PolicyConfig;
    readonly duplicate1toNPolicy?: DuplicateScreening1toNPolicyConfig;
    readonly maxEpochDriftRetries?: number;
    readonly maxArenaCapacity?: number;
  }) {
    this.txAdapter = params.txAdapter;
    this.kmsEnvelope = params.kmsEnvelope;
    this.kmsKeyProvider = params.kmsKeyProvider;
    this.tenantId = params.tenantId ?? 'karnataka-kelasagaara-prod';
    this.clusterId = params.clusterId ?? 'karnataka-kelasagaara-primary';
    this.verifyPolicy =
      params.verify1to1Policy ?? DEFAULT_1TO1_VERIFICATION_POLICY;
    this.duplicatePolicy =
      params.duplicate1toNPolicy ?? DEFAULT_1TON_DUPLICATE_POLICY;
    this.maxEpochDriftRetries = params.maxEpochDriftRetries ?? 5;
    this.maxArenaCapacity = params.maxArenaCapacity ?? 50000;
    this.activeIndex = new HighSpeedBiometricIndexV3(this.maxArenaCapacity);
  }

  public getLocalWatermarkEpoch(): number {
    return this.localWatermarkEpoch;
  }

  public getActiveGallerySize(): number {
    return this.activeIndex.size;
  }

  public getKnownGenerationForUid(uid: string): number {
    return this.uidGenerations.get(uid) ?? 0;
  }

  /**
   * Pulls and applies all committed WAL entries strictly newer than `localWatermarkEpoch`.
   * Single-flight guarded so concurrent callers on the same node share one WAL catch-up pass.
   */
  public async catchUpFromWalOutbox(): Promise<number> {
    if (this.catchUpInFlight !== null) {
      return this.catchUpInFlight;
    }

    this.catchUpInFlight = this.applyIncrementalWalDeltasInternal().finally(
      () => {
        this.catchUpInFlight = null;
      },
    );
    return this.catchUpInFlight;
  }

  private async applyIncrementalWalDeltasInternal(): Promise<number> {
    const deltas: readonly TransactionalWalEntryDocV18[] =
      await this.txAdapter.fetchIncrementalWalSince(this.localWatermarkEpoch);

    if (deltas.length === 0) {
      return this.localWatermarkEpoch;
    }

    // Phase 13.4 Invariant: Fail closed if compacted WAL entries created a sequence gap
    verifyContiguousWalSequence(this.localWatermarkEpoch, deltas);

    const validEntries = deltas.filter((e) => e.walSeq > this.localWatermarkEpoch);
    if (validEntries.length === 0) {
      return this.localWatermarkEpoch;
    }

    // Step 1: Parallel bounded unsealing of UPSERT envelopes (chunk size 16)
    const unsealedMap = new Map<number, EnrolledWorkerSfaceRecordV3>();
    const upsertEntries = validEntries.filter(
      (e) =>
        e.operation === 'UPSERT' &&
        e.envelope &&
        e.modelId === CANONICAL_SFACE_MODEL_ID &&
        e.modelVersion === CANONICAL_SFACE_MODEL_VERSION &&
        e.templateSchemaVersion === CANONICAL_TEMPLATE_SCHEMA_VERSION,
    );

    const CHUNK_SIZE = 16;
    for (let i = 0; i < upsertEntries.length; i += CHUNK_SIZE) {
      const chunk = upsertEntries.slice(i, i + CHUNK_SIZE);
      await Promise.all(
        chunk.map(async (entry) => {
          const aadContext: CanonicalAadContext = {
            uid: entry.uid,
            modelVersion: CANONICAL_SFACE_MODEL_VERSION,
            templateSchemaVersion: CANONICAL_TEMPLATE_SCHEMA_VERSION,
            tenantId: this.tenantId,
            purpose: 'BIOMETRIC_VAULT_SFACE_V3',
          };

          const unsealed = await this.kmsEnvelope.unsealTemplateV3(
            entry.envelope!,
            aadContext,
          );

          const record: EnrolledWorkerSfaceRecordV3 = {
            uid: entry.uid,
            maskedPhone: entry.maskedPhone,
            modelId: CANONICAL_SFACE_MODEL_ID,
            modelVersion: CANONICAL_SFACE_MODEL_VERSION,
            templateSchemaVersion: CANONICAL_TEMPLATE_SCHEMA_VERSION,
            sfaceEmbedding128: unsealed.sfaceEmbedding128,
            isoQualityScore: unsealed.isoQualityScore,
            padLivenessScore: unsealed.padLivenessScore,
            enrolledAtEpochMs: entry.committedAtEpochMs,
          };
          unsealedMap.set(entry.walSeq, record);
        }),
      );
    }

    // Step 2: Strictly monotonic sequential event application
    const nextRecordsMap = new Map(this.activeRecordsMap);
    const nextGenerations = new Map(this.uidGenerations);
    const upsertsToApply: EnrolledWorkerSfaceRecordV3[] = [];
    const tombstoneUids = new Set<string>();
    let highestSeq = this.localWatermarkEpoch;

    for (const entry of validEntries) {
      if (entry.walSeq <= highestSeq) {
        continue; // Strictly monotonic idempotent guard
      }

      if (entry.operation === 'TOMBSTONE') {
        tombstoneUids.add(entry.uid);
        nextRecordsMap.delete(entry.uid);
        nextGenerations.set(entry.uid, entry.templateGeneration);
        highestSeq = entry.walSeq;
        // Also prune from upsertsToApply if it was upserted in this same replay batch
        const existingIdx = upsertsToApply.findIndex((u) => u.uid === entry.uid);
        if (existingIdx !== -1) {
          upsertsToApply.splice(existingIdx, 1);
        }
        continue;
      }

      if (entry.operation === 'UPSERT') {
        const record = unsealedMap.get(entry.walSeq);
        if (record) {
          tombstoneUids.delete(entry.uid);
          upsertsToApply.push(record);
          nextRecordsMap.set(entry.uid, record);
          nextGenerations.set(entry.uid, entry.templateGeneration);
          highestSeq = entry.walSeq;
        }
      }
    }

    // Step 3: Single batch Copy-on-Write arena update (eliminates O(N * L) repeated full arena clones)
    const nextIndex = this.activeIndex.cloneWithBatchMutations(
      upsertsToApply,
      tombstoneUids,
    );

    // Atomic Copy-on-Write swap
    this.activeIndex = nextIndex;
    this.activeRecordsMap = nextRecordsMap;
    this.uidGenerations = nextGenerations;
    this.localWatermarkEpoch = highestSeq;

    return this.localWatermarkEpoch;
  }

  /**
   * Executes the full Phase 4 Search-then-CAS protocol with automatic WAL catch-up and re-screening
   * whenever a concurrent instance advances the global epoch during the screening window.
   */
  public async enrollWorkerWithEpochFencedRetry(params: {
    readonly uid: string;
    readonly maskedPhone: string;
    readonly idempotencyKey: string;
    readonly payload: BiometricPlaintextSfacePayloadV3;
    readonly allowReEnrollment?: boolean;
  }): Promise<CoordinatedEnrollmentOutcomeV18> {
    const validatedVec = assertValidCanonicalSfaceEmbedding(
      params.payload.sfaceEmbedding128,
      `enrollWorkerWithEpochFencedRetry(${params.uid})`,
    );

    if (
      params.payload.isoQualityScore < this.duplicatePolicy.minIsoQualityScore ||
      params.payload.padLivenessScore < this.duplicatePolicy.minPadLivenessScore
    ) {
      throw new Error(
        'QUALITY_OR_PAD_BELOW_POLICY_MINIMUM: Sample rejected prior to gallery screening.',
      );
    }

    // Pre-seal the canonical 128-D SFace envelope outside the transaction once
    const aadContext: CanonicalAadContext = {
      uid: params.uid,
      modelVersion: CANONICAL_SFACE_MODEL_VERSION,
      templateSchemaVersion: CANONICAL_TEMPLATE_SCHEMA_VERSION,
      tenantId: this.tenantId,
      purpose: 'BIOMETRIC_VAULT_SFACE_V3',
    };

    const preSealedEnvelope = await this.kmsEnvelope.sealTemplateV3(
      {
        sfaceEmbedding128: validatedVec,
        isoQualityScore: params.payload.isoQualityScore,
        padLivenessScore: params.payload.padLivenessScore,
      },
      aadContext,
    );

    // Compute deterministic request fingerprint for idempotency tamper detection
    const vecBytes = Buffer.from(
      validatedVec.buffer,
      validatedVec.byteOffset,
      validatedVec.byteLength,
    );
    const requestFingerprintSha256 = crypto
      .createHash('sha256')
      .update(`${params.uid}:${params.allowReEnrollment ? '1' : '0'}:`)
      .update(vecBytes)
      .digest('hex');

    // Initial incremental catch-up before first screening pass
    await this.catchUpFromWalOutbox();

    for (
      let driftAttempt = 0;
      driftAttempt <= this.maxEpochDriftRetries;
      driftAttempt++
    ) {
      const screenedAtEpoch = this.localWatermarkEpoch;
      const expectedGen = this.uidGenerations.get(params.uid) ?? 0;

      // 1. Run 1:N Duplicate Screening against current synchronized Copy-on-Write arena
      const duplicateSearch = this.activeIndex.search1toN(
        params.uid,
        validatedVec,
      );

      let decisionStatus: DuplicateScreeningDecisionStatus = 'CLEAN_APPROVED';
      if (
        duplicateSearch.matchedUid !== null &&
        duplicateSearch.maxCosineSimilarity >=
          this.duplicatePolicy.hardBlockThreshold
      ) {
        decisionStatus = 'HARD_DUPLICATE_BLOCKED';
      } else if (
        duplicateSearch.matchedUid !== null &&
        duplicateSearch.maxCosineSimilarity >=
          this.duplicatePolicy.warningThreshold
      ) {
        decisionStatus = 'DUPLICATE_WARNING_FLAGGED';
      }

      // 2. If Hard Duplicate (>= 0.90), record investigation ticket to audit collection and halt without writing to vault
      if (decisionStatus === 'HARD_DUPLICATE_BLOCKED') {
        const auditTicketId = `audit_dup_${params.uid}_${screenedAtEpoch}_${driftAttempt}`;
        const auditTicket: BiometricAuditTicketV3 = {
          ticketId: auditTicketId,
          candidateUid: params.uid,
          matchedUid: duplicateSearch.matchedUid ?? 'unknown',
          matchedMaskedPhone: duplicateSearch.matchedMaskedPhone ?? 'unknown',
          cosineSimilarity: duplicateSearch.maxCosineSimilarity,
          policyId: this.duplicatePolicy.policyId,
          createdAtEpochMs: Date.now(),
        };

        try {
          await this.txAdapter.recordDuplicateInvestigationTicket(auditTicket);
        } catch {
          // Non-blocking in mock environments
        }

        return {
          enrolled: false,
          decisionStatus: 'HARD_DUPLICATE_BLOCKED',
          committedGlobalEpoch: this.localWatermarkEpoch,
          templateGeneration: expectedGen,
          epochDriftRetriesUsed: driftAttempt,
          idempotentReplay: false,
          duplicateSearch,
          auditTicketId,
          releaseStatus: RELEASE_STATUS,
          calibrationApproved: PRODUCTION_BIOMETRIC_CALIBRATION_APPROVED,
        };
      }

      let auditTicket: BiometricAuditTicketV3 | undefined;
      if (
        decisionStatus === 'DUPLICATE_WARNING_FLAGGED' &&
        duplicateSearch.matchedUid &&
        duplicateSearch.matchedMaskedPhone
      ) {
        auditTicket = {
          ticketId: `audit_${params.uid}_${screenedAtEpoch}_${driftAttempt}`,
          candidateUid: params.uid,
          matchedUid: duplicateSearch.matchedUid,
          matchedMaskedPhone: duplicateSearch.matchedMaskedPhone,
          cosineSimilarity: duplicateSearch.maxCosineSimilarity,
          policyId: this.duplicatePolicy.policyId,
          createdAtEpochMs: Date.now(),
        };
      }

      // 3. Attempt atomic Firestore CAS transaction fenced at `screenedAtEpoch`
      const txResult = await this.txAdapter.commitEnrollmentTransactionally({
        uid: params.uid,
        tenantId: this.tenantId,
        maskedPhone: params.maskedPhone,
        idempotencyKey: params.idempotencyKey,
        requestFingerprintSha256,
        screenedAtGlobalEpoch: screenedAtEpoch,
        expectedTemplateGeneration: expectedGen,
        allowReEnrollment: params.allowReEnrollment ?? false,
        decisionStatus,
        preSealedEnvelope,
        auditTicket,
      });

      if (
        txResult.status === 'COMMITTED_NEW' ||
        txResult.status === 'IDEMPOTENT_REPLAY'
      ) {
        // Pull WAL deltas so local index reflects our newly committed epoch immediately
        await this.catchUpFromWalOutbox();
        return {
          enrolled: true,
          decisionStatus: txResult.decisionStatus ?? decisionStatus,
          committedGlobalEpoch: txResult.committedGlobalEpoch,
          templateGeneration: txResult.templateGeneration,
          epochDriftRetriesUsed: driftAttempt,
          idempotentReplay: txResult.status === 'IDEMPOTENT_REPLAY',
          duplicateSearch,
          auditTicketId: txResult.auditTicketId,
          releaseStatus: RELEASE_STATUS,
          calibrationApproved: PRODUCTION_BIOMETRIC_CALIBRATION_APPROVED,
        };
      }

      if (txResult.status === 'RECHECK_REQUIRED_EPOCH_DRIFT') {
        // Another instance committed between our 1:N search and our transaction!
        // Catch up from WAL outbox and loop to re-screen against the newly added worker(s).
        await this.catchUpFromWalOutbox();
        continue;
      }

      if (txResult.status === 'CONFLICT_ALREADY_ENROLLED') {
        throw new Error(
          `CONFLICT_ALREADY_ENROLLED: UID ${params.uid} is already enrolled (generation ${txResult.templateGeneration}).`,
        );
      }

      if (txResult.status === 'CONFLICT_STALE_GENERATION') {
        await this.catchUpFromWalOutbox();
        continue;
      }

      if (txResult.status === 'CONFLICT_IDEMPOTENCY_PAYLOAD_MISMATCH') {
        throw new Error(
          `CONFLICT_IDEMPOTENCY_PAYLOAD_MISMATCH: Idempotency key ${params.idempotencyKey} was reused with a different biometric payload.`,
        );
      }
    }

    throw new Error(
      `MAX_EPOCH_DRIFT_RETRIES_EXCEEDED: Could not finalize enrollment after ${this.maxEpochDriftRetries} concurrent epoch drift retries.`,
    );
  }

  /**
   * 1:1 Verification using the separate 1:1 policy (0.363 candidate threshold).
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

    await this.catchUpFromWalOutbox();
    const stored = this.activeIndex.getRecordByUid(claimedUid);
    if (!stored) {
      return {
        verified: false,
        decisionStatus: 'CLAIMANT_TEMPLATE_NOT_FOUND',
        policyApplied: this.verifyPolicy.policyId,
        cosineSimilarity: null,
        thresholdApplied: this.verifyPolicy.matchThreshold,
      };
    }

    let dot = 0.0;
    for (let i = 0; i < SFACE_EMBEDDING_DIMENSION; i++) {
      dot += validatedProbe[i] * stored.sfaceEmbedding128[i];
    }
    const cos = Math.max(-1.0, Math.min(1.0, dot));
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
   * Exports a KMS-wrapped `KS18` encrypted snapshot at the current `localWatermarkEpoch`.
   * The ephemeral 256-bit snapshot DEK is wrapped via `KmsKeyProvider` and zeroized in RAM.
   */
  public async exportKmsWrappedSnapshotKs18(
    keyId = 'ks18-snapshot-kek-v1',
  ): Promise<KmsWrappedKs18SnapshotArtifact> {
    await this.catchUpFromWalOutbox();
    const records = Array.from(this.activeRecordsMap.values());
    const ephemeralDek = crypto.randomBytes(32);

    try {
      const bundle = exportEncryptedAlignedSnapshotKs18({
        records,
        watermarkWalSeq: this.localWatermarkEpoch,
        clusterId: this.clusterId,
        keyId,
        snapshotEncryptionKey32: ephemeralDek,
      });

      const snapshotAad = encodeSnapshotCanonicalAad({
        clusterId: this.clusterId,
        keyId,
        modelVersion: CANONICAL_SFACE_MODEL_VERSION,
        watermarkWalSeq: bundle.watermarkWalSeq,
        nodeCount: bundle.nodeCount,
      });

      const { wrappedDek, keyVersionName } = await this.kmsKeyProvider.wrapKey(
        ephemeralDek,
        snapshotAad,
      );

      return {
        bundle,
        kmsKeyVersionName: keyVersionName,
        wrappedSnapshotDekBase64: wrappedDek.toString('base64'),
      };
    } finally {
      ephemeralDek.fill(0);
    }
  }

  /**
   * Cold-boots a replica instance in sub-200ms by unwrapping the `KS18` snapshot DEK via Cloud KMS,
   * hydrating the aligned 128-D arena, and replaying any incremental WAL entries committed after the snapshot.
   */
  public async hydrateFromKmsSnapshotAndWalTail(
    artifact: KmsWrappedKs18SnapshotArtifact,
  ): Promise<{
    readonly snapshotWatermark: number;
    readonly finalEpochAfterWalTail: number;
    readonly activeGallerySize: number;
    readonly snapshotHydrationLatencyMs: number;
  }> {
    if (artifact.bundle.watermarkWalSeq < this.localWatermarkEpoch) {
      throw new Error(
        `ANTI_ROLLBACK_VIOLATION: Snapshot watermark (${artifact.bundle.watermarkWalSeq}) is older than local epoch (${this.localWatermarkEpoch}).`,
      );
    }

    const snapshotAad = encodeSnapshotCanonicalAad({
      clusterId: this.clusterId,
      keyId: artifact.bundle.keyId,
      modelVersion: artifact.bundle.modelVersion,
      watermarkWalSeq: artifact.bundle.watermarkWalSeq,
      nodeCount: artifact.bundle.nodeCount,
    });

    const wrappedDek = Buffer.from(artifact.wrappedSnapshotDekBase64, 'base64');
    const unwrappedDek = await this.kmsKeyProvider.unwrapKey(
      wrappedDek,
      snapshotAad,
      artifact.kmsKeyVersionName,
    );

    try {
      const hydrated = hydrateEncryptedSnapshotKs18({
        bundle: artifact.bundle,
        expectedClusterId: this.clusterId,
        snapshotEncryptionKey32: unwrappedDek,
        maxArenaCapacity: this.maxArenaCapacity,
      });

      const rebuiltMap = new Map<string, EnrolledWorkerSfaceRecordV3>();
      const rebuiltGens = new Map<string, number>();
      for (const rec of hydrated.records) {
        rebuiltMap.set(rec.uid, rec);
        rebuiltGens.set(rec.uid, this.uidGenerations.get(rec.uid) ?? 1);
      }

      // Preserve previous state for atomic rollback if WAL tail replay fails
      const prevIndex = this.activeIndex;
      const prevRecordsMap = this.activeRecordsMap;
      const prevGenerations = this.uidGenerations;
      const prevEpoch = this.localWatermarkEpoch;

      this.activeIndex = hydrated.index;
      this.localWatermarkEpoch = hydrated.watermarkWalSeq;
      this.activeRecordsMap = rebuiltMap;
      this.uidGenerations = rebuiltGens;

      // Replay any WAL tail entries committed after the snapshot watermark
      let finalEpoch: number;
      try {
        finalEpoch = await this.catchUpFromWalOutbox();
      } catch (walErr) {
        this.activeIndex = prevIndex;
        this.activeRecordsMap = prevRecordsMap;
        this.uidGenerations = prevGenerations;
        this.localWatermarkEpoch = prevEpoch;
        throw walErr;
      }

      return {
        snapshotWatermark: hydrated.watermarkWalSeq,
        finalEpochAfterWalTail: finalEpoch,
        activeGallerySize: this.activeIndex.size,
        snapshotHydrationLatencyMs: hydrated.hydrationLatencyMs,
      };
    } finally {
      unwrappedDek.fill(0);
    }
  }
}
