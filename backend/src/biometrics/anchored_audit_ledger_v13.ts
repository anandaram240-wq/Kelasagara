/**
 * KELASAGARA V20.13 - WORKSTREAM E: ANCHORED BIOMETRIC AUDIT LEDGER WITH SIGNED CHECKPOINTS
 *
 * Implements:
 * 1. Monotonically sequenced, canonically hashed audit events using RFC 8785 JCS.
 * 2. Previous-event hash chaining with SHA-256.
 * 3. Asymmetric ECDSA-signed checkpoints anchored to an independent external authority.
 * 4. Tamper detection against:
 *    - Single event modification
 *    - Event insertion / deletion
 *    - Event reordering
 *    - Tail truncation
 *    - Entire history rewrite / recomputation by privileged DB actors.
 * 5. Strict data minimization: Zero biometric embeddings, raw photos, or full phone numbers.
 */

import crypto, { createHash, createSign, createVerify } from 'crypto';
import { canonicalizeJson, computeJcsSha256 } from '../crypto/rfc8785_canonicalizer';

export type AuditDecisionOutcome =
  | 'APPROVE_AS_DISTINCT_PERSON'
  | 'CONFIRM_DUPLICATE_ROUTE_TO_RECOVERY'
  | 'REQUEST_FRESH_RECAPTURE'
  | 'OWNERSHIP_VERIFIED'
  | 'CASE_CREATED'
  | 'REPLACEMENT_AUTHORIZED';

export interface AuditEventPayload {
  readonly sequenceNumber: number;
  readonly auditId: string;
  readonly caseId: string;
  readonly applicantUid: string;
  readonly actorId: string;
  readonly actorRole: 'BIOMETRIC_AUDITOR' | 'TRUST_AND_SAFETY_ADMIN' | 'SYSTEM' | 'RECOVERY_VERIFIER';
  readonly action: AuditDecisionOutcome;
  readonly justification: string;
  readonly metadata: {
    readonly stage1CosineScore?: number;
    readonly manifestVersion?: string;
    readonly verificationMethod?: string;
  };
  readonly timestampIso: string;
}

export interface ChainedAuditEvent {
  readonly payload: AuditEventPayload;
  readonly canonicalPayloadHash: string; // SHA-256 of RFC 8785 canonical payload bytes
  readonly previousChainHash: string;
  readonly entryHash: string;            // SHA-256(canonicalPayloadHash || previousChainHash)
}

export interface SignedLedgerCheckpoint {
  readonly checkpointId: string;
  readonly sequenceRange: {
    readonly startSeq: number;
    readonly endSeq: number;
  };
  readonly headEventHash: string;
  readonly cumulativeLedgerHash: string; // Merkle / cumulative hash over all entries
  readonly keyId: string;
  readonly keyVersion: number;
  readonly algorithm: 'ECDSA_P256_SHA256';
  readonly checkpointTimestampIso: string;
  readonly signatureBase64: string;
}

export class AnchoredAuditLedgerV13 {
  public static readonly GENESIS_HASH = 'KS_GENESIS_ANCHORED_AUDIT_V13_2026';

  private readonly events: ChainedAuditEvent[] = [];
  private readonly externalCheckpoints: SignedLedgerCheckpoint[] = [];
  private currentSeq = 0;

