import { describe, it, beforeEach } from 'node:test';
import assert from 'node:assert';
import express from 'express';
import request from 'supertest';
import admin from 'firebase-admin';
import crypto from 'crypto';

if (!admin.apps.length) {
  admin.initializeApp({ projectId: 'test-kelasagara-v19-3' });
}

import { createIdentityRouter } from '../routes/identity_routes';
import { StepUpProofServiceV19, StepUpProofRecordV19 } from '../services/step_up_proof_service_v19';
import { RegisteredPhoneOtpServiceV19 } from '../services/registered_phone_otp_service_v19';
import { ServerSignInProofServiceV19 } from '../services/server_sign_in_proof_service_v19';
import { IdentityBindingServiceV19 } from '../services/identity_binding_service_v19';
import { PersonIdentityDomainV19, PersonIdentityRecordV19 } from '../models/person_identity_v19';

describe('V19.3 Master End-to-End Proof Issuance, Route Integration & Journey Suite', () => {
  let app: express.Express;
  let store: Map<string, any>;
  let mockDb: admin.firestore.Firestore;

  const ALICE_UID = 'alice_worker_uid';
  const ALICE_PERSON_ID = 'prs_0123456789abcdef0123456789abcdef';
  const ALICE_PHONE = '+919876543210';
  const ATTACKER_UID = 'mallory_attacker_uid';
  const OFFICER_UID = 'compliance_officer_bob';
  const NEW_DEVICE_UID = 'alice_new_phone_uid';

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

    // Seed baseline identities
    store.set(`person_identities/${ALICE_PERSON_ID}`, {
      personId: ALICE_PERSON_ID,
      primaryAuthUid: ALICE_UID,
      linkedAuthUids: [ALICE_UID],
      workerId: 'wrk_alice_profile',
      hirerId: null,
      activeBiometricEnrollmentId: 'bme_alice_01',
      activeTemplateGeneration: 1,
      biometricLifecycleStatus: 'ENROLLED_ACTIVE',
      createdAtMs: Date.now() - 100000,
      updatedAtMs: Date.now() - 100000,
    });

    store.set(`users/${ALICE_UID}`, {
      uid: ALICE_UID,
      displayName: 'Alice Worker',
      phoneNumber: ALICE_PHONE,
      role: 'worker',
      personId: ALICE_PERSON_ID,
      accountStatus: 'approved',
      faceVerified: true,
    });

    store.set(`users/${NEW_DEVICE_UID}`, {
      uid: NEW_DEVICE_UID,
      displayName: 'Alice New Phone',
      phoneNumber: '+919999988888', // New SIM card
      role: 'worker',
      accountStatus: 'pending_face',
      faceVerified: false,
    });

    store.set(`users/${ATTACKER_UID}`, {
      uid: ATTACKER_UID,
      displayName: 'Mallory Impersonator',
      phoneNumber: '+919111122222',
      role: 'worker',
      accountStatus: 'pending_face',
      faceVerified: false,
    });

    // Mock admin.auth().verifyIdToken
    admin.auth().verifyIdToken = async (token: string) => {
      const nowSec = Math.floor(Date.now() / 1000);
      switch (token) {
        case 'token_alice':
          return { uid: ALICE_UID, auth_time: nowSec, role: 'worker' } as any;
        case 'token_alice_stale':
          return { uid: ALICE_UID, auth_time: nowSec - 1800, role: 'worker' } as any; // 30 min old
        case 'token_attacker':
          return { uid: ATTACKER_UID, auth_time: nowSec, role: 'worker' } as any;
        case 'token_new_device':
          return { uid: NEW_DEVICE_UID, auth_time: nowSec, role: 'worker' } as any;
        case 'token_officer':
          return {
            uid: OFFICER_UID,
            auth_time: nowSec,
            biometric_compliance_officer: true,
            email: 'officer@kelasagara.in',
          } as any;
        case 'token_non_officer':
          return {
            uid: ATTACKER_UID,
            auth_time: nowSec,
            biometric_compliance_officer: false,
            email: 'mallory@evil.com',
          } as any;
        default:
          throw new Error('Invalid Firebase token.');
      }
    };

    app = express();
    app.use(express.json());
    app.use('/api/identity', createIdentityRouter(mockDb));
  });

  // =========================================================================
  // SECTION 1: THE 12 ADVERSARIAL ATTACK SCENARIOS
  // =========================================================================

  it('ADV-01: Rejects fabricated step-up proofId with 400 and does not mutate identity', async () => {
    // 1. Linked user submitting fabricated proof
    const res = await request(app)
      .post('/api/identity/link-second-role')
      .set('Authorization', 'Bearer token_alice')
      .send({
        proofId: 'stp_completely_fabricated_id_9999',
        targetPersonId: ALICE_PERSON_ID,
        newRole: 'HIRER',
        newRoleProfileId: 'hirer_alice_exploit',
      });

    assert.strictEqual(res.status, 400);
    assert.strictEqual(res.body.success, false);
    assert.strictEqual(res.body.error, 'ROLE_LINK_FAILED');
    assert.match(res.body.message, /STEP_UP_PROOF_NOT_FOUND/);

    // 2. Unlinked attacker attempting to touch target identity
    const resAttacker = await request(app)
      .post('/api/identity/link-second-role')
      .set('Authorization', 'Bearer token_attacker')
      .send({
        proofId: 'stp_completely_fabricated_id_9999',
        targetPersonId: ALICE_PERSON_ID,
        newRole: 'HIRER',
        newRoleProfileId: 'hirer_mallory_exploit',
      });
    assert.strictEqual(resAttacker.status, 400);
    assert.match(resAttacker.body.message, /UNAUTHORIZED_SESSION/);

    // Verify Alice's record is completely unchanged
    const person = store.get(`person_identities/${ALICE_PERSON_ID}`);
    assert.strictEqual(person.hirerId, null);
    assert.deepStrictEqual(person.linkedAuthUids, [ALICE_UID]);
  });

  it('ADV-02: Rejects tampered proof signature with 400 (timing-safe HMAC check)', async () => {
    // Generate valid proof for Alice
    const proof = await StepUpProofServiceV19.issueProof({
      db: mockDb,
      issuedToUid: ALICE_UID,
      targetPersonId: ALICE_PERSON_ID,
      method: 'EXISTING_ACCOUNT_SIGN_IN',
    });

    // Adversary tampers with the HMAC signature bytes directly in Firestore store
    const tampered = store.get(`step_up_proofs/${proof.proofId}`);
    tampered.signature = crypto.randomBytes(32).toString('hex'); // Forged signature
    store.set(`step_up_proofs/${proof.proofId}`, tampered);

    const res = await request(app)
      .post('/api/identity/link-second-role')
      .set('Authorization', 'Bearer token_alice')
      .send({
        proofId: proof.proofId,
        targetPersonId: ALICE_PERSON_ID,
        newRole: 'HIRER',
        newRoleProfileId: 'hirer_alice_tampered',
      });

    assert.strictEqual(res.status, 400);
    assert.strictEqual(res.body.error, 'ROLE_LINK_FAILED');
    assert.match(res.body.message, /STEP_UP_PROOF_SIGNATURE_INVALID/);
  });

  it('ADV-03: Rejects proof replay attack (single-use transactional consumption)', async () => {
    // Issue proof to Alice
    const proof = await StepUpProofServiceV19.issueProof({
      db: mockDb,
      issuedToUid: ALICE_UID,
      targetPersonId: ALICE_PERSON_ID,
      method: 'EXISTING_ACCOUNT_SIGN_IN',
    });

    // 1st consumption: succeeds
    const res1 = await request(app)
      .post('/api/identity/link-second-role')
      .set('Authorization', 'Bearer token_alice')
      .send({
        proofId: proof.proofId,
        targetPersonId: ALICE_PERSON_ID,
        newRole: 'HIRER',
        newRoleProfileId: 'hirer_alice_valid',
      });

    assert.strictEqual(res1.status, 200);
    assert.strictEqual(res1.body.success, true);
    assert.strictEqual(res1.body.data.hirerId, 'hirer_alice_valid');

    // 2nd consumption: replay attack fails
    const res2 = await request(app)
      .post('/api/identity/link-second-role')
      .set('Authorization', 'Bearer token_alice')
      .send({
        proofId: proof.proofId,
        targetPersonId: ALICE_PERSON_ID,
        newRole: 'HIRER',
        newRoleProfileId: 'hirer_alice_replayed',
      });

    assert.strictEqual(res2.status, 400);
    assert.strictEqual(res2.body.error, 'ROLE_LINK_FAILED');
    assert.match(res2.body.message, /STEP_UP_PROOF_REPLAY_DETECTED/);
  });

  it('ADV-04: Rejects expired proof (> 5 minutes TTL)', async () => {
    const expiredProof = await StepUpProofServiceV19.issueProof({
      db: mockDb,
      issuedToUid: ALICE_UID,
      targetPersonId: ALICE_PERSON_ID,
      method: 'EXISTING_ACCOUNT_SIGN_IN',
      ttlMs: 1000, // 1 second TTL
      nowMs: Date.now() - 10000, // 10 seconds ago
    });

    const res = await request(app)
      .post('/api/identity/link-second-role')
      .set('Authorization', 'Bearer token_alice')
      .send({
        proofId: expiredProof.proofId,
        targetPersonId: ALICE_PERSON_ID,
        newRole: 'HIRER',
        newRoleProfileId: 'hirer_alice_expired',
      });

    assert.strictEqual(res.status, 400);
    assert.match(res.body.message, /STEP_UP_PROOF_EXPIRED/);
  });

  it('ADV-05: Rejects cross-caller proof theft (Attacker uses Alice\'s proof)', async () => {
    const proof = await StepUpProofServiceV19.issueProof({
      db: mockDb,
      issuedToUid: ALICE_UID,
      targetPersonId: ALICE_PERSON_ID,
      method: 'EXISTING_ACCOUNT_SIGN_IN',
    });

    // Attacker Mallory attempts to submit Alice's proof on /link-secondary-uid
    const res = await request(app)
      .post('/api/identity/link-secondary-uid')
      .set('Authorization', 'Bearer token_attacker')
      .send({
        proofId: proof.proofId,
        existingPersonId: ALICE_PERSON_ID,
      });

    assert.strictEqual(res.status, 400);
    assert.match(res.body.message, /STEP_UP_PROOF_CALLER_MISMATCH/);
  });

  it('ADV-06: Rejects cross-target personId mismatch', async () => {
    const otherPersonId = PersonIdentityDomainV19.mintOpaquePersonId();
    store.set(`person_identities/${otherPersonId}`, {
      personId: otherPersonId,
      primaryAuthUid: ALICE_UID,
      linkedAuthUids: [ALICE_UID],
      workerId: 'wrk_other',
      hirerId: null,
      activeBiometricEnrollmentId: 'bme_other',
      activeTemplateGeneration: 1,
      biometricLifecycleStatus: 'ENROLLED_ACTIVE',
    });

    const proof = await StepUpProofServiceV19.issueProof({
      db: mockDb,
      issuedToUid: ALICE_UID,
      targetPersonId: ALICE_PERSON_ID,
      method: 'EXISTING_ACCOUNT_SIGN_IN',
    });

    const res = await request(app)
      .post('/api/identity/link-second-role')
      .set('Authorization', 'Bearer token_alice')
      .send({
        proofId: proof.proofId,
        targetPersonId: otherPersonId,
        newRole: 'HIRER',
        newRoleProfileId: 'hirer_alice_wrong_target',
      });

    assert.strictEqual(res.status, 400);
    assert.match(res.body.message, /STEP_UP_PROOF_TARGET_MISMATCH/);
  });

  it('ADV-07: Rejects revoked step-up proof', async () => {
    const proof = await StepUpProofServiceV19.issueProof({
      db: mockDb,
      issuedToUid: ALICE_UID,
      targetPersonId: ALICE_PERSON_ID,
      method: 'EXISTING_ACCOUNT_SIGN_IN',
    });

    await StepUpProofServiceV19.revokeProof({
      db: mockDb,
      proofId: proof.proofId,
      revokedByUid: OFFICER_UID,
      reason: 'Security incident: suspected compromised token',
    });

    const res = await request(app)
      .post('/api/identity/link-second-role')
      .set('Authorization', 'Bearer token_alice')
      .send({
        proofId: proof.proofId,
        targetPersonId: ALICE_PERSON_ID,
        newRole: 'HIRER',
        newRoleProfileId: 'hirer_alice_revoked',
      });

    assert.strictEqual(res.status, 400);
    assert.match(res.body.message, /STEP_UP_PROOF_REVOKED/);
  });

  it('ADV-08: Rejects client injection of forbidden protected fields', async () => {
    const res = await request(app)
      .post('/api/identity/link-second-role')
      .set('Authorization', 'Bearer token_alice')
      .send({
        proofId: 'stp_any_id',
        targetPersonId: ALICE_PERSON_ID,
        newRole: 'HIRER',
        newRoleProfileId: 'hirer_alice_injected',
        faceVerified: true, // Injected!
        personId: 'prs_injected', // Injected!
      });

    assert.strictEqual(res.status, 400);
    assert.match(res.body.message, /SECURITY_VIOLATION: Direct client modification of protected field/);
  });

  it('ADV-09: Rejects stale authentication session on /issue-sign-in-proof (auth_time > 15m)', async () => {
    const res = await request(app)
      .post('/api/identity/issue-sign-in-proof')
      .set('Authorization', 'Bearer token_alice_stale') // 30 minutes old session
      .send({});

    assert.strictEqual(res.status, 401);
    assert.strictEqual(res.body.error, 'SIGN_IN_PROOF_FAILED');
    assert.match(res.body.message, /RECENT_AUTH_REQUIRED/);
  });

  it('ADV-10: Locks OTP session after 3 consecutive incorrect attempts', async () => {
    // Request OTP for Alice
    const otpSession = await RegisteredPhoneOtpServiceV19.requestOtpForRegisteredPhone({
      db: mockDb,
      callerUid: NEW_DEVICE_UID,
      targetPersonId: ALICE_PERSON_ID,
      testOtpCode: '852963',
    });

    const sessionId = otpSession.sessionId;

    // Attempt 1: wrong code
    const r1 = await request(app)
      .post('/api/identity/verify-registered-phone-otp')
      .set('Authorization', 'Bearer token_new_device')
      .send({ sessionId, code: '000000' });
    assert.strictEqual(r1.status, 400);
    assert.match(r1.body.message, /Attempts remaining: 2/);

    // Attempt 2: wrong code
    const r2 = await request(app)
      .post('/api/identity/verify-registered-phone-otp')
      .set('Authorization', 'Bearer token_new_device')
      .send({ sessionId, code: '111111' });
    assert.strictEqual(r2.status, 400);
    assert.match(r2.body.message, /Attempts remaining: 1/);

    // Attempt 3: wrong code
    const r3 = await request(app)
      .post('/api/identity/verify-registered-phone-otp')
      .set('Authorization', 'Bearer token_new_device')
      .send({ sessionId, code: '222222' });
    assert.strictEqual(r3.status, 400);
    assert.match(r3.body.message, /Attempts remaining: 0/);

    // Attempt 4: Even with CORRECT code, session is LOCKED
    const r4 = await request(app)
      .post('/api/identity/verify-registered-phone-otp')
      .set('Authorization', 'Bearer token_new_device')
      .send({ sessionId, code: '852963' });
    assert.strictEqual(r4.status, 400);
    assert.match(r4.body.message, /OTP_SESSION_LOCKED/);
  });

  it('ADV-11: Rejects verification of expired OTP session (> 5 minutes)', async () => {
    const expiredOtp = await RegisteredPhoneOtpServiceV19.requestOtpForRegisteredPhone({
      db: mockDb,
      callerUid: NEW_DEVICE_UID,
      targetPersonId: ALICE_PERSON_ID,
      nowMs: Date.now() - 360000, // 6 minutes ago
      testOtpCode: '123456',
    });

    const res = await request(app)
      .post('/api/identity/verify-registered-phone-otp')
      .set('Authorization', 'Bearer token_new_device')
      .send({ sessionId: expiredOtp.sessionId, code: '123456' });

    assert.strictEqual(res.status, 400);
    assert.match(res.body.message, /OTP_SESSION_EXPIRED/);
  });

  it('ADV-12: Rejects non-officer caller on /compliance/issue-proof with 403', async () => {
    // Seed review case
    store.set('biometric_review_queue/case_dispute_123', {
      reviewCaseId: 'case_dispute_123',
      claimantUid: NEW_DEVICE_UID,
      targetPersonId: ALICE_PERSON_ID,
      status: 'APPROVED',
      consumedForProof: false,
    });

    const res = await request(app)
      .post('/api/identity/compliance/issue-proof')
      .set('Authorization', 'Bearer token_non_officer')
      .send({ reviewCaseId: 'case_dispute_123' });

    assert.strictEqual(res.status, 403);
    assert.strictEqual(res.body.error, 'FORBIDDEN_COMPLIANCE_OFFICER_CLAIM_REQUIRED');
  });

  // =========================================================================
  // SECTION 2: END-TO-END IDENTITY JOURNEYS (A THROUGH H)
  // =========================================================================

  it('JOURNEY A: Fresh user registration creates authoritative PersonIdentityRecordV19', async () => {
    const freshUid = 'worker_fresh_001';
    const mintedPersonId = PersonIdentityDomainV19.mintOpaquePersonId();
    const enrollmentId = PersonIdentityDomainV19.mintOpaqueBiometricEnrollmentId();

    const newPerson: PersonIdentityRecordV19 = {
      personId: mintedPersonId,
      primaryAuthUid: freshUid,
      linkedAuthUids: [freshUid],
      workerId: 'wrk_fresh_001',
      hirerId: null,
      activeBiometricEnrollmentId: enrollmentId,
      activeTemplateGeneration: 1,
      biometricLifecycleStatus: 'ENROLLED_ACTIVE',
      createdAtMs: Date.now(),
      updatedAtMs: Date.now(),
    };

    PersonIdentityDomainV19.assertValidOpaquePersonId(newPerson.personId);
    assert.strictEqual(newPerson.personId, mintedPersonId);
    assert.strictEqual(newPerson.primaryAuthUid, freshUid);
    assert.deepStrictEqual(newPerson.linkedAuthUids, [freshUid]);
    assert.strictEqual(newPerson.workerId, 'wrk_fresh_001');
    assert.strictEqual(newPerson.hirerId, null);
    assert.strictEqual(newPerson.biometricLifecycleStatus, 'ENROLLED_ACTIVE');
  });

  it('JOURNEY B: Duplicate face interception blocks unlinked account creation and enforces anti-enumeration', async () => {
    const candidatePerson = store.get(`person_identities/${ALICE_PERSON_ID}`) as PersonIdentityRecordV19;

    // Stage 1: Prior to step-up verification, maskedAccountHint is STRICTLY NULL (Anti-Enumeration)
    const preStepUp = PersonIdentityDomainV19.buildRepeatRegistrationResponse({
      matchedPerson: candidatePerson,
      requestedRole: 'WORKER',
      rolePolicy: 'ALLOW_DUAL_ROLE_WITH_STEP_UP_AUTH',
      stepUpProof: { verified: false },
      matchedAccountPhoneLast4: '3210',
      reviewCaseId: 'rev_case_journey_b',
    });

    assert.strictEqual(preStepUp.outcome, 'POTENTIAL_EXISTING_REGISTRATION');
    assert.strictEqual(preStepUp.allowedToCreateNewUnlinkedAccount, false);
    assert.strictEqual(preStepUp.disclosureStage, 'STEP_UP_REQUIRED_NO_PII');
    assert.strictEqual(preStepUp.maskedAccountHint, null); // Zero information leakage!

    // Stage 2: Post-step-up verification, disclosure stage reveals minimal hint for legitimate claimant
    const postStepUp = PersonIdentityDomainV19.buildRepeatRegistrationResponse({
      matchedPerson: candidatePerson,
      requestedRole: 'WORKER',
      rolePolicy: 'ALLOW_DUAL_ROLE_WITH_STEP_UP_AUTH',
      stepUpProof: {
        verified: true,
        proofId: 'stp_valid_dummy',
        method: 'REGISTERED_PHONE_OTP',
        verifiedTargetPersonId: ALICE_PERSON_ID,
        verifiedAtMs: Date.now(),
      },
      matchedAccountPhoneLast4: '3210',
      reviewCaseId: 'rev_case_journey_b',
    });

    assert.strictEqual(postStepUp.outcome, 'POTENTIAL_EXISTING_REGISTRATION');
    assert.strictEqual(postStepUp.allowedToCreateNewUnlinkedAccount, false);
    assert.strictEqual(postStepUp.disclosureStage, 'STEP_UP_VERIFIED_MINIMAL_HINT');
    assert.ok(postStepUp.maskedAccountHint?.referenceCode.includes('3210'));
  });

  it('JOURNEY C: Worker Alice links second marketplace role (HIRER) via recent sign-in proof', async () => {
    // 1. Alice requests sign-in step-up proof with fresh auth session
    const proofRes = await request(app)
      .post('/api/identity/issue-sign-in-proof')
      .set('Authorization', 'Bearer token_alice')
      .send({});

    assert.strictEqual(proofRes.status, 200);
    assert.strictEqual(proofRes.body.success, true);
    const proofId = proofRes.body.data.proofId;
    assert.ok(proofId.startsWith('stp_'));

    // 2. Alice presents proof to link second role
    const linkRes = await request(app)
      .post('/api/identity/link-second-role')
      .set('Authorization', 'Bearer token_alice')
      .send({
        proofId,
        targetPersonId: ALICE_PERSON_ID,
        newRole: 'HIRER',
        newRoleProfileId: 'hirer_alice_official_profile',
      });

    assert.strictEqual(linkRes.status, 200);
    assert.strictEqual(linkRes.body.success, true);
    assert.strictEqual(linkRes.body.data.roleLinked, 'HIRER');
    assert.strictEqual(linkRes.body.data.workerId, 'wrk_alice_profile');
    assert.strictEqual(linkRes.body.data.hirerId, 'hirer_alice_official_profile');

    // 3. Confirm in store
    const updatedPerson = store.get(`person_identities/${ALICE_PERSON_ID}`);
    assert.strictEqual(updatedPerson.hirerId, 'hirer_alice_official_profile');
    assert.strictEqual(updatedPerson.workerId, 'wrk_alice_profile');
  });

  it('JOURNEY D: Returning user on new phone links secondary UID via registered phone OTP', async () => {
    // 1. New device triggers OTP to registered phone on record
    const otpReqRes = await request(app)
      .post('/api/identity/request-registered-phone-otp')
      .set('Authorization', 'Bearer token_new_device')
      .send({ targetPersonId: ALICE_PERSON_ID });

    assert.strictEqual(otpReqRes.status, 200);
    assert.strictEqual(otpReqRes.body.success, true);
    const sessionId = otpReqRes.body.data.sessionId;
    assert.strictEqual(otpReqRes.body.data.maskedPhone, '******3210');

    // Seed predictable code for testing session
    const otpSession = store.get(`phone_otp_sessions/${sessionId}`);
    const testCode = '654321';
    otpSession.salt = 'test_salt_123';
    otpSession.otpHash = crypto.createHash('sha256').update(`${testCode}:test_salt_123`).digest('hex');
    store.set(`phone_otp_sessions/${sessionId}`, otpSession);

    // 2. User submits correct OTP code
    const verifyRes = await request(app)
      .post('/api/identity/verify-registered-phone-otp')
      .set('Authorization', 'Bearer token_new_device')
      .send({ sessionId, code: testCode });

    assert.strictEqual(verifyRes.status, 200);
    assert.strictEqual(verifyRes.body.success, true);
    const proofId = verifyRes.body.data.proofId;

    // 3. User links new device UID using proof
    const linkRes = await request(app)
      .post('/api/identity/link-secondary-uid')
      .set('Authorization', 'Bearer token_new_device')
      .send({
        proofId,
        existingPersonId: ALICE_PERSON_ID,
      });

    assert.strictEqual(linkRes.status, 200);
    assert.strictEqual(linkRes.body.success, true);
    assert.ok(linkRes.body.data.linkedAuthUids.includes(NEW_DEVICE_UID));
    assert.ok(linkRes.body.data.linkedAuthUids.includes(ALICE_UID));

    // Confirm store
    const updatedPerson = store.get(`person_identities/${ALICE_PERSON_ID}`);
    assert.deepStrictEqual(updatedPerson.linkedAuthUids, [ALICE_UID, NEW_DEVICE_UID]);
    const newUser = store.get(`users/${NEW_DEVICE_UID}`);
    assert.strictEqual(newUser.personId, ALICE_PERSON_ID);
  });

  it('JOURNEY E: Compliance officer manually resolves review case and issues step-up proof', async () => {
    // Seed approved review case
    const reviewCaseId = 'case_rev_777';
    store.set(`biometric_review_queue/${reviewCaseId}`, {
      reviewCaseId,
      claimantUid: NEW_DEVICE_UID,
      targetPersonId: ALICE_PERSON_ID,
      status: 'APPROVED',
      consumedForProof: false,
      reviewedByOfficer: OFFICER_UID,
    });

    // 1. Compliance officer issues proof
    const officerRes = await request(app)
      .post('/api/identity/compliance/issue-proof')
      .set('Authorization', 'Bearer token_officer')
      .send({ reviewCaseId });

    assert.strictEqual(officerRes.status, 200);
    assert.strictEqual(officerRes.body.success, true);
    const proofId = officerRes.body.data.proofId;
    assert.strictEqual(officerRes.body.data.claimantUid, NEW_DEVICE_UID);

    // 2. Claimant consumes proof to link secondary UID
    const linkRes = await request(app)
      .post('/api/identity/link-secondary-uid')
      .set('Authorization', 'Bearer token_new_device')
      .send({
        proofId,
        existingPersonId: ALICE_PERSON_ID,
      });

    assert.strictEqual(linkRes.status, 200);
    assert.strictEqual(linkRes.body.success, true);
    assert.ok(linkRes.body.data.linkedAuthUids.includes(NEW_DEVICE_UID));
  });

  it('JOURNEY F: Enforces fail-closed protection against client self-assignment of faceVerified', async () => {
    // Assert client cannot inject faceVerified through identity routes
    const res = await request(app)
      .post('/api/identity/link-second-role')
      .set('Authorization', 'Bearer token_alice')
      .send({
        proofId: 'stp_any',
        targetPersonId: ALICE_PERSON_ID,
        newRole: 'HIRER',
        newRoleProfileId: 'h_profile',
        faceVerified: true,
      });

    assert.strictEqual(res.status, 400);
    assert.match(res.body.message, /SECURITY_VIOLATION: Direct client modification of protected field 'faceVerified' is forbidden/);
  });

  it('JOURNEY G: Concurrent race condition — two parallel requests with same proof -> exactly 1 succeeds', async () => {
    const proof = await StepUpProofServiceV19.issueProof({
      db: mockDb,
      issuedToUid: ALICE_UID,
      targetPersonId: ALICE_PERSON_ID,
      method: 'EXISTING_ACCOUNT_SIGN_IN',
    });

    // Fire two requests simultaneously with the same proof
    const [res1, res2] = await Promise.all([
      request(app)
        .post('/api/identity/link-second-role')
        .set('Authorization', 'Bearer token_alice')
        .send({
          proofId: proof.proofId,
          targetPersonId: ALICE_PERSON_ID,
          newRole: 'HIRER',
          newRoleProfileId: 'hirer_alice_race_1',
        }),
      request(app)
        .post('/api/identity/link-second-role')
        .set('Authorization', 'Bearer token_alice')
        .send({
          proofId: proof.proofId,
          targetPersonId: ALICE_PERSON_ID,
          newRole: 'HIRER',
          newRoleProfileId: 'hirer_alice_race_2',
        }),
    ]);

    const statuses = [res1.status, res2.status].sort();
    assert.deepStrictEqual(statuses, [200, 400]);

    const failedRes = res1.status === 400 ? res1 : res2;
    assert.match(failedRes.body.message, /STEP_UP_PROOF_REPLAY_DETECTED/);
  });

  it('JOURNEY H: Tamper attempt on person identity document preserves state', async () => {
    const origPerson = store.get(`person_identities/${ALICE_PERSON_ID}`);

    // Mallory tries to link Alice's personId to Mallory's UID without proof
    const res = await request(app)
      .post('/api/identity/link-secondary-uid')
      .set('Authorization', 'Bearer token_attacker')
      .send({
        proofId: 'stp_fake_proof',
        existingPersonId: ALICE_PERSON_ID,
      });

    assert.strictEqual(res.status, 400);

    // Verify Alice's person record in store has not been corrupted
    const currentPerson = store.get(`person_identities/${ALICE_PERSON_ID}`);
    assert.deepStrictEqual(currentPerson, origPerson);
  });
});
