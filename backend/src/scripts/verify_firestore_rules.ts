// File: backend/src/scripts/verify_firestore_rules.ts
// KELASAGARA V18 — Gate G-05 Automated Firestore Security Rules Penetration Suite
// Verifies strict server-only lockdown across all 5 biometric collections.

import * as fs from 'node:fs';
import * as path from 'node:path';
import {
  assertFails,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from '@firebase/rules-unit-testing';

export const LOCKED_BIOMETRIC_COLLECTIONS_V18 = [
  { collection: 'biometric_vault', sampleDocId: 'KLS-WKR-0001' },
  { collection: 'biometric_audit_queue', sampleDocId: 'audit_KLS-WKR-0001_1' },
  { collection: 'biometric_cluster_meta', sampleDocId: 'global_state' },
  { collection: 'biometric_idempotency', sampleDocId: 'idem_key_0001' },
  { collection: 'biometric_wal_outbox', sampleDocId: '000000000001' },
] as const;

export async function runFirestoreRulesVerificationV18(params?: {
  readonly projectId?: string;
  readonly rulesFilePath?: string;
  readonly emulatorHost?: string;
  readonly emulatorPort?: number;
}): Promise<{
  readonly passedAssertions: number;
  readonly verifiedCollections: readonly string[];
}> {
  const projectId = params?.projectId ?? 'kelasagaara-v18-rules-verify';
  const rulesPath =
    params?.rulesFilePath ??
    path.resolve(__dirname, '../../../firestore.rules');
  const rulesContent = fs.readFileSync(rulesPath, 'utf8');

  const testEnv: RulesTestEnvironment = await initializeTestEnvironment({
    projectId,
    firestore: {
      rules: rulesContent,
      host: params?.emulatorHost ?? '127.0.0.1',
      port: params?.emulatorPort ?? 8080,
    },
  });

  let passedAssertions = 0;

  try {
    const unauthContext = testEnv.unauthenticatedContext();
    const workerOwnContext = testEnv.authenticatedContext('KLS-WKR-0001', {
      role: 'worker',
    });
    const adminClaimClientContext = testEnv.authenticatedContext(
      'KLS-ADMIN-CLIENT',
      {
        role: 'admin',
        admin: true,
      },
    );

    for (const target of LOCKED_BIOMETRIC_COLLECTIONS_V18) {
      const docPath = `${target.collection}/${target.sampleDocId}`;

      // 1. Unauthenticated client read & write MUST fail
      await assertFails(unauthContext.firestore().doc(docPath).get());
      await assertFails(
        unauthContext.firestore().doc(docPath).set({ tampered: true }),
      );
      passedAssertions += 2;

      // 2. Authenticated worker reading or writing their own UID document MUST fail
      await assertFails(workerOwnContext.firestore().doc(docPath).get());
      await assertFails(
        workerOwnContext.firestore().doc(docPath).set({ tampered: true }),
      );
      await assertFails(workerOwnContext.firestore().doc(docPath).delete());
      passedAssertions += 3;

      // 3. Even a client token with custom { admin: true } claims MUST fail via client SDK
      // (Only backend Firebase Admin SDK bypassing security rules may access these collections)
      await assertFails(adminClaimClientContext.firestore().doc(docPath).get());
      await assertFails(
        adminClaimClientContext.firestore().doc(docPath).set({ tampered: true }),
      );
      passedAssertions += 2;
    }

    return {
      passedAssertions,
      verifiedCollections: LOCKED_BIOMETRIC_COLLECTIONS_V18.map(
        (c) => c.collection,
      ),
    };
  } finally {
    await testEnv.cleanup();
  }
}

if (require.main === module) {
  runFirestoreRulesVerificationV18()
    .then((res) => {
      console.log(
        `[Gate G-05 PASSED] Verified ${res.passedAssertions} denial assertions across: ${res.verifiedCollections.join(', ')}`,
      );
    })
    .catch((err) => {
      console.error('[Gate G-05 FAILED]', err);
      process.exitCode = 1;
    });
}
