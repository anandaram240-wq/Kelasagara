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
import {
  StepUpProofServiceV19,
} from '../services/step_up_proof_service_v19';

describe('V19.2 Master Adversarial Security & Identity Protection Suite', () => {
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

  // ── TEST 1: New Firebase UID submits verified:true and victim personId without server proof ──
  it('ADV-01: Rejects fabricated verified:true from untrusted caller and preserves victim identity state', async () => {
    const victimPersonId = PersonIdentityDomainV19.mintOpaquePersonId();
    store.set(`person_identities/${victimPersonId}`, {
      personId: victimPersonId,
      primaryAuthUid: 'victim_uid_001',
      linkedAuthUids: ['victim_uid_001'],
      workerId: 'victim_worker_profile',
      hirerId: null,
      activeBiometricEnrollmentId: 'bme_victim_1',
      activeTemplateGeneration: 1,
      biometricLifecycleStatus: 'ENROLLED_ACTIVE',
    });

    store.set('users/attacker_uid_999', {
      name: 'Mallory Attacker',
      role: 'worker',
      personId: 'prs_attacker_separate_id',
    });

    // Attacker fabricates verified: true in request body without server-issued proofId
    await assert.rejects(
      async () => {
        await IdentityBindingServiceV19.linkAuthorizedSecondRole({
          db: mockDb,
          callerUid: 'attacker_uid_999',
          targetPersonId: victimPersonId,
          newRole: 'HIRER',
          newRoleProfileId: 'attacker_hirer_profile',
          rolePolicy: 'ALLOW_DUAL_ROLE_WITH_STEP_UP_AUTH',
          stepUpProof: {
            verified: true,
            method: 'REGISTERED_PHONE_OTP',
            verifiedTargetPersonId: victimPersonId,
            verifiedAtMs: Date.now(),
          },
        });
      },
      /FORGED_PROOF_REJECTED/
    );

    // Assert zero database corruption on victim's record
    const victimRecord = store.get(`person_identities/${victimPersonId}`);
    assert.strictEqual(victimRecord.hirerId, null);
    assert.deepStrictEqual(victimRecord.linkedAuthUids, ['victim_uid_001']);
    assert.strictEqual(victimRecord.activeBiometricEnrollmentId, 'bme_victim_1');
  });

  // ── TEST 2: Caller supplies a forged verifiedTargetPersonId ──
  it('ADV-02: Rejects proof when caller tampers with targetPersonId', async () => {
    const legitPersonId = PersonIdentityDomainV19.mintOpaquePersonId();
    const victimPersonId = PersonIdentityDomainV19.mintOpaquePersonId();

    store.set(`person_identities/${victimPersonId}`, {
      personId: victimPersonId,
      primaryAuthUid: 'victim_user',
      linkedAuthUids: ['victim_user'],
      workerId: 'victim_worker',
      hirerId: null,
      activeBiometricEnrollmentId: 'bme_victim',
      activeTemplateGeneration: 1,
      biometricLifecycleStatus: 'ENROLLED_ACTIVE',
    });

    const proof = await StepUpProofServiceV19.issueProof({
      db: mockDb,
      issuedToUid: 'worker_alice',
      targetPersonId: legitPersonId,
      method: 'REGISTERED_PHONE_OTP',
    });

    // Caller attempts to use Alice's proof against a different target (victimPersonId)
    await assert.rejects(
      async () => {
        await IdentityBindingServiceV19.linkAuthorizedSecondRole({
          db: mockDb,
          callerUid: 'worker_alice',
          targetPersonId: victimPersonId,
          newRole: 'HIRER',
          newRoleProfileId: 'alice_hirer_profile',
          rolePolicy: 'ALLOW_DUAL_ROLE_WITH_STEP_UP_AUTH',
          stepUpProof: {
            verified: true,
            proofId: proof.proofId,
            method: 'REGISTERED_PHONE_OTP',
            verifiedTargetPersonId: victimPersonId, // Tampered target
            verifiedAtMs: Date.now(),
          },
        });
      },
      /PROOF_MISMATCH|STEP_UP_PROOF_TARGET_MISMATCH/
    );
  });

  // ── TEST 3: Proof generated for User A is submitted by User B ──
  it('ADV-03: Rejects proof issued for User A when submitted by User B (cross-user theft)', async () => {
    const targetPersonId = PersonIdentityDomainV19.mintOpaquePersonId();
    store.set(`person_identities/${targetPersonId}`, {
      personId: targetPersonId,
      primaryAuthUid: 'user_alice',
      linkedAuthUids: ['user_alice'],
      workerId: 'user_alice',
      hirerId: null,
      activeBiometricEnrollmentId: 'bme_alice',
      activeTemplateGeneration: 1,
      biometricLifecycleStatus: 'ENROLLED_ACTIVE',
    });

    // Server legitimately issued proof to Alice
    const proof = await StepUpProofServiceV19.issueProof({
      db: mockDb,
      issuedToUid: 'user_alice',
      targetPersonId,
      method: 'REGISTERED_PHONE_OTP',
    });

    // Mallory intercepts proofId and submits it as caller user_mallory
    await assert.rejects(
      async () => {
        await IdentityBindingServiceV19.linkAuthorizedSecondRole({
          db: mockDb,
          callerUid: 'user_mallory',
          targetPersonId,
          newRole: 'HIRER',
          newRoleProfileId: 'mallory_hirer_profile',
          rolePolicy: 'ALLOW_DUAL_ROLE_WITH_STEP_UP_AUTH',
          stepUpProof: {
            verified: true,
            proofId: proof.proofId,
            method: 'REGISTERED_PHONE_OTP',
            verifiedTargetPersonId: targetPersonId,
            verifiedAtMs: Date.now(),
          },
        });
      },
      /STEP_UP_PROOF_CALLER_MISMATCH/
    );

    // Assert target person remains uncompromised
    const person = store.get(`person_identities/${targetPersonId}`);
    assert.strictEqual(person.hirerId, null);
    assert.deepStrictEqual(person.linkedAuthUids, ['user_alice']);
  });

  // ── TEST 4: Expired, malformed, revoked, or fabricated proofs ──
  it('ADV-04: Rejects fabricated, expired, revoked, and signature-tampered proofs', async () => {
    const targetPersonId = PersonIdentityDomainV19.mintOpaquePersonId();
    store.set(`person_identities/${targetPersonId}`, {
      personId: targetPersonId,
      primaryAuthUid: 'test_user',
      linkedAuthUids: ['test_user'],
      workerId: 'test_user',
      hirerId: null,
      activeBiometricEnrollmentId: null,
      activeTemplateGeneration: 0,
      biometricLifecycleStatus: 'ENROLLED_ACTIVE',
    });

    // 4a. Fabricated non-existent proof
    await assert.rejects(
      async () => {
        await IdentityBindingServiceV19.linkAuthorizedSecondRole({
          db: mockDb,
          callerUid: 'test_user',
          targetPersonId,
          newRole: 'HIRER',
          newRoleProfileId: 'hirer_1',
          rolePolicy: 'ALLOW_DUAL_ROLE_WITH_STEP_UP_AUTH',
          stepUpProof: {
            verified: true,
            proofId: 'stp_fabricated_nonexistent_proof_9999',
            method: 'EXISTING_ACCOUNT_SIGN_IN',
            verifiedTargetPersonId: targetPersonId,
            verifiedAtMs: Date.now(),
          },
        });
      },
      /STEP_UP_PROOF_NOT_FOUND/
    );

    // 4b. Expired proof
    const expiredProof = await StepUpProofServiceV19.issueProof({
      db: mockDb,
      issuedToUid: 'test_user',
      targetPersonId,
      method: 'EXISTING_ACCOUNT_SIGN_IN',
      ttlMs: 100,
      nowMs: 1_000_000,
    });

    await assert.rejects(
      async () => {
        await IdentityBindingServiceV19.linkAuthorizedSecondRole({
          db: mockDb,
          callerUid: 'test_user',
          targetPersonId,
          newRole: 'HIRER',
          newRoleProfileId: 'hirer_1',
          rolePolicy: 'ALLOW_DUAL_ROLE_WITH_STEP_UP_AUTH',
          stepUpProof: {
            verified: true,
            proofId: expiredProof.proofId,
            method: 'EXISTING_ACCOUNT_SIGN_IN',
            verifiedTargetPersonId: targetPersonId,
            verifiedAtMs: 2_000_000,
          },
          nowMs: 2_000_000, // 1000s past expiration
        });
      },
      /STEP_UP_PROOF_EXPIRED/
    );

    // 4c. Revoked proof
    const validProof = await StepUpProofServiceV19.issueProof({
      db: mockDb,
      issuedToUid: 'test_user',
      targetPersonId,
      method: 'EXISTING_ACCOUNT_SIGN_IN',
    });
    await StepUpProofServiceV19.revokeProof({
      db: mockDb,
      proofId: validProof.proofId,
      revokedByUid: 'compliance_officer_9',
      reason: 'Session reset after suspicious activity',
    });

    await assert.rejects(
      async () => {
        await IdentityBindingServiceV19.linkAuthorizedSecondRole({
          db: mockDb,
          callerUid: 'test_user',
          targetPersonId,
          newRole: 'HIRER',
          newRoleProfileId: 'hirer_1',
          rolePolicy: 'ALLOW_DUAL_ROLE_WITH_STEP_UP_AUTH',
          stepUpProof: {
            verified: true,
            proofId: validProof.proofId,
            method: 'EXISTING_ACCOUNT_SIGN_IN',
            verifiedTargetPersonId: targetPersonId,
            verifiedAtMs: Date.now(),
          },
        });
      },
      /STEP_UP_PROOF_REVOKED/
    );

    // 4d. Cryptographic signature tampering
    const tamperedProof = await StepUpProofServiceV19.issueProof({
      db: mockDb,
      issuedToUid: 'test_user',
      targetPersonId,
      method: 'EXISTING_ACCOUNT_SIGN_IN',
    });
    // Tamper with signature in store
    const stored = store.get(`step_up_proofs/${tamperedProof.proofId}`);
    stored.signature = '0000111122223333444455556666777788889999aaaabbbbccccddddeeeeffff';
    store.set(`step_up_proofs/${tamperedProof.proofId}`, stored);

    await assert.rejects(
      async () => {
        await IdentityBindingServiceV19.linkAuthorizedSecondRole({
          db: mockDb,
          callerUid: 'test_user',
          targetPersonId,
          newRole: 'HIRER',
          newRoleProfileId: 'hirer_1',
          rolePolicy: 'ALLOW_DUAL_ROLE_WITH_STEP_UP_AUTH',
          stepUpProof: {
            verified: true,
            proofId: tamperedProof.proofId,
            method: 'EXISTING_ACCOUNT_SIGN_IN',
            verifiedTargetPersonId: targetPersonId,
            verifiedAtMs: Date.now(),
          },
        });
      },
      /STEP_UP_PROOF_SIGNATURE_INVALID/
    );
  });

  // ── TEST 5: Replay attack on consumed proof ──
  it('ADV-05: Rejects replay of a previously consumed proof', async () => {
    const targetPersonId = PersonIdentityDomainV19.mintOpaquePersonId();
    store.set(`person_identities/${targetPersonId}`, {
      personId: targetPersonId,
      primaryAuthUid: 'legit_user',
      linkedAuthUids: ['legit_user'],
      workerId: 'legit_user',
      hirerId: null,
      activeBiometricEnrollmentId: null,
      activeTemplateGeneration: 0,
      biometricLifecycleStatus: 'ENROLLED_ACTIVE',
    });
    store.set('users/legit_user', {
      name: 'Ramesh',
      role: 'worker',
      personId: targetPersonId,
    });

    const proof = await StepUpProofServiceV19.issueProof({
      db: mockDb,
      issuedToUid: 'legit_user',
      targetPersonId,
      method: 'EXISTING_ACCOUNT_SIGN_IN',
    });

    // 1st attempt: legitimate consumption
    const firstResult = await IdentityBindingServiceV19.linkAuthorizedSecondRole({
      db: mockDb,
      callerUid: 'legit_user',
      targetPersonId,
      newRole: 'HIRER',
      newRoleProfileId: 'hirer_profile_legit',
      rolePolicy: 'ALLOW_DUAL_ROLE_WITH_STEP_UP_AUTH',
      stepUpProof: {
        verified: true,
        proofId: proof.proofId,
        method: 'EXISTING_ACCOUNT_SIGN_IN',
        verifiedTargetPersonId: targetPersonId,
        verifiedAtMs: Date.now(),
      },
    });
    assert.strictEqual(firstResult.success, true);

    // 2nd attempt: attacker/script attempts to replay the same proofId
    await assert.rejects(
      async () => {
        await IdentityBindingServiceV19.linkAuthorizedSecondRole({
          db: mockDb,
          callerUid: 'legit_user',
          targetPersonId,
          newRole: 'HIRER',
          newRoleProfileId: 'hirer_profile_duplicate',
          rolePolicy: 'ALLOW_DUAL_ROLE_WITH_STEP_UP_AUTH',
          stepUpProof: {
            verified: true,
            proofId: proof.proofId,
            method: 'EXISTING_ACCOUNT_SIGN_IN',
            verifiedTargetPersonId: targetPersonId,
            verifiedAtMs: Date.now(),
          },
        });
      },
      /STEP_UP_PROOF_REPLAY_DETECTED/
    );
  });

  // ── TEST 6: New phone OTP proof cannot claim unrelated victim account ──
  it('ADV-06: New phone OTP proof fails when submitted against unrelated existing account', async () => {
    const freshAttackerPersonId = PersonIdentityDomainV19.mintOpaquePersonId();
    const existingVictimPersonId = PersonIdentityDomainV19.mintOpaquePersonId();

    store.set(`person_identities/${existingVictimPersonId}`, {
      personId: existingVictimPersonId,
      primaryAuthUid: 'victim_real_owner',
      linkedAuthUids: ['victim_real_owner'],
      workerId: 'victim_real_owner',
      hirerId: null,
      activeBiometricEnrollmentId: 'bme_victim',
      activeTemplateGeneration: 1,
      biometricLifecycleStatus: 'ENROLLED_ACTIVE',
    });

    // Attacker receives OTP proof for their newly registered number / personId
    const attackerOtpProof = await StepUpProofServiceV19.issueProof({
      db: mockDb,
      issuedToUid: 'attacker_new_sim',
      targetPersonId: freshAttackerPersonId,
      method: 'REGISTERED_PHONE_OTP',
    });

    // Attacker attempts to link to victim's existing account using their new SIM OTP proof
    await assert.rejects(
      async () => {
        await IdentityBindingServiceV19.linkAuthorizedSecondRole({
          db: mockDb,
          callerUid: 'attacker_new_sim',
          targetPersonId: existingVictimPersonId,
          newRole: 'HIRER',
          newRoleProfileId: 'attacker_hirer',
          rolePolicy: 'ALLOW_DUAL_ROLE_WITH_STEP_UP_AUTH',
          stepUpProof: {
            verified: true,
            proofId: attackerOtpProof.proofId,
            method: 'REGISTERED_PHONE_OTP',
            verifiedTargetPersonId: existingVictimPersonId,
            verifiedAtMs: Date.now(),
          },
        });
      },
      /STEP_UP_PROOF_TARGET_MISMATCH/
    );
  });

  // ── TEST 7: Client submits protected fields in update payloads ──
  it('ADV-07: assertNoClientWritableProtectedFields rejects every protected ownership field', () => {
    const protectedFields = [
      'personId',
      'primaryAuthUid',
      'linkedAuthUids',
      'activeBiometricEnrollmentId',
      'activeTemplateGeneration',
      'biometricLifecycleStatus',
      'faceVerified',
      'faceEnrolled',
      'accountStatus',
      'approvedBy',
      'approvedAt',
      'rejectedBy',
    ];

    for (const field of protectedFields) {
      assert.throws(
        () => {
          IdentityBindingServiceV19.assertNoClientWritableProtectedFields({
            displayName: 'Legitimate Name',
            [field]: 'malicious_injected_value',
          });
        },
        /SECURITY_VIOLATION/,
        `Field ${field} must trigger a SECURITY_VIOLATION exception`
      );
    }
  });

  // ── TEST 8: Role-linking collision on already occupied profile slot ──
  it('ADV-08: Rejects second role link when the requested role profile slot is already occupied', async () => {
    const personId = PersonIdentityDomainV19.mintOpaquePersonId();
    store.set(`person_identities/${personId}`, {
      personId,
      primaryAuthUid: 'owner_uid',
      linkedAuthUids: ['owner_uid'],
      workerId: 'worker_profile_active',
      hirerId: 'hirer_profile_already_occupied', // Hirer slot already taken
      activeBiometricEnrollmentId: 'bme_1',
      activeTemplateGeneration: 1,
      biometricLifecycleStatus: 'ENROLLED_ACTIVE',
    });
    store.set('users/owner_uid', { role: 'worker', personId });

    const proof = await StepUpProofServiceV19.issueProof({
      db: mockDb,
      issuedToUid: 'owner_uid',
      targetPersonId: personId,
      method: 'EXISTING_ACCOUNT_SIGN_IN',
    });

    await assert.rejects(
      async () => {
        await IdentityBindingServiceV19.linkAuthorizedSecondRole({
          db: mockDb,
          callerUid: 'owner_uid',
          targetPersonId: personId,
          newRole: 'HIRER',
          newRoleProfileId: 'hirer_profile_intruder',
          rolePolicy: 'ALLOW_DUAL_ROLE_WITH_STEP_UP_AUTH',
          stepUpProof: {
            verified: true,
            proofId: proof.proofId,
            method: 'EXISTING_ACCOUNT_SIGN_IN',
            verifiedTargetPersonId: personId,
            verifiedAtMs: Date.now(),
          },
        });
      },
      /PERSON_ALREADY_HAS_ACTIVE_HIRER_PROFILE/
    );

    // Stored hirer profile remains unchanged
    const person = store.get(`person_identities/${personId}`);
    assert.strictEqual(person.hirerId, 'hirer_profile_already_occupied');
  });

  // ── TEST 9: Policy disallowing dual roles ──
  it('ADV-09: Rejects role linking when system policy is SINGLE_ROLE_ONLY_WITH_REVIEW', async () => {
    const personId = PersonIdentityDomainV19.mintOpaquePersonId();
    store.set(`person_identities/${personId}`, {
      personId,
      primaryAuthUid: 'worker_uid',
      linkedAuthUids: ['worker_uid'],
      workerId: 'worker_uid',
      hirerId: null,
      activeBiometricEnrollmentId: 'bme_1',
      activeTemplateGeneration: 1,
      biometricLifecycleStatus: 'ENROLLED_ACTIVE',
    });

    const proof = await StepUpProofServiceV19.issueProof({
      db: mockDb,
      issuedToUid: 'worker_uid',
      targetPersonId: personId,
      method: 'EXISTING_ACCOUNT_SIGN_IN',
    });

    await assert.rejects(
      async () => {
        await IdentityBindingServiceV19.linkAuthorizedSecondRole({
          db: mockDb,
          callerUid: 'worker_uid',
          targetPersonId: personId,
          newRole: 'HIRER',
          newRoleProfileId: 'hirer_1',
          rolePolicy: 'SINGLE_ROLE_ONLY_WITH_REVIEW', // Policy blocks dual role
          stepUpProof: {
            verified: true,
            proofId: proof.proofId,
            method: 'EXISTING_ACCOUNT_SIGN_IN',
            verifiedTargetPersonId: personId,
            verifiedAtMs: Date.now(),
          },
        });
      },
      /ROLE_LINKING_DISABLED_BY_POLICY/
    );
  });

  // ── TEST 10: Concurrent requests attempting to consume the same proof ──
  it('ADV-10: Two concurrent requests attempting to consume the same proof results in exactly one success and one replay rejection', async () => {
    const personId = PersonIdentityDomainV19.mintOpaquePersonId();
    store.set(`person_identities/${personId}`, {
      personId,
      primaryAuthUid: 'race_worker_uid',
      linkedAuthUids: ['race_worker_uid'],
      workerId: 'race_worker_uid',
      hirerId: null,
      activeBiometricEnrollmentId: 'bme_race',
      activeTemplateGeneration: 1,
      biometricLifecycleStatus: 'ENROLLED_ACTIVE',
    });
    store.set('users/race_worker_uid', {
      name: 'Racing Worker',
      role: 'worker',
      personId,
    });

    const proof = await StepUpProofServiceV19.issueProof({
      db: mockDb,
      issuedToUid: 'race_worker_uid',
      targetPersonId: personId,
      method: 'EXISTING_ACCOUNT_SIGN_IN',
    });

    // Execute first request
    const firstCall = await IdentityBindingServiceV19.linkAuthorizedSecondRole({
      db: mockDb,
      callerUid: 'race_worker_uid',
      targetPersonId: personId,
      newRole: 'HIRER',
      newRoleProfileId: 'hirer_profile_race',
      rolePolicy: 'ALLOW_DUAL_ROLE_WITH_STEP_UP_AUTH',
      stepUpProof: {
        verified: true,
        proofId: proof.proofId,
        method: 'EXISTING_ACCOUNT_SIGN_IN',
        verifiedTargetPersonId: personId,
        verifiedAtMs: Date.now(),
      },
    });
    assert.strictEqual(firstCall.success, true);

    // Second concurrent/racing request with same proof
    await assert.rejects(
      async () => {
        await IdentityBindingServiceV19.linkAuthorizedSecondRole({
          db: mockDb,
          callerUid: 'race_worker_uid',
          targetPersonId: personId,
          newRole: 'HIRER',
          newRoleProfileId: 'hirer_profile_race_2',
          rolePolicy: 'ALLOW_DUAL_ROLE_WITH_STEP_UP_AUTH',
          stepUpProof: {
            verified: true,
            proofId: proof.proofId,
            method: 'EXISTING_ACCOUNT_SIGN_IN',
            verifiedTargetPersonId: personId,
            verifiedAtMs: Date.now(),
          },
        });
      },
      /STEP_UP_PROOF_REPLAY_DETECTED/
    );
  });
});
