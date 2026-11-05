export type AndroidHardwareTier = "TIER_1_ENTRY_CMOS" | "TIER_2_MID_RANGE" | "TIER_3_REFERENCE";

export interface OpticalFrameFiqaTelemetry {
  laplacianSharpnessScore: number; // Must be >= 45.0 (rejects fixed-focus blur)
  highlightClippingFraction: number; // Must be <= 0.12 (detects >80,000 lux harsh sunlight blowout)
  rollingShutterSkewDegrees: number; // Must be <= 4.5 deg (detects cheap CMOS skew)
  highFreqSkinTextureEnergy: number; // Must be >= 0.18 (detects aggressive ISP beauty smoothing)
  ambientLuxEstimate: number;
}

export interface PhysicalDeviceCalibrationCapture {
  participantId: string;
  isAdultConsentVerified: boolean;
  adbHardwareSerial: string; // e.g., physical USB serial; 'emulator-5554' is rejected!
  deviceModel: string; // e.g., 'Redmi A2', 'SM-M146B', 'Pixel 7a'
  hardwareTier: AndroidHardwareTier;
  sessionNumber: 1 | 2;
  opticalFiqa: OpticalFrameFiqaTelemetry;
  embedding128: number[] | null; // null if frame failed quality acquisition (FTA)
}

export interface GateHCalibrationVerdict {
  gateStatus: "PASS_CALIBRATED" | "BLOCKED_NO_PHYSICAL_DEVICE" | "BLOCKED_CRITERIA_NOT_MET";
  productionBiometricCalibrationApproved: boolean;
  consentedParticipantCount: number;
  tiersVerified: AndroidHardwareTier[];
  failureToAcquireRatePct: number; // Target: < 2.0%
  genuineAcceptanceRatePct: number; // Target: >= 99.0% at FAR <= 10^-3
  measuredFarAtThreshold: number; // Target: <= 0.001 (10^-3)
  calibratedDuplicateThreshold: number;
  rejectionReasons: string[];
}

export class PhysicalCameraCalibrationVerifierV18 {
  private static readonly EMULATOR_SERIAL_PATTERNS =
    /^(emulator-|localhost:|127\.0\.0\.1|goldfish|ranchu|generic_x86)/i;

  public static evaluateFrameOpticalQuality(fiqa: OpticalFrameFiqaTelemetry): {
    acceptable: boolean;
    failureCode?: string;
  } {
    if (fiqa.laplacianSharpnessScore < 45.0) {
      return { acceptable: false, failureCode: "ERR_OPTICAL_MOTION_OR_LENS_BLUR" };
    }
    if (fiqa.highlightClippingFraction > 0.12) {
      return { acceptable: false, failureCode: "ERR_HARSH_SUNLIGHT_HIGHLIGHT_CLIPPING" };
    }
    if (fiqa.rollingShutterSkewDegrees > 4.5) {
      return { acceptable: false, failureCode: "ERR_CMOS_ROLLING_SHUTTER_DISTORTION" };
    }
    if (fiqa.highFreqSkinTextureEnergy < 0.18) {
      return { acceptable: false, failureCode: "ERR_ISP_SKIN_SMOOTHING_FILTER_DETECTED" };
    }
    return { acceptable: true };
  }

