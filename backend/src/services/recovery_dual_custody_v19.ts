/**
 * KELASAGARA V20.19: INDEPENDENT REGISTRY-BACKED TWO-PERSON RECOVERY AUTHORIZATION
 *
 * Implements strict two-person authorization (2PA) anchored in an independently administered
 * organizational officer registry:
 *
 * 1. Multi-Tiered Dual-Custody Assurance:
 *    - Tier 1: Mock Officer Registry Verification (exercised in local test suites).
 *    - Tier 2: Software-Level Identity Separation (enforced algorithmically via this service).
 *    - Tier 3: Actual Organizational Identity Registration (enterprise IdP / directory binding).
 *    - Tier 4: Real Hardware MFA Enrollment (physical FIDO2 / WebAuthn security keys).
 *    - Tier 5: Independent Human Authorization (governed by organizational roles and out-of-band checks).
 *    * Gate Placement: Live organizational independence, approved personnel, and hardware MFA
 *      requirements are strictly governed under Gate D (Institutional, Legal and Human Pilot Authorization)
 *      and remain UNVERIFIED until Gate D formally passes.
 * 2. Distinct Human Identity Enforcement:
 *    - Rejects approvals where both holders share the same officerId or the same IdP subject.
 *    - Rejects shared MFA credentials.
 *    - Rejects requester self-approval (requester cannot approve their own case).
 * 3. Exact Context Cryptographic Binding:
 *    - Canonical signable payload binds: caseReference, targetAccount, recoveryOperation,
 *      requestedPhone, requestDigest, expiry, and uniqueOperationId.
 *    - Any modification invalidates cryptographic verification.
 * 4. Honest Anti-Collusion Disclosure:
 *    - Formally acknowledges that while technical controls verify separate accounts, IdP subjects,
 *      and MFA tokens, technical systems CANNOT eliminate human collusion if two distinct authorized
 *      human actors deliberately conspire. Preventing collusion requires organizational dual-custody
 *      governance, out-of-band verification, and institutional audit oversight.
 */

import * as crypto from 'crypto';

export type OrganizationalRoleV19 =
  | 'BIOMETRIC_COMPLIANCE_OFFICER'
  | 'INDEPENDENT_SECURITY_AUDITOR';

export type OfficerStatusV19 = 'ACTIVE' | 'SUSPENDED' | 'REVOKED';

export interface RegisteredOfficerRecordV19 {
  officerId: string;
  idpSubject: string; // Stable IdP subject (e.g. google-oauth2|sub-1001)
  role: OrganizationalRoleV19;
  allowedOperations: string[];
  mfaCredentialId: string; // Pinned FIDO2 / WebAuthn hardware authenticator
  mfaType: 'FIDO2_HARDWARE_KEY';
  status: OfficerStatusV19;
  publicKeyPem: string;
  enrolledAtIso: string;
}

export interface ApproverSignatureProofV19 {
  officerId: string;
  idpSubject: string;
  mfaCredentialId: string;
  signatureBase64: string;
  signedAtEpochMs: number;
}

export interface DualCustodyRecoveryTokenV19 {
  tokenId: string;
  uniqueOperationId: string;
  targetUid: string;
  caseReference: string;
  recoveryOperation: 'BIOMETRIC_ACCOUNT_UNLOCK' | 'TEMPLATE_SUPERSEDE_RECOVERY' | 'PHONE_FACTOR_REASSIGNMENT';
  requestedPhone?: string;
  requestDigest: string; // SHA-256 of full request payload
  requesterOfficerId: string;
  issuedAtEpochMs: number;
  expiresAtEpochMs: number;
  approvalHolder1: ApproverSignatureProofV19;
  approvalHolder2: ApproverSignatureProofV19;
}

