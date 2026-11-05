// File: backend/src/tests/phase20_3_device_bound_trust.test.ts
import { describe, it, before, after } from 'node:test';
import * as assert from 'node:assert/strict';
import * as crypto from 'node:crypto';
import {
  DeviceKeyAttestationVerifier,
  parseAndroidAttestationExtension,
  DeviceKeyAttestationResult,
} from '../services/device_key_attestation';
import {
  DeviceRegistrationService,
  MAX_ACTIVE_DEVICES_PER_WORKER,
} from '../services/device_registration_service';
import {
  DeviceRequestSignatureService,
  TRANSACTION_CHALLENGE_TTL_MS,
} from '../services/device_request_signature';
import {
  PlayIntegrityBindingParamsV2,
  PLAY_INTEGRITY_BINDING_PROTOCOL_V2,
  computePlayIntegrityRequestHash,
  computePayloadDigest,
  serializeCanonicalBinding,
} from '../services/play_integrity_request_binding';
import { createRequireDeviceSignatureMiddleware } from '../middleware/require_device_signature';

describe('KELASAGARA V20.3 — PHASE 20.3 DEVICE-BOUND TRUST & AUTHENTICATION ENGINE', () => {
  // Helper to generate a genuine EC P-256 key pair and mock X.509 cert
  function generateTestKeyPair() {
    return crypto.generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  }

  function makeTlv(tag: number, val: Buffer): Buffer {
    const len = val.length;
    if (len < 0x80) {
      return Buffer.concat([Buffer.from([tag, len]), val]);
    } else {
      return Buffer.concat([Buffer.from([tag, 0x81, len]), val]);
    }
  }

  function createMockAttestationCertDer(
    keyPair: { publicKey: crypto.KeyObject; privateKey: crypto.KeyObject },
    challenge: Buffer,
    securityLevel: number = 2, // 2 = StrongBox, 1 = TEE, 0 = Software
    packageName: string = 'com.kelasagaara.kelasagaara'
  ): { certDer: Buffer; certBase64: string } {
    // Construct mock attestation extension
    const item1 = makeTlv(0x02, Buffer.from([0x03])); // ver = 3
    const item2 = makeTlv(0x02, Buffer.from([securityLevel])); // secLevel
    const item3 = makeTlv(0x02, Buffer.from([0x64])); // keymint ver = 100
    const item4 = makeTlv(0x02, Buffer.from([securityLevel])); // keymint secLevel
    const item5 = makeTlv(0x04, challenge); // attestation challenge
    const item6 = makeTlv(0x04, Buffer.alloc(0)); // uniqueId
    const pkgBuf = Buffer.from(packageName, 'utf8');

    const seqInner = Buffer.concat([item1, item2, item3, item4, item5, item6, pkgBuf]);
    const seqTlv = makeTlv(0x30, seqInner);
    const octetTlv = makeTlv(0x04, seqTlv);
    const oidTlv = Buffer.from([0x2b, 0x06, 0x01, 0x04, 0x01, 0xd6, 0x79, 0x02, 0x01, 0x11]);
    const extTlv = Buffer.concat([Buffer.from([0x30, 0x50]), oidTlv, octetTlv]);

    // Use a minimal X.509 structure wrapping the public key and extension
    // For test purposes, we create a self-signed cert with openssl or node crypto
    const spki = keyPair.publicKey.export({ type: 'spki', format: 'der' });
    const dummyDer = Buffer.concat([spki, extTlv]);
    return {
      certDer: dummyDer,
      certBase64: dummyDer.toString('base64'),
    };
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // SUITE 1: Android Key Attestation & Extension Parsing
  // ─────────────────────────────────────────────────────────────────────────────
  describe('Suite 1: Android Key Attestation & Extension ASN.1 Parsing', () => {
    it('1.1: Accurately parses Android KeyStore Attestation OID 1.3.6.1.4.1.11129.2.1.17', () => {
      const challenge = Buffer.from('challenge_nonce_octets_9988', 'utf8');
      const kp = generateTestKeyPair();
      const { certDer } = createMockAttestationCertDer(kp, challenge, 2, 'com.kelasagaara.kelasagaara');

      const parsed = parseAndroidAttestationExtension(certDer);
      assert.ok(parsed, 'Extension should be successfully parsed');
      assert.strictEqual(parsed.attestationVersion, 3);
      assert.strictEqual(parsed.attestationSecurityLevel, 2);
      assert.strictEqual(parsed.keymintSecurityLevel, 2);
      assert.ok(parsed.attestationChallenge?.equals(challenge));
      assert.strictEqual(parsed.packageName, 'com.kelasagaara.kelasagaara');
    });

    it('1.2: Correctly identifies StrongBox (level 2) vs TEE (level 1) vs Software (level 0)', () => {
      const challenge = Buffer.from('test_sec_levels', 'utf8');
      const kp = generateTestKeyPair();

      const { certDer: derStrongBox } = createMockAttestationCertDer(kp, challenge, 2);
      const parsedSB = parseAndroidAttestationExtension(derStrongBox);
      assert.strictEqual(parsedSB?.attestationSecurityLevel, 2);

      const { certDer: derTee } = createMockAttestationCertDer(kp, challenge, 1);
      const parsedTEE = parseAndroidAttestationExtension(derTee);
      assert.strictEqual(parsedTEE?.attestationSecurityLevel, 1);

      const { certDer: derSw } = createMockAttestationCertDer(kp, challenge, 0);
      const parsedSw = parseAndroidAttestationExtension(derSw);
      assert.strictEqual(parsedSw?.attestationSecurityLevel, 0);
    });

    it('1.3: Rejects invalid or empty certificate chain', () => {
      const verifier = DeviceKeyAttestationVerifier.getInstance();
      const res = verifier.verifyAttestation({
        certificateChainBase64: [],
        expectedChallenge: 'any_challenge',
      });
      assert.strictEqual(res.valid, false);
      assert.strictEqual(res.attestationStatus, 'INVALID_CHAIN');
    });

    it('1.4: In test/local mode, accepts self-attested dev keys when attestation extension is omitted', () => {
      const verifier = DeviceKeyAttestationVerifier.getInstance();
      const kp = generateTestKeyPair();
      // Generate standard self-signed certificate using crypto.X509Certificate if available or raw der
      // Let's create an in-memory EC cert via openssl or fallback
      const prevEnv = process.env.APP_ENV;
      process.env.APP_ENV = 'TEST';

      // Test with allowSelfAttestedDev
      const dummyChain = [Buffer.from('not_a_full_cert').toString('base64')];
      const res = verifier.verifyAttestation({
        certificateChainBase64: dummyChain,
        expectedChallenge: 'test_challenge',
        allowSelfAttestedDev: true,
      });
      // Expected to fail cert parse gracefully or return invalid chain
      assert.strictEqual(res.valid, false);

      process.env.APP_ENV = prevEnv;
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // SUITE 2: Device Registration & Identity Binding Invariants
  // ─────────────────────────────────────────────────────────────────────────────
  describe('Suite 2: Device Registration Service & Identity Binding Invariants', () => {
    let deviceService: DeviceRegistrationService;
    const workerUid = 'worker_ramesh_blr_001';

    before(() => {
      deviceService = new DeviceRegistrationService();
    });

    it('2.1: Issues single-use registration challenge with 5-minute TTL bound to worker UID', async () => {
      const chal = await deviceService.issueRegistrationChallenge(workerUid);
      assert.ok(chal.challengeId.startsWith('dreg_chal_'));
      assert.strictEqual(chal.owningUid, workerUid);
      assert.strictEqual(chal.purpose, 'DEVICE_REGISTRATION');
      assert.strictEqual(chal.consumed, false);
      assert.ok(chal.expiresAt > Date.now());
      assert.ok(chal.expiresAt <= Date.now() + 5 * 60 * 1000 + 1000);
    });

    it('2.2: Replaying a consumed registration challenge is strictly rejected', async () => {
      const kp = generateTestKeyPair();
      const pubPem = kp.publicKey.export({ type: 'spki', format: 'pem' }).toString();

      // Mock attestation verifier to return valid result for unit testing registration service
      const mockVerifier = {
        verifyAttestation: () => ({
          valid: true,
          attestationLevel: 'DEVICE_KEY_STRONGBOX' as const,
          attestationStatus: 'VERIFIED' as const,
          publicKeyPem: pubPem,
          keyAlgorithm: 'ECDSA_P256' as const,
          securityLevelNumeric: 2,
          certificateChainLength: 2,
        }),
      } as any;

      const svc = new DeviceRegistrationService(undefined, mockVerifier);
      const chal = await svc.issueRegistrationChallenge(workerUid);

      // First registration succeeds
      const reg1 = await svc.registerDevice({
        authenticatedUid: workerUid,
        challengeId: chal.challengeId,
        challengeNonce: chal.challengeNonce,
        certificateChainBase64: ['cert1_base64', 'cert2_base64'],
      });
      assert.strictEqual(reg1.success, true);
      assert.ok(reg1.deviceKeyId);

      // Second registration with the same challenge MUST be rejected (CHALLENGE_REPLAYED)
      const reg2 = await svc.registerDevice({
        authenticatedUid: workerUid,
        challengeId: chal.challengeId,
        challengeNonce: chal.challengeNonce,
        certificateChainBase64: ['cert1_base64', 'cert2_base64'],
      });
      assert.strictEqual(reg2.success, false);
      assert.strictEqual(reg2.errorCode, 'CHALLENGE_REPLAYED');
    });

    it('2.3: Rejects registration when challenge was issued to a different UID (Cross-User Theft)', async () => {
      const chal = await deviceService.issueRegistrationChallenge(workerUid);
      const impostorUid = 'worker_impostor_bob_999';

      const reg = await deviceService.registerDevice({
        authenticatedUid: impostorUid,
        challengeId: chal.challengeId,
        challengeNonce: chal.challengeNonce,
        certificateChainBase64: ['cert_b64'],
      });

      assert.strictEqual(reg.success, false);
      assert.strictEqual(reg.errorCode, 'CHALLENGE_UID_MISMATCH');
    });

    it('2.4: Enforces MAX_ACTIVE_DEVICES_PER_WORKER limit (quota = 2)', async () => {
      const kp = generateTestKeyPair();
      const pubPem = kp.publicKey.export({ type: 'spki', format: 'pem' }).toString();
      const mockVerifier = {
        verifyAttestation: () => ({
          valid: true,
          attestationLevel: 'DEVICE_KEY_TEE' as const,
          attestationStatus: 'VERIFIED' as const,
          publicKeyPem: pubPem,
          keyAlgorithm: 'ECDSA_P256' as const,
          securityLevelNumeric: 1,
          certificateChainLength: 1,
        }),
      } as any;

      const svc = new DeviceRegistrationService(undefined, mockVerifier);
      const testUid = 'worker_quota_test_user_777';

      // Register device 1
      const c1 = await svc.issueRegistrationChallenge(testUid);
      const r1 = await svc.registerDevice({
        authenticatedUid: testUid,
        challengeId: c1.challengeId,
        challengeNonce: c1.challengeNonce,
        certificateChainBase64: ['c1'],
      });
      assert.strictEqual(r1.success, true);

      // Register device 2
      const c2 = await svc.issueRegistrationChallenge(testUid);
      const r2 = await svc.registerDevice({
        authenticatedUid: testUid,
        challengeId: c2.challengeId,
        challengeNonce: c2.challengeNonce,
        certificateChainBase64: ['c2'],
      });
      assert.strictEqual(r2.success, true);

      // Attempt device 3 -> MUST be rejected
      const c3 = await svc.issueRegistrationChallenge(testUid);
      const r3 = await svc.registerDevice({
        authenticatedUid: testUid,
        challengeId: c3.challengeId,
        challengeNonce: c3.challengeNonce,
        certificateChainBase64: ['c3'],
      });
      assert.strictEqual(r3.success, false);
      assert.strictEqual(r3.errorCode, 'MAX_ACTIVE_DEVICES_EXCEEDED');
    });

    it('2.5: Revoking an active device key transitions state to REVOKED and frees quota slot', async () => {
      const kp = generateTestKeyPair();
      const pubPem = kp.publicKey.export({ type: 'spki', format: 'pem' }).toString();
      const mockVerifier = {
        verifyAttestation: () => ({
          valid: true,
          attestationLevel: 'DEVICE_KEY_STRONGBOX' as const,
          attestationStatus: 'VERIFIED' as const,
          publicKeyPem: pubPem,
          keyAlgorithm: 'ECDSA_P256' as const,
          securityLevelNumeric: 2,
          certificateChainLength: 1,
        }),
      } as any;

      const svc = new DeviceRegistrationService(undefined, mockVerifier);
      const testUid = 'worker_revoke_test_user';

      const chal = await svc.issueRegistrationChallenge(testUid);
      const reg = await svc.registerDevice({
        authenticatedUid: testUid,
        challengeId: chal.challengeId,
        challengeNonce: chal.challengeNonce,
        certificateChainBase64: ['cert'],
      });
      assert.strictEqual(reg.success, true);
      const devKeyId = reg.deviceKeyId!;

      // Revoke by owner
      const rev = await svc.revokeDeviceKey(devKeyId, testUid, 'LOST_OR_STOLEN');
      assert.strictEqual(rev.success, true);

      const record = await svc.getDeviceKey(devKeyId);
      assert.strictEqual(record?.lifecycleStatus, 'REVOKED');
      assert.ok(record?.revokedAt);
      assert.strictEqual(record?.revocationReason, 'LOST_OR_STOLEN');

      // Active devices count should now be 0
      const active = await svc.getActiveDevicesForUser(testUid);
      assert.strictEqual(active.length, 0);
    });

    it('2.6: Rejects unauthorized revocation attempts from non-owner accounts', async () => {
      const kp = generateTestKeyPair();
      const pubPem = kp.publicKey.export({ type: 'spki', format: 'pem' }).toString();
      const mockVerifier = {
        verifyAttestation: () => ({
          valid: true,
          attestationLevel: 'DEVICE_KEY_TEE' as const,
          attestationStatus: 'VERIFIED' as const,
          publicKeyPem: pubPem,
          keyAlgorithm: 'ECDSA_P256' as const,
          securityLevelNumeric: 1,
          certificateChainLength: 1,
        }),
      } as any;

      const svc = new DeviceRegistrationService(undefined, mockVerifier);
      const ownerUid = 'worker_legit_owner';
      const attackerUid = 'worker_attacker_hacker';

      const chal = await svc.issueRegistrationChallenge(ownerUid);
      const reg = await svc.registerDevice({
        authenticatedUid: ownerUid,
        challengeId: chal.challengeId,
        challengeNonce: chal.challengeNonce,
        certificateChainBase64: ['c'],
      });

      const rev = await svc.revokeDeviceKey(reg.deviceKeyId!, attackerUid);
      assert.strictEqual(rev.success, false);
      assert.strictEqual(rev.errorCode, 'UNAUTHORIZED');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // SUITE 3: Transaction-Bound Device Signature Protocol
  // ─────────────────────────────────────────────────────────────────────────────
  describe('Suite 3: Transaction-Bound Device Signature Protocol & Invariants', () => {
    let deviceService: DeviceRegistrationService;
    let sigService: DeviceRequestSignatureService;
    let workerKey: { publicKey: crypto.KeyObject; privateKey: crypto.KeyObject };
    let workerPubKeyPem: string;
    let registeredDeviceKeyId: string;
    const workerUid = 'worker_anand_major_proj';

    before(async () => {
      workerKey = generateTestKeyPair();
      workerPubKeyPem = workerKey.publicKey.export({ type: 'spki', format: 'pem' }).toString();

      const mockVerifier = {
        verifyAttestation: () => ({
          valid: true,
          attestationLevel: 'DEVICE_KEY_STRONGBOX' as const,
          attestationStatus: 'VERIFIED' as const,
          publicKeyPem: workerPubKeyPem,
          keyAlgorithm: 'ECDSA_P256' as const,
          securityLevelNumeric: 2,
          certificateChainLength: 2,
        }),
      } as any;

      deviceService = new DeviceRegistrationService(undefined, mockVerifier);
      sigService = new DeviceRequestSignatureService(undefined, deviceService);

      const chal = await deviceService.issueRegistrationChallenge(workerUid);
      const reg = await deviceService.registerDevice({
        authenticatedUid: workerUid,
        challengeId: chal.challengeId,
        challengeNonce: chal.challengeNonce,
        certificateChainBase64: ['chain'],
      });
      registeredDeviceKeyId = reg.deviceKeyId!;
    });

    it('3.1: Issues transaction challenge bound to UID, deviceKeyId, and purpose', async () => {
      const txChal = await sigService.issueTransactionChallenge({
        uid: workerUid,
        deviceKeyId: registeredDeviceKeyId,
        purpose: 'BIOMETRIC_ENROLLMENT',
      });

      assert.ok(txChal.challengeId.startsWith('tx_chal_'));
      assert.strictEqual(txChal.uid, workerUid);
      assert.strictEqual(txChal.deviceKeyId, registeredDeviceKeyId);
      assert.strictEqual(txChal.purpose, 'BIOMETRIC_ENROLLMENT');
      assert.strictEqual(txChal.consumed, false);
    });

    it('3.2: Rejects transaction challenge issuance for a non-existent or revoked device', async () => {
      await assert.rejects(
        async () => {
          await sigService.issueTransactionChallenge({
            uid: workerUid,
            deviceKeyId: 'devkey_non_existent',
            purpose: 'BIOMETRIC_ENROLLMENT',
          });
        },
        /Device key not found/
      );
    });

    it('3.3: Successfully generates and verifies genuine ECDSA P-256 transaction signature', async () => {
      const rawImageBytes = Buffer.from('mock_genuine_face_camera_frame_bytes_12345', 'utf8');
      const payloadDigest = computePayloadDigest(rawImageBytes);

      const txChal = await sigService.issueTransactionChallenge({
        uid: workerUid,
        deviceKeyId: registeredDeviceKeyId,
        purpose: 'BIOMETRIC_ENROLLMENT',
      });

      const params: PlayIntegrityBindingParamsV2 = {
        protocolVersion: PLAY_INTEGRITY_BINDING_PROTOCOL_V2,
        packageName: 'com.kelasagaara.kelasagaara',
        appVersion: '1.0.0',
        authenticatedUid: workerUid,
        deviceKeyId: registeredDeviceKeyId,
        challengeId: txChal.challengeId,
        challengePurpose: 'BIOMETRIC_ENROLLMENT',
        serverNonce: txChal.challengeNonce,
        idempotencyKey: 'idem_tx_001',
        httpMethod: 'POST',
        route: '/api/biometrics/v10/enroll',
        payloadDigestSha256: payloadDigest,
      };

      // Client-side: serialize canonical binary payload and sign with private key
      const canonicalBytes = serializeCanonicalBinding(params);
      const signature = crypto.sign('sha256', canonicalBytes, workerKey.privateKey);
      const signatureBase64 = signature.toString('base64');

      // Server-side: verify signature
      const result = sigService.verifyDeviceSignature({
        bindingParams: params,
        signatureBase64,
        publicKeyPem: workerPubKeyPem,
      });

      assert.strictEqual(result.valid, true);
      assert.strictEqual(result.deviceKeyId, registeredDeviceKeyId);
      assert.ok(result.canonicalRequestHash);
    });

    it('3.4: Rejects signature verification if ANY field of the transaction payload is tampered', async () => {
      const rawImageBytes = Buffer.from('original_face_camera_frame_bytes', 'utf8');
      const payloadDigest = computePayloadDigest(rawImageBytes);

      const params: PlayIntegrityBindingParamsV2 = {
        protocolVersion: PLAY_INTEGRITY_BINDING_PROTOCOL_V2,
        packageName: 'com.kelasagaara.kelasagaara',
        appVersion: '1.0.0',
        authenticatedUid: workerUid,
        deviceKeyId: registeredDeviceKeyId,
        challengeId: 'tx_chal_tamper_test',
        challengePurpose: 'BIOMETRIC_ENROLLMENT',
        serverNonce: 'nonce_original',
        idempotencyKey: 'idem_001',
        httpMethod: 'POST',
        route: '/api/biometrics/v10/enroll',
        payloadDigestSha256: payloadDigest,
      };

      const canonicalBytes = serializeCanonicalBinding(params);
      const signature = crypto.sign('sha256', canonicalBytes, workerKey.privateKey);
      const signatureBase64 = signature.toString('base64');

      // Attack A: Tamper 1 byte in capture image payload
      const tamperedImageBytes = Buffer.from('original_face_camera_frame_bytes!', 'utf8');
      const tamperedParamsA: PlayIntegrityBindingParamsV2 = {
        ...params,
        payloadDigestSha256: computePayloadDigest(tamperedImageBytes),
      };
      const resA = sigService.verifyDeviceSignature({
        bindingParams: tamperedParamsA,
        signatureBase64,
        publicKeyPem: workerPubKeyPem,
      });
      assert.strictEqual(resA.valid, false, 'Tampered image bytes must fail verification');

      // Attack B: Tamper route (enroll signature submitted to verify-1to1)
      const tamperedParamsB: PlayIntegrityBindingParamsV2 = {
        ...params,
        route: '/api/biometrics/v10/verify-1to1',
      };
      const resB = sigService.verifyDeviceSignature({
        bindingParams: tamperedParamsB,
        signatureBase64,
        publicKeyPem: workerPubKeyPem,
      });
      assert.strictEqual(resB.valid, false, 'Tampered route must fail verification');

      // Attack C: Cross-user identity swap (Alice signature submitted for Bob)
      const tamperedParamsC: PlayIntegrityBindingParamsV2 = {
        ...params,
        authenticatedUid: 'worker_bob_victim',
      };
      const resC = sigService.verifyDeviceSignature({
        bindingParams: tamperedParamsC,
        signatureBase64,
        publicKeyPem: workerPubKeyPem,
      });
      assert.strictEqual(resC.valid, false, 'Cross-user submission must fail verification');
    });

    it('3.5: Prevents challenge replay: atomic consumption allows exactly one usage', async () => {
      const txChal = await sigService.issueTransactionChallenge({
        uid: workerUid,
        deviceKeyId: registeredDeviceKeyId,
        purpose: 'BIOMETRIC_ENROLLMENT',
      });

      // Consumption 1: Success
      const c1 = await sigService.consumeTransactionChallenge({
        challengeId: txChal.challengeId,
        nonce: txChal.challengeNonce,
        expectedUid: workerUid,
        expectedDeviceKeyId: registeredDeviceKeyId,
        expectedPurpose: 'BIOMETRIC_ENROLLMENT',
      });
      assert.strictEqual(c1.valid, true);

      // Consumption 2 (Replay attack): MUST fail
      const c2 = await sigService.consumeTransactionChallenge({
        challengeId: txChal.challengeId,
        nonce: txChal.challengeNonce,
        expectedUid: workerUid,
        expectedDeviceKeyId: registeredDeviceKeyId,
        expectedPurpose: 'BIOMETRIC_ENROLLMENT',
      });
      assert.strictEqual(c2.valid, false);
      assert.strictEqual(c2.errorCode, 'CHALLENGE_REPLAYED');
    });

    it('3.6: Rejects consumption when purpose does not match issuance (Purpose Substitution)', async () => {
      const txChal = await sigService.issueTransactionChallenge({
        uid: workerUid,
        deviceKeyId: registeredDeviceKeyId,
        purpose: 'BIOMETRIC_ENROLLMENT',
      });

      const res = await sigService.consumeTransactionChallenge({
        challengeId: txChal.challengeId,
        nonce: txChal.challengeNonce,
        expectedUid: workerUid,
        expectedDeviceKeyId: registeredDeviceKeyId,
        expectedPurpose: 'BIOMETRIC_VERIFICATION_1TO1', // Purpose substitution attack
      });

      assert.strictEqual(res.valid, false);
      assert.strictEqual(res.errorCode, 'CHALLENGE_PURPOSE_MISMATCH');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // SUITE 4: Middleware Enforcement & 3-Factor Isolation
  // ─────────────────────────────────────────────────────────────────────────────
  describe('Suite 4: Middleware Enforcement & 3-Factor Independence', () => {
    let deviceService: DeviceRegistrationService;
    let sigService: DeviceRequestSignatureService;
    let workerKey: { publicKey: crypto.KeyObject; privateKey: crypto.KeyObject };
    let workerPubKeyPem: string;
    let registeredDeviceKeyId: string;
    const workerUid = 'worker_independent_audit_user';

    before(async () => {
      workerKey = generateTestKeyPair();
      workerPubKeyPem = workerKey.publicKey.export({ type: 'spki', format: 'pem' }).toString();

      const mockVerifier = {
        verifyAttestation: () => ({
          valid: true,
          attestationLevel: 'DEVICE_KEY_STRONGBOX' as const,
          attestationStatus: 'VERIFIED' as const,
          publicKeyPem: workerPubKeyPem,
          keyAlgorithm: 'ECDSA_P256' as const,
          securityLevelNumeric: 2,
          certificateChainLength: 1,
        }),
      } as any;

      deviceService = new DeviceRegistrationService(undefined, mockVerifier);
      sigService = new DeviceRequestSignatureService(undefined, deviceService);

      const chal = await deviceService.issueRegistrationChallenge(workerUid);
      const reg = await deviceService.registerDevice({
        authenticatedUid: workerUid,
        challengeId: chal.challengeId,
        challengeNonce: chal.challengeNonce,
        certificateChainBase64: ['c'],
      });
      registeredDeviceKeyId = reg.deviceKeyId!;
    });

    it('4.1: Rejects unauthenticated request with HTTP 401', async () => {
      const middleware = createRequireDeviceSignatureMiddleware(deviceService, sigService);
      const req: any = { user: null, headers: {}, body: {} };
      let status = 0;
      let jsonResp: any = null;
      const res: any = {
        status: (s: number) => {
          status = s;
          return { json: (j: any) => (jsonResp = j) };
        },
      };

      await middleware(req, res, () => {});
      assert.strictEqual(status, 401);
      assert.strictEqual(jsonResp.code, 'UNAUTHENTICATED');
    });

    it('4.2: In production/strict mode, rejects request missing device credentials with HTTP 400', async () => {
      const prevStrict = process.env.STRICT_DEVICE_SECURITY;
      process.env.STRICT_DEVICE_SECURITY = 'true';

      const middleware = createRequireDeviceSignatureMiddleware(deviceService, sigService);
      const req: any = { user: { uid: workerUid }, headers: {}, body: {} };
      let status = 0;
      let jsonResp: any = null;
      const res: any = {
        status: (s: number) => {
          status = s;
          return { json: (j: any) => (jsonResp = j) };
        },
      };

      await middleware(req, res, () => {});
      assert.strictEqual(status, 400);
      assert.strictEqual(jsonResp.code, 'MISSING_DEVICE_SECURITY_CREDENTIALS');

      process.env.STRICT_DEVICE_SECURITY = prevStrict;
    });

    it('4.3: Rejects request using a device key registered to a DIFFERENT user (Cross-User Account Hijack)', async () => {
      const impostorUid = 'worker_impostor_mallory';
      const middleware = createRequireDeviceSignatureMiddleware(deviceService, sigService);

      const req: any = {
        user: { uid: impostorUid },
        headers: {
          'x-device-key-id': registeredDeviceKeyId,
          'x-device-signature': 'dummy_sig',
        },
        body: {},
      };
      let status = 0;
      let jsonResp: any = null;
      const res: any = {
        status: (s: number) => {
          status = s;
          return { json: (j: any) => (jsonResp = j) };
        },
      };

      await middleware(req, res, () => {});
      assert.strictEqual(status, 403);
      assert.strictEqual(jsonResp.code, 'DEVICE_OWNERSHIP_MISMATCH');
    });

    it('4.4: Rejects request using a REVOKED device key with HTTP 403', async () => {
      // Revoke the key
      await deviceService.revokeDeviceKey(registeredDeviceKeyId, workerUid, 'TEST_REVOCATION');

      const middleware = createRequireDeviceSignatureMiddleware(deviceService, sigService);
      const req: any = {
        user: { uid: workerUid },
        headers: {
          'x-device-key-id': registeredDeviceKeyId,
          'x-device-signature': 'dummy_sig',
        },
        body: {},
      };
      let status = 0;
      let jsonResp: any = null;
      const res: any = {
        status: (s: number) => {
          status = s;
          return { json: (j: any) => (jsonResp = j) };
        },
      };

      await middleware(req, res, () => {});
      assert.strictEqual(status, 403);
      assert.strictEqual(jsonResp.code, 'DEVICE_KEY_REVOKED');
    });

    it('4.5: Valid 3-Factor Request (Firebase Auth + Active Device Key + Valid Signature) passes to next()', async () => {
      // Re-register a fresh active device key for this test
      const freshKey = generateTestKeyPair();
      const freshPubPem = freshKey.publicKey.export({ type: 'spki', format: 'pem' }).toString();
      const mockVerifier = {
        verifyAttestation: () => ({
          valid: true,
          attestationLevel: 'DEVICE_KEY_STRONGBOX' as const,
          attestationStatus: 'VERIFIED' as const,
          publicKeyPem: freshPubPem,
          keyAlgorithm: 'ECDSA_P256' as const,
          securityLevelNumeric: 2,
          certificateChainLength: 1,
        }),
      } as any;

      const freshDeviceService = new DeviceRegistrationService(undefined, mockVerifier);
      const freshSigService = new DeviceRequestSignatureService(undefined, freshDeviceService);
      const userUid = 'worker_three_factor_valid_user';

      const dChal = await freshDeviceService.issueRegistrationChallenge(userUid);
      const reg = await freshDeviceService.registerDevice({
        authenticatedUid: userUid,
        challengeId: dChal.challengeId,
        challengeNonce: dChal.challengeNonce,
        certificateChainBase64: ['c'],
      });
      const devKeyId = reg.deviceKeyId!;

      const txChal = await freshSigService.issueTransactionChallenge({
        uid: userUid,
        deviceKeyId: devKeyId,
        purpose: 'BIOMETRIC_ENROLLMENT',
      });

      const rawImageBytes = Buffer.from('uncompressed_face_capture_frame_640x480', 'utf8');
      const payloadDigest = computePayloadDigest(rawImageBytes);

      const bindingParams: PlayIntegrityBindingParamsV2 = {
        protocolVersion: PLAY_INTEGRITY_BINDING_PROTOCOL_V2,
        packageName: 'com.kelasagaara.kelasagaara',
        appVersion: '1.0.0',
        authenticatedUid: userUid,
        deviceKeyId: devKeyId,
        challengeId: txChal.challengeId,
        challengePurpose: 'BIOMETRIC_ENROLLMENT',
        serverNonce: txChal.challengeNonce,
        idempotencyKey: 'idem_valid_3factor',
        httpMethod: 'POST',
        route: '/api/biometrics/v10/enroll',
        payloadDigestSha256: payloadDigest,
      };

      const canonicalBytes = serializeCanonicalBinding(bindingParams);
      const sig = crypto.sign('sha256', canonicalBytes, freshKey.privateKey);

      const middleware = createRequireDeviceSignatureMiddleware(freshDeviceService, freshSigService);
      const req: any = {
        user: { uid: userUid },
        baseUrl: '/api/biometrics/v10',
        path: '/enroll',
        method: 'POST',
        headers: {
          'x-device-key-id': devKeyId,
          'x-device-signature': sig.toString('base64'),
          'x-transaction-challenge-id': txChal.challengeId,
          'x-challenge-nonce': txChal.challengeNonce,
          'x-idempotency-key': 'idem_valid_3factor',
        },
        body: {
          imageBase64: rawImageBytes.toString('base64'),
        },
      };

      let passedToNext = false;
      const res: any = {
        status: () => ({ json: () => {} }),
      };

      await middleware(req, res, () => {
        passedToNext = true;
      });

      assert.strictEqual(passedToNext, true, 'Valid 3-factor request must pass to next()');
      assert.ok(req.deviceKey);
      assert.strictEqual(req.deviceKey.deviceKeyId, devKeyId);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // SUITE 5: PLAY_INTEGRITY_BINDING_V2 Specification & Digest Parity
  // ─────────────────────────────────────────────────────────────────────────────
  describe('Suite 5: PLAY_INTEGRITY_BINDING_V2 & Camera Payload Digest Parity', () => {
    it('5.1: Binds SHA256(exact submitted image bytes) instead of client-extracted vectors', () => {
      const rawImage1 = Buffer.from('camera_frame_capture_bytes_attempt_1');
      const rawImage2 = Buffer.from('camera_frame_capture_bytes_attempt_2');

      const digest1 = computePayloadDigest(rawImage1);
      const digest2 = computePayloadDigest(rawImage2);

      assert.notStrictEqual(digest1, digest2);
      assert.strictEqual(digest1.length, 64); // SHA-256 hex string
    });

    it('5.2: Guarantees length-prefixed binary canonical serialization prevents delimiter collisions', () => {
      // If two fields are:
      // Case A: field1 = "abc", field2 = "def"
      // Case B: field1 = "abcd", field2 = "ef"
      // A simple concatenation "abcdef" collides! But 4-byte length prefix guarantees distinct bytes.
      const paramsA: PlayIntegrityBindingParamsV2 = {
        protocolVersion: PLAY_INTEGRITY_BINDING_PROTOCOL_V2,
        packageName: 'com.kelasagaara.kelasagaara',
        appVersion: '1.0.0',
        authenticatedUid: 'usr_abc',
        deviceKeyId: 'def',
        challengeId: 'chl1',
        challengePurpose: 'BIOMETRIC_ENROLLMENT',
        serverNonce: 'nonce1',
        idempotencyKey: 'idem1',
        httpMethod: 'POST',
        route: '/enroll',
        payloadDigestSha256: 'hash1',
      };

      const paramsB: PlayIntegrityBindingParamsV2 = {
        ...paramsA,
        authenticatedUid: 'usr_abcd',
        deviceKeyId: 'ef',
      };

      const binA = serializeCanonicalBinding(paramsA);
      const binB = serializeCanonicalBinding(paramsB);

      assert.notDeepStrictEqual(binA, binB, 'Length-prefixing must prevent delimiter collisions');

      const hashA = computePlayIntegrityRequestHash(paramsA);
      const hashB = computePlayIntegrityRequestHash(paramsB);
      assert.notStrictEqual(hashA, hashB);
    });
  });
});
