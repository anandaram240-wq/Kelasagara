// File: backend/src/services/firestore_transaction_adapter_v18.ts
// KELASAGARA V18 / PHASE 13 — Production Firestore runTransaction Adapter
// Standards: ISO/IEC 24745, DPDP Rules 2025, ACID Transactional Outbox WAL
// Release Posture: CONTROLLED_TEST_BUILD_ONLY | productionBiometricCalibrationApproved = false

import {
  CANONICAL_SFACE_MODEL_ID,
  CANONICAL_SFACE_MODEL_VERSION,
  CANONICAL_TEMPLATE_SCHEMA_VERSION,
  EncryptedBiometricEnvelopeV3,
  PRODUCTION_BIOMETRIC_CALIBRATION_APPROVED,
  RELEASE_STATUS,
} from '../crypto/cloud_kms_envelope';
import {
  BiometricAuditTicketV3,
  DuplicateScreeningDecisionStatus,
  StoredVaultDocumentV3,
} from './gallery_consistency_service';

/**
 * Minimal structural interfaces matching firebase-admin/firestore (v12+)
 * so this adapter binds directly to Admin SDK Firestore or Emulator instances.
 */
export interface FirestoreDocSnapshotLike<T = Record<string, unknown>> {
  readonly exists: boolean;
  readonly id: string;
  data(): T | undefined;
}

export interface FirestoreDocRefLike<T = Record<string, unknown>> {
  readonly id: string;
  readonly path: string;
  get(): Promise<FirestoreDocSnapshotLike<T>>;
  set(data: T): Promise<unknown>;
  delete(): Promise<unknown>;
}

export interface FirestoreQuerySnapshotLike<T = Record<string, unknown>> {
  readonly docs: ReadonlyArray<FirestoreDocSnapshotLike<T>>;
}

export interface FirestoreCollectionRefLike<T = Record<string, unknown>> {
  doc(docId: string): FirestoreDocRefLike<T>;
  where(
    field: string,
    op: '==' | '>' | '>=' | '<=',
    value: unknown,
  ): {
    get(): Promise<FirestoreQuerySnapshotLike<T>>;
  };
  get(): Promise<FirestoreQuerySnapshotLike<T>>;
}

export interface FirestoreTransactionLike {
  get<T = Record<string, unknown>>(
    docRef: FirestoreDocRefLike<T>,
  ): Promise<FirestoreDocSnapshotLike<T>>;
  set<T = Record<string, unknown>>(
    docRef: FirestoreDocRefLike<T>,
    data: T,
  ): FirestoreTransactionLike;
  delete(docRef: FirestoreDocRefLike<unknown>): FirestoreTransactionLike;
}

export interface FirestoreDatabaseLike {
  collection<T = Record<string, unknown>>(
    collectionName: string,
  ): FirestoreCollectionRefLike<T>;
  runTransaction<R>(
    updateFunction: (transaction: FirestoreTransactionLike) => Promise<R>,
    transactionOptions?: { maxAttempts?: number },
  ): Promise<R>;
}

export interface ClusterEpochMetaDocV18 {
  readonly clusterId: string;
  readonly globalEpoch: number;
  readonly lastMutatedUid: string;
  readonly lastMutationType: 'ENROLL' | 'RE_ENROLL' | 'ERASE';
  readonly updatedAtEpochMs: number;
}

export interface VaultRecordDocV18 extends StoredVaultDocumentV3 {
  readonly templateGeneration: number;
  readonly committedAtGlobalEpoch: number;
}

export interface IdempotencyRecordDocV18 {
  readonly idempotencyKey: string;
  readonly uid: string;
  readonly operationType: 'ENROLL' | 'RE_ENROLL' | 'ERASE';
  readonly requestFingerprintSha256: string;
  readonly outcomeStatus:
    | DuplicateScreeningDecisionStatus
    | 'ERASED_SUCCESS';
  readonly committedGlobalEpoch: number;
  readonly templateGeneration: number;
  readonly auditTicketId?: string;
  readonly createdAtEpochMs: number;
}

export interface TransactionalWalEntryDocV18 {
  readonly walSeq: number;
  readonly uid: string;
  readonly maskedPhone: string;
  readonly operation: 'UPSERT' | 'TOMBSTONE';
  readonly templateGeneration: number;
  readonly modelId: string;
  readonly modelVersion: string;
  readonly templateSchemaVersion: number;
  readonly envelope?: EncryptedBiometricEnvelopeV3;
  readonly committedAtEpochMs: number;
}

