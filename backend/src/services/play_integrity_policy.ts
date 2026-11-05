// File: backend/src/services/play_integrity_policy.ts
import { PlayIntegrityDecodedVerdict } from './play_integrity_google_client';

export type IntegrityDecisionOutcome =
  | 'INTEGRITY_ACCEPTED'
  | 'INTEGRITY_RETRY'
  | 'INTEGRITY_STEP_UP'
  | 'INTEGRITY_RESTRICTED'
  | 'INTEGRITY_REJECTED'
  | 'INTEGRITY_UNAVAILABLE';

export type IntegrityEnvironmentTier = 'LOCAL' | 'STAGING' | 'PRODUCTION';

export interface IntegrityPolicyEvaluation {
  readonly outcome: IntegrityDecisionOutcome;
  readonly reason: string;
  readonly appIntegrityPassed: boolean;
  readonly deviceIntegrityPassed: boolean;
  readonly requestFreshnessPassed: boolean;
  readonly certificatePassed: boolean;
  readonly details: Record<string, any>;
}

export interface IntegrityPolicyConfig {
  readonly environment: IntegrityEnvironmentTier;
  readonly approvedCertificatesSha256: readonly string[];
  readonly maxTokenAgeSeconds: number; // e.g. 300s (5 minutes)
  readonly maxFutureClockSkewSeconds: number; // e.g. 60s
  readonly requireDeviceIntegrity: boolean; // In production: true
  readonly requireStrongIntegrity: boolean; // Optional future high-security flag
  readonly requirePlayRecognized: boolean; // In production: true
}

export const APPROVED_RELEASE_CERTIFICATES = [
  'a0425250004454e7fc63dba402351e439f975b0ff38f23cb2ca131edb037f7e5', // Kelasagara Release & Debug Keystore
] as const;

export const DEFAULT_INTEGRITY_POLICY_CONFIG: IntegrityPolicyConfig = {
  environment: (process.env.APP_ENV as IntegrityEnvironmentTier) || 'LOCAL',
  approvedCertificatesSha256: APPROVED_RELEASE_CERTIFICATES,
  maxTokenAgeSeconds: 300,
  maxFutureClockSkewSeconds: 60,
  requireDeviceIntegrity: process.env.APP_ENV === 'PRODUCTION',
  requireStrongIntegrity: false,
  requirePlayRecognized: process.env.APP_ENV === 'PRODUCTION',
};

export class PlayIntegrityPolicyEngine {
  private readonly config: IntegrityPolicyConfig;

  constructor(config: Partial<IntegrityPolicyConfig> = {}) {
    this.config = {
      ...DEFAULT_INTEGRITY_POLICY_CONFIG,
      ...config,
    };
  }

