/**
 * KELASAGARA V20.14: CLOUD IAM POLICY VERIFIER & PERMISSION MATRIX ENGINE
 *
 * Implements deterministic validation of service account capabilities,
 * static Terraform policy linting, and sandbox availability checks.
 */

export type ServiceAccountIdentity =
  | 'sa-biometrics-enrollment'
  | 'sa-biometrics-verifier'
  | 'sa-biometrics-reviewer'
  | 'sa-biometrics-inventory'
  | 'sa-biometrics-audit-notary'
  | 'sa-ordinary-backend'
  | 'client-flutter-user';

export type IamAction =
  | 'datastore.entities.create'
  | 'datastore.entities.get'
  | 'datastore.entities.update'
  | 'datastore.entities.delete'
  | 'cloudkms.cryptoKeyVersions.useToEncrypt'
  | 'cloudkms.cryptoKeyVersions.useToDecrypt'
  | 'cloudkms.cryptoKeyVersions.useToSign'
  | 'cloudkms.cryptoKeyVersions.viewPublicKey'
  | 'storage.objects.create'
  | 'storage.objects.get'
  | 'storage.objects.delete'
  | 'iam.serviceAccounts.actAs'
  | 'iam.serviceAccountTokens.create'
  | 'iam.serviceAccountKeys.create';

export interface AuthorizationEvaluationResult {
  allowed: boolean;
  identity: ServiceAccountIdentity;
  action: IamAction;
  targetResource: string;
  reason: string;
}

/**
 * Declares the authoritative least-privilege permission matrix
 * implemented in infra/terraform/iam_bindings.tf
 */
export const IAM_LEAST_PRIVILEGE_POLICY: Record<ServiceAccountIdentity, Set<IamAction>> = {
  'sa-biometrics-enrollment': new Set([
    'datastore.entities.create',
    'datastore.entities.get',
    'cloudkms.cryptoKeyVersions.useToEncrypt',
  ]),
  'sa-biometrics-verifier': new Set([
    'datastore.entities.get',
    'cloudkms.cryptoKeyVersions.useToDecrypt',
    'cloudkms.cryptoKeyVersions.viewPublicKey',
  ]),
  'sa-biometrics-reviewer': new Set([
    'datastore.entities.get',
    'datastore.entities.update',
  ]),
  'sa-biometrics-inventory': new Set([
    'datastore.entities.get',
    'cloudkms.cryptoKeyVersions.viewPublicKey',
  ]),
  'sa-biometrics-audit-notary': new Set([
    'datastore.entities.create',
    'storage.objects.create',
    'cloudkms.cryptoKeyVersions.useToSign',
  ]),
  'sa-ordinary-backend': new Set([
    'datastore.entities.get',
  ]),
  'client-flutter-user': new Set([]), // Direct client access to vault is completely blocked by firestore.rules
};

/**
 * Evaluates whether a service identity is authorized to perform an action on a target resource.
 */
export function evaluateIamPermission(
  identity: ServiceAccountIdentity,
  action: IamAction,
  targetResource: string
): AuthorizationEvaluationResult {
  const allowedActions = IAM_LEAST_PRIVILEGE_POLICY[identity];
  if (!allowedActions) {
    return {
      allowed: false,
      identity,
      action,
      targetResource,
      reason: `DENIED: Unknown service account identity '${identity}'.`,
    };
  }

  // Explicit resource constraints
  if (action === 'cloudkms.cryptoKeyVersions.useToSign') {
    if (!targetResource.includes('audit-checkpoint-signing-key') && !targetResource.includes('manifest-attestation-key')) {
      return {
        allowed: false,
        identity,
        action,
        targetResource,
        reason: `DENIED: Target key '${targetResource}' does not support asymmetric signing.`,
      };
    }
  }

  if (action === 'storage.objects.delete') {
    return {
      allowed: false,
      identity,
      action,
      targetResource,
      reason: `DENIED: Storage object deletion is globally forbidden on immutable audit buckets.`,
    };
  }

  if (action === 'iam.serviceAccountKeys.create') {
    return {
      allowed: false,
      identity,
      action,
      targetResource,
      reason: `DENIED: Long-lived service account key creation is disabled by organization policy constraint iam.disableServiceAccountKeyCreation.`,
    };
  }

  if (allowedActions.has(action)) {
    return {
      allowed: true,
      identity,
      action,
      targetResource,
      reason: `ALLOWED: Action '${action}' is permitted for identity '${identity}' on '${targetResource}'.`,
    };
  }

  return {
    allowed: false,
    identity,
    action,
    targetResource,
    reason: `DENIED: Identity '${identity}' lacks required IAM permission '${action}'.`,
  };
}

