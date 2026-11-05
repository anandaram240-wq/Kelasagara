// backend/src/tests/gallery_consistency_v3.test.ts
// Gate G-03 (Cloud KMS HSM Envelope Encryption) and Gate G-04 (Lock-free CoW Gallery Index & Epoch Synchronization)

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  CANONICAL_SFACE_MODEL_ID,
  CANONICAL_SFACE_MODEL_VERSION,
  CANONICAL_TEMPLATE_SCHEMA_VERSION,
  SFACE_EMBEDDING_DIMENSION,
  SFACE_V3_BINARY_PAYLOAD_BYTES,
  BiometricPlaintextSfacePayloadV3,
  CanonicalAadContext,
  CloudKmsEnvelopeService,
  LocalDevKeyProvider,
  packSfacePayloadV3,
  unpackSfacePayloadV3,
  l2NormalizeSfaceVector,
} from '../crypto/cloud_kms_envelope';
import {
  BiometricAuditTicketV3,
  BiometricVaultPersistenceAdapter,
  GalleryConsistencyServiceV3,
  StoredVaultDocumentV3,
} from '../services/gallery_consistency_service';

function createDummyPayload(seed: number, quality = 85.0, pad = 0.95): BiometricPlaintextSfacePayloadV3 {
  const raw = new Float32Array(128);
  raw[seed % 128] = 1.0;
  raw[(seed + 1) % 128] = 0.05;
  return {
    sfaceEmbedding128: l2NormalizeSfaceVector(raw),
    isoQualityScore: quality,
    padLivenessScore: pad,
  };
}

class MockBiometricVaultPersistence implements BiometricVaultPersistenceAdapter {
  public globalEpoch = 1;
  public docs = new Map<string, StoredVaultDocumentV3>();
  public auditTickets: BiometricAuditTicketV3[] = [];

  async getGlobalEpoch(): Promise<number> {
    return this.globalEpoch;
  }

  async incrementGlobalEpoch(expectedCurrentEpoch?: number): Promise<number> {
    if (expectedCurrentEpoch !== undefined && this.globalEpoch !== expectedCurrentEpoch) {
      throw new Error(`EPOCH_CONFLICT: expected ${expectedCurrentEpoch}, current ${this.globalEpoch}`);
    }
    this.globalEpoch++;
    return this.globalEpoch;
  }

  async fetchAllActiveTemplates(): Promise<StoredVaultDocumentV3[]> {
    return Array.from(this.docs.values()).filter((d) => d.status !== 'ERASED');
  }

  async getVaultDocumentByUid(uid: string): Promise<StoredVaultDocumentV3 | null> {
    return this.docs.get(uid) ?? null;
  }

  async saveVaultDocument(doc: StoredVaultDocumentV3): Promise<void> {
    this.docs.set(doc.uid, doc);
  }

  async deleteVaultDocument(uid: string): Promise<boolean> {
    return this.docs.delete(uid);
  }

  async enqueueAuditTicket(ticket: BiometricAuditTicketV3): Promise<void> {
    this.auditTickets.push(ticket);
  }
}

