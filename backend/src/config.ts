// backend/src/config.ts
import dotenv from "dotenv";
import path from "path";

dotenv.config();

/**
 * Safely parses and bounds-checks a numeric threshold configuration value.
 * Throws explicit descriptive errors on missing, empty, NaN, infinite, or out-of-range inputs.
 */
export function parseThreshold(
  name: string,
  rawValue: string | undefined,
  defaultValue: number,
  min = -1.0,
  max = 1.0
): number {
  if (rawValue === undefined) {
    return defaultValue;
  }
  const trimmed = rawValue.trim();
  if (trimmed.length === 0) {
    throw new Error(`[ThresholdGovernance] Invalid configuration: ${name} cannot be an empty string.`);
  }
  const parsed = Number(trimmed);
  if (isNaN(parsed) || !isFinite(parsed)) {
    throw new Error(`[ThresholdGovernance] Invalid configuration: ${name} must be a valid finite number, got "${rawValue}".`);
  }
  if (parsed < min || parsed > max) {
    throw new Error(
      `[ThresholdGovernance] Invalid configuration: ${name} must be between ${min} and ${max}, got ${parsed}.`
    );
  }
  return parsed;
}

/**
 * Validates the operational threshold hierarchy and enforces fail-safe production rules.
 */
export function validateThresholdGovernance(cfg: {
  verificationThreshold: number;
  duplicateThreshold: number;
  hardBlockThreshold: number;
  ambiguityThreshold: number;
  advisoryFloorThreshold: number;
  nodeEnv?: string;
  enableBiometricIdentityGating?: boolean;
  productionCalibrationApproved?: boolean;
}): void {
  // 1. Monotonic ordering: verification < duplicate < hardBlock
  if (cfg.verificationThreshold >= cfg.duplicateThreshold) {
    throw new Error(
      `[ThresholdGovernance] Inverted hierarchy: verificationThreshold (${cfg.verificationThreshold}) must be strictly less than duplicateThreshold (${cfg.duplicateThreshold}).`
    );
  }
  if (cfg.duplicateThreshold >= cfg.hardBlockThreshold) {
    throw new Error(
      `[ThresholdGovernance] Inverted hierarchy: duplicateThreshold (${cfg.duplicateThreshold}) must be strictly less than hardBlockThreshold (${cfg.hardBlockThreshold}).`
    );
  }
  if (cfg.ambiguityThreshold > cfg.duplicateThreshold) {
    throw new Error(
      `[ThresholdGovernance] Inconsistent bounds: ambiguityThreshold (${cfg.ambiguityThreshold}) cannot exceed duplicateThreshold (${cfg.duplicateThreshold}).`
    );
  }
  if (cfg.advisoryFloorThreshold > cfg.verificationThreshold) {
    throw new Error(
      `[ThresholdGovernance] Inconsistent bounds: advisoryFloorThreshold (${cfg.advisoryFloorThreshold}) cannot exceed verificationThreshold (${cfg.verificationThreshold}).`
    );
  }

  // 2. Production Fail-Safe Gate:
  // In production, biometric identity gating MUST NOT be activated unless explicit,
  // documented, and approved field calibration has been completed.
  const isProd = cfg.nodeEnv === "production";
  if (isProd && cfg.enableBiometricIdentityGating && !cfg.productionCalibrationApproved) {
    throw new Error(
      "[ThresholdGovernance] CRITICAL RELEASE BLOCKER: Biometric identity gating is enabled in production without approved calibration manifest (PRODUCTION_BIOMETRIC_CALIBRATION_APPROVED !== 'true'). System must fail-closed."
    );
  }
}

/**
 * Enforces production authentication isolation.
 * Prohibits ALLOW_DEV_TOKEN from being enabled in production environments.
 */
export function validateAuthenticationGovernance(nodeEnv?: string, allowDevToken?: boolean): void {
  const isProd = nodeEnv === "production";
  if (isProd && allowDevToken === true) {
    throw new Error(
      "[AuthenticationGovernance] CRITICAL SECURITY FAULT: ALLOW_DEV_TOKEN cannot be enabled in production mode (NODE_ENV=production). Server must fail-closed."
    );
  }
}