export type TransactionCommitStatusV18 =
  | 'COMMITTED_NEW'
  | 'IDEMPOTENT_REPLAY'
  | 'RECHECK_REQUIRED_EPOCH_DRIFT'
  | 'CONFLICT_STALE_GENERATION'
  | 'CONFLICT_ALREADY_ENROLLED'
  | 'CONFLICT_IDEMPOTENCY_PAYLOAD_MISMATCH';

export interface TransactionalEnrollmentInputV18 {
  readonly uid: string;
  readonly tenantId: string;
  readonly maskedPhone: string;
  readonly idempotencyKey: string;
  readonly requestFingerprintSha256: string;
  readonly screenedAtGlobalEpoch: number;
  readonly expectedTemplateGeneration: number; // 0 for initial enrollment, >0 for re-enrollment
  readonly allowReEnrollment: boolean;
  readonly decisionStatus: 'CLEAN_APPROVED' | 'DUPLICATE_WARNING_FLAGGED';
  readonly preSealedEnvelope: EncryptedBiometricEnvelopeV3;
  readonly auditTicket?: BiometricAuditTicketV3;
}

export interface TransactionalEnrollmentResultV18 {
  readonly status: TransactionCommitStatusV18;
  readonly committedGlobalEpoch: number;
  readonly latestGlobalEpoch: number;
  readonly templateGeneration: number;
  readonly decisionStatus?: DuplicateScreeningDecisionStatus;
  readonly auditTicketId?: string;
  readonly releaseStatus: typeof RELEASE_STATUS;
  readonly calibrationApproved: typeof PRODUCTION_BIOMETRIC_CALIBRATION_APPROVED;
}

/**
 * Production Firestore Transactional Persistence Adapter implementing Phase 2, 3, and 4 invariants:
 * - Strict Read-Before-Write inside `db.runTransaction`
 * - Idempotency key reservation & payload fingerprint mismatch detection
 * - Search-to-Commit Epoch Fencing (`screenedAtGlobalEpoch === currentGlobalEpoch`)
 * - Per-UID `templateGeneration` fencing against stale overwrites
 * - Atomic WAL Outbox creation (`biometric_wal/{walSeq}`) for zero-loss multi-node replication
 */
export class FirestoreBiometricTransactionAdapterV18 {
  public static readonly META_COLLECTION = 'biometric_cluster_meta';
  public static readonly META_DOC_ID = 'global_state';
  public static readonly VAULT_COLLECTION = 'biometric_vault';
  public static readonly IDEMPOTENCY_COLLECTION = 'biometric_idempotency';
  public static readonly AUDIT_COLLECTION = 'biometric_audit_queue';
  public static readonly WAL_COLLECTION = 'biometric_wal_outbox';

  private readonly db: FirestoreDatabaseLike;
  private readonly clusterId: string;

  constructor(
    db: FirestoreDatabaseLike,
    clusterId = 'karnataka-kelasagaara-primary',
  ) {
    this.db = db;
    this.clusterId = clusterId;
  }

