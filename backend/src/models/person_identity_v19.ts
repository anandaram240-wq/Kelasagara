import { randomBytes } from 'crypto';
import { CANONICAL_SFACE_CONTRACT } from '../biometrics/canonical_pipeline';

export type MarketplaceRole = 'WORKER' | 'HIRER';

export type RoleLinkingPolicy =
  | 'ALLOW_DUAL_ROLE_WITH_STEP_UP_AUTH'
  | 'SINGLE_ROLE_ONLY_WITH_REVIEW';

export type AccountBiometricLifecycleStatus =
  | 'FACE_NOT_ENROLLED_LEGACY'        // Journey C: Pre-biometric existing account
  | 'FACE_ENROLLMENT_REQUIRED'       // Journey A: New registration awaiting face enrollment
  | 'ENROLLED_ACTIVE'                // Journey D: Active verified template bound to personId
  | 'POTENTIAL_EXISTING_REGISTRATION'// Journey B: 1:N match held pending sign-in / step-up / review
  | 'REENROLLMENT_IN_PROGRESS'       // Journey E: Updating template / phone replacement
  | 'ALTERNATE_KYC_PENDING_OR_ACTIVE'// Journey F: Approved non-biometric document/supervisor path
  | 'TEMPLATE_REVOKED_OR_DELETED';   // Section 10.3: Template deleted/revoked

export type BiometricTemplateRecordState =
  | 'RESERVED_PENDING'
  | 'ACTIVE'
  | 'SUPERSEDED_RETIRED'
  | 'QUARANTINED_REVIEW'
  | 'REVOKED_DELETED';

export type StepUpVerificationProof =
  | { verified: false }
  | {
      verified: true;
      proofId?: string;
      method: 'EXISTING_ACCOUNT_SIGN_IN' | 'REGISTERED_PHONE_OTP' | 'COMPLIANCE_OFFICER_REVIEW';
      verifiedTargetPersonId: string;
      verifiedAtMs: number;
    };

/**
 * Authoritative Person Identity Record (stored in `person_identities/{personId}`).
 * Contains zero biometric vectors and zero raw PII duplication.
 */
export interface PersonIdentityRecordV19 {
  personId: string; // Server-generated opaque ID: prs_<32 hex chars>
  primaryAuthUid: string;
  linkedAuthUids: string[];
  workerId: string | null;
  hirerId: string | null;
  activeBiometricEnrollmentId: string | null;
  activeTemplateGeneration: number;
  biometricLifecycleStatus: AccountBiometricLifecycleStatus;
  createdAtMs: number;
  updatedAtMs: number;
}

/**
 * Versioned Biometric Enrollment Lifecycle Metadata (stored in `biometric_vault/{authUid}`).
 */
export interface BiometricEnrollmentLifecycleV19 {
  biometricEnrollmentId: string; // Server-generated opaque ID: bme_<32 hex chars>
  personId: string;
  authUid: string;
  templateGeneration: number;
  state: BiometricTemplateRecordState;
  modelVersion: typeof CANONICAL_SFACE_CONTRACT.modelId;
  templateSchemaVersion: typeof CANONICAL_SFACE_CONTRACT.templateSchemaVersion;
  supersedesEnrollmentId: string | null;
  createdAtMs: number;
  retiredAtMs: number | null;
}

/**
 * Privacy-preserving response for Journey B (Second-Account / Repeat Registration Attempt).
 * Enforces Section 8.3: Never reveals masked account hints before step-up authorization.
 */
export interface PotentialExistingRegistrationResponseV19 {
  outcome: 'POTENTIAL_EXISTING_REGISTRATION';
  allowedToCreateNewUnlinkedAccount: false;
  disclosureStage:
    | 'STEP_UP_REQUIRED_NO_PII'
    | 'STEP_UP_VERIFIED_MINIMAL_HINT'
    | 'DUAL_ROLE_LINK_ELIGIBLE';
  nextSteps: Array<
    | 'SIGN_IN_EXISTING_ACCOUNT'
    | 'VERIFY_EXISTING_PHONE_OTP'
    | 'LINK_SECOND_MARKETPLACE_ROLE'
    | 'REQUEST_HUMAN_COMPLIANCE_REVIEW'
    | 'USE_ALTERNATE_KYC'
  >;
  /** Strictly null unless StepUpVerificationProof.verified === true */
  maskedAccountHint: {
    referenceCode: string; // e.g., KLS-WRK***42-8819
    existingRoles: MarketplaceRole[];
  } | null;
  reviewCaseId: string;
}