/**
 * Production project identifiers denylist.
 */
export const PRODUCTION_PROJECT_DENYLIST = [
  'kelasagara-prod',
  'kelasagara-production',
  'kelasagaara-v17',
  'kelasagaara_v17',
  'kelasagara-live',
  'production',
  'prod',
];

export interface TerraformValidationResult {
  valid: boolean;
  errors: string[];
  warnings: string[];
}

/**
 * Statically validates Terraform project configuration parameters against security invariants.
 */
export function validateTerraformConfiguration(config: {
  projectId: string;
  environment: string;
  roleBindings: Array<{ role: string; principal: string }>;
  bucketConfig?: { retentionPolicyDays?: number; uniformAccess?: boolean };
}): TerraformValidationResult {
  const errors: string[] = [];
  const warnings: string[] = [];

  // Denylist check
  const normalizedProjectId = config.projectId.toLowerCase().trim();
  if (PRODUCTION_PROJECT_DENYLIST.includes(normalizedProjectId)) {
    errors.push(
      `CRITICAL_SECURITY_VIOLATION: Project ID '${config.projectId}' matches a production identifier in the denylist.`
    );
  }

  // Non-production environment check
  if (config.environment === 'production' || config.environment === 'prod') {
    errors.push(`CRITICAL_SECURITY_VIOLATION: Environment '${config.environment}' is prohibited. Only non-production environments may be provisioned.`);
  }

  // Broad/over-privileged roles check
  for (const binding of config.roleBindings) {
    if (binding.role === 'roles/owner' || binding.role === 'roles/editor') {
      errors.push(
        `CRITICAL_LEAST_PRIVILEGE_VIOLATION: Role '${binding.role}' granted to '${binding.principal}'. Primitive roles are strictly prohibited.`
      );
    }
    if (binding.role === 'roles/iam.serviceAccountKeyAdmin') {
      errors.push(
        `SECURITY_VIOLATION: Role '${binding.role}' granted to '${binding.principal}'. Long-lived key creation is prohibited.`
      );
    }
    if (binding.role === 'roles/storage.admin' || binding.role === 'roles/storage.objectAdmin') {
      errors.push(
        `AUDIT_VIOLATION: Over-privileged storage role '${binding.role}' granted to '${binding.principal}'. Audit buckets must be append-only.`
      );
    }
  }

  // Bucket configuration check
  if (config.bucketConfig) {
    if (config.bucketConfig.uniformAccess === false) {
      errors.push('AUDIT_VIOLATION: Uniform bucket-level access must be enabled.');
    }
  }

  return {
    valid: errors.length === 0,
    errors,
    warnings,
  };
}

/**
 * Checks whether an authorized live Google Cloud sandbox project is configured.
 */
export function checkSandboxCloudAvailability(): {
  available: boolean;
  status: 'SUCCESS_SANDBOX_CONFIGURED' | 'BLOCKED_SANDBOX_IAM_NOT_AVAILABLE';
  message: string;
} {
  const credentials = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  const explicitSandboxProjectId = process.env.GCP_SANDBOX_PROJECT_ID;

  if (!credentials || !explicitSandboxProjectId) {
    return {
      available: false,
      status: 'BLOCKED_SANDBOX_IAM_NOT_AVAILABLE',
      message:
        'BLOCKED_SANDBOX_IAM_NOT_AVAILABLE: No authorized non-production Google Cloud sandbox project or credentials configured. Per V20.14 Rule 10, live cloud validation is blocked to prevent accidental or unverified cloud alterations.',
    };
  }

  return {
    available: true,
    status: 'SUCCESS_SANDBOX_CONFIGURED',
    message: `Sandbox project '${explicitSandboxProjectId}' configured for live test execution.`,
  };
}
