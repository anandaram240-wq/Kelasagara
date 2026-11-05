// backend/src/services/audit_service.ts
import admin from "firebase-admin";
import crypto from "crypto";
import {
  BiometricAuditEventType,
  BiometricAuditLogDoc,
} from "../schemas/data_architecture_schemas";
import {
  computeAuditLogHash,
  GENESIS_PREVIOUS_HASH,
} from "./tamper_evident_audit";
import { maskPhoneNumber } from "./biometric_matching";

export interface BiometricAuditEvent {
  eventType: BiometricAuditEventType;
  uid: string;
  matchedUid?: string;
  attemptingPhone?: string;
  similarityScore?: number;
  threshold?: number;
  metadata?: Record<string, any>;
}

function sanitizeAuditMetadata(metadata?: Record<string, any>): Record<string, any> | undefined {
  if (!metadata) return undefined;
  const sanitized: Record<string, any> = {};
  for (const [key, val] of Object.entries(metadata)) {
    // Ticket T-06: Strict PII and heavy biometric artifact filtering
    if (/image|base64|buffer|embedding|vector|probe|raw|phone|mobile/i.test(key)) {
      continue;
    }
    sanitized[key] = val;
  }
  return sanitized;
}

export class AuditService {
  private static mockDbInstance: any = null;
  private static inMemoryLogs: Map<string, any> = new Map();

  public static setMockDb(db: any) {
    this.mockDbInstance = db;
  }

  public static clearInMemoryLogs(): void {
    this.inMemoryLogs.clear();
  }

  public static getInMemoryLogs(): any[] {
    return Array.from(this.inMemoryLogs.values());
  }

  public static isProductionEnvironment(): boolean {
    return process.env.NODE_ENV === "production";
  }

  public static get isDevTestMode(): boolean {
    // Under NO circumstances can volatile memory-only fallback be selected in production
    if (this.isProductionEnvironment()) {
      return false;
    }
    return (
      !process.env.GOOGLE_APPLICATION_CREDENTIALS &&
      !process.env.FIRESTORE_EMULATOR_HOST &&
      (process.env.ALLOW_DEV_TOKEN === "true" ||
        process.env.NODE_ENV === "test" ||
        process.env.NODE_ENV === "development")
    );
  }

  private static get db() {
    if (this.mockDbInstance) return this.mockDbInstance;
    return admin.firestore();
  }

  /**
   * Verifies the cryptographic hash-chain continuity across an ordered array of audit logs.
   * Returns true only if every record's previousLogHash equals the predecessor's currentLogHash.
   */
  public static verifyChainContinuity(logs: BiometricAuditLogDoc[]): boolean {
    if (!logs || logs.length === 0) return true;
    for (let i = 0; i < logs.length; i++) {
      const current = logs[i];
      if (i === 0) {
        if (current.sequenceNumber === 1 && current.previousLogHash !== GENESIS_PREVIOUS_HASH) {
          return false;
        }
      } else {
        const predecessor = logs[i - 1];
        if (current.previousLogHash !== predecessor.currentLogHash) {
          return false;
        }
        if (current.sequenceNumber !== predecessor.sequenceNumber + 1) {
          return false;
        }
      }
    }
    return true;
  }