export interface RecoveryExecutionRequestV19 {
  recoveryToken: DualCustodyRecoveryTokenV19;
  targetUid: string;
  caseReference: string;
  recoveryOperation: 'BIOMETRIC_ACCOUNT_UNLOCK' | 'TEMPLATE_SUPERSEDE_RECOVERY' | 'PHONE_FACTOR_REASSIGNMENT';
  requestedPhone?: string;
  requestDigest: string;
  hasVerifiedOriginalFactor?: boolean;
}

export interface RecoveryExecutionResultV19 {
  allowed: boolean;
  errorCode?: string;
  errorMessage?: string;
  auditRecordId?: string;
}

/**
 * Independently Administered Officer Registry Interface.
 */
export interface IOfficerAuthorizationRegistry {
  getOfficer(officerId: string): RegisteredOfficerRecordV19 | null;
  registerOfficer(record: RegisteredOfficerRecordV19): void;
  updateOfficerStatus(officerId: string, status: OfficerStatusV19): void;
  isRegistryAvailable(): boolean;
}

export class InMemoryOfficerRegistry implements IOfficerAuthorizationRegistry {
  private officers = new Map<string, RegisteredOfficerRecordV19>();
  private available = true;

  public setAvailable(available: boolean): void {
    this.available = available;
  }

  public isRegistryAvailable(): boolean {
    return this.available;
  }

  public getOfficer(officerId: string): RegisteredOfficerRecordV19 | null {
    if (!this.available) return null;
    return this.officers.get(officerId) || null;
  }

  public registerOfficer(record: RegisteredOfficerRecordV19): void {
    this.officers.set(record.officerId, record);
  }

  public updateOfficerStatus(officerId: string, status: OfficerStatusV19): void {
    const o = this.officers.get(officerId);
    if (o) {
      o.status = status;
    }
  }
}

export class RecoveryDualCustodyEngineV19 {
  private registry: IOfficerAuthorizationRegistry;
  private consumedTokens = new Set<string>();
  private activeLocks = new Set<string>();

  constructor(registry?: IOfficerAuthorizationRegistry) {
    this.registry = registry || new InMemoryOfficerRegistry();
  }

  public getRegistry(): IOfficerAuthorizationRegistry {
    return this.registry;
  }

  public getSignablePayload(
    targetUid: string,
    caseReference: string,
    recoveryOperation: string,
    requestedPhone: string | undefined,
    requestDigest: string,
    uniqueOperationId: string,
    issuedAtEpochMs: number,
    expiresAtEpochMs: number
  ): string {
    const phone = requestedPhone || 'NONE';
    return `${targetUid}|${caseReference}|${recoveryOperation}|${phone}|${requestDigest}|${uniqueOperationId}|${issuedAtEpochMs}|${expiresAtEpochMs}`;
  }

