// backend/src/tests/firestore_vector_search.test.ts
import { describe, it } from 'node:test';
import assert from 'node:assert';
import admin from 'firebase-admin';
import { FirestoreBiometricRepository } from '../services/firestore_biometric_repository';

describe('FirestoreBiometricRepository Distributed Vector Search & LRU (Gate G-04)', () => {
  const probe = new Array(128).fill(1 / Math.sqrt(128));

  it('findTopKDistributed converts Firestore COSINE distance (1 - distance) to similarity and excludes caller UID', async () => {
    const mockDocs = [
      {
        id: 'caller_uid_1',
        data: () => ({ vectorDistance: 0.0, phoneNumberMasked: '+91******1111', status: 'active' }),
      },
      {
        id: 'duplicate_worker_2',
        data: () => ({ vectorDistance: 0.14, phoneNumberMasked: '+91******2222', status: 'active' }),
      },
      {
        id: 'distinct_worker_3',
        data: () => ({ vectorDistance: 0.62, phoneNumberMasked: '+91******3333', status: 'active' }),
      },
    ];

    const mockGet = async () => ({ docs: mockDocs });
    const mockFindNearest = () => ({ get: mockGet });
    const mockCollection = () => ({
      findNearest: mockFindNearest,
    });

    FirestoreBiometricRepository._customDb = {
      collection: mockCollection,
    };
    (admin.firestore.FieldValue as any).vector = (arr: number[]) => arr;

    try {
      const matches = await FirestoreBiometricRepository.findTopKDistributed(probe, 'caller_uid_1', 2);

      assert.strictEqual(matches.length, 2);
      assert.strictEqual(matches[0].uid, 'duplicate_worker_2');
      assert.ok(Math.abs(matches[0].similarity - 0.86) < 0.001);
      assert.strictEqual(matches[1].uid, 'distinct_worker_3');
      assert.ok(Math.abs(matches[1].similarity - 0.38) < 0.001);
    } finally {
      FirestoreBiometricRepository._customDb = null;
    }
  });

  it('getEncryptedTemplate1to1 serves repeated 1:1 lookups from the in-memory LRU cache until invalidated', async () => {
    let getCallCount = 0;

    const mockDocGet = async () => {
      getCallCount++;
      return {
        exists: true,
        data: () => ({
          status: 'active',
          ciphertextBase64: 'ct_b64',
          ivBase64: 'iv_b64',
          authTagBase64: 'tag_b64',
          wrappedDekBase64: 'dek_b64',
          keyId: 'kek_v1',
          modelId: 'sface_2021dec_int8',
        }),
      };
    };

    const mockDoc = () => ({ get: mockDocGet });
    const mockCollection = () => ({
      doc: mockDoc,
    });

    FirestoreBiometricRepository._customDb = {
      collection: mockCollection,
    };

    try {
      const first = await FirestoreBiometricRepository.getEncryptedTemplate1to1('worker_99');
      const second = await FirestoreBiometricRepository.getEncryptedTemplate1to1('worker_99');

      assert.strictEqual(first?.ciphertextBase64, 'ct_b64');
      assert.strictEqual(second?.ciphertextBase64, 'ct_b64');
      assert.strictEqual(getCallCount, 1); // Served from cache!

      FirestoreBiometricRepository.invalidateCache('worker_99');
      await FirestoreBiometricRepository.getEncryptedTemplate1to1('worker_99');
      assert.strictEqual(getCallCount, 2); // Re-fetched after invalidation!
    } finally {
      FirestoreBiometricRepository._customDb = null;
    }
  });
});
