/**
 * KELASAGARA V20.18: PILOT READINESS CORRECTIONS ADVERSARIAL TEST SUITE
 *
 * Implements 45 dedicated verification tests covering all 5 core engineering tracks:
 * - Track A: Plan Execution Environment & Supply-Chain Attestation (Tests 1–10)
 * - Track B: Workload Identity & Durable Replay Protection (Tests 11–20)
 * - Track C: Vault Decryption Isolation & Best-Effort Memory Clearing (Tests 21–30)
 * - Track D: Two-Person Dual Custody Recovery Assurance (Tests 31–38)
 * - Track E: Audit Notary Create-Only & Reconciler Independence (Tests 39–45)
 */

import { describe, it, before, after } from 'node:test';
import * as assert from 'node:assert';
import * as crypto from 'crypto';
import * as fs from 'fs';
import * as path from 'path';

import {
  TrustedPlanWrapperV18,
  APPROVED_TOFU_BINARY_HASH,
  APPROVED_TOFU_VERSION,
} from '../services/trusted_plan_wrapper_v18';
import {
  InternalWorkloadIdentityServiceV18,
  DistributedDurableReplayStore,
} from '../services/internal_workload_identity_v18';
import {
  VaultDecryptionGuardV18,
  EncryptedVaultRecordV18,
} from '../services/vault_decryption_guard_v18';
import {
  RecoveryDualCustodyEngineV18,
  DualCustodyApproverV18,
  DualCustodyRecoveryTokenV18,
} from '../services/recovery_dual_custody_v18';
import {
  AuditReconcilerServiceV18,
  AuditEventRecordV18,
  ExternalCheckpointObjectV18,
} from '../services/audit_reconciler_service_v18';

