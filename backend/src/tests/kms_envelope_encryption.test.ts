// backend/src/tests/kms_envelope_encryption.test.ts
import { describe, it } from 'node:test';
import assert from 'node:assert';
import { BiometricEnvelopeEncryptionService } from '../services/kms_envelope_encryption';
import { LocalDevKeyProvider } from '../services/kms_key_provider';

describe('BiometricEnvelopeEncryptionService (Gate G-04 / Gate G-05)', () => {
  const localProvider = new LocalDevKeyProvider({
    keyVersion: 'local_k1',
    keyResourceName: 'projects/test/locations/global/keyRings/test-ring/cryptoKeys/test-kek',
  });

  const service = new BiometricEnvelopeEncryptionService(localProvider);

  it('successfully encrypts and decrypts a 128-D biometric embedding vector', async () => {
    const uid = 'test_worker_12345';
    const originalEmbedding = new Float32Array(128);
    for (let i = 0; i < 128; i++) {
      originalEmbedding[i] = Math.sin(i) * 0.5;
    }

    const envelope = await service.encryptTemplate(uid, originalEmbedding);

    assert.strictEqual(envelope.version, 'v16_kms_gcm');
    assert.strictEqual(envelope.uid, uid);
    assert.ok(envelope.ciphertextBase64.length > 0);
    assert.ok(envelope.wrappedDekBase64.length > 0);
    assert.ok(envelope.authTagBase64.length > 0);
    assert.ok(envelope.ivBase64.length > 0);

    const decrypted = await service.decryptTemplate(envelope);
    assert.strictEqual(decrypted.length, 128);

    for (let i = 0; i < 128; i++) {
      assert.ok(
        Math.abs(decrypted[i] - originalEmbedding[i]) < 1e-6,
        `Index ${i} mismatch: ${decrypted[i]} vs ${originalEmbedding[i]}`
      );
    }
  });

  it('rejects decryption fail-closed if UID context in envelope is tampered (INV-02)', async () => {
    const uid = 'test_worker_tamper';
    const original = new Float32Array([0.1, 0.2, 0.3, 0.4]);
    const envelope = await service.encryptTemplate(uid, original);

    // Attacker modifies UID
    const tamperedEnvelope = { ...envelope, uid: 'attacker_uid_stolen' };

    await assert.rejects(
      async () => {
        await service.decryptTemplate(tamperedEnvelope);
      },
      (err: any) => {
        return err.message.includes('DEK_UNWRAP_FAILED') || err.message.includes('DECRYPTION_FAILED');
      }
    );
  });

  it('rejects decryption fail-closed if ciphertext or auth tag is corrupted (INV-01)', async () => {
    const uid = 'test_worker_corrupt';
    const original = new Float32Array([0.5, 0.6, 0.7]);
    const envelope = await service.encryptTemplate(uid, original);

    // Flip byte in ciphertext
    const rawCipher = Buffer.from(envelope.ciphertextBase64, 'base64');
    rawCipher[0] ^= 0xff;
    const corruptedEnvelope = { ...envelope, ciphertextBase64: rawCipher.toString('base64') };

    await assert.rejects(
      async () => {
        await service.decryptTemplate(corruptedEnvelope);
      },
      (err: any) => {
        return err.message.includes('DECRYPTION_FAILED');
      }
    );
  });

  it('successfully re-wraps DEK to a new key version without re-encrypting ciphertext', async () => {
    const uid = 'test_worker_rotation';
    const original = new Float32Array(128).fill(0.42);
    const envelope = await service.encryptTemplate(uid, original);

    const newProvider = new LocalDevKeyProvider({
      keyVersion: 'local_k2_rotated',
      keyResourceName: 'projects/test/locations/global/keyRings/test-ring/cryptoKeys/test-kek-v2',
    });

    const rotatedEnvelope = await service.rewrapTemplateDek(envelope, newProvider);

    // Ciphertext and IV must remain identical
    assert.strictEqual(rotatedEnvelope.ciphertextBase64, envelope.ciphertextBase64);
    assert.strictEqual(rotatedEnvelope.ivBase64, envelope.ivBase64);
    assert.strictEqual(rotatedEnvelope.authTagBase64, envelope.authTagBase64);

    // Key metadata must reflect the new version
    assert.strictEqual(rotatedEnvelope.keyVersion, 'local_k2_rotated');
    assert.strictEqual(rotatedEnvelope.kmsKeyResourceName, 'projects/test/locations/global/keyRings/test-ring/cryptoKeys/test-kek-v2');

    // Decrypting with new provider succeeds
    const rotatedService = new BiometricEnvelopeEncryptionService(newProvider);
    const decryptedRotated = await rotatedService.decryptTemplate(rotatedEnvelope);
    assert.strictEqual(decryptedRotated.length, 128);
    assert.ok(Math.abs(decryptedRotated[0] - 0.42) < 1e-6);
  });

  it('enforces production environment guard against LocalDevKeyProvider', () => {
    const prevEnv = process.env.NODE_ENV;
    const prevBypass = process.env.ALLOW_LOCAL_DEV_KMS_IN_NON_PROD;
    try {
      process.env.NODE_ENV = 'production';
      delete process.env.ALLOW_LOCAL_DEV_KMS_IN_NON_PROD;

      assert.throws(
        () => {
          new BiometricEnvelopeEncryptionService(localProvider);
        },
        (err: any) => {
          return err.message.includes('KMS_ENVIRONMENT_SECURITY_ERROR');
        }
      );
    } finally {
      process.env.NODE_ENV = prevEnv;
      if (prevBypass !== undefined) {
        process.env.ALLOW_LOCAL_DEV_KMS_IN_NON_PROD = prevBypass;
      }
    }
  });
});
