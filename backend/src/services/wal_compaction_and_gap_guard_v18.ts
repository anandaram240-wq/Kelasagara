// File: backend/src/services/wal_compaction_and_gap_guard_v18.ts
// KELASAGARA V18 / PHASE 13.4 — Contiguous WAL Sequence Gap Guard & Watermark-Fenced Compactor
// Prevents silent split-brain when lagging nodes query a compacted WAL outbox.
// Release Posture: CONTROLLED_TEST_BUILD_ONLY | productionBiometricCalibrationApproved = false

import {
  FirestoreBiometricTransactionAdapterV18,
  FirestoreDatabaseLike,
  TransactionalWalEntryDocV18,
} from './firestore_transaction_adapter_v18';
import { KmsWrappedKs18SnapshotArtifact } from './transactional_gallery_coordinator_v18';

export interface WalCompactionPolicyConfigV18 {
  /**
   * Number of trailing WAL entries to retain BEFORE the verified snapshot watermark
   * so in-flight nodes slightly behind the snapshot can still catch up incrementally.
   */
  readonly retainSafetyWindowEntries: number;

  /**
   * Maximum number of expired WAL documents deleted per compaction pass.
   */
  readonly maxDeleteBatchSize: number;
}

export const DEFAULT_WAL_COMPACTION_POLICY_V18: WalCompactionPolicyConfigV18 = {
  retainSafetyWindowEntries: 100,
  maxDeleteBatchSize: 250,
} as const;

export interface WalCompactionReportV18 {
  readonly snapshotWatermarkWalSeq: number;
  readonly pruneUpToWalSeqInclusive: number;
  readonly deletedWalCount: number;
  readonly deletedWalSeqs: readonly number[];
  readonly skippedAboveCutoffCount: number;
}

/**
 * Verifies that a sequence of incremental WAL entries fetched since `localWatermarkEpoch`
 * is strictly contiguous with zero missing sequence numbers:
 *   deltas[0].walSeq === localWatermarkEpoch + 1
 *   deltas[i].walSeq === deltas[i - 1].walSeq + 1
 *
 * If any gap exists (e.g., because entries were compacted into a KS18 snapshot while
 * this instance was paused), throws `WAL_GAP_DETECTED_SNAPSHOT_REQUIRED` so the caller
 * never operates on an incomplete 1:N duplicate gallery.
 */
export function verifyContiguousWalSequence(
  localWatermarkEpoch: number,
  sortedDeltas: readonly TransactionalWalEntryDocV18[],
): void {
  if (sortedDeltas.length === 0) {
    return;
  }

  let expectedSeq = localWatermarkEpoch + 1;
  for (let i = 0; i < sortedDeltas.length; i++) {
    const actualSeq = sortedDeltas[i].walSeq;
    if (actualSeq !== expectedSeq) {
      throw new Error(
        `WAL_GAP_DETECTED_SNAPSHOT_REQUIRED: Expected contiguous walSeq ${expectedSeq} after watermark ${localWatermarkEpoch}, but received walSeq ${actualSeq}. Node must re-hydrate from latest KS18 snapshot.`,
      );
    }
    expectedSeq += 1;
  }
}

/**
 * Watermark-Fenced WAL Outbox Compactor.
 * Prunes historical `biometric_wal_outbox` records ONLY after a KMS-wrapped KS18 snapshot
 * has been generated and verified at `snapshotWatermarkWalSeq`, while preserving a trailing
 * safety window (`retainSafetyWindowEntries`).
 */
export class WalCompactorServiceV18 {
  private readonly db: FirestoreDatabaseLike;
  private readonly policy: WalCompactionPolicyConfigV18;

  constructor(
    db: FirestoreDatabaseLike,
    policy: WalCompactionPolicyConfigV18 = DEFAULT_WAL_COMPACTION_POLICY_V18,
  ) {
    if (policy.retainSafetyWindowEntries < 0) {
      throw new Error('INVALID_COMPACTION_POLICY: retainSafetyWindowEntries must be >= 0.');
    }
    if (policy.maxDeleteBatchSize <= 0) {
      throw new Error('INVALID_COMPACTION_POLICY: maxDeleteBatchSize must be > 0.');
    }
    this.db = db;
    this.policy = policy;
  }

