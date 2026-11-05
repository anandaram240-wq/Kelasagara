// FILE: backend/src/biometrics/unified_biometric_pipeline_v18.ts

import {
  GroupCommitEpochSequencerV18,
  SequencerEnrollmentItem,
  SequencerItemOutcome,
  GroupCommitBatchTelemetry,
} from "./group_commit_epoch_sequencer_v18";
import {
  GcsWormAuditAnchorV18,
  WormBucketAnchorObject,
} from "./gcs_worm_audit_anchor_v18";
import { CloudKmsFailClosedGuardV18 } from "./cloud_kms_fail_closed_guard_v18";
import {
  PhysicalCameraCalibrationVerifierV18,
  OpticalFrameFiqaTelemetry,
} from "./physical_camera_calibration_verifier_v18";

export interface HttpEnrollmentSubmissionV18 {
  requestId: string;
  applicantUid: string;
  normalizedEmbedding128: Float32Array;
  opticalFiqa: OpticalFrameFiqaTelemetry;
}

export type UnifiedEnrollmentResponseV18 =
  | {
      httpStatus: 200;
      outcome: Extract<SequencerItemOutcome, { status: "COMMITTED" }>;
      wormAnchorPath: string;
      batchTelemetry: GroupCommitBatchTelemetry;
    }
  | {
      httpStatus: 409;
      outcome: Extract<
        SequencerItemOutcome,
        { status: "DUPLICATE_INVESTIGATION_PENDING" }
      >;
      wormAnchorPath: string;
      batchTelemetry: GroupCommitBatchTelemetry;
    }
  | {
      httpStatus: 422;
      status: "OPTICAL_FIQA_REJECTED";
      applicantUid: string;
      failureCode: string;
    };

interface PendingCoalescedItem {
  submission: HttpEnrollmentSubmissionV18;
  resolve: (res: UnifiedEnrollmentResponseV18) => void;
  reject: (err: Error) => void;
}

/**
 * Unifies all four Phase 17 subsystems (FIQA Verifier, Group-Commit Sequencer,
 * Fail-Closed Cloud KMS Guard, and GCS WORM Audit Anchor) with an automatic
 * asynchronous micro-batch coalescer for concurrent HTTP requests.
 */
export class UnifiedBiometricPipelineV18 {
  private readonly sequencer: GroupCommitEpochSequencerV18;
  private readonly wormAudit: GcsWormAuditAnchorV18;
  private readonly kmsGuard: CloudKmsFailClosedGuardV18;
  private readonly maxBatchSize: number;
  private readonly coalesceWindowMs: number;

  private pendingQueue: PendingCoalescedItem[] = [];
  private flushTimer: NodeJS.Timeout | null = null;
  private totalAuditEventsTracked = 0;
  private readonly sealedWormAnchors: WormBucketAnchorObject[] = [];

  constructor(params: {
    sequencer: GroupCommitEpochSequencerV18;
    wormAudit: GcsWormAuditAnchorV18;
    kmsGuard: CloudKmsFailClosedGuardV18;
    maxBatchSize?: number;
    coalesceWindowMs?: number;
  }) {
    this.sequencer = params.sequencer;
    this.wormAudit = params.wormAudit;
    this.kmsGuard = params.kmsGuard;
    this.maxBatchSize = params.maxBatchSize ?? 64;
    this.coalesceWindowMs = params.coalesceWindowMs ?? 4;
  }