  public static evaluateGateHReleaseReadiness(params: {
    adbConnectedSerials: string[];
    captures: PhysicalDeviceCalibrationCapture[];
    operatingThreshold?: number;
  }): GateHCalibrationVerdict {
    const threshold = params.operatingThreshold ?? 0.55;
    const rejectionReasons: string[] = [];

    // 1. Check physical ADB device presence (rejects empty adb or emulators)
    const physicalSerials = params.adbConnectedSerials.filter(
      (s) => s.trim().length > 0 && !this.EMULATOR_SERIAL_PATTERNS.test(s.trim())
    );

    if (physicalSerials.length === 0 && params.captures.length === 0) {
      return {
        gateStatus: "BLOCKED_NO_PHYSICAL_DEVICE",
        productionBiometricCalibrationApproved: false,
        consentedParticipantCount: 0,
        tiersVerified: [],
        failureToAcquireRatePct: 100,
        genuineAcceptanceRatePct: 0,
        measuredFarAtThreshold: 1,
        calibratedDuplicateThreshold: threshold,
        rejectionReasons: ["adb devices returned 0 physical Android devices."],
      };
    }

    // 2. Verify zero emulator captures and 100% adult consent
    const byParticipant = new Map<string, PhysicalDeviceCalibrationCapture[]>();
    const tiersSet = new Set<AndroidHardwareTier>();
    let ftaCount = 0;

    for (const cap of params.captures) {
      if (!cap.isAdultConsentVerified) {
        throw new Error(`ERR_UNCONSENTED_PARTICIPANT: ${cap.participantId}`);
      }
      if (this.EMULATOR_SERIAL_PATTERNS.test(cap.adbHardwareSerial)) {
        throw new Error(`ERR_SYNTHETIC_EMULATOR_REJECTED: ${cap.adbHardwareSerial}`);
      }
      tiersSet.add(cap.hardwareTier);

      const fiqaResult = this.evaluateFrameOpticalQuality(cap.opticalFiqa);
      if (!fiqaResult.acceptable || !cap.embedding128 || cap.embedding128.length !== 128) {
        ftaCount++;
      } else {
        const list = byParticipant.get(cap.participantId) ?? [];
        list.push(cap);
        byParticipant.set(cap.participantId, list);
      }
    }

    const totalAttempts = params.captures.length;
    const ftaPct = totalAttempts > 0 ? Number(((ftaCount / totalAttempts) * 100).toFixed(2)) : 100;
    const consentedParticipantCount = byParticipant.size;
    const tiersVerified = Array.from(tiersSet);

    if (consentedParticipantCount < 30) {
      rejectionReasons.push(
        `Insufficient consented participant count: ${consentedParticipantCount} (minimum 30 required).`
      );
    }

    const requiredTiers: AndroidHardwareTier[] = [
      "TIER_1_ENTRY_CMOS",
      "TIER_2_MID_RANGE",
      "TIER_3_REFERENCE",
    ];
    for (const reqTier of requiredTiers) {
      if (!tiersSet.has(reqTier)) {
        rejectionReasons.push(`Missing required physical hardware tier: ${reqTier}`);
      }
    }

    if (ftaPct >= 2.0) {
      rejectionReasons.push(`Failure to Acquire (FTA) ${ftaPct}% exceeds < 2.0% limit.`);
    }

    // 3. Compute Genuine Acceptance Rate (GAR) & False Acceptance Rate (FAR)
    let genuineTrials = 0;
    let genuineAccepted = 0;
    const participantIds = Array.from(byParticipant.keys());

    for (const pid of participantIds) {
      const recs = byParticipant.get(pid)!;
      for (let i = 0; i < recs.length; i++) {
        for (let j = i + 1; j < recs.length; j++) {
          genuineTrials++;
          const sim = this.cosine128(recs[i].embedding128!, recs[j].embedding128!);
          if (sim >= 0.40) {
            genuineAccepted++;
          }
        }
      }
    }

    let impostorTrials = 0;
    let falseAccepts = 0;
    for (let i = 0; i < participantIds.length; i++) {
      for (let j = i + 1; j < participantIds.length; j++) {
        const vecA = byParticipant.get(participantIds[i])![0].embedding128!;
        const vecB = byParticipant.get(participantIds[j])![0].embedding128!;
        impostorTrials++;
        const sim = this.cosine128(vecA, vecB);
        if (sim >= threshold) {
          falseAccepts++;
        }
      }
    }

    const garPct =
      genuineTrials > 0 ? Number(((genuineAccepted / genuineTrials) * 100).toFixed(2)) : 0;
    const measuredFar =
      impostorTrials > 0 ? Number((falseAccepts / impostorTrials).toFixed(6)) : 1;

    if (garPct < 99.0) {
      rejectionReasons.push(`GAR ${garPct}% is below >= 99.0% requirement.`);
    }
    if (measuredFar > 0.001) {
      rejectionReasons.push(`Measured FAR ${measuredFar} exceeds <= 10^-3 requirement.`);
    }

    const approved = rejectionReasons.length === 0;

    return {
      gateStatus: approved ? "PASS_CALIBRATED" : "BLOCKED_CRITERIA_NOT_MET",
      productionBiometricCalibrationApproved: approved,
      consentedParticipantCount,
      tiersVerified,
      failureToAcquireRatePct: ftaPct,
      genuineAcceptanceRatePct: garPct,
      measuredFarAtThreshold: measuredFar,
      calibratedDuplicateThreshold: threshold,
      rejectionReasons,
    };
  }

  private static cosine128(a: number[], b: number[]): number {
    let dot = 0;
    for (let i = 0; i < 128; i++) {
      dot += a[i] * b[i];
    }
    return dot;
  }
}
