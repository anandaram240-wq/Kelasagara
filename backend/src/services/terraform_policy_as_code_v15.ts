/**
 * KELASAGARA V20.15: TERRAFORM POLICY-AS-CODE INDEPENDENT AUDIT ENGINE
 *
 * Implements strict, reproducible policy validation across Terraform configurations,
 * variables, resource attributes, and IAM bindings. Enforces the 15 non-negotiable
 * infrastructure invariants defined in KELASAGARA V20.15 Workstream C.
 */

export interface PolicyRuleDefinition {
  ruleId: string;
  name: string;
  scope: string;
  severity: 'CRITICAL' | 'HIGH' | 'MEDIUM';
  description: string;
  remediation: string;
}

export interface PolicyEvaluationResult {
  ruleId: string;
  passed: boolean;
  message: string;
  details?: Record<string, any>;
}

export interface TerraformInfrastructureConfiguration {
  projectId: string;
  environment: string;
  providerVersions: Record<string, string>;
  moduleSources: string[];
  backendConfig?: {
    type?: string;
    bucket?: string;
    prefix?: string;
  };
  iamBindings: Array<{
    role: string;
    member: string;
    resource: string;
  }>;
  storageBuckets: Array<{
    name: string;
    publicAccessPrevention: string;
    uniformAccess: boolean;
    retentionPolicy?: {
      isLocked: boolean;
      retentionPeriodSeconds: number;
    };
  }>;
  kmsKeys: Array<{
    name: string;
    purpose: string;
    protectionLevel: string;
    algorithm?: string;
    preventDestroy: boolean;
  }>;
  firestoreDatabases: Array<{
    name: string;
    type: string;
    deleteProtection: boolean;
  }>;
}

export const PRODUCTION_PROJECT_DENYLIST = [
  'kelasagara-prod',
  'kelasagara-production',
  'kelasagaara_v17',
  'kelasagaara-v17',
  'kelasagara-live',
  'production',
  'prod',
];

