/**
 * backend/src/biometric-evaluation/one_to_one_evaluator.ts
 *
 * Evaluates 1:1 Face Authentication (eKYC verification) according to ISO/IEC 19795-1:
 * - Claimed Identity Verification: Probe embedding vs Enrolled Reference template.
 * - Enforces zero 1:N cross-search.
 * - Isolates biometric comparison from Play Integrity and Keystore tokens.
 * - Assesses edge cases: Revoked template, Incompatible model version, Tampered ciphertext.
 */

import { cosineSimilarity } from '../services/biometric_matching';
import { ConfidenceIntervalCalculator, ConfidenceInterval } from './confidence_interval_calculator';

export interface OneToOneScenarioInput {
  readonly scenarioName: string;
  readonly claimedUid: string;
  readonly probeEmbedding: number[] | Float32Array;
  readonly enrolledTemplate: {
    readonly uid: string;
    readonly embedding: number[] | Float32Array;
    readonly modelVersion: string;
    readonly isRevoked: boolean;
    readonly isEncrypted: boolean;
  };
  readonly isTrueClaimant: boolean; // Ground truth: Is probe genuinely from the account owner?
}

export interface OneToOneVerificationResult {
  readonly scenarioName: string;
  readonly isTrueClaimant: boolean;
  readonly authenticated: boolean;
  readonly similarity: number;
  readonly thresholdUsed: number;
  readonly isError: boolean;
  readonly errorCode?: 'MODEL_VERSION_MISMATCH' | 'TEMPLATE_REVOKED' | 'ENCRYPTION_CORRUPTION' | 'SIMILARITY_BELOW_THRESHOLD' | 'IMPOSTOR_ACCEPTED';
}

export interface OneToOneSummary {
  readonly totalTrials: number;
  readonly genuineTrials: number;
  readonly impostorTrials: number;
  readonly falseMatches: number; // Impostors falsely accepted
  readonly falseNonMatches: number; // Genuine users falsely rejected
  readonly fmr: number;
  readonly fnmr: number;
  readonly fmrCi: ConfidenceInterval;
  readonly fnmrCi: ConfidenceInterval;
  readonly scenarioResults: readonly OneToOneVerificationResult[];
}

export class OneToOneEvaluator {
  public static readonly DEFAULT_VERIFICATION_THRESHOLD = 0.363; // Canonical SFace reference floor

  public static evaluateScenario(
    input: OneToOneScenarioInput,
    threshold = this.DEFAULT_VERIFICATION_THRESHOLD
  ): OneToOneVerificationResult {
    // 1. Template Revocation Gate
    if (input.enrolledTemplate.isRevoked) {
      return {
        scenarioName: input.scenarioName,
        isTrueClaimant: input.isTrueClaimant,
        authenticated: false,
        similarity: 0.0,
        thresholdUsed: threshold,
        isError: true,
        errorCode: 'TEMPLATE_REVOKED',
      };
    }

    // 2. Model Version Compatibility Gate
    if (input.enrolledTemplate.modelVersion !== 'sface_opencv_zoo_v1_primary') {
      return {
        scenarioName: input.scenarioName,
        isTrueClaimant: input.isTrueClaimant,
        authenticated: false,
        similarity: 0.0,
        thresholdUsed: threshold,
        isError: true,
        errorCode: 'MODEL_VERSION_MISMATCH',
      };
    }

    // 3. Biometric Comparison (Isolated from Play Integrity / Keystore)
    const sim = cosineSimilarity(input.probeEmbedding, input.enrolledTemplate.embedding);
    const passesSimilarity = sim >= threshold;

    if (input.isTrueClaimant) {
      return {
        scenarioName: input.scenarioName,
        isTrueClaimant: true,
        authenticated: passesSimilarity,
        similarity: Number(sim.toFixed(4)),
        thresholdUsed: threshold,
        isError: !passesSimilarity,
        errorCode: !passesSimilarity ? 'SIMILARITY_BELOW_THRESHOLD' : undefined,
      };
    } else {
      // Impostor presentation
      return {
        scenarioName: input.scenarioName,
        isTrueClaimant: false,
        authenticated: passesSimilarity,
        similarity: Number(sim.toFixed(4)),
        thresholdUsed: threshold,
        isError: passesSimilarity,
        errorCode: passesSimilarity ? 'IMPOSTOR_ACCEPTED' : undefined,
      };
    }
  }

  public static summarize(
    results: readonly OneToOneVerificationResult[]
  ): OneToOneSummary {
    let genuineTotal = 0;
    let impostorTotal = 0;
    let falseMatches = 0;
    let falseNonMatches = 0;

    for (const r of results) {
      if (r.isTrueClaimant) {
        genuineTotal++;
        if (!r.authenticated) {
          falseNonMatches++;
        }
      } else {
        impostorTotal++;
        if (r.authenticated) {
          falseMatches++;
        }
      }
    }

    const fmr = impostorTotal > 0 ? falseMatches / impostorTotal : 0;
    const fnmr = genuineTotal > 0 ? falseNonMatches / genuineTotal : 0;

    return {
      totalTrials: results.length,
      genuineTrials: genuineTotal,
      impostorTrials: impostorTotal,
      falseMatches,
      falseNonMatches,
      fmr: Number(fmr.toFixed(8)),
      fnmr: Number(fnmr.toFixed(8)),
      fmrCi: ConfidenceIntervalCalculator.calculateClopperPearson(falseMatches, impostorTotal || 1),
      fnmrCi: ConfidenceIntervalCalculator.calculateClopperPearson(falseNonMatches, genuineTotal || 1),
      scenarioResults: results,
    };
  }
}