describe('Gate G-03: Cloud KMS Envelope Encryption & 520-Byte Binary Frame', () => {
  it('correctly packs and unpacks 128-D SFace + quality + PAD into exactly 520 bytes', () => {
    const payload = createDummyPayload(101, 88.5, 0.99);
    const packed = packSfacePayloadV3(payload);

    assert.equal(packed.length, SFACE_V3_BINARY_PAYLOAD_BYTES);
    assert.equal(packed.length, 520);

    const unpacked = unpackSfacePayloadV3(packed);
    assert.equal(unpacked.sfaceEmbedding128.length, 128);
    assert.ok(Math.abs(unpacked.sfaceEmbedding128[101] - payload.sfaceEmbedding128[101]) < 1e-6);
    assert.ok(Math.abs(unpacked.isoQualityScore - 88.5) < 1e-4);
    assert.ok(Math.abs(unpacked.padLivenessScore - 0.99) < 1e-4);
  });

  it('rejects invalid embedding buffer dimensions in packSfacePayloadV3', () => {
    assert.throws(() => {
      packSfacePayloadV3({
        sfaceEmbedding128: new Float32Array(512), // Wrong length
        isoQualityScore: 80,
        padLivenessScore: 0.9,
      });
    }, /INVALID_SFACE_DIMENSION/);

    assert.throws(() => {
      const raw = new Float32Array(128);
      raw[0] = 5.0; // Unnormalized
      packSfacePayloadV3({
        sfaceEmbedding128: raw,
        isoQualityScore: 80,
        padLivenessScore: 0.9,
      });
    }, /UNNORMALIZED_SFACE_VECTOR/);
  });

  it('seals and unseals template payload under AES-256-GCM envelope encryption with LocalDevKeyProvider', async () => {
    const keyProvider = new LocalDevKeyProvider();
    const kms = new CloudKmsEnvelopeService(keyProvider);

    const originalPayload = createDummyPayload(42, 91.0, 0.97);
    const aad: CanonicalAadContext = {
      uid: 'worker_test_42',
      tenantId: 'tenant_karnataka_bengaluru',
      modelVersion: CANONICAL_SFACE_MODEL_VERSION,
      templateSchemaVersion: CANONICAL_TEMPLATE_SCHEMA_VERSION,
      purpose: 'BIOMETRIC_VAULT_SFACE_V3',
    };

    const sealed = await kms.sealTemplateV3(originalPayload, aad);
    assert.equal(sealed.schemaVersion, 3);
    assert.equal(sealed.modelId, CANONICAL_SFACE_MODEL_ID);
    assert.equal(sealed.modelVersion, CANONICAL_SFACE_MODEL_VERSION);
    assert.ok(sealed.ciphertextBase64.length > 520);

    const decrypted = await kms.unsealTemplateV3(sealed, aad);
    assert.equal(decrypted.sfaceEmbedding128.length, 128);
    assert.ok(Math.abs(decrypted.isoQualityScore - 91.0) < 1e-4);
    assert.ok(Math.abs(decrypted.padLivenessScore - 0.97) < 1e-4);
  });

  it('strictly rejects decryption if AAD context (UID or tenant) is modified (Context Binding INV-02)', async () => {
    const keyProvider = new LocalDevKeyProvider();
    const kms = new CloudKmsEnvelopeService(keyProvider);

    const payload = createDummyPayload(77, 85.0, 0.92);
    const correctAad: CanonicalAadContext = {
      uid: 'worker_alice',
      tenantId: 'tenant_south',
      modelVersion: CANONICAL_SFACE_MODEL_VERSION,
      templateSchemaVersion: CANONICAL_TEMPLATE_SCHEMA_VERSION,
      purpose: 'BIOMETRIC_VAULT_SFACE_V3',
    };

    const sealed = await kms.sealTemplateV3(payload, correctAad);

    // Tamper with UID in AAD
    const tamperedAadUid: CanonicalAadContext = {
      ...correctAad,
      uid: 'worker_eve',
    };

    await assert.rejects(
      async () => kms.unsealTemplateV3(sealed, tamperedAadUid),
      /Unsupported state or unable to authenticate data/,
    );

    // Tamper with tenant in AAD
    const tamperedAadTenant: CanonicalAadContext = {
      ...correctAad,
      tenantId: 'tenant_north',
    };

    await assert.rejects(
      async () => kms.unsealTemplateV3(sealed, tamperedAadTenant),
      /Unsupported state or unable to authenticate data/,
    );
  });

  it('rejects corrupted ciphertext or auth tag (INV-01)', async () => {
    const keyProvider = new LocalDevKeyProvider();
    const kms = new CloudKmsEnvelopeService(keyProvider);

    const payload = createDummyPayload(88);
    const aad: CanonicalAadContext = {
      uid: 'worker_bob',
      tenantId: 'tenant_default',
      modelVersion: CANONICAL_SFACE_MODEL_VERSION,
      templateSchemaVersion: CANONICAL_TEMPLATE_SCHEMA_VERSION,
      purpose: 'BIOMETRIC_VAULT_SFACE_V3',
    };

    const sealed = await kms.sealTemplateV3(payload, aad);

    // Corrupt ciphertext buffer
    const corruptedCiphertext = Buffer.from(sealed.ciphertextBase64, 'base64');
    corruptedCiphertext[20] ^= 0xff; // Bit flip

    const corruptedEnvelope = {
      ...sealed,
      ciphertextBase64: corruptedCiphertext.toString('base64'),
    };

    await assert.rejects(
      async () => kms.unsealTemplateV3(corruptedEnvelope, aad),
      /Unsupported state or unable to authenticate data/,
    );
  });
});

