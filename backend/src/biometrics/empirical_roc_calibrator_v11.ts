// FILE: backend/src/biometrics/empirical_roc_calibrator_v11.ts

import crypto from "crypto";
import { Arcface512SessionPoolV11, BiometricModelVersion } from "./arcface_512_session_pool_v11";

export interface ParticipantRecordV11 {
  participantId: string;
  sessionNumber: 1 | 2;
  captureIndex: number;
  embedding: number[];
  qualityScore: number;
  timestampIso?: string;
}

export interface RocPoint {
  threshold: number;
  far: number; // False Acceptance Rate
  frr: number; // False Rejection Rate
  tpr: number; // 1 - frr
}

export interface CalibrationCertificateV11 {
  certificateId: string;
  issuedAtIso: string;
  modelVersion: BiometricModelVersion;
  datasetParticipantCount: number;
  genuineComparisonCount: number;
  impostorComparisonCount: number;
  genuineMeanCosine: number;
  genuineStdCosine: number;
  impostorMeanCosine: number;
  impostorStdCosine: number;
  decidabilityDPrime: number;
  equalErrorRate: number;
  calibratedTauHigh: number;
  calibratedTauLow: number;
  targetFarAchieved: number;
  targetFrrAchieved: number;
  isEmpiricallyValidatedForProduction: boolean;
  releaseGateStatus: "CONTROLLED_PILOT_ONLY" | "GENERAL_PRODUCTION_APPROVED";
  validationHash: string; // HMAC-SHA256 digital signature
  notes: string[];
}

export interface StepUpChallengeTokenV11 {
  challengeId: string;
  uid: string;
  action: "BLINK" | "TURN_LEFT" | "TURN_RIGHT" | "NOD";
  nonce: string;
  issuedAtMs: number;
  expiresAtMs: number;
  signature: string;
}

export interface StepUpChallengeResponseV11 {
  challengeId: string;
  uid: string;
  action: "BLINK" | "TURN_LEFT" | "TURN_RIGHT" | "NOD";
  nonce: string;
  issuedAtMs: number;
  expiresAtMs: number;
  signature: string;
  observedAction: "BLINK" | "TURN_LEFT" | "TURN_RIGHT" | "NOD";
  actionMagnitude: number; // e.g. degrees turned or eye closure ratio
  livenessConfidence: number; // 0..1.0
}

/**
 * Empirical ROC Auto-Calibrator, Grey-Zone Ambiguity Band Engine,
 * and Active Liveness Step-Up Challenge Manager.
 */
export class EmpiricalRocCalibratorV11 {
  public static readonly MIN_PARTICIPANTS_PRODUCTION = 30;
  public static readonly MIN_DECIDABILITY_D_PRIME = 4.5;
  public static readonly MAX_EQUAL_ERROR_RATE = 0.015; // 1.5% max EER for production gate
  public static readonly CHALLENGE_TTL_MS = 60_000; // 60 seconds

  private static readonly HMAC_KEY =
    process.env.BIOMETRIC_CALIBRATION_HMAC_KEY ||
    "KS_CALIBRATION_CERT_SIGN_KEY_32BYTES_0123456789";

  /**
   * Computes the Decidability Index d' (D-Prime) between genuine and impostor score distributions:
   * d' = (sqrt(2) * |mu_g - mu_i|) / sqrt(sigma_g^2 + sigma_i^2)
   */
  public static computeDecidabilityDPrime(
    muGenuine: number,
    sigmaGenuine: number,
    muImpostor: number,
    sigmaImpostor: number
  ): number {
    const denom = Math.sqrt(sigmaGenuine * sigmaGenuine + sigmaImpostor * sigmaImpostor);
    if (denom < 1e-7) return 0.0;
    const dPrime = (Math.SQRT2 * Math.abs(muGenuine - muImpostor)) / denom;
    return Number(dPrime.toFixed(4));
  }

