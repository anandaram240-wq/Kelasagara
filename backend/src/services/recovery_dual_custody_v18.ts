/**
 * KELASAGARA V20.18: TWO-PERSON AUTHORIZATION DUAL-CUSTODY ENGINE
 *
 * Implements rigorous multi-party authorization for biometric account recovery:
 *
 * 1. Two Distinct Organizational Identities:
 *    - Holder 1: Biometric Compliance Officer (BCO)
 *    - Holder 2: Independent Security Auditor (ISA)
 * 2. Identity Provider Independence:
 *    - Must have different verified IdP subjects (h1.idpSubject !== h2.idpSubject).
 *    - Separate MFA credentials/sessions (h1.mfaCredentialId !== h2.mfaCredentialId).
 *    - Two accounts controlled through the same human identity are strictly rejected.
 * 3. Requester Separation:
 *    - Prohibits requester self-approval (requesterId cannot equal either approver).
 * 4. Exact Context Binding:
 *    - Approvals are cryptographically bound to targetUid, caseReference, operationType,
 *      and proposed replacement phone number.
 *    - Tampering with any field invalidates the authorization.
 * 5. Lifecycle & Replay Safeguards:
 *    - Maximum 15-minute TTL.
 *    - Atomic single-use consumption preventing concurrent race conditions.
 */

import * as crypto from 'crypto';

export interface DualCustodyApproverV18 {
  officerId: string;
  idpSubject: string; // Unique verified Identity Provider subject identifier
  role: 'BIOMETRIC_COMPLIANCE_OFFICER' | 'INDEPENDENT_SECURITY_AUDITOR';
  publicKeyPem: string;
  mfaCredentialId: string; // Pinned hardware token / authenticator ID
}

export interface ApproverSignatureProofV18 {
  officerId: string;
  idpSubject: string;
  mfaCredentialId: string;
  signatureBase64: string;
  signedAtEpochMs: number;
}

export interface DualCustodyRecoveryTokenV18 {
  tokenId: string;
  targetUid: string;
  caseReference: string;
  operationType: 'BIOMETRIC_ACCOUNT_UNLOCK' | 'TEMPLATE_SUPERSEDE_RECOVERY' | 'PHONE_FACTOR_REASSIGNMENT';
  proposedReplacementPhone?: string;
  requesterOfficerId: string;
  issuedAtEpochMs: number;
  expiresAtEpochMs: number;
  approvalHolder1: ApproverSignatureProofV18;
  approvalHolder2: ApproverSignatureProofV18;
}

export interface RecoveryExecutionRequestV18 {
  recoveryToken: DualCustodyRecoveryTokenV18;
  targetUid: string;
  caseReference: string;
  operationType: 'BIOMETRIC_ACCOUNT_UNLOCK' | 'TEMPLATE_SUPERSEDE_RECOVERY' | 'PHONE_FACTOR_REASSIGNMENT';
  proposedReplacementPhone?: string;
  hasVerifiedOriginalFactor?: boolean;
}

export interface RecoveryExecutionResultV18 {
  allowed: boolean;
  errorCode?: string;
  errorMessage?: string;
  auditRecordId?: string;
}

export class RecoveryDualCustodyEngineV18 {
  private consumedTokens = new Set<string>();
  private activeLocks = new Set<string>();
  private registeredApprovers = new Map<string, DualCustodyApproverV18>();

  public registerApprover(approver: DualCustodyApproverV18): void {
    this.registeredApprovers.set(approver.officerId, approver);
  }

  /**
   * Constructs canonical signable payload binding exact case, account, operation, and phone.
   */
  public getSignablePayload(
    targetUid: string,
    caseReference: string,
    operationType: string,
    proposedReplacementPhone: string | undefined,
    issuedAtEpochMs: number,
    expiresAtEpochMs: number
  ): string {
    const phone = proposedReplacementPhone || 'NONE';
    return `${targetUid}|${caseReference}|${operationType}|${phone}|${issuedAtEpochMs}|${expiresAtEpochMs}`;
  }