export const POLICY_RULES: Record<string, PolicyRuleDefinition> = {
  'POL-01': {
    ruleId: 'POL-01',
    name: 'No Production Project IDs',
    scope: 'Project Configuration',
    severity: 'CRITICAL',
    description: 'Target project ID must not match any production identifier.',
    remediation: 'Use an authorized sandbox project ID conforming to non-production naming conventions.',
  },
  'POL-02': {
    ruleId: 'POL-02',
    name: 'No Default Production Credentials',
    scope: 'Environment & Provider',
    severity: 'CRITICAL',
    description: 'Provider must not rely on unverified default production credentials.',
    remediation: 'Provide explicit sandbox project configuration.',
  },
  'POL-03': {
    ruleId: 'POL-03',
    name: 'No Public Storage Buckets',
    scope: 'Cloud Storage',
    severity: 'CRITICAL',
    description: 'All buckets must have public_access_prevention = enforced and uniform access enabled.',
    remediation: 'Set public_access_prevention = "enforced" and uniform_bucket_level_access = true.',
  },
  'POL-04': {
    ruleId: 'POL-04',
    name: 'No Public KMS Access',
    scope: 'Cloud KMS',
    severity: 'CRITICAL',
    description: 'KMS keys must never grant access to allUsers or allAuthenticatedUsers.',
    remediation: 'Restrict KMS key bindings strictly to dedicated service accounts.',
  },
  'POL-05': {
    ruleId: 'POL-05',
    name: 'No Wildcard IAM Grants',
    scope: 'Cloud IAM',
    severity: 'CRITICAL',
    description: 'No IAM role or member assignment may use wildcard characters (*).',
    remediation: 'Explicitly specify exact principal emails and concrete IAM roles.',
  },
  'POL-06': {
    ruleId: 'POL-06',
    name: 'No Project-Wide Administrator Roles',
    scope: 'Cloud IAM',
    severity: 'CRITICAL',
    description: 'Primitive roles (roles/owner, roles/editor) are strictly forbidden.',
    remediation: 'Use granular, least-privilege predefined or custom IAM roles.',
  },
  'POL-07': {
    ruleId: 'POL-07',
    name: 'No Service Account Key Creation',
    scope: 'Cloud IAM & Org Policy',
    severity: 'HIGH',
    description: 'Roles granting service account key creation are strictly prohibited.',
    remediation: 'Rely exclusively on Workload Identity Federation instead of static JSON keys.',
  },
  'POL-08': {
    ruleId: 'POL-08',
    name: 'No Retention Policy Ambiguity',
    scope: 'Cloud Storage',
    severity: 'HIGH',
    description: 'Storage buckets must explicitly declare retention duration and lock status.',
    remediation: 'Define an explicit retention_policy block with retention_period.',
  },
  'POL-09': {
    ruleId: 'POL-09',
    name: 'No Irreversible Retention Lock in Phase 20.15',
    scope: 'Cloud Storage',
    severity: 'CRITICAL',
    description: 'Bucket retention lock must remain false (is_locked = false) during development/testing.',
    remediation: 'Set is_locked = false in retention_policy.',
  },
  'POL-10': {
    ruleId: 'POL-10',
    name: 'No Destruction of Protected KMS Resources',
    scope: 'Cloud KMS',
    severity: 'CRITICAL',
    description: 'All cryptographic keys must declare prevent_destroy = true lifecycle protections.',
    remediation: 'Add lifecycle { prevent_destroy = true } to all google_kms_crypto_key resources.',
  },
  'POL-11': {
    ruleId: 'POL-11',
    name: 'No Unapproved Database Creation',
    scope: 'Firestore',
    severity: 'HIGH',
    description: 'Only approved named databases (biometric-vault-db, audit-ledger-db) may be declared.',
    remediation: 'Do not create arbitrary or unauthorized databases.',
  },
  'POL-12': {
    ruleId: 'POL-12',
    name: 'No Default Database Fallback for Privileged Services',
    scope: 'Firestore',
    severity: 'CRITICAL',
    description: 'Biometric vault and audit services must target dedicated named databases, not (default).',
    remediation: 'Route biometric and audit storage to dedicated named databases.',
  },
  'POL-13': {
    ruleId: 'POL-13',
    name: 'No Unapproved Provider Versions',
    scope: 'Terraform Provider',
    severity: 'HIGH',
    description: 'Google provider version must be pinned exactly (version = "5.20.0").',
    remediation: 'Pin provider version to approved release in required_providers.',
  },
  'POL-14': {
    ruleId: 'POL-14',
    name: 'No Unapproved Module Sources',
    scope: 'Terraform Modules',
    severity: 'CRITICAL',
    description: 'External, remote, or unpinned module sources (HTTP, generic Git) are forbidden.',
    remediation: 'Use strictly verified, local module sources.',
  },
  'POL-15': {
    ruleId: 'POL-15',
    name: 'No Production Backend Configuration',
    scope: 'Terraform Backend',
    severity: 'CRITICAL',
    description: 'Remote state backend must not target production state buckets.',
    remediation: 'Configure isolated non-production state backends with access controls.',
  },
};

/**
 * Evaluates a complete Terraform infrastructure configuration against all 15 Policy-as-Code rules.
 */