describe('Gate G-04: Lock-Free Copy-on-Write HNSW Gallery Index & Global Epoch Synchronization', () => {
  it('synchronizes local CoW snapshot with remote persistence epoch', async () => {
    const persistence = new MockBiometricVaultPersistence();
    const kms = new CloudKmsEnvelopeService(new LocalDevKeyProvider());
    const service = new GalleryConsistencyServiceV3(persistence, kms);

    assert.equal(service.getCurrentEpoch(), -1);
    await service.ensureSynchronized();
    assert.equal(service.getCurrentEpoch(), 1);
    assert.equal(service.getActiveGallerySize(), 0);
  });

  it('enrolls unique worker, bumps global epoch, and updates active CoW arena (CLEAN_APPROVED)', async () => {
    const persistence = new MockBiometricVaultPersistence();
    const kms = new CloudKmsEnvelopeService(new LocalDevKeyProvider());
    const service = new GalleryConsistencyServiceV3(persistence, kms);
    await service.ensureSynchronized();

    const outcome = await service.enrollWithGlobalEpochBump({
      uid: 'worker_alice',
      maskedPhone: '+91 ****1234',
      payload: createDummyPayload(1, 95.0, 0.99),
    });

    assert.equal(outcome.enrolled, true);
    assert.equal(outcome.decisionStatus, 'CLEAN_APPROVED');
    assert.equal(outcome.globalEpoch, 2);
    assert.equal(service.getCurrentEpoch(), 2);
    assert.equal(service.getActiveGallerySize(), 1);
    assert.equal(persistence.docs.size, 1);
  });

  it('halts and returns HARD_DUPLICATE_BLOCKED when similarity >= 0.90 (no epoch bump)', async () => {
    const persistence = new MockBiometricVaultPersistence();
    const kms = new CloudKmsEnvelopeService(new LocalDevKeyProvider());
    const service = new GalleryConsistencyServiceV3(persistence, kms);
    await service.ensureSynchronized();

    // Alice enrolls
    await service.enrollWithGlobalEpochBump({
      uid: 'worker_alice',
      maskedPhone: '+91 ****1111',
      payload: createDummyPayload(1, 90.0, 0.98),
    });
    assert.equal(service.getCurrentEpoch(), 2);

    // Sybil attempts enrollment with Alice's identical vector
    const outcome = await service.enrollWithGlobalEpochBump({
      uid: 'worker_sybil',
      maskedPhone: '+91 ****9999',
      payload: createDummyPayload(1, 90.0, 0.98),
    });

    assert.equal(outcome.enrolled, false);
    assert.equal(outcome.decisionStatus, 'HARD_DUPLICATE_BLOCKED');
    assert.equal(outcome.globalEpoch, 2); // No epoch bump
    assert.equal(service.getActiveGallerySize(), 1); // Not inserted
    assert.equal(persistence.docs.size, 1);
    assert.equal(outcome.duplicateSearch.matchedUid, 'worker_alice');
  });

  it('enqueues audit ticket for DUPLICATE_WARNING_FLAGGED (0.74 <= sim < 0.90) and sets status to PENDING_AUDIT', async () => {
    const persistence = new MockBiometricVaultPersistence();
    const kms = new CloudKmsEnvelopeService(new LocalDevKeyProvider());
    const service = new GalleryConsistencyServiceV3(persistence, kms);
    await service.ensureSynchronized();

    const aliceVec = createDummyPayload(1);
    await service.enrollWithGlobalEpochBump({
      uid: 'worker_alice',
      maskedPhone: '+91 ****1111',
      payload: aliceVec,
    });

    // Synthesize a vector that has cosine similarity ~ 0.80 with Alice (between 0.74 and 0.90)
    const rawSimilar = new Float32Array(128);
    for (let i = 0; i < 128; i++) {
      rawSimilar[i] = aliceVec.sfaceEmbedding128[i] * 0.8 + (i === 10 ? 0.6 : 0.0);
    }
    const similarPayload: BiometricPlaintextSfacePayloadV3 = {
      sfaceEmbedding128: l2NormalizeSfaceVector(rawSimilar),
      isoQualityScore: 88,
      padLivenessScore: 0.95,
    };

    const outcome = await service.enrollWithGlobalEpochBump({
      uid: 'worker_ambiguous',
      maskedPhone: '+91 ****8888',
      payload: similarPayload,
    });

    assert.equal(outcome.enrolled, true);
    assert.equal(outcome.decisionStatus, 'DUPLICATE_WARNING_FLAGGED');
    assert.equal(service.getActiveGallerySize(), 2);
    assert.equal(persistence.auditTickets.length, 1);
    assert.equal(persistence.auditTickets[0].candidateUid, 'worker_ambiguous');
    assert.equal(persistence.auditTickets[0].matchedUid, 'worker_alice');
  });

  it('performs 1:1 verification using canonical threshold 0.363', async () => {
    const persistence = new MockBiometricVaultPersistence();
    const kms = new CloudKmsEnvelopeService(new LocalDevKeyProvider());
    const service = new GalleryConsistencyServiceV3(persistence, kms);
    await service.ensureSynchronized();

    const alicePayload = createDummyPayload(1);
    await service.enrollWithGlobalEpochBump({
      uid: 'worker_alice',
      maskedPhone: '+91 ****1111',
      payload: alicePayload,
    });

    // 1:1 verify genuine user
    const verifyResult = await service.verifyWorker1to1('worker_alice', alicePayload);
    assert.equal(verifyResult.verified, true);
    assert.equal(verifyResult.decisionStatus, 'MATCH_CONFIRMED');
    assert.ok(verifyResult.cosineSimilarity !== null && verifyResult.cosineSimilarity >= 0.363);

    // 1:1 verify impostor (orthogonal)
    const impostorPayload = createDummyPayload(50);
    const impostorResult = await service.verifyWorker1to1('worker_alice', impostorPayload);
    assert.equal(impostorResult.verified, false);
    assert.equal(impostorResult.decisionStatus, 'NON_MATCH_REJECTED');
    assert.ok(impostorResult.cosineSimilarity !== null && impostorResult.cosineSimilarity < 0.363);
  });

  it('enforces DPDPA §12 Right to Erasure by purging vault document and swapping CoW RAM arena', async () => {
    const persistence = new MockBiometricVaultPersistence();
    const kms = new CloudKmsEnvelopeService(new LocalDevKeyProvider());
    const service = new GalleryConsistencyServiceV3(persistence, kms);
    await service.ensureSynchronized();

    await service.enrollWithGlobalEpochBump({
      uid: 'worker_alice',
      maskedPhone: '+91 ****1111',
      payload: createDummyPayload(1),
    });
    assert.equal(service.getActiveGallerySize(), 1);

    const erased = await service.eraseWorkerBiometrics('worker_alice');
    assert.equal(erased.erased, true);
    assert.equal(service.getActiveGallerySize(), 0);
    assert.equal(persistence.docs.has('worker_alice'), false);

    // Non-existent user returns false
    const erasedAgain = await service.eraseWorkerBiometrics('worker_alice');
    assert.equal(erasedAgain.erased, false);
  });
});