  public createApproverProof(
    officer: RegisteredOfficerRecordV19,
    privateKeyPem: string,
    targetUid: string,
    caseReference: string,
    recoveryOperation: string,
    requestedPhone: string | undefined,
    requestDigest: string,
    uniqueOperationId: string,
    issuedAtEpochMs: number,
    expiresAtEpochMs: number
  ): ApproverSignatureProofV19 {
    const payload = this.getSignablePayload(
      targetUid,
      caseReference,
      recoveryOperation,
      requestedPhone,
      requestDigest,
      uniqueOperationId,
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

  public async evaluateRecoveryAuthorization(
    req: RecoveryExecutionRequestV19
  ): Promise<RecoveryExecutionResultV19> {
    const { recoveryToken, targetUid, caseReference, recoveryOperation, requestedPhone, requestDigest } = req;

    // 1. Independent Registry Availability Gate
    if (!this.registry.isRegistryAvailable()) {
      return {
        allowed: false,
        errorCode: 'ERR_REGISTRY_UNAVAILABLE',
        errorMessage: 'AUTHORIZATION_BLOCKED: Independent organizational officer registry is unavailable. Human independence cannot be established.',
      };
    }

    // 2. Concurrency Lock & Replay Prevention
    if (this.activeLocks.has(recoveryToken.tokenId)) {
      return {
        allowed: false,
        errorCode: 'ERR_CONCURRENT_CONSUMPTION_BLOCKED',
        errorMessage: 'CONCURRENCY_BLOCKED: Another transaction is consuming this token.',
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

      // 3. Expiry Check (Max 15 min TTL)
      const now = Date.now();
      if (now > recoveryToken.expiresAtEpochMs) {
        return {
          allowed: false,
          errorCode: 'ERR_RECOVERY_TOKEN_EXPIRED',
          errorMessage: 'TOKEN_EXPIRED: Recovery authorization expired.',
        };
      }

      if (recoveryToken.expiresAtEpochMs - recoveryToken.issuedAtEpochMs > 15 * 60 * 1000 + 1000) {
        return {
          allowed: false,
          errorCode: 'ERR_EXCESSIVE_TOKEN_TTL',
          errorMessage: 'TTL_EXCEEDED: Recovery token TTL exceeds 15-minute maximum.',
        };
      }

      // 4. Exact Context Binding
      if (recoveryToken.targetUid !== targetUid) {
        return { allowed: false, errorCode: 'ERR_TARGET_UID_MISMATCH', errorMessage: 'ACCOUNT_MISMATCH.' };
      }
      if (recoveryToken.caseReference !== caseReference) {
        return { allowed: false, errorCode: 'ERR_CASE_REFERENCE_MISMATCH', errorMessage: 'CASE_REF_MISMATCH.' };
      }
      if (recoveryToken.recoveryOperation !== recoveryOperation) {
        return { allowed: false, errorCode: 'ERR_OPERATION_TYPE_MISMATCH', errorMessage: 'OPERATION_MISMATCH.' };
      }
      if ((recoveryToken.requestedPhone || 'NONE') !== (requestedPhone || 'NONE')) {
        return { allowed: false, errorCode: 'ERR_REPLACEMENT_PHONE_MODIFIED', errorMessage: 'PHONE_MISMATCH.' };
      }
      if (recoveryToken.requestDigest !== requestDigest) {
        return { allowed: false, errorCode: 'ERR_REQUEST_DIGEST_MODIFIED', errorMessage: 'REQUEST_DIGEST_MISMATCH.' };
      }

      // 5. Two Independent Authorization Proofs
      const h1 = recoveryToken.approvalHolder1;
      const h2 = recoveryToken.approvalHolder2;
      if (!h1 || !h2) {
        return { allowed: false, errorCode: 'ERR_INCOMPLETE_DUAL_CUSTODY', errorMessage: 'DUAL_CUSTODY_INCOMPLETE.' };
      }

      // 6. Anti-Collusion & Distinct Identity Verification
      if (h1.officerId === h2.officerId) {
        return { allowed: false, errorCode: 'ERR_DUAL_CUSTODY_SAME_OFFICER', errorMessage: 'COLLUSION_BLOCKED: Same officer.' };
      }
      if (h1.idpSubject === h2.idpSubject) {
        return { allowed: false, errorCode: 'ERR_DUAL_CUSTODY_SAME_IDP_SUBJECT', errorMessage: 'COLLUSION_BLOCKED: Same IdP subject.' };
      }
      if (h1.mfaCredentialId === h2.mfaCredentialId) {
        return { allowed: false, errorCode: 'ERR_DUAL_CUSTODY_SHARED_MFA', errorMessage: 'MFA_VIOLATION: Shared MFA credential.' };
      }

      // Requester Self-Approval Check
      if (recoveryToken.requesterOfficerId === h1.officerId || recoveryToken.requesterOfficerId === h2.officerId) {
        return { allowed: false, errorCode: 'ERR_REQUESTER_SELF_APPROVAL', errorMessage: 'SELF_APPROVAL_PROHIBITED.' };
      }

      // 7. Verify Officer 1 in Independent Registry
      const regOfficer1 = this.registry.getOfficer(h1.officerId);
      if (!regOfficer1) {
        return { allowed: false, errorCode: 'ERR_UNREGISTERED_OFFICER_1', errorMessage: 'OFFICER_NOT_REGISTERED.' };
      }
      if (regOfficer1.status !== 'ACTIVE') {
        return { allowed: false, errorCode: 'ERR_OFFICER_1_STATUS_INACTIVE', errorMessage: `OFFICER_STATUS_INVALID: Officer 1 is ${regOfficer1.status}.` };
      }
      if (regOfficer1.role !== 'BIOMETRIC_COMPLIANCE_OFFICER') {
        return { allowed: false, errorCode: 'ERR_UNAUTHORIZED_APPROVER_1', errorMessage: 'OFFICER_ROLE_MISMATCH.' };
      }
      if (!regOfficer1.allowedOperations.includes(recoveryOperation)) {
        return { allowed: false, errorCode: 'ERR_OFFICER_1_OPERATION_NOT_ALLOWED', errorMessage: 'OPERATION_NOT_PERMITTED.' };
      }

      // 8. Verify Officer 2 in Independent Registry
      const regOfficer2 = this.registry.getOfficer(h2.officerId);
      if (!regOfficer2) {
        return { allowed: false, errorCode: 'ERR_UNREGISTERED_OFFICER_2', errorMessage: 'OFFICER_NOT_REGISTERED.' };
      }
      if (regOfficer2.status !== 'ACTIVE') {
        return { allowed: false, errorCode: 'ERR_OFFICER_2_STATUS_INACTIVE', errorMessage: `OFFICER_STATUS_INVALID: Officer 2 is ${regOfficer2.status}.` };
      }
      if (regOfficer2.role !== 'INDEPENDENT_SECURITY_AUDITOR') {
        return { allowed: false, errorCode: 'ERR_UNAUTHORIZED_APPROVER_2', errorMessage: 'OFFICER_ROLE_MISMATCH.' };
      }
      if (!regOfficer2.allowedOperations.includes(recoveryOperation)) {
        return { allowed: false, errorCode: 'ERR_OFFICER_2_OPERATION_NOT_ALLOWED', errorMessage: 'OPERATION_NOT_PERMITTED.' };
      }

      // 9. Verify Cryptographic Signatures Over Canonical Payload
      const canonicalPayload = this.getSignablePayload(
        recoveryToken.targetUid,
        recoveryToken.caseReference,
        recoveryToken.recoveryOperation,
        recoveryToken.requestedPhone,
        recoveryToken.requestDigest,
        recoveryToken.uniqueOperationId,
        recoveryToken.issuedAtEpochMs,
        recoveryToken.expiresAtEpochMs
      );

      const v1 = crypto.createVerify('SHA256');
      v1.update(canonicalPayload);
      v1.end();
      if (!v1.verify(regOfficer1.publicKeyPem, h1.signatureBase64, 'base64')) {
        return { allowed: false, errorCode: 'ERR_APPROVER_1_SIGNATURE_INVALID', errorMessage: 'SIGNATURE_INVALID: Officer 1.' };
      }

      const v2 = crypto.createVerify('SHA256');
      v2.update(canonicalPayload);
      v2.end();
      if (!v2.verify(regOfficer2.publicKeyPem, h2.signatureBase64, 'base64')) {
        return { allowed: false, errorCode: 'ERR_APPROVER_2_SIGNATURE_INVALID', errorMessage: 'SIGNATURE_INVALID: Officer 2.' };
      }

      // 10. Replacement Factor Security
      if (req.requestedPhone && !req.hasVerifiedOriginalFactor) {
        return { allowed: false, errorCode: 'ERR_REPLACEMENT_FACTOR_UNVERIFIED', errorMessage: 'FACTOR_SECURITY_VIOLATION.' };
      }

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