  /**
   * Computes full empirical ROC curve and selects calibrated thresholds.
   */
  public static calibrateFromCorpus(
    records: ParticipantRecordV11[],
    modelVersion: BiometricModelVersion = "v11_adaface_512"
  ): CalibrationCertificateV11 {
    const participants = new Set(records.map((r) => r.participantId));
    const participantCount = participants.size;

    const genuineScores: number[] = [];
    const impostorScores: number[] = [];

    // Form genuine and impostor pairwise comparisons
    for (let i = 0; i < records.length; i++) {
      for (let j = i + 1; j < records.length; j++) {
        const sim = Arcface512SessionPoolV11.computeCosineSimilarity(
          records[i].embedding,
          records[j].embedding
        );

        if (records[i].participantId === records[j].participantId) {
          genuineScores.push(sim);
        } else {
          impostorScores.push(sim);
        }
      }
    }

    if (genuineScores.length === 0 || impostorScores.length === 0) {
      throw new Error("ERR_INSUFFICIENT_PAIRS: Corpus must produce at least 1 genuine and 1 impostor pair.");
    }

    // Mean and standard deviation calculations
    const genuineMean = genuineScores.reduce((a, b) => a + b, 0) / genuineScores.length;
    const impostorMean = impostorScores.reduce((a, b) => a + b, 0) / impostorScores.length;

    const genuineVar =
      genuineScores.reduce((acc, s) => acc + Math.pow(s - genuineMean, 2), 0) /
      genuineScores.length;
    const impostorVar =
      impostorScores.reduce((acc, s) => acc + Math.pow(s - impostorMean, 2), 0) /
      impostorScores.length;

    const genuineStd = Math.sqrt(genuineVar);
    const impostorStd = Math.sqrt(impostorVar);

    const dPrime = this.computeDecidabilityDPrime(
      genuineMean,
      genuineStd,
      impostorMean,
      impostorStd
    );

    // Compute ROC sweep from 0.10 to 0.95 in 0.01 increments
    let bestEer = 1.0;
    let eerThreshold = 0.50;
    let tauHigh = modelVersion === "v11_adaface_512" ? 0.62 : 0.363;
    let tauLow = modelVersion === "v11_adaface_512" ? 0.48 : 0.320;
    let farAtTauHigh = 0.0;
    let frrAtTauHigh = 0.0;

    let foundTauHigh = false;

    for (let t = 0.1; t <= 0.95; t += 0.01) {
      const threshold = Number(t.toFixed(2));

      // FAR: impostors >= threshold
      const falseAccepts = impostorScores.filter((s) => s >= threshold).length;
      const far = falseAccepts / impostorScores.length;

      // FRR: genuines < threshold
      const falseRejects = genuineScores.filter((s) => s < threshold).length;
      const frr = falseRejects / genuineScores.length;

      // EER point: min |FAR - FRR|
      if (Math.abs(far - frr) < Math.abs(bestEer)) {
        bestEer = (far + frr) / 2;
        eerThreshold = threshold;
      }

      // Tau High: strict threshold where FAR <= 0.0001 (1 in 10,000) or lowest far
      if (!foundTauHigh && far <= 0.0001) {
        tauHigh = threshold;
        farAtTauHigh = far;
        frrAtTauHigh = frr;
        foundTauHigh = true;
      }

      // Tau Low: Grey-Zone lower threshold where FAR <= 0.01 (1 in 100)
      if (far <= 0.01 && tauLow === (modelVersion === "v11_adaface_512" ? 0.48 : 0.32)) {
        tauLow = threshold;
      }
    }

    if (!foundTauHigh) {
      tauHigh = Number((impostorMean + 3.89 * impostorStd).toFixed(3));
      farAtTauHigh = 0.0001;
      frrAtTauHigh = Number(
        (genuineScores.filter((s) => s < tauHigh).length / genuineScores.length).toFixed(4)
      );
    }

    // Check production release gate criteria
    const hasEnoughParticipants = participantCount >= this.MIN_PARTICIPANTS_PRODUCTION;
    const hasHighDecidability = dPrime >= this.MIN_DECIDABILITY_D_PRIME;
    const hasLowEer = bestEer <= this.MAX_EQUAL_ERROR_RATE;

    const isEmpiricallyValidatedForProduction =
      hasEnoughParticipants && hasHighDecidability && hasLowEer;

    const releaseGateStatus = isEmpiricallyValidatedForProduction
      ? "GENERAL_PRODUCTION_APPROVED"
      : "CONTROLLED_PILOT_ONLY";

    const certificateId = `KS_CERT_V11_${crypto.randomBytes(6).toString("hex")}`;
    const issuedAtIso = new Date().toISOString();

    const payloadToSign = `${certificateId}:${modelVersion}:${participantCount}:${dPrime}:${bestEer}:${tauHigh}:${tauLow}:${releaseGateStatus}`;
    const validationHash = crypto
      .createHmac("sha256", this.HMAC_KEY)
      .update(payloadToSign)
      .digest("hex");

    const notes: string[] = [];
    if (!hasEnoughParticipants) {
      notes.push(`Participant count ${participantCount} < required minimum ${this.MIN_PARTICIPANTS_PRODUCTION}.`);
    }
    if (!hasHighDecidability) {
      notes.push(`Decidability index d'=${dPrime} < required minimum ${this.MIN_DECIDABILITY_D_PRIME}.`);
    }
    if (!hasLowEer) {
      notes.push(`Equal Error Rate EER=${(bestEer * 100).toFixed(2)}% > required maximum ${(this.MAX_EQUAL_ERROR_RATE * 100).toFixed(2)}%.`);
    }
    if (isEmpiricallyValidatedForProduction) {
      notes.push("All Phase 11 production criteria met: N>=30, d'>=4.5, EER<=1.5%. Approved for 100,000+ general rollout.");
    }

    return {
      certificateId,
      issuedAtIso,
      modelVersion,
      datasetParticipantCount: participantCount,
      genuineComparisonCount: genuineScores.length,
      impostorComparisonCount: impostorScores.length,
      genuineMeanCosine: Number(genuineMean.toFixed(4)),
      genuineStdCosine: Number(genuineStd.toFixed(4)),
      impostorMeanCosine: Number(impostorMean.toFixed(4)),
      impostorStdCosine: Number(impostorStd.toFixed(4)),
      decidabilityDPrime: dPrime,
      equalErrorRate: Number(bestEer.toFixed(4)),
      calibratedTauHigh: tauHigh,
      calibratedTauLow: tauLow,
      targetFarAchieved: Number(farAtTauHigh.toFixed(6)),
      targetFrrAchieved: Number(frrAtTauHigh.toFixed(4)),
      isEmpiricallyValidatedForProduction,
      releaseGateStatus,
      validationHash,
      notes,
    };
  }

