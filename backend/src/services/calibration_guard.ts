// backend/src/services/calibration_guard.ts
/**
 * Cryptographic Calibration Guard (Ticket T-12).
 * Verifies Ed25519 signature of calibration.json at system startup.
 * Enforces Invariants I-01 (Fail-Closed) and I-07 (Threshold Provenance).
 */

import fs from "fs";
import path from "path";
import crypto from "crypto";

export interface CalibrationFilePayload {
  calibrationRunId: string;
  modelId: string;
  modelSha256: string;
  dataset: string;
  sampleSize: {
    subjects: number;
    genuinePairs: number;
    impostorPairs: number;
  };
  metrics: {
    auc: number;
    eer: number;
    fmr1e3Threshold: number;
    fnmrAt1e3: number;
    fmr1e4Threshold: number;
    fnmrAt1e4: number;
    advisoryFloorThreshold: number;
  };
  calibratedAt: string;
  signerIdentity: string;
}

export interface SignedCalibrationDoc {
  payload: CalibrationFilePayload;
  publicKeyHex: string;
  signatureHex: string;
}

export class CalibrationGuard {
  private static cachedCalibration: CalibrationFilePayload | null = null;

  /**
   * Loads and cryptographically validates calibration.json.
   * If file is absent, altered, or signature fails, throws error (fail-closed).
   */
  static loadAndVerify(filePath?: string): CalibrationFilePayload {
    if (this.cachedCalibration) {
      return this.cachedCalibration;
    }

    const targetPath =
      filePath ||
      path.resolve(__dirname, "../../calibration/calibration.json");

    if (!fs.existsSync(targetPath)) {
      throw new Error(
        `[CalibrationGuard] Invariant I-07 Violation: Missing calibration artifact at ${targetPath}. Fail-closed.`
      );
    }

    const raw = fs.readFileSync(targetPath, "utf8");
    let doc: SignedCalibrationDoc;
    try {
      doc = JSON.parse(raw);
    } catch (parseErr: any) {
      throw new Error(`[CalibrationGuard] Corrupt calibration JSON: ${parseErr.message}`);
    }

    if (!doc.payload || !doc.publicKeyHex || !doc.signatureHex) {
      throw new Error("[CalibrationGuard] Invalid calibration document schema: missing payload, publicKey, or signature.");
    }

    // Canonicalize payload for deterministic verification
    const canonicalPayload = JSON.stringify(doc.payload);
    const dataBuffer = Buffer.from(canonicalPayload, "utf8");
    const signatureBuffer = Buffer.from(doc.signatureHex, "hex");

    // Reconstruct Ed25519 Public Key
    const pubKeyDer = Buffer.concat([
      Buffer.from("302a300506032b6570032100", "hex"), // standard ASN.1 PKIX prefix for Ed25519
      Buffer.from(doc.publicKeyHex, "hex"),
    ]);

    const publicKey = crypto.createPublicKey({
      key: pubKeyDer,
      format: "der",
      type: "spki",
    });

    const isValid = crypto.verify(null, dataBuffer, publicKey, signatureBuffer);
    if (!isValid) {
      throw new Error(
        "[CalibrationGuard] Invariant I-07 Violation: Ed25519 cryptographic signature mismatch on calibration.json! Tampering intercepted."
      );
    }

    this.cachedCalibration = doc.payload;
    return doc.payload;
  }

  /**
   * Helper to sign a calibration payload (used during official calibration runs).
   */
  static signPayload(
    payload: CalibrationFilePayload,
    privateKey: crypto.KeyObject,
    publicKeyHex: string
  ): SignedCalibrationDoc {
    const canonicalPayload = JSON.stringify(payload);
    const dataBuffer = Buffer.from(canonicalPayload, "utf8");
    const signature = crypto.sign(null, dataBuffer, privateKey);

    return {
      payload,
      publicKeyHex,
      signatureHex: signature.toString("hex"),
    };
  }
}
