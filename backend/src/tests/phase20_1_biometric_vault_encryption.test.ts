// File: backend/src/tests/phase20_1_biometric_vault_encryption.test.ts
import { describe, it } from 'node:test';
import * as assert from 'node:assert';
import * as crypto from 'node:crypto';
import * as admin from 'firebase-admin';
import {
  BiometricTemplateCryptoService,
  BiometricCryptoError,
  BIOMETRIC_VAULT_SCHEMA_VERSION,
  CANONICAL_CIPHER_ALGORITHM,
  CANONICAL_ENCODING_FORMAT,
} from '../services/biometric_template_crypto';
import {
  LocalDevKeyProvider,
  KmsKeyProvider,
  SFACE_EMBEDDING_DIMENSION,
} from '../crypto/cloud_kms_envelope';
import {
  BiometricLifecycleCoordinatorV10,
  CompatibleGalleryIndex,
  GalleryCandidateHit,
} from '../services/biometric_lifecycle_coordinator_v10';
import { FirestoreCompatibleGalleryIndex } from '../services/firestore_compatible_gallery_index';
import { BiometricOperationReceiptService } from '../biometrics/identity_contract_v10';
import { BiometricVaultV2Migrator } from '../scripts/migrate_biometric_vault_v1_to_v2';

/**
 * Creates a synthetic unit-normalized 128-D Float32Array from a numeric seed.
 */
function createSyntheticEmbedding(seed: number): Float32Array {
  const vec = new Float32Array(128);
  let normSq = 0.0;
  for (let i = 0; i < 128; i++) {
    const val = Math.sin(seed * 997 + i * 13) * Math.cos(seed * 31 + i);
    vec[i] = val;
    normSq += val * val;
  }
  const norm = Math.sqrt(normSq);
  for (let i = 0; i < 128; i++) {
    vec[i] /= norm;
  }
  return vec;
}

/**
 * In-memory Mock Firestore implementation for isolated lifecycle unit testing.
 */
class MockFirestoreForCrypto {
  public store = new Map<string, any>();

  collection(name: string) {
    const self = this;
    return {
      doc(id: string) {
        const docPath = `${name}/${id}`;
        return {
          id,
          path: docPath,
          async get() {
            const data = self.store.get(docPath);
            return {
              id,
              exists: data !== undefined,
              data: () => (data ? JSON.parse(JSON.stringify(data)) : undefined),
            };
          },
          async set(data: any, options?: { merge?: boolean }) {
            if (options?.merge && self.store.has(docPath)) {
              const existing = self.store.get(docPath);
              self.store.set(docPath, { ...existing, ...JSON.parse(JSON.stringify(data)) });
            } else {
              self.store.set(docPath, JSON.parse(JSON.stringify(data)));
            }
          },
          async update(data: any) {
            const existing = self.store.get(docPath) ? { ...self.store.get(docPath) } : {};
            for (const [k, v] of Object.entries(data)) {
              if (
                v === admin.firestore.FieldValue.delete() ||
                (v && typeof v === 'object' && ('_methodName' in (v as any) || (v as any).constructor?.name === 'DeleteTransform' || Object.keys(v).length === 0))
              ) {
                delete existing[k];
              } else {
                existing[k] = JSON.parse(JSON.stringify(v));
              }
            }
            self.store.set(docPath, existing);
          },
          async delete() {
            self.store.delete(docPath);
          },
        };
      },
      where(field: string, op: string, value: any) {
        return {
          async get() {
            const docs: any[] = [];
            for (const [key, val] of self.store.entries()) {
              if (key.startsWith(`${name}/`)) {
                if (op === '==' && val[field] === value) {
                  docs.push({
                    id: key.split('/')[1],
                    data: () => JSON.parse(JSON.stringify(val)),
                  });
                }
              }
            }
            return { docs, empty: docs.length === 0, size: docs.length };
          },
        };
      },
      orderBy(_field: any) {
        return {
          limit(_n: number) {
            return {
              async get() {
                const docs: any[] = [];
                for (const [key, val] of self.store.entries()) {
                  if (key.startsWith(`${name}/`)) {
                    docs.push({
                      id: key.split('/')[1],
                      data: () => JSON.parse(JSON.stringify(val)),
                    });
                  }
                }
                return { docs, empty: docs.length === 0, size: docs.length };
              },
            };
          },
        };
      },
      async get() {
        const docs: any[] = [];
        for (const [key, val] of self.store.entries()) {
          if (key.startsWith(`${name}/`)) {
            docs.push({
              id: key.split('/')[1],
              data: () => JSON.parse(JSON.stringify(val)),
            });
          }
        }
        return { docs, empty: docs.length === 0, size: docs.length };
      },
    };
  }