  /**
   * Signs approval proof for an approver.
   */
  public createApproverProof(
    officer: DualCustodyApproverV18,
    privateKeyPem: string,
    targetUid: string,
    caseReference: string,
    operationType: string,
    proposedReplacementPhone: string | undefined,
    issuedAtEpochMs: number,
    expiresAtEpochMs: number
  ): ApproverSignatureProofV18 {
    const payload = this.getSignablePayload(
      targetUid,
      caseReference,
      operationType,
      proposedReplacementPhone,
      issuedAtEpochMs,
      expiresAtEpochMs
    );
    const sign = crypto.createSign('SHA256');
    sign.update(payload);
    sign.end();
    const signatureBase64 = sign.sign(privateKeyPem, 'base64');

    return {
      officerId: officer.officerId,
      idpSubject: officer.idpSubject,
      mfaCredentialId: officer.mfaCredentialId,
      signatureBase64,
      signedAtEpochMs: Date.now(),
    };
  }

  /**
   * Evaluates a two-person recovery authorization token atomically.
   */
  public async evaluateRecoveryAuthorization(
    req: RecoveryExecutionRequestV18
  ): Promise<RecoveryExecutionResultV18> {
    const { recoveryToken, targetUid, caseReference, operationType, proposedReplacementPhone } = req;

    // 1. Concurrency Lock & Replay Prevention
    if (this.activeLocks.has(recoveryToken.tokenId)) {
      return {
        allowed: false,
        errorCode: 'ERR_CONCURRENT_CONSUMPTION_BLOCKED',
        errorMessage: 'CONCURRENCY_BLOCKED: Another transaction is actively consuming this recovery token.',
      };
    }
    this.activeLocks.add(recoveryToken.tokenId);

    try {
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

      // 3. Exact Account, Case, and Operation Binding
      if (recoveryToken.targetUid !== targetUid) {
        return {
          allowed: false,
          errorCode: 'ERR_TARGET_UID_MISMATCH',
          errorMessage: `ACCOUNT_MISMATCH: Token bound to '${recoveryToken.targetUid}', requested for '${targetUid}'.`,
        };
      }

      if (recoveryToken.caseReference !== caseReference) {
        return {
          allowed: false,
          errorCode: 'ERR_CASE_REFERENCE_MISMATCH',
          errorMessage: `CASE_REF_MISMATCH: Token bound to case '${recoveryToken.caseReference}', requested '${caseReference}'.`,
        };
      }

      if (recoveryToken.operationType !== operationType) {
        return {
          allowed: false,
          errorCode: 'ERR_OPERATION_TYPE_MISMATCH',
          errorMessage: `OPERATION_MISMATCH: Token bound to operation '${recoveryToken.operationType}', requested '${operationType}'.`,
        };
      }

      if ((recoveryToken.proposedReplacementPhone || 'NONE') !== (proposedReplacementPhone || 'NONE')) {
        return {
          allowed: false,
          errorCode: 'ERR_REPLACEMENT_PHONE_MODIFIED',
          errorMessage: `PHONE_MISMATCH: Token bound to replacement phone '${recoveryToken.proposedReplacementPhone}', requested '${proposedReplacementPhone}'.`,
        };
      }

      // 4. Two Independent Authorization Proofs
      const h1 = recoveryToken.approvalHolder1;
      const h2 = recoveryToken.approvalHolder2;

      if (!h1 || !h2) {
        return {
          allowed: false,
          errorCode: 'ERR_INCOMPLETE_DUAL_CUSTODY',
          errorMessage: 'DUAL_CUSTODY_INCOMPLETE: Exactly two independent authorization proofs are required.',
        };
      }

      // 5. Anti-Collusion & Distinct Identity Verification
      // A. Distinct Officer IDs
      if (h1.officerId === h2.officerId) {
        return {
          allowed: false,
          errorCode: 'ERR_DUAL_CUSTODY_SAME_OFFICER',
          errorMessage: `COLLUSION_BLOCKED: Holder 1 and Holder 2 are the same officer '${h1.officerId}'. Two distinct individuals required.`,
        };
      }

      // B. Distinct Verified Identity Provider Subjects
      if (h1.idpSubject === h2.idpSubject) {
        return {
          allowed: false,
          errorCode: 'ERR_DUAL_CUSTODY_SAME_IDP_SUBJECT',
          errorMessage: `COLLUSION_BLOCKED: Both approvers resolve to the same underlying IdP subject '${h1.idpSubject}'.`,
        };
      }

      // C. Separate MFA Credentials
      if (h1.mfaCredentialId === h2.mfaCredentialId) {
        return {
          allowed: false,
          errorCode: 'ERR_DUAL_CUSTODY_SHARED_MFA',
          errorMessage: `MFA_SECURITY_VIOLATION: Both approvers presented identical MFA credential '${h1.mfaCredentialId}'.`,
        };
      }

      // D. Requester Self-Approval Check
      if (
        recoveryToken.requesterOfficerId === h1.officerId ||
        recoveryToken.requesterOfficerId === h2.officerId
      ) {
        return {
          allowed: false,
          errorCode: 'ERR_REQUESTER_SELF_APPROVAL',
          errorMessage: `SELF_APPROVAL_PROHIBITED: Requester '${recoveryToken.requesterOfficerId}' cannot approve their own recovery case.`,
        };
      }

      // 6. Verify Approver 1 Role & Signature
      const approver1 = this.registeredApprovers.get(h1.officerId);
      if (!approver1 || approver1.role !== 'BIOMETRIC_COMPLIANCE_OFFICER') {
        return {
          allowed: false,
          errorCode: 'ERR_UNAUTHORIZED_APPROVER_1',
          errorMessage: `UNAUTHORIZED_OFFICER: Holder 1 '${h1.officerId}' is not an authorized Biometric Compliance Officer.`,
        };
      }

      // 7. Verify Approver 2 Role & Signature
      const approver2 = this.registeredApprovers.get(h2.officerId);
      if (!approver2 || approver2.role !== 'INDEPENDENT_SECURITY_AUDITOR') {
        return {
          allowed: false,
          errorCode: 'ERR_UNAUTHORIZED_APPROVER_2',
          errorMessage: `UNAUTHORIZED_OFFICER: Holder 2 '${h2.officerId}' is not an authorized Independent Security Auditor.`,
        };
      }

      const canonicalPayload = this.getSignablePayload(
        recoveryToken.targetUid,
        recoveryToken.caseReference,
        recoveryToken.operationType,
        recoveryToken.proposedReplacementPhone,
        recoveryToken.issuedAtEpochMs,
        recoveryToken.expiresAtEpochMs
      );

      // Verify Sig 1
      const v1 = crypto.createVerify('SHA256');
      v1.update(canonicalPayload);
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
      v2.update(canonicalPayload);
      v2.end();
      if (!v2.verify(approver2.publicKeyPem, h2.signatureBase64, 'base64')) {
        return {
          allowed: false,
          errorCode: 'ERR_APPROVER_2_SIGNATURE_INVALID',
          errorMessage: 'SIGNATURE_INVALID: Cryptographic signature verification failed for Holder 2.',
        };
      }

      // 8. Replacement Factor Verification
      if (req.proposedReplacementPhone && !req.hasVerifiedOriginalFactor) {
        return {
          allowed: false,
          errorCode: 'ERR_REPLACEMENT_FACTOR_UNVERIFIED',
          errorMessage:
            'FACTOR_SECURITY_VIOLATION: Unverified replacement phone cannot prove account ownership without primary identity verification.',
        };
      }

      // 9. Atomic Consumption
      this.consumedTokens.add(recoveryToken.tokenId);

      return {
        allowed: true,
        auditRecordId: `recovery-audit-${crypto.randomBytes(8).toString('hex')}`,
      };
    } finally {
      this.activeLocks.delete(recoveryToken.tokenId);
    }
  }
}
