import * as admin from 'firebase-admin';
import {
  issueBiometricChallengeTransactional,
  CHALLENGE_COLLECTION,
  CHALLENGE_TTL_MS,
} from '../src/index';

describe('requestBiometricChallenge 60s Transactional Challenge Logic', () => {
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
        };

        const out = await fn(tx);
        for (const [k, v] of staged.entries()) {
          store.set(k, v);
        }
        return out;
      },
    } as unknown as admin.firestore.Firestore;
  });

  it('issues a 60-second challenge bound to (uid, purpose) and returns identical ticket on idempotent retry', async () => {
    const t0 = 1_760_000_000_000;

    const first = await issueBiometricChallengeTransactional({
      db: mockDb,
      uid: 'worker_901',
      purpose: 'verify_1to1',
      clientRequestId: 'req_retry_safe_01',
      issuedVia: 'callable_fallback',
      nowMs: t0,
    });

    expect(first.challengeId).toBe('chal_worker_901_verify_1to1_req_retry_safe_01');
    expect(first.ttlSeconds).toBe(60);
    expect(first.expiresAtMs - first.issuedAtMs).toBe(CHALLENGE_TTL_MS);
    expect(first.consumed).toBe(false);

    // Retry 2 seconds later with the same clientRequestId -> returns existing ticket
    const retry = await issueBiometricChallengeTransactional({
      db: mockDb,
      uid: 'worker_901',
      purpose: 'verify_1to1',
      clientRequestId: 'req_retry_safe_01',
      issuedVia: 'callable_fallback',
      nowMs: t0 + 2_000,
    });

    expect(retry.challengeId).toBe(first.challengeId);
    expect(retry.nonce).toBe(first.nonce);
    expect(retry.expiresAtMs).toBe(first.expiresAtMs);
  });

  it('allocates a fresh challenge ID without overwriting the audit record if previous ticket was consumed or near expiry', async () => {
    const t0 = 1_760_000_000_000;

    const first = await issueBiometricChallengeTransactional({
      db: mockDb,
      uid: 'worker_901',
      purpose: 'enroll',
      clientRequestId: 'req_reuse_test_02',
      issuedVia: 'callable_fallback',
      nowMs: t0,
    });

    // Simulate /enroll-biometric consuming the challenge
    const firstPath = `${CHALLENGE_COLLECTION}/${first.challengeId}`;
    store.set(firstPath, { ...store.get(firstPath), consumed: true });

    // Calling again with the same clientRequestId must allocate a NEW challengeId
    // and leave the consumed document untouched
    const second = await issueBiometricChallengeTransactional({
      db: mockDb,
      uid: 'worker_901',
      purpose: 'enroll',
      clientRequestId: 'req_reuse_test_02',
      issuedVia: 'callable_fallback',
      nowMs: t0 + 5_000,
    });

    expect(second.challengeId).not.toBe(first.challengeId);
    expect(second.nonce).not.toBe(first.nonce);
    expect(store.get(firstPath).consumed).toBe(true);
  });

  it('ignores malformed clientRequestId containing path separators and falls back to random hex ID', async () => {
    const ticket = await issueBiometricChallengeTransactional({
      db: mockDb,
      uid: 'worker_901',
      purpose: 'reverify_shift',
      clientRequestId: '../../biometric_vault/admin',
      issuedVia: 'callable_fallback',
    });

    expect(ticket.challengeId).toMatch(/^[0-9a-f]{32}$/);
  });
});