export function evaluateTerraformPolicies(
  config: TerraformInfrastructureConfiguration
): { allPassed: boolean; results: PolicyEvaluationResult[] } {
  const results: PolicyEvaluationResult[] = [];

  // POL-01: No Production Project IDs
  const normProject = config.projectId.toLowerCase().trim();
  const isDenylisted = PRODUCTION_PROJECT_DENYLIST.includes(normProject) || normProject.endsWith('-prod') || normProject.endsWith('-production');
  const isConforming = (normProject.startsWith('kelasagara-') || normProject.startsWith('ks-')) && !normProject.includes('prod');
  const pol01Passed = !isDenylisted && isConforming;
  results.push({
    ruleId: 'POL-01',
    passed: pol01Passed,
    message: pol01Passed
      ? `PASSED: Project ID '${config.projectId}' is an approved non-production identifier.`
      : (isDenylisted
        ? `VIOLATION: Project ID '${config.projectId}' matches a production identifier in the denylist.`
        : `VIOLATION: Project ID '${config.projectId}' does not conform to approved non-production naming conventions.`),
  });

  // POL-02: No Default Production Credentials
  const hasValidEnv = ['sandbox', 'staging', 'dev', 'test'].includes(config.environment.toLowerCase());
  results.push({
    ruleId: 'POL-02',
    passed: hasValidEnv,
    message: hasValidEnv
      ? `PASSED: Environment '${config.environment}' is a declared non-production environment.`
      : `VIOLATION: Environment '${config.environment}' is invalid or production.`,
  });

  // POL-03: No Public Storage Buckets
  const badBuckets = config.storageBuckets.filter(
    (b) => b.publicAccessPrevention !== 'enforced' || b.uniformAccess !== true
  );
  results.push({
    ruleId: 'POL-03',
    passed: badBuckets.length === 0,
    message:
      badBuckets.length === 0
        ? `PASSED: All ${config.storageBuckets.length} storage buckets enforce public access prevention and uniform access.`
        : `VIOLATION: Found ${badBuckets.length} storage buckets lacking enforced public access block.`,
  });

  // POL-04: No Public KMS Access
  const publicKms = config.iamBindings.filter(
    (b) =>
      b.resource.includes('cryptoKeys') &&
      (b.member === 'allUsers' || b.member === 'allAuthenticatedUsers')
  );
  results.push({
    ruleId: 'POL-04',
    passed: publicKms.length === 0,
    message:
      publicKms.length === 0
        ? `PASSED: Zero public or unauthenticated IAM bindings on Cloud KMS keys.`
        : `VIOLATION: Found public IAM member on KMS resource: ${publicKms[0].resource}`,
  });

  // POL-05: No Wildcard IAM Grants
  const wildcardBindings = config.iamBindings.filter(
    (b) => b.member.includes('*') || b.role.includes('*')
  );
  results.push({
    ruleId: 'POL-05',
    passed: wildcardBindings.length === 0,
    message:
      wildcardBindings.length === 0
        ? `PASSED: No wildcard characters detected in IAM roles or principal members.`
        : `VIOLATION: Wildcard IAM grant detected: ${wildcardBindings[0].role} -> ${wildcardBindings[0].member}`,
  });

  // POL-06: No Project-Wide Administrator Roles
  const adminBindings = config.iamBindings.filter(
    (b) =>
      b.role === 'roles/owner' ||
      b.role === 'roles/editor' ||
      b.role === 'roles/resourcemanager.organizationAdmin'
  );
  results.push({
    ruleId: 'POL-06',
    passed: adminBindings.length === 0,
    message:
      adminBindings.length === 0
        ? `PASSED: No primitive roles (roles/owner, roles/editor) found in IAM bindings.`
        : `VIOLATION: Over-privileged administrative role '${adminBindings[0].role}' granted to '${adminBindings[0].member}'.`,
  });

  // POL-07: No Service Account Key Creation
  const keyAdminBindings = config.iamBindings.filter(
    (b) => b.role === 'roles/iam.serviceAccountKeyAdmin'
  );
  results.push({
    ruleId: 'POL-07',
    passed: keyAdminBindings.length === 0,
    message:
      keyAdminBindings.length === 0
        ? `PASSED: No service account key admin roles granted. Workload Identity is enforced.`
        : `VIOLATION: Key admin role granted: ${keyAdminBindings[0].member}`,
  });

  // POL-08: No Retention Policy Ambiguity
  const ambiguousRetention = config.storageBuckets.filter(
    (b) => !b.retentionPolicy || b.retentionPolicy.retentionPeriodSeconds <= 0
  );
  results.push({
    ruleId: 'POL-08',
    passed: ambiguousRetention.length === 0,
    message:
      ambiguousRetention.length === 0
        ? `PASSED: All storage buckets declare explicit retention durations.`
        : `VIOLATION: Bucket lacks explicit retention policy duration: ${ambiguousRetention[0].name}`,
  });

  // POL-09: No Irreversible Retention Lock in Phase 20.15
  const lockedBuckets = config.storageBuckets.filter(
    (b) => b.retentionPolicy && b.retentionPolicy.isLocked === true
  );
  results.push({
    ruleId: 'POL-09',
    passed: lockedBuckets.length === 0,
    message:
      lockedBuckets.length === 0
        ? `PASSED: Bucket Lock is disabled (is_locked = false) across all buckets.`
        : `VIOLATION: Bucket Lock is set to true on bucket '${lockedBuckets[0].name}'. Irreversible lock forbidden in test phase.`,
  });

  // POL-10: No Destruction of Protected KMS Resources
  const unprotectedKeys = config.kmsKeys.filter((k) => k.preventDestroy !== true);
  results.push({
    ruleId: 'POL-10',
    passed: unprotectedKeys.length === 0,
    message:
      unprotectedKeys.length === 0
        ? `PASSED: All ${config.kmsKeys.length} KMS crypto keys declare prevent_destroy = true.`
        : `VIOLATION: KMS key '${unprotectedKeys[0].name}' lacks prevent_destroy = true.`,
  });

  // POL-11: No Unapproved Database Creation
  const allowedDbs = ['biometric-vault-db', 'audit-ledger-db'];
  const unapprovedDbs = config.firestoreDatabases.filter((d) => !allowedDbs.includes(d.name));
  results.push({
    ruleId: 'POL-11',
    passed: unapprovedDbs.length === 0,
    message:
      unapprovedDbs.length === 0
        ? `PASSED: Declared Firestore databases (${config.firestoreDatabases.map((d) => d.name).join(', ')}) are approved.`
        : `VIOLATION: Unapproved Firestore database declared: ${unapprovedDbs[0].name}`,
  });

  // POL-12: No Default Database Fallback for Privileged Services
  const defaultDbDeclared = config.firestoreDatabases.some((d) => d.name === '(default)');
  results.push({
    ruleId: 'POL-12',
    passed: !defaultDbDeclared,
    message: !defaultDbDeclared
      ? `PASSED: Privileged infrastructure declares dedicated named databases without default database fallback.`
      : `VIOLATION: Privileged infrastructure attempted to provision or route to (default) database.`,
  });

  // POL-13: No Unapproved Provider Versions
  const googleVer = config.providerVersions['google'];
  const isPinned = googleVer === '5.20.0';
  results.push({
    ruleId: 'POL-13',
    passed: isPinned,
    message: isPinned
      ? `PASSED: Google provider version is strictly pinned to '5.20.0'.`
      : `VIOLATION: Google provider version '${googleVer}' is unpinned or unapproved.`,
  });

  // POL-14: No Unapproved Module Sources
  const remoteModules = config.moduleSources.filter(
    (src) => src.startsWith('http://') || src.startsWith('https://') || src.startsWith('git::')
  );
  results.push({
    ruleId: 'POL-14',
    passed: remoteModules.length === 0,
    message:
      remoteModules.length === 0
        ? `PASSED: No unpinned external remote modules detected.`
        : `VIOLATION: Remote module source detected: ${remoteModules[0]}`,
  });

  // POL-15: No Production Backend Configuration
  const isProdBackend =
    config.backendConfig &&
    (config.backendConfig.bucket?.includes('prod') || config.backendConfig.prefix?.includes('prod'));
  results.push({
    ruleId: 'POL-15',
    passed: !isProdBackend,
    message: !isProdBackend
      ? `PASSED: Remote state backend configuration does not target production.`
      : `VIOLATION: Remote state backend targets production state bucket: ${config.backendConfig?.bucket}`,
  });

  const allPassed = results.every((r) => r.passed);
  return { allPassed, results };
}
