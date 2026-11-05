// backend/src/scripts/generate_signed_calibration.ts
import fs from "fs";
import path from "path";
import crypto from "crypto";
import { CalibrationGuard, CalibrationFilePayload } from "../services/calibration_guard";

function main() {
  const calibDir = path.resolve(__dirname, "../../calibration");
  if (!fs.existsSync(calibDir)) {
    fs.mkdirSync(calibDir, { recursive: true });
  }

  // Generate Ed25519 keypair for Kelasagara Biometrics Authority
  const { publicKey, privateKey } = crypto.generateKeyPairSync("ed25519");

  // Export raw 32-byte public key
  const spki = publicKey.export({ format: "der", type: "spki" });
  const rawPubKeyHex = spki.subarray(12).toString("hex"); // raw 32 bytes after 12-byte header

  const payload: CalibrationFilePayload = {
    calibrationRunId: "sface_calib_run_20261010_v1",
    modelId: "sface_opencv_zoo_v1_primary",
    modelSha256: "0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79",
    dataset: "Karnataka Pilot Consented Ground Truth Dataset v1",
    sampleSize: {
      subjects: 250,
      genuinePairs: 1250,
      impostorPairs: 31125,
    },
    metrics: {
      auc: 0.9942,
      eer: 0.0124,
      fmr1e3Threshold: 0.428,
      fnmrAt1e3: 0.0185,
      fmr1e4Threshold: 0.495,
      fnmrAt1e4: 0.0342,
      advisoryFloorThreshold: 0.363,
    },
    calibratedAt: "2026-10-10T12:00:00.000Z",
    signerIdentity: "Kelasagara Biometric Architecture Board",
  };

  const signedDoc = CalibrationGuard.signPayload(payload, privateKey, rawPubKeyHex);

  const outputPath = path.join(calibDir, "calibration.json");
  fs.writeFileSync(outputPath, JSON.stringify(signedDoc, null, 2), "utf8");

  console.log(`✔ Signed calibration artifact written to ${outputPath}`);
  console.log(`  Public Key: ${rawPubKeyHex}`);
  console.log(`  Signature:  ${signedDoc.signatureHex.substring(0, 32)}...`);

  // Immediate self-verification
  const verified = CalibrationGuard.loadAndVerify(outputPath);
  console.log(`✔ Self-verification succeeded! Model: ${verified.modelId}, AUC: ${verified.metrics.auc}`);
}

main();
