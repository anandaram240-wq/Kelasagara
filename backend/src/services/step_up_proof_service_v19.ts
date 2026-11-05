import crypto from 'crypto';
import admin from 'firebase-admin';

export type StepUpMethod =
  | 'EXISTING_ACCOUNT_SIGN_IN'
  | 'REGISTERED_PHONE_OTP'
  | 'COMPLIANCE_OFFICER_REVIEW';

export interface StepUpProofRecordV19 {
  proofId: string;
  issuedToUid: string;
  targetPersonId: string;
  method: StepUpMethod;
  issuedAtMs: number;
  expiresAtMs: number;
  consumed: boolean;
  consumedAtMs: number | null;
  consumedByUid: string | null;
  revoked?: boolean;
  revokedAtMs?: number | null;
  revokeReason?: string;
  signature: string;
}

export class StepUpProofServiceV19 {
  public static readonly COLLECTION = 'step_up_proofs';
  public static readonly DEFAULT_TTL_MS = 5 * 60 * 1000; // 5 minutes TTL

  private static getServerSecret(): string {
    return (
      process.env.STEP_UP_PROOF_SECRET ||
      process.env.BIOMETRIC_ENCRYPTION_KEY ||
      'kelasagara_stepup_proof_master_secret_2026_v19_2'
    );
  }

  /**
   * Generates a tamper-evident HMAC-SHA256 signature for the step-up proof.
   */
  public static generateSignature(
    fields: {
      proofId: string;
      issuedToUid: string;
      targetPersonId: string;
      method: string;
      expiresAtMs: number;
    },
    secret: string = StepUpProofServiceV19.getServerSecret()
  ): string {
    const payload = `${fields.proofId}:${fields.issuedToUid}:${fields.targetPersonId}:${fields.method}:${fields.expiresAtMs}`;
    return crypto.createHmac('sha256', secret).update(payload).digest('hex');
  }

  /**
   * Issues a server-side, single-use, cryptographically signed step-up proof record.
   * Can ONLY be invoked by trusted backend code after successful verification.
   */
  public static async issueProof(params: {
    db: admin.firestore.Firestore;
    issuedToUid: string;
    targetPersonId: string;
    method: StepUpMethod;
    ttlMs?: number;
    nowMs?: number;
  }): Promise<StepUpProofRecordV19> {
    const {
      db,
      issuedToUid,
      targetPersonId,
      method,
      ttlMs = StepUpProofServiceV19.DEFAULT_TTL_MS,
      nowMs = Date.now(),
    } = params;

    if (!issuedToUid || typeof issuedToUid !== 'string') {
      throw new Error('INVALID_ARGUMENT: issuedToUid is required.');
    }
    if (!targetPersonId || !/^prs_[0-9a-f]{32}$/.test(targetPersonId)) {
      throw new Error('INVALID_ARGUMENT: targetPersonId must be a valid opaque personId.');
    }

    const proofId = `stp_${crypto.randomBytes(24).toString('hex')}`;
    const expiresAtMs = nowMs + ttlMs;

    const signature = this.generateSignature({
      proofId,
      issuedToUid,
      targetPersonId,
      method,
      expiresAtMs,
    });

    const record: StepUpProofRecordV19 = {
      proofId,
      issuedToUid,
      targetPersonId,
      method,
      issuedAtMs: nowMs,
      expiresAtMs,
      consumed: false,
      consumedAtMs: null,
      consumedByUid: null,
      revoked: false,
      signature,
    };

    await db.collection(this.COLLECTION).doc(proofId).set(record);
    return record;
  }

  /**
   * Validates and atomically consumes a step-up proof inside an existing Firestore transaction.
   * Strict security checks:
   * 1. Proof must exist in database.
   * 2. Proof must not be consumed (anti-replay).
   * 3. Proof must not be revoked.
   * 4. Proof must be issued to the exact calling authenticated UID.
   * 5. Proof must target the exact target personId.
   * 6. Proof must not be expired.
   * 7. HMAC-SHA256 signature must be mathematically valid (anti-tampering).
   */
  public static async verifyAndConsumeInTransaction(params: {
    tx: admin.firestore.Transaction;
    db: admin.firestore.Firestore;
    proofId: string;
    callerUid: string;
    targetPersonId: string;
    nowMs?: number;
  }): Promise<StepUpProofRecordV19> {
    const {
      tx,
      db,
      proofId,
      callerUid,
      targetPersonId,
      nowMs = Date.now(),
    } = params;

    if (!proofId || typeof proofId !== 'string') {
      throw new Error('FORGED_STEP_UP_PROOF_REJECTED: Missing or malformed proofId.');
    }

    const proofRef = db.collection(this.COLLECTION).doc(proofId);
    const snap = await tx.get(proofRef);

    if (!snap.exists) {
      throw new Error(`STEP_UP_PROOF_NOT_FOUND: Proof ${proofId} does not exist in store.`);
    }

    const data = snap.data() as StepUpProofRecordV19;

    if (data.consumed === true) {
      throw new Error(
        `STEP_UP_PROOF_REPLAY_DETECTED: Proof ${proofId} was already consumed at ${data.consumedAtMs} by ${data.consumedByUid}.`
      );
    }

    if (data.revoked === true) {
      throw new Error(
        `STEP_UP_PROOF_REVOKED: Proof ${proofId} has been revoked (${data.revokeReason || 'no reason provided'}).`
      );
    }

    if (data.issuedToUid !== callerUid) {
      throw new Error(
        `STEP_UP_PROOF_CALLER_MISMATCH: Proof ${proofId} was issued to ${data.issuedToUid}, but caller is ${callerUid}.`
      );
    }

    if (data.targetPersonId !== targetPersonId) {
      throw new Error(
        `STEP_UP_PROOF_TARGET_MISMATCH: Proof ${proofId} was issued for target ${data.targetPersonId}, but requested target is ${targetPersonId}.`
      );
    }

    if (nowMs > data.expiresAtMs) {
      throw new Error(
        `STEP_UP_PROOF_EXPIRED: Proof ${proofId} expired at ${data.expiresAtMs} (current time: ${nowMs}).`
      );
    }

    // Verify cryptographic signature
    const expectedSig = this.generateSignature({
      proofId: data.proofId,
      issuedToUid: data.issuedToUid,
      targetPersonId: data.targetPersonId,
      method: data.method,
      expiresAtMs: data.expiresAtMs,
    });

    if (
      !crypto.timingSafeEqual(
        Buffer.from(data.signature, 'hex'),
        Buffer.from(expectedSig, 'hex')
      )
    ) {
      throw new Error(
        `STEP_UP_PROOF_SIGNATURE_INVALID: Cryptographic signature mismatch on proof ${proofId}.`
      );
    }

    // Atomically consume the proof inside the transaction
    tx.update(proofRef, {
      consumed: true,
      consumedAtMs: nowMs,
      consumedByUid: callerUid,
    });

    return {
      ...data,
      consumed: true,
      consumedAtMs: nowMs,
      consumedByUid: callerUid,
    };
  }

  /**
   * Revokes an existing proof (e.g. on security suspicion or session reset).
   */
  public static async revokeProof(params: {
    db: admin.firestore.Firestore;
    proofId: string;
    revokedByUid: string;
    reason: string;
    nowMs?: number;
  }): Promise<void> {
    const { db, proofId, revokedByUid, reason, nowMs = Date.now() } = params;
    const proofRef = db.collection(this.COLLECTION).doc(proofId);
    await proofRef.update({
      revoked: true,
      revokedAtMs: nowMs,
      revokeReason: `REVOKED_BY_${revokedByUid}: ${reason}`,
    });
  }
}
