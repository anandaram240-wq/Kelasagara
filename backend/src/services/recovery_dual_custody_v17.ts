/**
 * KELASAGARA V20.17: RECOVERY DUAL-CUSTODY AUTHORIZATION ENGINE
 *
 * Enforces strict multi-party authorization for biometric account unlock and recovery.
 * Adheres to dual-custody security standards:
 *
 * 1. Two Independent Authorization Holders:
 *    - Holder 1: Biometric Compliance Officer (BCO)
 *    - Holder 2: Independent Security Auditor (ISA)
 * 2. Non-Collusion Gate: The same individual CANNOT satisfy both approvals (holder1.id !== holder2.id).
 * 3. Exact Account & Case Binding: Token binds targetUid and opaque caseReference.
 * 4. Short-Lived Expiration: Max TTL of 15 minutes (900 seconds).
 * 5. Replay Protection: Single-use consumption; reused tokens are permanently blocked.
 * 6. Recovery Reference Isolation: Case references alone NEVER authorize account recovery.
 * 7. Replacement Factor Defense: An OTP sent to an unverified replacement phone cannot act
 *    as proof of ownership for the original biometric account.
 */

import * as crypto from 'crypto';

export interface DualCustodyApprover {
  officerId: string;
  role: 'BIOMETRIC_COMPLIANCE_OFFICER' | 'INDEPENDENT_SECURITY_AUDITOR';
  publicKeyPem: string;
}

export interface ApproverSignatureProof {
  officerId: string;
  signatureBase64: string;
  signedAtEpochMs: number;
}

export interface DualCustodyRecoveryToken {
  tokenId: string;
  targetUid: string;
  caseReference: string;
  issuedAtEpochMs: number;
  expiresAtEpochMs: number;
  approvalHolder1: ApproverSignatureProof;
  approvalHolder2: ApproverSignatureProof;
}

export interface RecoveryExecutionRequest {
  recoveryToken: DualCustodyRecoveryToken;
  targetUid: string;
  caseReference: string;
  replacementPhoneNumber?: string;
  hasVerifiedOriginalFactor?: boolean;
}

export interface RecoveryExecutionResult {
  allowed: boolean;
  errorCode?: string;
  errorMessage?: string;
  auditRecordId?: string;
}

export class RecoveryDualCustodyEngine {
  private consumedTokens = new Set<string>();
  private registeredApprovers = new Map<string, DualCustodyApprover>();

  /**
   * Registers authorized approver public keys.
   */
  public registerApprover(approver: DualCustodyApprover): void {
    this.registeredApprovers.set(approver.officerId, approver);
  }

  /**
   * Canonical string payload signed by each custody holder.
   */
  public getSignablePayload(
    targetUid: string,
    caseReference: string,
    issuedAtEpochMs: number,
    expiresAtEpochMs: number
  ): string {
    return `${targetUid}|${caseReference}|${issuedAtEpochMs}|${expiresAtEpochMs}`;
  }

  /**
   * Signs approval proof for an approver.
   */
  public createApproverProof(
    officerId: string,
    privateKeyPem: string,
    targetUid: string,
    caseReference: string,
    issuedAtEpochMs: number,
    expiresAtEpochMs: number
  ): ApproverSignatureProof {
    const payload = this.getSignablePayload(targetUid, caseReference, issuedAtEpochMs, expiresAtEpochMs);
    const sign = crypto.createSign('SHA256');
    sign.update(payload);
    sign.end();
    const signatureBase64 = sign.sign(privateKeyPem, 'base64');

    return {
      officerId,
      signatureBase64,
      signedAtEpochMs: Date.now(),
    };
  }

