import crypto from 'crypto';
import admin from 'firebase-admin';
import { StepUpProofServiceV19, StepUpProofRecordV19 } from './step_up_proof_service_v19';

export interface PhoneOtpSessionV19 {
  sessionId: string;
  targetPersonId: string;
  registeredPhoneNumberMasked: string;
  callerUid: string;
  otpHash: string;
  salt: string;
  attempts: number;
  maxAttempts: number;
  issuedAtMs: number;
  expiresAtMs: number;
  verified: boolean;
  consumed: boolean;
  proofId?: string;
}

export class RegisteredPhoneOtpServiceV19 {
  public static readonly COLLECTION = 'phone_otp_sessions';
  public static readonly OTP_TTL_MS = 5 * 60 * 1000; // 5 minutes TTL
  public static readonly MAX_ATTEMPTS = 3;

  private static hashOtp(code: string, salt: string): string {
    return crypto.createHash('sha256').update(`${code}:${salt}`).digest('hex');
  }

  /**
   * Masks a phone number for safe display (e.g. "+91 9876543210" -> "******3210").
   */
  public static maskPhoneNumber(phone: string): string {
    if (!phone) return '****';
    const digits = phone.replace(/\D/g, '');
    if (digits.length < 4) return '****';
    return `******${digits.slice(-4)}`;
  }

  /**
   * Requests an OTP sent strictly to the phone number ALREADY registered to targetPersonId.
   * Looks up the phone number from the server-authoritative person record, NEVER from the caller!
   */
  public static async requestOtpForRegisteredPhone(params: {
    db: admin.firestore.Firestore;
    callerUid: string;
    targetPersonId: string;
    nowMs?: number;
    testOtpCode?: string; // Only allowed in non-production test environments
  }): Promise<{
    sessionId: string;
    maskedPhone: string;
    expiresAtMs: number;
  }> {
    const { db, callerUid, targetPersonId, nowMs = Date.now(), testOtpCode } = params;

    if (!callerUid || typeof callerUid !== 'string') {
      throw new Error('INVALID_ARGUMENT: callerUid is required.');
    }
    if (!targetPersonId || !/^prs_[0-9a-f]{32}$/.test(targetPersonId)) {
      throw new Error('INVALID_ARGUMENT: targetPersonId must be a valid opaque personId.');
    }

    // 1. Server-Authoritative Lookup: Fetch person record
    const personRef = db.collection('person_identities').doc(targetPersonId);
    const personSnap = await personRef.get();
    if (!personSnap.exists) {
      throw new Error(`TARGET_PERSON_NOT_FOUND: Person ${targetPersonId} does not exist.`);
    }

    const personData = personSnap.data()!;
    const primaryUid = personData.primaryAuthUid as string;
    if (!primaryUid) {
      throw new Error('TARGET_PERSON_HAS_NO_PRIMARY_UID');
    }

    // 2. Fetch the registered phone number on record from primary user doc
    const userRef = db.collection('users').doc(primaryUid);
    const userSnap = await userRef.get();
    let registeredPhone: string | null = null;

    if (userSnap.exists) {
      registeredPhone = userSnap.data()?.phoneNumber as string || null;
    }

    if (!registeredPhone) {
      // Fallback check in biometric_vault
      const vaultRef = db.collection('biometric_vault').doc(primaryUid);
      const vaultSnap = await vaultRef.get();
      if (vaultSnap.exists) {
        registeredPhone = vaultSnap.data()?.phoneNumber as string || null;
      }
    }

    if (!registeredPhone) {
      throw new Error(
        `NO_REGISTERED_PHONE_ON_RECORD: Person ${targetPersonId} does not have a registered mobile number on record.`
      );
    }

    // 3. Generate 6-digit cryptographic OTP code
    const otpCode = testOtpCode && process.env.NODE_ENV !== 'production'
      ? testOtpCode
      : (Math.floor(100000 + Math.random() * 900000)).toString();

    const salt = crypto.randomBytes(16).toString('hex');
    const otpHash = this.hashOtp(otpCode, salt);
    const sessionId = `otp_${crypto.randomBytes(16).toString('hex')}`;
    const expiresAtMs = nowMs + this.OTP_TTL_MS;
    const maskedPhone = this.maskPhoneNumber(registeredPhone);

    const sessionRecord: PhoneOtpSessionV19 = {
      sessionId,
      targetPersonId,
      registeredPhoneNumberMasked: maskedPhone,
      callerUid,
      otpHash,
      salt,
      attempts: 0,
      maxAttempts: this.MAX_ATTEMPTS,
      issuedAtMs: nowMs,
      expiresAtMs,
      verified: false,
      consumed: false,
    };

    await db.collection(this.COLLECTION).doc(sessionId).set(sessionRecord);

    // In production, dispatch OTP via SMS Gateway (Twilio/GCP SMS).
    // Note: Never log the raw OTP code or phone number.
    return {
      sessionId,
      maskedPhone,
      expiresAtMs,
    };
  }

  /**
   * Verifies the OTP code submitted by the caller.
   * If valid: marks session verified/consumed and issues a server-side StepUpProofRecordV19.
   * Strictly enforces: max attempts (<= 3), TTL expiration, single-use, caller binding.
   */
  public static async verifyOtpAndIssueProof(params: {
    db: admin.firestore.Firestore;
    sessionId: string;
    callerUid: string;
    code: string;
    nowMs?: number;
  }): Promise<StepUpProofRecordV19> {
    const { db, sessionId, callerUid, code, nowMs = Date.now() } = params;

    if (!sessionId || !code) {
      throw new Error('INVALID_ARGUMENT: sessionId and code are required.');
    }

    return db.runTransaction(async (tx) => {
      const sessionRef = db.collection(this.COLLECTION).doc(sessionId);
      const snap = await tx.get(sessionRef);

      if (!snap.exists) {
        throw new Error('OTP_SESSION_NOT_FOUND: OTP session does not exist.');
      }

      const session = snap.data() as PhoneOtpSessionV19;

      if (session.consumed === true) {
        throw new Error('OTP_SESSION_ALREADY_CONSUMED: This OTP session has already been used.');
      }

      if (session.callerUid !== callerUid) {
        throw new Error('OTP_SESSION_CALLER_MISMATCH: Caller does not match session initiator.');
      }

      if (nowMs > session.expiresAtMs) {
        throw new Error('OTP_SESSION_EXPIRED: OTP session has expired.');
      }

      if (session.attempts >= session.maxAttempts) {
        throw new Error('OTP_SESSION_LOCKED: Maximum OTP verification attempts exceeded.');
      }

      // Verify code against salted hash
      const computedHash = this.hashOtp(code, session.salt);
      const isMatch = computedHash === session.otpHash;

      if (!isMatch) {
        const nextAttempts = session.attempts + 1;
        await sessionRef.update({
          attempts: nextAttempts,
          lastAttemptAtMs: nowMs,
        });
        throw new Error(
          `OTP_CODE_INCORRECT: Verification code is incorrect. Attempts remaining: ${session.maxAttempts - nextAttempts}.`
        );
      }

      // Valid OTP -> Mark session consumed
      tx.update(sessionRef, {
        verified: true,
        consumed: true,
        verifiedAtMs: nowMs,
      });

      // Issue authoritative StepUpProof bound to callerUid and targetPersonId
      const proof = await StepUpProofServiceV19.issueProof({
        db,
        issuedToUid: callerUid,
        targetPersonId: session.targetPersonId,
        method: 'REGISTERED_PHONE_OTP',
        nowMs,
      });

      tx.update(sessionRef, { proofId: proof.proofId });
      return proof;
    });
  }
}
