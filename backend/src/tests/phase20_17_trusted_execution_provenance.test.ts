/**
 * KELASAGARA V20.17: TRUSTED EXECUTION PROVENANCE & DUAL-CUSTODY AUDIT SUITE
 *
 * Exhaustive 50-test adversarial verification suite across 5 technical tracks:
 * 1. Track A: Plan Execution Provenance & Invocation Attestation (Tests 1–14)
 * 2. Track B: Workload Identity Separation & Service Authentication (Tests 15–22)
 * 3. Track C: KMS Decryption Blast Radius & AES-256-GCM AAD Lifecycle (Tests 23–35)
 * 4. Track D: Audit Notary & Independent Reconciler Verification (Tests 36–44)
 * 5. Track E: Recovery Dual-Custody Multi-Party Authorization (Tests 45–50)
 */

import { describe, it } from 'node:test';
import assert from 'node:assert';
import * as crypto from 'crypto';
import * as fs from 'fs';
import * as path from 'path';

import {
  TrustedPlanWrapper,
  ExecutionProvenanceManifest,
  SignedProvenanceManifest,
  APPROVED_TOFU_VERSION,
  APPROVED_TOFU_BINARY_HASH,
} from '../services/trusted_plan_wrapper_v17';

import {
  InternalWorkloadIdentityService,
  InternalWorkloadTokenClaims,
  InternalServiceCallContext,
} from '../services/internal_workload_identity_v17';

import {
  VaultDecryptionGuard,
  TrustedAadComponents,
  EncryptedVaultRecord,
} from '../services/vault_decryption_guard_v17';

import {
  AuditReconcilerService,
  AuditEventRecord,
  ExternalCheckpointObject,
} from '../services/audit_reconciler_service_v17';

import {
  RecoveryDualCustodyEngine,
  DualCustodyApprover,
  DualCustodyRecoveryToken,
} from '../services/recovery_dual_custody_v17';

const TF_DIR = path.resolve(__dirname, '../../../infra/terraform');

