/**
 * backend/src/biometric-evaluation/genuine_pair_generator.ts
 *
 * Generates genuine (intra-subject) comparison pairs:
 * - Cross-session pairs (Session 0 vs Session 1, Session 0 vs Session 2).
 * - Environmental variation pairs (Indoor vs Outdoor, Normal vs Low Light).
 * - Camera variation pairs (Entry 720p vs Flagship 4K).
 * - Ensures zero cross-subject contamination.
 */

import { CaptureSample } from './dataset_manifest';

export interface ComparisonPair {
  readonly pairId: string;
  readonly sampleA: CaptureSample;
  readonly sampleB: CaptureSample;
  readonly subjectIdA: string;
  readonly subjectIdB: string;
  readonly isGenuine: boolean;
  readonly isCrossSession: boolean;
  readonly isCrossCamera: boolean;
  readonly isCrossLighting: boolean;
}

export class GenuinePairGenerator {
  public static generatePairs(samples: readonly CaptureSample[]): readonly ComparisonPair[] {
    const pairs: ComparisonPair[] = [];
    // Group samples by subject
    const subjectMap = new Map<string, CaptureSample[]>();
    for (const s of samples) {
      if (!subjectMap.has(s.participantId)) {
        subjectMap.set(s.participantId, []);
      }
      subjectMap.get(s.participantId)!.push(s);
    }

    let pairIdSeq = 1;
    for (const [subjId, list] of subjectMap.entries()) {
      for (let i = 0; i < list.length; i++) {
        for (let j = i + 1; j < list.length; j++) {
          const sA = list[i];
          const sB = list[j];

          // To avoid redundant frame correlations within the exact same burst session,
          // prioritize cross-session comparisons or distinct session bursts.
          const crossSession = sA.sessionIndex !== sB.sessionIndex;
          const crossCamera = sA.camera !== sB.camera;
          const crossLighting = sA.lighting !== sB.lighting;

          pairs.push({
            pairId: `GEN-${String(pairIdSeq++).padStart(6, '0')}`,
            sampleA: sA,
            sampleB: sB,
            subjectIdA: subjId,
            subjectIdB: subjId,
            isGenuine: true,
            isCrossSession: crossSession,
            isCrossCamera: crossCamera,
            isCrossLighting: crossLighting,
          });
        }
      }
    }
    return pairs;
  }
}