export class PersonIdentityDomainV19 {
  /**
   * Generates a cryptographically random, opaque personId.
   * Never derives identifiers from face landmarks or embedding vectors (Section 4 & 8.1).
   */
  public static mintOpaquePersonId(): string {
    return `prs_${randomBytes(16).toString('hex')}`;
  }

  public static mintOpaqueBiometricEnrollmentId(): string {
    return `bme_${randomBytes(16).toString('hex')}`;
  }

  public static assertValidOpaquePersonId(personId: string): void {
    if (!/^prs_[0-9a-f]{32}$/.test(personId)) {
      throw new Error(
        'INVALID_PERSON_ID_FORMAT: personId must be an opaque server-minted prs_<32hex> identifier.'
      );
    }
  }

  /**
   * Evaluates a 1:N candidate match during registration or role addition (Journeys A, B, C)
   * without leaking cross-account PII prior to step-up verification.
   */
  public static buildRepeatRegistrationResponse(params: {
    matchedPerson: PersonIdentityRecordV19;
    requestedRole: MarketplaceRole;
    rolePolicy: RoleLinkingPolicy;
    stepUpProof: StepUpVerificationProof;
    matchedAccountPhoneLast4?: string;
    reviewCaseId: string;
  }): PotentialExistingRegistrationResponseV19 {
    const {
      matchedPerson,
      requestedRole,
      rolePolicy,
      stepUpProof,
      matchedAccountPhoneLast4,
      reviewCaseId,
    } = params;

    this.assertValidOpaquePersonId(matchedPerson.personId);

    const isStepUpVerifiedForMatchedPerson =
      stepUpProof.verified &&
      stepUpProof.verifiedTargetPersonId === matchedPerson.personId;

    // 1. Pre-Step-Up: Return zero masked identifiers to prevent face-based enumeration (Section 8.3)
    if (!isStepUpVerifiedForMatchedPerson) {
      return {
        outcome: 'POTENTIAL_EXISTING_REGISTRATION',
        allowedToCreateNewUnlinkedAccount: false,
        disclosureStage: 'STEP_UP_REQUIRED_NO_PII',
        nextSteps: [
          'SIGN_IN_EXISTING_ACCOUNT',
          'VERIFY_EXISTING_PHONE_OTP',
          'REQUEST_HUMAN_COMPLIANCE_REVIEW',
          'USE_ALTERNATE_KYC',
        ],
        maskedAccountHint: null,
        reviewCaseId,
      };
    }

    // 2. Step-Up Verified: Determine existing roles and whether dual-role linking is eligible
    const existingRoles: MarketplaceRole[] = [];
    if (matchedPerson.workerId) existingRoles.push('WORKER');
    if (matchedPerson.hirerId) existingRoles.push('HIRER');

    const wantsSecondRole =
      (requestedRole === 'HIRER' && !matchedPerson.hirerId && Boolean(matchedPerson.workerId)) ||
      (requestedRole === 'WORKER' && !matchedPerson.workerId && Boolean(matchedPerson.hirerId));

    const roleIdToMask =
      matchedPerson.workerId ?? matchedPerson.hirerId ?? matchedPerson.personId;
    const referenceCode = this.formatMaskedReferenceCode(
      roleIdToMask,
      matchedAccountPhoneLast4
    );

    if (
      wantsSecondRole &&
      rolePolicy === 'ALLOW_DUAL_ROLE_WITH_STEP_UP_AUTH'
    ) {
      return {
        outcome: 'POTENTIAL_EXISTING_REGISTRATION',
        allowedToCreateNewUnlinkedAccount: false,
        disclosureStage: 'DUAL_ROLE_LINK_ELIGIBLE',
        nextSteps: ['LINK_SECOND_MARKETPLACE_ROLE', 'SIGN_IN_EXISTING_ACCOUNT'],
        maskedAccountHint: {
          referenceCode,
          existingRoles,
        },
        reviewCaseId,
      };
    }

    return {
      outcome: 'POTENTIAL_EXISTING_REGISTRATION',
      allowedToCreateNewUnlinkedAccount: false,
      disclosureStage: 'STEP_UP_VERIFIED_MINIMAL_HINT',
      nextSteps: [
        'SIGN_IN_EXISTING_ACCOUNT',
        'REQUEST_HUMAN_COMPLIANCE_REVIEW',
      ],
      maskedAccountHint: {
        referenceCode,
        existingRoles,
      },
      reviewCaseId,
    };
  }