  public evaluateVerdict(verdict: PlayIntegrityDecodedVerdict, nowEpochMs: number = Date.now()): IntegrityPolicyEvaluation {
    const details: Record<string, any> = {};

    // 1. Freshness & Clock Skew Validation
    const tokenTime = Number(verdict.requestDetails.timestampMillis);
    if (!Number.isFinite(tokenTime)) {
      return {
        outcome: 'INTEGRITY_REJECTED',
        reason: 'INVALID_TIMESTAMP_IN_VERDICT',
        appIntegrityPassed: false,
        deviceIntegrityPassed: false,
        requestFreshnessPassed: false,
        certificatePassed: false,
        details: { tokenTime },
      };
    }

    const ageMs = nowEpochMs - tokenTime;
    const futureSkewMs = tokenTime - nowEpochMs;
    const maxAgeMs = this.config.maxTokenAgeSeconds * 1000;
    const maxFutureSkewMs = this.config.maxFutureClockSkewSeconds * 1000;

    let requestFreshnessPassed = true;
    if (futureSkewMs > maxFutureSkewMs) {
      return {
        outcome: 'INTEGRITY_REJECTED',
        reason: 'VERDICT_TIMESTAMP_IN_FUTURE',
        appIntegrityPassed: false,
        deviceIntegrityPassed: false,
        requestFreshnessPassed: false,
        certificatePassed: false,
        details: { futureSkewMs, maxFutureSkewMs },
      };
    }

    if (ageMs > maxAgeMs) {
      return {
        outcome: 'INTEGRITY_RETRY',
        reason: 'INTEGRITY_TOKEN_EXPIRED',
        appIntegrityPassed: false,
        deviceIntegrityPassed: false,
        requestFreshnessPassed: false,
        certificatePassed: false,
        details: { ageMs, maxAgeMs },
      };
    }

    // 2. Certificate Fingerprint Validation
    const certs = (verdict.appIntegrity.certificateSha256Digest || []).map((c) =>
      c.toLowerCase().replace(/:/g, '')
    );
    details.certDigests = certs;

    const certificatePassed = certs.some((c) =>
      this.config.approvedCertificatesSha256.map((ac) => ac.toLowerCase().replace(/:/g, '')).includes(c)
    );

    if (!certificatePassed && this.config.environment === 'PRODUCTION') {
      return {
        outcome: 'INTEGRITY_REJECTED',
        reason: 'UNAPPROVED_SIGNING_CERTIFICATE',
        appIntegrityPassed: false,
        deviceIntegrityPassed: false,
        requestFreshnessPassed: true,
        certificatePassed: false,
        details,
      };
    }

    // 3. Application Integrity Validation
    const appVerdict = verdict.appIntegrity.appRecognitionVerdict;
    details.appRecognitionVerdict = appVerdict;
    let appIntegrityPassed = false;

    if (appVerdict === 'PLAY_RECOGNIZED') {
      appIntegrityPassed = true;
    } else if (appVerdict === 'UNRECOGNIZED_VERSION') {
      // In Staging or Local, an unreleased sideloaded build can be stepped up
      if (this.config.environment !== 'PRODUCTION') {
        appIntegrityPassed = true;
      }
    }

    if (!appIntegrityPassed) {
      return {
        outcome: 'INTEGRITY_REJECTED',
        reason: 'APP_NOT_RECOGNIZED_BY_GOOGLE_PLAY',
        appIntegrityPassed: false,
        deviceIntegrityPassed: false,
        requestFreshnessPassed: true,
        certificatePassed,
        details,
      };
    }

    // 4. Device Integrity Validation
    const devVerdicts = verdict.deviceIntegrity?.deviceRecognitionVerdict || [];
    details.deviceRecognitionVerdict = devVerdicts;

    const meetsStrong = devVerdicts.includes('MEETS_STRONG_INTEGRITY');
    const meetsDevice = devVerdicts.includes('MEETS_DEVICE_INTEGRITY');
    const meetsBasic = devVerdicts.includes('MEETS_BASIC_INTEGRITY');

    let deviceIntegrityPassed = false;
    if (this.config.requireStrongIntegrity) {
      deviceIntegrityPassed = meetsStrong;
    } else if (this.config.requireDeviceIntegrity) {
      deviceIntegrityPassed = meetsDevice || meetsStrong;
    } else {
      // Local/Staging permits basic or device integrity
      deviceIntegrityPassed = meetsBasic || meetsDevice || meetsStrong;
    }

    if (!deviceIntegrityPassed) {
      // If basic is present but device is missing in production -> STEP_UP
      if (meetsBasic) {
        return {
          outcome: 'INTEGRITY_STEP_UP',
          reason: 'DEVICE_FAILS_HARDWARE_INTEGRITY_REQUIRES_STEPUP',
          appIntegrityPassed: true,
          deviceIntegrityPassed: false,
          requestFreshnessPassed: true,
          certificatePassed,
          details,
        };
      }

      // Rooted, emulator, or completely compromised
      return {
        outcome: 'INTEGRITY_RESTRICTED',
        reason: 'COMPROMISED_OR_UNRECOGNIZED_DEVICE_ENVIRONMENT',
        appIntegrityPassed: true,
        deviceIntegrityPassed: false,
        requestFreshnessPassed: true,
        certificatePassed,
        details,
      };
    }

    // 5. Environment Protection (Google Play Protect)
    const playProtect = verdict.environmentDetails?.playProtectVerdict;
    if (playProtect === 'DANGEROUS' || playProtect === 'RISKY') {
      return {
        outcome: 'INTEGRITY_REJECTED',
        reason: 'PLAY_PROTECT_FLAGGED_RISKY_ENVIRONMENT',
        appIntegrityPassed: true,
        deviceIntegrityPassed: true,
        requestFreshnessPassed: true,
        certificatePassed,
        details: { playProtect },
      };
    }

    return {
      outcome: 'INTEGRITY_ACCEPTED',
      reason: 'VERDICT_CRITERIA_SATISFIED',
      appIntegrityPassed: true,
      deviceIntegrityPassed: true,
      requestFreshnessPassed: true,
      certificatePassed,
      details,
    };
  }
}