  /**
   * Appends an audit event to the ledger with canonical RFC 8785 serialization and hash chaining.
   */
  public appendEvent(params: {
    caseId: string;
    applicantUid: string;
    actorId: string;
    actorRole: 'BIOMETRIC_AUDITOR' | 'TRUST_AND_SAFETY_ADMIN' | 'SYSTEM' | 'RECOVERY_VERIFIER';
    action: AuditDecisionOutcome;
    justification: string;
    metadata?: {
      stage1CosineScore?: number;
      manifestVersion?: string;
      verificationMethod?: string;
    };
    nowIso?: string;
  }): ChainedAuditEvent {
    if (params.justification.trim().length < 5) {
      throw new Error('ERR_AUDIT_JUSTIFICATION_TOO_SHORT: Justification must be at least 5 characters.');
    }

    this.currentSeq++;
    const sequenceNumber = this.currentSeq;
    const auditId = `AUD-${sequenceNumber}-${crypto.randomBytes(8).toString('hex').toUpperCase()}`;
    const timestampIso = params.nowIso ?? new Date().toISOString();

    const payload: AuditEventPayload = {
      sequenceNumber,
      auditId,
      caseId: params.caseId,
      applicantUid: params.applicantUid,
      actorId: params.actorId,
      actorRole: params.actorRole,
      action: params.action,
      justification: params.justification.trim(),
      metadata: params.metadata ?? {},
      timestampIso,
    };

    const canonicalPayloadHash = computeJcsSha256(payload);

    const previousChainHash =
      this.events.length === 0
        ? AnchoredAuditLedgerV13.GENESIS_HASH
        : this.events[this.events.length - 1].entryHash;

    const entryHash = createHash('sha256')
      .update(`${canonicalPayloadHash}|${previousChainHash}`)
      .digest('hex');

    const chainedEvent: ChainedAuditEvent = {
      payload,
      canonicalPayloadHash,
      previousChainHash,
      entryHash,
    };

    this.events.push(chainedEvent);
    return chainedEvent;
  }

  /**
   * Generates a signed checkpoint over the current ledger state using an external asymmetric key.
   */
  public createSignedCheckpoint(params: {
    privateKeyPem: string;
    keyId: string;
    keyVersion: number;
    nowIso?: string;
  }): SignedLedgerCheckpoint {
    if (this.events.length === 0) {
      throw new Error('ERR_CHECKPOINT_EMPTY_LEDGER: Cannot create checkpoint on empty ledger.');
    }

    const startSeq = this.events[0].payload.sequenceNumber;
    const endSeq = this.events[this.events.length - 1].payload.sequenceNumber;
    const headEventHash = this.events[this.events.length - 1].entryHash;

    // Cumulative hash over all entry hashes
    const cumulativeLedgerHash = createHash('sha256')
      .update(this.events.map((e) => e.entryHash).join(','))
      .digest('hex');

    const checkpointId = `CHK-${endSeq}-${crypto.randomBytes(6).toString('hex').toUpperCase()}`;
    const checkpointTimestampIso = params.nowIso ?? new Date().toISOString();

    const checkpointPayload = {
      checkpointId,
      sequenceRange: { startSeq, endSeq },
      headEventHash,
      cumulativeLedgerHash,
      keyId: params.keyId,
      keyVersion: params.keyVersion,
      algorithm: 'ECDSA_P256_SHA256' as const,
      checkpointTimestampIso,
    };

    const canonicalBytes = Buffer.from(canonicalizeJson(checkpointPayload), 'utf8');

    const signer = createSign('SHA256');
    signer.update(canonicalBytes);
    signer.end();
    const signatureBase64 = signer.sign(params.privateKeyPem, 'base64');

    const checkpoint: SignedLedgerCheckpoint = {
      ...checkpointPayload,
      signatureBase64,
    };

    this.externalCheckpoints.push(checkpoint);
    return checkpoint;
  }

  /**
   * Verifies internal hash-chain integrity of the ledger.
   */
  public verifyInternalChain(): { valid: boolean; violationIndex?: number; reason?: string } {
    let expectedPrev = AnchoredAuditLedgerV13.GENESIS_HASH;
    let expectedSeq = 1;

    for (let i = 0; i < this.events.length; i++) {
      const e = this.events[i];

      // Sequence check
      if (e.payload.sequenceNumber !== expectedSeq) {
        return {
          valid: false,
          violationIndex: i,
          reason: `SEQUENCE_GAP_OR_REORDER: Expected seq ${expectedSeq}, got ${e.payload.sequenceNumber}.`,
        };
      }

      // Previous hash check
      if (e.previousChainHash !== expectedPrev) {
        return {
          valid: false,
          violationIndex: i,
          reason: `BROKEN_CHAIN: Entry ${i} previousChainHash does not match predecessor.`,
        };
      }

      // Canonical payload hash verification
      const recomputedPayloadHash = computeJcsSha256(e.payload);
      if (recomputedPayloadHash !== e.canonicalPayloadHash) {
        return {
          valid: false,
          violationIndex: i,
          reason: `PAYLOAD_TAMPERED: Entry ${i} payload does not match canonicalPayloadHash.`,
        };
      }

      // Entry hash verification
      const recomputedEntryHash = createHash('sha256')
        .update(`${e.canonicalPayloadHash}|${e.previousChainHash}`)
        .digest('hex');

      if (recomputedEntryHash !== e.entryHash) {
        return {
          valid: false,
          violationIndex: i,
          reason: `ENTRY_HASH_MISMATCH: Entry ${i} entryHash corrupted.`,
        };
      }

      expectedPrev = e.entryHash;
      expectedSeq++;
    }

    return { valid: true };
  }

