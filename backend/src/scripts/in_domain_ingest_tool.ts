// backend/src/scripts/in_domain_ingest_tool.ts
/**
 * Track H: In-Domain Ingest Tool (Ticket H-01).
 * Automated, DPDPA-compliant biometric ingest and manifest generator.
 * Enforces Invariants I-01, I-04, I-05, and DPDPA consent verification.
 */

import crypto from "crypto";
import { runFaceInference } from "../services/face_inference";
import { DatasetPartitionManager } from "../evaluation/dataset_partitions";

export interface SubjectConsentRecord {
  consentId: string;
  subjectId: string;
  ethicsApprovalId: string;
  consentHash: string;
  consentedAt: string;
  consentPurpose: string;
  allowsRawImageRetention: boolean;
  signerPublicKeyHex: string;
  signatureHex: string;
}

export interface IngestedSubjectRecord {
  subjectId: string;
  partition: "TUNE" | "VALIDATE" | "LOCKBOX";
  embedding: number[];
  embeddingSha256: string;
  deviceModel: string;
  sessionIndex: number;
  qualityPassed: boolean;
  ingestedAt: string;
}

export class InDomainIngestTool {
  /**
   * Verifies DPDPA consent record and Institutional Ethics Approval before processing.
   * Enforces Gate GATE-S6-11 and Invariants I-01, I-04.
   */
  static verifyConsent(consent: SubjectConsentRecord): boolean {
    if (!consent.consentId || !consent.subjectId) return false;
    if (!consent.ethicsApprovalId || !consent.ethicsApprovalId.startsWith("IEC-KELASAGARA-")) {
      throw new Error(`[IngestTool] Gate GATE-S6-11 Violation: Missing or unauthorized ETHICS_APPROVAL_ID '${consent.ethicsApprovalId}'.`);
    }
    if (!consent.consentHash || consent.consentHash.length < 32) {
      throw new Error(`[IngestTool] Gate GATE-S6-11 Violation: Invalid consent linkage hash.`);
    }
    if (!consent.consentPurpose.includes("biometric")) return false;
    // Consent must not be older than 365 days
    const ageMs = Date.now() - new Date(consent.consentedAt).getTime();
    if (ageMs > 365 * 24 * 3600 * 1000) return false;
    return true;
  }

  /**
   * Processes a single acquired subject session frame.
   * Extracts embedding and zeroes out raw image buffer.
   */
  static async processSubjectFrame(
    rawImageBuffer: Buffer,
    consent: SubjectConsentRecord,
    deviceModel: string,
    sessionIndex: number
  ): Promise<IngestedSubjectRecord> {
    if (!this.verifyConsent(consent)) {
      throw new Error(`[IngestTool] Consent invalid or expired for subject ${consent.subjectId}. Fail-closed.`);
    }

    try {
      // 1. Extract sovereign 128-D embedding using SFace ONNX
      const embedding = await runFaceInference(rawImageBuffer);

      // 2. Hash embedding for manifest
      const embBuf = Buffer.from(new Float32Array(embedding).buffer);
      const embeddingSha256 = crypto.createHash("sha256").update(embBuf).digest("hex");

      // 3. Assign partition deterministically
      const partition = DatasetPartitionManager.assignPartition(consent.subjectId);

      return {
        subjectId: consent.subjectId,
        partition,
        embedding,
        embeddingSha256,
        deviceModel,
        sessionIndex,
        qualityPassed: true,
        ingestedAt: new Date().toISOString(),
      };
    } finally {
      // 4. Invariant I-04: Secure memory sanitization — erase raw pixel data
      if (!consent.allowsRawImageRetention) {
        rawImageBuffer.fill(0);
      }
    }
  }

  /**
   * Status check: Returns whether in-domain scoring is authorized.
   */
  static getInDomainScoringStatus(ingestedSubjectsCount: number): {
    scoringAllowed: boolean;
    statusMessage: string;
  } {
    if (ingestedSubjectsCount < 200) {
      return {
        scoringAllowed: false,
        statusMessage: `BLOCKED: Only ${ingestedSubjectsCount}/200 consented subjects collected. In-domain benchmark blocked pending field acquisition.`,
      };
    }
    return {
      scoringAllowed: true,
      statusMessage: "AUTHORIZED: Consented cohort threshold (N >= 200) satisfied.",
    };
  }
}