// Initial parse from environment
const rawVerificationThreshold = parseThreshold("VERIFICATION_THRESHOLD", process.env.VERIFICATION_THRESHOLD, 0.363, 0.10, 0.80);
const rawDuplicateThreshold = parseThreshold("DUPLICATE_THRESHOLD", process.env.DUPLICATE_THRESHOLD, 0.74, 0.50, 0.95);
const rawHardBlockThreshold = parseThreshold("HARD_BLOCK_THRESHOLD", process.env.HARD_BLOCK_THRESHOLD, 0.90, 0.70, 0.99);
const rawAmbiguityThreshold = parseThreshold("AMBIGUITY_THRESHOLD", process.env.AMBIGUITY_THRESHOLD, 0.65, 0.30, 0.85);
const rawAdvisoryFloorThreshold = parseThreshold("ADVISORY_FLOOR_THRESHOLD", process.env.ADVISORY_FLOOR_THRESHOLD, 0.363, 0.10, 0.80);

const isProd = process.env.NODE_ENV === "production";
const enableBiometricIdentityGating = process.env.ENABLE_BIOMETRIC_IDENTITY_GATING === "true";
const productionCalibrationApproved = process.env.PRODUCTION_BIOMETRIC_CALIBRATION_APPROVED === "true";
const rawAllowDevToken = process.env.ALLOW_DEV_TOKEN === "true";

// Execute governance validations
validateThresholdGovernance({
  verificationThreshold: rawVerificationThreshold,
  duplicateThreshold: rawDuplicateThreshold,
  hardBlockThreshold: rawHardBlockThreshold,
  ambiguityThreshold: rawAmbiguityThreshold,
  advisoryFloorThreshold: rawAdvisoryFloorThreshold,
  nodeEnv: process.env.NODE_ENV,
  enableBiometricIdentityGating,
  productionCalibrationApproved,
});

validateAuthenticationGovernance(process.env.NODE_ENV, rawAllowDevToken);

