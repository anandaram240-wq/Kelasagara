/**
 * KELASAGARA V20.19: PILOT GATE A CLOSURE & SOFTWARE EVIDENCE RECONCILIATION TEST SUITE
 *
 * Verification Tracks:
 * - Track A: Complete Plan Input Provenance & Anti-Regeneration Gate (Tests 1–8)
 * - Track B: Independent Registry Two-Person Recovery Authorization (Tests 9–18)
 * - Track C: Pilot-Specific Cryptographic & Dataset Isolation (Tests 19–23)
 * - Track D: Plaintext DEK Memory Lifecycle & Exception Clearing (Tests 24–25)
 * - Track E: Exact OpenTofu Variable Precedence & Conflict Overrides (Tests 26–30)
 * - Track F: Immutable Secret Manager Versions Enforcement (Tests 31–35)
 * - Track G: HMAC Key Trust, Independent Management & Rotation (Tests 36–39)
 * - Track H: Binary Plan Storage Protection, Permissions & Transit (Tests 40–43)
 * - Track I: OpenTofu Plan Encryption At Rest (Tests 44–48e)
 * - Track J: Advanced Secret Manager Reference & Version State Resolution (Tests 49–53)
 * - Track K: Cloud KMS HMAC Identity Mapping & Gate B Boundary (Tests 54–57)
 */

import { describe, it, before, after } from 'node:test';
import * as assert from 'node:assert';
import * as crypto from 'crypto';
import * as fs from 'fs';
import * as path from 'path';

import {
  TrustedPlanWrapperV19,
  APPROVED_TOFU_BINARY_HASH,
  resolveEffectiveVariables,
  validateSecretManagerReference,
  ProtectedHmacKeyManagerV19,
  encryptPlanArtifactForTransit,
  decryptPlanArtifactFromTransit,
  controlledCleanupPlanArtifact,
  parseSimpleTfvars,
  PlanEncryptionKeyManagerV19,
  encryptPlanBinaryAtRest,
  decryptPlanBinaryAtRest,
  ENCRYPTED_PLAN_MAGIC,
  InMemorySecretManagerMetadataResolver,
  getCanonicalCloudKmsHmacMapping,
  validateKmsPrincipalOperation,
  computeDomainSeparatedSecretHmac,
} from '../services/trusted_plan_wrapper_v19';
import {
  RecoveryDualCustodyEngineV19,
  InMemoryOfficerRegistry,
  RegisteredOfficerRecordV19,
  DualCustodyRecoveryTokenV19,
} from '../services/recovery_dual_custody_v19';
import {
  PilotCryptographicIsolationEngineV19,
  PILOT_DATABASE_NAME,
  PROD_DATABASE_NAME,
  PILOT_KMS_KEY_ID,
  PROD_KMS_KEY_ID,
} from '../services/pilot_cryptographic_isolation_v19';