  /**
   * Atomically commits an enrollment or re-enrollment ONLY if:
   * 1. The idempotency key has not been used with a different payload.
   * 2. The global gallery epoch has not advanced since `screenedAtGlobalEpoch`
   *    (if it advanced, returns `RECHECK_REQUIRED_EPOCH_DRIFT` without mutating state).
   * 3. The user's `templateGeneration` matches `expectedTemplateGeneration`.
   */
  public async commitEnrollmentTransactionally(
    input: TransactionalEnrollmentInputV18,
  ): Promise<TransactionalEnrollmentResultV18> {
    if (!input.uid || !input.idempotencyKey || !input.requestFingerprintSha256) {
      throw new Error(
        'INVALID_TRANSACTION_INPUT: uid, idempotencyKey, and requestFingerprintSha256 are required.',
      );
    }
    if (
      input.preSealedEnvelope.modelId !== CANONICAL_SFACE_MODEL_ID ||
      input.preSealedEnvelope.modelVersion !== CANONICAL_SFACE_MODEL_VERSION ||
      input.preSealedEnvelope.schemaVersion !== CANONICAL_TEMPLATE_SCHEMA_VERSION
    ) {
      throw new Error(
        'INCOMPATIBLE_ENVELOPE_IN_TX: Only canonical 128-D SFace v3 envelopes may be committed.',
      );
    }

    const metaRef = this.db
      .collection<ClusterEpochMetaDocV18>(
        FirestoreBiometricTransactionAdapterV18.META_COLLECTION,
      )
      .doc(FirestoreBiometricTransactionAdapterV18.META_DOC_ID);

    const idemRef = this.db
      .collection<IdempotencyRecordDocV18>(
        FirestoreBiometricTransactionAdapterV18.IDEMPOTENCY_COLLECTION,
      )
      .doc(input.idempotencyKey);

    const vaultRef = this.db
      .collection<VaultRecordDocV18>(
        FirestoreBiometricTransactionAdapterV18.VAULT_COLLECTION,
      )
      .doc(input.uid);

    return this.db.runTransaction(
      async (tx) => {
        // ====================================================================
        // STEP 1: READ PHASE (All reads MUST complete before any write)
        // ====================================================================
        const [metaSnap, idemSnap, vaultSnap] = await Promise.all([
          tx.get(metaRef),
          tx.get(idemRef),
          tx.get(vaultRef),
        ]);

        const currentEpoch = metaSnap.exists
          ? (metaSnap.data()?.globalEpoch ?? 0)
          : 0;

        // 1A. Check Idempotency Reservation
        if (idemSnap.exists) {
          const existingIdem = idemSnap.data()!;
          if (
            existingIdem.uid !== input.uid ||
            existingIdem.requestFingerprintSha256 !==
              input.requestFingerprintSha256
          ) {
            return {
              status: 'CONFLICT_IDEMPOTENCY_PAYLOAD_MISMATCH',
              committedGlobalEpoch: existingIdem.committedGlobalEpoch,
              latestGlobalEpoch: currentEpoch,
              templateGeneration: existingIdem.templateGeneration,
              releaseStatus: RELEASE_STATUS,
              calibrationApproved: PRODUCTION_BIOMETRIC_CALIBRATION_APPROVED,
            };
          }

          return {
            status: 'IDEMPOTENT_REPLAY',
            committedGlobalEpoch: existingIdem.committedGlobalEpoch,
            latestGlobalEpoch: currentEpoch,
            templateGeneration: existingIdem.templateGeneration,
            decisionStatus:
              existingIdem.outcomeStatus as DuplicateScreeningDecisionStatus,
            auditTicketId: existingIdem.auditTicketId,
            releaseStatus: RELEASE_STATUS,
            calibrationApproved: PRODUCTION_BIOMETRIC_CALIBRATION_APPROVED,
          };
        }

        // 1B. Check Per-UID Template Generation Fence
        const existingVault = vaultSnap.exists ? vaultSnap.data() : undefined;
        const isCurrentlyActive =
          existingVault !== undefined && existingVault.status !== 'ERASED';
        const currentGen = existingVault?.templateGeneration ?? 0;

        if (isCurrentlyActive && !input.allowReEnrollment) {
          return {
            status: 'CONFLICT_ALREADY_ENROLLED',
            committedGlobalEpoch: -1,
            latestGlobalEpoch: currentEpoch,
            templateGeneration: currentGen,
            releaseStatus: RELEASE_STATUS,
            calibrationApproved: PRODUCTION_BIOMETRIC_CALIBRATION_APPROVED,
          };
        }

        if (currentGen !== input.expectedTemplateGeneration) {
          return {
            status: 'CONFLICT_STALE_GENERATION',
            committedGlobalEpoch: -1,
            latestGlobalEpoch: currentEpoch,
            templateGeneration: currentGen,
            releaseStatus: RELEASE_STATUS,
            calibrationApproved: PRODUCTION_BIOMETRIC_CALIBRATION_APPROVED,
          };
        }

        // 1C. Phase 4 Mandatory Check: Search-to-Commit Epoch Fence
        // If another enrollment or re-enrollment committed after this request ran 1:N search,
        // halt before writing and instruct the coordinator to re-screen against the updated gallery.
        if (currentEpoch !== input.screenedAtGlobalEpoch) {
          return {
            status: 'RECHECK_REQUIRED_EPOCH_DRIFT',
            committedGlobalEpoch: -1,
            latestGlobalEpoch: currentEpoch,
            templateGeneration: currentGen,
            releaseStatus: RELEASE_STATUS,
            calibrationApproved: PRODUCTION_BIOMETRIC_CALIBRATION_APPROVED,
          };
        }

        // ====================================================================
        // STEP 2: WRITE PHASE (Atomic Mutation of Vault, Epoch, Idempotency & WAL)
        // ====================================================================
        const nextEpoch = currentEpoch + 1;
        const nextGeneration = currentGen + 1;
        const nowMs = Date.now();
        const vaultStatus =
          input.decisionStatus === 'DUPLICATE_WARNING_FLAGGED'
            ? 'PENDING_AUDIT'
            : 'ACTIVE';

        const newVaultDoc: VaultRecordDocV18 = {
          uid: input.uid,
          tenantId: input.tenantId,
          maskedPhone: input.maskedPhone,
          modelId: CANONICAL_SFACE_MODEL_ID,
          modelVersion: CANONICAL_SFACE_MODEL_VERSION,
          templateSchemaVersion: CANONICAL_TEMPLATE_SCHEMA_VERSION,
          status: vaultStatus,
          envelope: input.preSealedEnvelope,
          idempotencyKey: input.idempotencyKey,
          templateGeneration: nextGeneration,
          committedAtGlobalEpoch: nextEpoch,
          updatedAtEpochMs: nowMs,
        };

        const newMetaDoc: ClusterEpochMetaDocV18 = {
          clusterId: this.clusterId,
          globalEpoch: nextEpoch,
          lastMutatedUid: input.uid,
          lastMutationType: isCurrentlyActive ? 'RE_ENROLL' : 'ENROLL',
          updatedAtEpochMs: nowMs,
        };

        const newIdemDoc: IdempotencyRecordDocV18 = {
          idempotencyKey: input.idempotencyKey,
          uid: input.uid,
          operationType: isCurrentlyActive ? 'RE_ENROLL' : 'ENROLL',
          requestFingerprintSha256: input.requestFingerprintSha256,
          outcomeStatus: input.decisionStatus,
          committedGlobalEpoch: nextEpoch,
          templateGeneration: nextGeneration,
          auditTicketId: input.auditTicket?.ticketId,
          createdAtEpochMs: nowMs,
        };

        const walDocRef = this.db
          .collection<TransactionalWalEntryDocV18>(
            FirestoreBiometricTransactionAdapterV18.WAL_COLLECTION,
          )
          .doc(String(nextEpoch).padStart(12, '0'));

        const walEntry: TransactionalWalEntryDocV18 = {
          walSeq: nextEpoch,
          uid: input.uid,
          maskedPhone: input.maskedPhone,
          operation: 'UPSERT',
          templateGeneration: nextGeneration,
          modelId: CANONICAL_SFACE_MODEL_ID,
          modelVersion: CANONICAL_SFACE_MODEL_VERSION,
          templateSchemaVersion: CANONICAL_TEMPLATE_SCHEMA_VERSION,
          envelope: input.preSealedEnvelope,
          committedAtEpochMs: nowMs,
        };

        tx.set(vaultRef, newVaultDoc);
        tx.set(metaRef, newMetaDoc);
        tx.set(idemRef, newIdemDoc);
        tx.set(walDocRef, walEntry);

        if (input.auditTicket) {
          const auditRef = this.db
            .collection<BiometricAuditTicketV3>(
              FirestoreBiometricTransactionAdapterV18.AUDIT_COLLECTION,
            )
            .doc(input.auditTicket.ticketId);
          tx.set(auditRef, input.auditTicket);
        }

        return {
          status: 'COMMITTED_NEW',
          committedGlobalEpoch: nextEpoch,
          latestGlobalEpoch: nextEpoch,
          templateGeneration: nextGeneration,
          decisionStatus: input.decisionStatus,
          auditTicketId: input.auditTicket?.ticketId,
          releaseStatus: RELEASE_STATUS,
          calibrationApproved: PRODUCTION_BIOMETRIC_CALIBRATION_APPROVED,
        };
      },
      { maxAttempts: 5 },
    );
  }

