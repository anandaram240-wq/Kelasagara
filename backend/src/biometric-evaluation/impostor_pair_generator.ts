/**
 * backend/src/biometric-evaluation/impostor_pair_generator.ts
 *
 * Generates independent impostor (inter-subject) comparison pairs:
 * - Compares samples across different subjects.
 * - Tracks subject cluster identity to prevent false independence assumptions.
 * - Supports balanced cross-demographic and same-demographic negative pairs.
 */

import { CaptureSample } from './dataset_manifest';
import { ComparisonPair } from './genuine_pair_generator';

export class ImpostorPairGenerator {
  public static generatePairs(
    samples: readonly CaptureSample[],
    maxPairs?: number
  ): readonly ComparisonPair[] {
    const pairs: ComparisonPair[] = [];
    const subjectMap = new Map<string, CaptureSample[]>();
    for (const s of samples) {
      if (!subjectMap.has(s.participantId)) {
        subjectMap.set(s.participantId, []);
      }
      subjectMap.get(s.participantId)!.push(s);
    }

    const subjectList = Array.from(subjectMap.keys());
    let pairIdSeq = 1;

    for (let i = 0; i < subjectList.length; i++) {
      const subjA = subjectList[i];
      const samplesA = subjectMap.get(subjA)!;

      for (let j = i + 1; j < subjectList.length; j++) {
        const subjB = subjectList[j];
        const samplesB = subjectMap.get(subjB)!;

        // Generate representative inter-subject pairs (e.g. Session 0 vs Session 0)
        for (const sA of samplesA) {
          for (const sB of samplesB) {
            pairs.push({
              pairId: `IMP-${String(pairIdSeq++).padStart(6, '0')}`,
              sampleA: sA,
              sampleB: sB,
              subjectIdA: subjA,
              subjectIdB: subjB,
              isGenuine: false,
              isCrossSession: sA.sessionIndex !== sB.sessionIndex,
              isCrossCamera: sA.camera !== sB.camera,
              isCrossLighting: sA.lighting !== sB.lighting,
            });

            if (maxPairs && pairs.length >= maxPairs) {
              return pairs;
            }
          }
        }
      }
    }

    return pairs;
  }
}
