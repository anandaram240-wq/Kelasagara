/**
 * backend/src/biometric-evaluation/participant_split_validator.ts
 *
 * Enforces strict scientific subject-level isolation between:
 * - Dataset A: Development
 * - Dataset B: Calibration
 * - Dataset C: Holdout
 *
 * Invariant: Zero subject overlap, zero session leakage, zero frame cross-contamination.
 */

import { DatasetManifest, DatasetPartition } from './dataset_manifest';

export interface SplitValidationResult {
  readonly isValid: boolean;
  readonly partitionSubjectCounts: Record<DatasetPartition, number>;
  readonly partitionSampleCounts: Record<DatasetPartition, number>;
  readonly crossPartitionLeakingSubjects: readonly string[];
  readonly orphanSamples: readonly string[];
  readonly errors: readonly string[];
}

export class ParticipantSplitValidator {
  public static validatePartitionIntegrity(manifest: DatasetManifest): SplitValidationResult {
    const errors: string[] = [];
    const partitionSubjectCounts: Record<DatasetPartition, number> = {
      DEVELOPMENT_A: 0,
      CALIBRATION_B: 0,
      HOLDOUT_C: 0,
    };
    const partitionSampleCounts: Record<DatasetPartition, number> = {
      DEVELOPMENT_A: 0,
      CALIBRATION_B: 0,
      HOLDOUT_C: 0,
    };

    const participantPartitionMap = new Map<string, DatasetPartition>();
    const seenSubjectsPerPartition: Record<DatasetPartition, Set<string>> = {
      DEVELOPMENT_A: new Set(),
      CALIBRATION_B: new Set(),
      HOLDOUT_C: new Set(),
    };

    // 1. Audit Participant Registry
    for (const p of manifest.participants) {
      if (participantPartitionMap.has(p.participantId)) {
        errors.push(`DUPLICATE_PARTICIPANT_DECLARATION: Subject ${p.participantId} declared multiple times`);
      }
      participantPartitionMap.set(p.participantId, p.partition);
      seenSubjectsPerPartition[p.partition].add(p.participantId);
    }

    partitionSubjectCounts.DEVELOPMENT_A = seenSubjectsPerPartition.DEVELOPMENT_A.size;
    partitionSubjectCounts.CALIBRATION_B = seenSubjectsPerPartition.CALIBRATION_B.size;
    partitionSubjectCounts.HOLDOUT_C = seenSubjectsPerPartition.HOLDOUT_C.size;

    // 2. Cross-Partition Subject Overlap Check (Subject Leakage)
    const leakingSubjects: string[] = [];
    const sets = [
      { name: 'DEV vs CALIB', s1: seenSubjectsPerPartition.DEVELOPMENT_A, s2: seenSubjectsPerPartition.CALIBRATION_B },
      { name: 'DEV vs HOLDOUT', s1: seenSubjectsPerPartition.DEVELOPMENT_A, s2: seenSubjectsPerPartition.HOLDOUT_C },
      { name: 'CALIB vs HOLDOUT', s1: seenSubjectsPerPartition.CALIBRATION_B, s2: seenSubjectsPerPartition.HOLDOUT_C },
    ];

    for (const { name, s1, s2 } of sets) {
      for (const subj of s1) {
        if (s2.has(subj)) {
          leakingSubjects.push(subj);
          errors.push(`CRITICAL_PARTITION_LEAKAGE (${name}): Subject ${subj} appears in multiple partitions`);
        }
      }
    }

    // 3. Sample-to-Partition Alignment Audit
    const orphanSamples: string[] = [];
    for (const sample of manifest.samples) {
      const declaredPartition = participantPartitionMap.get(sample.participantId);
      if (!declaredPartition) {
        orphanSamples.push(sample.sampleId);
        errors.push(`ORPHAN_SAMPLE: Sample ${sample.sampleId} references undeclared subject ${sample.participantId}`);
        continue;
      }

      if (sample.partition !== declaredPartition) {
        errors.push(
          `SAMPLE_PARTITION_MISMATCH: Sample ${sample.sampleId} tagged as ${sample.partition} but subject ${sample.participantId} belongs to ${declaredPartition}`
        );
      }
      partitionSampleCounts[sample.partition]++;
    }

    return {
      isValid: errors.length === 0,
      partitionSubjectCounts,
      partitionSampleCounts,
      crossPartitionLeakingSubjects: leakingSubjects,
      orphanSamples,
      errors,
    };
  }
}