  /**
   * Atomically erases a worker's biometric record (India DPDPA 2023 §12), increments the
   * template generation tombstone so stale in-flight requests cannot resurrect it,
   * and appends a TOMBSTONE entry to the transactional WAL.
   */
  public async commitErasureTransactionally(params: {
    readonly uid: string;
    readonly idempotencyKey: string;
  }): Promise<{
    readonly erased: boolean;
    readonly committedGlobalEpoch: number;
    readonly newGeneration: number;
  }> {
    const metaRef = this.db
      .collection<ClusterEpochMetaDocV18>(
        FirestoreBiometricTransactionAdapterV18.META_COLLECTION,
      )
      .doc(FirestoreBiometricTransactionAdapterV18.META_DOC_ID);

    const vaultRef = this.db
      .collection<VaultRecordDocV18>(
        FirestoreBiometricTransactionAdapterV18.VAULT_COLLECTION,
      )
      .doc(params.uid);

    const idemRef = this.db
      .collection<IdempotencyRecordDocV18>(
        FirestoreBiometricTransactionAdapterV18.IDEMPOTENCY_COLLECTION,
      )
      .doc(params.idempotencyKey);

    return this.db.runTransaction(async (tx) => {
      const [metaSnap, vaultSnap, idemSnap] = await Promise.all([
        tx.get(metaRef),
        tx.get(vaultRef),
        tx.get(idemRef),
      ]);

      const currentEpoch = metaSnap.exists
        ? (metaSnap.data()?.globalEpoch ?? 0)
        : 0;

      if (idemSnap.exists) {
        const existingIdem = idemSnap.data()!;
        return {
          erased: true,
          committedGlobalEpoch: existingIdem.committedGlobalEpoch,
          newGeneration: existingIdem.templateGeneration,
        };
      }

      if (!vaultSnap.exists || vaultSnap.data()?.status === 'ERASED') {
        return {
          erased: false,
          committedGlobalEpoch: currentEpoch,
          newGeneration: vaultSnap.data()?.templateGeneration ?? 0,
        };
      }

      const prevDoc = vaultSnap.data()!;
      const nextEpoch = currentEpoch + 1;
      const nextGen = prevDoc.templateGeneration + 1;
      const nowMs = Date.now();

      const walDocRef = this.db
        .collection<TransactionalWalEntryDocV18>(
          FirestoreBiometricTransactionAdapterV18.WAL_COLLECTION,
        )
        .doc(String(nextEpoch).padStart(12, '0'));

      // Delete ciphertext document from active vault and record tombstone in WAL + Meta
      tx.delete(vaultRef);
      tx.set(metaRef, {
        clusterId: this.clusterId,
        globalEpoch: nextEpoch,
        lastMutatedUid: params.uid,
        lastMutationType: 'ERASE',
        updatedAtEpochMs: nowMs,
      });
      tx.set(idemRef, {
        idempotencyKey: params.idempotencyKey,
        uid: params.uid,
        operationType: 'ERASE',
        requestFingerprintSha256: `ERASE:${params.uid}`,
        outcomeStatus: 'ERASED_SUCCESS',
        committedGlobalEpoch: nextEpoch,
        templateGeneration: nextGen,
        createdAtEpochMs: nowMs,
      });
      tx.set(walDocRef, {
        walSeq: nextEpoch,
        uid: params.uid,
        maskedPhone: 'REDACTED',
        operation: 'TOMBSTONE',
        templateGeneration: nextGen,
        modelId: CANONICAL_SFACE_MODEL_ID,
        modelVersion: CANONICAL_SFACE_MODEL_VERSION,
        templateSchemaVersion: CANONICAL_TEMPLATE_SCHEMA_VERSION,
        committedAtEpochMs: nowMs,
      });

      return {
        erased: true,
        committedGlobalEpoch: nextEpoch,
        newGeneration: nextGen,
      };
    });
  }