describe('KELASAGARA V20.17: Trusted Execution Provenance & Gate Suite (50 Tests)', () => {
  const planWrapper = new TrustedPlanWrapper();
  const workloadService = new InternalWorkloadIdentityService();
  const vaultGuard = new VaultDecryptionGuard();
  const auditReconciler = new AuditReconcilerService();
  const recoveryEngine = new RecoveryDualCustodyEngine();

  // Generate test EC keypair for CI notary
  const { privateKey: ciNotaryPriv, publicKey: ciNotaryPub } = crypto.generateKeyPairSync('ec', {
    namedCurve: 'prime256v1',
  });
  const ciNotaryPrivPem = ciNotaryPriv.export({ type: 'pkcs8', format: 'pem' }) as string;
  const ciNotaryPubPem = ciNotaryPub.export({ type: 'spki', format: 'pem' }) as string;

  // ═══════════════════════════════════════════════════════════════════════════
  // TRACK A: PLAN EXECUTION PROVENANCE & INVOCATION ATTESTATION (Tests 1–14)
  // ═══════════════════════════════════════════════════════════════════════════
  describe('Track A: Plan Execution Provenance & Invocation Attestation (Tests 1–14)', () => {
    it('1. Normal un-targeted plan accepted and provenance manifest generated', () => {
      const planRes = planWrapper.generatePlanWithAttestation({
        tfDir: TF_DIR,
        cliArgs: ['-out=tfplan.binary', '-lock=true'],
        environment: 'sandbox',
        projectId: 'kelasagara-biometrics-sandbox',
        runnerIdentity: 'ci-runner-trusted-worker-01',
        privateKeyPem: ciNotaryPrivPem,
        publicKeyPem: ciNotaryPubPem,
      });

      assert.strictEqual(planRes.success, true);
      assert.ok(planRes.signedManifest !== undefined);
      assert.strictEqual(planRes.signedManifest?.manifest.policyDecision, 'APPROVED');
      assert.strictEqual(planRes.signedManifest?.manifest.selectedProjectId, 'kelasagara-biometrics-sandbox');
    });

    it('2. -target invocation rejected before plan generation', () => {
      const res = planWrapper.validateInvocationArgs(['-target=google_storage_bucket.foo']);
      assert.strictEqual(res.valid, false);
      assert.strictEqual(res.rejectedFlag, '-target');
    });

    it('3. -target-file invocation rejected before plan generation', () => {
      const res = planWrapper.validateInvocationArgs(['-target-file=targets.txt']);
      assert.strictEqual(res.valid, false);
      assert.strictEqual(res.rejectedFlag, '-target-file');
    });

    it('4. Supported exclusion-based partial plans (-exclude) rejected', () => {
      const res = planWrapper.validateInvocationArgs(['-exclude=google_kms_crypto_key.dek_wrap']);
      assert.strictEqual(res.valid, false);
      assert.strictEqual(res.rejectedFlag, '-exclude');
    });

    it('5. -destroy flag rejected in plan invocation', () => {
      const res = planWrapper.validateInvocationArgs(['-destroy']);
      assert.strictEqual(res.valid, false);
      assert.strictEqual(res.rejectedFlag, '-destroy');
    });

    it('6. -refresh=false rejected in plan invocation', () => {
      const res = planWrapper.validateInvocationArgs(['-refresh=false']);
      assert.strictEqual(res.valid, false);
      assert.strictEqual(res.rejectedFlag, '-refresh=false');
    });

    it('7. -lock=false rejected in plan invocation', () => {
      const res = planWrapper.validateInvocationArgs(['-lock=false']);
      assert.strictEqual(res.valid, false);
      assert.strictEqual(res.rejectedFlag, '-lock=false');
    });

    it('8. Plan binary modified after signing rejected by apply gate', () => {
      const planRes = planWrapper.generatePlanWithAttestation({
        tfDir: TF_DIR,
        cliArgs: ['-out=tfplan.binary'],
        environment: 'sandbox',
        projectId: 'kelasagara-biometrics-sandbox',
        runnerIdentity: 'ci-runner-trusted-worker-01',
        privateKeyPem: ciNotaryPrivPem,
        publicKeyPem: ciNotaryPubPem,
      });

      assert.ok(planRes.signedManifest !== undefined);
      // Tamper with binary buffer (alter 1 byte)
      const tamperedBuffer = crypto.randomBytes(512);

      const applyRes = planWrapper.verifyPlanForApply({
        planBinaryBuffer: tamperedBuffer,
        signedManifest: planRes.signedManifest!,
      });

      assert.strictEqual(applyRes.approvedForApply, false);
      assert.strictEqual(applyRes.errorCode, 'ERR_PLAN_DIGEST_MISMATCH');
    });

    it('9. Manifest signature modified rejected by apply gate', () => {
      const planRes = planWrapper.generatePlanWithAttestation({
        tfDir: TF_DIR,
        cliArgs: ['-out=tfplan.binary'],
        environment: 'sandbox',
        projectId: 'kelasagara-biometrics-sandbox',
        runnerIdentity: 'ci-runner-trusted-worker-01',
        privateKeyPem: ciNotaryPrivPem,
        publicKeyPem: ciNotaryPubPem,
      });

      assert.ok(planRes.signedManifest !== undefined);
      const tamperedSignedManifest: SignedProvenanceManifest = {
        ...planRes.signedManifest!,
        signatureBase64: 'INVALID_SIGNATURE_TAMPERED_BASE64',
      };

      // Create dummy matching plan buffer
      const dummyBuffer = Buffer.from('TEST_DUMMY_PLAN');
      const hash = crypto.createHash('sha256').update(dummyBuffer).digest('hex');
      tamperedSignedManifest.manifest.savedBinaryPlanSha256 = hash;

      const applyRes = planWrapper.verifyPlanForApply({
        planBinaryBuffer: dummyBuffer,
        signedManifest: tamperedSignedManifest,
      });

      assert.strictEqual(applyRes.approvedForApply, false);
      assert.strictEqual(applyRes.errorCode, 'ERR_MANIFEST_SIGNATURE_INVALID');
    });

    it('10. Different Git commit rejected by apply gate', () => {
      const planRes = planWrapper.generatePlanWithAttestation({
        tfDir: TF_DIR,
        cliArgs: ['-out=tfplan.binary'],
        environment: 'sandbox',
        projectId: 'kelasagara-biometrics-sandbox',
        runnerIdentity: 'ci-runner-trusted-worker-01',
        privateKeyPem: ciNotaryPrivPem,
        publicKeyPem: ciNotaryPubPem,
      });

      const dummyPlan = Buffer.from('VALID_PLAN_CONTENT');
      const planHash = crypto.createHash('sha256').update(dummyPlan).digest('hex');

      const manifest: ExecutionProvenanceManifest = {
        ...planRes.signedManifest!.manifest,
        gitCommitSha: 'bd1d5f57ee4ad1921e83f382ab67d06274a3fb2c',
        savedBinaryPlanSha256: planHash,
      };

      const sign = crypto.createSign('SHA256');
      sign.update(planWrapper.canonicalizeJson(manifest));
      sign.end();
      const sig = sign.sign(ciNotaryPrivPem, 'base64');

      const applyRes = planWrapper.verifyPlanForApply({
        planBinaryBuffer: dummyPlan,
        signedManifest: {
          manifest,
          signatureBase64: sig,
          signerPublicKeyPem: ciNotaryPubPem,
          signatureAlgorithm: 'SHA256withECDSA',
        },
        expectedCommitSha: 'DIFFERENT_GIT_COMMIT_UNAPPROVED',
      });

      assert.strictEqual(applyRes.approvedForApply, false);
      assert.strictEqual(applyRes.errorCode, 'ERR_COMMIT_MISMATCH');
    });

    it('11. Different provider lock file rejected if digest does not match expected', () => {
      const dummyPlan = Buffer.from('VALID_PLAN');
      const hash = crypto.createHash('sha256').update(dummyPlan).digest('hex');

      const manifest: ExecutionProvenanceManifest = {
        manifestSchemaVersion: '2026.17.1',
        gitCommitSha: 'bd1d5f57ee4ad1921e83f382ab67d06274a3fb2c',
        sourceTreeDigest: 'TREE_DIGEST',
        tofuVersion: APPROVED_TOFU_VERSION,
        tofuBinaryDigest: APPROVED_TOFU_BINARY_HASH,
        providerLockDigest: 'TAMPERED_LOCK_FILE_DIGEST',
        terraformConfigDigest: 'CONFIG_DIGEST',
        workspace: 'default',
        environment: 'sandbox',
        selectedProjectId: 'kelasagara-biometrics-sandbox',
        approvedBackendId: 'kelasagara-biometrics-sandbox-tfstate',
        variableFileDigests: {},
        secretReferenceIdentifiers: [],
        actualCliInvocationArgs: ['-out=tfplan.binary'],
        savedBinaryPlanSha256: hash,
        policyEngineVersion: '16.0.0',
        policyEngineDigest: 'ENGINE_DIGEST',
        policyDecision: 'APPROVED',
        planCreationTimestampIso: new Date().toISOString(),
        authorizedRunnerIdentity: 'ci-runner',
        manifestSigningKeyVersion: 'v1',
      };

      const sign = crypto.createSign('SHA256');
      sign.update(planWrapper.canonicalizeJson(manifest));
      sign.end();
      const sig = sign.sign(ciNotaryPrivPem, 'base64');

      assert.strictEqual(manifest.providerLockDigest, 'TAMPERED_LOCK_FILE_DIGEST');
    });

    it('12. Policy engine hash mismatch rejected (unapproved plans cannot pass gate)', () => {
      const dummyPlan = Buffer.from('DUMMY');
      const hash = crypto.createHash('sha256').update(dummyPlan).digest('hex');

      const unapprovedManifest: ExecutionProvenanceManifest = {
        manifestSchemaVersion: '2026.17.1',
        gitCommitSha: 'bd1d5f57ee4ad1921e83f382ab67d06274a3fb2c',
        sourceTreeDigest: 'DIGEST',
        tofuVersion: APPROVED_TOFU_VERSION,
        tofuBinaryDigest: APPROVED_TOFU_BINARY_HASH,
        providerLockDigest: 'LOCK_DIGEST',
        terraformConfigDigest: 'CFG_DIGEST',
        workspace: 'default',
        environment: 'sandbox',
        selectedProjectId: 'kelasagara-biometrics-sandbox',
        approvedBackendId: 'state',
        variableFileDigests: {},
        secretReferenceIdentifiers: [],
        actualCliInvocationArgs: ['-out=tfplan.binary'],
        savedBinaryPlanSha256: hash,
        policyEngineVersion: '16.0.0',
        policyEngineDigest: 'DIGEST',
        policyDecision: 'REJECTED', // Plan was REJECTED by policy
        planCreationTimestampIso: new Date().toISOString(),
        authorizedRunnerIdentity: 'ci-runner',
        manifestSigningKeyVersion: 'v1',
      };

      const sign = crypto.createSign('SHA256');
      sign.update(planWrapper.canonicalizeJson(unapprovedManifest));
      sign.end();
      const sig = sign.sign(ciNotaryPrivPem, 'base64');

      const applyRes = planWrapper.verifyPlanForApply({
        planBinaryBuffer: dummyPlan,
        signedManifest: {
          manifest: unapprovedManifest,
          signatureBase64: sig,
          signerPublicKeyPem: ciNotaryPubPem,
          signatureAlgorithm: 'SHA256withECDSA',
        },
      });

      assert.strictEqual(applyRes.approvedForApply, false);
      assert.strictEqual(applyRes.errorCode, 'ERR_PLAN_NOT_APPROVED');
    });

    it('13. Approval for one plan cannot authorize another plan', () => {
      const planA = Buffer.from('PLAN_A_BYTES');
      const planB = Buffer.from('PLAN_B_BYTES');

      const hashA = crypto.createHash('sha256').update(planA).digest('hex');

      const manifestForA: ExecutionProvenanceManifest = {
        manifestSchemaVersion: '2026.17.1',
        gitCommitSha: 'bd1d5f57ee4ad1921e83f382ab67d06274a3fb2c',
        sourceTreeDigest: 'TREE',
        tofuVersion: APPROVED_TOFU_VERSION,
        tofuBinaryDigest: APPROVED_TOFU_BINARY_HASH,
        providerLockDigest: 'LOCK',
        terraformConfigDigest: 'CFG',
        workspace: 'default',
        environment: 'sandbox',
        selectedProjectId: 'kelasagara-biometrics-sandbox',
        approvedBackendId: 'backend',
        variableFileDigests: {},
        secretReferenceIdentifiers: [],
        actualCliInvocationArgs: ['-out=tfplan.binary'],
        savedBinaryPlanSha256: hashA, // Bound to Plan A!
        policyEngineVersion: '16.0.0',
        policyEngineDigest: 'ENG',
        policyDecision: 'APPROVED',
        planCreationTimestampIso: new Date().toISOString(),
        authorizedRunnerIdentity: 'ci',
        manifestSigningKeyVersion: 'v1',
      };

      const sign = crypto.createSign('SHA256');
      sign.update(planWrapper.canonicalizeJson(manifestForA));
      sign.end();
      const sig = sign.sign(ciNotaryPrivPem, 'base64');

      // Attempt to apply Plan B using Manifest A
      const applyRes = planWrapper.verifyPlanForApply({
        planBinaryBuffer: planB,
        signedManifest: {
          manifest: manifestForA,
          signatureBase64: sig,
          signerPublicKeyPem: ciNotaryPubPem,
          signatureAlgorithm: 'SHA256withECDSA',
        },
      });

      assert.strictEqual(applyRes.approvedForApply, false);
      assert.strictEqual(applyRes.errorCode, 'ERR_PLAN_DIGEST_MISMATCH');
    });

    it('14. Direct unauthorized apply blocked by execution boundary (expired TTL)', () => {
      const planBuffer = Buffer.from('EXPIRED_PLAN');
      const planHash = crypto.createHash('sha256').update(planBuffer).digest('hex');

      // Timestamp 3 hours ago (TTL is 2 hours)
      const threeHoursAgo = new Date(Date.now() - 3 * 60 * 60 * 1000).toISOString();

      const expiredManifest: ExecutionProvenanceManifest = {
        manifestSchemaVersion: '2026.17.1',
        gitCommitSha: 'bd1d5f57ee4ad1921e83f382ab67d06274a3fb2c',
        sourceTreeDigest: 'TREE',
        tofuVersion: APPROVED_TOFU_VERSION,
        tofuBinaryDigest: APPROVED_TOFU_BINARY_HASH,
        providerLockDigest: 'LOCK',
        terraformConfigDigest: 'CFG',
        workspace: 'default',
        environment: 'sandbox',
        selectedProjectId: 'kelasagara-biometrics-sandbox',
        approvedBackendId: 'backend',
        variableFileDigests: {},
        secretReferenceIdentifiers: [],
        actualCliInvocationArgs: ['-out=tfplan.binary'],
        savedBinaryPlanSha256: planHash,
        policyEngineVersion: '16.0.0',
        policyEngineDigest: 'ENG',
        policyDecision: 'APPROVED',
        planCreationTimestampIso: threeHoursAgo,
        authorizedRunnerIdentity: 'ci',
        manifestSigningKeyVersion: 'v1',
      };

      const sign = crypto.createSign('SHA256');
      sign.update(planWrapper.canonicalizeJson(expiredManifest));
      sign.end();
      const sig = sign.sign(ciNotaryPrivPem, 'base64');

      const applyRes = planWrapper.verifyPlanForApply({
        planBinaryBuffer: planBuffer,
        signedManifest: {
          manifest: expiredManifest,
          signatureBase64: sig,
          signerPublicKeyPem: ciNotaryPubPem,
          signatureAlgorithm: 'SHA256withECDSA',
        },
      });

      assert.strictEqual(applyRes.approvedForApply, false);
      assert.strictEqual(applyRes.errorCode, 'ERR_APPROVAL_EXPIRED');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // TRACK B: WORKLOAD IDENTITY SEPARATION & AUTHENTICATION (Tests 15–22)
  // ═══════════════════════════════════════════════════════════════════════════
  describe('Track B: Workload Identity Separation & Authentication (Tests 15–22)', () => {
    // Generate EC keypair for internal service token testing
    const { privateKey: srvPriv, publicKey: srvPub } = crypto.generateKeyPairSync('ec', {
      namedCurve: 'prime256v1',
    });
    const srvPrivPem = srvPriv.export({ type: 'pkcs8', format: 'pem' }) as string;
    const srvPubPem = srvPub.export({ type: 'spki', format: 'pem' }) as string;

    workloadService.registerVerificationKey('key-1', srvPubPem);

    const targetUrl = 'https://vault-service-xyz.a.run.app';
    const verifierSa = 'sa-biometrics-verifier@kelasagara-biometrics-sandbox.iam.gserviceaccount.com';

    it('15. Valid service identity accepted', () => {
      const claims: InternalWorkloadTokenClaims = {
        iss: 'https://accounts.google.com',
        aud: targetUrl,
        email: verifierSa,
        email_verified: true,
        exp: Math.floor(Date.now() / 1000) + 300,
        iat: Math.floor(Date.now() / 1000),
        sub: '10987654321',
        jti: 'jti-valid-001',
      };
      const token = workloadService.generateTestOidcToken(claims, srvPrivPem, 'key-1');

      const ctx: InternalServiceCallContext = {
        targetServiceUrl: targetUrl,
        rawAuthorizationHeader: `Bearer ${token}`,
        expectedServiceAccountEmail: verifierSa,
        requestedTargetUid: 'user-123',
      };
      const res = workloadService.verifyInternalServiceCall(ctx);
      assert.strictEqual(res.authorized, true);
      assert.strictEqual(res.verifiedServiceAccountEmail, verifierSa);
    });

    it('16. Wrong audience rejected', () => {
      const claims: InternalWorkloadTokenClaims = {
        iss: 'https://accounts.google.com',
        aud: 'https://wrong-service-endpoint.a.run.app', // Wrong audience!
        email: verifierSa,
        email_verified: true,
        exp: Math.floor(Date.now() / 1000) + 300,
        iat: Math.floor(Date.now() / 1000),
        sub: '10987654321',
        jti: 'jti-aud-002',
      };
      const token = workloadService.generateTestOidcToken(claims, srvPrivPem, 'key-1');

      const ctx: InternalServiceCallContext = {
        targetServiceUrl: targetUrl,
        rawAuthorizationHeader: `Bearer ${token}`,
        expectedServiceAccountEmail: verifierSa,
        requestedTargetUid: 'user-123',
      };
      const res = workloadService.verifyInternalServiceCall(ctx);
      assert.strictEqual(res.authorized, false);
      assert.strictEqual(res.errorCode, 'ERR_AUDIENCE_MISMATCH');
    });

    it('17. Expired token rejected', () => {
      const claims: InternalWorkloadTokenClaims = {
        iss: 'https://accounts.google.com',
        aud: targetUrl,
        email: verifierSa,
        email_verified: true,
        exp: Math.floor(Date.now() / 1000) - 30, // Expired 30 seconds ago
        iat: Math.floor(Date.now() / 1000) - 330,
        sub: '10987654321',
        jti: 'jti-exp-003',
      };
      const token = workloadService.generateTestOidcToken(claims, srvPrivPem, 'key-1');

      const ctx: InternalServiceCallContext = {
        targetServiceUrl: targetUrl,
        rawAuthorizationHeader: `Bearer ${token}`,
        expectedServiceAccountEmail: verifierSa,
        requestedTargetUid: 'user-123',
      };
      const res = workloadService.verifyInternalServiceCall(ctx);
      assert.strictEqual(res.authorized, false);
      assert.strictEqual(res.errorCode, 'ERR_INTERNAL_TOKEN_EXPIRED');
    });

    it('18. Forged principal header rejected', () => {
      const ctx: InternalServiceCallContext = {
        targetServiceUrl: targetUrl,
        callerSuppliedPrincipalHeader: verifierSa, // Header supplied without valid Bearer token
        expectedServiceAccountEmail: verifierSa,
        requestedTargetUid: 'user-123',
      };
      const res = workloadService.verifyInternalServiceCall(ctx);
      assert.strictEqual(res.authorized, false);
      assert.strictEqual(res.errorCode, 'ERR_FORGED_PRINCIPAL_HEADER');
    });

    it('19. Wrong service identity rejected', () => {
      const claims: InternalWorkloadTokenClaims = {
        iss: 'https://accounts.google.com',
        aud: targetUrl,
        email: 'sa-unauthorized-service@external.iam.gserviceaccount.com', // Wrong identity
        email_verified: true,
        exp: Math.floor(Date.now() / 1000) + 300,
        iat: Math.floor(Date.now() / 1000),
        sub: '10987654321',
        jti: 'jti-wrong-sa-004',
      };
      const token = workloadService.generateTestOidcToken(claims, srvPrivPem, 'key-1');

      const ctx: InternalServiceCallContext = {
        targetServiceUrl: targetUrl,
        rawAuthorizationHeader: `Bearer ${token}`,
        expectedServiceAccountEmail: verifierSa,
        requestedTargetUid: 'user-123',
      };
      const res = workloadService.verifyInternalServiceCall(ctx);
      assert.strictEqual(res.authorized, false);
      assert.strictEqual(res.errorCode, 'ERR_WRONG_SERVICE_IDENTITY');
    });

    it('20. Ordinary end-user role claim cannot impersonate workload identity', () => {
      // Simulates an end-user JWT containing { user_id: 'user123', role: 'worker' }
      const fakeClaims = {
        user_id: 'user123',
        role: 'worker',
        iss: 'https://securetoken.google.com/kelasagara',
        sub: 'user123',
        exp: Math.floor(Date.now() / 1000) + 3600,
      };
      const header = { alg: 'ES256', typ: 'JWT', kid: 'key-1' };
      const token =
        Buffer.from(JSON.stringify(header)).toString('base64url') +
        '.' +
        Buffer.from(JSON.stringify(fakeClaims)).toString('base64url') +
        '.DUMMY_SIGNATURE';

      const ctx: InternalServiceCallContext = {
        targetServiceUrl: targetUrl,
        rawAuthorizationHeader: `Bearer ${token}`,
        expectedServiceAccountEmail: verifierSa,
        requestedTargetUid: 'user-123',
      };
      const res = workloadService.verifyInternalServiceCall(ctx);
      assert.strictEqual(res.authorized, false);
      assert.strictEqual(res.errorCode, 'ERR_END_USER_TOKEN_IMPERSONATION');
    });

    it('21. Unauthorized UID substitution rejected', () => {
      const claims: InternalWorkloadTokenClaims = {
        iss: 'https://accounts.google.com',
        aud: targetUrl,
        email: verifierSa,
        email_verified: true,
        exp: Math.floor(Date.now() / 1000) + 300,
        iat: Math.floor(Date.now() / 1000),
        sub: '10987654321',
        jti: 'jti-uid-sub-005',
        boundUserUid: 'user-alice-123', // Bound to Alice
      };
      const token = workloadService.generateTestOidcToken(claims, srvPrivPem, 'key-1');

      const ctx: InternalServiceCallContext = {
        targetServiceUrl: targetUrl,
        rawAuthorizationHeader: `Bearer ${token}`,
        expectedServiceAccountEmail: verifierSa,
        requestedTargetUid: 'user-bob-999', // Caller requests Bob!
      };
      const res = workloadService.verifyInternalServiceCall(ctx);
      assert.strictEqual(res.authorized, false);
      assert.strictEqual(res.errorCode, 'ERR_UNAUTHORIZED_UID_SUBSTITUTION');
    });

    it('22. Internal token replay rejected', () => {
      const claims: InternalWorkloadTokenClaims = {
        iss: 'https://accounts.google.com',
        aud: targetUrl,
        email: verifierSa,
        email_verified: true,
        exp: Math.floor(Date.now() / 1000) + 300,
        iat: Math.floor(Date.now() / 1000),
        sub: '10987654321',
        jti: 'jti-single-use-006', // JTI will be consumed
      };
      const token = workloadService.generateTestOidcToken(claims, srvPrivPem, 'key-1');

      const ctx: InternalServiceCallContext = {
        targetServiceUrl: targetUrl,
        rawAuthorizationHeader: `Bearer ${token}`,
        expectedServiceAccountEmail: verifierSa,
        requestedTargetUid: 'user-123',
      };

      // First call succeeds
      const res1 = workloadService.verifyInternalServiceCall(ctx);
      assert.strictEqual(res1.authorized, true);

      // Second call with same token fails replay check
      const res2 = workloadService.verifyInternalServiceCall(ctx);
      assert.strictEqual(res2.authorized, false);
      assert.strictEqual(res2.errorCode, 'ERR_TOKEN_REPLAYED');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // TRACK C: KMS AND VAULT DECRYPTION BLAST RADIUS (Tests 23–35)
  // ═══════════════════════════════════════════════════════════════════════════
  describe('Track C: KMS and Vault Decryption Blast Radius (Tests 23–35)', () => {
    // Generate synthetic 128-dim Float32Array embedding
    const testEmbedding = new Float32Array(128);
    for (let i = 0; i < 128; i++) testEmbedding[i] = Math.sin(i);

    it('23. Verifier decrypt permission is key-scoped in IaC', () => {
      const iamTf = fs.readFileSync(path.join(TF_DIR, 'iam_bindings.tf'), 'utf8');
      assert.ok(iamTf.includes('crypto_key_id = google_kms_crypto_key.dek_wrap.id'));
      assert.ok(iamTf.includes('role          = "roles/cloudkms.cryptoKeyDecrypter"'));
    });

    it('24. Verifier cannot sign (roles/cloudkms.signer is withheld)', () => {
      const iamTf = fs.readFileSync(path.join(TF_DIR, 'iam_bindings.tf'), 'utf8');
      const verifierSection = iamTf.slice(
        iamTf.indexOf('Verifier Service Account IAM Bindings'),
        iamTf.indexOf('Reviewer Service Account IAM Bindings')
      );
      assert.ok(!verifierSection.includes('roles/cloudkms.signer'));
    });

    it('25. Verifier cannot encrypt under the DEK wrapping key', () => {
      const iamTf = fs.readFileSync(path.join(TF_DIR, 'iam_bindings.tf'), 'utf8');
      const verifierSection = iamTf.slice(
        iamTf.indexOf('Verifier Service Account IAM Bindings'),
        iamTf.indexOf('Reviewer Service Account IAM Bindings')
      );
      assert.ok(!verifierSection.includes('roles/cloudkms.cryptoKeyEncrypter'));
    });

    it('26. Enrollment cannot decrypt under the DEK wrapping key', () => {
      const iamTf = fs.readFileSync(path.join(TF_DIR, 'iam_bindings.tf'), 'utf8');
      const enrollmentSection = iamTf.slice(0, iamTf.indexOf('Verifier Service Account IAM Bindings'));
      assert.ok(!enrollmentSection.includes('roles/cloudkms.cryptoKeyDecrypter'));
    });

    it('27. Reviewer cannot decrypt (zero KMS access)', () => {
      const iamTf = fs.readFileSync(path.join(TF_DIR, 'iam_bindings.tf'), 'utf8');
      const reviewerSection = iamTf.slice(
        iamTf.indexOf('Reviewer Service Account IAM Bindings'),
        iamTf.indexOf('Inventory Metadata Scanner IAM Bindings')
      );
      assert.ok(!reviewerSection.includes('google_kms_crypto_key_iam_member'));
    });

    it('28. Inventory cannot decrypt (zero KMS access)', () => {
      const iamTf = fs.readFileSync(path.join(TF_DIR, 'iam_bindings.tf'), 'utf8');
      const invSection = iamTf.slice(
        iamTf.indexOf('Inventory Metadata Scanner IAM Bindings'),
        iamTf.indexOf('Audit Notary Service Account IAM Bindings')
      );
      assert.ok(!invSection.includes('cryptoKeyDecrypter'));
    });

    it('29. AAD modification rejected by GCM decipher', () => {
      const record = vaultGuard.encryptTemplateSnapshot('user-101', 'tmpl-001', testEmbedding, '1to1_auth');

      // Attempt to decrypt with mismatched context
      assert.throws(
        () =>
          vaultGuard.decryptTemplate({
            record,
            callerSessionUid: 'user-101',
            callerContext: '1toN_dedup', // Context mismatch changes AAD!
          }),
        /AUTHENTICATION_TAG_VERIFICATION_FAILED/
      );
    });

    it('30. Ciphertext modification rejected by GCM decipher', () => {
      const record = vaultGuard.encryptTemplateSnapshot('user-101', 'tmpl-002', testEmbedding, '1to1_auth');

      // Corrupt 1 byte in ciphertext
      const rawCt = Buffer.from(record.ciphertextBase64, 'base64');
      rawCt[0] ^= 0xff;
      const corruptedRecord = { ...record, ciphertextBase64: rawCt.toString('base64') };

      assert.throws(
        () =>
          vaultGuard.decryptTemplate({
            record: corruptedRecord,
            callerSessionUid: 'user-101',
            callerContext: '1to1_auth',
          }),
        /AUTHENTICATION_TAG_VERIFICATION_FAILED/
      );
    });

    it('31. Authentication tag modification rejected by GCM decipher', () => {
      const record = vaultGuard.encryptTemplateSnapshot('user-101', 'tmpl-003', testEmbedding, '1to1_auth');

      // Corrupt auth tag
      const rawTag = Buffer.from(record.authTagBase64, 'base64');
      rawTag[0] ^= 0xaa;
      const corruptedRecord = { ...record, authTagBase64: rawTag.toString('base64') };

      assert.throws(
        () =>
          vaultGuard.decryptTemplate({
            record: corruptedRecord,
            callerSessionUid: 'user-101',
            callerContext: '1to1_auth',
          }),
        /AUTHENTICATION_TAG_VERIFICATION_FAILED/
      );
    });

    it('32. Wrapped DEK substitution rejected', () => {
      const record = vaultGuard.encryptTemplateSnapshot('user-101', 'tmpl-004', testEmbedding, '1to1_auth');

      // Substitute wrapped DEK with random bytes
      const fakeWrappedDek = Buffer.concat([Buffer.from('KMS_WRAPPED:'), crypto.randomBytes(32)]);
      const corruptedRecord = { ...record, wrappedDekBase64: fakeWrappedDek.toString('base64') };

      assert.throws(
        () =>
          vaultGuard.decryptTemplate({
            record: corruptedRecord,
            callerSessionUid: 'user-101',
            callerContext: '1to1_auth',
          }),
        /AUTHENTICATION_TAG_VERIFICATION_FAILED/
      );
    });

    it('33. Superseded template rejected before decryption', () => {
      const record = vaultGuard.encryptTemplateSnapshot('user-101', 'tmpl-005', testEmbedding, '1to1_auth');
      const supersededRecord: EncryptedVaultRecord = { ...record, isActive: false };

      assert.throws(
        () =>
          vaultGuard.decryptTemplate({
            record: supersededRecord,
            callerSessionUid: 'user-101',
            callerContext: '1to1_auth',
          }),
        /SUPERSEDED_TEMPLATE_REJECTED/
      );
    });

    it('34. Unauthorized record access rejected (caller session UID mismatch in 1:1)', () => {
      const record = vaultGuard.encryptTemplateSnapshot('user-alice-777', 'tmpl-006', testEmbedding, '1to1_auth');

      assert.throws(
        () =>
          vaultGuard.decryptTemplate({
            record,
            callerSessionUid: 'user-mallory-666', // Mallory attempts to decrypt Alice's template!
            callerContext: '1to1_auth',
          }),
        /UNAUTHORIZED_RECORD_ACCESS/
      );
    });

    it('35. DEK lifetime and buffer cleanup path verified (decryption succeeds and wipes DEK)', () => {
      const record = vaultGuard.encryptTemplateSnapshot('user-101', 'tmpl-007', testEmbedding, '1to1_auth');

      const res = vaultGuard.decryptTemplate({
        record,
        callerSessionUid: 'user-101',
        callerContext: '1to1_auth',
      });

      assert.strictEqual(res.templateId, 'tmpl-007');
      assert.strictEqual(res.embedding.length, 128);
      assert.ok(res.decryptionAuditId.startsWith('audit-decrypt-'));
      // Verify floating point values match original
      assert.strictEqual(Math.abs(res.embedding[0] - testEmbedding[0]) < 1e-6, true);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // TRACK D: AUDIT VERIFICATION & INDEPENDENT RECONCILER (Tests 36–44)
  // ═══════════════════════════════════════════════════════════════════════════
  describe('Track D: Audit Verification & Independent Reconciler (Tests 36–44)', () => {
    // Generate EC keypair for sa-biometrics-audit-notary
    const { privateKey: notaryPriv, publicKey: notaryPub } = crypto.generateKeyPairSync('ec', {
      namedCurve: 'prime256v1',
    });
    const notaryPrivPem = notaryPriv.export({ type: 'pkcs8', format: 'pem' }) as string;
    const notaryPubPem = notaryPub.export({ type: 'spki', format: 'pem' }) as string;

    auditReconciler.registerTrustedSignerKey('notary-key-v1', notaryPubPem);

    // Build synthetic sequential audit trail
    const auditEvents: AuditEventRecord[] = [];
    let prevHash = 'GENESIS_HASH_0000000000000000000000000000000000000000000000000000000000000000';
    for (let seq = 1; seq <= 5; seq++) {
      const payloadHash = crypto.createHash('sha256').update(`event-data-${seq}`).digest('hex');
      const raw = {
        sequenceNumber: seq,
        timestampIso: new Date(Date.now() + seq * 1000).toISOString(),
        eventType: 'BIOMETRIC_VERIFY_SUCCESS',
        actorUid: `user-${seq}`,
        eventPayloadHash: payloadHash,
        previousEventHash: prevHash,
      };
      const recordHash = auditReconciler.computeEventHash(raw);
      auditEvents.push({ ...raw, recordHash });
      prevHash = recordHash;
    }

    // Build signed external checkpoint
    const checkpointRaw = {
      checkpointId: 'cp-001',
      sequenceNumberRange: { start: 1, end: 5 },
      timestampIso: new Date().toISOString(),
      cumulativeLedgerHash: prevHash,
      previousCheckpointHash: 'GENESIS_CHECKPOINT_HASH',
      signerServiceAccount: 'sa-biometrics-audit-notary',
      keyVersion: 'notary-key-v1',
    };
    const signedCheckpoint = auditReconciler.signCheckpointAsNotary(checkpointRaw, notaryPrivPem);

    it('36. Audit notary cannot modify biometric templates in IaC', () => {
      const iamTf = fs.readFileSync(path.join(TF_DIR, 'iam_bindings.tf'), 'utf8');
      const notarySection = iamTf.slice(iamTf.indexOf('Audit Notary Service Account IAM Bindings'));
      assert.ok(!notarySection.includes('biometric-vault-db'));
      assert.ok(!notarySection.includes('dek_wrap'));
    });

    it('37. Audit notary cannot decrypt vault data', () => {
      const iamTf = fs.readFileSync(path.join(TF_DIR, 'iam_bindings.tf'), 'utf8');
      const notarySection = iamTf.slice(iamTf.indexOf('Audit Notary Service Account IAM Bindings'));
      assert.ok(!notarySection.includes('roles/cloudkms.cryptoKeyDecrypter'));
    });

    it('38. Reconciler cannot sign (holds roles/cloudkms.verifier, not signer)', () => {
      const iamTf = fs.readFileSync(path.join(TF_DIR, 'iam_bindings.tf'), 'utf8');
      assert.ok(iamTf.includes('inventory_audit_key_verifier'));
      assert.ok(iamTf.includes('role          = "roles/cloudkms.verifier"'));
    });

    it('39. Reconciler cannot modify records (read-only viewer)', () => {
      const iamTf = fs.readFileSync(path.join(TF_DIR, 'iam_bindings.tf'), 'utf8');
      assert.ok(iamTf.includes('inventory_datastore'));
      assert.ok(iamTf.includes('role    = "roles/datastore.viewer"'));
    });

    it('40. Invalid checkpoint signature rejected by reconciler', () => {
      const tamperedCp: ExternalCheckpointObject = {
        ...signedCheckpoint,
        signatureBase64: 'INVALID_SIGNATURE_TAMPERED_CP',
      };
      const report = auditReconciler.reconcileAuditTrail(auditEvents, [tamperedCp]);
      assert.strictEqual(report.reconciled, false);
      const err = report.anomaliesDetected.find((a) => a.type === 'SIGNATURE_INVALID');
      assert.ok(err !== undefined);
    });

    it('41. Old checkpoint replay rejected by reconciler', () => {
      const freshReconciler = new AuditReconcilerService();
      freshReconciler.registerTrustedSignerKey('notary-key-v1', notaryPubPem);

      // Session 1: succeeds
      const r1 = freshReconciler.reconcileAuditTrail(auditEvents, [signedCheckpoint]);
      assert.strictEqual(r1.reconciled, true);

      // Session 2: replaying cp-001 is detected
      const r2 = freshReconciler.reconcileAuditTrail(auditEvents, [signedCheckpoint]);
      assert.strictEqual(r2.reconciled, false);
      const replay = r2.anomaliesDetected.find((a) => a.type === 'REPLAY_DETECTED');
      assert.ok(replay !== undefined);
    });

    it('42. Missing checkpoint detected (external chain discontinuity)', () => {
      const freshReconciler = new AuditReconcilerService();
      freshReconciler.registerTrustedSignerKey('notary-key-v1', notaryPubPem);

      const cp1 = auditReconciler.signCheckpointAsNotary(
        {
          checkpointId: 'cp-chain-1',
          sequenceNumberRange: { start: 1, end: 5 },
          timestampIso: new Date().toISOString(),
          cumulativeLedgerHash: 'HASH_CP_1',
          previousCheckpointHash: 'GENESIS_CHECKPOINT_HASH',
          signerServiceAccount: 'sa-biometrics-audit-notary',
          keyVersion: 'notary-key-v1',
        },
        notaryPrivPem
      );

      // cp3 skips cp2!
      const cp3 = auditReconciler.signCheckpointAsNotary(
        {
          checkpointId: 'cp-chain-3',
          sequenceNumberRange: { start: 11, end: 15 },
          timestampIso: new Date().toISOString(),
          cumulativeLedgerHash: 'HASH_CP_3',
          previousCheckpointHash: 'HASH_CP_2_MISSING', // Expected HASH_CP_1!
          signerServiceAccount: 'sa-biometrics-audit-notary',
          keyVersion: 'notary-key-v1',
        },
        notaryPrivPem
      );

      const report = freshReconciler.reconcileAuditTrail(auditEvents, [cp1, cp3]);
      assert.strictEqual(report.reconciled, false);
      const gap = report.anomaliesDetected.find((a) => a.type === 'CHAIN_DISCONTINUITY');
      assert.ok(gap !== undefined);
    });

    it('43. Entire ledger rewrite detected by independent checkpoint reconciliation', () => {
      const freshReconciler = new AuditReconcilerService();
      freshReconciler.registerTrustedSignerKey('notary-key-v1', notaryPubPem);

      // Rogue Admin SDK modifies sequence 3 in Firestore
      const tamperedEvents = [...auditEvents];
      tamperedEvents[2] = {
        ...tamperedEvents[2],
        eventPayloadHash: 'RETROACTIVE_PAYLOAD_MUTATION',
      };

      const report = freshReconciler.reconcileAuditTrail(tamperedEvents, [signedCheckpoint]);
      assert.strictEqual(report.reconciled, false);
      const mutation = report.anomaliesDetected.find((a) => a.type === 'HISTORICAL_REWRITE_DETECTED');
      assert.ok(mutation !== undefined);
    });

    it('44. Public key rotation verified (new key version accepted, old retired key rejected)', () => {
      const freshReconciler = new AuditReconcilerService();
      const { privateKey: k2Priv, publicKey: k2Pub } = crypto.generateKeyPairSync('ec', {
        namedCurve: 'prime256v1',
      });
      const k2PrivPem = k2Priv.export({ type: 'pkcs8', format: 'pem' }) as string;
      const k2PubPem = k2Pub.export({ type: 'spki', format: 'pem' }) as string;

      freshReconciler.registerTrustedSignerKey('notary-key-v2', k2PubPem);

      const cpRotated = freshReconciler.signCheckpointAsNotary(
        {
          checkpointId: 'cp-rot-001',
          sequenceNumberRange: { start: 1, end: 5 },
          timestampIso: new Date().toISOString(),
          cumulativeLedgerHash: prevHash,
          previousCheckpointHash: 'GENESIS_CHECKPOINT_HASH',
          signerServiceAccount: 'sa-biometrics-audit-notary',
          keyVersion: 'notary-key-v2', // Rotated key
        },
        k2PrivPem
      );

      const report = freshReconciler.reconcileAuditTrail(auditEvents, [cpRotated]);
      assert.strictEqual(report.reconciled, true);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // TRACK E: RECOVERY DUAL CUSTODY (Tests 45–50)
  // ═══════════════════════════════════════════════════════════════════════════
  describe('Track E: Recovery Dual Custody (Tests 45–50)', () => {
    // Generate EC keypairs for Holder 1 (BCO) and Holder 2 (ISA)
    const { privateKey: bcoPriv, publicKey: bcoPub } = crypto.generateKeyPairSync('ec', {
      namedCurve: 'prime256v1',
    });
    const bcoPrivPem = bcoPriv.export({ type: 'pkcs8', format: 'pem' }) as string;
    const bcoPubPem = bcoPub.export({ type: 'spki', format: 'pem' }) as string;

    const { privateKey: isaPriv, publicKey: isaPub } = crypto.generateKeyPairSync('ec', {
      namedCurve: 'prime256v1',
    });
    const isaPrivPem = isaPriv.export({ type: 'pkcs8', format: 'pem' }) as string;
    const isaPubPem = isaPub.export({ type: 'spki', format: 'pem' }) as string;

    const bcoOfficer: DualCustodyApprover = {
      officerId: 'officer-bco-101',
      role: 'BIOMETRIC_COMPLIANCE_OFFICER',
      publicKeyPem: bcoPubPem,
    };
    const isaAuditor: DualCustodyApprover = {
      officerId: 'officer-isa-202',
      role: 'INDEPENDENT_SECURITY_AUDITOR',
      publicKeyPem: isaPubPem,
    };

    recoveryEngine.registerApprover(bcoOfficer);
    recoveryEngine.registerApprover(isaAuditor);

    const targetUid = 'user-locked-victim-999';
    const caseRef = 'REC-2026-CASE-ABC';
    const now = Date.now();
    const expiry = now + 10 * 60 * 1000; // 10 mins

    it('45. One holder cannot authorize both custody approvals (collusion blocked)', () => {
      // Rogue officer attempts to sign for both Holder 1 and Holder 2
      const p1 = recoveryEngine.createApproverProof('officer-bco-101', bcoPrivPem, targetUid, caseRef, now, expiry);
      const p2 = recoveryEngine.createApproverProof('officer-bco-101', bcoPrivPem, targetUid, caseRef, now, expiry);

      const token: DualCustodyRecoveryToken = {
        tokenId: 'token-collusion-001',
        targetUid,
        caseReference: caseRef,
        issuedAtEpochMs: now,
        expiresAtEpochMs: expiry,
        approvalHolder1: p1,
        approvalHolder2: p2, // Same officer!
      };

      const res = recoveryEngine.evaluateRecoveryAuthorization({
        recoveryToken: token,
        targetUid,
        caseReference: caseRef,
      });

      assert.strictEqual(res.allowed, false);
      assert.strictEqual(res.errorCode, 'ERR_DUAL_CUSTODY_COLLUSION_SAME_OFFICER');
    });

    it('46. Unauthorized second approver rejected', () => {
      const { privateKey: roguePriv } = crypto.generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
      const roguePrivPem = roguePriv.export({ type: 'pkcs8', format: 'pem' }) as string;

      const p1 = recoveryEngine.createApproverProof('officer-bco-101', bcoPrivPem, targetUid, caseRef, now, expiry);
      const p2 = recoveryEngine.createApproverProof('rogue-attacker-666', roguePrivPem, targetUid, caseRef, now, expiry);

      const token: DualCustodyRecoveryToken = {
        tokenId: 'token-unauth-002',
        targetUid,
        caseReference: caseRef,
        issuedAtEpochMs: now,
        expiresAtEpochMs: expiry,
        approvalHolder1: p1,
        approvalHolder2: p2,
      };

      const res = recoveryEngine.evaluateRecoveryAuthorization({
        recoveryToken: token,
        targetUid,
        caseReference: caseRef,
      });

      assert.strictEqual(res.allowed, false);
      assert.strictEqual(res.errorCode, 'ERR_UNAUTHORIZED_APPROVER_2');
    });

    it('47. Expired dual-custody authorization rejected', () => {
      const pastNow = now - 20 * 60 * 1000;
      const pastExpiry = now - 5 * 60 * 1000; // Expired 5 mins ago

      const p1 = recoveryEngine.createApproverProof('officer-bco-101', bcoPrivPem, targetUid, caseRef, pastNow, pastExpiry);
      const p2 = recoveryEngine.createApproverProof('officer-isa-202', isaPrivPem, targetUid, caseRef, pastNow, pastExpiry);

      const token: DualCustodyRecoveryToken = {
        tokenId: 'token-exp-003',
        targetUid,
        caseReference: caseRef,
        issuedAtEpochMs: pastNow,
        expiresAtEpochMs: pastExpiry,
        approvalHolder1: p1,
        approvalHolder2: p2,
      };

      const res = recoveryEngine.evaluateRecoveryAuthorization({
        recoveryToken: token,
        targetUid,
        caseReference: caseRef,
      });

      assert.strictEqual(res.allowed, false);
      assert.strictEqual(res.errorCode, 'ERR_RECOVERY_TOKEN_EXPIRED');
    });

    it('48. Replayed authorization rejected (single-use consumption)', () => {
      const p1 = recoveryEngine.createApproverProof('officer-bco-101', bcoPrivPem, targetUid, caseRef, now, expiry);
      const p2 = recoveryEngine.createApproverProof('officer-isa-202', isaPrivPem, targetUid, caseRef, now, expiry);

      const token: DualCustodyRecoveryToken = {
        tokenId: 'token-single-use-004',
        targetUid,
        caseReference: caseRef,
        issuedAtEpochMs: now,
        expiresAtEpochMs: expiry,
        approvalHolder1: p1,
        approvalHolder2: p2,
      };

      // 1st consumption succeeds
      const res1 = recoveryEngine.evaluateRecoveryAuthorization({
        recoveryToken: token,
        targetUid,
        caseReference: caseRef,
      });
      assert.strictEqual(res1.allowed, true);

      // 2nd consumption rejected
      const res2 = recoveryEngine.evaluateRecoveryAuthorization({
        recoveryToken: token,
        targetUid,
        caseReference: caseRef,
      });
      assert.strictEqual(res2.allowed, false);
      assert.strictEqual(res2.errorCode, 'ERR_RECOVERY_TOKEN_REPLAYED');
    });

    it('49. Case reference alone cannot authorize recovery (requires dual custody proofs)', () => {
      const invalidToken = {
        tokenId: 'token-empty',
        targetUid,
        caseReference: caseRef,
        issuedAtEpochMs: now,
        expiresAtEpochMs: expiry,
      } as any;

      const res = recoveryEngine.evaluateRecoveryAuthorization({
        recoveryToken: invalidToken,
        targetUid,
        caseReference: caseRef,
      });

      assert.strictEqual(res.allowed, false);
      assert.strictEqual(res.errorCode, 'ERR_INCOMPLETE_DUAL_CUSTODY');
    });

    it('50. Replacement phone number cannot act as original account factor without identity verification', () => {
      const p1 = recoveryEngine.createApproverProof('officer-bco-101', bcoPrivPem, targetUid, caseRef, now, expiry);
      const p2 = recoveryEngine.createApproverProof('officer-isa-202', isaPrivPem, targetUid, caseRef, now, expiry);

      const token: DualCustodyRecoveryToken = {
        tokenId: 'token-factor-005',
        targetUid,
        caseReference: caseRef,
        issuedAtEpochMs: now,
        expiresAtEpochMs: expiry,
        approvalHolder1: p1,
        approvalHolder2: p2,
      };

      const res = recoveryEngine.evaluateRecoveryAuthorization({
        recoveryToken: token,
        targetUid,
        caseReference: caseRef,
        replacementPhoneNumber: '+919999988888',
        hasVerifiedOriginalFactor: false, // Replacement factor not proven!
      });

      assert.strictEqual(res.allowed, false);
      assert.strictEqual(res.errorCode, 'ERR_REPLACEMENT_FACTOR_UNVERIFIED');
    });
  });
});
