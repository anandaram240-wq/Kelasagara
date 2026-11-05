import * as fs from 'fs';
import * as path from 'path';
import { describe, it, before, after, beforeEach } from 'node:test';
import assert from 'node:assert';
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
  RulesTestEnvironment,
} from '@firebase/rules-unit-testing';

const isEmulatorActive = Boolean(process.env.FIRESTORE_EMULATOR_HOST);

describe(
  'V19.3 Live Firestore Emulator Security Rules & Penetration Suite',
  {
    skip: !isEmulatorActive
      ? 'FIRESTORE_EMULATOR_HOST not detected. Execute with emulator via: export JAVA_HOME=/opt/homebrew/opt/openjdk && npx firebase emulators:exec --only firestore "node --test backend/dist/tests/firestore_emulator_security_rules_v19_3.test.js"'
      : false,
  },
  () => {
  let testEnv: RulesTestEnvironment;

  before(async () => {
    const rulesPath = path.resolve(__dirname, '../../../firestore.rules');
    const rulesContent = fs.readFileSync(rulesPath, 'utf8');

    testEnv = await initializeTestEnvironment({
      projectId: 'kelasagara-rules-pentest-v19-3',
      firestore: {
        rules: rulesContent,
        host: process.env.FIRESTORE_EMULATOR_HOST?.split(':')[0] || '127.0.0.1',
        port: Number(process.env.FIRESTORE_EMULATOR_HOST?.split(':')[1] || 8080),
      },
    });
  });

  after(async () => {
    if (testEnv) {
      await testEnv.cleanup();
    }
  });

  beforeEach(async () => {
    if (testEnv) {
      await testEnv.clearFirestore();

      // Seed baseline database state using Admin SDK (simulating server state)
      await testEnv.withSecurityRulesDisabled(async (adminCtx) => {
        const db = adminCtx.firestore();

        // 1. Authoritative person identity
        await db.collection('person_identities').doc('prs_test_alice_001').set({
          personId: 'prs_test_alice_001',
          primaryAuthUid: 'alice_uid',
          linkedAuthUids: ['alice_uid'],
          workerId: 'alice_uid',
          hirerId: null,
          activeBiometricEnrollmentId: 'bme_alice',
          activeTemplateGeneration: 1,
          biometricLifecycleStatus: 'ENROLLED_ACTIVE',
        });

        // 2. Secret server step-up proof
        await db.collection('step_up_proofs').doc('stp_secret_proof_alice').set({
          proofId: 'stp_secret_proof_alice',
          issuedToUid: 'alice_uid',
          targetPersonId: 'prs_test_alice_001',
          method: 'REGISTERED_PHONE_OTP',
          consumed: false,
          expiresAtMs: Date.now() + 300000,
        });

        // 3. Biometric vault record
        await db.collection('biometric_vault').doc('alice_uid').set({
          ciphertextBase64: 'kms_encrypted_vector_data',
          wrappedDekBase64: 'wrapped_dek_key',
          phoneNumber: '+919876543210',
          role: 'worker',
        });

        // 4. Biometric challenge record
        await db.collection('biometric_challenges').doc('chal_secret_123').set({
          nonce: 'secret_cryptographic_nonce',
          uid: 'alice_uid',
          consumed: false,
        });

        // 5. Existing user doc for Alice (worker, pending_face)
        await db.collection('users').doc('alice_uid').set({
          displayName: 'Alice Gowda',
          role: 'worker',
          accountStatus: 'pending_face',
          faceVerified: false,
          personId: 'prs_test_alice_001',
          createdAt: new Date().toISOString(),
        });
      });
    }
  });

  // ── TEST 1: Direct client read of person_identities is FORBIDDEN ──
  it('RULE-01: Direct client read of /person_identities/{id} is strictly denied', async () => {
    const aliceDb = testEnv.authenticatedContext('alice_uid').firestore();
    const attackerDb = testEnv.authenticatedContext('mallory_uid').firestore();
    const unauthDb = testEnv.unauthenticatedContext().firestore();

    await assertFails(aliceDb.collection('person_identities').doc('prs_test_alice_001').get());
    await assertFails(attackerDb.collection('person_identities').doc('prs_test_alice_001').get());
    await assertFails(unauthDb.collection('person_identities').doc('prs_test_alice_001').get());
  });

  // ── TEST 2: Direct client write of person_identities is FORBIDDEN ──
  it('RULE-02: Direct client write to /person_identities/{id} is strictly denied', async () => {
    const aliceDb = testEnv.authenticatedContext('alice_uid').firestore();
    const attackerDb = testEnv.authenticatedContext('mallory_uid').firestore();

    await assertFails(
      aliceDb.collection('person_identities').doc('prs_test_alice_001').update({
        hirerId: 'forged_hirer_id',
      })
    );
    await assertFails(
      attackerDb.collection('person_identities').doc('prs_forged_intruder').set({
        personId: 'prs_forged_intruder',
        primaryAuthUid: 'mallory_uid',
      })
    );
  });

  // ── TEST 3: Direct client read/write of step_up_proofs is FORBIDDEN ──
  it('RULE-03: Direct client read and write to /step_up_proofs/{id} is strictly denied', async () => {
    const aliceDb = testEnv.authenticatedContext('alice_uid').firestore();
    const attackerDb = testEnv.authenticatedContext('mallory_uid').firestore();

    await assertFails(aliceDb.collection('step_up_proofs').doc('stp_secret_proof_alice').get());
    await assertFails(attackerDb.collection('step_up_proofs').doc('stp_secret_proof_alice').get());
    await assertFails(
      attackerDb.collection('step_up_proofs').doc('stp_forged_proof_mallory').set({
        proofId: 'stp_forged_proof_mallory',
        issuedToUid: 'mallory_uid',
        consumed: false,
      })
    );
  });

  // ── TEST 4: Direct client read/write of biometric_vault is FORBIDDEN ──
  it('RULE-04: Direct client access to /biometric_vault/{uid} is strictly denied', async () => {
    const aliceDb = testEnv.authenticatedContext('alice_uid').firestore();
    const attackerDb = testEnv.authenticatedContext('mallory_uid').firestore();

    await assertFails(aliceDb.collection('biometric_vault').doc('alice_uid').get());
    await assertFails(attackerDb.collection('biometric_vault').doc('alice_uid').get());
    await assertFails(
      attackerDb.collection('biometric_vault').doc('alice_uid').set({
        ciphertextBase64: 'injected_vector',
      })
    );
  });

  // ── TEST 5: Direct client read/write of biometric_challenges is FORBIDDEN ──
  it('RULE-05: Direct client access to /biometric_challenges/{id} is strictly denied', async () => {
    const aliceDb = testEnv.authenticatedContext('alice_uid').firestore();
    const attackerDb = testEnv.authenticatedContext('mallory_uid').firestore();

    await assertFails(aliceDb.collection('biometric_challenges').doc('chal_secret_123').get());
    await assertFails(
      attackerDb.collection('biometric_challenges').doc('chal_secret_123').update({
        consumed: false,
      })
    );
  });

  // ── TEST 6: Client attempt to set faceVerified: true is STRICTLY FORBIDDEN (Remediation of Branch 2C) ──
  it('RULE-06: Client cannot self-assign faceVerified: true or bypass biometric enrollment', async () => {
    const aliceDb = testEnv.authenticatedContext('alice_uid').firestore();

    // Alice attempts to set faceVerified=true and advance status to approved
    await assertFails(
      aliceDb.collection('users').doc('alice_uid').update({
        faceVerified: true,
        accountStatus: 'approved',
      })
    );

    // Alice attempts to set faceVerified=true with pending_review
    await assertFails(
      aliceDb.collection('users').doc('alice_uid').update({
        faceVerified: true,
        accountStatus: 'pending_review',
      })
    );
  });

  // ── TEST 7: Client attempt to tamper with personId or protected identity ownership fields ──
  it('RULE-07: Client cannot modify personId, linkedAuthUids, or biometric ownership fields', async () => {
    const aliceDb = testEnv.authenticatedContext('alice_uid').firestore();

    await assertFails(
      aliceDb.collection('users').doc('alice_uid').update({
        personId: 'prs_hijacked_new_identity',
      })
    );

    await assertFails(
      aliceDb.collection('users').doc('alice_uid').update({
        primaryAuthUid: 'attacker_uid',
      })
    );

    await assertFails(
      aliceDb.collection('users').doc('alice_uid').update({
        linkedAuthUids: ['alice_uid', 'attacker_uid'],
      })
    );

    await assertFails(
      aliceDb.collection('users').doc('alice_uid').update({
        activeBiometricEnrollmentId: 'bme_forged',
      })
    );
  });

  // ── TEST 8: Legitimate client profile update succeeds ──
  it('RULE-08: Legitimate profile updates by account owner succeed cleanly', async () => {
    const aliceDb = testEnv.authenticatedContext('alice_uid').firestore();

    await assertSucceeds(
      aliceDb.collection('users').doc('alice_uid').update({
        displayName: 'Alice G. Gowda',
        bio: 'Certified master electrician in Bangalore',
      })
    );
  });

  // ── TEST 9: Unauthenticated reads to unapproved worker profiles are denied ──
  it('RULE-09: Unauthenticated clients cannot read unapproved worker profiles', async () => {
    const unauthDb = testEnv.unauthenticatedContext().firestore();
    // alice_uid has accountStatus: 'pending_face'
    await assertFails(unauthDb.collection('users').doc('alice_uid').get());
  });

  // ── TEST 10: Admin SDK bypasses security rules safely for server-authoritative operations ──
  it('RULE-10: Backend Admin SDK can read and write all protected collections', async () => {
    await testEnv.withSecurityRulesDisabled(async (adminCtx) => {
      const db = adminCtx.firestore();

      const personSnap = await db.collection('person_identities').doc('prs_test_alice_001').get();
      assert.strictEqual(personSnap.exists, true);

      const proofSnap = await db.collection('step_up_proofs').doc('stp_secret_proof_alice').get();
      assert.strictEqual(proofSnap.exists, true);

      await db.collection('users').doc('alice_uid').update({
        faceVerified: true,
        accountStatus: 'approved',
      });

      const userSnap = await db.collection('users').doc('alice_uid').get();
      assert.strictEqual(userSnap.data()?.faceVerified, true);
      assert.strictEqual(userSnap.data()?.accountStatus, 'approved');
    });
  });
});
