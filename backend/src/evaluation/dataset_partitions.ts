// backend/src/evaluation/dataset_partitions.ts
/**
 * Partition Management & Lockbox Governance Engine (Ticket G-02).
 * Enforces strict zero-identity overlap between TUNE, VALIDATE, and LOCKBOX.
 * Tracks and logs single-access lockbox evaluation with pre-committed SHA-256 manifests.
 */

import crypto from "crypto";

export type PartitionType = "TUNE" | "VALIDATE" | "LOCKBOX";

export interface SubjectMetadata {
  subjectId: string;
  partition: PartitionType;
  demographicGroup?: string;
  qualityScore?: number;
}

export interface PartitionManifest {
  manifestId: string;
  sha256Hash: string;
  totalIdentities: number;
  tuneCount: number;
  validateCount: number;
  lockboxCount: number;
  generatedAt: string;
}

export class DatasetPartitionManager {
  private static lockboxAccessed = false;
  private static lockboxAccessLog: { timestamp: number; caller: string; manifestHash: string }[] = [];

  /**
   * Asserts that identity sets have ZERO intersection across partitions (Invariant I-32).
   */
  static validateZeroOverlap(
    tuneIds: string[],
    validateIds: string[],
    lockboxIds: string[]
  ): { isValid: boolean; overlapDetails?: string } {
    const tuneSet = new Set(tuneIds);
    const valSet = new Set(validateIds);
    const lockSet = new Set(lockboxIds);

    for (const id of tuneIds) {
      if (valSet.has(id)) {
        return { isValid: false, overlapDetails: `Identity collision between TUNE and VALIDATE: ${id}` };
      }
      if (lockSet.has(id)) {
        return { isValid: false, overlapDetails: `Identity collision between TUNE and LOCKBOX: ${id}` };
      }
    }

    for (const id of validateIds) {
      if (lockSet.has(id)) {
        return { isValid: false, overlapDetails: `Identity collision between VALIDATE and LOCKBOX: ${id}` };
      }
    }

    return { isValid: true };
  }

  /**
   * Computes SHA-256 manifest hash of partitioned identity manifest.
   */
  static computeManifestHash(subjects: SubjectMetadata[]): string {
    const sorted = [...subjects].sort((a, b) => a.subjectId.localeCompare(b.subjectId));
    const serialized = JSON.stringify(sorted);
    return crypto.createHash("sha256").update(serialized).digest("hex");
  }

  /**
   * Evaluates LOCKBOX partition under strict one-time access discipline.
   * Throws an invariant violation error if accessed more than once!
   */
  static accessLockbox(caller: string, manifestHash: string): void {
    if (this.lockboxAccessed) {
      throw new Error(
        `[PartitionManager] Invariant Violation: LOCKBOX partition has already been unlocked and accessed! ` +
        `Single-access discipline forbids repeated evaluation to prevent p-hacking.`
      );
    }

    this.lockboxAccessed = true;
    this.lockboxAccessLog.push({
      timestamp: Date.now(),
      caller,
      manifestHash,
    });
    console.log(`[PartitionManager] LOCKBOX unlocked by '${caller}'. Manifest: ${manifestHash}`);
  }

  /**
   * Checks whether lockbox has been accessed.
   */
  static isLockboxAccessed(): boolean {
    return this.lockboxAccessed;
  }

  /**
   * Deterministically assigns a subject to TUNE (40%), VALIDATE (40%), or LOCKBOX (20%).
   */
  static assignPartition(subjectId: string): PartitionType {
    const hash = crypto.createHash("md5").update(subjectId).digest("hex");
    const intVal = parseInt(hash.substring(0, 4), 16) % 100;
    if (intVal < 40) return "TUNE";
    if (intVal < 80) return "VALIDATE";
    return "LOCKBOX";
  }

  /**
   * Resets partition manager state (test isolation only).
   */
  static resetForTesting(): void {
    this.lockboxAccessed = false;
    this.lockboxAccessLog = [];
  }
}
