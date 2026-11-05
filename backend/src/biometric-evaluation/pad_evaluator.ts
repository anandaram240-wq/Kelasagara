/**
 * backend/src/biometric-evaluation/pad_evaluator.ts
 *
 * Evaluates Presentation Attack Detection (PAD) according to ISO/IEC 30107-3:2023:
 * - APCER: Attack Presentation Classification Error Rate (Spoofs accepted as live).
 * - BPCER: Bona Fide Presentation Classification Error Rate (Live users rejected as spoof).
 * - Attack Instrument Species: Printed photo, Phone screen, High-res monitor, Video replay.
 * - Separates software API injection / replay from optical presentation attacks.
 */

export type AttackInstrumentSpecies =
  | 'PRINTED_PHOTO_MATTE'
  | 'PRINTED_PHOTO_GLOSSY'
  | 'SCREEN_REPLAY_SMARTPHONE'
  | 'SCREEN_REPLAY_TABLET'
  | 'SCREEN_REPLAY_4K_MONITOR'
  | 'PRE_RECORDED_VIDEO_LOOP'
  | 'SYNTHETIC_DEEPFAKE_REPLAY'
  | 'PARTIAL_FACIAL_CUTOUT';

export interface PadPresentationAttempt {
  readonly attemptId: string;
  readonly isBonaFide: boolean; // Ground truth: true = genuine live presentation; false = presentation attack
  readonly attackSpecies?: AttackInstrumentSpecies;
  readonly captureLighting: string;
  readonly displayBrightness?: number;
  // Output from PAD engines (ChallengeBurstPadService + TemporalPadValidator + PadLivenessFiqaGuardV11)
  readonly classifiedAsLive: boolean;
  readonly livenessScore: number;
  readonly rejectionReason?: string;
}

export interface AttackSpeciesSummary {
  readonly species: AttackInstrumentSpecies;
  readonly totalAttempts: number;
  readonly falseAccepts: number; // Attack accepted as live
  readonly apcer: number;
}

export interface PadEvaluationSummary {
  readonly totalPresentations: number;
  readonly bonaFideCount: number;
  readonly attackCount: number;
  readonly bonaFideRejections: number; // Genuine user classified as attack
  readonly bpcer: number; // BPCER = bonaFideRejections / bonaFideCount
  readonly attackAccepts: number; // Attack classified as live
  readonly apcer: number; // APCER = attackAccepts / attackCount
  readonly speciesBreakdown: readonly AttackSpeciesSummary[];
  readonly passDecisionParameters: {
    readonly minOpenEar: number;
    readonly maxClosedRatio: number;
    readonly minAnchorCosine: number;
    readonly maxLumaFlux: number;
  };
}

export class PadEvaluator {
  public static evaluateAttempts(
    attempts: readonly PadPresentationAttempt[]
  ): PadEvaluationSummary {
    let bonaFideTotal = 0;
    let bonaFideRejections = 0;
    let attackTotal = 0;
    let attackAccepts = 0;

    const speciesMap = new Map<AttackInstrumentSpecies, { total: number; accepts: number }>();

    for (const a of attempts) {
      if (a.isBonaFide) {
        bonaFideTotal++;
        if (!a.classifiedAsLive) {
          bonaFideRejections++;
        }
      } else {
        attackTotal++;
        if (a.classifiedAsLive) {
          attackAccepts++;
        }
        if (a.attackSpecies) {
          if (!speciesMap.has(a.attackSpecies)) {
            speciesMap.set(a.attackSpecies, { total: 0, accepts: 0 });
          }
          const entry = speciesMap.get(a.attackSpecies)!;
          entry.total++;
          if (a.classifiedAsLive) {
            entry.accepts++;
          }
        }
      }
    }

    const speciesBreakdown: AttackSpeciesSummary[] = [];
    for (const [species, data] of speciesMap.entries()) {
      speciesBreakdown.push({
        species,
        totalAttempts: data.total,
        falseAccepts: data.accepts,
        apcer: data.total > 0 ? Number((data.accepts / data.total).toFixed(4)) : 0.0,
      });
    }

    return {
      totalPresentations: attempts.length,
      bonaFideCount: bonaFideTotal,
      attackCount: attackTotal,
      bonaFideRejections,
      bpcer: bonaFideTotal > 0 ? Number((bonaFideRejections / bonaFideTotal).toFixed(4)) : 0.0,
      attackAccepts,
      apcer: attackTotal > 0 ? Number((attackAccepts / attackTotal).toFixed(4)) : 0.0,
      speciesBreakdown,
      passDecisionParameters: {
        minOpenEar: 0.22,
        maxClosedRatio: 0.65,
        minAnchorCosine: 0.80,
        maxLumaFlux: 0.15,
      },
    };
  }
}