  /**
   * Fetches incremental WAL entries strictly greater than `sinceWalSeq` so replica nodes
   * can catch up in milliseconds on `RECHECK_REQUIRED_EPOCH_DRIFT` without scanning the full vault.
   */
  public async fetchIncrementalWalSince(
    sinceWalSeq: number,
  ): Promise<readonly TransactionalWalEntryDocV18[]> {
    const snap = await this.db
      .collection<TransactionalWalEntryDocV18>(
        FirestoreBiometricTransactionAdapterV18.WAL_COLLECTION,
      )
      .where('walSeq', '>', sinceWalSeq)
      .get();

    return snap.docs
      .map((d) => d.data()!)
      .filter((d) => d !== undefined)
      .sort((a, b) => a.walSeq - b.walSeq);
  }

  /**
   * Persists a duplicate inquiry / investigation ticket to `biometric_audit_queue`
   * when 1:N screening halts on a suspected duplicate, creating a reversible case.
   */
  public async recordDuplicateInvestigationTicket(
    ticket: BiometricAuditTicketV3,
  ): Promise<void> {
    const auditRef = this.db
      .collection<BiometricAuditTicketV3>(
        FirestoreBiometricTransactionAdapterV18.AUDIT_COLLECTION,
      )
      .doc(ticket.ticketId);
    await auditRef.set(ticket);
  }
}
