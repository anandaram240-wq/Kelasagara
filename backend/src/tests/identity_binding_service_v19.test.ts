import { describe, it, beforeEach } from 'node:test';
import assert from 'node:assert';
import admin from 'firebase-admin';
import {
  PersonIdentityDomainV19,
  PersonIdentityRecordV19,
} from '../models/person_identity_v19';
import {
  IdentityBindingServiceV19,
} from '../services/identity_binding_service_v19';
import { StepUpProofServiceV19 } from '../services/step_up_proof_service_v19';

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
    toBe: (expected: any) => assert.notStrictEqual(actual, expected),
    toThrow: () => {
      assert.doesNotThrow(() => {
        if (typeof actual === 'function') actual();
      });
    },
  },
});

describe('V19.1 Identity Binding, Anti-Hijacking & Role-Linking Audit Suite', () => {
  let store: Map<string, any>;
  let mockDb: admin.firestore.Firestore;

  beforeEach(() => {
    store = new Map<string, any>();

    mockDb = {
      collection: (colName: string) => ({
        doc: (docId: string) => {
          const path = `${colName}/${docId}`;
          return {
            id: docId,
            path,
            get: async () => ({
              exists: store.has(path),
              data: () => (store.has(path) ? structuredClone(store.get(path)) : undefined),
            }),
            set: async (data: any) => {
              store.set(path, structuredClone(data));
            },
            update: async (data: any) => {
              const existing = store.get(path) || {};
              store.set(path, { ...existing, ...structuredClone(data) });
            },
          };
        },
      }),
      runTransaction: async <T>(fn: (tx: any) => Promise<T>): Promise<T> => {
        let writesStarted = false;
        const staged = new Map<string, any>();

        const tx = {
          get: async (ref: { path: string; get: () => Promise<any> }) => {
            if (writesStarted) {
              throw new Error('FAILED_PRECONDITION: Reads must precede writes.');
            }
            return ref.get();
          },
          set: (ref: { path: string }, data: any) => {
            writesStarted = true;
            staged.set(ref.path, structuredClone(data));
          },
          update: (ref: { path: string }, data: any) => {
            writesStarted = true;
            const existing = staged.has(ref.path)
              ? staged.get(ref.path)
              : store.get(ref.path) || {};
            staged.set(ref.path, { ...existing, ...structuredClone(data) });
          },
        };

        const out = await fn(tx);
        for (const [k, v] of staged.entries()) {
          store.set(k, v);
        }
        return out;
      },
    } as unknown as admin.firestore.Firestore;
  });

  it('Phase 4: assertNoClientWritableProtectedFields strictly rejects client tampering with identity ownership', () => {
    expect(() =>
      IdentityBindingServiceV19.assertNoClientWritableProtectedFields({
        name: 'Ravi Kumar',
        personId: 'prs_hijacked_id_123',
      })
    ).toThrow('SECURITY_VIOLATION');

    expect(() =>
      IdentityBindingServiceV19.assertNoClientWritableProtectedFields({
        linkedAuthUids: ['attacker_uid'],
      })
    ).toThrow('SECURITY_VIOLATION');

    expect(() =>
      IdentityBindingServiceV19.assertNoClientWritableProtectedFields({
        activeBiometricEnrollmentId: 'bme_spoofed',
      })
    ).toThrow('SECURITY_VIOLATION');

    // Safe updates pass without error
    expect(() =>
      IdentityBindingServiceV19.assertNoClientWritableProtectedFields({
        fullName: 'Ravi Kumar',
        preferredLanguage: 'kn',
        address: 'Bengaluru',
      })
    ).not.toThrow();
  });

  it('Phase 1 & 3: getOrInitPersonIdentity mints opaque personId and persists linkage idempotently', async () => {
    store.set('users/worker_uid_01', {
      name: 'Basavaraj',
      role: 'worker',
      accountStatus: 'pending_face',
    });

    const person = await IdentityBindingServiceV19.getOrInitPersonIdentity({
      db: mockDb,
      authUid: 'worker_uid_01',
      initialRole: 'WORKER',
    });

    expect(person.personId).toMatch(/^prs_[0-9a-f]{32}$/);
    expect(person.primaryAuthUid).toBe('worker_uid_01');
    expect(person.linkedAuthUids).toEqual(['worker_uid_01']);
    expect(person.workerId).toBe('worker_uid_01');
    expect(person.hirerId).toBeNull();
    expect(store.get('users/worker_uid_01').personId).toBe(person.personId);

    // Calling again returns identical personId (idempotent)
    const secondCall = await IdentityBindingServiceV19.getOrInitPersonIdentity({
      db: mockDb,
      authUid: 'worker_uid_01',
      initialRole: 'WORKER',
    });

    expect(secondCall.personId).toBe(person.personId);
  });

  it('Phase 2 Anti-Hijacking: rejects role-linking if step-up proof is unverified or targets another person', async () => {
    const validPersonId = PersonIdentityDomainV19.mintOpaquePersonId();
    store.set(`person_identities/${validPersonId}`, {
      personId: validPersonId,
      primaryAuthUid: 'legit_worker_uid',
      linkedAuthUids: ['legit_worker_uid'],
      workerId: 'legit_worker_uid',
      hirerId: null,
      activeBiometricEnrollmentId: null,
      activeTemplateGeneration: 0,
      biometricLifecycleStatus: 'ENROLLED_ACTIVE',
    });

    // Case 1: unverified proof
    await assert.rejects(
      async () => {
        await IdentityBindingServiceV19.linkAuthorizedSecondRole({
          db: mockDb,
          callerUid: 'legit_worker_uid',
          targetPersonId: validPersonId,
          newRole: 'HIRER',
          newRoleProfileId: 'legit_hirer_profile',
          rolePolicy: 'ALLOW_DUAL_ROLE_WITH_STEP_UP_AUTH',
          stepUpProof: { verified: false },
        });
      },
      /UNAUTHORIZED_PROOF_OF_CONTROL/
    );

    // Case 2: proof targeting a different personId
    await assert.rejects(
      async () => {
        await IdentityBindingServiceV19.linkAuthorizedSecondRole({
          db: mockDb,
          callerUid: 'legit_worker_uid',
          targetPersonId: validPersonId,
          newRole: 'HIRER',
          newRoleProfileId: 'legit_hirer_profile',
          rolePolicy: 'ALLOW_DUAL_ROLE_WITH_STEP_UP_AUTH',
          stepUpProof: {
            verified: true,
            method: 'REGISTERED_PHONE_OTP',
            verifiedTargetPersonId: 'prs_00000000000000000000000000000000',
            verifiedAtMs: Date.now(),
          },
        });
      },
      /PROOF_MISMATCH/
    );
  });

  it('Phase 2 & 3: allows dual-role linking when step-up proof is valid and policy allows it', async () => {
    const validPersonId = PersonIdentityDomainV19.mintOpaquePersonId();
    store.set(`person_identities/${validPersonId}`, {
      personId: validPersonId,
      primaryAuthUid: 'legit_worker_uid',
      linkedAuthUids: ['legit_worker_uid'],
      workerId: 'legit_worker_uid',
      hirerId: null,
      activeBiometricEnrollmentId: 'bme_123',
      activeTemplateGeneration: 1,
      biometricLifecycleStatus: 'ENROLLED_ACTIVE',
      createdAtMs: 1_760_000_000_000,
      updatedAtMs: 1_760_000_000_000,
    });
    store.set('users/legit_worker_uid', {
      name: 'Suresh',
      role: 'worker',
      personId: validPersonId,
    });

    const result = await IdentityBindingServiceV19.linkAuthorizedSecondRole({
      db: mockDb,
      callerUid: 'legit_worker_uid',
      targetPersonId: validPersonId,
      newRole: 'HIRER',
      newRoleProfileId: 'hirer_profile_99',
      rolePolicy: 'ALLOW_DUAL_ROLE_WITH_STEP_UP_AUTH',
      stepUpProof: {
        verified: true,
        method: 'EXISTING_ACCOUNT_SIGN_IN',
        verifiedTargetPersonId: validPersonId,
        verifiedAtMs: Date.now(),
      },
    });

    expect(result.success).toBe(true);
    expect(result.roleLinked).toBe('HIRER');
    expect(result.person.workerId).toBe('legit_worker_uid');
    expect(result.person.hirerId).toBe('hirer_profile_99');

    const updatedStored = store.get(`person_identities/${validPersonId}`);
    expect(updatedStored.hirerId).toBe('hirer_profile_99');
    expect(updatedStored.workerId).toBe('legit_worker_uid');
  });

  it('Phase 3: linkSecondaryAuthUid blocks linking if the new UID is already bound to a conflicting personId', async () => {
    const personA = PersonIdentityDomainV19.mintOpaquePersonId();
    const personB = PersonIdentityDomainV19.mintOpaquePersonId();

    store.set(`person_identities/${personA}`, {
      personId: personA,
      primaryAuthUid: 'user_a',
      linkedAuthUids: ['user_a'],
      workerId: 'user_a',
      hirerId: null,
      activeBiometricEnrollmentId: null,
      activeTemplateGeneration: 0,
      biometricLifecycleStatus: 'ENROLLED_ACTIVE',
    });

    store.set('users/user_b', {
      name: 'Other User',
      personId: personB, // user_b belongs to personB
    });

    const proof = await StepUpProofServiceV19.issueProof({
      db: mockDb,
      issuedToUid: 'user_b',
      targetPersonId: personA,
      method: 'COMPLIANCE_OFFICER_REVIEW',
    });

    await assert.rejects(
      async () => {
        await IdentityBindingServiceV19.linkSecondaryAuthUid({
          db: mockDb,
          existingPersonId: personA,
          newAuthUid: 'user_b',
          stepUpProof: {
            verified: true,
            proofId: proof.proofId,
            method: 'COMPLIANCE_OFFICER_REVIEW',
            verifiedTargetPersonId: personA,
            verifiedAtMs: Date.now(),
          },
        });
      },
      /CONFLICTING_IDENTITY_BINDING/
    );
  });

  it('Phase 5 Anti-Enumeration: buildRepeatRegistrationResponse withholds all PII when proof is absent', () => {
    const personRecord: PersonIdentityRecordV19 = {
      personId: PersonIdentityDomainV19.mintOpaquePersonId(),
      primaryAuthUid: 'target_uid_01',
      linkedAuthUids: ['target_uid_01'],
      workerId: 'wrk_999888',
      hirerId: null,
      activeBiometricEnrollmentId: 'bme_111',
      activeTemplateGeneration: 1,
      biometricLifecycleStatus: 'ENROLLED_ACTIVE',
      createdAtMs: 1_760_000_000_000,
      updatedAtMs: 1_760_000_000_000,
    };

    // Attacker sends registration probe with matching face but zero step-up
    const probeResponse = PersonIdentityDomainV19.buildRepeatRegistrationResponse({
      matchedPerson: personRecord,
      requestedRole: 'WORKER',
      rolePolicy: 'ALLOW_DUAL_ROLE_WITH_STEP_UP_AUTH',
      stepUpProof: { verified: false },
      matchedAccountPhoneLast4: '5177',
      reviewCaseId: 'rev_anti_enum_01',
    });

    expect(probeResponse.outcome).toBe('POTENTIAL_EXISTING_REGISTRATION');
    expect(probeResponse.allowedToCreateNewUnlinkedAccount).toBe(false);
    expect(probeResponse.disclosureStage).toBe('STEP_UP_REQUIRED_NO_PII');
    expect(probeResponse.maskedAccountHint).toBeNull(); // ZERO PII LEAKED
  });
});