  /**
   * Entrypoint for individual concurrent HTTP enrollment requests.
   * Automatically filters bad optical frames, checks KMS health, and coalesces
   * concurrent requests arriving within `coalesceWindowMs` into a single global
   * epoch batch commit with WORM audit sealing.
   */
  public async submitEnrollmentHttp(
    submission: HttpEnrollmentSubmissionV18
  ): Promise<UnifiedEnrollmentResponseV18> {
    // 1. Fail-Closed KMS Lockdown Gate (BLK-02 / Gate C)
    if (this.kmsGuard.getCircuitState() !== "HEALTHY") {
      throw new Error(
        "ERR_HSM_LOCKDOWN_ACTIVE: Pipeline halted and arena zeroized due to KMS security fault."
      );
    }

    // 2. ISO/IEC 29794-5 Optical FIQA Pre-Filter (BLK-01 / Gate H)
    // Rejects blurry, overexposed (>80,000 lux clipping), or ISP-smoothed frames before sequencer lock
    const fiqaVerdict =
      PhysicalCameraCalibrationVerifierV18.evaluateFrameOpticalQuality(
        submission.opticalFiqa
      );
    if (!fiqaVerdict.acceptable) {
      return {
        httpStatus: 422,
        status: "OPTICAL_FIQA_REJECTED",
        applicantUid: submission.applicantUid,
        failureCode: fiqaVerdict.failureCode ?? "ERR_OPTICAL_QUALITY_FAILED",
      };
    }

    // 3. Enqueue into Asynchronous Micro-Batch Coalescer (Gate F)
    return new Promise<UnifiedEnrollmentResponseV18>((resolve, reject) => {
      this.pendingQueue.push({ submission, resolve, reject });

      if (this.pendingQueue.length >= this.maxBatchSize) {
        if (this.flushTimer) {
          clearTimeout(this.flushTimer);
          this.flushTimer = null;
        }
        void this.flushMicroBatch();
      } else if (!this.flushTimer) {
        this.flushTimer = setTimeout(() => {
          this.flushTimer = null;
          void this.flushMicroBatch();
        }, this.coalesceWindowMs);
      }
    });
  }

  public getSealedWormAnchors(): WormBucketAnchorObject[] {
    return [...this.sealedWormAnchors];
  }

  private async flushMicroBatch(): Promise<void> {
    if (this.pendingQueue.length === 0) return;

    const batchToProcess = this.pendingQueue.splice(0, this.maxBatchSize);

    try {
      if (this.kmsGuard.getCircuitState() !== "HEALTHY") {
        throw new Error(
          "ERR_HSM_LOCKDOWN_ACTIVE: Cannot flush micro-batch while KMS is in lockdown."
        );
      }

      const sequencerItems: SequencerEnrollmentItem[] = batchToProcess.map(
        (entry) => ({
          requestId: entry.submission.requestId,
          applicantUid: entry.submission.applicantUid,
          normalizedEmbedding128: entry.submission.normalizedEmbedding128,
        })
      );

      // Execute single vectorized Group-Commit + All-Pairs Intra-Batch Deduplication
      const { outcomes, telemetry } =
        this.sequencer.executeGroupCommitBatch(sequencerItems);

      // Append hash-chained audit events and seal WORM Merkle anchor (BLK-03 / Gate D)
      const startSeq = this.totalAuditEventsTracked + 1;
      for (const entry of batchToProcess) {
        const outcome = outcomes.get(entry.submission.requestId)!;
        if (outcome.status === "COMMITTED") {
          this.wormAudit.appendEvent({
            eventType: "ENROLLMENT_COMMITTED",
            actorId: "UNIFIED_PIPELINE_V18",
            payloadObject: {
              requestId: entry.submission.requestId,
              applicantUid: outcome.applicantUid,
              committedEpoch: outcome.committedEpoch,
              walSequenceNumber: outcome.walSequenceNumber,
            },
          });
        } else {
          this.wormAudit.appendEvent({
            eventType: "DUPLICATE_INVESTIGATION_QUEUED",
            actorId: "UNIFIED_PIPELINE_V18",
            payloadObject: {
              requestId: entry.submission.requestId,
              auditTicketId: outcome.auditTicketId,
              collisionSource: outcome.collisionSource,
              existingAccountLocked: outcome.existingAccountLocked,
            },
          });
        }
        this.totalAuditEventsTracked += 1;
      }
      const endSeq = this.totalAuditEventsTracked;

      const wormAnchor = await this.wormAudit.sealAnchorToWormBucket(
        startSeq,
        endSeq
      );
      this.sealedWormAnchors.push(wormAnchor);

      // Resolve each individual HTTP caller's Promise with its specific outcome
      for (const entry of batchToProcess) {
        const outcome = outcomes.get(entry.submission.requestId)!;
        if (outcome.status === "COMMITTED") {
          entry.resolve({
            httpStatus: 200,
            outcome,
            wormAnchorPath: wormAnchor.objectPath,
            batchTelemetry: telemetry,
          });
        } else {
          entry.resolve({
            httpStatus: 409,
            outcome,
            wormAnchorPath: wormAnchor.objectPath,
            batchTelemetry: telemetry,
          });
        }
      }
    } catch (err: unknown) {
      const errorObj =
        err instanceof Error ? err : new Error("ERR_BATCH_FLUSH_FAILED");
      for (const entry of batchToProcess) {
        entry.reject(errorObj);
      }
    }
  }
}