  /**
   * Evaluates a proposed recovery token and execution request.
   */
  public evaluateRecoveryAuthorization(req: RecoveryExecutionRequest): RecoveryExecutionResult {
    const { recoveryToken, targetUid, caseReference } = req;

    // 1. Replay Protection: Token ID must not be consumed
    if (this.consumedTokens.has(recoveryToken.tokenId)) {
      return {
        allowed: false,
        errorCode: 'ERR_RECOVERY_TOKEN_REPLAYED',
        errorMessage: `REPLAY_PREVENTION_BLOCKED: Recovery token '${recoveryToken.tokenId}' has already been consumed.`,
      };
    }

    // 2. Token Expiry Check (Max 15 min TTL)
    const now = Date.now();
    if (now > recoveryToken.expiresAtEpochMs) {
      return {
        allowed: false,
        errorCode: 'ERR_RECOVERY_TOKEN_EXPIRED',
        errorMessage: `TOKEN_EXPIRED: Recovery authorization expired at epoch ${recoveryToken.expiresAtEpochMs}. Re-initiation required.`,
      };
    }

    if (recoveryToken.expiresAtEpochMs - recoveryToken.issuedAtEpochMs > 15 * 60 * 1000 + 1000) {
      return {
        allowed: false,
        errorCode: 'ERR_EXCESSIVE_TOKEN_TTL',
        errorMessage: 'TTL_EXCEEDED: Recovery token TTL cannot exceed 15 minutes.',
      };
    }

    // 3. Exact Account & Case Binding
    if (recoveryToken.targetUid !== targetUid) {
      return {
        allowed: false,
        errorCode: 'ERR_TARGET_UID_MISMATCH',
        errorMessage: `ACCOUNT_MISMATCH: Token is bound to '${recoveryToken.targetUid}', but recovery was requested for '${targetUid}'.`,
      };
    }

    if (recoveryToken.caseReference !== caseReference) {
      return {
        allowed: false,
        errorCode: 'ERR_CASE_REFERENCE_MISMATCH',
        errorMessage: `CASE_REF_MISMATCH: Token is bound to case '${recoveryToken.caseReference}', but requested case was '${caseReference}'.`,
      };
    }

    // 4. Non-Collusion Check: Two distinct officers required
    const h1 = recoveryToken.approvalHolder1;
    const h2 = recoveryToken.approvalHolder2;

    if (!h1 || !h2) {
      return {
        allowed: false,
        errorCode: 'ERR_INCOMPLETE_DUAL_CUSTODY',
        errorMessage: 'DUAL_CUSTODY_INCOMPLETE: Exactly two independent authorization proofs are required.',
      };
    }

    if (h1.officerId === h2.officerId) {
      return {
        allowed: false,
        errorCode: 'ERR_DUAL_CUSTODY_COLLUSION_SAME_OFFICER',
        errorMessage: `COLLUSION_BLOCKED: Holder 1 and Holder 2 are the same officer '${h1.officerId}'. Two distinct individuals are strictly mandatory.`,
      };
    }

    // 5. Verify Approver 1 Role & Signature
    const approver1 = this.registeredApprovers.get(h1.officerId);
    if (!approver1 || approver1.role !== 'BIOMETRIC_COMPLIANCE_OFFICER') {
      return {
        allowed: false,
        errorCode: 'ERR_UNAUTHORIZED_APPROVER_1',
        errorMessage: `UNAUTHORIZED_OFFICER: Holder 1 '${h1.officerId}' is not an authorized Biometric Compliance Officer.`,
      };
    }

    // 6. Verify Approver 2 Role & Signature
    const approver2 = this.registeredApprovers.get(h2.officerId);
    if (!approver2 || approver2.role !== 'INDEPENDENT_SECURITY_AUDITOR') {
      return {
        allowed: false,
        errorCode: 'ERR_UNAUTHORIZED_APPROVER_2',
        errorMessage: `UNAUTHORIZED_OFFICER: Holder 2 '${h2.officerId}' is not an authorized Independent Security Auditor.`,
      };
    }

    const payload = this.getSignablePayload(
      recoveryToken.targetUid,
      recoveryToken.caseReference,
      recoveryToken.issuedAtEpochMs,
      recoveryToken.expiresAtEpochMs
    );

    // Verify Sig 1
    const v1 = crypto.createVerify('SHA256');
    v1.update(payload);
    v1.end();
    if (!v1.verify(approver1.publicKeyPem, h1.signatureBase64, 'base64')) {
      return {
        allowed: false,
        errorCode: 'ERR_APPROVER_1_SIGNATURE_INVALID',
        errorMessage: 'SIGNATURE_INVALID: Cryptographic signature verification failed for Holder 1.',
      };
    }

    // Verify Sig 2
    const v2 = crypto.createVerify('SHA256');
    v2.update(payload);
    v2.end();
    if (!v2.verify(approver2.publicKeyPem, h2.signatureBase64, 'base64')) {
      return {
        allowed: false,
        errorCode: 'ERR_APPROVER_2_SIGNATURE_INVALID',
        errorMessage: 'SIGNATURE_INVALID: Cryptographic signature verification failed for Holder 2.',
      };
    }

    // 7. Replacement Factor Protection
    if (req.replacementPhoneNumber && !req.hasVerifiedOriginalFactor) {
      return {
        allowed: false,
        errorCode: 'ERR_REPLACEMENT_FACTOR_UNVERIFIED',
        errorMessage:
          'FACTOR_SECURITY_VIOLATION: An unverified replacement phone number cannot prove ownership of the original account without verified identity verification.',
      };
    }

    // Mark token as consumed
    this.consumedTokens.add(recoveryToken.tokenId);

    return {
      allowed: true,
      auditRecordId: `recovery-audit-${crypto.randomBytes(8).toString('hex')}`,
    };
  }
}
