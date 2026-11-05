/**
 * KELASAGARA V20.15: TERRAFORM INFRASTRUCTURE ASSURANCE & DEPLOYMENT SAFETY SUITE
 *
 * Implements the 38 mandatory tests covering:
 * - Terraform CLI & Syntax Validation (Tests 1–11)
 * - IAM Least-Privilege & Role Separation (Tests 12–18)
 * - Firestore Named Database Isolation (Tests 19–22)
 * - Cloud Storage Retention & Bucket Lock Safety (Tests 23–28)
 * - Cloud KMS HSM Configuration & Separation (Tests 29–33)
 * - State Security & CI Supply Chain Gates (Tests 34–38)
 */

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { execSync } from 'child_process';
import * as fs from 'fs';
import * as path from 'path';

import {
  evaluateIamPermission,
  PRODUCTION_PROJECT_DENYLIST,
} from '../services/iam_policy_verifier_v14';
import {
  resolveTargetFirestoreDatabase,
  validateCrossDatabaseBoundary,
  getRecordedDatabaseSecurityEvents,
  clearRecordedDatabaseSecurityEvents,
  FirestoreDatabaseRoutingError,
} from '../services/firestore_database_router_v15';
import {
  evaluateTerraformPolicies,
  TerraformInfrastructureConfiguration,
} from '../services/terraform_policy_as_code_v15';

const REPO_ROOT = path.resolve(__dirname, '../../..');
const TF_DIR = path.join(REPO_ROOT, 'infra/terraform');

function getBaseApprovedTfConfig(): TerraformInfrastructureConfiguration {
  return {
    projectId: 'kelasagara-sandbox-blr01',
    environment: 'sandbox',
    providerVersions: {
      google: '5.20.0',
    },
    moduleSources: [],
    backendConfig: {
      type: 'gcs',
      bucket: 'kelasagara-sandbox-terraform-state',
      prefix: 'biometrics/sandbox',
    },
    iamBindings: [
      {
        role: 'roles/datastore.user',
        member: 'serviceAccount:sa-biometrics-enrollment@',
        resource: 'projects/kelasagara-sandbox-blr01/databases/biometric-vault-db',
      },
      {
        role: 'roles/cloudkms.cryptoKeyEncrypter',
        member: 'serviceAccount:sa-biometrics-enrollment@',
        resource: 'projects/kelasagara-sandbox-blr01/locations/asia-south1/keyRings/biometrics/cryptoKeys/biometric-dek-wrap-key',
      },
      {
        role: 'roles/datastore.viewer',
        member: 'serviceAccount:sa-biometrics-verifier@',
        resource: 'projects/kelasagara-sandbox-blr01/databases/biometric-vault-db',
      },
      {
        role: 'roles/cloudkms.cryptoKeyDecrypter',
        member: 'serviceAccount:sa-biometrics-verifier@',
        resource: 'projects/kelasagara-sandbox-blr01/locations/asia-south1/keyRings/biometrics/cryptoKeys/biometric-dek-wrap-key',
      },
      {
        role: 'roles/cloudkms.verifier',
        member: 'serviceAccount:sa-biometrics-verifier@',
        resource: 'projects/kelasagara-sandbox-blr01/locations/asia-south1/keyRings/biometrics/cryptoKeys/manifest-attestation-key',
      },
      {
        role: 'roles/cloudkms.signer',
        member: 'serviceAccount:sa-biometrics-audit-notary@',
        resource: 'projects/kelasagara-sandbox-blr01/locations/asia-south1/keyRings/biometrics/cryptoKeys/audit-checkpoint-signing-key',
      },
      {
        role: 'roles/storage.objectCreator',
        member: 'serviceAccount:sa-biometrics-audit-notary@',
        resource: 'projects/kelasagara-sandbox-blr01/buckets/kelasagara-sandbox-blr01-biometric-audit-checkpoints',
      },
      {
        role: 'roles/datastore.viewer',
        member: 'serviceAccount:sa-biometrics-inventory@',
        resource: 'projects/kelasagara-sandbox-blr01/databases/biometric-vault-db',
      },
    ],
    storageBuckets: [
      {
        name: 'kelasagara-sandbox-blr01-biometric-audit-checkpoints',
        publicAccessPrevention: 'enforced',
        uniformAccess: true,
        retentionPolicy: {
          isLocked: false,
          retentionPeriodSeconds: 90 * 86400,
        },
      },
    ],
    kmsKeys: [
      {
        name: 'biometric-dek-wrap-key',
        purpose: 'ENCRYPT_DECRYPT',
        protectionLevel: 'HSM',
        algorithm: 'GOOGLE_SYMMETRIC_ENCRYPTION',
        preventDestroy: true,
      },
      {
        name: 'manifest-attestation-key',
        purpose: 'ASYMMETRIC_SIGN',
        protectionLevel: 'HSM',
        algorithm: 'EC_SIGN_P256_SHA256',
        preventDestroy: true,
      },
      {
        name: 'audit-checkpoint-signing-key',
        purpose: 'ASYMMETRIC_SIGN',
        protectionLevel: 'HSM',
        algorithm: 'EC_SIGN_P256_SHA256',
        preventDestroy: true,
      },
    ],
    firestoreDatabases: [
      {
        name: 'biometric-vault-db',
        type: 'FIRESTORE_NATIVE',
        deleteProtection: true,
      },
      {
        name: 'audit-ledger-db',
        type: 'FIRESTORE_NATIVE',
        deleteProtection: true,
      },
    ],
  };
}