  /**
   * Verifies the ledger against an externally retained signed checkpoint.
   * Defeats the "privileged actor rewrite" attack: even if a database administrator rewrites
   * every single event in the database and recomputes a valid internal chain,
   * verification against the external signed checkpoint fails immediately.
   */
  public verifyAgainstExternalCheckpoint(
    checkpoint: SignedLedgerCheckpoint,
    trustedPublicKeyPem: string
  ): { verified: boolean; reason?: string } {
    // 1. Verify cryptographic signature of the external checkpoint
    const checkpointPayload = {
      checkpointId: checkpoint.checkpointId,
      sequenceRange: checkpoint.sequenceRange,
      headEventHash: checkpoint.headEventHash,
      cumulativeLedgerHash: checkpoint.cumulativeLedgerHash,
      keyId: checkpoint.keyId,
      keyVersion: checkpoint.keyVersion,
      algorithm: checkpoint.algorithm,
      checkpointTimestampIso: checkpoint.checkpointTimestampIso,
    };

    const canonicalBytes = Buffer.from(canonicalizeJson(checkpointPayload), 'utf8');
    const verifier = createVerify('SHA256');
    verifier.update(canonicalBytes);
    verifier.end();

    const validSig = verifier.verify(trustedPublicKeyPem, checkpoint.signatureBase64, 'base64');
    if (!validSig) {
      return { verified: false, reason: 'CHECKPOINT_SIGNATURE_INVALID: Asymmetric checkpoint signature check failed.' };
    }

    // 2. Verify internal chain up to checkpoint range
    const chainCheck = this.verifyInternalChain();
    if (!chainCheck.valid) {
      return { verified: false, reason: `LEDGER_CHAIN_INVALID: ${chainCheck.reason}` };
    }

    // 3. Verify sequence length matches or exceeds checkpoint
    if (this.events.length < checkpoint.sequenceRange.endSeq) {
      return {
        verified: false,
        reason: `TAIL_TRUNCATION_DETECTED: Ledger has ${this.events.length} events, checkpoint requires ${checkpoint.sequenceRange.endSeq}.`,
      };
    }

    // 4. Verify head event hash at checkpoint sequence
    const eventAtCheckpoint = this.events[checkpoint.sequenceRange.endSeq - 1];
    if (eventAtCheckpoint.entryHash !== checkpoint.headEventHash) {
      return {
        verified: false,
        reason: 'FULL_HISTORY_REWRITE_DETECTED: Head event hash does not match externally signed checkpoint.',
      };
    }

    // 5. Verify cumulative ledger hash across sequence range
    const relevantEvents = this.events.slice(
      checkpoint.sequenceRange.startSeq - 1,
      checkpoint.sequenceRange.endSeq
    );
    const computedCumulative = createHash('sha256')
      .update(relevantEvents.map((e) => e.entryHash).join(','))
      .digest('hex');

    if (computedCumulative !== checkpoint.cumulativeLedgerHash) {
      return {
        verified: false,
        reason: 'LEDGER_CONTENTS_MISMATCH: Cumulative hash does not match externally signed checkpoint.',
      };
    }

    return { verified: true };
  }

  public getEvents(): readonly ChainedAuditEvent[] {
    return this.events;
  }

  public getCheckpoints(): readonly SignedLedgerCheckpoint[] {
    return this.externalCheckpoints;
  }
}
