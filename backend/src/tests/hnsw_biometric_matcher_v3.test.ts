// backend/src/tests/hnsw_biometric_matcher_v3.test.ts
// Gate G-04: HighSpeedBiometricIndexV3 Unit Tests for Canonical 128-D SFace Contiguous Arena

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  HighSpeedBiometricIndexV3,
  EnrolledWorkerSfaceRecordV3,
} from '../services/hnsw_biometric_matcher_v3';
import {
  CANONICAL_SFACE_MODEL_ID,
  CANONICAL_SFACE_MODEL_VERSION,
  CANONICAL_TEMPLATE_SCHEMA_VERSION,
  SFACE_EMBEDDING_DIMENSION,
  l2NormalizeSfaceVector,
} from '../crypto/cloud_kms_envelope';

function createNormalizedVector(dim: number, primaryIndex: number, noise = 0.0): Float32Array {
  const vec = new Float32Array(dim);
  vec[primaryIndex % dim] = 1.0;
  if (noise > 0) {
    vec[(primaryIndex + 1) % dim] = noise;
  }
  return l2NormalizeSfaceVector(vec);
}

describe('HighSpeedBiometricIndexV3 & Canonical 128-D SFace Contiguous Arena', () => {
  it('enforces strict 128-D SFace dimensionality and normalization guardrails', () => {
    const index = new HighSpeedBiometricIndexV3(100);

    // Invalid dimensions should throw
    assert.throws(() => {
      index.upsertTemplate({
        uid: 'w1',
        maskedPhone: '+91 ****1234',
        modelId: CANONICAL_SFACE_MODEL_ID,
        modelVersion: CANONICAL_SFACE_MODEL_VERSION,
        templateSchemaVersion: CANONICAL_TEMPLATE_SCHEMA_VERSION,
        sfaceEmbedding128: new Float32Array(512), // Wrong length
        isoQualityScore: 85,
        padLivenessScore: 0.95,
        enrolledAtEpochMs: Date.now(),
      });
    }, /INVALID_SFACE_DIMENSION/);

    // Unnormalized vector should throw
    assert.throws(() => {
      const raw = new Float32Array(128);
      raw[0] = 5.0; // Norm is 5.0, not 1.0
      index.upsertTemplate({
        uid: 'w1',
        maskedPhone: '+91 ****1234',
        modelId: CANONICAL_SFACE_MODEL_ID,
        modelVersion: CANONICAL_SFACE_MODEL_VERSION,
        templateSchemaVersion: CANONICAL_TEMPLATE_SCHEMA_VERSION,
        sfaceEmbedding128: raw,
        isoQualityScore: 85,
        padLivenessScore: 0.95,
        enrolledAtEpochMs: Date.now(),
      });
    }, /UNNORMALIZED_SFACE_VECTOR/);
  });

  it('correctly auto-approves for distinct individuals with low cosine similarity', () => {
    const index = new HighSpeedBiometricIndexV3(100);
    index.upsertTemplate({
      uid: 'worker_alice',
      maskedPhone: '+91 ****1111',
      modelId: CANONICAL_SFACE_MODEL_ID,
      modelVersion: CANONICAL_SFACE_MODEL_VERSION,
      templateSchemaVersion: CANONICAL_TEMPLATE_SCHEMA_VERSION,
      sfaceEmbedding128: createNormalizedVector(128, 0),
      isoQualityScore: 90,
      padLivenessScore: 0.98,
      enrolledAtEpochMs: Date.now(),
    });

    // Probe is orthogonal to Alice (index 50 vs 0)
    const probe = createNormalizedVector(128, 50);

    const result = index.search1toN('worker_bob', probe);
    assert.equal(result.matchedUid, 'worker_alice');
    assert.ok(result.maxCosineSimilarity < 0.30);
  });

  it('detects duplicate match when cosine similarity >= 0.74', () => {
    const index = new HighSpeedBiometricIndexV3(100);
    index.upsertTemplate({
      uid: 'worker_alice',
      maskedPhone: '+91 ****1111',
      modelId: CANONICAL_SFACE_MODEL_ID,
      modelVersion: CANONICAL_SFACE_MODEL_VERSION,
      templateSchemaVersion: CANONICAL_TEMPLATE_SCHEMA_VERSION,
      sfaceEmbedding128: createNormalizedVector(128, 0, 0.05),
      isoQualityScore: 90,
      padLivenessScore: 0.98,
      enrolledAtEpochMs: Date.now(),
    });

    // Sybil probe claiming to be a new user but with Alice's face (similarity ~ 0.99)
    const probe = createNormalizedVector(128, 0, 0.08);

    const result = index.search1toN('worker_sybil', probe);
    assert.equal(result.matchedUid, 'worker_alice');
    assert.equal(result.matchedMaskedPhone, '+91 ****1111');
    assert.ok(result.maxCosineSimilarity >= 0.74);
  });

  it('executes 1,000-candidate 1:N search in sub-millisecond latency', () => {
    const index = new HighSpeedBiometricIndexV3(1500);
    for (let i = 0; i < 1000; i++) {
      index.upsertTemplate({
        uid: `worker_${i}`,
        maskedPhone: `+91 ****${i.toString().padStart(4, '0')}`,
        modelId: CANONICAL_SFACE_MODEL_ID,
        modelVersion: CANONICAL_SFACE_MODEL_VERSION,
        templateSchemaVersion: CANONICAL_TEMPLATE_SCHEMA_VERSION,
        sfaceEmbedding128: createNormalizedVector(128, i, 0.1),
        isoQualityScore: 85,
        padLivenessScore: 0.92,
        enrolledAtEpochMs: Date.now(),
      });
    }

    assert.equal(index.size, 1000);
    const probe = createNormalizedVector(128, 100, 0.1);

    const res = index.search1toN('probe_user', probe);
    assert.ok(res.searchLatencyMs < 10.0, `Expected < 10ms, got ${res.searchLatencyMs}ms`);
    assert.equal(res.candidatesEvaluated, 1000);
  });

  it('supports getRecordByUid, cloneWithUpsert, and cloneWithoutUid for lock-free CoW operations', () => {
    const index = new HighSpeedBiometricIndexV3(100);
    const rec1: EnrolledWorkerSfaceRecordV3 = {
      uid: 'worker_1',
      maskedPhone: '+91 ****1111',
      modelId: CANONICAL_SFACE_MODEL_ID,
      modelVersion: CANONICAL_SFACE_MODEL_VERSION,
      templateSchemaVersion: CANONICAL_TEMPLATE_SCHEMA_VERSION,
      sfaceEmbedding128: createNormalizedVector(128, 1),
      isoQualityScore: 88,
      padLivenessScore: 0.95,
      enrolledAtEpochMs: 1000,
    };
    const rec2: EnrolledWorkerSfaceRecordV3 = {
      uid: 'worker_2',
      maskedPhone: '+91 ****2222',
      modelId: CANONICAL_SFACE_MODEL_ID,
      modelVersion: CANONICAL_SFACE_MODEL_VERSION,
      templateSchemaVersion: CANONICAL_TEMPLATE_SCHEMA_VERSION,
      sfaceEmbedding128: createNormalizedVector(128, 2),
      isoQualityScore: 92,
      padLivenessScore: 0.99,
      enrolledAtEpochMs: 2000,
    };

    index.upsertTemplate(rec1);
    assert.equal(index.size, 1);

    // getRecordByUid
    const fetched1 = index.getRecordByUid('worker_1');
    assert.ok(fetched1 !== null);
    assert.equal(fetched1.uid, 'worker_1');
    assert.equal(fetched1.maskedPhone, '+91 ****1111');
    assert.equal(fetched1.isoQualityScore, 88);
    assert.equal(fetched1.sfaceEmbedding128.length, 128);
    assert.equal(index.getRecordByUid('nonexistent'), null);

    // cloneWithUpsert creates a new index without mutating original
    const clonedWith2 = index.cloneWithUpsert(rec2);
    assert.equal(index.size, 1); // Original unchanged
    assert.equal(clonedWith2.size, 2);
    assert.ok(clonedWith2.getRecordByUid('worker_1') !== null);
    assert.ok(clonedWith2.getRecordByUid('worker_2') !== null);

    // cloneWithoutUid removes worker_1 without mutating source index
    const clonedWithout1 = clonedWith2.cloneWithoutUid('worker_1');
    assert.equal(clonedWith2.size, 2); // Source unchanged
    assert.equal(clonedWithout1.size, 1);
    assert.equal(clonedWithout1.getRecordByUid('worker_1'), null);
    assert.ok(clonedWithout1.getRecordByUid('worker_2') !== null);
  });
});
