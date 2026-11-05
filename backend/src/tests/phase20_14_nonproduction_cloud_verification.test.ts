/**
 * KELASAGARA V20.14: NON-PRODUCTION CLOUD SECURITY & IAM INDEPENDENT AUDIT SUITE
 *
 * Implements the 10 mandatory IAM least-privilege tests, Terraform static policy
 * validation, and sandbox availability verification specified in KELASAGARA V20.14.
 */

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  evaluateIamPermission,
  validateTerraformConfiguration,
  checkSandboxCloudAvailability,
  PRODUCTION_PROJECT_DENYLIST,
} from '../services/iam_policy_verifier_v14';

describe('KELASAGARA V20.14: Non-Production Cloud Security & IAM Audit Suite', () => {
  describe('Workstream B: Mandatory Least-Privilege IAM Permission Tests (Tests 1–10)', () => {
    it('1. Enrollment identity can perform its authorized operation: write pending template & wrap DEK', () => {
      const writeResult = evaluateIamPermission(
        'sa-biometrics-enrollment',
        'datastore.entities.create',
        'projects/kelasagara-sandbox/databases/(default)/documents/biometric_vault'
      );
      assert.equal(writeResult.allowed, true);

      const kmsWrapResult = evaluateIamPermission(
        'sa-biometrics-enrollment',
        'cloudkms.cryptoKeyVersions.useToEncrypt',
        'projects/kelasagara-sandbox/locations/asia-south1/keyRings/biometrics/cryptoKeys/biometric-dek-wrap-key'
      );
      assert.equal(kmsWrapResult.allowed, true);
    });

    it('2. Verifier cannot modify biometric templates: write/delete denied for sa-biometrics-verifier', () => {
      const createAttempt = evaluateIamPermission(
        'sa-biometrics-verifier',
        'datastore.entities.create',
        'projects/kelasagara-sandbox/databases/(default)/documents/biometric_vault'
      );
      assert.equal(createAttempt.allowed, false);
      assert.ok(createAttempt.reason.includes('DENIED'));

      const deleteAttempt = evaluateIamPermission(
        'sa-biometrics-verifier',
        'datastore.entities.delete',
        'projects/kelasagara-sandbox/databases/(default)/documents/biometric_vault'
      );
      assert.equal(deleteAttempt.allowed, false);
      assert.ok(deleteAttempt.reason.includes('DENIED'));
    });

    it('3. Reviewer cannot decrypt biometric templates: KMS unwrap DEK denied for sa-biometrics-reviewer', () => {
      const kmsDecryptAttempt = evaluateIamPermission(
        'sa-biometrics-reviewer',
        'cloudkms.cryptoKeyVersions.useToDecrypt',
        'projects/kelasagara-sandbox/locations/asia-south1/keyRings/biometrics/cryptoKeys/biometric-dek-wrap-key'
      );
      assert.equal(kmsDecryptAttempt.allowed, false);
      assert.ok(kmsDecryptAttempt.reason.includes('DENIED'));
    });

    it('4. Inventory identity cannot write or delete records: strictly read-only metadata viewer', () => {
      const writeAttempt = evaluateIamPermission(
        'sa-biometrics-inventory',
        'datastore.entities.create',
        'projects/kelasagara-sandbox/databases/(default)/documents/biometric_vault'
      );
      assert.equal(writeAttempt.allowed, false);

      const updateAttempt = evaluateIamPermission(
        'sa-biometrics-inventory',
        'datastore.entities.update',
        'projects/kelasagara-sandbox/databases/(default)/documents/biometric_vault'
      );
      assert.equal(updateAttempt.allowed, false);

      const deleteAttempt = evaluateIamPermission(
        'sa-biometrics-inventory',
        'datastore.entities.delete',
        'projects/kelasagara-sandbox/databases/(default)/documents/biometric_vault'
      );
      assert.equal(deleteAttempt.allowed, false);

      // Read metadata IS allowed
      const readResult = evaluateIamPermission(
        'sa-biometrics-inventory',
        'datastore.entities.get',
        'projects/kelasagara-sandbox/databases/(default)/documents/biometric_vault'
      );
      assert.equal(readResult.allowed, true);
    });

    it('5. Audit notary cannot change enrollment records: template updates denied for sa-biometrics-audit-notary', () => {
      const updateTemplateAttempt = evaluateIamPermission(
        'sa-biometrics-audit-notary',
        'datastore.entities.update',
        'projects/kelasagara-sandbox/databases/(default)/documents/biometric_vault'
      );
      assert.equal(updateTemplateAttempt.allowed, false);
      assert.ok(updateTemplateAttempt.reason.includes('DENIED'));
    });

    it('6. Ordinary service cannot invoke manifest signing without authorization', () => {
      const ordinarySignAttempt = evaluateIamPermission(
        'sa-ordinary-backend',
        'cloudkms.cryptoKeyVersions.useToSign',
        'projects/kelasagara-sandbox/locations/asia-south1/keyRings/biometrics/cryptoKeys/manifest-attestation-key'
      );
      assert.equal(ordinarySignAttempt.allowed, false);
      assert.ok(ordinarySignAttempt.reason.includes('DENIED'));
    });

    it('7. Unauthorized identity impersonation is denied: actAs permission blocked across services', () => {
      const impersonateAttempt = evaluateIamPermission(
        'sa-ordinary-backend',
        'iam.serviceAccounts.actAs',
        'projects/kelasagara-sandbox/serviceAccounts/sa-biometrics-audit-notary@'
      );
      assert.equal(impersonateAttempt.allowed, false);
      assert.ok(impersonateAttempt.reason.includes('DENIED'));
    });

    it('8. Unauthorized token creation is denied: serviceAccountTokens.create blocked without explicit binding', () => {
      const tokenCreateAttempt = evaluateIamPermission(
        'sa-biometrics-verifier',
        'iam.serviceAccountTokens.create',
        'projects/kelasagara-sandbox/serviceAccounts/sa-biometrics-enrollment@'
      );
      assert.equal(tokenCreateAttempt.allowed, false);
      assert.ok(tokenCreateAttempt.reason.includes('DENIED'));
    });

    it('9. Unauthorized service-account key creation is denied: disabled by organization policy constraint', () => {
      const keyCreateAttempt = evaluateIamPermission(
        'sa-biometrics-enrollment',
        'iam.serviceAccountKeys.create',
        'projects/kelasagara-sandbox/serviceAccounts/sa-biometrics-enrollment@'
      );
      assert.equal(keyCreateAttempt.allowed, false);
      assert.ok(keyCreateAttempt.reason.includes('iam.disableServiceAccountKeyCreation'));
    });

    it('10. Normal Flutter client cannot directly access protected template records: zero IAM vault permissions', () => {
      const clientVaultReadAttempt = evaluateIamPermission(
        'client-flutter-user',
        'datastore.entities.get',
        'projects/kelasagara-sandbox/databases/(default)/documents/biometric_vault'
      );
      assert.equal(clientVaultReadAttempt.allowed, false);

      const clientVaultWriteAttempt = evaluateIamPermission(
        'client-flutter-user',
        'datastore.entities.create',
        'projects/kelasagara-sandbox/databases/(default)/documents/biometric_vault'
      );
      assert.equal(clientVaultWriteAttempt.allowed, false);
    });
  });

  describe('Workstream B: Infrastructure-As-Code Static Policy & Safety Gates (Tests 11–15)', () => {
    it('11. Terraform project denylist strictly rejects production project IDs', () => {
      for (const prodProject of PRODUCTION_PROJECT_DENYLIST) {
        const result = validateTerraformConfiguration({
          projectId: prodProject,
          environment: 'sandbox',
          roleBindings: [],
        });
        assert.equal(result.valid, false);
        assert.ok(result.errors.some((err) => err.includes('matches a production identifier in the denylist')));
      }
    });

    it('12. Terraform policy linter strictly rejects primitive roles (roles/owner, roles/editor)', () => {
      const badConfig = {
        projectId: 'kelasagara-sandbox-01',
        environment: 'sandbox',
        roleBindings: [
          { role: 'roles/owner', principal: 'user:dev@example.com' },
          { role: 'roles/editor', principal: 'serviceAccount:sa-test@' },
        ],
      };
      const result = validateTerraformConfiguration(badConfig);
      assert.equal(result.valid, false);
      assert.equal(result.errors.length, 2);
      assert.ok(result.errors[0].includes('Primitive roles are strictly prohibited'));
    });

    it('13. Storage object deletion is globally blocked on immutable audit buckets', () => {
      const deleteAttempt = evaluateIamPermission(
        'sa-biometrics-audit-notary',
        'storage.objects.delete',
        'projects/kelasagara-sandbox/buckets/kelasagara-sandbox-biometric-audit-checkpoints'
      );
      assert.equal(deleteAttempt.allowed, false);
      assert.ok(deleteAttempt.reason.includes('Storage object deletion is globally forbidden'));
    });

    it('14. Explicit status check records BLOCKED_SANDBOX_IAM_NOT_AVAILABLE when cloud credentials are unset', () => {
      // Ensure environment has no live GCP sandbox credentials
      const availability = checkSandboxCloudAvailability();
      assert.equal(availability.available, false);
      assert.equal(availability.status, 'BLOCKED_SANDBOX_IAM_NOT_AVAILABLE');
      assert.ok(availability.message.includes('Per V20.14 Rule 10, live cloud validation is blocked'));
    });

    it('15. Collection-level IAM limitation verified: Datastore IAM applies at database level, requiring application-layer defense', () => {
      // In GCP Cloud IAM, roles/datastore.user applies to the entire database instance
      // Application layer must enforce collection whitelisting
      const enrollmentVaultAccess = evaluateIamPermission(
        'sa-biometrics-enrollment',
        'datastore.entities.create',
        'projects/kelasagara-sandbox/databases/(default)/documents/biometric_vault'
      );
      assert.equal(enrollmentVaultAccess.allowed, true);

      // Verifier cannot write to any collection in Datastore
      const verifierWriteAttempt = evaluateIamPermission(
        'sa-biometrics-verifier',
        'datastore.entities.create',
        'projects/kelasagara-sandbox/databases/(default)/documents/biometric_vault'
      );
      assert.equal(verifierWriteAttempt.allowed, false);
    });
  });
});