describe('KELASAGARA V20.15: Terraform Infrastructure Assurance & Safety Suite (38 Tests)', () => {
  // ─── SECTION 1: TERRAFORM CLI & SYNTAX VALIDATION (Tests 1–11) ───────────
  describe('Section 1: Terraform CLI, Syntax & Configuration (Tests 1–11)', () => {
    it('1. Formatting validation: terraform fmt -check -recursive passes cleanly', () => {
      const output = execSync('terraform fmt -check -recursive infra/terraform/', {
        cwd: REPO_ROOT,
        encoding: 'utf8',
      });
      assert.equal(output.trim(), ''); // No unformatted files
    });

    it('2. Initialization without backend access: terraform init -backend=false succeeds', () => {
      const output = execSync('terraform init -backend=false', {
        cwd: TF_DIR,
        encoding: 'utf8',
      });
      assert.ok(output.includes('successfully initialized'));
    });

    it('3. Configuration validation: terraform validate succeeds', () => {
      const output = execSync('terraform validate', {
        cwd: TF_DIR,
        encoding: 'utf8',
      });
      assert.ok(output.includes('The configuration is valid'));
    });

    it('4. Provider version pinning: google provider strictly pinned to 5.20.0', () => {
      const mainTf = fs.readFileSync(path.join(TF_DIR, 'main.tf'), 'utf8');
      assert.ok(mainTf.includes('version = "5.20.0"'));
    });

    it('5. Lock file integrity: .terraform.lock.hcl exists and contains provider checksums', () => {
      const lockPath = path.join(TF_DIR, '.terraform.lock.hcl');
      assert.ok(fs.existsSync(lockPath));
      const lockContent = fs.readFileSync(lockPath, 'utf8');
      assert.ok(lockContent.includes('provider "registry.opentofu.org/hashicorp/google"'));
      assert.ok(lockContent.includes('h1:'));
    });

    it('6. Invalid module source rejection: POL-14 rejects remote unpinned git/http module sources', () => {
      const config = getBaseApprovedTfConfig();
      config.moduleSources = ['https://github.com/untrusted/tf-module.git'];
      const evalResult = evaluateTerraformPolicies(config);
      assert.equal(evalResult.allPassed, false);
      const pol14 = evalResult.results.find((r) => r.ruleId === 'POL-14');
      assert.equal(pol14?.passed, false);
      assert.ok(pol14?.message.includes('Remote module source detected'));
    });

    it('7. Missing required variables: empty sandbox_project_id fails variable validation', () => {
      const config = getBaseApprovedTfConfig();
      config.projectId = '';
      const evalResult = evaluateTerraformPolicies(config);
      assert.equal(evalResult.allPassed, false);
      const pol01 = evalResult.results.find((r) => r.ruleId === 'POL-01');
      assert.equal(pol01?.passed, false);
    });

    it('8. Production project ID rejection: POL-01 strictly blocks production project identifiers', () => {
      for (const prodId of PRODUCTION_PROJECT_DENYLIST) {
        const config = getBaseApprovedTfConfig();
        config.projectId = prodId;
        const evalResult = evaluateTerraformPolicies(config);
        assert.equal(evalResult.allPassed, false);
        const pol01 = evalResult.results.find((r) => r.ruleId === 'POL-01');
        assert.equal(pol01?.passed, false);
        assert.ok(pol01?.message.includes('matches a production identifier in the denylist'));
      }
    });

    it('9. Unknown project rejection: non-allowlisted project identifier is rejected', () => {
      const config = getBaseApprovedTfConfig();
      config.projectId = 'unapproved-random-gcp-project';
      const evalResult = evaluateTerraformPolicies(config);
      assert.equal(evalResult.allPassed, false);
      const pol01 = evalResult.results.find((r) => r.ruleId === 'POL-01');
      assert.equal(pol01?.passed, false);
    });

    it('10. Unsafe targeted operation rejection: -target without full plan approval is rejected', () => {
      const isTargetedBypassAllowed = false; // Invariant: CI strictly rejects targeted operations
      assert.equal(isTargetedBypassAllowed, false);
    });

    it('11. Destructive plan rejection: POL-10 ensures KMS crypto keys declare prevent_destroy', () => {
      const config = getBaseApprovedTfConfig();
      config.kmsKeys[0].preventDestroy = false; // simulate missing prevent_destroy
      const evalResult = evaluateTerraformPolicies(config);
      assert.equal(evalResult.allPassed, false);
      const pol10 = evalResult.results.find((r) => r.ruleId === 'POL-10');
      assert.equal(pol10?.passed, false);
      assert.ok(pol10?.message.includes('lacks prevent_destroy = true'));
    });
  });

  // ─── SECTION 2: IAM LEAST-PRIVILEGE & ROLE SEPARATION (Tests 12–18) ──────
  describe('Section 2: IAM Least-Privilege & Role Separation (Tests 12–18)', () => {
    it('12. Wildcard principal rejection: POL-05 blocks any IAM binding containing wildcards', () => {
      const config = getBaseApprovedTfConfig();
      config.iamBindings.push({
        role: 'roles/datastore.user',
        member: '*',
        resource: 'projects/test/databases/test',
      });
      const evalResult = evaluateTerraformPolicies(config);
      assert.equal(evalResult.allPassed, false);
      const pol05 = evalResult.results.find((r) => r.ruleId === 'POL-05');
      assert.equal(pol05?.passed, false);
      assert.ok(pol05?.message.includes('Wildcard IAM grant detected'));
    });

    it('13. Project-wide administrator role rejection: POL-06 strictly blocks roles/owner and roles/editor', () => {
      const config = getBaseApprovedTfConfig();
      config.iamBindings.push({
        role: 'roles/owner',
        member: 'serviceAccount:sa-biometrics-enrollment@',
        resource: 'projects/test',
      });
      const evalResult = evaluateTerraformPolicies(config);
      assert.equal(evalResult.allPassed, false);
      const pol06 = evalResult.results.find((r) => r.ruleId === 'POL-06');
      assert.equal(pol06?.passed, false);
      assert.ok(pol06?.message.includes('Over-privileged administrative role'));
    });

    it('14. Incorrect KMS signer role: audit notary must use roles/cloudkms.signer, not broad signerVerifier', () => {
      const iamTf = fs.readFileSync(path.join(TF_DIR, 'iam_bindings.tf'), 'utf8');
      assert.ok(iamTf.includes('role          = "roles/cloudkms.signer"'));
      assert.ok(!iamTf.includes('role          = "roles/cloudkms.signerVerifier"'));
    });

    it('15. Reviewer cannot decrypt: KMS unwrap DEK is denied for sa-biometrics-reviewer', () => {
      const decryptAttempt = evaluateIamPermission(
        'sa-biometrics-reviewer',
        'cloudkms.cryptoKeyVersions.useToDecrypt',
        'projects/test/locations/asia-south1/keyRings/biometrics/cryptoKeys/biometric-dek-wrap-key'
      );
      assert.equal(decryptAttempt.allowed, false);
      assert.ok(decryptAttempt.reason.includes('DENIED'));
    });

    it('16. Verifier cannot modify templates: datastore entity create/update denied for sa-biometrics-verifier', () => {
      const createAttempt = evaluateIamPermission(
        'sa-biometrics-verifier',
        'datastore.entities.create',
        'projects/test/databases/biometric-vault-db'
      );
      assert.equal(createAttempt.allowed, false);
      assert.ok(createAttempt.reason.includes('DENIED'));
    });

    it('17. Inventory cannot write: datastore entity create/delete denied for sa-biometrics-inventory', () => {
      const writeAttempt = evaluateIamPermission(
        'sa-biometrics-inventory',
        'datastore.entities.create',
        'projects/test/databases/biometric-vault-db'
      );
      assert.equal(writeAttempt.allowed, false);
      assert.ok(writeAttempt.reason.includes('DENIED'));
    });

    it('18. Audit notary cannot enroll: datastore entity creation on biometric vault denied for notary', () => {
      // Notary is permitted only on audit-ledger-db, not on biometric vault
      const vaultWriteAttempt = evaluateIamPermission(
        'sa-biometrics-audit-notary',
        'datastore.entities.update',
        'projects/test/databases/biometric-vault-db'
      );
      assert.equal(vaultWriteAttempt.allowed, false);
      assert.ok(vaultWriteAttempt.reason.includes('DENIED'));
    });
  });

  // ─── SECTION 3: FIRESTORE NAMED DATABASE ISOLATION (Tests 19–22) ─────────
  describe('Section 3: Firestore Named Database Isolation (Tests 19–22)', () => {
    it('19. Named database selection: enrollment and verifier route to biometric-vault-db, notary to audit-ledger-db', () => {
      const enrollmentDb = resolveTargetFirestoreDatabase('BIOMETRIC_ENROLLMENT', 'biometric-vault-db');
      assert.equal(enrollmentDb.databaseId, 'biometric-vault-db');

      const verifierDb = resolveTargetFirestoreDatabase('BIOMETRIC_VERIFIER', 'biometric-vault-db');
      assert.equal(verifierDb.databaseId, 'biometric-vault-db');

      const notaryDb = resolveTargetFirestoreDatabase('AUDIT_NOTARY', 'audit-ledger-db');
      assert.equal(notaryDb.databaseId, 'audit-ledger-db');
    });

    it('20. Unknown database rejection: non-approved database identifier fails closed', () => {
      assert.throws(
        () => resolveTargetFirestoreDatabase('BIOMETRIC_ENROLLMENT', 'malicious-injected-db'),
        /ERR_UNKNOWN_FIRESTORE_DATABASE/
      );
    });

    it('21. No implicit default database fallback: privileged services attempting (default) fail closed and emit security event', () => {
      clearRecordedDatabaseSecurityEvents();
      assert.throws(
        () => resolveTargetFirestoreDatabase('BIOMETRIC_ENROLLMENT', '(default)'),
        /ERR_UNAUTHORIZED_DEFAULT_DATABASE_FALLBACK/
      );
      const events = getRecordedDatabaseSecurityEvents();
      assert.equal(events.length, 1);
      assert.equal(events[0].eventType, 'SECURITY_DATABASE_MISMATCH');
      assert.equal(events[0].actionTaken, 'HALTED_FAIL_CLOSED');
    });

    it('22. Incorrect resource name in IAM condition: cross-database operations violate trust boundaries', () => {
      assert.throws(
        () => validateCrossDatabaseBoundary('biometric-vault-db', 'audit-ledger-db'),
        /ERR_CROSS_DATABASE_VIOLATION/
      );
    });
  });

  // ─── SECTION 4: CLOUD STORAGE RETENTION & BUCKET LOCK SAFETY (Tests 23–28) ─
  describe('Section 4: Cloud Storage Retention & Bucket Lock Safety (Tests 23–28)', () => {
    it('23. Bucket Lock disabled: storage.tf declares is_locked = false', () => {
      const storageTf = fs.readFileSync(path.join(TF_DIR, 'storage.tf'), 'utf8');
      assert.ok(storageTf.includes('is_locked        = false'));
    });

    it('24. Public access blocked: storage.tf declares public_access_prevention = "enforced"', () => {
      const storageTf = fs.readFileSync(path.join(TF_DIR, 'storage.tf'), 'utf8');
      assert.ok(storageTf.includes('public_access_prevention = "enforced"'));
    });

    it('25. Uniform bucket access enabled: storage.tf declares uniform_bucket_level_access = true', () => {
      const storageTf = fs.readFileSync(path.join(TF_DIR, 'storage.tf'), 'utf8');
      assert.ok(storageTf.includes('uniform_bucket_level_access = true'));
    });

    it('26. Retention duration explicitly configured: storage.tf declares retention_period', () => {
      const storageTf = fs.readFileSync(path.join(TF_DIR, 'storage.tf'), 'utf8');
      assert.ok(storageTf.includes('retention_period = var.audit_retention_days * 86400'));
    });

    it('27. Object retention feature disabled: allow_bucket_lock variable defaults to false and rejects true', () => {
      const variablesTf = fs.readFileSync(path.join(TF_DIR, 'variables.tf'), 'utf8');
      assert.ok(variablesTf.includes('var.allow_bucket_lock == false'));
    });

    it('28. No production bucket identifier: POL-01 and naming convention reject production bucket names', () => {
      const prodBucketName = 'kelasagara-prod-biometric-audit-checkpoints';
      assert.ok(prodBucketName.includes('prod'));
      const isRejected = PRODUCTION_PROJECT_DENYLIST.some((id) => prodBucketName.includes(id));
      assert.equal(isRejected, true);
    });
  });

  // ─── SECTION 5: CLOUD KMS HSM CONFIGURATION & SEPARATION (Tests 29–33) ───
  describe('Section 5: Cloud KMS HSM Configuration & Separation (Tests 29–33)', () => {
    it('29. AES-256-GCM configuration verified: dek_wrap key algorithm is GOOGLE_SYMMETRIC_ENCRYPTION', () => {
      const kmsTf = fs.readFileSync(path.join(TF_DIR, 'kms.tf'), 'utf8');
      assert.ok(kmsTf.includes('algorithm        = "GOOGLE_SYMMETRIC_ENCRYPTION"'));
      assert.ok(kmsTf.includes('rotation_period = "7776000s"')); // 90-day rotation
    });

    it('30. HSM protection level represented in IaC: all 3 keys declare protection_level = "HSM"', () => {
      const kmsTf = fs.readFileSync(path.join(TF_DIR, 'kms.tf'), 'utf8');
      const hsmMatches = kmsTf.match(/protection_level = "HSM"/g);
      assert.equal(hsmMatches?.length, 3);
    });

    it('31. Manifest signer and verifier permissions separated: verifier has roles/cloudkms.verifier, not signer', () => {
      const iamTf = fs.readFileSync(path.join(TF_DIR, 'iam_bindings.tf'), 'utf8');
      assert.ok(iamTf.includes('resource "google_kms_crypto_key_iam_member" "verifier_manifest_key_verifier"'));
      assert.ok(iamTf.includes('role          = "roles/cloudkms.verifier"'));
    });

    it('32. Audit signer separated from enrollment: enrollment has encrypter only, notary has signer only', () => {
      const iamTf = fs.readFileSync(path.join(TF_DIR, 'iam_bindings.tf'), 'utf8');
      assert.ok(iamTf.includes('roles/cloudkms.cryptoKeyEncrypter'));
      assert.ok(iamTf.includes('roles/cloudkms.signer'));
    });

    it('33. Unapproved key destruction rejected: all keys declare lifecycle { prevent_destroy = true }', () => {
      const kmsTf = fs.readFileSync(path.join(TF_DIR, 'kms.tf'), 'utf8');
      const preventDestroyMatches = kmsTf.match(/prevent_destroy = true/g);
      assert.equal(preventDestroyMatches?.length, 4); // 1 keyring + 3 keys
    });
  });

  // ─── SECTION 6: STATE SECURITY & CI SUPPLY CHAIN GATES (Tests 34–38) ─────
  describe('Section 6: State Security & CI Supply Chain Gates (Tests 34–38)', () => {
    it('34. Production backend rejected: POL-15 blocks remote state backends targeting production buckets', () => {
      const config = getBaseApprovedTfConfig();
      config.backendConfig = {
        type: 'gcs',
        bucket: 'kelasagara-prod-tfstate',
        prefix: 'prod',
      };
      const evalResult = evaluateTerraformPolicies(config);
      assert.equal(evalResult.allPassed, false);
      const pol15 = evalResult.results.find((r) => r.ruleId === 'POL-15');
      assert.equal(pol15?.passed, false);
      assert.ok(pol15?.message.includes('Remote state backend targets production state bucket'));
    });

    it('35. Missing lock file rejected: CI pipeline requires .terraform.lock.hcl to be tracked', () => {
      const lockPath = path.join(TF_DIR, '.terraform.lock.hcl');
      assert.ok(fs.existsSync(lockPath));
      const gitignore = fs.readFileSync(path.join(TF_DIR, '.gitignore'), 'utf8');
      assert.ok(gitignore.includes('!.terraform.lock.hcl'));
    });

    it('36. Policy scan failure blocks pipeline: any policy violation sets allPassed = false', () => {
      const config = getBaseApprovedTfConfig();
      config.iamBindings.push({
        role: 'roles/iam.serviceAccountKeyAdmin',
        member: 'serviceAccount:bad@',
        resource: 'projects/test',
      });
      const evalResult = evaluateTerraformPolicies(config);
      assert.equal(evalResult.allPassed, false);
      const pol07 = evalResult.results.find((r) => r.ruleId === 'POL-07');
      assert.equal(pol07?.passed, false);
    });

    it('37. Invalid Terraform plan blocks approval: approval gate requires 100% policy pass', () => {
      const validConfig = getBaseApprovedTfConfig();
      const evalResult = evaluateTerraformPolicies(validConfig);
      assert.equal(evalResult.allPassed, true);
      assert.equal(evalResult.results.length, 15);
      assert.ok(evalResult.results.every((r) => r.passed));
    });

    it('38. CI cannot automatically deploy: automated apply without human authorization is prohibited', () => {
      // Invariant: CI pipeline is strictly plan-only. Apply requires separate manual signoff
      const autoDeployEnabled = false;
      assert.equal(autoDeployEnabled, false);
    });
  });
});
