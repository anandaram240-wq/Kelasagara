// backend/src/services/model_registry.ts
//
// MODEL REGISTRY & GOVERNANCE ENGINE
// Enforces Invariants I-01 (Fail-Closed), I-07 (Threshold Provenance), and I-18 (Artifact Integrity).
//
// Invariant Policy:
// A model registered as 'RESEARCH_ONLY' (e.g. uncalibrated weights or random initializations)
// is STRICTLY FORBIDDEN from granting automated biometric approval ('approved', 'CLEAR', 'VERIFIED').
// All enrollments evaluated under RESEARCH_ONLY models MUST resolve to 'pending_review' or 'technical_failure_retry'.

import crypto from "crypto";
import fs from "fs";
import path from "path";

export type ModelTier = "RESEARCH_ONLY" | "PILOT_SHADOW" | "PRODUCTION_CLEARED" | "DEPRECATED";

export interface ModelMetadata {
  modelId: string;
  version: string;
  tier: ModelTier;
  embeddingDim: number;
  expectedSha256: string;
  provenance: string;
  clearedForAutomatedApproval: boolean;
  calibrationRunId?: string;
}

export class ModelRegistry {
  private static models: Map<string, ModelMetadata> = new Map([
    [
      "sface_opencv_zoo_v1_primary",
      {
        modelId: "sface_opencv_zoo",
        version: "sface_opencv_zoo_v1_primary",
        tier: "PILOT_SHADOW",
        embeddingDim: 128,
        expectedSha256: "0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79",
        provenance: "OpenCV Zoo SFace FP32 (face_recognition_sface_2021dec.onnx). Trained weights from OpenCV Zoo. License: Apache-2.0.",
        clearedForAutomatedApproval: false,
        calibrationRunId: "sface_calib_run_20261010_v1",
      },
    ],
    [
      "sface_opencv_zoo_v1_fallback_int8",
      {
        modelId: "sface_opencv_zoo",
        version: "sface_opencv_zoo_v1_fallback_int8",
        tier: "PILOT_SHADOW",
        embeddingDim: 128,
        expectedSha256: "2b0e941e6f16cc048c20aee0c8e31f569118f65d702914540f7bfdc14048d78a",
        provenance: "OpenCV Zoo SFace INT8 (face_recognition_sface_2021dec_int8.onnx). Quantized weights from OpenCV Zoo. License: Apache-2.0.",
        clearedForAutomatedApproval: false,
        calibrationRunId: "sface_int8_calib_run_20261010_v1",
      },
    ],
    [
      "kelasagara_mobilefacenet_v1_arcface",
      {
        modelId: "kelasagara_mobilefacenet",
        version: "kelasagara_mobilefacenet_v1_arcface",
        tier: "RESEARCH_ONLY",
        embeddingDim: 128,
        expectedSha256: "cde3799f041eca6a6a99bfac53d9e97eb81ff34ac450d519aa41a9c99bef7d7c",
        provenance: "Uninitialized random PyTorch export (ml/export_mobilefacenet_onnx.py). No training dataset.",
        clearedForAutomatedApproval: false,
      },
    ],
    [
      "sface_opencv_zoo_shadow_v1",
      {
        modelId: "sface_opencv_zoo",
        version: "sface_opencv_zoo_shadow_v1",
        tier: "RESEARCH_ONLY",
        embeddingDim: 128,
        expectedSha256: "shadow_evaluation_placeholder",
        provenance: "OpenCV Zoo SFace architecture; shadow non-authoritative evaluator.",
        clearedForAutomatedApproval: false,
      },
    ],
  ]);

  /**
   * Retrieves model metadata by version tag.
   */
  static getModel(version: string): ModelMetadata {
    const meta = this.models.get(version);
    if (!meta) {
      throw new Error(`[ModelRegistry] Unknown or unregistered model version: ${version}`);
    }
    return meta;
  }

  /**
   * Verifies the physical integrity and SHA-256 hash of the ONNX model file.
   */
  static verifyArtifactIntegrity(modelPath: string, version: string): boolean {
    const meta = this.getModel(version);
    if (!fs.existsSync(modelPath)) {
      throw new Error(`[ModelRegistry] Model file does not exist at path: ${modelPath}`);
    }

    const fileBuffer = fs.readFileSync(modelPath);
    const actualHash = crypto.createHash("sha256").update(fileBuffer).digest("hex");

    if (actualHash !== meta.expectedSha256) {
      throw new Error(
        `[ModelRegistry] Artifact integrity check FAILED for ${version}.\n` +
          `Expected SHA-256: ${meta.expectedSha256}\n` +
          `Actual SHA-256:   ${actualHash}`
      );
    }

    return true;
  }

  /**
   * Asserts whether a model is permitted to issue automated approvals.
   * Throws an invariant violation error if an uncalibrated / RESEARCH_ONLY model is attempted.
   */
  static assertClearedForAutomatedApproval(version: string): void {
    const meta = this.getModel(version);
    if (!meta.clearedForAutomatedApproval || meta.tier === "RESEARCH_ONLY") {
      throw new Error(
        `[ModelRegistry] Invariant I-01 / I-18 Violation: Model '${version}' is registered as ` +
          `'${meta.tier}' and is NOT cleared for automated approval. Automated 'approved' / 'VERIFIED' status is forbidden.`
      );
    }
  }
}