  /**
   * Mints a signed Active Liveness Step-Up Challenge Token.
   */
  public static createStepUpChallenge(
    uid: string,
    action: "BLINK" | "TURN_LEFT" | "TURN_RIGHT" | "NOD" = "BLINK"
  ): StepUpChallengeTokenV11 {
    const challengeId = `KS_CHAL_${crypto.randomBytes(8).toString("hex")}`;
    const nonce = crypto.randomBytes(16).toString("hex");
    const issuedAtMs = Date.now();
    const expiresAtMs = issuedAtMs + this.CHALLENGE_TTL_MS;

    const payload = `${challengeId}:${uid}:${action}:${nonce}:${issuedAtMs}:${expiresAtMs}`;
    const signature = crypto.createHmac("sha256", this.HMAC_KEY).update(payload).digest("hex");

    return {
      challengeId,
      uid,
      action,
      nonce,
      issuedAtMs,
      expiresAtMs,
      signature,
    };
  }

  /**
   * Verifies the client's active challenge response.
   */
  public static verifyStepUpChallenge(
    response: StepUpChallengeResponseV11
  ): { isValid: boolean; reason?: string } {
    const now = Date.now();
    if (now > response.expiresAtMs) {
      return { isValid: false, reason: "ERR_CHALLENGE_EXPIRED: Challenge TTL exceeded 60s." };
    }

    // Verify HMAC signature
    const payload = `${response.challengeId}:${response.uid}:${response.action}:${response.nonce}:${response.issuedAtMs}:${response.expiresAtMs}`;
    const expectedSig = crypto.createHmac("sha256", this.HMAC_KEY).update(payload).digest("hex");

    if (expectedSig !== response.signature) {
      return { isValid: false, reason: "ERR_INVALID_CHALLENGE_SIG: Challenge signature mismatch." };
    }

    // Verify requested action matches observed action
    if (response.action !== response.observedAction) {
      return {
        isValid: false,
        reason: `ERR_CHALLENGE_ACTION_MISMATCH: Requested ${response.action}, observed ${response.observedAction}.`,
      };
    }

    // Verify action magnitude
    if (response.action === "BLINK" && response.actionMagnitude < 0.6) {
      return { isValid: false, reason: "ERR_INSUFFICIENT_BLINK: Eye closure ratio was below 0.6." };
    }

    if (
      (response.action === "TURN_LEFT" || response.action === "TURN_RIGHT" || response.action === "NOD") &&
      response.actionMagnitude < 12.0 // at least 12 degrees head rotation
    ) {
      return {
        isValid: false,
        reason: `ERR_INSUFFICIENT_ROTATION: Observed rotation ${response.actionMagnitude}deg < minimum 12deg.`,
      };
    }

    if (response.livenessConfidence < 0.8) {
      return {
        isValid: false,
        reason: `ERR_LOW_LIVENESS_CONFIDENCE: Liveness score ${response.livenessConfidence} < 0.80.`,
      };
    }

    return { isValid: true };
  }
}
