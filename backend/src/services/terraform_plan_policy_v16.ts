/**
 * KELASAGARA V20.16: TERRAFORM PLAN POLICY-AS-CODE ENGINE (LAYER 2)
 *
 * Evaluates full Terraform Plan JSON representations (from `terraform show -json`)
 * to provide deterministic pre-deployment validation before any cloud mutation.
 *
 * Core Capabilities:
 * 1. Deep Resource Inspection: Checks every planned resource's `project` attribute,
 *    detecting resource-level project overrides (e.g., resource targeting 'kelasagara-prod').
 * 2. Provider Alias & Configuration Consistency: Verifies all provider configurations
 *    and aliases target approved non-production projects.
 * 3. Destruction & Replacement Prevention: Flags destructive actions (["delete"], ["delete", "create"])
 *    on protected resources (Cloud KMS keys, Storage buckets, Firestore databases).
 * 4. Granular IAM & KMS Role Validation: Blocks wildcard principals, owner/editor roles,
 *    combined signerVerifier, and redundant publicKeyViewer grants.
 * 5. Storage Retention Lock Gate: Strictly blocks `is_locked = true` on bucket retention policies.
 * 6. Targeted Operation Enforcement: Flags `-target` executions to prevent security gate bypass.
 */

export interface TerraformPlanResourceChange {
  address: string;
  module_address?: string;
  mode: string;
  type: string;
  name: string;
  provider_name: string;
  change: {
    actions: ('no-op' | 'create' | 'read' | 'update' | 'delete')[];
    before: Record<string, any> | null;
    after: Record<string, any> | null;
    after_unknown?: Record<string, any>;
  };
}

export interface TerraformPlan {
  format_version?: string;
  terraform_version?: string;
  variables?: Record<string, { value: any }>;
  resource_changes?: TerraformPlanResourceChange[];
  configuration?: {
    provider_config?: Record<
      string,
      {
        name: string;
        expressions?: Record<string, { constant_value?: any }>;
      }
    >;
    root_module?: {
      resources?: Array<{
        address: string;
        type: string;
        name: string;
        provider_config_key: string;
        expressions?: Record<string, any>;
      }>;
    };
  };
  targeted?: boolean;
  target_resources?: string[];
}

export interface PlanPolicyViolation {
  ruleId: string;
  severity: 'CRITICAL' | 'HIGH' | 'MEDIUM';
  resourceAddress?: string;
  message: string;
}

export interface PlanPolicyEvaluationResult {
  allPassed: boolean;
  violations: PlanPolicyViolation[];
  scannedResourcesCount: number;
  evaluatedRulesCount: number;
}

const PRODUCTION_IDENTIFIER_DENYLIST = [
  'kelasagara-prod',
  'kelasagara-production',
  'kelasagaara_v17',
  'kelasagaara-v17',
  'kelasagara-live',
  'production',
  'prod',
];

const PROTECTED_RESOURCE_TYPES = [
  'google_kms_crypto_key',
  'google_kms_key_ring',
  'google_storage_bucket',
  'google_firestore_database',
];