  /**
   * Links an authorized second marketplace role (Worker <-> Hirer) to an existing
   * personId without creating a duplicate person record (Section 4).
   */
  public static linkAuthorizedRoleToPerson(params: {
    person: PersonIdentityRecordV19;
    newRole: MarketplaceRole;
    newRoleProfileId: string;
    stepUpProof: StepUpVerificationProof;
    rolePolicy: RoleLinkingPolicy;
    nowMs?: number;
  }): PersonIdentityRecordV19 {
    const {
      person,
      newRole,
      newRoleProfileId,
      stepUpProof,
      rolePolicy,
      nowMs = Date.now(),
    } = params;

    if (rolePolicy !== 'ALLOW_DUAL_ROLE_WITH_STEP_UP_AUTH') {
      throw new Error('ROLE_LINKING_DISABLED_BY_POLICY');
    }
    if (
      !stepUpProof.verified ||
      stepUpProof.verifiedTargetPersonId !== person.personId
    ) {
      throw new Error('STEP_UP_VERIFICATION_REQUIRED_FOR_ROLE_LINKING');
    }

    if (newRole === 'WORKER') {
      if (person.workerId && person.workerId !== newRoleProfileId) {
        throw new Error('PERSON_ALREADY_HAS_ACTIVE_WORKER_PROFILE');
      }
      return {
        ...person,
        workerId: newRoleProfileId,
        updatedAtMs: nowMs,
      };
    } else {
      if (person.hirerId && person.hirerId !== newRoleProfileId) {
        throw new Error('PERSON_ALREADY_HAS_ACTIVE_HIRER_PROFILE');
      }
      return {
        ...person,
        hirerId: newRoleProfileId,
        updatedAtMs: nowMs,
      };
    }
  }

  /**
   * Journey C & E: Prepares a new active enrollment lifecycle record and marks the
   * prior enrollment (if any) as SUPERSEDED_RETIRED only upon new generation commit.
   */
  public static transitionEnrollmentGeneration(params: {
    person: PersonIdentityRecordV19;
    previousEnrollment: BiometricEnrollmentLifecycleV19 | null;
    newEnrollmentId?: string;
    nowMs?: number;
  }): {
    updatedPerson: PersonIdentityRecordV19;
    newEnrollment: BiometricEnrollmentLifecycleV19;
    retiredPreviousEnrollment: BiometricEnrollmentLifecycleV19 | null;
  } {
    const {
      person,
      previousEnrollment,
      newEnrollmentId = this.mintOpaqueBiometricEnrollmentId(),
      nowMs = Date.now(),
    } = params;

    this.assertValidOpaquePersonId(person.personId);

    const nextGeneration = person.activeTemplateGeneration + 1;
    if (
      previousEnrollment &&
      previousEnrollment.templateGeneration !== person.activeTemplateGeneration
    ) {
      throw new Error('STALE_PREVIOUS_ENROLLMENT_GENERATION');
    }

    const newEnrollment: BiometricEnrollmentLifecycleV19 = {
      biometricEnrollmentId: newEnrollmentId,
      personId: person.personId,
      authUid: person.primaryAuthUid,
      templateGeneration: nextGeneration,
      state: 'ACTIVE',
      modelVersion: CANONICAL_SFACE_CONTRACT.modelId,
      templateSchemaVersion: CANONICAL_SFACE_CONTRACT.templateSchemaVersion,
      supersedesEnrollmentId:
        previousEnrollment?.biometricEnrollmentId ?? null,
      createdAtMs: nowMs,
      retiredAtMs: null,
    };

    const retiredPreviousEnrollment: BiometricEnrollmentLifecycleV19 | null =
      previousEnrollment
        ? {
            ...previousEnrollment,
            state: 'SUPERSEDED_RETIRED',
            retiredAtMs: nowMs,
          }
        : null;

    const updatedPerson: PersonIdentityRecordV19 = {
      ...person,
      activeBiometricEnrollmentId: newEnrollment.biometricEnrollmentId,
      activeTemplateGeneration: nextGeneration,
      biometricLifecycleStatus: 'ENROLLED_ACTIVE',
      updatedAtMs: nowMs,
    };

    return {
      updatedPerson,
      newEnrollment,
      retiredPreviousEnrollment,
    };
  }

  private static formatMaskedReferenceCode(
    roleOrPersonId: string,
    phoneLast4?: string
  ): string {
    const alnum = (roleOrPersonId || 'USR').replace(/[^a-zA-Z0-9]/g, '');
    const prefix = alnum.slice(0, 3).toUpperCase().padEnd(3, 'X');
    const suffix = alnum.slice(-2).toUpperCase().padStart(2, '0');
    const safeLast4 =
      phoneLast4 && /^\d{4}$/.test(phoneLast4) ? phoneLast4 : 'XXXX';
    return `KLS-${prefix}***${suffix}-${safeLast4}`;
  }
}
