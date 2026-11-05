/**
 * backend/src/biometric-evaluation/one_to_n_evaluator.ts
 *
 * Evaluates 1:N Identification and Deduplication according to ISO/IEC 19795-1:
 * - FPIR (False Positive Identification Rate): Non-enrolled person falsely flagged as duplicate.
 * - FNIR (False Negative Identification Rate): Enrolled duplicate candidate missed.
 * - Rank-1 and Rank-K Identification Rates.
 * - Gallery scalability and decision boundary evaluation (0.74 warning, 0.78 / 0.90 block).
 */

import { cosineSimilarity } from '../services/biometric_matching';

export interface GalleryEntry {
  readonly personId: string;
  readonly owningUid: string;
  readonly embedding: number[] | Float32Array;
  readonly epoch: number;
}

export interface IdentificationProbe {
  readonly probeId: string;
  readonly truePersonId?: string; // If null, genuine new person not in gallery
  readonly embedding: number[] | Float32Array;
}

export interface CandidateHit {
  readonly personId: string;
  readonly owningUid: string;
  readonly similarity: number;
  readonly rank: number;
}

export interface IdentificationResult {
  readonly probeId: string;
  readonly truePersonId?: string;
  readonly isEnrolledSubject: boolean;
  readonly topMatch?: CandidateHit;
  readonly candidates: readonly CandidateHit[];
  readonly decision: 'UNIQUE' | 'DUPLICATE_WARNING' | 'DUPLICATE_HARD_BLOCK';
  readonly isCorrect: boolean;
}

export interface OneToNSummary {
  readonly totalProbes: number;
  readonly enrolledProbes: number;
  readonly unenrolledProbes: number;
  readonly rank1CorrectCount: number;
  readonly rank1Rate: number; // Rank-1 identification accuracy
  readonly falsePositiveIdentifications: number; // Unenrolled flagged as duplicate
  readonly fpir: number; // FPIR
  readonly falseNegativeIdentifications: number; // Enrolled missed (classified as UNIQUE)
  readonly fnir: number; // FNIR
  readonly gallerySize: number;
}

export class OneToNEvaluator {
  public static readonly WARN_THRESHOLD = 0.74;
  public static readonly BLOCK_THRESHOLD = 0.78;
  public static readonly HARD_BLOCK_THRESHOLD = 0.90;

  public static searchGallery(
    probe: IdentificationProbe,
    gallery: readonly GalleryEntry[],
    k = 5
  ): IdentificationResult {
    const hits: CandidateHit[] = [];

    for (const entry of gallery) {
      const sim = cosineSimilarity(probe.embedding, entry.embedding);
      hits.push({
        personId: entry.personId,
        owningUid: entry.owningUid,
        similarity: Number(sim.toFixed(4)),
        rank: 0,
      });
    }

    hits.sort((a, b) => b.similarity - a.similarity);
    const topHits = hits.slice(0, k).map((h, idx) => ({ ...h, rank: idx + 1 }));
    const top = topHits.length > 0 ? topHits[0] : undefined;

    let decision: 'UNIQUE' | 'DUPLICATE_WARNING' | 'DUPLICATE_HARD_BLOCK' = 'UNIQUE';
    if (top) {
      if (top.similarity >= this.HARD_BLOCK_THRESHOLD) {
        decision = 'DUPLICATE_HARD_BLOCK';
      } else if (top.similarity >= this.BLOCK_THRESHOLD) {
        decision = 'DUPLICATE_HARD_BLOCK';
      } else if (top.similarity >= this.WARN_THRESHOLD) {
        decision = 'DUPLICATE_WARNING';
      }
    }

    const isEnrolled = !!probe.truePersonId;
    let isCorrect = false;

    if (isEnrolled) {
      // Correct if top match matches probe's true person ID and was flagged
      isCorrect = !!(top && top.personId === probe.truePersonId && decision !== 'UNIQUE');
    } else {
      // Correct if probe was classified as UNIQUE
      isCorrect = decision === 'UNIQUE';
    }

    return {
      probeId: probe.probeId,
      truePersonId: probe.truePersonId,
      isEnrolledSubject: isEnrolled,
      topMatch: top,
      candidates: topHits,
      decision,
      isCorrect,
    };
  }

  public static summarize(
    results: readonly IdentificationResult[],
    gallerySize: number
  ): OneToNSummary {
    let enrolledTotal = 0;
    let unenrolledTotal = 0;
    let rank1Correct = 0;
    let falsePositives = 0;
    let falseNegatives = 0;

    for (const r of results) {
      if (r.isEnrolledSubject) {
        enrolledTotal++;
        if (r.topMatch && r.topMatch.personId === r.truePersonId) {
          rank1Correct++;
        }
        if (r.decision === 'UNIQUE') {
          falseNegatives++;
        }
      } else {
        unenrolledTotal++;
        if (r.decision !== 'UNIQUE') {
          falsePositives++;
        }
      }
    }

    return {
      totalProbes: results.length,
      enrolledProbes: enrolledTotal,
      unenrolledProbes: unenrolledTotal,
      rank1CorrectCount: rank1Correct,
      rank1Rate: enrolledTotal > 0 ? Number((rank1Correct / enrolledTotal).toFixed(4)) : 1.0,
      falsePositiveIdentifications: falsePositives,
      fpir: unenrolledTotal > 0 ? Number((falsePositives / unenrolledTotal).toFixed(6)) : 0.0,
      falseNegativeIdentifications: falseNegatives,
      fnir: enrolledTotal > 0 ? Number((falseNegatives / enrolledTotal).toFixed(6)) : 0.0,
      gallerySize,
    };
  }
}