  /**
   * Prunes WAL entries with `walSeq <= (snapshotWatermarkWalSeq - retainSafetyWindowEntries)`.
   * Refuses to compact if the snapshot artifact is invalid or has not advanced beyond the safety window.
   */
  public async compactWalBeforeVerifiedSnapshot(
    verifiedSnapshot: KmsWrappedKs18SnapshotArtifact,
  ): Promise<WalCompactionReportV18> {
    if (
      !verifiedSnapshot.wrappedSnapshotDekBase64 ||
      !verifiedSnapshot.kmsKeyVersionName ||
      verifiedSnapshot.bundle.formatMagic !== 'KS18'
    ) {
      throw new Error(
        'UNVERIFIED_SNAPSHOT_ARTIFACT: Cannot compact WAL without a valid KMS-wrapped KS18 snapshot.',
      );
    }

    const watermark = verifiedSnapshot.bundle.watermarkWalSeq;
    const cutoffSeq = watermark - this.policy.retainSafetyWindowEntries;

    if (cutoffSeq <= 0) {
      return {
        snapshotWatermarkWalSeq: watermark,
        pruneUpToWalSeqInclusive: 0,
        deletedWalCount: 0,
        deletedWalSeqs: [],
        skippedAboveCutoffCount: 0,
      };
    }

    const walCollection = this.db.collection<TransactionalWalEntryDocV18>(
      FirestoreBiometricTransactionAdapterV18.WAL_COLLECTION,
    );

    const candidateSnap = await walCollection
      .where('walSeq', '<=', cutoffSeq)
      .get();

    const candidates = candidateSnap.docs
      .map((d) => ({ docId: d.id, data: d.data() }))
      .filter(
        (item): item is { docId: string; data: TransactionalWalEntryDocV18 } =>
          item.data !== undefined,
      )
      .sort((a, b) => a.data.walSeq - b.data.walSeq);

    const deletedSeqs: number[] = [];
    let skippedCount = 0;

    for (const item of candidates) {
      if (deletedSeqs.length >= this.policy.maxDeleteBatchSize) {
        break;
      }
      // Double-check boundary invariant before deleting
      if (item.data.walSeq > cutoffSeq) {
        skippedCount += 1;
        continue;
      }

      await walCollection.doc(item.docId).delete();
      deletedSeqs.push(item.data.walSeq);
    }

    return {
      snapshotWatermarkWalSeq: watermark,
      pruneUpToWalSeqInclusive: cutoffSeq,
      deletedWalCount: deletedSeqs.length,
      deletedWalSeqs: deletedSeqs,
      skippedAboveCutoffCount: skippedCount,
    };
  }

  /**
   * Convenience helper to prune historical WAL entries directly by watermark seq.
   */
  public async compactWalEntriesBeforeWatermark(
    snapshotWatermarkWalSeq: number,
  ): Promise<WalCompactionReportV18> {
    const cutoffSeq = snapshotWatermarkWalSeq - this.policy.retainSafetyWindowEntries;

    if (cutoffSeq <= 0) {
      return {
        snapshotWatermarkWalSeq,
        pruneUpToWalSeqInclusive: 0,
        deletedWalCount: 0,
        deletedWalSeqs: [],
        skippedAboveCutoffCount: 0,
      };
    }

    const walCollection = this.db.collection<TransactionalWalEntryDocV18>(
      FirestoreBiometricTransactionAdapterV18.WAL_COLLECTION,
    );

    const candidateSnap = await walCollection
      .where('walSeq', '<=', cutoffSeq)
      .get();

    const candidates = candidateSnap.docs
      .map((d) => ({ docId: d.id, data: d.data() }))
      .filter(
        (item): item is { docId: string; data: TransactionalWalEntryDocV18 } =>
          item.data !== undefined,
      )
      .sort((a, b) => a.data.walSeq - b.data.walSeq);

    const deletedSeqs: number[] = [];
    let skippedCount = 0;

    for (const item of candidates) {
      if (deletedSeqs.length >= this.policy.maxDeleteBatchSize) {
        break;
      }
      if (item.data.walSeq > cutoffSeq) {
        skippedCount += 1;
        continue;
      }

      await walCollection.doc(item.docId).delete();
      deletedSeqs.push(item.data.walSeq);
    }

    return {
      snapshotWatermarkWalSeq,
      pruneUpToWalSeqInclusive: cutoffSeq,
      deletedWalCount: deletedSeqs.length,
      deletedWalSeqs: deletedSeqs,
      skippedAboveCutoffCount: skippedCount,
    };
  }
}