  /**
   * Records a cryptographically hash-chained audit log event (Invariant I-17, Ticket T-06).
   * Strips all raw biometric templates, base64 buffers, and PII before persistence.
   * In production mode, volatile in-memory fallback is strictly blocked; failures throw if requireDurable is true.
   */
  static async logEvent(
    event: BiometricAuditEvent,
    options: { requireDurable?: boolean } = { requireDurable: true }
  ): Promise<BiometricAuditLogDoc | null> {
    try {
      const cleanMetadata = sanitizeAuditMetadata(event.metadata);

      if (this.isDevTestMode && !this.mockDbInstance) {
        // In-memory deterministic audit chaining explicitly for offline test/dev execution only
        let previousHash = GENESIS_PREVIOUS_HASH;
        let nextSeq = 1;
        const entries = Array.from(this.inMemoryLogs.values());
        if (entries.length > 0) {
          const lastEntry = entries[entries.length - 1];
          if (lastEntry.currentLogHash && typeof lastEntry.sequenceNumber === "number") {
            previousHash = lastEntry.currentLogHash;
            nextSeq = lastEntry.sequenceNumber + 1;
          }
        }
        const eventId = `audit_${Date.now()}_${crypto.randomBytes(4).toString("hex")}`;
        const nowIso = new Date().toISOString();
        const currentLogHash = computeAuditLogHash({
          sequenceNumber: nextSeq,
          previousLogHash: previousHash,
          eventType: event.eventType,
          uid: event.uid,
          timestamp: nowIso,
          matchedUid: event.matchedUid,
          similarityScore: event.similarityScore,
          metadata: cleanMetadata,
        });
        const auditRecord: any = {
          eventId,
          sequenceNumber: nextSeq,
          previousLogHash: previousHash,
          currentLogHash,
          timestamp: nowIso,
          eventType: event.eventType,
          uid: event.uid,
          service: "kelasagara_biomatch_backend",
          version: "v7.0.0",
        };
        if (event.matchedUid !== undefined) auditRecord.matchedUid = event.matchedUid;
        if (event.attemptingPhone !== undefined) auditRecord.attemptingPhone = maskPhoneNumber(event.attemptingPhone);
        if (event.similarityScore !== undefined) auditRecord.similarityScore = event.similarityScore;
        if (event.threshold !== undefined) auditRecord.threshold = event.threshold;
        if (cleanMetadata !== undefined) auditRecord.metadata = cleanMetadata;

        this.inMemoryLogs.set(eventId, auditRecord);
        return auditRecord as BiometricAuditLogDoc;
      }

      // If in production without durable credentials / persistence, reject in-memory downgrade
      if (this.isProductionEnvironment() && !process.env.GOOGLE_APPLICATION_CREDENTIALS && !this.mockDbInstance) {
        if (options.requireDurable) {
          throw new Error(
            "[AuditService] CRITICAL AUDIT FAILURE: Missing durable GCP credentials in production. Volatile fallback prohibited."
          );
        }
      }

      const logsRef = this.db.collection("biometric_audit_logs");

      // Query latest log to obtain previous hash and sequence number
      let previousHash = GENESIS_PREVIOUS_HASH;
      let nextSeq = 1;

      try {
        const latestSnap = await logsRef
          .orderBy("sequenceNumber", "desc")
          .limit(1)
          .get();

        if (!latestSnap.empty) {
          const latestDoc = latestSnap.docs[0].data();
          if (latestDoc.currentLogHash && typeof latestDoc.sequenceNumber === "number") {
            previousHash = latestDoc.currentLogHash;
            nextSeq = latestDoc.sequenceNumber + 1;
          }
        }
      } catch (queryErr) {
        // Fallback: If index is not yet built, proceed with default sequence/hash
        console.warn(
          "[AuditService] Could not retrieve predecessor log for chain link, using genesis fallback:",
          (queryErr as any).message
        );
      }

      const eventId = `audit_${Date.now()}_${crypto.randomBytes(4).toString("hex")}`;
      const nowIso = new Date().toISOString();

      const currentLogHash = computeAuditLogHash({
        sequenceNumber: nextSeq,
        previousLogHash: previousHash,
        eventType: event.eventType,
        uid: event.uid,
        timestamp: nowIso,
        matchedUid: event.matchedUid,
        similarityScore: event.similarityScore,
        metadata: cleanMetadata,
      });

      const auditRecord: Record<string, any> = {
        eventId,
        sequenceNumber: nextSeq,
        previousLogHash: previousHash,
        currentLogHash,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        eventType: event.eventType,
        uid: event.uid,
        service: "kelasagara_biomatch_backend",
        version: "v7.0.0",
      };
      if (event.matchedUid !== undefined) auditRecord.matchedUid = event.matchedUid;
      if (event.attemptingPhone !== undefined) auditRecord.attemptingPhone = maskPhoneNumber(event.attemptingPhone);
      if (event.similarityScore !== undefined) auditRecord.similarityScore = event.similarityScore;
      if (event.threshold !== undefined) auditRecord.threshold = event.threshold;
      if (cleanMetadata !== undefined) auditRecord.metadata = cleanMetadata;

      await logsRef.doc(eventId).set(auditRecord);
      return auditRecord as BiometricAuditLogDoc;
    } catch (error: any) {
      console.error("[AuditService] Failed to record audit log:", error.message);
      if (this.isProductionEnvironment() && options?.requireDurable !== false) {
        throw new Error(
          `[AuditService] CRITICAL AUDIT FAILURE: Durable audit write failed in production (${error.message}). Operation cannot proceed silently.`
        );
      }
      return null;
    }
  }
}
