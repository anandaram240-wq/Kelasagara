// File: backend/src/biometrics/identity_contract_v10.ts
import { createHmac, randomBytes, timingSafeEqual } from 'crypto';

/**
 * Business Account Onboarding & Access State (Managed by Worker/Hirer Onboarding Rules).
 * Biometric operations MUST NOT arbitrarily promote a 'suspended' or 'pending_profile'
 * account to 'approved' unless the onboarding state machine explicitly transitions from 'pending_face'.
 */
export type KelasagaraAccountStatus =
  | 'pending_profile'
  | 'pending_face'
  | 'pending_review'
  | 'approved'
  | 'suspended';

/**
 * Dedicated Biometric Lifecycle State (Part 3.2).
 */
export type BiometricLifecycleState =
  | 'UNENROLLED'
  | 'ENROLLMENT_PENDING'
  | 'ACTIVE'
  | 'RE_ENROLLMENT_PENDING'
  | 'REVIEW_REQUIRED'
  | 'LOCKED'
  | 'REVOKED'
  | 'RECOVERY_REQUIRED';

export type BiometricWorkflowType =
  | 'INITIAL_ENROLLMENT'
  | 'EXISTING_ACCOUNT_VERIFY_1TO1'
  | 'AUTHORIZED_REPLACEMENT'
  | 'TEMPLATE_REVOCATION';

export type BiometricOperationState =
  | 'RECEIVED_NOT_STARTED'
  | 'IN_PROGRESS'
  | 'COMMITTED'
  | 'REJECTED'
  | 'EXPIRED'
  | 'RETRYABLE_FAILURE';

export type StructuredBiometricCode =
  | 'NO_MATCH'
  | 'VERIFIED_1TO1'
  | 'GENUINE_USER_MISMATCH'
  | 'ALREADY_ENROLLED'
  | 'FACE_ALREADY_LINKED'
  | 'AMBIGUOUS_MATCH'
  | 'QUALITY_REJECTED'
  | 'LIVENESS_FAILED'
  | 'CHALLENGE_EXPIRED'
  | 'INVALID_OPERATION_STATE'
  | 'RETRY_REQUIRED'
  | 'MODEL_UNAVAILABLE'
  | 'INDEX_UNAVAILABLE'
  | 'KMS_UNAVAILABLE'
  | 'UNAUTHORIZED'
  | 'RATE_LIMITED'
  | 'RECOVERY_REQUIRED';

export interface SignedEnrollmentReceiptPayload {
  uid: string;
  operationId: string;
  enrollmentId: string;
  enrollmentVersion: number;
  issuedAtMs: number;
  expiresAtMs: number;
  oneTimeRedemptionNonce: string;
}

export class BiometricOperationReceiptService {
  private static readonly RECEIPT_TTL_MS = 10 * 60 * 1000; // 10 minutes

  constructor(private readonly serverHmacSecret: Buffer) {
    if (!serverHmacSecret || serverHmacSecret.byteLength < 32) {
      throw new Error('RECEIPT_HMAC_SECRET_MUST_BE_AT_LEAST_32_BYTES');
    }
  }

  public issueSignedReceipt(params: {
    uid: string;
    operationId: string;
    enrollmentId: string;
    enrollmentVersion: number;
    nowMs?: number;
  }): { receiptToken: string; payload: SignedEnrollmentReceiptPayload } {
    const nowMs = params.nowMs ?? Date.now();
    const payload: SignedEnrollmentReceiptPayload = {
      uid: params.uid,
      operationId: params.operationId,
      enrollmentId: params.enrollmentId,
      enrollmentVersion: params.enrollmentVersion,
      issuedAtMs: nowMs,
      expiresAtMs: nowMs + BiometricOperationReceiptService.RECEIPT_TTL_MS,
      oneTimeRedemptionNonce: randomBytes(16).toString('base64url'),
    };

    const encodedPayload = Buffer.from(JSON.stringify(payload), 'utf8').toString('base64url');
    const signature = createHmac('sha256', this.serverHmacSecret)
      .update(encodedPayload)
      .digest('base64url');

    return {
      receiptToken: `${encodedPayload}.${signature}`,
      payload,
    };
  }

  public verifySignedReceipt(
    receiptToken: string,
    expectedUid: string,
    nowMs: number = Date.now()
  ): SignedEnrollmentReceiptPayload {
    const parts = receiptToken.split('.');
    if (parts.length !== 2) {
      throw new Error('MALFORMED_RECEIPT_TOKEN');
    }
    const [encodedPayload, providedSig] = parts;
    const expectedSig = createHmac('sha256', this.serverHmacSecret)
      .update(encodedPayload)
      .digest();
    const actualSig = Buffer.from(providedSig, 'base64url');

    if (
      expectedSig.byteLength !== actualSig.byteLength ||
      !timingSafeEqual(expectedSig, actualSig)
    ) {
      throw new Error('INVALID_RECEIPT_SIGNATURE');
    }

    const payload = JSON.parse(
      Buffer.from(encodedPayload, 'base64url').toString('utf8')
    ) as SignedEnrollmentReceiptPayload;

    if (payload.uid !== expectedUid) {
      throw new Error('RECEIPT_UID_MISMATCH');
    }
    if (nowMs > payload.expiresAtMs) {
      throw new Error('RECEIPT_EXPIRED');
    }
    return payload;
  }
}