export class TerraformPlanPolicyEngine {
  /**
   * Evaluates a complete Terraform plan JSON object against all Layer 2 policy invariants.
   */
  public evaluatePlan(plan: TerraformPlan): PlanPolicyEvaluationResult {
    const violations: PlanPolicyViolation[] = [];
    const resourceChanges = plan.resource_changes || [];

    // ─── RULE 1: Targeted Execution Policy Gate ────────────────────────────────
    if (plan.targeted || (plan.target_resources && plan.target_resources.length > 0)) {
      violations.push({
        ruleId: 'PLAN-POL-TARGET-GATE',
        severity: 'HIGH',
        message:
          'TARGETED_OPERATION_FLAGGED: Plan was generated using -target. Targeted plans cannot bypass full-infrastructure policy verification and require explicit security authorization.',
      });
    }

    // ─── RULE 2: Provider Configuration & Alias Project Consistency ────────────
    if (plan.configuration?.provider_config) {
      for (const [providerKey, prov] of Object.entries(plan.configuration.provider_config)) {
        const configuredProject = prov.expressions?.project?.constant_value;
        if (typeof configuredProject === 'string') {
          const normProj = configuredProject.toLowerCase().trim();
          if (
            PRODUCTION_IDENTIFIER_DENYLIST.includes(normProj) ||
            normProj.endsWith('-prod') ||
            normProj.endsWith('-production')
          ) {
            violations.push({
              ruleId: 'PLAN-POL-PROD-PROVIDER',
              severity: 'CRITICAL',
              message: `Provider configuration '${providerKey}' references production project '${configuredProject}'.`,
            });
          }
        }
      }
    }

    // ─── RULE 3: Plan Variables Evaluation ──────────────────────────────────────
    if (plan.variables) {
      for (const [varName, varVal] of Object.entries(plan.variables)) {
        if (typeof varVal?.value === 'string') {
          const normVal = varVal.value.toLowerCase().trim();
          if (
            PRODUCTION_IDENTIFIER_DENYLIST.includes(normVal) ||
            normVal.endsWith('-prod') ||
            normVal.endsWith('-production')
          ) {
            violations.push({
              ruleId: 'PLAN-POL-PROD-VARIABLE',
              severity: 'CRITICAL',
              message: `Plan variable '${varName}' contains production identifier '${varVal.value}'.`,
            });
          }
        }
      }
    }

    // ─── RULE 4: Resource Changes Deep Inspection ──────────────────────────────
    for (const res of resourceChanges) {
      const actions = res.change.actions;
      const after = res.change.after || {};

      // 4A: Resource-Level Project Override Inspection
      if (after.project && typeof after.project === 'string') {
        const resProject = after.project.toLowerCase().trim();
        if (
          PRODUCTION_IDENTIFIER_DENYLIST.includes(resProject) ||
          resProject.endsWith('-prod') ||
          resProject.endsWith('-production')
        ) {
          violations.push({
            ruleId: 'PLAN-POL-RESOURCE-PROD-OVERRIDE',
            severity: 'CRITICAL',
            resourceAddress: res.address,
            message: `Resource '${res.address}' overrides project to production target '${after.project}'. Execution denied.`,
          });
        }
      }

      // 4B: Destruction or Replacement on Protected Resources
      const isDelete = actions.includes('delete');
      const isReplace = actions.includes('delete') && actions.includes('create');
      if (PROTECTED_RESOURCE_TYPES.includes(res.type) && (isDelete || isReplace)) {
        violations.push({
          ruleId: 'PLAN-POL-PROTECTED-RESOURCE-DESTROY',
          severity: 'CRITICAL',
          resourceAddress: res.address,
          message: `DESTRUCTIVE_ACTION_BLOCKED: Planned actions [${actions.join(', ')}] on protected resource '${res.address}' (${res.type}) are strictly prohibited.`,
        });
      }

      // 4C: Cloud Storage Specific Policies
      if (res.type === 'google_storage_bucket') {
        // Reject Bucket Lock activation in non-production
        const retentionPolicies = after.retention_policy;
        if (Array.isArray(retentionPolicies)) {
          for (const rp of retentionPolicies) {
            if (rp.is_locked === true) {
              violations.push({
                ruleId: 'PLAN-POL-BUCKET-LOCK-PROHIBITED',
                severity: 'CRITICAL',
                resourceAddress: res.address,
                message: `Bucket '${res.address}' attempts to enable irreversible Bucket Lock (is_locked = true). Bucket locks are strictly prohibited in sandbox/test environments.`,
              });
            }
          }
        } else if (retentionPolicies && retentionPolicies.is_locked === true) {
          violations.push({
            ruleId: 'PLAN-POL-BUCKET-LOCK-PROHIBITED',
            severity: 'CRITICAL',
            resourceAddress: res.address,
            message: `Bucket '${res.address}' attempts to enable irreversible Bucket Lock (is_locked = true). Bucket locks are strictly prohibited in sandbox/test environments.`,
          });
        }

        // Public access block
        if (after.public_access_prevention && after.public_access_prevention !== 'enforced') {
          violations.push({
            ruleId: 'PLAN-POL-BUCKET-PUBLIC-ACCESS',
            severity: 'CRITICAL',
            resourceAddress: res.address,
            message: `Bucket '${res.address}' does not enforce public access prevention. Received: '${after.public_access_prevention}'`,
          });
        }

        // Uniform bucket access
        if (after.uniform_bucket_level_access === false) {
          violations.push({
            ruleId: 'PLAN-POL-BUCKET-UNIFORM-ACCESS',
            severity: 'HIGH',
            resourceAddress: res.address,
            message: `Bucket '${res.address}' disables uniform_bucket_level_access. Fine-grained ACLs are prohibited.`,
          });
        }
      }

      // 4D: Cloud KMS Specific Policies
      if (res.type === 'google_kms_crypto_key') {
        const versionTemplate = Array.isArray(after.version_template)
          ? after.version_template[0]
          : after.version_template;
        if (versionTemplate && versionTemplate.protection_level) {
          if (versionTemplate.protection_level !== 'HSM') {
            violations.push({
              ruleId: 'PLAN-POL-KMS-HSM-MANDATE',
              severity: 'HIGH',
              resourceAddress: res.address,
              message: `CryptoKey '${res.address}' specifies protection_level = '${versionTemplate.protection_level}'. Must be 'HSM'.`,
            });
          }
        }
      }

      // 4E: IAM Bindings Deep Inspection
      if (
        res.type === 'google_project_iam_member' ||
        res.type === 'google_kms_crypto_key_iam_member' ||
        res.type === 'google_storage_bucket_iam_member'
      ) {
        const member = (after.member || '').toLowerCase();
        const role = after.role || '';

        // Wildcard member check
        if (member === 'allusers' || member === 'allauthenticatedusers' || member.includes('*')) {
          violations.push({
            ruleId: 'PLAN-POL-IAM-WILDCARD',
            severity: 'CRITICAL',
            resourceAddress: res.address,
            message: `IAM binding '${res.address}' grants role '${role}' to public/wildcard principal '${after.member}'.`,
          });
        }

        // Project-wide admin roles check
        if (role === 'roles/owner' || role === 'roles/editor') {
          violations.push({
            ruleId: 'PLAN-POL-IAM-ADMIN-ROLE',
            severity: 'CRITICAL',
            resourceAddress: res.address,
            message: `IAM binding '${res.address}' grants project-wide administrative role '${role}' to '${after.member}'.`,
          });
        }

        // Combined signerVerifier check
        if (role === 'roles/cloudkms.signerVerifier') {
          violations.push({
            ruleId: 'PLAN-POL-KMS-SIGNER-VERIFIER',
            severity: 'CRITICAL',
            resourceAddress: res.address,
            message: `IAM binding '${res.address}' grants broad 'roles/cloudkms.signerVerifier'. Must be split into roles/cloudkms.signer and roles/cloudkms.verifier.`,
          });
        }

        // Redundant publicKeyViewer check
        if (res.type === 'google_kms_crypto_key_iam_member' && role === 'roles/cloudkms.publicKeyViewer') {
          // Check if there is another binding granting roles/cloudkms.verifier to the same member on the same crypto_key
          const cryptoKeyId = after.crypto_key_id;
          const hasVerifierRole = resourceChanges.some(
            (other) =>
              other.address !== res.address &&
              other.type === 'google_kms_crypto_key_iam_member' &&
              other.change.after?.crypto_key_id === cryptoKeyId &&
              other.change.after?.member === after.member &&
              other.change.after?.role === 'roles/cloudkms.verifier'
          );
          if (hasVerifierRole) {
            violations.push({
              ruleId: 'PLAN-POL-REDUNDANT-KMS-ROLE',
              severity: 'MEDIUM',
              resourceAddress: res.address,
              message: `Redundant IAM role 'roles/cloudkms.publicKeyViewer' assigned to '${after.member}' on key '${cryptoKeyId}', which already has 'roles/cloudkms.verifier'.`,
            });
          }
        }
      }
    }

    return {
      allPassed: violations.length === 0,
      violations,
      scannedResourcesCount: resourceChanges.length,
      evaluatedRulesCount: 10,
    };
  }
}