  async runTransaction<T>(updateFunction: (tx: any) => Promise<T>): Promise<T> {
    const tx = {
      get: async (ref: any) => ref.get(),
      set: async (ref: any, data: any, options?: any) => ref.set(data, options),
      update: async (ref: any, data: any) => ref.update(data),
      delete: async (ref: any) => ref.delete(),
    };
    return updateFunction(tx);
  }

  batch() {
    const operations: Array<() => Promise<void>> = [];
    return {
      set: (ref: any, data: any, options?: any) => {
        operations.push(() => ref.set(data, options));
      },
      update: (ref: any, data: any) => {
        operations.push(() => ref.update(data));
      },
      delete: (ref: any) => {
        operations.push(() => ref.delete());
      },
      commit: async () => {
        for (const op of operations) await op();
      },
    };
  }
}

describe('Phase 20.1: Zero-Plaintext Biometric Vault & KMS Envelope Tests', () => {
  const localKms = new LocalDevKeyProvider();
  const cryptoService = new BiometricTemplateCryptoService(localKms, 'kelasagara-test');

  // ───────────────────────────────────────────────────────────────────────────
  // 1. Encryption Correctness & Numerical Round Trip
  // ───────────────────────────────────────────────────────────────────────────
  describe('1. Encryption Correctness', () => {
    it('encrypts 128-D embedding into versioned AES-256-GCM envelope', async () => {
      const originalVec = createSyntheticEmbedding(42);
      const pkg = await cryptoService.encryptTemplate({
        templateId: 'enr_test_001',
        ownerUid: 'usr_alice_001',
        embedding128: originalVec,
      });

      assert.strictEqual(pkg.schemaVersion, BIOMETRIC_VAULT_SCHEMA_VERSION);
      assert.strictEqual(pkg.biometricEnvelope.algorithm, CANONICAL_CIPHER_ALGORITHM);
      assert.strictEqual(pkg.biometricEnvelope.encoding, CANONICAL_ENCODING_FORMAT);
      assert.strictEqual(pkg.biometricEnvelope.envelopeVersion, 2);
      assert.ok(pkg.biometricEnvelope.ciphertextBase64.length > 0);
      assert.ok(pkg.biometricEnvelope.wrappedDekBase64.length > 0);
      assert.ok(pkg.biometricEnvelope.ivBase64.length > 0);
      assert.ok(pkg.biometricEnvelope.authTagBase64.length > 0);
      assert.strictEqual(pkg.metadata.dimensions, SFACE_EMBEDDING_DIMENSION);
    });

    it('performs exact lossless numerical round-trip decryption', async () => {
      const originalVec = createSyntheticEmbedding(99);
      const pkg = await cryptoService.encryptTemplate({
        templateId: 'enr_test_002',
        ownerUid: 'usr_bob_002',
        embedding128: originalVec,
      });

      const decryptedVec = await cryptoService.decryptTemplate({
        templateId: 'enr_test_002',
        ownerUid: 'usr_bob_002',
        envelope: pkg.biometricEnvelope,
      });

      assert.strictEqual(decryptedVec.length, 128);
      for (let i = 0; i < 128; i++) {
        // Exact 32-bit floating point precision match
        assert.strictEqual(decryptedVec[i], originalVec[i]);
      }
    });

    it('verifies unit L2 norm is preserved on decrypted vector', async () => {
      const originalVec = createSyntheticEmbedding(123);
      const pkg = await cryptoService.encryptTemplate({
        templateId: 'enr_test_003',
        ownerUid: 'usr_carol_003',
        embedding128: originalVec,
      });

      const decryptedVec = await cryptoService.decryptTemplate({
        templateId: 'enr_test_003',
        ownerUid: 'usr_carol_003',
        envelope: pkg.biometricEnvelope,
      });

      let normSq = 0.0;
      for (let i = 0; i < 128; i++) normSq += decryptedVec[i] * decryptedVec[i];
      const norm = Math.sqrt(normSq);
      assert.ok(Math.abs(norm - 1.0) < 1e-5, `Decrypted norm ${norm} must be 1.0`);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 2. Tampering Resistance (AAD & Cryptographic Integrity)
  // ───────────────────────────────────────────────────────────────────────────
  describe('2. Tampering Resistance', () => {
    it('rejects envelope if ciphertext bits are modified (INV-01)', async () => {
      const originalVec = createSyntheticEmbedding(1);
      const pkg = await cryptoService.encryptTemplate({
        templateId: 'enr_tamper_01',
        ownerUid: 'usr_tamper_01',
        embedding128: originalVec,
      });

      const rawCiphertext = Buffer.from(pkg.biometricEnvelope.ciphertextBase64, 'base64');
      rawCiphertext[10] ^= 0x55; // Flip bit
      const tamperedEnvelope = {
        ...pkg.biometricEnvelope,
        ciphertextBase64: rawCiphertext.toString('base64'),
      };

      await assert.rejects(
        async () => {
          await cryptoService.decryptTemplate({
            templateId: 'enr_tamper_01',
            ownerUid: 'usr_tamper_01',
            envelope: tamperedEnvelope,
          });
        },
        (err: any) => {
          assert.ok(
            err.code === 'AUTHENTICATION_TAG_VERIFICATION_FAILED' ||
            err.code === 'KMS_UNWRAPKEY_FAILURE',
            `Expected tag verification failure or KMS unwrap failure on AAD mismatch, got ${err.code}`
          );
          return true;
        }
      );
    });

    it('rejects envelope if IV is modified', async () => {
      const originalVec = createSyntheticEmbedding(2);
      const pkg = await cryptoService.encryptTemplate({
        templateId: 'enr_tamper_02',
        ownerUid: 'usr_tamper_02',
        embedding128: originalVec,
      });

      const rawIv = Buffer.from(pkg.biometricEnvelope.ivBase64, 'base64');
      rawIv[0] ^= 0xff;
      const tamperedEnvelope = {
        ...pkg.biometricEnvelope,
        ivBase64: rawIv.toString('base64'),
      };

      await assert.rejects(
        async () => {
          await cryptoService.decryptTemplate({
            templateId: 'enr_tamper_02',
            ownerUid: 'usr_tamper_02',
            envelope: tamperedEnvelope,
          });
        },
        (err: any) => {
          assert.ok(
            err.code === 'AUTHENTICATION_TAG_VERIFICATION_FAILED' ||
            err.code === 'KMS_UNWRAPKEY_FAILURE',
            `Expected tag verification failure or KMS unwrap failure on AAD mismatch, got ${err.code}`
          );
          return true;
        }
      );
    });

    it('rejects envelope if authentication tag is modified', async () => {
      const originalVec = createSyntheticEmbedding(3);
      const pkg = await cryptoService.encryptTemplate({
        templateId: 'enr_tamper_03',
        ownerUid: 'usr_tamper_03',
        embedding128: originalVec,
      });

      const rawTag = Buffer.from(pkg.biometricEnvelope.authTagBase64, 'base64');
      rawTag[0] ^= 0x01;
      const tamperedEnvelope = {
        ...pkg.biometricEnvelope,
        authTagBase64: rawTag.toString('base64'),
      };

      await assert.rejects(
        async () => {
          await cryptoService.decryptTemplate({
            templateId: 'enr_tamper_03',
            ownerUid: 'usr_tamper_03',
            envelope: tamperedEnvelope,
          });
        },
        (err: any) => {
          assert.ok(
            err.code === 'AUTHENTICATION_TAG_VERIFICATION_FAILED' ||
            err.code === 'KMS_UNWRAPKEY_FAILURE',
            `Expected tag verification failure or KMS unwrap failure on AAD mismatch, got ${err.code}`
          );
          return true;
        }
      );
    });

    it('Context Binding (INV-02): rejects decryption if ownerUid context is changed (cross-user theft)', async () => {
      const originalVec = createSyntheticEmbedding(4);
      const pkg = await cryptoService.encryptTemplate({
        templateId: 'enr_tamper_04',
        ownerUid: 'usr_alice_legit',
        embedding128: originalVec,
      });

      // Attacker copies Alice's envelope into Bob's profile
      await assert.rejects(
        async () => {
          await cryptoService.decryptTemplate({
            templateId: 'enr_tamper_04',
            ownerUid: 'usr_bob_impostor', // Mismatched owner in AAD!
            envelope: pkg.biometricEnvelope,
          });
        },
        (err: any) => {
          assert.ok(
            err.code === 'AUTHENTICATION_TAG_VERIFICATION_FAILED' ||
            err.code === 'KMS_UNWRAPKEY_FAILURE',
            `Expected tag verification failure or KMS unwrap failure on AAD mismatch, got ${err.code}`
          );
          return true;
        }
      );
    });

    it('Context Binding: rejects decryption if templateId context is changed', async () => {
      const originalVec = createSyntheticEmbedding(5);
      const pkg = await cryptoService.encryptTemplate({
        templateId: 'enr_template_A',
        ownerUid: 'usr_same_owner',
        embedding128: originalVec,
      });

      await assert.rejects(
        async () => {
          await cryptoService.decryptTemplate({
            templateId: 'enr_template_B', // Wrong template ID!
            ownerUid: 'usr_same_owner',
            envelope: pkg.biometricEnvelope,
          });
        },
        (err: any) => {
          assert.ok(
            err.code === 'AUTHENTICATION_TAG_VERIFICATION_FAILED' ||
            err.code === 'KMS_UNWRAPKEY_FAILURE',
            `Expected tag verification failure or KMS unwrap failure on AAD mismatch, got ${err.code}`
          );
          return true;
        }
      );
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 3. Key Management Fail-Closed & Rotation Compatibility
  // ───────────────────────────────────────────────────────────────────────────
  describe('3. Key Management Failures & Rotation', () => {
    it('fails closed when KMS throws network timeout or unavailable', async () => {
      const failingKms: KmsKeyProvider = {
        async wrapKey() {
          throw new Error('503 Service Unavailable: KMS backend timeout');
        },
        async unwrapKey() {
          throw new Error('503 Service Unavailable: KMS backend timeout');
        },
      };

      const failingCrypto = new BiometricTemplateCryptoService(failingKms);
      const vec = createSyntheticEmbedding(10);

      await assert.rejects(
        async () => {
          await failingCrypto.encryptTemplate({
            templateId: 'enr_fail_01',
            ownerUid: 'usr_fail_01',
            embedding128: vec,
          });
        },
        (err: any) => {
          assert.strictEqual(err.code, 'KMS_WRAPKEY_FAILURE');
          assert.strictEqual(err.retryable, true);
          return true;
        }
      );
    });

    it('supports decrypting templates encrypted under older key versions', async () => {
      const olderKms = new LocalDevKeyProvider(
        '4b656c61736167616172614465764d61737465724b65795f323032365f48534d',
        'projects/kelasagaara-dev/locations/asia-south1/keyRings/ring/cryptoKeys/kek/cryptoKeyVersions/1'
      );
      const olderCrypto = new BiometricTemplateCryptoService(olderKms);
      const vec = createSyntheticEmbedding(20);

      const pkg = await olderCrypto.encryptTemplate({
        templateId: 'enr_rot_01',
        ownerUid: 'usr_rot_01',
        embedding128: vec,
      });

      assert.strictEqual(
        pkg.biometricEnvelope.kmsKeyVersion,
        'projects/kelasagaara-dev/locations/asia-south1/keyRings/ring/cryptoKeys/kek/cryptoKeyVersions/1'
      );

      const decrypted = await olderCrypto.decryptTemplate({
        templateId: 'enr_rot_01',
        ownerUid: 'usr_rot_01',
        envelope: pkg.biometricEnvelope,
      });

      assert.strictEqual(decrypted.length, 128);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 4. Biometric Lifecycle Integration Tests
  // ───────────────────────────────────────────────────────────────────────────
  describe('4. Biometric Lifecycle Integration', () => {
    it('persists zero-plaintext encrypted envelope into biometric_vault on clean enrollment', async () => {
      const mockDb = new MockFirestoreForCrypto();
      const galleryIndex = new FirestoreCompatibleGalleryIndex(mockDb as any, cryptoService);
      const receiptService = new BiometricOperationReceiptService(Buffer.alloc(32, 1));
      const coordinator = new BiometricLifecycleCoordinatorV10(
        mockDb as any,
        galleryIndex,
        receiptService,
        undefined,
        cryptoService
      );

      const uid = 'usr_worker_encrypted_01';
      // Seed pre-existing user profile
      mockDb.store.set(`users/${uid}`, {
        uid,
        accountStatus: 'pending_face',
        biometricStatus: 'UNENROLLED',
      });
      mockDb.store.set('biometric_system_meta/gallery_epoch_v10', { epochVersion: 5 });

      const vector = createSyntheticEmbedding(101);
      const res = await coordinator.enrollInitial({
        authenticatedUid: uid,
        idempotencyKey: 'idem_enc_01',
        challengeNonce: 'nonce_enc_01',
        validatedSFaceEmbedding128: vector,
      });

      assert.strictEqual(res.httpStatus, 200);
      assert.strictEqual(res.code, 'NO_MATCH');
      assert.strictEqual(res.biometricStatus, 'ACTIVE');

      // VERIFY FIRESTORE VAULT DOCUMENT
      const vaultKey = `biometric_vault/${res.enrollmentId}`;
      const vaultDoc = mockDb.store.get(vaultKey);
      assert.ok(vaultDoc, 'Vault document must exist');
      assert.strictEqual(vaultDoc.schemaVersion, 2);
      assert.ok(vaultDoc.biometricEnvelope, 'biometricEnvelope must be present');

      // STRICT ZERO-PLAINTEXT VERIFICATION:
      assert.strictEqual(vaultDoc.canonicalEmbedding, undefined, 'canonicalEmbedding must NOT be persisted');
      assert.strictEqual(vaultDoc.sfaceEmbedding128, undefined, 'sfaceEmbedding128 must NOT be persisted');
      assert.strictEqual(vaultDoc.embedding, undefined, 'embedding must NOT be persisted');
    });

    it('fails closed and restores user state if KMS encryption fails during enrollment', async () => {
      const mockDb = new MockFirestoreForCrypto();
      const galleryIndex = new FirestoreCompatibleGalleryIndex(mockDb as any, cryptoService);
      const receiptService = new BiometricOperationReceiptService(Buffer.alloc(32, 2));

      // Failing crypto provider
      const failingKms: KmsKeyProvider = {
        async wrapKey() {
          throw new Error('KMS Down');
        },
        async unwrapKey() {
          throw new Error('KMS Down');
        },
      };
      const failingCrypto = new BiometricTemplateCryptoService(failingKms);

      const coordinator = new BiometricLifecycleCoordinatorV10(
        mockDb as any,
        galleryIndex,
        receiptService,
        undefined,
        failingCrypto
      );

      const uid = 'usr_worker_fail_02';
      mockDb.store.set(`users/${uid}`, {
        uid,
        accountStatus: 'pending_face',
        biometricStatus: 'UNENROLLED',
      });
      mockDb.store.set('biometric_system_meta/gallery_epoch_v10', { epochVersion: 10 });

      const vector = createSyntheticEmbedding(102);
      const res = await coordinator.enrollInitial({
        authenticatedUid: uid,
        idempotencyKey: 'idem_fail_02',
        challengeNonce: 'nonce_fail_02',
        validatedSFaceEmbedding128: vector,
      });

      assert.strictEqual(res.httpStatus, 503);
      assert.strictEqual(res.code, 'KMS_UNAVAILABLE');

      // Invariant: Epoch must NOT have incremented
      const epochDoc = mockDb.store.get('biometric_system_meta/gallery_epoch_v10');
      assert.strictEqual(epochDoc.epochVersion, 10);

      // Invariant: User must remain UNENROLLED and NOT faceVerified
      const userDoc = mockDb.store.get(`users/${uid}`);
      assert.strictEqual(userDoc.biometricStatus, 'UNENROLLED');
      assert.strictEqual(userDoc.faceVerified, undefined);
    });

    it('gallery reconstructs encrypted templates and intercepts duplicate face with HTTP 409', async () => {
      const mockDb = new MockFirestoreForCrypto();
      const galleryIndex = new FirestoreCompatibleGalleryIndex(mockDb as any, cryptoService);
      const receiptService = new BiometricOperationReceiptService(Buffer.alloc(32, 3));
      const coordinator = new BiometricLifecycleCoordinatorV10(
        mockDb as any,
        galleryIndex,
        receiptService,
        undefined,
        cryptoService
      );

      // 1. Enroll Alice with encrypted template
      const aliceUid = 'usr_alice_orig';
      mockDb.store.set(`users/${aliceUid}`, {
        uid: aliceUid,
        accountStatus: 'pending_face',
        biometricStatus: 'UNENROLLED',
      });
      mockDb.store.set('biometric_system_meta/gallery_epoch_v10', { epochVersion: 1 });

      const aliceVec = createSyntheticEmbedding(777);
      const enrollRes = await coordinator.enrollInitial({
        authenticatedUid: aliceUid,
        idempotencyKey: 'idem_alice_01',
        challengeNonce: 'nonce_alice_01',
        validatedSFaceEmbedding128: aliceVec,
      });
      assert.strictEqual(enrollRes.httpStatus, 200);

      // 2. Imposter Bob attempts enrollment with Alice's face
      const bobUid = 'usr_bob_sybil';
      mockDb.store.set(`users/${bobUid}`, {
        uid: bobUid,
        accountStatus: 'pending_face',
        biometricStatus: 'UNENROLLED',
      });

      // Slightly perturbed probe vector (simulating fresh camera frame)
      const bobProbe = new Float32Array(128);
      for (let i = 0; i < 128; i++) {
        bobProbe[i] = aliceVec[i] + (Math.random() - 0.5) * 0.005;
      }
      let normSq = 0;
      for (let i = 0; i < 128; i++) normSq += bobProbe[i] * bobProbe[i];
      const norm = Math.sqrt(normSq);
      for (let i = 0; i < 128; i++) bobProbe[i] /= norm;

      const dupRes = await coordinator.enrollInitial({
        authenticatedUid: bobUid,
        idempotencyKey: 'idem_bob_dup',
        challengeNonce: 'nonce_bob_dup',
        validatedSFaceEmbedding128: bobProbe,
      });

      assert.strictEqual(dupRes.httpStatus, 409);
      assert.strictEqual(dupRes.code, 'FACE_ALREADY_LINKED');
      assert.ok(dupRes.caseReference?.startsWith('CASE-'));
    });

    it('executes 1:1 authentication by decrypting only the claimed user enrolled template', async () => {
      const mockDb = new MockFirestoreForCrypto();
      const galleryIndex = new FirestoreCompatibleGalleryIndex(mockDb as any, cryptoService);
      const receiptService = new BiometricOperationReceiptService(Buffer.alloc(32, 4));
      const coordinator = new BiometricLifecycleCoordinatorV10(
        mockDb as any,
        galleryIndex,
        receiptService,
        undefined,
        cryptoService
      );

      const uid = 'usr_1to1_worker';
      mockDb.store.set(`users/${uid}`, {
        uid,
        accountStatus: 'approved',
        biometricStatus: 'UNENROLLED',
      });
      mockDb.store.set('biometric_system_meta/gallery_epoch_v10', { epochVersion: 20 });

      const vec = createSyntheticEmbedding(555);
      const enrollRes = await coordinator.enrollInitial({
        authenticatedUid: uid,
        idempotencyKey: 'idem_1to1_enr',
        challengeNonce: 'nonce_1to1_enr',
        validatedSFaceEmbedding128: vec,
      });

      // Authenticate with identical face
      const authRes = await coordinator.verifyExistingAccount1to1({
        authenticatedUid: uid,
        challengeNonce: 'nonce_verify_1',
        validatedSFaceEmbedding128: vec,
      });

      assert.strictEqual(authRes.httpStatus, 200);
      assert.strictEqual(authRes.code, 'VERIFIED_1TO1');

      // Negative test: Authenticate with stranger face
      const strangerVec = createSyntheticEmbedding(999);
      const strangerRes = await coordinator.verifyExistingAccount1to1({
        authenticatedUid: uid,
        challengeNonce: 'nonce_verify_2',
        validatedSFaceEmbedding128: strangerVec,
      });

      assert.strictEqual(strangerRes.httpStatus, 403);
      assert.strictEqual(strangerRes.code, 'GENUINE_USER_MISMATCH');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 5. Migration Utility Tests (Synthetic Records)
  // ───────────────────────────────────────────────────────────────────────────
  describe('5. Vault Migration Utility', () => {
    it('discovers, dry-runs, and migrates synthetic plaintext records to encrypted V2', async () => {
      const mockDb = new MockFirestoreForCrypto();
      const migrator = new BiometricVaultV2Migrator(
        mockDb as any,
        cryptoService,
        'biometric_vault'
      );

      // Seed 3 legacy plaintext templates
      for (let i = 1; i <= 3; i++) {
        const id = `legacy_enr_${i}`;
        const vec = Array.from(createSyntheticEmbedding(i * 10));
        mockDb.store.set(`biometric_vault/${id}`, {
          enrollmentId: id,
          owningUid: `usr_legacy_${i}`,
          canonicalEmbedding: vec,
          sfaceEmbedding128: vec,
          status: 'ACTIVE',
        });
      }

      // Stage A: Discovery
      const discovery = await migrator.runDiscovery();
      assert.strictEqual(discovery.totalRecords, 3);
      assert.strictEqual(discovery.legacyPlaintextCount, 3);
      assert.strictEqual(discovery.alreadyEncryptedCount, 0);

      // Stage B: Dry-run
      const dryRun = await migrator.runDryRun();
      assert.strictEqual(dryRun.validCount, 3);
      assert.strictEqual(dryRun.invalidCount, 0);

      // Stage D: Migration
      const migration = await migrator.runMigration({ batchSize: 10, maxConcurrency: 2 });
      assert.strictEqual(migration.recordsMigrated, 3);
      assert.strictEqual(migration.recordsFailed, 0);

      // Stage E: Verification
      const verification = await migrator.runVerification();
      assert.strictEqual(verification.verifiedCount, 3);
      assert.strictEqual(verification.failedCount, 0);

      // Verify that plaintext arrays were deleted from database
      for (let i = 1; i <= 3; i++) {
        const doc = mockDb.store.get(`biometric_vault/legacy_enr_${i}`);
        assert.strictEqual(doc.schemaVersion, 2);
        assert.ok(doc.biometricEnvelope);
        assert.strictEqual(doc.canonicalEmbedding, undefined);
        assert.strictEqual(doc.sfaceEmbedding128, undefined);
      }

      // Idempotency test: Re-running migration migrates 0 additional records
      const rerun = await migrator.runMigration();
      assert.strictEqual(rerun.recordsMigrated, 0);
    });
  });
});
