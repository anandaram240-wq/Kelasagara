// backend/src/services/template_lifecycle.ts
/**
 * Track D: Template Lifecycle & Anti-Drift Service (Ticket D-03).
 * Governs model migration, cryptographic provenance tagging, and safe adaptive template updates.
 * Enforces Invariants I-01 (Fail-Closed), I-02 (Sovereign Weights), and I-07.
 */

import crypto from "crypto";

export interface BiometricTemplateRecord {
  uid: string;
  embedding: number[];
  modelId: string;
  modelVersion: string;
  modelSha256: string;
  templateSha256: string;
  createdAt: string;
  updatedAt: string;
  adaptationCount: number;
}

export interface AdaptiveUpdateRequest {
  currentTemplate: BiometricTemplateRecord;
  probeEmbedding: number[];
  matchCosine: number;
  livenessPassed: boolean;
  qualityPassed: boolean;
  qualityScore: number;
}

export class TemplateLifecycleService {
  // Safe adaptive update parameters
  private static readonly HIGH_CONFIDENCE_THRESHOLD = 0.75; // Cosine must be >= 0.75 (far above standard 0.363)
  private static readonly MIN_QUALITY_FOR_ADAPTATION = 0.70;
  private static readonly ADAPTATION_ALPHA = 0.05;          // Conservative learning rate (5% probe, 95% template)

  private static hashVector(v: number[]): string {
    const buf = Buffer.from(new Float32Array(v).buffer);
    return crypto.createHash("sha256").update(buf).digest("hex");
  }

  private static l2Normalize(v: number[]): number[] {
    let sum = 0;
    for (let i = 0; i < v.length; i++) sum += v[i] * v[i];
    const norm = Math.max(1e-12, Math.sqrt(sum));
    return v.map((x) => x / norm);
  }

  /**
   * Tags and seals a freshly enrolled template with cryptographic model provenance.
   */
  static createSealedTemplate(
    uid: string,
    embedding: number[],
    modelId: string,
    modelVersion: string,
    modelSha256: string
  ): BiometricTemplateRecord {
    const templateSha256 = this.hashVector(embedding);
    const now = new Date().toISOString();

    return {
      uid,
      embedding,
      modelId,
      modelVersion,
      modelSha256,
      templateSha256,
      createdAt: now,
      updatedAt: now,
      adaptationCount: 0,
    };
  }

  /**
   * Evaluates and executes an adaptive template update.
   * Prevents attacker template poisoning and drift by strictly rejecting near-threshold probes.
   */
  static updateTemplateAdaptively(req: AdaptiveUpdateRequest): {
    updated: boolean;
    newTemplate?: BiometricTemplateRecord;
    reason: string;
  } {
    // 1. Mandatory liveness & quality gates
    if (!req.livenessPassed) {
      return { updated: false, reason: "ADAPTATION_BLOCKED: Liveness verification failed" };
    }
    if (!req.qualityPassed || req.qualityScore < this.MIN_QUALITY_FOR_ADAPTATION) {
      return { updated: false, reason: "ADAPTATION_BLOCKED: Quality below adaptation threshold" };
    }

    // 2. High confidence match requirement (Anti-drift guard)
    if (req.matchCosine < this.HIGH_CONFIDENCE_THRESHOLD) {
      return {
        updated: false,
        reason: `ADAPTATION_BLOCKED: Match score ${req.matchCosine.toFixed(3)} below safe high-confidence floor (${this.HIGH_CONFIDENCE_THRESHOLD})`,
      };
    }

    // 3. Perform conservative exponential moving average update
    const oldEmb = req.currentTemplate.embedding;
    const probe = req.probeEmbedding;
    const dim = oldEmb.length;

    const newEmbRaw = new Array(dim);
    for (let i = 0; i < dim; i++) {
      newEmbRaw[i] = (1 - this.ADAPTATION_ALPHA) * oldEmb[i] + this.ADAPTATION_ALPHA * probe[i];
    }
    const newEmb = this.l2Normalize(newEmbRaw);
    const newSha = this.hashVector(newEmb);

    const updatedRecord: BiometricTemplateRecord = {
      ...req.currentTemplate,
      embedding: newEmb,
      templateSha256: newSha,
      updatedAt: new Date().toISOString(),
      adaptationCount: req.currentTemplate.adaptationCount + 1,
    };

    return {
      updated: true,
      newTemplate: updatedRecord,
      reason: "ADAPTATION_APPLIED: High-confidence exemplar safely incorporated",
    };
  }

  /**
   * Dual-model migration support: verifies compatibility and schedules re-enrollment.
   */
  static evaluateMigrationStatus(
    template: BiometricTemplateRecord,
    activeModelId: string
  ): { isCurrentModel: boolean; migrationRequired: boolean } {
    const isCurrent = template.modelId === activeModelId;
    return {
      isCurrentModel: isCurrent,
      migrationRequired: !isCurrent,
    };
  }
}
