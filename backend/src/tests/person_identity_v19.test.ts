import { describe, it } from 'node:test';
import assert from 'node:assert';
import {
  PersonIdentityDomainV19,
  PersonIdentityRecordV19,
} from '../models/person_identity_v19';

const expect = (actual: any) => ({
  toBe: (expected: any) => assert.strictEqual(actual, expected),
  toEqual: (expected: any) => assert.deepStrictEqual(actual, expected),
  toMatch: (regex: RegExp) => assert.match(actual, regex),
  toThrow: (msg?: string) => {
    if (msg) {
      assert.throws(() => {
        if (typeof actual === 'function') actual();
      }, new RegExp(msg));
    } else {
      assert.throws(() => {
        if (typeof actual === 'function') actual();
      });
    }
  },
  toBeNull: () => assert.strictEqual(actual, null),
  not: {
    toBeNull: () => assert.notStrictEqual(actual, null),
  },
});

describe('V19 Stage B: Person Identity, Role-Linking & Step-Up Disclosure Policy', () => {
  const baseWorkerPerson: PersonIdentityRecordV19 = {
    personId: PersonIdentityDomainV19.mintOpaquePersonId(),
    primaryAuthUid: 'auth_uid_worker_1',
    linkedAuthUids: ['auth_uid_worker_1'],
    workerId: 'wrk_900142',
    hirerId: null,
    activeBiometricEnrollmentId: 'bme_00001111222233334444555566667777',
    activeTemplateGeneration: 1,
    biometricLifecycleStatus: 'ENROLLED_ACTIVE',
    createdAtMs: 1_760_000_000_000,
    updatedAtMs: 1_760_000_000_000,
  };

  it('mints opaque personId values and rejects non-opaque or vector-derived IDs', () => {
    expect(baseWorkerPerson.personId).toMatch(/^prs_[0-9a-f]{32}$/);
    expect(() =>
      PersonIdentityDomainV19.assertValidOpaquePersonId('vec_0.123_-0.441')
    ).toThrow('INVALID_PERSON_ID_FORMAT');
  });

  it('Journey B: withholds all masked account details before step-up proof of control (anti-enumeration)', () => {
    const response = PersonIdentityDomainV19.buildRepeatRegistrationResponse({
      matchedPerson: baseWorkerPerson,
      requestedRole: 'WORKER',
      rolePolicy: 'ALLOW_DUAL_ROLE_WITH_STEP_UP_AUTH',
      stepUpProof: { verified: false },
      matchedAccountPhoneLast4: '8819',
      reviewCaseId: 'rev_case_101',
    });

    expect(response.allowedToCreateNewUnlinkedAccount).toBe(false);
    expect(response.disclosureStage).toBe('STEP_UP_REQUIRED_NO_PII');
    expect(response.maskedAccountHint).toBeNull();
  });

  it('Journey B + Role Linking: unlocks dual-role linking and minimal masked hint ONLY after step-up verification', () => {
    const response = PersonIdentityDomainV19.buildRepeatRegistrationResponse({
      matchedPerson: baseWorkerPerson,
      requestedRole: 'HIRER',
      rolePolicy: 'ALLOW_DUAL_ROLE_WITH_STEP_UP_AUTH',
      stepUpProof: {
        verified: true,
        method: 'REGISTERED_PHONE_OTP',
        verifiedTargetPersonId: baseWorkerPerson.personId,
        verifiedAtMs: 1_760_000_050_000,
      },
      matchedAccountPhoneLast4: '8819',
      reviewCaseId: 'rev_case_102',
    });

    expect(response.disclosureStage).toBe('DUAL_ROLE_LINK_ELIGIBLE');
    expect(response.maskedAccountHint).not.toBeNull();
    expect(response.maskedAccountHint?.referenceCode).toBe('KLS-WRK***42-8819');
    expect(response.maskedAccountHint?.existingRoles).toEqual(['WORKER']);

    const linked = PersonIdentityDomainV19.linkAuthorizedRoleToPerson({
      person: baseWorkerPerson,
      newRole: 'HIRER',
      newRoleProfileId: 'hir_500299',
      rolePolicy: 'ALLOW_DUAL_ROLE_WITH_STEP_UP_AUTH',
      stepUpProof: {
        verified: true,
        method: 'REGISTERED_PHONE_OTP',
        verifiedTargetPersonId: baseWorkerPerson.personId,
        verifiedAtMs: 1_760_000_050_000,
      },
    });

    expect(linked.workerId).toBe('wrk_900142');
    expect(linked.hirerId).toBe('hir_500299');
    expect(linked.personId).toBe(baseWorkerPerson.personId);
  });

  it('Journey C & E: transitions templateGeneration atomically and retires previous enrollment without orphaning personId', () => {
    const firstLifecycle = {
      biometricEnrollmentId: baseWorkerPerson.activeBiometricEnrollmentId!,
      personId: baseWorkerPerson.personId,
      authUid: baseWorkerPerson.primaryAuthUid,
      templateGeneration: 1,
      state: 'ACTIVE' as const,
      modelVersion: 'opencv_sface_2021dec_fp32_v1' as const,
      templateSchemaVersion: 2 as const,
      supersedesEnrollmentId: null,
      createdAtMs: 1_760_000_000_000,
      retiredAtMs: null,
    };

    const { updatedPerson, newEnrollment, retiredPreviousEnrollment } =
      PersonIdentityDomainV19.transitionEnrollmentGeneration({
        person: baseWorkerPerson,
        previousEnrollment: firstLifecycle,
        nowMs: 1_760_000_900_000,
      });

    expect(updatedPerson.activeTemplateGeneration).toBe(2);
    expect(updatedPerson.activeBiometricEnrollmentId).toBe(
      newEnrollment.biometricEnrollmentId
    );
    expect(newEnrollment.state).toBe('ACTIVE');
    expect(newEnrollment.supersedesEnrollmentId).toBe(
      firstLifecycle.biometricEnrollmentId
    );
    expect(retiredPreviousEnrollment?.state).toBe('SUPERSEDED_RETIRED');
    expect(retiredPreviousEnrollment?.retiredAtMs).toBe(1_760_000_900_000);
  });
});