export const config = {
  port: parseInt(process.env.PORT || "5001", 10),
  projectId: process.env.FIREBASE_PROJECT_ID || "kelasagara-f127a",
  firestoreEmulatorHost: process.env.FIRESTORE_EMULATOR_HOST,
  authEmulatorHost: process.env.FIREBASE_AUTH_EMULATOR_HOST,
  
  // Model settings (Primary & Validated Fallback Redundancy)
  modelPath: process.env.MODEL_PATH || path.resolve(__dirname, "../../models/face_recognition_sface_2021dec.onnx"),
  fallbackModelPath: process.env.FALLBACK_MODEL_PATH || path.resolve(__dirname, "../../models/face_recognition_sface_2021dec_int8.onnx"),
  legacyModelPath: process.env.LEGACY_MODEL_PATH || path.resolve(__dirname, "../../models/kelasagara_mobilefacenet.onnx"),
  modelVersion: process.env.MODEL_VERSION || "sface_opencv_zoo_v1_primary",
  fallbackModelVersion: process.env.FALLBACK_MODEL_VERSION || "sface_opencv_zoo_v1_fallback_int8",
  legacyModelVersion: "kelasagara_mobilefacenet_v1_arcface",
  embeddingDim: 128,
  
  // ── THRESHOLD GOVERNANCE & PROVENANCE ─────────────────────────────────────
  // Published Reference Values (Documented model reference, NOT production calibrated for Kelasagara):
  referenceVerificationThreshold: 0.363, // OpenCV Zoo SFace 2021dec reference cosine threshold
  referenceDuplicateThreshold: 0.74,    // Empirical duplicate heuristic
  referenceHardBlockThreshold: 0.90,    // High-confidence duplicate block heuristic

  // Active Operating Thresholds:
  verificationThreshold: rawVerificationThreshold,
  duplicateThreshold: rawDuplicateThreshold,
  hardBlockThreshold: rawHardBlockThreshold,
  ambiguityThreshold: rawAmbiguityThreshold,
  advisoryFloorThreshold: rawAdvisoryFloorThreshold,
  autoApprove: false,

  // Provenance & Release Gate Classification:
  isProductionCalibrated: false, // EXPLICIT: Field evaluation on representative target population pending
  thresholdTier: isProd ? "PRODUCTION_CANDIDATE" : "DEVELOPMENT_TEST",
  isIdentityGatingPermitted: isProd ? productionCalibrationApproved : true,
  productionBiometricCalibrationApproved: productionCalibrationApproved,
  releaseGateStatus: (productionCalibrationApproved ? "PRODUCTION_CANARY_APPROVED" : "CONTROLLED_TEST_BUILD_ONLY") as "CONTROLLED_TEST_BUILD_ONLY" | "PRODUCTION_CANARY_APPROVED",
  duplicateWarningThreshold: rawDuplicateThreshold,
  duplicateBlockThreshold: rawHardBlockThreshold,
  
  // Free-tier safety limits

  maxGalleryScanLimit: parseInt(process.env.MAX_GALLERY_SCAN_LIMIT || "500", 10),
  maxEnrollAttemptsPerDay: parseInt(process.env.MAX_ENROLL_ATTEMPTS || "3", 10),
  rateLimitWindowMs: 24 * 60 * 60 * 1000,
  maxPayloadSize: process.env.MAX_PAYLOAD_SIZE || "5mb",

  // Security & Network Configuration
  allowedOrigins: (process.env.ALLOWED_ORIGINS || "http://localhost:3000,http://localhost:5001,http://localhost:8080,http://10.0.2.2:5001")
    .split(",")
    .map((o) => o.trim()),

  // Dev / Testing bypass flags — Strictly false in production mode
  allowDevToken: !isProd && rawAllowDevToken,
};

export interface BiometricEngineConfig {
  verificationThreshold: number;
  duplicateWarningThreshold: number;
  duplicateBlockThreshold: number;
  productionBiometricCalibrationApproved: boolean;
  releaseGateStatus: 'CONTROLLED_TEST_BUILD_ONLY' | 'PRODUCTION_CANARY_APPROVED';
}

export function loadBiometricConfig(env: NodeJS.ProcessEnv = process.env): BiometricEngineConfig {
  const verificationThreshold = Number(env.BIOMETRIC_VERIFY_THRESHOLD ?? 0.363);
  const duplicateWarningThreshold = Number(env.BIOMETRIC_DUP_WARN_THRESHOLD ?? 0.74);
  const duplicateBlockThreshold = Number(env.BIOMETRIC_DUP_BLOCK_THRESHOLD ?? 0.90);

  for (const [name, val] of Object.entries({
    verificationThreshold,
    duplicateWarningThreshold,
    duplicateBlockThreshold,
  })) {
    if (!Number.isFinite(val) || val <= 0.0 || val >= 1.0) {
      throw new Error(`INVALID_THRESHOLD_CONFIG: ${name}=${val} must be finite in (0.0, 1.0)`);
    }
  }

  if (
    !(verificationThreshold < duplicateWarningThreshold &&
      duplicateWarningThreshold < duplicateBlockThreshold)
  ) {
    throw new Error(
      `NON_MONOTONIC_THRESHOLDS: Expected verify (${verificationThreshold}) < dupWarn (${duplicateWarningThreshold}) < dupBlock (${duplicateBlockThreshold})`
    );
  }

  const isApproved = env.PRODUCTION_BIOMETRIC_CALIBRATION_APPROVED === 'true';

  return {
    verificationThreshold,
    duplicateWarningThreshold,
    duplicateBlockThreshold,
    productionBiometricCalibrationApproved: isApproved,
    releaseGateStatus: isApproved ? 'PRODUCTION_CANARY_APPROVED' : 'CONTROLLED_TEST_BUILD_ONLY',
  };
}