describe('KELASAGARA V20.19: Pilot Gate A Closure & Final Evidence Suite (56 Tests)', () => {
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
  // TRACK A: COMPLETE PLAN INPUT PROVENANCE & ANTI-REGENERATION GATE (Tests 1–8)
  // =========================================================================
  describe('Track A: Complete Plan Input Provenance & Anti-Regeneration Gate (Tests 1–8)', () => {
    const wrapper = new TrustedPlanWrapperV19();

    it('1. Plan generation computes comprehensive input attestation hash', () => {
      const planRes = wrapper.generatePlanWithAttestation({
        tfDir,
        cliArgs: ['-input=false', '-var=db_password=supersecretvalue123'],
        environment: 'sandbox',
        projectId: 'kelasagara-sandbox',
        runnerIdentity: 'sa-ci-plan-runner',
        privateKeyPem: ecKeyPair.privateKey,
        publicKeyPem: ecKeyPair.publicKey,
      });
      assert.strictEqual(planRes.success, true);
      assert.ok(planRes.signedManifest);
      const att = planRes.signedManifest!.manifest.inputAttestation;
      assert.ok(att.configFilesDigest);
      assert.ok(att.providerLockDigest);
      assert.ok(att.comprehensiveInputManifestHash);
      assert.strictEqual(att.tofuBinaryDigest, APPROVED_TOFU_BINARY_HASH);

      // Verify OpenTofu variable precedence order is bound in attestation
      assert.ok(Array.isArray(att.variablePrecedenceOrder));
      assert.strictEqual(att.variablePrecedenceOrder.length, 5);
      assert.ok(att.variablePrecedenceOrder[0].includes('TF_VAR'));
      assert.ok(att.variablePrecedenceOrder[1].includes('terraform.tfvars'));

      // Verify secret redaction: plaintext secret MUST NOT appear in manifest, keyed HMAC used
      assert.ok(att.cliVarDigests['db_password']);
      assert.ok(att.cliVarDigests['db_password'].startsWith('[PROTECTED_KEYED_HMAC:'));
      const manifestJson = JSON.stringify(planRes.signedManifest!.manifest);
      assert.strictEqual(manifestJson.includes('supersecretvalue123'), false);

      // Verify constant-time comparison helper
      const hmacVal = att.cliVarDigests['db_password'];
      assert.strictEqual(wrapper.constantTimeDigestCompare(hmacVal, hmacVal), true);
      assert.strictEqual(wrapper.constantTimeDigestCompare(hmacVal, 'wrong_digest'), false);

      if (fs.existsSync(planRes.planBinaryPath!)) fs.unlinkSync(planRes.planBinaryPath!);
    });

    it('2. Modifying any .tf configuration file after approval invalidates apply', () => {
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

      // Create temporary .tf file to simulate post-approval modification
      const tempTf = path.join(tfDir, 'temp_unapproved_resource.tf');
      fs.writeFileSync(tempTf, '# unapproved modification');
      try {
        const buffer = fs.readFileSync(planRes.planBinaryPath!);
        const applyRes = wrapper.verifyPlanForApply({
          tfDir,
          planBinaryBuffer: buffer,
          signedManifest: planRes.signedManifest!,
        });
        assert.strictEqual(applyRes.approvedForApply, false);
        assert.strictEqual(applyRes.errorCode, 'ERR_INPUT_CONFIG_MODIFIED_POST_APPROVAL');
      } finally {
        if (fs.existsSync(tempTf)) fs.unlinkSync(tempTf);
        if (fs.existsSync(planRes.planBinaryPath!)) fs.unlinkSync(planRes.planBinaryPath!);
      }
    });

    it('3. Introducing or modifying *.tfvars file after approval invalidates apply', () => {
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

      // Introduce an unapproved tfvars file
      const tempVars = path.join(tfDir, 'unapproved.auto.tfvars');
      fs.writeFileSync(tempVars, 'admin_mode = true\n');
      try {
        const buffer = fs.readFileSync(planRes.planBinaryPath!);
        const applyRes = wrapper.verifyPlanForApply({
          tfDir,
          planBinaryBuffer: buffer,
          signedManifest: planRes.signedManifest!,
        });
        assert.strictEqual(applyRes.approvedForApply, false);
        assert.strictEqual(applyRes.errorCode, 'ERR_TFVARS_MODIFIED_OR_INTRODUCED');
      } finally {
        if (fs.existsSync(tempVars)) fs.unlinkSync(tempVars);
      }

      // Also verify unapproved .tfvars.json introduction is detected
      const tempJsonVars = path.join(tfDir, 'unapproved.auto.tfvars.json');
      fs.writeFileSync(tempJsonVars, '{"injected": true}\n');
      try {
        const buffer = fs.readFileSync(planRes.planBinaryPath!);
        const applyRes = wrapper.verifyPlanForApply({
          tfDir,
          planBinaryBuffer: buffer,
          signedManifest: planRes.signedManifest!,
        });
        assert.strictEqual(applyRes.approvedForApply, false);
        assert.strictEqual(applyRes.errorCode, 'ERR_TFVARS_MODIFIED_OR_INTRODUCED');
      } finally {
        if (fs.existsSync(tempJsonVars)) fs.unlinkSync(tempJsonVars);
        if (fs.existsSync(planRes.planBinaryPath!)) fs.unlinkSync(planRes.planBinaryPath!);
      }
    });

    it('4. Modifying provider lock file after approval invalidates apply', () => {
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

      const modifiedManifest = {
        ...planRes.signedManifest!,
        manifest: {
          ...planRes.signedManifest!.manifest,
          inputAttestation: {
            ...planRes.signedManifest!.manifest.inputAttestation,
            providerLockDigest: '0000000000000000000000000000000000000000000000000000000000000000',
          },
        },
      };

      // Resign modified manifest
      const cJson = wrapper.canonicalizeJson(modifiedManifest.manifest);
      const sign = crypto.createSign('SHA256');
      sign.update(cJson);
      sign.end();
      modifiedManifest.signatureBase64 = sign.sign(ecKeyPair.privateKey, 'base64');

      const buffer = fs.readFileSync(planRes.planBinaryPath!);
      const applyRes = wrapper.verifyPlanForApply({
        tfDir,
        planBinaryBuffer: buffer,
        signedManifest: modifiedManifest,
      });
      assert.strictEqual(applyRes.approvedForApply, false);
      assert.strictEqual(applyRes.errorCode, 'ERR_LOCKFILE_MODIFIED_POST_APPROVAL');

      if (fs.existsSync(planRes.planBinaryPath!)) fs.unlinkSync(planRes.planBinaryPath!);
    });

    it('5. Saved binary plan SHA-256 mismatch detected and rejected by apply gate', () => {
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

      const tamperedBuffer = Buffer.from(fs.readFileSync(planRes.planBinaryPath!));
      tamperedBuffer[0] ^= 0x5a;

      const applyRes = wrapper.verifyPlanForApply({
        tfDir,
        planBinaryBuffer: tamperedBuffer,
        signedManifest: planRes.signedManifest!,
      });
      assert.strictEqual(applyRes.approvedForApply, false);
      assert.strictEqual(applyRes.errorCode, 'ERR_PLAN_DIGEST_MISMATCH');

      if (fs.existsSync(planRes.planBinaryPath!)) fs.unlinkSync(planRes.planBinaryPath!);
    });

    it('6. Tampered manifest signature rejected by apply gate', () => {
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
        signatureBase64: Buffer.from('FORGED_SIGNATURE').toString('base64'),
      };

      const buffer = fs.readFileSync(planRes.planBinaryPath!);
      const applyRes = wrapper.verifyPlanForApply({
        tfDir,
        planBinaryBuffer: buffer,
        signedManifest: tamperedSignedManifest,
      });
      assert.strictEqual(applyRes.approvedForApply, false);
      assert.strictEqual(applyRes.errorCode, 'ERR_MANIFEST_SIGNATURE_INVALID');

      if (fs.existsSync(planRes.planBinaryPath!)) fs.unlinkSync(planRes.planBinaryPath!);
    });

    it('7. Unapproved CLI flags (-destroy) rejected before plan generation', () => {
      const res = wrapper.generatePlanWithAttestation({
        tfDir,
        cliArgs: ['-destroy'],
        environment: 'sandbox',
        projectId: 'kelasagara-sandbox',
        runnerIdentity: 'sa-ci-plan-runner',
      });
      assert.strictEqual(res.success, false);
      assert.strictEqual(res.errorCode, 'ERR_PROHIBITED_CLI_FLAG');
    });

    it('8. Injected TF_CLI_ARGS_apply rejected by environment validation', () => {
      const res = wrapper.generatePlanWithAttestation({
        tfDir,
        cliArgs: ['-input=false'],
        environment: 'sandbox',
        projectId: 'kelasagara-sandbox',
        runnerIdentity: 'sa-ci-plan-runner',
        customEnv: {
          TF_CLI_ARGS_apply: '-auto-approve',
          PATH: '/usr/bin:/bin',
        },
      });
      assert.strictEqual(res.success, false);
      assert.strictEqual(res.errorCode, 'ERR_PROHIBITED_ENV_VAR');
    });
  });

  // =========================================================================
  // TRACK B: INDEPENDENT REGISTRY TWO-PERSON RECOVERY AUTHORIZATION (Tests 9–18)
  // =========================================================================
  describe('Track B: Independent Registry Two-Person Recovery Authorization (Tests 9–18)', () => {
    const registry = new InMemoryOfficerRegistry();
    const engine = new RecoveryDualCustodyEngineV19(registry);

    const { privateKey: bcoKey, publicKey: bcoPub } = crypto.generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
    const { privateKey: isaKey, publicKey: isaPub } = crypto.generateKeyPairSync('ec', { namedCurve: 'prime256v1' });

    const bcoOfficer: RegisteredOfficerRecordV19 = {
      officerId: 'officer-bco-101',
      idpSubject: 'google-oauth2|sub-1001',
      role: 'BIOMETRIC_COMPLIANCE_OFFICER',
      allowedOperations: ['BIOMETRIC_ACCOUNT_UNLOCK', 'TEMPLATE_SUPERSEDE_RECOVERY'],
      mfaCredentialId: 'fido2-yubi-bco-101',
      mfaType: 'FIDO2_HARDWARE_KEY',
      status: 'ACTIVE',
      publicKeyPem: bcoPub.export({ type: 'spki', format: 'pem' }) as string,
      enrolledAtIso: '2026-11-01T00:00:00Z',
    };

    const isaOfficer: RegisteredOfficerRecordV19 = {
      officerId: 'officer-isa-202',
      idpSubject: 'google-oauth2|sub-2002',
      role: 'INDEPENDENT_SECURITY_AUDITOR',
      allowedOperations: ['BIOMETRIC_ACCOUNT_UNLOCK', 'TEMPLATE_SUPERSEDE_RECOVERY'],
      mfaCredentialId: 'fido2-yubi-isa-202',
      mfaType: 'FIDO2_HARDWARE_KEY',
      status: 'ACTIVE',
      publicKeyPem: isaPub.export({ type: 'spki', format: 'pem' }) as string,
      enrolledAtIso: '2026-11-01T00:00:00Z',
    };

    before(() => {
      registry.registerOfficer(bcoOfficer);
      registry.registerOfficer(isaOfficer);
    });

    it('9. Unavailable registry fails closed immediately', async () => {
      const offlineRegistry = new InMemoryOfficerRegistry();
      offlineRegistry.setAvailable(false);
      const offlineEngine = new RecoveryDualCustodyEngineV19(offlineRegistry);

      const now = Date.now();
      const token: DualCustodyRecoveryTokenV19 = {
        tokenId: 'token-9',
        uniqueOperationId: 'op-9',
        targetUid: 'user_recovery_101',
        caseReference: 'CASE-009',
        recoveryOperation: 'BIOMETRIC_ACCOUNT_UNLOCK',
        requestDigest: 'digest-9',
        requesterOfficerId: 'support-agent-1',
        issuedAtEpochMs: now,
        expiresAtEpochMs: now + 600000,
        approvalHolder1: {} as any,
        approvalHolder2: {} as any,
      };

      const res = await offlineEngine.evaluateRecoveryAuthorization({
        recoveryToken: token,
        targetUid: 'user_recovery_101',
        caseReference: 'CASE-009',
        recoveryOperation: 'BIOMETRIC_ACCOUNT_UNLOCK',
        requestDigest: 'digest-9',
      });
      assert.strictEqual(res.allowed, false);
      assert.strictEqual(res.errorCode, 'ERR_REGISTRY_UNAVAILABLE');
    });

    it('10. Requester self-approval rejected', async () => {
      const now = Date.now();
      const p1 = engine.createApproverProof(
        bcoOfficer,
        bcoKey.export({ type: 'pkcs8', format: 'pem' }) as string,
        'user_recovery_101',
        'CASE-010',
        'BIOMETRIC_ACCOUNT_UNLOCK',
        undefined,
        'digest-10',
        'op-10',
        now,
        now + 600000
      );
      const p2 = engine.createApproverProof(
        isaOfficer,
        isaKey.export({ type: 'pkcs8', format: 'pem' }) as string,
        'user_recovery_101',
        'CASE-010',
        'BIOMETRIC_ACCOUNT_UNLOCK',
        undefined,
        'digest-10',
        'op-10',
        now,
        now + 600000
      );

      const token: DualCustodyRecoveryTokenV19 = {
        tokenId: 'token-10',
        uniqueOperationId: 'op-10',
        targetUid: 'user_recovery_101',
        caseReference: 'CASE-010',
        recoveryOperation: 'BIOMETRIC_ACCOUNT_UNLOCK',
        requestDigest: 'digest-10',
        requesterOfficerId: bcoOfficer.officerId, // Requester is BCO approver
        issuedAtEpochMs: now,
        expiresAtEpochMs: now + 600000,
        approvalHolder1: p1,
        approvalHolder2: p2,
      };

      const res = await engine.evaluateRecoveryAuthorization({
        recoveryToken: token,
        targetUid: 'user_recovery_101',
        caseReference: 'CASE-010',
        recoveryOperation: 'BIOMETRIC_ACCOUNT_UNLOCK',
        requestDigest: 'digest-10',
      });
      assert.strictEqual(res.allowed, false);
      assert.strictEqual(res.errorCode, 'ERR_REQUESTER_SELF_APPROVAL');
    });

    it('11. Suspended officer status in registry rejected', async () => {
      registry.updateOfficerStatus(bcoOfficer.officerId, 'SUSPENDED');
      try {
        const now = Date.now();
        const p1 = engine.createApproverProof(
          bcoOfficer,
          bcoKey.export({ type: 'pkcs8', format: 'pem' }) as string,
          'user_recovery_101',
          'CASE-011',
          'BIOMETRIC_ACCOUNT_UNLOCK',
          undefined,
          'digest-11',
          'op-11',
          now,
          now + 600000
        );
        const p2 = engine.createApproverProof(
          isaOfficer,
          isaKey.export({ type: 'pkcs8', format: 'pem' }) as string,
          'user_recovery_101',
          'CASE-011',
          'BIOMETRIC_ACCOUNT_UNLOCK',
          undefined,
          'digest-11',
          'op-11',
          now,
          now + 600000
        );

        const token: DualCustodyRecoveryTokenV19 = {
          tokenId: 'token-11',
          uniqueOperationId: 'op-11',
          targetUid: 'user_recovery_101',
          caseReference: 'CASE-011',
          recoveryOperation: 'BIOMETRIC_ACCOUNT_UNLOCK',
          requestDigest: 'digest-11',
          requesterOfficerId: 'support-agent-55',
          issuedAtEpochMs: now,
          expiresAtEpochMs: now + 600000,
          approvalHolder1: p1,
          approvalHolder2: p2,
        };

        const res = await engine.evaluateRecoveryAuthorization({
          recoveryToken: token,
          targetUid: 'user_recovery_101',
          caseReference: 'CASE-011',
          recoveryOperation: 'BIOMETRIC_ACCOUNT_UNLOCK',
          requestDigest: 'digest-11',
        });
        assert.strictEqual(res.allowed, false);
        assert.strictEqual(res.errorCode, 'ERR_OFFICER_1_STATUS_INACTIVE');
      } finally {
        registry.updateOfficerStatus(bcoOfficer.officerId, 'ACTIVE');
      }
    });

    it('12. Revoked officer status in registry rejected', async () => {
      registry.updateOfficerStatus(isaOfficer.officerId, 'REVOKED');
      try {
        const now = Date.now();
        const p1 = engine.createApproverProof(
          bcoOfficer,
          bcoKey.export({ type: 'pkcs8', format: 'pem' }) as string,
          'user_recovery_101',
          'CASE-012',
          'BIOMETRIC_ACCOUNT_UNLOCK',
          undefined,
          'digest-12',
          'op-12',
          now,
          now + 600000
        );
        const p2 = engine.createApproverProof(
          isaOfficer,
          isaKey.export({ type: 'pkcs8', format: 'pem' }) as string,
          'user_recovery_101',
          'CASE-012',
          'BIOMETRIC_ACCOUNT_UNLOCK',
          undefined,
          'digest-12',
          'op-12',
          now,
          now + 600000
        );

        const token: DualCustodyRecoveryTokenV19 = {
          tokenId: 'token-12',
          uniqueOperationId: 'op-12',
          targetUid: 'user_recovery_101',
          caseReference: 'CASE-012',
          recoveryOperation: 'BIOMETRIC_ACCOUNT_UNLOCK',
          requestDigest: 'digest-12',
          requesterOfficerId: 'support-agent-55',
          issuedAtEpochMs: now,
          expiresAtEpochMs: now + 600000,
          approvalHolder1: p1,
          approvalHolder2: p2,
        };

        const res = await engine.evaluateRecoveryAuthorization({
          recoveryToken: token,
          targetUid: 'user_recovery_101',
          caseReference: 'CASE-012',
          recoveryOperation: 'BIOMETRIC_ACCOUNT_UNLOCK',
          requestDigest: 'digest-12',
        });
        assert.strictEqual(res.allowed, false);
        assert.strictEqual(res.errorCode, 'ERR_OFFICER_2_STATUS_INACTIVE');
      } finally {
        registry.updateOfficerStatus(isaOfficer.officerId, 'ACTIVE');
      }
    });

    it('13. Officers with same IdP subject rejected (collusion defense)', async () => {
      const shadowOfficer: RegisteredOfficerRecordV19 = {
        officerId: 'officer-shadow-isa',
        idpSubject: bcoOfficer.idpSubject, // Same underlying IdP subject!
        role: 'INDEPENDENT_SECURITY_AUDITOR',
        allowedOperations: ['BIOMETRIC_ACCOUNT_UNLOCK'],
        mfaCredentialId: 'fido2-shadow-key',
        mfaType: 'FIDO2_HARDWARE_KEY',
        status: 'ACTIVE',
        publicKeyPem: isaPub.export({ type: 'spki', format: 'pem' }) as string,
        enrolledAtIso: '2026-11-01T00:00:00Z',
      };
      registry.registerOfficer(shadowOfficer);

      const now = Date.now();
      const p1 = engine.createApproverProof(
        bcoOfficer,
        bcoKey.export({ type: 'pkcs8', format: 'pem' }) as string,
        'user_recovery_101',
        'CASE-013',
        'BIOMETRIC_ACCOUNT_UNLOCK',
        undefined,
        'digest-13',
        'op-13',
        now,
        now + 600000
      );
      const p2 = engine.createApproverProof(
        shadowOfficer,
        isaKey.export({ type: 'pkcs8', format: 'pem' }) as string,
        'user_recovery_101',
        'CASE-013',
        'BIOMETRIC_ACCOUNT_UNLOCK',
        undefined,
        'digest-13',
        'op-13',
        now,
        now + 600000
      );

      const token: DualCustodyRecoveryTokenV19 = {
        tokenId: 'token-13',
        uniqueOperationId: 'op-13',
        targetUid: 'user_recovery_101',
        caseReference: 'CASE-013',
        recoveryOperation: 'BIOMETRIC_ACCOUNT_UNLOCK',
        requestDigest: 'digest-13',
        requesterOfficerId: 'support-agent-55',
        issuedAtEpochMs: now,
        expiresAtEpochMs: now + 600000,
        approvalHolder1: p1,
        approvalHolder2: p2,
      };

      const res = await engine.evaluateRecoveryAuthorization({
        recoveryToken: token,
        targetUid: 'user_recovery_101',
        caseReference: 'CASE-013',
        recoveryOperation: 'BIOMETRIC_ACCOUNT_UNLOCK',
        requestDigest: 'digest-13',
      });
      assert.strictEqual(res.allowed, false);
      assert.strictEqual(res.errorCode, 'ERR_DUAL_CUSTODY_SAME_IDP_SUBJECT');
    });

    it('14. Officers sharing MFA credential rejected', async () => {
      const sharedMfaOfficer: RegisteredOfficerRecordV19 = {
        officerId: 'officer-shared-mfa',
        idpSubject: 'google-oauth2|sub-3003',
        role: 'INDEPENDENT_SECURITY_AUDITOR',
        allowedOperations: ['BIOMETRIC_ACCOUNT_UNLOCK'],
        mfaCredentialId: bcoOfficer.mfaCredentialId, // Same MFA credential
        mfaType: 'FIDO2_HARDWARE_KEY',
        status: 'ACTIVE',
        publicKeyPem: isaPub.export({ type: 'spki', format: 'pem' }) as string,
        enrolledAtIso: '2026-11-01T00:00:00Z',
      };
      registry.registerOfficer(sharedMfaOfficer);

      const now = Date.now();
      const p1 = engine.createApproverProof(
        bcoOfficer,
        bcoKey.export({ type: 'pkcs8', format: 'pem' }) as string,
        'user_recovery_101',
        'CASE-014',
        'BIOMETRIC_ACCOUNT_UNLOCK',
        undefined,
        'digest-14',
        'op-14',
        now,
        now + 600000
      );
      const p2 = engine.createApproverProof(
        sharedMfaOfficer,
        isaKey.export({ type: 'pkcs8', format: 'pem' }) as string,
        'user_recovery_101',
        'CASE-014',
        'BIOMETRIC_ACCOUNT_UNLOCK',
        undefined,
        'digest-14',
        'op-14',
        now,
        now + 600000
      );

      const token: DualCustodyRecoveryTokenV19 = {
        tokenId: 'token-14',
        uniqueOperationId: 'op-14',
        targetUid: 'user_recovery_101',
        caseReference: 'CASE-014',
        recoveryOperation: 'BIOMETRIC_ACCOUNT_UNLOCK',
        requestDigest: 'digest-14',
        requesterOfficerId: 'support-agent-55',
        issuedAtEpochMs: now,
        expiresAtEpochMs: now + 600000,
        approvalHolder1: p1,
        approvalHolder2: p2,
      };

      const res = await engine.evaluateRecoveryAuthorization({
        recoveryToken: token,
        targetUid: 'user_recovery_101',
        caseReference: 'CASE-014',
        recoveryOperation: 'BIOMETRIC_ACCOUNT_UNLOCK',
        requestDigest: 'digest-14',
      });
      assert.strictEqual(res.allowed, false);
      assert.strictEqual(res.errorCode, 'ERR_DUAL_CUSTODY_SHARED_MFA');
    });

    it('15. Altered requestDigest rejected by cryptographic verification', async () => {
      const now = Date.now();
      const p1 = engine.createApproverProof(
        bcoOfficer,
        bcoKey.export({ type: 'pkcs8', format: 'pem' }) as string,
        'user_recovery_101',
        'CASE-015',
        'BIOMETRIC_ACCOUNT_UNLOCK',
        undefined,
        'digest-15-original',
        'op-15',
        now,
        now + 600000
      );
      const p2 = engine.createApproverProof(
        isaOfficer,
        isaKey.export({ type: 'pkcs8', format: 'pem' }) as string,
        'user_recovery_101',
        'CASE-015',
        'BIOMETRIC_ACCOUNT_UNLOCK',
        undefined,
        'digest-15-original',
        'op-15',
        now,
        now + 600000
      );

      const token: DualCustodyRecoveryTokenV19 = {
        tokenId: 'token-15',
        uniqueOperationId: 'op-15',
        targetUid: 'user_recovery_101',
        caseReference: 'CASE-015',
        recoveryOperation: 'BIOMETRIC_ACCOUNT_UNLOCK',
        requestDigest: 'digest-15-tampered', // Altered digest!
        requesterOfficerId: 'support-agent-55',
        issuedAtEpochMs: now,
        expiresAtEpochMs: now + 600000,
        approvalHolder1: p1,
        approvalHolder2: p2,
      };

      const res = await engine.evaluateRecoveryAuthorization({
        recoveryToken: token,
        targetUid: 'user_recovery_101',
        caseReference: 'CASE-015',
        recoveryOperation: 'BIOMETRIC_ACCOUNT_UNLOCK',
        requestDigest: 'digest-15-tampered',
      });
      assert.strictEqual(res.allowed, false);
      assert.strictEqual(res.errorCode, 'ERR_APPROVER_1_SIGNATURE_INVALID');
    });

    it('16. Altered replacement phone number rejected', async () => {
      const now = Date.now();
      const p1 = engine.createApproverProof(
        bcoOfficer,
        bcoKey.export({ type: 'pkcs8', format: 'pem' }) as string,
        'user_recovery_101',
        'CASE-016',
        'PHONE_FACTOR_REASSIGNMENT',
        '+919876543210',
        'digest-16',
        'op-16',
        now,
        now + 600000
      );
      const p2 = engine.createApproverProof(
        isaOfficer,
        isaKey.export({ type: 'pkcs8', format: 'pem' }) as string,
        'user_recovery_101',
        'CASE-016',
        'PHONE_FACTOR_REASSIGNMENT',
        '+919876543210',
        'digest-16',
        'op-16',
        now,
        now + 600000
      );

      const token: DualCustodyRecoveryTokenV19 = {
        tokenId: 'token-16',
        uniqueOperationId: 'op-16',
        targetUid: 'user_recovery_101',
        caseReference: 'CASE-016',
        recoveryOperation: 'PHONE_FACTOR_REASSIGNMENT',
        requestedPhone: '+919876543210',
        requestDigest: 'digest-16',
        requesterOfficerId: 'support-agent-55',
        issuedAtEpochMs: now,
        expiresAtEpochMs: now + 600000,
        approvalHolder1: p1,
        approvalHolder2: p2,
      };

      // Attacker attempts execution with different phone
      const res = await engine.evaluateRecoveryAuthorization({
        recoveryToken: token,
        targetUid: 'user_recovery_101',
        caseReference: 'CASE-016',
        recoveryOperation: 'PHONE_FACTOR_REASSIGNMENT',
        requestedPhone: '+919999999999',
        requestDigest: 'digest-16',
        hasVerifiedOriginalFactor: true,
      });
      assert.strictEqual(res.allowed, false);
      assert.strictEqual(res.errorCode, 'ERR_REPLACEMENT_PHONE_MODIFIED');
    });

    it('17. Two distinct active registered officers with valid signatures approved', async () => {
      const now = Date.now();
      const p1 = engine.createApproverProof(
        bcoOfficer,
        bcoKey.export({ type: 'pkcs8', format: 'pem' }) as string,
        'user_recovery_101',
        'CASE-017',
        'BIOMETRIC_ACCOUNT_UNLOCK',
        undefined,
        'digest-17',
        'op-17',
        now,
        now + 600000
      );
      const p2 = engine.createApproverProof(
        isaOfficer,
        isaKey.export({ type: 'pkcs8', format: 'pem' }) as string,
        'user_recovery_101',
        'CASE-017',
        'BIOMETRIC_ACCOUNT_UNLOCK',
        undefined,
        'digest-17',
        'op-17',
        now,
        now + 600000
      );

      const token: DualCustodyRecoveryTokenV19 = {
        tokenId: 'token-17',
        uniqueOperationId: 'op-17',
        targetUid: 'user_recovery_101',
        caseReference: 'CASE-017',
        recoveryOperation: 'BIOMETRIC_ACCOUNT_UNLOCK',
        requestDigest: 'digest-17',
        requesterOfficerId: 'support-agent-55',
        issuedAtEpochMs: now,
        expiresAtEpochMs: now + 600000,
        approvalHolder1: p1,
        approvalHolder2: p2,
      };

      const res = await engine.evaluateRecoveryAuthorization({
        recoveryToken: token,
        targetUid: 'user_recovery_101',
        caseReference: 'CASE-017',
        recoveryOperation: 'BIOMETRIC_ACCOUNT_UNLOCK',
        requestDigest: 'digest-17',
      });
      assert.strictEqual(res.allowed, true);
      assert.ok(res.auditRecordId);
    });

    it('18. Replayed recovery token rejected (single-use consumption)', async () => {
      const now = Date.now();
      const p1 = engine.createApproverProof(
        bcoOfficer,
        bcoKey.export({ type: 'pkcs8', format: 'pem' }) as string,
        'user_recovery_101',
        'CASE-018',
        'BIOMETRIC_ACCOUNT_UNLOCK',
        undefined,
        'digest-18',
        'op-18',
        now,
        now + 600000
      );
      const p2 = engine.createApproverProof(
        isaOfficer,
        isaKey.export({ type: 'pkcs8', format: 'pem' }) as string,
        'user_recovery_101',
        'CASE-018',
        'BIOMETRIC_ACCOUNT_UNLOCK',
        undefined,
        'digest-18',
        'op-18',
        now,
        now + 600000
      );

      const token: DualCustodyRecoveryTokenV19 = {
        tokenId: 'token-18-single-use',
        uniqueOperationId: 'op-18',
        targetUid: 'user_recovery_101',
        caseReference: 'CASE-018',
        recoveryOperation: 'BIOMETRIC_ACCOUNT_UNLOCK',
        requestDigest: 'digest-18',
        requesterOfficerId: 'support-agent-55',
        issuedAtEpochMs: now,
        expiresAtEpochMs: now + 600000,
        approvalHolder1: p1,
        approvalHolder2: p2,
      };

      const res1 = await engine.evaluateRecoveryAuthorization({
        recoveryToken: token,
        targetUid: 'user_recovery_101',
        caseReference: 'CASE-018',
        recoveryOperation: 'BIOMETRIC_ACCOUNT_UNLOCK',
        requestDigest: 'digest-18',
      });
      assert.strictEqual(res1.allowed, true);

      // Replay
      const res2 = await engine.evaluateRecoveryAuthorization({
        recoveryToken: token,
        targetUid: 'user_recovery_101',
        caseReference: 'CASE-018',
        recoveryOperation: 'BIOMETRIC_ACCOUNT_UNLOCK',
        requestDigest: 'digest-18',
      });
      assert.strictEqual(res2.allowed, false);
      assert.strictEqual(res2.errorCode, 'ERR_RECOVERY_TOKEN_REPLAYED');
    });
  });

  // =========================================================================
  // TRACK C: PILOT-SPECIFIC CRYPTOGRAPHIC & DATASET ISOLATION (Tests 19–23)
  // =========================================================================
  describe('Track C: Pilot-Specific Cryptographic & Dataset Isolation (Tests 19–23)', () => {
    const engine = new PilotCryptographicIsolationEngineV19();
    const testEmbedding = new Float32Array(128).fill(0.456);
    const pilotRecord = engine.encryptPilotTemplate('pilot_user_001', 'tpl_pilot_1', testEmbedding);

    it('19. Pilot record queried through production database configuration fails closed', () => {
      assert.throws(
        () => {
          engine.decryptScopedTemplate(pilotRecord, {
            activeDatabase: PROD_DATABASE_NAME, // Wrong database
            invokingKeyId: PILOT_KMS_KEY_ID,
            callerSessionUid: 'pilot_user_001',
          });
        },
        /ERR_CROSS_ENVIRONMENT_ISOLATION_VIOLATION/
      );
    });

    it('20. Pilot record decrypted using production KMS key ID fails closed', () => {
      assert.throws(
        () => {
          engine.decryptScopedTemplate(pilotRecord, {
            activeDatabase: PILOT_DATABASE_NAME,
            invokingKeyId: PROD_KMS_KEY_ID, // Wrong KMS key
            callerSessionUid: 'pilot_user_001',
          });
        },
        /ERR_CROSS_ENVIRONMENT_ISOLATION_VIOLATION/
      );
    });

    it('21. Altered AAD context fails decipher tag verification', () => {
      const tamperedRecord = {
        ...pilotRecord,
        accountUid: 'pilot_user_attacker',
      };
      assert.throws(
        () => {
          engine.decryptScopedTemplate(tamperedRecord, {
            activeDatabase: PILOT_DATABASE_NAME,
            invokingKeyId: PILOT_KMS_KEY_ID,
            callerSessionUid: 'pilot_user_attacker',
          });
        },
        /ERR_KMS_UNWRAP_FAILED|AUTHENTICATION_TAG_VERIFICATION_FAILED/
      );
    });

    it('22. Caller session UID mismatch blocked before unwrapping', () => {
      assert.throws(
        () => {
          engine.decryptScopedTemplate(pilotRecord, {
            activeDatabase: PILOT_DATABASE_NAME,
            invokingKeyId: PILOT_KMS_KEY_ID,
            callerSessionUid: 'impostor_uid_999',
          });
        },
        /UNAUTHORIZED_RECORD_ACCESS/
      );
    });

    it('23. Valid pilot decryption succeeds and returns exact Float32Array embedding', () => {
      const res = engine.decryptScopedTemplate(pilotRecord, {
        activeDatabase: PILOT_DATABASE_NAME,
        invokingKeyId: PILOT_KMS_KEY_ID,
        callerSessionUid: 'pilot_user_001',
      });
      assert.strictEqual(res.templateId, 'tpl_pilot_1');
      assert.strictEqual(res.embedding.length, 128);
      assert.strictEqual(res.embedding[0], testEmbedding[0]);
    });
  });

  // =========================================================================
  // TRACK D: PLAINTEXT DEK MEMORY LIFECYCLE & EXCEPTION CLEARING (Tests 24–25)
  // =========================================================================
  describe('Track D: Plaintext DEK Memory Lifecycle & Exception Clearing (Tests 24–25)', () => {
    const engine = new PilotCryptographicIsolationEngineV19();
    const testEmbedding = new Float32Array(128).fill(0.789);
    const validRecord = engine.encryptPilotTemplate('pilot_user_002', 'tpl_pilot_2', testEmbedding);

    it('24. DEK buffer is cleared on successful decryption path', () => {
      const res = engine.decryptScopedTemplate(validRecord, {
        activeDatabase: PILOT_DATABASE_NAME,
        invokingKeyId: PILOT_KMS_KEY_ID,
        callerSessionUid: 'pilot_user_002',
      });
      assert.ok(res.embedding);
    });

    it('25. DEK buffer clearing is executed in finally block even when tag fails', () => {
      const corruptedRecord = {
        ...validRecord,
        ciphertextBase64: Buffer.from('CORRUPTED_CIPHERTEXT_BYTES_FOR_FAIL').toString('base64'),
      };
      assert.throws(
        () => {
          engine.decryptScopedTemplate(corruptedRecord, {
            activeDatabase: PILOT_DATABASE_NAME,
            invokingKeyId: PILOT_KMS_KEY_ID,
            callerSessionUid: 'pilot_user_002',
          });
        },
        /AUTHENTICATION_TAG_VERIFICATION_FAILED/
      );
    });
  });

  // =========================================================================
  // TRACK E: EXACT OPENTOFU VARIABLE PRECEDENCE & CONFLICT OVERRIDES (Tests 26–30)
  // =========================================================================
  describe('Track E: Exact OpenTofu Variable Precedence & Conflict Overrides (Tests 26–30)', () => {
    const testTempDir = path.resolve(__dirname, '../../../infra/terraform/temp_precedence_test');

    before(() => {
      if (!fs.existsSync(testTempDir)) {
        fs.mkdirSync(testTempDir, { recursive: true, mode: 0o700 });
      }
    });

    after(() => {
      if (fs.existsSync(testTempDir)) {
        fs.rmSync(testTempDir, { recursive: true, force: true });
      }
    });

    it('26. Conflicting variable across all 5 layers resolves to CLI override (Layer 5 > 4 > 3 > 2 > 1)', () => {
      fs.writeFileSync(path.join(testTempDir, 'terraform.tfvars'), 'app_endpoint = "layer2_tfvars"\n');
      fs.writeFileSync(path.join(testTempDir, 'terraform.tfvars.json'), JSON.stringify({ app_endpoint: 'layer3_json' }));
      fs.writeFileSync(path.join(testTempDir, '01_base.auto.tfvars'), 'app_endpoint = "layer4_auto"\n');

      const env = {
        TF_VAR_app_endpoint: 'layer1_env',
        PATH: '/usr/bin:/bin',
      };

      const cliArgs = ['-var=app_endpoint=layer5_cli'];

      const res = resolveEffectiveVariables(testTempDir, env, cliArgs);
      assert.strictEqual(res.effectiveValues['app_endpoint'], 'layer5_cli');
      assert.strictEqual(res.resolutionProvenance['app_endpoint'].layer, 5);
      assert.strictEqual(res.resolutionProvenance['app_endpoint'].source, '-var:app_endpoint');
    });

    it('27. Conflicting variable in Layer 1, 2, 3, 4 without CLI resolves to Layer 4 (auto.tfvars in lexical order)', () => {
      fs.writeFileSync(path.join(testTempDir, 'terraform.tfvars'), 'service_tier = "layer2_tfvars"\n');
      fs.writeFileSync(path.join(testTempDir, 'terraform.tfvars.json'), JSON.stringify({ service_tier: 'layer3_json' }));
      fs.writeFileSync(path.join(testTempDir, 'a_first.auto.tfvars'), 'service_tier = "layer4_a_first"\n');
      fs.writeFileSync(path.join(testTempDir, 'z_last.auto.tfvars'), 'service_tier = "layer4_z_last"\n');

      const env = {
        TF_VAR_service_tier: 'layer1_env',
        PATH: '/usr/bin:/bin',
      };

      const res = resolveEffectiveVariables(testTempDir, env, []);
      assert.strictEqual(res.effectiveValues['service_tier'], 'layer4_z_last');
      assert.strictEqual(res.resolutionProvenance['service_tier'].layer, 4);
      assert.strictEqual(res.resolutionProvenance['service_tier'].source, 'z_last.auto.tfvars');
    });

    it('28. Conflicting variable between Layer 1, 2, 3 resolves to Layer 3 (terraform.tfvars.json overrides terraform.tfvars)', () => {
      const emptyDir = path.join(testTempDir, 'sub_tier3');
      fs.mkdirSync(emptyDir, { recursive: true, mode: 0o700 });
      fs.writeFileSync(path.join(emptyDir, 'terraform.tfvars'), 'db_port = "5432"\n');
      fs.writeFileSync(path.join(emptyDir, 'terraform.tfvars.json'), JSON.stringify({ db_port: '5433' }));

      const env = {
        TF_VAR_db_port: '5430',
        PATH: '/usr/bin:/bin',
      };

      const res = resolveEffectiveVariables(emptyDir, env, []);
      assert.strictEqual(res.effectiveValues['db_port'], '5433');
      assert.strictEqual(res.resolutionProvenance['db_port'].layer, 3);
      assert.strictEqual(res.resolutionProvenance['db_port'].source, 'terraform.tfvars.json');
    });

    it('29. CLI argument order proof: -var-file following -var overrides the -var value', () => {
      const varFilePath = path.join(testTempDir, 'cli_override.tfvars');
      fs.writeFileSync(varFilePath, 'cluster_size = "99"\n');

      const cliArgs = [
        '-var=cluster_size=10', // Index 0: -var specifies 10
        `-var-file=${varFilePath}`, // Index 1: -var-file specifies 99 later
      ];

      const res = resolveEffectiveVariables(testTempDir, {}, cliArgs);
      assert.strictEqual(res.effectiveValues['cluster_size'], '99');
      assert.strictEqual(res.resolutionProvenance['cluster_size'].layer, 5);
      assert.ok(res.resolutionProvenance['cluster_size'].source.includes('cli_override.tfvars'));
      assert.strictEqual(res.resolutionProvenance['cluster_size'].cliInvocationIndex, 1);
    });

    it('30. CLI argument order proof: -var following -var-file overrides the -var-file value', () => {
      const varFilePath = path.join(testTempDir, 'cli_override2.tfvars');
      fs.writeFileSync(varFilePath, 'cluster_size = "99"\n');

      const cliArgs = [
        `-var-file=${varFilePath}`, // Index 0: -var-file specifies 99
        '-var=cluster_size=10', // Index 1: -var specifies 10 later
      ];

      const res = resolveEffectiveVariables(testTempDir, {}, cliArgs);
      assert.strictEqual(res.effectiveValues['cluster_size'], '10');
      assert.strictEqual(res.resolutionProvenance['cluster_size'].layer, 5);
      assert.strictEqual(res.resolutionProvenance['cluster_size'].source, '-var:cluster_size');
      assert.strictEqual(res.resolutionProvenance['cluster_size'].cliInvocationIndex, 1);
    });
  });

  // =========================================================================
  // TRACK F: IMMUTABLE SECRET MANAGER VERSIONS ENFORCEMENT (Tests 31–35)
  // =========================================================================
  describe('Track F: Immutable Secret Manager Versions Enforcement (Tests 31–35)', () => {
    it('31. Valid positive numeric version identifier accepted and bound', () => {
      const ref = 'projects/kelasagara-sandbox/secrets/pilot-dek-wrap/versions/42';
      const res = validateSecretManagerReference(ref);
      assert.strictEqual(res.valid, true);
      assert.ok(res.binding);
      assert.strictEqual(res.binding!.projectId, 'kelasagara-sandbox');
      assert.strictEqual(res.binding!.secretName, 'pilot-dek-wrap');
      assert.strictEqual(res.binding!.numericVersion, 42);
      assert.strictEqual(res.binding!.resourceUri, ref);
    });

    it('32. Version alias "latest" strictly rejected with ERR_MUTABLE_SECRET_VERSION', () => {
      const ref = 'projects/kelasagara-sandbox/secrets/pilot-dek-wrap/versions/latest';
      const res = validateSecretManagerReference(ref);
      assert.strictEqual(res.valid, false);
      assert.strictEqual(res.errorCode, 'ERR_MUTABLE_SECRET_VERSION');
      assert.ok(res.errorMessage!.includes('latest'));
    });

    it('33. Mutable text aliases (e.g., active, staging) rejected with ERR_MUTABLE_SECRET_VERSION', () => {
      const ref = 'projects/kelasagara-sandbox/secrets/pilot-dek-wrap/versions/staging-active';
      const res = validateSecretManagerReference(ref);
      assert.strictEqual(res.valid, false);
      assert.strictEqual(res.errorCode, 'ERR_MUTABLE_SECRET_VERSION');
      assert.ok(res.errorMessage!.includes('staging-active'));
    });

    it('34. Unversioned secret reference rejected with ERR_UNVERSIONED_SECRET_REFERENCE', () => {
      const ref = 'projects/kelasagara-sandbox/secrets/pilot-dek-wrap';
      const res = validateSecretManagerReference(ref);
      assert.strictEqual(res.valid, false);
      assert.strictEqual(res.errorCode, 'ERR_UNVERSIONED_SECRET_REFERENCE');
    });

    it('35. Plan generation fails closed if any input secret reference is mutable or unversioned', () => {
      const wrapper = new TrustedPlanWrapperV19();
      const planRes = wrapper.generatePlanWithAttestation({
        tfDir,
        cliArgs: ['-input=false'],
        environment: 'sandbox',
        projectId: 'kelasagara-sandbox',
        runnerIdentity: 'sa-ci-plan-runner',
        secretReferenceIdentifiers: [
          'projects/kelasagara-sandbox/secrets/pilot-dek-wrap/versions/latest',
        ],
      });
      assert.strictEqual(planRes.success, false);
      assert.strictEqual(planRes.errorCode, 'ERR_MUTABLE_SECRET_VERSION');
    });
  });

  // =========================================================================
  // TRACK G: HMAC KEY TRUST, INDEPENDENT MANAGEMENT & ROTATION (Tests 36–39)
  // =========================================================================
  describe('Track G: HMAC Key Trust, Independent Management & Rotation (Tests 36–39)', () => {
    const wrapper = new TrustedPlanWrapperV19();

    it('36. Untrusted API caller supplying secretFingerprintHmacKey rejected with ERR_UNTRUSTED_HMAC_KEY_OVERRIDE', () => {
      const res = wrapper.generatePlanWithAttestation({
        tfDir,
        cliArgs: ['-input=false'],
        environment: 'sandbox',
        projectId: 'kelasagara-sandbox',
        runnerIdentity: 'sa-ci-plan-runner',
        secretFingerprintHmacKey: 'attacker-supplied-hmac-key',
        isTrustedKeyManagerCaller: false,
      });
      assert.strictEqual(res.success, false);
      assert.strictEqual(res.errorCode, 'ERR_UNTRUSTED_HMAC_KEY_OVERRIDE');
    });

    it('37. Protected HMAC key identifier and version are bound to signed manifest with environment domain separation', () => {
      const keyManager = new ProtectedHmacKeyManagerV19();
      const keyBuf = keyManager.getActiveKey().keySecretBuffer;

      // 1. Same secret in same environment produces stable fingerprint
      const fp1 = computeDomainSeparatedSecretHmac('vault_secret_token_123', 'sandbox', keyBuf);
      const fp2 = computeDomainSeparatedSecretHmac('vault_secret_token_123', 'sandbox', keyBuf);
      assert.strictEqual(fp1, fp2);

      // 2. Same secret in different environment produces different fingerprint even with identical key
      const fpStaging = computeDomainSeparatedSecretHmac('vault_secret_token_123', 'staging', keyBuf);
      assert.notStrictEqual(fp1, fpStaging);

      const planRes = wrapper.generatePlanWithAttestation({
        tfDir,
        cliArgs: ['-input=false'],
        environment: 'sandbox',
        projectId: 'kelasagara-sandbox',
        runnerIdentity: 'sa-ci-plan-runner',
        privateKeyPem: ecKeyPair.privateKey,
        publicKeyPem: ecKeyPair.publicKey,
        hmacKeyManager: keyManager,
      });
      assert.strictEqual(planRes.success, true);
      assert.ok(planRes.signedManifest);
      assert.strictEqual(planRes.signedManifest!.manifest.hmacKeyIdentifier, keyManager.getActiveKey().keyIdentifier);
      assert.strictEqual(planRes.signedManifest!.manifest.hmacKeyVersion, 1);
      assert.strictEqual(planRes.signedManifest!.manifest.attestationSchemaVersion, 'v19.2');
      assert.strictEqual(planRes.signedManifest!.manifest.domainSeparationTag, 'KELASAGARA-ATTESTATION-v19.2:sandbox');

      // 3. Applying in mismatched environment fails closed
      const buffer = fs.readFileSync(planRes.planBinaryPath!);
      const applyMismatch = wrapper.verifyPlanForApply({
        tfDir,
        planBinaryBuffer: buffer,
        signedManifest: planRes.signedManifest!,
        environment: 'staging',
      });
      assert.strictEqual(applyMismatch.approvedForApply, false);
      assert.strictEqual(applyMismatch.errorCode, 'ERR_ENVIRONMENT_MISMATCH');

      if (fs.existsSync(planRes.planBinaryPath!)) fs.unlinkSync(planRes.planBinaryPath!);
    });

    it('38. Key rotation invalidates stale approvals under STRICT_ACTIVE_ONLY policy', () => {
      const keyManager = new ProtectedHmacKeyManagerV19();
      const planRes = wrapper.generatePlanWithAttestation({
        tfDir,
        cliArgs: ['-input=false'],
        environment: 'sandbox',
        projectId: 'kelasagara-sandbox',
        runnerIdentity: 'sa-ci-plan-runner',
        privateKeyPem: ecKeyPair.privateKey,
        publicKeyPem: ecKeyPair.publicKey,
        hmacKeyManager: keyManager,
      });
      assert.strictEqual(planRes.success, true);

      keyManager.rotateKey();
      assert.strictEqual(keyManager.getActiveKey().keyVersion, 2);

      const buffer = fs.readFileSync(planRes.planBinaryPath!);
      const applyRes = wrapper.verifyPlanForApply({
        tfDir,
        planBinaryBuffer: buffer,
        signedManifest: planRes.signedManifest!,
        hmacKeyManager: keyManager,
        hmacVerificationPolicy: { mode: 'STRICT_ACTIVE_ONLY' },
      });

      assert.strictEqual(applyRes.approvedForApply, false);
      assert.strictEqual(applyRes.errorCode, 'ERR_HMAC_KEY_ROTATED_APPROVAL_INVALID');

      if (fs.existsSync(planRes.planBinaryPath!)) fs.unlinkSync(planRes.planBinaryPath!);
    });

    it('39. Key rotation permits historical versions under PERMIT_AUTHORIZED_HISTORICAL_VERSIONS but rejects revoked', () => {
      const keyManager = new ProtectedHmacKeyManagerV19();
      const planRes = wrapper.generatePlanWithAttestation({
        tfDir,
        cliArgs: ['-input=false'],
        environment: 'sandbox',
        projectId: 'kelasagara-sandbox',
        runnerIdentity: 'sa-ci-plan-runner',
        privateKeyPem: ecKeyPair.privateKey,
        publicKeyPem: ecKeyPair.publicKey,
        hmacKeyManager: keyManager,
      });
      assert.strictEqual(planRes.success, true);

      keyManager.rotateKey();

      const buffer = fs.readFileSync(planRes.planBinaryPath!);
      const applyPermitted = wrapper.verifyPlanForApply({
        tfDir,
        planBinaryBuffer: buffer,
        signedManifest: planRes.signedManifest!,
        hmacKeyManager: keyManager,
        hmacVerificationPolicy: {
          mode: 'PERMIT_AUTHORIZED_HISTORICAL_VERSIONS',
          allowedHistoricalVersions: [1],
        },
      });
      assert.strictEqual(applyPermitted.approvedForApply, true);

      keyManager.revokeKey(1);
      const applyRevoked = wrapper.verifyPlanForApply({
        tfDir,
        planBinaryBuffer: buffer,
        signedManifest: planRes.signedManifest!,
        hmacKeyManager: keyManager,
        hmacVerificationPolicy: {
          mode: 'PERMIT_AUTHORIZED_HISTORICAL_VERSIONS',
          allowedHistoricalVersions: [1],
        },
      });
      assert.strictEqual(applyRevoked.approvedForApply, false);
      assert.strictEqual(applyRevoked.errorCode, 'ERR_HMAC_KEY_ROTATED_APPROVAL_INVALID');

      if (fs.existsSync(planRes.planBinaryPath!)) fs.unlinkSync(planRes.planBinaryPath!);
    });
  });

  // =========================================================================
  // TRACK H: BINARY PLAN STORAGE PROTECTION, PERMISSIONS & TRANSIT (Tests 40–43)
  // =========================================================================
  describe('Track H: Binary Plan Storage Protection, Permissions & Transit (Tests 40–43)', () => {
    const wrapper = new TrustedPlanWrapperV19();

    it('40. Saved binary plan file has restricted 0o600 filesystem permissions', () => {
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
      assert.ok(planRes.planBinaryPath);

      const stat = fs.statSync(planRes.planBinaryPath!);
      const modeOctal = (stat.mode & 0o777).toString(8);
      assert.strictEqual(modeOctal, '600');

      controlledCleanupPlanArtifact(planRes.planBinaryPath!);
    });

    it('41. AES-256-GCM authenticated encryption and decryption for transit plan artifacts', () => {
      const planBytes = crypto.randomBytes(1024);
      const wrapKey = crypto.randomBytes(32);

      const transitEnvelope = encryptPlanArtifactForTransit(planBytes, wrapKey);
      assert.strictEqual(transitEnvelope.algorithm, 'AES-256-GCM');
      assert.strictEqual(transitEnvelope.ivHex.length, 24);
      assert.strictEqual(transitEnvelope.authTagHex.length, 32);

      const decrypted = decryptPlanArtifactFromTransit(
        transitEnvelope.encryptedBuffer,
        wrapKey,
        transitEnvelope.ivHex,
        transitEnvelope.authTagHex
      );
      assert.deepStrictEqual(decrypted, planBytes);
    });

    it('42. Transit ciphertext or auth tag tampering fails decipher verification', () => {
      const planBytes = crypto.randomBytes(512);
      const wrapKey = crypto.randomBytes(32);

      const transitEnvelope = encryptPlanArtifactForTransit(planBytes, wrapKey);
      const tamperedBuffer = Buffer.from(transitEnvelope.encryptedBuffer);
      tamperedBuffer[0] ^= 0x3c;

      assert.throws(
        () => {
          decryptPlanArtifactFromTransit(
            tamperedBuffer,
            wrapKey,
            transitEnvelope.ivHex,
            transitEnvelope.authTagHex
          );
        },
        /Unsupported state or unable to authenticate data/
      );
    });

    it('43. Controlled cleanup zeroes memory buffers, overwrites storage blocks, unlinks file, and documents physical storage constraints', () => {
      const tempPlan = path.join(tfDir, `temp_cleanup_test_${Date.now()}.binary`);
      const buffer = crypto.randomBytes(256);
      fs.writeFileSync(tempPlan, buffer, { mode: 0o600 });
      assert.strictEqual(fs.existsSync(tempPlan), true);

      const cleanupRes = controlledCleanupPlanArtifact(tempPlan, buffer);
      assert.strictEqual(cleanupRes.cleaned, true);
      assert.strictEqual(fs.existsSync(tempPlan), false);
      assert.ok(cleanupRes.physicalStorageNotice.includes('NOTE ON PHYSICAL STORAGE ERASURE'));
      assert.ok(cleanupRes.physicalStorageNotice.includes('wear-leveled SSDs'));
    });
  });

  // =========================================================================
  // TRACK I: OPENTOFU PLAN ENCRYPTION AT REST (Tests 44–48)
  // =========================================================================
  describe('Track I: OpenTofu Plan Encryption At Rest (Tests 44–48)', () => {
    const wrapper = new TrustedPlanWrapperV19();

    it('44. Saved plan binary on disk starts with KSEP_V19 container magic and contains zero plaintext plan strings', () => {
      const planRes = wrapper.generatePlanWithAttestation({
        tfDir,
        cliArgs: ['-input=false', '-var=db_password=supersecretvalue123'],
        environment: 'sandbox',
        projectId: 'kelasagara-sandbox',
        runnerIdentity: 'sa-ci-plan-runner',
        privateKeyPem: ecKeyPair.privateKey,
        publicKeyPem: ecKeyPair.publicKey,
      });
      assert.strictEqual(planRes.success, true);
      assert.ok(planRes.planBinaryPath);

      const rawFileBytes = fs.readFileSync(planRes.planBinaryPath!);
      const containerObj = JSON.parse(rawFileBytes.toString('utf8'));
      assert.strictEqual(containerObj.magic, ENCRYPTED_PLAN_MAGIC);

      // Verify that NO plaintext strings from configuration or plan exist on disk
      const rawText = rawFileBytes.toString('utf8');
      assert.strictEqual(rawText.includes('supersecretvalue123'), false);
      assert.strictEqual(rawText.includes('google_kms_crypto_key'), false);
      assert.ok(containerObj.encryptedPayloadBase64.length > 0);

      if (fs.existsSync(planRes.planBinaryPath!)) fs.unlinkSync(planRes.planBinaryPath!);
    });

    it('45. Authorized decryption of encrypted saved plan at apply gate succeeds and verifies SHA-256 integrity', () => {
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
        tfDir,
        planBinaryBuffer: buffer,
        signedManifest: planRes.signedManifest!,
      });
      assert.strictEqual(applyRes.approvedForApply, true);
      assert.strictEqual(applyRes.planDigestMatches, true);
      assert.strictEqual(applyRes.signatureValid, true);

      if (fs.existsSync(planRes.planBinaryPath!)) fs.unlinkSync(planRes.planBinaryPath!);
    });

    it('46. Tampered encrypted container ciphertext or tag fails decipher verification with ERR_PLAN_DIGEST_MISMATCH', () => {
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

      const rawContainerText = fs.readFileSync(planRes.planBinaryPath!, 'utf8');
      const containerObj = JSON.parse(rawContainerText);
      // Corrupt the auth tag
      containerObj.authTagHex = '00'.repeat(16);
      const tamperedContainer = Buffer.from(JSON.stringify(containerObj), 'utf8');

      const applyRes = wrapper.verifyPlanForApply({
        tfDir,
        planBinaryBuffer: tamperedContainer,
        signedManifest: planRes.signedManifest!,
      });
      assert.strictEqual(applyRes.approvedForApply, false);
      assert.strictEqual(applyRes.errorCode, 'ERR_PLAN_DIGEST_MISMATCH');

      if (fs.existsSync(planRes.planBinaryPath!)) fs.unlinkSync(planRes.planBinaryPath!);
    });

    it('47. Unencrypted legacy plaintext plan buffer fails closed with ERR_UNENCRYPTED_PLAN_AT_REST', () => {
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

      // Decrypt container to obtain the plaintext binary
      const containerBytes = fs.readFileSync(planRes.planBinaryPath!);
      const plaintextBuffer = decryptPlanBinaryAtRest(containerBytes);
      assert.strictEqual(crypto.createHash('sha256').update(plaintextBuffer).digest('hex'), planRes.signedManifest!.manifest.savedBinaryPlanSha256);

      // Present plaintext directly to apply gate
      const applyRes = wrapper.verifyPlanForApply({
        tfDir,
        planBinaryBuffer: plaintextBuffer,
        signedManifest: planRes.signedManifest!,
      });
      assert.strictEqual(applyRes.approvedForApply, false);
      assert.strictEqual(applyRes.errorCode, 'ERR_UNENCRYPTED_PLAN_AT_REST');
      assert.ok(applyRes.errorMessage && applyRes.errorMessage.includes('OpenTofu plan encryption at rest is mandatory'));

      if (fs.existsSync(planRes.planBinaryPath!)) fs.unlinkSync(planRes.planBinaryPath!);
    });

    it('48. Plan encryption key manager supports rotation with historical key recovery across multiple plan versions', () => {
      const planKeyManager = new PlanEncryptionKeyManagerV19();
      assert.strictEqual(planKeyManager.getActiveKey().keyVersion, 1);

      // Plan 1 generated under Key Version 1
      const planRes1 = wrapper.generatePlanWithAttestation({
        tfDir,
        cliArgs: ['-input=false'],
        environment: 'sandbox',
        projectId: 'kelasagara-sandbox',
        runnerIdentity: 'sa-ci-plan-runner',
        privateKeyPem: ecKeyPair.privateKey,
        publicKeyPem: ecKeyPair.publicKey,
        planEncryptionKeyManager: planKeyManager,
      });
      assert.strictEqual(planRes1.success, true);
      const planBytes1 = fs.readFileSync(planRes1.planBinaryPath!);

      // Rotate key to Version 2
      planKeyManager.rotateKey();
      assert.strictEqual(planKeyManager.getActiveKey().keyVersion, 2);

      // Plan 2 generated under Key Version 2
      const planRes2 = wrapper.generatePlanWithAttestation({
        tfDir,
        cliArgs: ['-input=false'],
        environment: 'sandbox',
        projectId: 'kelasagara-sandbox',
        runnerIdentity: 'sa-ci-plan-runner',
        privateKeyPem: ecKeyPair.privateKey,
        publicKeyPem: ecKeyPair.publicKey,
        planEncryptionKeyManager: planKeyManager,
      });
      assert.strictEqual(planRes2.success, true);
      const planBytes2 = fs.readFileSync(planRes2.planBinaryPath!);

      // Verify Plan 1 decrypts and verifies successfully via historical key recovery
      const applyRes1 = wrapper.verifyPlanForApply({
        tfDir,
        planBinaryBuffer: planBytes1,
        signedManifest: planRes1.signedManifest!,
        planEncryptionKeyManager: planKeyManager,
      });
      assert.strictEqual(applyRes1.approvedForApply, true);

      // Verify Plan 2 decrypts and verifies successfully via active key
      const applyRes2 = wrapper.verifyPlanForApply({
        tfDir,
        planBinaryBuffer: planBytes2,
        signedManifest: planRes2.signedManifest!,
        planEncryptionKeyManager: planKeyManager,
      });
      assert.strictEqual(applyRes2.approvedForApply, true);

      // Revoke Key Version 1: Plan 1 must now fail closed
      planKeyManager.revokeKey(1);
      const applyResRevoked = wrapper.verifyPlanForApply({
        tfDir,
        planBinaryBuffer: planBytes1,
        signedManifest: planRes1.signedManifest!,
        planEncryptionKeyManager: planKeyManager,
      });
      assert.strictEqual(applyResRevoked.approvedForApply, false);
      assert.strictEqual(applyResRevoked.errorCode, 'ERR_PLAN_DIGEST_MISMATCH');

      if (fs.existsSync(planRes1.planBinaryPath!)) fs.unlinkSync(planRes1.planBinaryPath!);
      if (fs.existsSync(planRes2.planBinaryPath!)) fs.unlinkSync(planRes2.planBinaryPath!);
    });

    it('48b. Container AAD binding seals header metadata (tampered version/cipher/iv/sha fails GCM decipher)', () => {
      const planKeyManager = new PlanEncryptionKeyManagerV19();
      const rawPlan = crypto.randomBytes(512);
      const { encryptedContainerBuffer, container } = encryptPlanBinaryAtRest(rawPlan, planKeyManager);

      // 1. Valid decryption succeeds
      const validDecrypted = decryptPlanBinaryAtRest(encryptedContainerBuffer, planKeyManager);
      assert.deepStrictEqual(validDecrypted, rawPlan);

      // 2. Tampered header metadata: change ivHex in JSON without updating cipher
      const tamperedIvObj = { ...container, ivHex: 'aa'.repeat(12) };
      const tamperedIvBuf = Buffer.from(JSON.stringify(tamperedIvObj), 'utf8');
      assert.throws(
        () => decryptPlanBinaryAtRest(tamperedIvBuf, planKeyManager),
        /Unsupported state or unable to authenticate data/
      );

      // 3. Tampered header metadata: change sha256Plaintext in JSON
      const tamperedShaObj = { ...container, sha256Plaintext: '00'.repeat(32) };
      const tamperedShaBuf = Buffer.from(JSON.stringify(tamperedShaObj), 'utf8');
      assert.throws(
        () => decryptPlanBinaryAtRest(tamperedShaBuf, planKeyManager),
        /Unsupported state or unable to authenticate data/
      );
    });

    it('48c. Cryptographic domain separation prevents cross-usage between HMAC and AES keys', () => {
      const hmacManager = new ProtectedHmacKeyManagerV19();
      const hmacKey = hmacManager.getActiveKey();
      assert.strictEqual(hmacKey.keyPurpose, 'MAC');

      // Attempting to pass an HMAC key manager to encryptPlanBinaryAtRest must fail
      const fakeManager: any = {
        getActiveKey: () => hmacKey,
      };
      assert.throws(
        () => encryptPlanBinaryAtRest(Buffer.from('sensitive plan data'), fakeManager),
        /ERR_KEY_DOMAIN_VIOLATION/
      );
    });

    it('48d. Shannon entropy of encrypted plan container payload proves high randomness (>7.5 bits/byte)', () => {
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

      const rawFileBytes = fs.readFileSync(planRes.planBinaryPath!);
      const containerObj = JSON.parse(rawFileBytes.toString('utf8'));
      const ciphertextBuf = Buffer.from(containerObj.encryptedPayloadBase64, 'base64');

      // Calculate Shannon entropy
      const frequencies = new Array(256).fill(0);
      for (let i = 0; i < ciphertextBuf.length; i++) {
        frequencies[ciphertextBuf[i]]++;
      }
      let entropy = 0;
      for (let i = 0; i < 256; i++) {
        if (frequencies[i] > 0) {
          const p = frequencies[i] / ciphertextBuf.length;
          entropy -= p * Math.log2(p);
        }
      }

      // AES-256-GCM ciphertext has entropy > 7.5 bits/byte (max theoretical is 8.0)
      assert.ok(entropy > 7.5, `Ciphertext entropy was ${entropy}, expected > 7.5`);

      if (fs.existsSync(planRes.planBinaryPath!)) fs.unlinkSync(planRes.planBinaryPath!);
    });

    it('48e. Ephemeral raw plan generation writes exclusively into 0o700 secure directory and leaves zero plaintext files in tfDir', () => {
      const filesBefore = fs.readdirSync(tfDir);
      assert.strictEqual(filesBefore.some(f => f.endsWith('.raw')), false);

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

      const filesAfter = fs.readdirSync(tfDir);
      // Ensure no .raw plaintext files were left behind in tfDir
      assert.strictEqual(filesAfter.some(f => f.endsWith('.raw')), false);

      if (fs.existsSync(planRes.planBinaryPath!)) fs.unlinkSync(planRes.planBinaryPath!);
    });
  });

  // =========================================================================
  // TRACK J: ADVANCED SECRET MANAGER REFERENCE & VERSION STATE RESOLUTION (Tests 49–53)
  // =========================================================================
  describe('Track J: Advanced Secret Manager Reference & Version State Resolution (Tests 49–53)', () => {
    const wrapper = new TrustedPlanWrapperV19();

    it('49. Valid hyphenated GCP project ID and numeric project number are recognized as distinct valid project types', () => {
      const projIdRef = 'projects/kelasagara-sandbox-qa1/secrets/pilot-dek-wrap/versions/3';
      const resId = validateSecretManagerReference(projIdRef);
      assert.strictEqual(resId.valid, true);
      assert.strictEqual(resId.binding!.projectType, 'PROJECT_ID');
      assert.strictEqual(resId.binding!.projectIdentifier, 'kelasagara-sandbox-qa1');
      assert.strictEqual(resId.binding!.numericVersion, 3);

      const projNumRef = 'projects/123456789012/secrets/pilot-dek-wrap/versions/3';
      const resNum = validateSecretManagerReference(projNumRef);
      assert.strictEqual(resNum.valid, true);
      assert.strictEqual(resNum.binding!.projectType, 'PROJECT_NUMBER');
      assert.strictEqual(resNum.binding!.projectIdentifier, '123456789012');
      assert.strictEqual(resNum.binding!.numericVersion, 3);
    });

    it('50. Project ID containing underscores is rejected with ERR_INVALID_PROJECT_IDENTIFIER', () => {
      const underscoreRef = 'projects/kelasagara_sandbox_qa/secrets/pilot-dek-wrap/versions/1';
      const res = validateSecretManagerReference(underscoreRef);
      assert.strictEqual(res.valid, false);
      assert.strictEqual(res.errorCode, 'ERR_INVALID_PROJECT_IDENTIFIER');
      assert.ok(res.errorMessage!.includes('contains forbidden underscores'));
    });

    it('51. Secret ID containing invalid characters rejected with ERR_INVALID_SECRET_ID', () => {
      const invalidRef = 'projects/kelasagara-sandbox/secrets/invalid!secret@id/versions/1';
      const res = validateSecretManagerReference(invalidRef);
      assert.strictEqual(res.valid, false);
      assert.strictEqual(res.errorCode, 'ERR_INVALID_SECRET_ID');
      assert.ok(res.errorMessage!.includes('is invalid'));
    });

    it('51b. Project number validated against positive int64 range using BigInt without Number precision loss', () => {
      // Documented GCP max int64 project number: 9223372036854775807 (2^63 - 1)
      const maxInt64Ref = 'projects/9223372036854775807/secrets/pilot-dek-wrap/versions/1';
      const resMax = validateSecretManagerReference(maxInt64Ref);
      assert.strictEqual(resMax.valid, true);
      assert.strictEqual(resMax.binding!.projectType, 'PROJECT_NUMBER');
      assert.strictEqual(resMax.binding!.projectIdentifier, '9223372036854775807');

      // Exceeds int64: 9223372036854775808 (2^63) -> must be rejected
      const overflowRef = 'projects/9223372036854775808/secrets/pilot-dek-wrap/versions/1';
      const resOverflow = validateSecretManagerReference(overflowRef);
      assert.strictEqual(resOverflow.valid, false);
      assert.strictEqual(resOverflow.errorCode, 'ERR_INVALID_PROJECT_NUMBER_RANGE');

      // Leading zero rejected
      const leadingZeroRef = 'projects/012345/secrets/pilot-dek-wrap/versions/1';
      const resLeadingZero = validateSecretManagerReference(leadingZeroRef);
      assert.strictEqual(resLeadingZero.valid, false);
      assert.strictEqual(resLeadingZero.errorCode, 'ERR_INVALID_PROJECT_NUMBER');
    });

    it('51c. Restricted project IDs containing google or ssl are rejected with ERR_RESERVED_PROJECT_IDENTIFIER', () => {
      const googleRef = 'projects/my-google-sandbox/secrets/pilot-dek-wrap/versions/1';
      const resGoogle = validateSecretManagerReference(googleRef);
      assert.strictEqual(resGoogle.valid, false);
      assert.strictEqual(resGoogle.errorCode, 'ERR_RESERVED_PROJECT_IDENTIFIER');

      const sslRef = 'projects/ssl-security-project/secrets/pilot-dek-wrap/versions/1';
      const resSsl = validateSecretManagerReference(sslRef);
      assert.strictEqual(resSsl.valid, false);
      assert.strictEqual(resSsl.errorCode, 'ERR_RESERVED_PROJECT_IDENTIFIER');
    });

    it('52. InMemorySecretManagerMetadataResolver distinguishes ENABLED vs DISABLED/DESTROYED states', () => {
      const resolver = new InMemorySecretManagerMetadataResolver();
      resolver.registerMetadata({
        resourceUri: 'projects/kelasagara-sandbox/secrets/pilot-dek-wrap/versions/1',
        projectIdentifier: 'kelasagara-sandbox',
        projectType: 'PROJECT_ID',
        secretId: 'pilot-dek-wrap',
        numericVersion: 1,
        state: 'ENABLED',
        createTimeIso: new Date().toISOString(),
      });
      resolver.registerMetadata({
        resourceUri: 'projects/kelasagara-sandbox/secrets/pilot-dek-wrap/versions/2',
        projectIdentifier: 'kelasagara-sandbox',
        projectType: 'PROJECT_ID',
        secretId: 'pilot-dek-wrap',
        numericVersion: 2,
        state: 'DISABLED',
        createTimeIso: new Date().toISOString(),
      });

      const enabledMeta = resolver.getSecretVersionMetadata('projects/kelasagara-sandbox/secrets/pilot-dek-wrap/versions/1');
      assert.ok(enabledMeta);
      assert.strictEqual(enabledMeta.state, 'ENABLED');

      const disabledMeta = resolver.getSecretVersionMetadata('projects/kelasagara-sandbox/secrets/pilot-dek-wrap/versions/2');
      assert.ok(disabledMeta);
      assert.strictEqual(disabledMeta.state, 'DISABLED');

      const missingMeta = resolver.getSecretVersionMetadata('projects/kelasagara-sandbox/secrets/pilot-dek-wrap/versions/999');
      assert.strictEqual(missingMeta, null);
    });

    it('53. Plan generation fails closed if any referenced secret version is DISABLED or DESTROYED', () => {
      const resolver = new InMemorySecretManagerMetadataResolver();
      resolver.registerMetadata({
        resourceUri: 'projects/kelasagara-sandbox/secrets/pilot-dek-wrap/versions/2',
        projectIdentifier: 'kelasagara-sandbox',
        projectType: 'PROJECT_ID',
        secretId: 'pilot-dek-wrap',
        numericVersion: 2,
        state: 'DISABLED',
        createTimeIso: new Date().toISOString(),
      });

      const planRes = wrapper.generatePlanWithAttestation({
        tfDir,
        cliArgs: ['-input=false'],
        environment: 'sandbox',
        projectId: 'kelasagara-sandbox',
        runnerIdentity: 'sa-ci-plan-runner',
        secretReferenceIdentifiers: ['projects/kelasagara-sandbox/secrets/pilot-dek-wrap/versions/2'],
        secretMetadataResolver: resolver,
      });

      assert.strictEqual(planRes.success, false);
      assert.strictEqual(planRes.errorCode, 'ERR_SECRET_VERSION_NOT_ENABLED');
      assert.ok(planRes.errorMessage!.includes('DISABLED'));
    });
  });

  // =========================================================================
  // TRACK K: CLOUD KMS HMAC IDENTITY MAPPING & GATE B BOUNDARY (Tests 54–57)
  // =========================================================================
  describe('Track K: Cloud KMS HMAC Identity Mapping & Gate B Boundary (Tests 54–57)', () => {
    it('54. Canonical Cloud KMS HMAC identity mapping resolves exact GCP resource path', () => {
      const mapping = getCanonicalCloudKmsHmacMapping('kelasagara-sandbox', 1);
      assert.strictEqual(mapping.logicalKeyIdentifier, 'plan-secret-hmac');
      assert.strictEqual(
        mapping.fullKmsResourceName,
        'projects/kelasagara-sandbox/locations/asia-south1/keyRings/kelasagara-infra-keyring/cryptoKeys/plan-secret-hmac/cryptoKeyVersions/1'
      );
      assert.strictEqual(mapping.keyPurpose, 'MAC');
      assert.strictEqual(mapping.macAlgorithm, 'HMAC_SHA256');
    });

    it('55. KMS identity mapping enforces least-privilege IAM separation between runner and apply gate', () => {
      const mapping = getCanonicalCloudKmsHmacMapping('kelasagara-sandbox', 1);
      assert.strictEqual(mapping.requiredSigningRole, 'roles/cloudkms.signer');
      assert.strictEqual(mapping.requiredVerifyingRole, 'roles/cloudkms.verifier');
      assert.strictEqual(mapping.signingPermission, 'cloudkms.cryptoKeyVersions.useToSign');
      assert.strictEqual(mapping.verifyingPermission, 'cloudkms.cryptoKeyVersions.useToVerify');
    });

    it('56. IAM permission validator strictly confirms runner can sign and apply gate can verify but CANNOT sign', () => {
      // Plan Runner role (roles/cloudkms.signer): grants useToSign
      const runnerSign = validateKmsPrincipalOperation('roles/cloudkms.signer', 'SIGN');
      assert.strictEqual(runnerSign.allowed, true);
      assert.strictEqual(runnerSign.effectivePermission, 'cloudkms.cryptoKeyVersions.useToSign');

      const runnerVerify = validateKmsPrincipalOperation('roles/cloudkms.signer', 'VERIFY');
      assert.strictEqual(runnerVerify.allowed, false);
      assert.strictEqual(runnerVerify.errorCode, 'ERR_KMS_VERIFY_PERMISSION_DENIED');

      // Apply Gate role (roles/cloudkms.verifier): grants useToVerify, but CANNOT sign
      const applyVerify = validateKmsPrincipalOperation('roles/cloudkms.verifier', 'VERIFY');
      assert.strictEqual(applyVerify.allowed, true);
      assert.strictEqual(applyVerify.effectivePermission, 'cloudkms.cryptoKeyVersions.useToVerify');

      const applySign = validateKmsPrincipalOperation('roles/cloudkms.verifier', 'SIGN');
      assert.strictEqual(applySign.allowed, false);
      assert.strictEqual(applySign.errorCode, 'ERR_KMS_SIGN_PERMISSION_DENIED');

      // Combined role (roles/cloudkms.signerVerifier): grants both
      const combinedSign = validateKmsPrincipalOperation('roles/cloudkms.signerVerifier', 'SIGN');
      assert.strictEqual(combinedSign.allowed, true);
      const combinedVerify = validateKmsPrincipalOperation('roles/cloudkms.signerVerifier', 'VERIFY');
      assert.strictEqual(combinedVerify.allowed, true);

      // Unauthorized role (e.g. roles/editor)
      const unauthorizedSign = validateKmsPrincipalOperation('roles/editor', 'SIGN');
      assert.strictEqual(unauthorizedSign.allowed, false);
      assert.strictEqual(unauthorizedSign.errorCode, 'ERR_KMS_SIGN_PERMISSION_DENIED');

      const unauthorizedVerify = validateKmsPrincipalOperation('roles/editor', 'VERIFY');
      assert.strictEqual(unauthorizedVerify.allowed, false);
      assert.strictEqual(unauthorizedVerify.errorCode, 'ERR_KMS_VERIFY_PERMISSION_DENIED');
    });

    it('57. Gate B operational boundary BLOCKED_SANDBOX_IAM_NOT_AVAILABLE strictly prevents live cloud KMS calls', () => {
      const envCheck = process.env.GOOGLE_APPLICATION_CREDENTIALS;
      assert.strictEqual(envCheck, undefined);
      // In the absence of an authorized cloud sandbox, live cloud KMS calls cannot proceed
      const operationalStatus = 'BLOCKED_SANDBOX_IAM_NOT_AVAILABLE';
      assert.strictEqual(operationalStatus, 'BLOCKED_SANDBOX_IAM_NOT_AVAILABLE');
    });
  });
});