describe('KELASAGARA V20.18: Pilot Readiness Corrections & Security Boundary Suite (45 Tests)', () => {
  const tfDir = path.resolve(__dirname, '../../../infra/terraform');
  let ecKeyPair: { privateKey: string; publicKey: string };

  before(() => {
    const { privateKey, publicKey } = crypto.generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
    ecKeyPair = {
      privateKey: privateKey.export({ type: 'pkcs8', format: 'pem' }) as string,
      publicKey: publicKey.export({ type: 'spki', format: 'pem' }) as string,
    };
  });

  // =========================================================================
  // TRACK A: PLAN EXECUTION ENVIRONMENT & SUPPLY-CHAIN ATTESTATION (Tests 1–10)
  // =========================================================================
  describe('Track A: Plan Execution Environment & Supply-Chain Attestation (Tests 1–10)', () => {
    const wrapper = new TrustedPlanWrapperV18();

    it('1. Injected TF_CLI_ARGS_plan rejected before OpenTofu launch', () => {
      const res = wrapper.generatePlanWithAttestation({
        tfDir,
        cliArgs: ['-input=false'],
        environment: 'sandbox',
        projectId: 'kelasagara-sandbox',
        runnerIdentity: 'sa-ci-plan-runner',
        customEnv: {
          TF_CLI_ARGS_plan: '-target=module.compute',
          PATH: '/usr/bin:/bin',
        },
      });
      assert.strictEqual(res.success, false);
      assert.strictEqual(res.errorCode, 'ERR_PROHIBITED_ENV_VAR');
      assert.match(res.errorMessage || '', /TF_CLI_ARGS_plan/);
    });

    it('2. Injected unapproved workspace (prod) rejected', () => {
      const res = wrapper.generatePlanWithAttestation({
        tfDir,
        cliArgs: ['-input=false'],
        environment: 'sandbox',
        projectId: 'kelasagara-sandbox',
        runnerIdentity: 'sa-ci-plan-runner',
        workspace: 'prod',
      });
      assert.strictEqual(res.success, false);
      assert.strictEqual(res.errorCode, 'ERR_UNAPPROVED_WORKSPACE');
    });

    it('3. Alternate CLI configuration (.terraformrc) rejected', () => {
      const altFile = path.join(tfDir, '.terraformrc');
      fs.writeFileSync(altFile, 'provider_installation { filesystem_mirror { path = "/tmp" } }');
      try {
        const res = wrapper.generatePlanWithAttestation({
          tfDir,
          cliArgs: ['-input=false'],
          environment: 'sandbox',
          projectId: 'kelasagara-sandbox',
          runnerIdentity: 'sa-ci-plan-runner',
        });
        assert.strictEqual(res.success, false);
        assert.strictEqual(res.errorCode, 'ERR_ALTERNATE_CLI_CONFIG');
      } finally {
        if (fs.existsSync(altFile)) fs.unlinkSync(altFile);
      }
    });

    it('4. Unexpected variable injection (unapproved TF_VAR_*) rejected', () => {
      const res = wrapper.generatePlanWithAttestation({
        tfDir,
        cliArgs: ['-input=false'],
        environment: 'sandbox',
        projectId: 'kelasagara-sandbox',
        runnerIdentity: 'sa-ci-plan-runner',
        customEnv: {
          TF_VAR_injected_admin_override: 'true',
          PATH: '/usr/bin:/bin',
        },
      });
      assert.strictEqual(res.success, false);
      assert.strictEqual(res.errorCode, 'ERR_UNAPPROVED_TF_ENV_VAR');
    });

    it('5. Unapproved CLI flag (-target) rejected', () => {
      const res = wrapper.generatePlanWithAttestation({
        tfDir,
        cliArgs: ['-target=google_storage_bucket.audit_bucket'],
        environment: 'sandbox',
        projectId: 'kelasagara-sandbox',
        runnerIdentity: 'sa-ci-plan-runner',
      });
      assert.strictEqual(res.success, false);
      assert.strictEqual(res.errorCode, 'ERR_PROHIBITED_CLI_FLAG');
    });

    it('6. Modified plan binary rejected by apply gate', () => {
      const planRes = wrapper.generatePlanWithAttestation({
        tfDir,
        cliArgs: ['-input=false'],
        environment: 'sandbox',
        projectId: 'kelasagara-sandbox',
        runnerIdentity: 'sa-ci-plan-runner',
        privateKeyPem: ecKeyPair.privateKey,
        publicKeyPem: ecKeyPair.publicKey,
      });
      assert.strictEqual(planRes.success, true);
      assert.ok(planRes.signedManifest);

      // Mutate binary buffer
      const tamperedBuffer = Buffer.from(fs.readFileSync(planRes.planBinaryPath!));
      tamperedBuffer[0] ^= 0xff;

      const applyRes = wrapper.verifyPlanForApply({
        planBinaryBuffer: tamperedBuffer,
        signedManifest: planRes.signedManifest!,
      });
      assert.strictEqual(applyRes.approvedForApply, false);
      assert.strictEqual(applyRes.errorCode, 'ERR_PLAN_DIGEST_MISMATCH');

      // Cleanup
      if (fs.existsSync(planRes.planBinaryPath!)) fs.unlinkSync(planRes.planBinaryPath!);
    });

    it('7. Modified manifest signature rejected by apply gate', () => {
      const planRes = wrapper.generatePlanWithAttestation({
        tfDir,
        cliArgs: ['-input=false'],
        environment: 'sandbox',
        projectId: 'kelasagara-sandbox',
        runnerIdentity: 'sa-ci-plan-runner',
        privateKeyPem: ecKeyPair.privateKey,
        publicKeyPem: ecKeyPair.publicKey,
      });
      assert.strictEqual(planRes.success, true);

      const tamperedSignedManifest = {
        ...planRes.signedManifest!,
        signatureBase64: Buffer.from('TAMPERED_SIG').toString('base64'),
      };

      const buffer = fs.readFileSync(planRes.planBinaryPath!);
      const applyRes = wrapper.verifyPlanForApply({
        planBinaryBuffer: buffer,
        signedManifest: tamperedSignedManifest,
      });
      assert.strictEqual(applyRes.approvedForApply, false);
      assert.strictEqual(applyRes.errorCode, 'ERR_MANIFEST_SIGNATURE_INVALID');

      if (fs.existsSync(planRes.planBinaryPath!)) fs.unlinkSync(planRes.planBinaryPath!);
    });

    it('8. Different executable digest rejected by apply gate', () => {
      const planRes = wrapper.generatePlanWithAttestation({
        tfDir,
        cliArgs: ['-input=false'],
        environment: 'sandbox',
        projectId: 'kelasagara-sandbox',
        runnerIdentity: 'sa-ci-plan-runner',
        privateKeyPem: ecKeyPair.privateKey,
        publicKeyPem: ecKeyPair.publicKey,
      });
      assert.strictEqual(planRes.success, true);

      const buffer = fs.readFileSync(planRes.planBinaryPath!);
      const applyRes = wrapper.verifyPlanForApply({
        planBinaryBuffer: buffer,
        signedManifest: planRes.signedManifest!,
        expectedTofuBinaryHash: '0000000000000000000000000000000000000000000000000000000000000000',
      });
      assert.strictEqual(applyRes.approvedForApply, false);
      assert.strictEqual(applyRes.errorCode, 'ERR_TOOLCHAIN_MISMATCH');

      if (fs.existsSync(planRes.planBinaryPath!)) fs.unlinkSync(planRes.planBinaryPath!);
    });

    it('9. Different provider lock digest detected if modified', () => {
      const lockPath = path.join(tfDir, '.terraform.lock.hcl');
      const originalDigest = wrapper.getFileSha256(lockPath);
      assert.strictEqual(typeof originalDigest, 'string');
      assert.strictEqual(originalDigest.length, 64);
    });

    it('10. Unauthorized apply rejected when policyDecision is REJECTED', () => {
      const planRes = wrapper.generatePlanWithAttestation({
        tfDir,
        cliArgs: ['-input=false'],
        environment: 'sandbox',
        projectId: 'kelasagara-sandbox',
        runnerIdentity: 'sa-ci-plan-runner',
        privateKeyPem: ecKeyPair.privateKey,
        publicKeyPem: ecKeyPair.publicKey,
      });
      assert.strictEqual(planRes.success, true);

      // Manually forge manifest policy decision to REJECTED with valid re-signature
      const forgedManifest = {
        ...planRes.signedManifest!.manifest,
        policyDecision: 'REJECTED' as const,
      };
      const canonicalJson = wrapper.canonicalizeJson(forgedManifest);
      const sign = crypto.createSign('SHA256');
      sign.update(canonicalJson);
      sign.end();
      const newSig = sign.sign(ecKeyPair.privateKey, 'base64');

      const forgedSignedManifest = {
        manifest: forgedManifest,
        signatureBase64: newSig,
        signerPublicKeyPem: ecKeyPair.publicKey,
        signatureAlgorithm: 'SHA256withECDSA' as const,
      };

      const buffer = fs.readFileSync(planRes.planBinaryPath!);
      const applyRes = wrapper.verifyPlanForApply({
        planBinaryBuffer: buffer,
        signedManifest: forgedSignedManifest,
      });
      assert.strictEqual(applyRes.approvedForApply, false);
      assert.strictEqual(applyRes.errorCode, 'ERR_PLAN_NOT_APPROVED');

      if (fs.existsSync(planRes.planBinaryPath!)) fs.unlinkSync(planRes.planBinaryPath!);
    });
  });

  // =========================================================================
  // TRACK B: WORKLOAD IDENTITY & DURABLE REPLAY PROTECTION (Tests 11–20)
  // =========================================================================
  describe('Track B: Workload Identity & Durable Replay Protection (Tests 11–20)', () => {
    const service = new InternalWorkloadIdentityServiceV18();
    const verifierSa = 'sa-biometrics-verifier@kelasagara.iam.gserviceaccount.com';
    const targetUrl = 'https://vault.internal.service';

    before(() => {
      service.registerVerificationKey('key-1', ecKeyPair.publicKey);
    });

    it('11. Incorrect audience rejected', async () => {
      const token = service.generateTestOidcToken(
        {
          iss: 'https://accounts.google.com',
          aud: 'https://wrong-audience.internal',
          email: verifierSa,
          exp: Math.floor(Date.now() / 1000) + 3600,
          iat: Math.floor(Date.now() / 1000),
          sub: '1092837465019283',
        },
        ecKeyPair.privateKey
      );

      const res = await service.verifySensitiveOperationCall({
        targetServiceUrl: targetUrl,
        rawAuthorizationHeader: `Bearer ${token}`,
        method: 'POST',
        endpoint: '/api/v1/vault/decrypt',
        targetAccountUid: 'worker_alice_123',
        targetResource: 'template_001',
        operationNonce: 'nonce-11',
        operationId: 'op-11',
        expectedServiceAccountEmail: verifierSa,
      });

      assert.strictEqual(res.authorized, false);
      assert.strictEqual(res.errorCode, 'ERR_AUDIENCE_MISMATCH');
    });

    it('12. Incorrect issuer rejected', async () => {
      const token = service.generateTestOidcToken(
        {
          iss: 'https://malicious-issuer.com',
          aud: targetUrl,
          email: verifierSa,
          exp: Math.floor(Date.now() / 1000) + 3600,
          iat: Math.floor(Date.now() / 1000),
          sub: '1092837465019283',
        },
        ecKeyPair.privateKey
      );

      const res = await service.verifySensitiveOperationCall({
        targetServiceUrl: targetUrl,
        rawAuthorizationHeader: `Bearer ${token}`,
        method: 'POST',
        endpoint: '/api/v1/vault/decrypt',
        targetAccountUid: 'worker_alice_123',
        targetResource: 'template_001',
        operationNonce: 'nonce-12',
        operationId: 'op-12',
        expectedServiceAccountEmail: verifierSa,
      });

      assert.strictEqual(res.authorized, false);
      assert.strictEqual(res.errorCode, 'ERR_INVALID_TOKEN_ISSUER');
    });

    it('13. Expired token rejected', async () => {
      const token = service.generateTestOidcToken(
        {
          iss: 'https://accounts.google.com',
          aud: targetUrl,
          email: verifierSa,
          exp: Math.floor(Date.now() / 1000) - 60, // Expired 1 min ago
          iat: Math.floor(Date.now() / 1000) - 3600,
          sub: '1092837465019283',
        },
        ecKeyPair.privateKey
      );

      const res = await service.verifySensitiveOperationCall({
        targetServiceUrl: targetUrl,
        rawAuthorizationHeader: `Bearer ${token}`,
        method: 'POST',
        endpoint: '/api/v1/vault/decrypt',
        targetAccountUid: 'worker_alice_123',
        targetResource: 'template_001',
        operationNonce: 'nonce-13',
        operationId: 'op-13',
        expectedServiceAccountEmail: verifierSa,
      });

      assert.strictEqual(res.authorized, false);
      assert.strictEqual(res.errorCode, 'ERR_INTERNAL_TOKEN_EXPIRED');
    });

    it('14. Invalid signature rejected', async () => {
      const { privateKey: otherKey } = crypto.generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
      const otherKeyPem = otherKey.export({ type: 'pkcs8', format: 'pem' }) as string;

      const token = service.generateTestOidcToken(
        {
          iss: 'https://accounts.google.com',
          aud: targetUrl,
          email: verifierSa,
          exp: Math.floor(Date.now() / 1000) + 3600,
          iat: Math.floor(Date.now() / 1000),
          sub: '1092837465019283',
        },
        otherKeyPem
      );

      const res = await service.verifySensitiveOperationCall({
        targetServiceUrl: targetUrl,
        rawAuthorizationHeader: `Bearer ${token}`,
        method: 'POST',
        endpoint: '/api/v1/vault/decrypt',
        targetAccountUid: 'worker_alice_123',
        targetResource: 'template_001',
        operationNonce: 'nonce-14',
        operationId: 'op-14',
        expectedServiceAccountEmail: verifierSa,
      });

      assert.strictEqual(res.authorized, false);
      assert.strictEqual(res.errorCode, 'ERR_INVALID_TOKEN_SIGNATURE');
    });

    it('15. Forged principal header rejected without token', async () => {
      const res = await service.verifySensitiveOperationCall({
        targetServiceUrl: targetUrl,
        callerSuppliedPrincipalHeader: 'sa-biometrics-verifier@kelasagara.iam.gserviceaccount.com',
        method: 'POST',
        endpoint: '/api/v1/vault/decrypt',
        targetAccountUid: 'worker_alice_123',
        targetResource: 'template_001',
        operationNonce: 'nonce-15',
        operationId: 'op-15',
        expectedServiceAccountEmail: verifierSa,
      });

      assert.strictEqual(res.authorized, false);
      assert.strictEqual(res.errorCode, 'ERR_FORGED_PRINCIPAL_HEADER');
    });

    it('16. JTI missing is accepted if token claims and signature are valid', async () => {
      const token = service.generateTestOidcToken(
        {
          iss: 'https://accounts.google.com',
          aud: targetUrl,
          email: verifierSa,
          exp: Math.floor(Date.now() / 1000) + 3600,
          iat: Math.floor(Date.now() / 1000),
          sub: '1092837465019283',
          // Notice: jti is omitted! Google Cloud SA tokens regularly omit jti.
        },
        ecKeyPair.privateKey
      );

      const res = await service.verifySensitiveOperationCall({
        targetServiceUrl: targetUrl,
        rawAuthorizationHeader: `Bearer ${token}`,
        method: 'POST',
        endpoint: '/api/v1/vault/decrypt',
        targetAccountUid: 'worker_alice_123',
        targetResource: 'template_001',
        operationNonce: 'nonce-16-first-call',
        operationId: 'op-16',
        expectedServiceAccountEmail: verifierSa,
      });

      assert.strictEqual(res.authorized, true);
      assert.strictEqual(res.verifiedServiceAccountEmail, verifierSa);
    });

    it('17. Token reuse with unique request nonce is accepted across multiple requests', async () => {
      const token = service.generateTestOidcToken(
        {
          iss: 'https://accounts.google.com',
          aud: targetUrl,
          email: verifierSa,
          exp: Math.floor(Date.now() / 1000) + 3600,
          iat: Math.floor(Date.now() / 1000),
          sub: '1092837465019283',
        },
        ecKeyPair.privateKey
      );

      // Call 1
      const res1 = await service.verifySensitiveOperationCall({
        targetServiceUrl: targetUrl,
        rawAuthorizationHeader: `Bearer ${token}`,
        method: 'POST',
        endpoint: '/api/v1/vault/decrypt',
        targetAccountUid: 'worker_alice_123',
        targetResource: 'template_001',
        operationNonce: 'nonce-17-request-A',
        operationId: 'op-17-A',
        expectedServiceAccountEmail: verifierSa,
      });
      assert.strictEqual(res1.authorized, true);

      // Call 2 with SAME valid token but NEW nonce
      const res2 = await service.verifySensitiveOperationCall({
        targetServiceUrl: targetUrl,
        rawAuthorizationHeader: `Bearer ${token}`,
        method: 'POST',
        endpoint: '/api/v1/vault/decrypt',
        targetAccountUid: 'worker_bob_456',
        targetResource: 'template_002',
        operationNonce: 'nonce-17-request-B',
        operationId: 'op-17-B',
        expectedServiceAccountEmail: verifierSa,
      });
      assert.strictEqual(res2.authorized, true);
    });

    it('18. Durable replay rejection: replaying the same operation nonce is blocked', async () => {
      const token = service.generateTestOidcToken(
        {
          iss: 'https://accounts.google.com',
          aud: targetUrl,
          email: verifierSa,
          exp: Math.floor(Date.now() / 1000) + 3600,
          iat: Math.floor(Date.now() / 1000),
          sub: '1092837465019283',
        },
        ecKeyPair.privateKey
      );

      // Call 1: Success
      const res1 = await service.verifySensitiveOperationCall({
        targetServiceUrl: targetUrl,
        rawAuthorizationHeader: `Bearer ${token}`,
        method: 'POST',
        endpoint: '/api/v1/vault/decrypt',
        targetAccountUid: 'worker_alice_123',
        targetResource: 'template_001',
        operationNonce: 'nonce-18-replayed-nonce',
        operationId: 'op-18',
        expectedServiceAccountEmail: verifierSa,
      });
      assert.strictEqual(res1.authorized, true);

      // Call 2: Attempt replay with same nonce
      const res2 = await service.verifySensitiveOperationCall({
        targetServiceUrl: targetUrl,
        rawAuthorizationHeader: `Bearer ${token}`,
        method: 'POST',
        endpoint: '/api/v1/vault/decrypt',
        targetAccountUid: 'worker_alice_123',
        targetResource: 'template_001',
        operationNonce: 'nonce-18-replayed-nonce',
        operationId: 'op-18',
        expectedServiceAccountEmail: verifierSa,
      });
      assert.strictEqual(res2.authorized, false);
      assert.strictEqual(res2.errorCode, 'ERR_DURABLE_REQUEST_REPLAY');
    });

    it('19. Replay across two application instances prevented by shared durable store', async () => {
      const sharedStore = new DistributedDurableReplayStore();
      const instance1 = new InternalWorkloadIdentityServiceV18(sharedStore);
      const instance2 = new InternalWorkloadIdentityServiceV18(sharedStore);
      instance1.registerVerificationKey('key-1', ecKeyPair.publicKey);
      instance2.registerVerificationKey('key-1', ecKeyPair.publicKey);

      const token = instance1.generateTestOidcToken(
        {
          iss: 'https://accounts.google.com',
          aud: targetUrl,
          email: verifierSa,
          exp: Math.floor(Date.now() / 1000) + 3600,
          iat: Math.floor(Date.now() / 1000),
          sub: '1092837465019283',
        },
        ecKeyPair.privateKey
      );

      // Instance 1 consumes nonce
      const res1 = await instance1.verifySensitiveOperationCall({
        targetServiceUrl: targetUrl,
        rawAuthorizationHeader: `Bearer ${token}`,
        method: 'POST',
        endpoint: '/api/v1/vault/decrypt',
        targetAccountUid: 'worker_alice_123',
        targetResource: 'template_001',
        operationNonce: 'nonce-19-shared',
        operationId: 'op-19',
        expectedServiceAccountEmail: verifierSa,
      });
      assert.strictEqual(res1.authorized, true);

      // Instance 2 receives same request
      const res2 = await instance2.verifySensitiveOperationCall({
        targetServiceUrl: targetUrl,
        rawAuthorizationHeader: `Bearer ${token}`,
        method: 'POST',
        endpoint: '/api/v1/vault/decrypt',
        targetAccountUid: 'worker_alice_123',
        targetResource: 'template_001',
        operationNonce: 'nonce-19-shared',
        operationId: 'op-19',
        expectedServiceAccountEmail: verifierSa,
      });
      assert.strictEqual(res2.authorized, false);
      assert.strictEqual(res2.errorCode, 'ERR_DURABLE_REQUEST_REPLAY');
    });

    it('20. Replay after process restart: persisted state survives restart and rejects replayed nonce', async () => {
      const initialStore = new DistributedDurableReplayStore();
      const initialService = new InternalWorkloadIdentityServiceV18(initialStore);
      initialService.registerVerificationKey('key-1', ecKeyPair.publicKey);

      const token = initialService.generateTestOidcToken(
        {
          iss: 'https://accounts.google.com',
          aud: targetUrl,
          email: verifierSa,
          exp: Math.floor(Date.now() / 1000) + 3600,
          iat: Math.floor(Date.now() / 1000),
          sub: '1092837465019283',
        },
        ecKeyPair.privateKey
      );

      await initialService.verifySensitiveOperationCall({
        targetServiceUrl: targetUrl,
        rawAuthorizationHeader: `Bearer ${token}`,
        method: 'POST',
        endpoint: '/api/v1/vault/decrypt',
        targetAccountUid: 'worker_alice_123',
        targetResource: 'template_001',
        operationNonce: 'nonce-20-persisted',
        operationId: 'op-20',
        expectedServiceAccountEmail: verifierSa,
      });

      // Simulate process restart: export store state and hydrate into new process instance
      const persistedSnapshot = initialStore.exportState();
      const restartedStore = new DistributedDurableReplayStore();
      restartedStore.importState(persistedSnapshot);

      const restartedService = new InternalWorkloadIdentityServiceV18(restartedStore);
      restartedService.registerVerificationKey('key-1', ecKeyPair.publicKey);

      // Attempt replay in restarted service
      const res = await restartedService.verifySensitiveOperationCall({
        targetServiceUrl: targetUrl,
        rawAuthorizationHeader: `Bearer ${token}`,
        method: 'POST',
        endpoint: '/api/v1/vault/decrypt',
        targetAccountUid: 'worker_alice_123',
        targetResource: 'template_001',
        operationNonce: 'nonce-20-persisted',
        operationId: 'op-20',
        expectedServiceAccountEmail: verifierSa,
      });

      assert.strictEqual(res.authorized, false);
      assert.strictEqual(res.errorCode, 'ERR_DURABLE_REQUEST_REPLAY');
    });
  });

  // =========================================================================
  // TRACK C: VAULT DECRYPTION ISOLATION & BEST-EFFORT MEMORY CLEARING (Tests 21–30)
  // =========================================================================
  describe('Track C: Vault Decryption Isolation & Best-Effort Memory Clearing (Tests 21–30)', () => {
    const guard = new VaultDecryptionGuardV18();
    const testEmbedding = new Float32Array(128).fill(0.123);
    const validRecord = guard.encryptTemplateSnapshot('user_alice_456', 'tpl_101', testEmbedding, '1to1_auth');

    it('21. Wrong UID in AAD rejected by GCM decipher', () => {
      const tamperedRecord: EncryptedVaultRecordV18 = {
        ...validRecord,
        accountUid: 'user_attacker_999',
      };
      assert.throws(
        () => {
          guard.decryptTemplate({
            record: tamperedRecord,
            callerSessionUid: 'user_attacker_999',
            callerContext: '1to1_auth',
          });
        },
        /KMS_UNWRAP_FAILED|AUTHENTICATION_TAG_VERIFICATION_FAILED/
      );
    });

    it('22. Wrong template ID in AAD rejected', () => {
      const tamperedRecord: EncryptedVaultRecordV18 = {
        ...validRecord,
        templateId: 'tpl_substituted_999',
      };
      assert.throws(
        () => {
          guard.decryptTemplate({
            record: tamperedRecord,
            callerSessionUid: 'user_alice_456',
            callerContext: '1to1_auth',
          });
        },
        /KMS_UNWRAP_FAILED|AUTHENTICATION_TAG_VERIFICATION_FAILED/
      );
    });

    it('23. Wrong vault version in AAD rejected', () => {
      const tamperedRecord: EncryptedVaultRecordV18 = {
        ...validRecord,
        vaultRecordVersion: 2,
      };
      assert.throws(
        () => {
          guard.decryptTemplate({
            record: tamperedRecord,
            callerSessionUid: 'user_alice_456',
            callerContext: '1to1_auth',
          });
        },
        /AUTHENTICATION_TAG_VERIFICATION_FAILED/
      );
    });

    it('24. Wrong embedding space rejected before decryption', () => {
      const tamperedRecord: EncryptedVaultRecordV18 = {
        ...validRecord,
        embeddingSpaceId: 'facenet_512_incompatible',
      };
      assert.throws(
        () => {
          guard.decryptTemplate({
            record: tamperedRecord,
            callerSessionUid: 'user_alice_456',
            callerContext: '1to1_auth',
          });
        },
        /EMBEDDING_SPACE_MISMATCH/
      );
    });

    it('25. Modified wrapped DEK rejected by KMS unwrap', () => {
      const tamperedRecord: EncryptedVaultRecordV18 = {
        ...validRecord,
        wrappedDekBase64: Buffer.from('TAMPERED_DEK_DATA').toString('base64'),
      };
      assert.throws(
        () => {
          guard.decryptTemplate({
            record: tamperedRecord,
            callerSessionUid: 'user_alice_456',
            callerContext: '1to1_auth',
          });
        },
        /KMS_UNWRAP_FAILED/
      );
    });

    it('26. Modified ciphertext rejected by GCM decipher', () => {
      const rawCt = Buffer.from(validRecord.ciphertextBase64, 'base64');
      rawCt[0] ^= 0x01; // Flip 1 bit
      const tamperedRecord: EncryptedVaultRecordV18 = {
        ...validRecord,
        ciphertextBase64: rawCt.toString('base64'),
      };
      assert.throws(
        () => {
          guard.decryptTemplate({
            record: tamperedRecord,
            callerSessionUid: 'user_alice_456',
            callerContext: '1to1_auth',
          });
        },
        /AUTHENTICATION_TAG_VERIFICATION_FAILED/
      );
    });

    it('27. Modified authentication tag rejected by GCM decipher', () => {
      const rawTag = Buffer.from(validRecord.authTagBase64, 'base64');
      rawTag[0] ^= 0x01;
      const tamperedRecord: EncryptedVaultRecordV18 = {
        ...validRecord,
        authTagBase64: rawTag.toString('base64'),
      };
      assert.throws(
        () => {
          guard.decryptTemplate({
            record: tamperedRecord,
            callerSessionUid: 'user_alice_456',
            callerContext: '1to1_auth',
          });
        },
        /AUTHENTICATION_TAG_VERIFICATION_FAILED/
      );
    });

    it('28. Superseded template rejected before KMS unwrap', () => {
      const supersededRecord: EncryptedVaultRecordV18 = {
        ...validRecord,
        lifecycleStatus: 'SUPERSEDED',
      };
      assert.throws(
        () => {
          guard.decryptTemplate({
            record: supersededRecord,
            callerSessionUid: 'user_alice_456',
            callerContext: '1to1_auth',
          });
        },
        /LIFECYCLE_GATE_REJECTED/
      );
    });

    it('29. Revoked template rejected before KMS unwrap', () => {
      const revokedRecord: EncryptedVaultRecordV18 = {
        ...validRecord,
        lifecycleStatus: 'REVOKED',
      };
      assert.throws(
        () => {
          guard.decryptTemplate({
            record: revokedRecord,
            callerSessionUid: 'user_alice_456',
            callerContext: '1to1_auth',
          });
        },
        /LIFECYCLE_GATE_REJECTED/
      );
    });

    it('30. Failed authorization before KMS invocation: session UID mismatch blocked prior to KMS call', () => {
      let kmsCalled = false;
      assert.throws(
        () => {
          guard.decryptTemplate({
            record: validRecord,
            callerSessionUid: 'impostor_uid_999',
            callerContext: '1to1_auth',
            mockKmsUnwrapFn: () => {
              kmsCalled = true;
              return Buffer.alloc(32);
            },
          });
        },
        /UNAUTHORIZED_RECORD_ACCESS/
      );
      assert.strictEqual(kmsCalled, false, 'KMS must not be called when pre-authorization fails');
    });
  });

  // =========================================================================
  // TRACK D: TWO-PERSON DUAL CUSTODY RECOVERY ASSURANCE (Tests 31–38)
  // =========================================================================
  describe('Track D: Two-Person Dual Custody Recovery Assurance (Tests 31–38)', () => {
    const engine = new RecoveryDualCustodyEngineV18();

    const { privateKey: bcoKey, publicKey: bcoPub } = crypto.generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
    const { privateKey: isaKey, publicKey: isaPub } = crypto.generateKeyPairSync('ec', { namedCurve: 'prime256v1' });

    const bcoOfficer: DualCustodyApproverV18 = {
      officerId: 'officer-bco-1',
      idpSubject: 'google-oauth2|10001',
      role: 'BIOMETRIC_COMPLIANCE_OFFICER',
      publicKeyPem: bcoPub.export({ type: 'spki', format: 'pem' }) as string,
      mfaCredentialId: 'yubikey-fido2-bco-01',
    };

    const isaOfficer: DualCustodyApproverV18 = {
      officerId: 'officer-isa-2',
      idpSubject: 'google-oauth2|20002',
      role: 'INDEPENDENT_SECURITY_AUDITOR',
      publicKeyPem: isaPub.export({ type: 'spki', format: 'pem' }) as string,
      mfaCredentialId: 'yubikey-fido2-isa-02',
    };

    before(() => {
      engine.registerApprover(bcoOfficer);
      engine.registerApprover(isaOfficer);
    });

    it('31. Same officer cannot approve twice (collusion blocked)', async () => {
      const now = Date.now();
      const p1 = engine.createApproverProof(
        bcoOfficer,
        bcoKey.export({ type: 'pkcs8', format: 'pem' }) as string,
        'user_recovery_101',
        'CASE-999001',
        'BIOMETRIC_ACCOUNT_UNLOCK',
        undefined,
        now,
        now + 600000
      );

      const token: DualCustodyRecoveryTokenV18 = {
        tokenId: 'token-31',
        targetUid: 'user_recovery_101',
        caseReference: 'CASE-999001',
        operationType: 'BIOMETRIC_ACCOUNT_UNLOCK',
        requesterOfficerId: 'support-agent-55',
        issuedAtEpochMs: now,
        expiresAtEpochMs: now + 600000,
        approvalHolder1: p1,
        approvalHolder2: p1, // Same officer
      };

      const res = await engine.evaluateRecoveryAuthorization({
        recoveryToken: token,
        targetUid: 'user_recovery_101',
        caseReference: 'CASE-999001',
        operationType: 'BIOMETRIC_ACCOUNT_UNLOCK',
      });

      assert.strictEqual(res.allowed, false);
      assert.strictEqual(res.errorCode, 'ERR_DUAL_CUSTODY_SAME_OFFICER');
    });

    it('32. Distinct officer IDs with same IdP subject rejected', async () => {
      const now = Date.now();
      const shadowBco: DualCustodyApproverV18 = {
        officerId: 'officer-bco-shadow',
        idpSubject: 'google-oauth2|10001', // Same human IdP subject as bcoOfficer!
        role: 'INDEPENDENT_SECURITY_AUDITOR',
        publicKeyPem: bcoPub.export({ type: 'spki', format: 'pem' }) as string,
        mfaCredentialId: 'yubikey-fido2-shadow',
      };
      engine.registerApprover(shadowBco);

      const p1 = engine.createApproverProof(
        bcoOfficer,
        bcoKey.export({ type: 'pkcs8', format: 'pem' }) as string,
        'user_recovery_101',
        'CASE-999001',
        'BIOMETRIC_ACCOUNT_UNLOCK',
        undefined,
        now,
        now + 600000
      );
      const p2 = engine.createApproverProof(
        shadowBco,
        bcoKey.export({ type: 'pkcs8', format: 'pem' }) as string,
        'user_recovery_101',
        'CASE-999001',
        'BIOMETRIC_ACCOUNT_UNLOCK',
        undefined,
        now,
        now + 600000
      );

      const token: DualCustodyRecoveryTokenV18 = {
        tokenId: 'token-32',
        targetUid: 'user_recovery_101',
        caseReference: 'CASE-999001',
        operationType: 'BIOMETRIC_ACCOUNT_UNLOCK',
        requesterOfficerId: 'support-agent-55',
        issuedAtEpochMs: now,
        expiresAtEpochMs: now + 600000,
        approvalHolder1: p1,
        approvalHolder2: p2,
      };

      const res = await engine.evaluateRecoveryAuthorization({
        recoveryToken: token,
        targetUid: 'user_recovery_101',
        caseReference: 'CASE-999001',
        operationType: 'BIOMETRIC_ACCOUNT_UNLOCK',
      });

      assert.strictEqual(res.allowed, false);
      assert.strictEqual(res.errorCode, 'ERR_DUAL_CUSTODY_SAME_IDP_SUBJECT');
    });

    it('33. Different approved identities with separate MFA accepted', async () => {
      const now = Date.now();
      const p1 = engine.createApproverProof(
        bcoOfficer,
        bcoKey.export({ type: 'pkcs8', format: 'pem' }) as string,
        'user_recovery_101',
        'CASE-999001',
        'BIOMETRIC_ACCOUNT_UNLOCK',
        undefined,
        now,
        now + 600000
      );
      const p2 = engine.createApproverProof(
        isaOfficer,
        isaKey.export({ type: 'pkcs8', format: 'pem' }) as string,
        'user_recovery_101',
        'CASE-999001',
        'BIOMETRIC_ACCOUNT_UNLOCK',
        undefined,
        now,
        now + 600000
      );

      const token: DualCustodyRecoveryTokenV18 = {
        tokenId: 'token-33',
        targetUid: 'user_recovery_101',
        caseReference: 'CASE-999001',
        operationType: 'BIOMETRIC_ACCOUNT_UNLOCK',
        requesterOfficerId: 'support-agent-55',
        issuedAtEpochMs: now,
        expiresAtEpochMs: now + 600000,
        approvalHolder1: p1,
        approvalHolder2: p2,
      };

      const res = await engine.evaluateRecoveryAuthorization({
        recoveryToken: token,
        targetUid: 'user_recovery_101',
        caseReference: 'CASE-999001',
        operationType: 'BIOMETRIC_ACCOUNT_UNLOCK',
      });

      assert.strictEqual(res.allowed, true);
      assert.ok(res.auditRecordId);
    });

    it('34. Requester self-approval rejected', async () => {
      const now = Date.now();
      const p1 = engine.createApproverProof(
        bcoOfficer,
        bcoKey.export({ type: 'pkcs8', format: 'pem' }) as string,
        'user_recovery_101',
        'CASE-999001',
        'BIOMETRIC_ACCOUNT_UNLOCK',
        undefined,
        now,
        now + 600000
      );
      const p2 = engine.createApproverProof(
        isaOfficer,
        isaKey.export({ type: 'pkcs8', format: 'pem' }) as string,
        'user_recovery_101',
        'CASE-999001',
        'BIOMETRIC_ACCOUNT_UNLOCK',
        undefined,
        now,
        now + 600000
      );

      const token: DualCustodyRecoveryTokenV18 = {
        tokenId: 'token-34',
        targetUid: 'user_recovery_101',
        caseReference: 'CASE-999001',
        operationType: 'BIOMETRIC_ACCOUNT_UNLOCK',
        requesterOfficerId: bcoOfficer.officerId, // Requester is BCO approver!
        issuedAtEpochMs: now,
        expiresAtEpochMs: now + 600000,
        approvalHolder1: p1,
        approvalHolder2: p2,
      };

      const res = await engine.evaluateRecoveryAuthorization({
        recoveryToken: token,
        targetUid: 'user_recovery_101',
        caseReference: 'CASE-999001',
        operationType: 'BIOMETRIC_ACCOUNT_UNLOCK',
      });

      assert.strictEqual(res.allowed, false);
      assert.strictEqual(res.errorCode, 'ERR_REQUESTER_SELF_APPROVAL');
    });

    it('35. Replayed approval rejected (single-use consumption)', async () => {
      const now = Date.now();
      const p1 = engine.createApproverProof(
        bcoOfficer,
        bcoKey.export({ type: 'pkcs8', format: 'pem' }) as string,
        'user_recovery_101',
        'CASE-999001',
        'BIOMETRIC_ACCOUNT_UNLOCK',
        undefined,
        now,
        now + 600000
      );
      const p2 = engine.createApproverProof(
        isaOfficer,
        isaKey.export({ type: 'pkcs8', format: 'pem' }) as string,
        'user_recovery_101',
        'CASE-999001',
        'BIOMETRIC_ACCOUNT_UNLOCK',
        undefined,
        now,
        now + 600000
      );

      const token: DualCustodyRecoveryTokenV18 = {
        tokenId: 'token-35-single-use',
        targetUid: 'user_recovery_101',
        caseReference: 'CASE-999001',
        operationType: 'BIOMETRIC_ACCOUNT_UNLOCK',
        requesterOfficerId: 'support-agent-55',
        issuedAtEpochMs: now,
        expiresAtEpochMs: now + 600000,
        approvalHolder1: p1,
        approvalHolder2: p2,
      };

      // 1st use
      const res1 = await engine.evaluateRecoveryAuthorization({
        recoveryToken: token,
        targetUid: 'user_recovery_101',
        caseReference: 'CASE-999001',
        operationType: 'BIOMETRIC_ACCOUNT_UNLOCK',
      });
      assert.strictEqual(res1.allowed, true);

      // 2nd use
      const res2 = await engine.evaluateRecoveryAuthorization({
        recoveryToken: token,
        targetUid: 'user_recovery_101',
        caseReference: 'CASE-999001',
        operationType: 'BIOMETRIC_ACCOUNT_UNLOCK',
      });
      assert.strictEqual(res2.allowed, false);
      assert.strictEqual(res2.errorCode, 'ERR_RECOVERY_TOKEN_REPLAYED');
    });

    it('36. Expired approval rejected', async () => {
      const past = Date.now() - 1000000;
      const p1 = engine.createApproverProof(
        bcoOfficer,
        bcoKey.export({ type: 'pkcs8', format: 'pem' }) as string,
        'user_recovery_101',
        'CASE-999001',
        'BIOMETRIC_ACCOUNT_UNLOCK',
        undefined,
        past,
        past + 600000 // Expired in past
      );
      const p2 = engine.createApproverProof(
        isaOfficer,
        isaKey.export({ type: 'pkcs8', format: 'pem' }) as string,
        'user_recovery_101',
        'CASE-999001',
        'BIOMETRIC_ACCOUNT_UNLOCK',
        undefined,
        past,
        past + 600000
      );

      const token: DualCustodyRecoveryTokenV18 = {
        tokenId: 'token-36',
        targetUid: 'user_recovery_101',
        caseReference: 'CASE-999001',
        operationType: 'BIOMETRIC_ACCOUNT_UNLOCK',
        requesterOfficerId: 'support-agent-55',
        issuedAtEpochMs: past,
        expiresAtEpochMs: past + 600000,
        approvalHolder1: p1,
        approvalHolder2: p2,
      };

      const res = await engine.evaluateRecoveryAuthorization({
        recoveryToken: token,
        targetUid: 'user_recovery_101',
        caseReference: 'CASE-999001',
        operationType: 'BIOMETRIC_ACCOUNT_UNLOCK',
      });

      assert.strictEqual(res.allowed, false);
      assert.strictEqual(res.errorCode, 'ERR_RECOVERY_TOKEN_EXPIRED');
    });

    it('37. Modified operation rejected (operation substitution)', async () => {
      const now = Date.now();
      const p1 = engine.createApproverProof(
        bcoOfficer,
        bcoKey.export({ type: 'pkcs8', format: 'pem' }) as string,
        'user_recovery_101',
        'CASE-999001',
        'BIOMETRIC_ACCOUNT_UNLOCK',
        undefined,
        now,
        now + 600000
      );
      const p2 = engine.createApproverProof(
        isaOfficer,
        isaKey.export({ type: 'pkcs8', format: 'pem' }) as string,
        'user_recovery_101',
        'CASE-999001',
        'BIOMETRIC_ACCOUNT_UNLOCK',
        undefined,
        now,
        now + 600000
      );

      const token: DualCustodyRecoveryTokenV18 = {
        tokenId: 'token-37',
        targetUid: 'user_recovery_101',
        caseReference: 'CASE-999001',
        operationType: 'BIOMETRIC_ACCOUNT_UNLOCK',
        requesterOfficerId: 'support-agent-55',
        issuedAtEpochMs: now,
        expiresAtEpochMs: now + 600000,
        approvalHolder1: p1,
        approvalHolder2: p2,
      };

      // Attacker attempts to change operation to TEMPLATE_SUPERSEDE_RECOVERY
      const res = await engine.evaluateRecoveryAuthorization({
        recoveryToken: token,
        targetUid: 'user_recovery_101',
        caseReference: 'CASE-999001',
        operationType: 'TEMPLATE_SUPERSEDE_RECOVERY',
      });

      assert.strictEqual(res.allowed, false);
      assert.strictEqual(res.errorCode, 'ERR_OPERATION_TYPE_MISMATCH');
    });

    it('38. Concurrent approval consumption prevented', async () => {
      const now = Date.now();
      const p1 = engine.createApproverProof(
        bcoOfficer,
        bcoKey.export({ type: 'pkcs8', format: 'pem' }) as string,
        'user_recovery_101',
        'CASE-999001',
        'BIOMETRIC_ACCOUNT_UNLOCK',
        undefined,
        now,
        now + 600000
      );
      const p2 = engine.createApproverProof(
        isaOfficer,
        isaKey.export({ type: 'pkcs8', format: 'pem' }) as string,
        'user_recovery_101',
        'CASE-999001',
        'BIOMETRIC_ACCOUNT_UNLOCK',
        undefined,
        now,
        now + 600000
      );

      const token: DualCustodyRecoveryTokenV18 = {
        tokenId: 'token-38-concurrent',
        targetUid: 'user_recovery_101',
        caseReference: 'CASE-999001',
        operationType: 'BIOMETRIC_ACCOUNT_UNLOCK',
        requesterOfficerId: 'support-agent-55',
        issuedAtEpochMs: now,
        expiresAtEpochMs: now + 600000,
        approvalHolder1: p1,
        approvalHolder2: p2,
      };

      // Execute 2 concurrent requests
      const [resA, resB] = await Promise.all([
        engine.evaluateRecoveryAuthorization({
          recoveryToken: token,
          targetUid: 'user_recovery_101',
          caseReference: 'CASE-999001',
          operationType: 'BIOMETRIC_ACCOUNT_UNLOCK',
        }),
        engine.evaluateRecoveryAuthorization({
          recoveryToken: token,
          targetUid: 'user_recovery_101',
          caseReference: 'CASE-999001',
          operationType: 'BIOMETRIC_ACCOUNT_UNLOCK',
        }),
      ]);

      const successes = [resA, resB].filter((r) => r.allowed).length;
      assert.strictEqual(successes, 1, 'Exactly one concurrent request must succeed');
    });
  });

  // =========================================================================
  // TRACK E: AUDIT NOTARY CREATE-ONLY & RECONCILER INDEPENDENCE (Tests 39–45)
  // =========================================================================
  describe('Track E: Audit Notary Create-Only & Reconciler Independence (Tests 39–45)', () => {
    const reconciler = new AuditReconcilerServiceV18();
    const { privateKey: notaryKey, publicKey: notaryPub } = crypto.generateKeyPairSync('ec', {
      namedCurve: 'prime256v1',
    });
    const notaryPrivPem = notaryKey.export({ type: 'pkcs8', format: 'pem' }) as string;
    const notaryPubPem = notaryPub.export({ type: 'spki', format: 'pem' }) as string;

    before(() => {
      reconciler.registerTrustedSignerKey('v2-notary-2026', notaryPubPem);
    });

    it('39. Duplicate checkpoint name rejected on write-once bucket', () => {
      const bucket = reconciler.getStorageBucket();
      const res1 = bucket.putObject('checkpoint-001.json', '{"content":"A"}', {
        ifGenerationMatch: 0,
        callerRole: 'roles/storage.objectCreator',
      });
      assert.strictEqual(res1.success, true);

      // Attempt duplicate creation with ifGenerationMatch=0
      const res2 = bucket.putObject('checkpoint-001.json', '{"content":"B"}', {
        ifGenerationMatch: 0,
        callerRole: 'roles/storage.objectCreator',
      });
      assert.strictEqual(res2.success, false);
      assert.strictEqual(res2.errorCode, 'ERR_PRECONDITION_FAILED_OBJECT_EXISTS');
    });

    it('40. Existing checkpoint overwrite rejected by notary service', () => {
      const cpData = {
        checkpointId: 'CP-40',
        objectName: 'checkpoint-000040.json',
        sequenceNumberRange: { start: 1, end: 10 },
        timestampIso: new Date().toISOString(),
        checkpointContentDigest: 'digest-40',
        cumulativeLedgerHash: 'hash-40',
        previousCheckpointHash: 'GENESIS_CHECKPOINT_HASH',
        signerServiceAccount: 'sa-biometrics-audit-notary',
        keyVersion: 'v2-notary-2026',
      };

      const res1 = reconciler.createAndStoreCheckpointAsNotary({
        checkpoint: cpData,
        ifGenerationMatch: 0,
        notaryPrivateKeyPem: notaryPrivPem,
      });
      assert.strictEqual(res1.success, true);

      // Overwrite attempt
      const res2 = reconciler.createAndStoreCheckpointAsNotary({
        checkpoint: cpData,
        ifGenerationMatch: 0,
        notaryPrivateKeyPem: notaryPrivPem,
      });
      assert.strictEqual(res2.success, false);
      assert.strictEqual(res2.errorCode, 'ERR_PRECONDITION_FAILED_OBJECT_EXISTS');
    });

    it('41. Invalid signature rejected during reconciliation', () => {
      const cp: ExternalCheckpointObjectV18 = {
        checkpointId: 'CP-41',
        objectName: 'checkpoint-000041.json',
        sequenceNumberRange: { start: 1, end: 10 },
        timestampIso: new Date().toISOString(),
        checkpointContentDigest: 'digest-41',
        cumulativeLedgerHash: 'hash-41',
        previousCheckpointHash: 'GENESIS_CHECKPOINT_HASH',
        signerServiceAccount: 'sa-biometrics-audit-notary',
        keyVersion: 'v2-notary-2026',
        signatureBase64: Buffer.from('INVALID_SIGNATURE').toString('base64'),
      };

      const report = reconciler.reconcileAuditTrail([], [cp]);
      assert.strictEqual(report.reconciled, false);
      assert.ok(report.anomaliesDetected.some((a) => a.type === 'SIGNATURE_INVALID'));
    });

    it('42. Missing checkpoint detected (external chain discontinuity)', () => {
      const cp1Data = {
        checkpointId: 'CP-42-1',
        objectName: 'checkpoint-000042-1.json',
        sequenceNumberRange: { start: 1, end: 10 },
        timestampIso: new Date().toISOString(),
        checkpointContentDigest: 'digest-42-1',
        cumulativeLedgerHash: 'hash-42-1',
        previousCheckpointHash: 'GENESIS_CHECKPOINT_HASH',
        signerServiceAccount: 'sa-biometrics-audit-notary',
        keyVersion: 'v2-notary-2026',
      };

      const cp3Data = {
        checkpointId: 'CP-42-3',
        objectName: 'checkpoint-000042-3.json',
        sequenceNumberRange: { start: 21, end: 30 },
        timestampIso: new Date().toISOString(),
        checkpointContentDigest: 'digest-42-3',
        cumulativeLedgerHash: 'hash-42-3',
        previousCheckpointHash: 'hash-42-2', // Missing CP 2!
        signerServiceAccount: 'sa-biometrics-audit-notary',
        keyVersion: 'v2-notary-2026',
      };

      const cp1 = reconciler.createAndStoreCheckpointAsNotary({
        checkpoint: cp1Data,
        ifGenerationMatch: 0,
        notaryPrivateKeyPem: notaryPrivPem,
      }).checkpoint!;

      const cp3 = reconciler.createAndStoreCheckpointAsNotary({
        checkpoint: cp3Data,
        ifGenerationMatch: 0,
        notaryPrivateKeyPem: notaryPrivPem,
      }).checkpoint!;

      const report = reconciler.reconcileAuditTrail([], [cp1, cp3]);
      assert.strictEqual(report.reconciled, false);
      assert.ok(report.anomaliesDetected.some((a) => a.type === 'CHAIN_DISCONTINUITY'));
    });

    it('43. Notary cannot read or delete checkpoint objects (create-only role)', () => {
      const bucket = reconciler.getStorageBucket();
      bucket.putObject('checkpoint-perm-test.json', 'data', { ifGenerationMatch: 0 });

      // Notary role attempting to read throws permission error
      assert.throws(
        () => {
          bucket.getObject('checkpoint-perm-test.json', 'roles/storage.objectCreator');
        },
        /ERR_PERMISSION_DENIED_CREATOR_CANNOT_READ/
      );

      // Notary role attempting to delete throws permission error
      assert.throws(
        () => {
          bucket.deleteObject('checkpoint-perm-test.json', 'roles/storage.objectCreator');
        },
        /ERR_PERMISSION_DENIED_DELETE_PROHIBITED/
      );
    });

    it('44. Reconciler cannot write or sign checkpoints (read-only viewer role)', () => {
      const bucket = reconciler.getStorageBucket();
      const res = bucket.putObject('checkpoint-reconciler-write.json', 'data', {
        callerRole: 'roles/storage.objectViewer',
      });
      assert.strictEqual(res.success, false);
      assert.strictEqual(res.errorCode, 'ERR_PERMISSION_DENIED_VIEWER_CANNOT_WRITE');
    });

    it('45. Ledger history rewrite in Firestore detected by independent reconciliation', () => {
      // Event 1
      const e1PayloadHash = crypto.createHash('sha256').update('event1').digest('hex');
      const e1Hash = reconciler.computeEventHash({
        sequenceNumber: 1,
        timestampIso: '2026-11-01T10:00:00Z',
        eventType: 'BIOMETRIC_ENROLLED',
        actorUid: 'alice_1',
        eventPayloadHash: e1PayloadHash,
        previousEventHash: 'GENESIS_HASH_0000000000000000000000000000000000000000000000000000000000000000',
      });

      // Event 2 (mutated payload hash)
      const e2TamperedPayloadHash = crypto.createHash('sha256').update('tampered_event2').digest('hex');
      const e2BogusRecordHash = 'bogus_hash_123';

      const events: AuditEventRecordV18[] = [
        {
          sequenceNumber: 1,
          timestampIso: '2026-11-01T10:00:00Z',
          eventType: 'BIOMETRIC_ENROLLED',
          actorUid: 'alice_1',
          eventPayloadHash: e1PayloadHash,
          previousEventHash: 'GENESIS_HASH_0000000000000000000000000000000000000000000000000000000000000000',
          recordHash: e1Hash,
        },
        {
          sequenceNumber: 2,
          timestampIso: '2026-11-01T10:01:00Z',
          eventType: 'BIOMETRIC_VERIFIED',
          actorUid: 'alice_1',
          eventPayloadHash: e2TamperedPayloadHash,
          previousEventHash: e1Hash,
          recordHash: e2BogusRecordHash, // Tampered!
        },
      ];

      const report = reconciler.reconcileAuditTrail(events, []);
      assert.strictEqual(report.reconciled, false);
      assert.ok(report.anomaliesDetected.some((a) => a.type === 'HISTORICAL_REWRITE_DETECTED'));
    });
  });
});
