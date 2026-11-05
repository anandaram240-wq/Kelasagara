// backend/src/services/tamper_evident_audit.ts
import crypto from "crypto";
import {
  BiometricAuditEventType,
  BiometricAuditLogDoc,
} from "../schemas/data_architecture_schemas";

export const GENESIS_PREVIOUS_HASH =
  "0000000000000000000000000000000000000000000000000000000000000000";

export class AuditIntegrityViolationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "AuditIntegrityViolationError";
  }
}

/**
 * Deterministically serialize any object into canonical JSON with sorted keys.
 */
export function canonicalJsonStringify(obj: any): string {
  if (obj === null || typeof obj !== "object") {
    return JSON.stringify(obj);
  }
  if (Array.isArray(obj)) {
    return "[" + obj.map((item) => canonicalJsonStringify(item)).join(",") + "]";
  }
  const keys = Object.keys(obj).sort();
  const pairs = keys.map(
    (key) => `${JSON.stringify(key)}:${canonicalJsonStringify(obj[key])}`
  );
  return "{" + pairs.join(",") + "}";
}

/**
 * Computes the SHA-256 hash of an audit log event using canonical formatting.
 */
export function computeAuditLogHash(params: {
  sequenceNumber: number;
  previousLogHash: string;
  eventType: BiometricAuditEventType;
  uid: string;
  timestamp: string;
  matchedUid?: string;
  similarityScore?: number;
  metadata?: Record<string, any>;
}): string {
  const canonicalPayload = canonicalJsonStringify({
    matchedUid: params.matchedUid || null,
    similarityScore: params.similarityScore !== undefined ? params.similarityScore : null,
    metadata: params.metadata || {},
  });

  const rawMessage = `${params.sequenceNumber}|${params.previousLogHash}|${params.eventType}|${params.uid}|${params.timestamp}|${canonicalPayload}`;
  return crypto.createHash("sha256").update(rawMessage, "utf8").digest("hex");
}

export class TamperEvidentAuditService {
  private inMemoryChain: BiometricAuditLogDoc[] = [];
  private currentSequenceNumber = 0;
  private lastHash: string = GENESIS_PREVIOUS_HASH;

  /**
   * Appends an event to the tamper-evident hash chain.
   */
  createChainedEvent(params: {
    eventId: string;
    eventType: BiometricAuditEventType;
    uid: string;
    matchedUid?: string;
    attemptingPhone?: string;
    similarityScore?: number;
    threshold?: number;
    metadata?: Record<string, any>;
    customTimestamp?: string;
  }): BiometricAuditLogDoc {
    this.currentSequenceNumber += 1;
    const timestamp = params.customTimestamp || new Date().toISOString();
    const previousLogHash = this.lastHash;

    const currentLogHash = computeAuditLogHash({
      sequenceNumber: this.currentSequenceNumber,
      previousLogHash,
      eventType: params.eventType,
      uid: params.uid,
      timestamp,
      matchedUid: params.matchedUid,
      similarityScore: params.similarityScore,
      metadata: params.metadata,
    });

    const doc: BiometricAuditLogDoc = {
      eventId: params.eventId,
      sequenceNumber: this.currentSequenceNumber,
      previousLogHash,
      currentLogHash,
      timestamp,
      eventType: params.eventType,
      uid: params.uid,
      matchedUid: params.matchedUid,
      attemptingPhone: params.attemptingPhone,
      similarityScore: params.similarityScore,
      threshold: params.threshold,
      service: "kelasagara_biomatch_backend",
      version: "v7.0.0",
      metadata: params.metadata,
    };

    this.inMemoryChain.push(doc);
    this.lastHash = currentLogHash;
    return doc;
  }

  /**
   * Returns current chain records.
   */
  getChain(): BiometricAuditLogDoc[] {
    return [...this.inMemoryChain];
  }

  /**
   * Resets or seeds the chain (for testing or bootstrap).
   */
  seedChain(logs: BiometricAuditLogDoc[]): void {
    this.inMemoryChain = [...logs];
    if (logs.length > 0) {
      this.currentSequenceNumber = logs[logs.length - 1].sequenceNumber;
      this.lastHash = logs[logs.length - 1].currentLogHash;
    } else {
      this.currentSequenceNumber = 0;
      this.lastHash = GENESIS_PREVIOUS_HASH;
    }
  }

  /**
   * Validates the cryptographic integrity of an audit chain.
   * Invariant I-17: Detects any modification, deletion, or insertion of audit events.
   */
  static verifyChainIntegrity(chain: BiometricAuditLogDoc[]): {
    isValid: boolean;
    recordsVerified: number;
    error?: string;
  } {
    if (chain.length === 0) {
      return { isValid: true, recordsVerified: 0 };
    }

    let expectedPrevHash = GENESIS_PREVIOUS_HASH;

    for (let i = 0; i < chain.length; i++) {
      const record = chain[i];
      const expectedSeq = i + 1;

      // 1. Verify sequence order
      if (record.sequenceNumber !== expectedSeq) {
        throw new AuditIntegrityViolationError(
          `Sequence break at index ${i}: expected sequenceNumber ${expectedSeq}, got ${record.sequenceNumber}. Possible record deletion or reordering.`
        );
      }

      // 2. Verify previousLogHash link
      if (record.previousLogHash !== expectedPrevHash) {
        throw new AuditIntegrityViolationError(
          `Hash chain broken at sequence ${record.sequenceNumber}: previousLogHash '${record.previousLogHash}' does not match expected '${expectedPrevHash}'. Possible record tampering or splicing.`
        );
      }

      // 3. Recalculate and verify current record hash
      const ts =
        typeof record.timestamp === "string"
          ? record.timestamp
          : record.timestamp?.toISOString
          ? record.timestamp.toISOString()
          : String(record.timestamp);

      const computedHash = computeAuditLogHash({
        sequenceNumber: record.sequenceNumber,
        previousLogHash: record.previousLogHash,
        eventType: record.eventType,
        uid: record.uid,
        timestamp: ts,
        matchedUid: record.matchedUid,
        similarityScore: record.similarityScore,
        metadata: record.metadata,
      });

      if (computedHash !== record.currentLogHash) {
        throw new AuditIntegrityViolationError(
          `Record content tampered at sequence ${record.sequenceNumber}: recorded hash '${record.currentLogHash}' differs from recomputed '${computedHash}'. Field modification detected.`
        );
      }

      expectedPrevHash = record.currentLogHash;
    }

    return {
      isValid: true,
      recordsVerified: chain.length,
    };
  }
}
