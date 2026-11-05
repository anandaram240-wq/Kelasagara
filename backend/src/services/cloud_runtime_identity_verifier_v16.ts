/**
 * KELASAGARA V20.16: CLOUD RUNTIME IDENTITY & ADC VERIFIER
 *
 * Implements environment-sensitive credential and runtime identity verification
 * adhering to NIST SP 800-207 Zero Trust and Google Cloud Workload Identity principles.
 *
 * Differentiates credential sources:
 * 1. DOWNLOADED_SA_KEY_JSON: Downloaded service-account private-key JSON (STRICTLY PROHIBITED in prod/CI).
 * 2. LOCAL_USER_ADC: Local developer user credentials (PERMITTED in local dev with sandbox authorization).
 * 3. ATTACHED_WORKLOAD_IDENTITY: Attached user-managed service account through metadata server (MANDATED in production).
 * 4. WORKLOAD_IDENTITY_FEDERATION: Approved Workload Identity Federation (MANDATED in CI / multi-cloud).
 * 5. AUTHORIZED_IMPERSONATION: Explicitly authorized short-lived non-production impersonation.
 */

export type CredentialSourceType =
  | 'DOWNLOADED_SA_KEY_JSON'
  | 'LOCAL_USER_ADC'
  | 'ATTACHED_WORKLOAD_IDENTITY'
  | 'WORKLOAD_IDENTITY_FEDERATION'
  | 'AUTHORIZED_IMPERSONATION';

export type RuntimeEnvironment =
  | 'PRODUCTION_HOSTED'
  | 'STAGING_HOSTED'
  | 'CI_PIPELINE'
  | 'LOCAL_DEVELOPMENT';

export interface CredentialContext {
  sourceType: CredentialSourceType;
  environment: RuntimeEnvironment;
  targetProjectId: string;
  principalEmail?: string;
  expectedServiceAccountEmail?: string;
  isImpersonated?: boolean;
  impersonationOriginPrincipal?: string;
  hasExplicitSandboxAuthorization?: boolean;
  metadataServerReachable?: boolean;
  wifAudience?: string;
}

export interface CredentialVerificationResult {
  allowed: boolean;
  errorCode?: string;
  message: string;
  verifiedPrincipal?: string;
  runtimeIdentityType: CredentialSourceType;
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

export const APPROVED_SANDBOX_IDENTITIES = [
  'sa-biometrics-enrollment',
  'sa-biometrics-verifier',
  'sa-biometrics-reviewer',
  'sa-biometrics-inventory',
  'sa-biometrics-audit-notary',
  'sa-terraform-sandbox-deployer',
];

export class CloudRuntimeIdentityVerifier {
  /**
   * Evaluates credential context against environment security policies.
   */
  public verifyCredentialSource(context: CredentialContext): CredentialVerificationResult {
    const normProject = context.targetProjectId.toLowerCase().trim();
    const isProdProject =
      PRODUCTION_PROJECT_DENYLIST.includes(normProject) ||
      normProject.endsWith('-prod') ||
      normProject.endsWith('-production');

    // ─── 1. HOSTED PRODUCTION WORKLOADS ─────────────────────────────────────────
    if (context.environment === 'PRODUCTION_HOSTED') {
      // Rule 1A: Reject downloaded static service account private key JSON
      if (context.sourceType === 'DOWNLOADED_SA_KEY_JSON') {
        return {
          allowed: false,
          errorCode: 'ERR_STATIC_PRIVATE_KEY_PROHIBITED',
          message:
            'CRITICAL SECURITY VIOLATION: Downloaded service-account private-key JSON is strictly prohibited in hosted production. Must use Attached Workload Identity or Workload Identity Federation.',
          runtimeIdentityType: context.sourceType,
        };
      }

      // Rule 1B: Reject developer user credentials (User ADC)
      if (context.sourceType === 'LOCAL_USER_ADC') {
        return {
          allowed: false,
          errorCode: 'ERR_USER_CREDENTIALS_IN_PRODUCTION',
          message:
            'CRITICAL SECURITY VIOLATION: Developer user ADC credentials cannot be used in hosted production environments.',
          runtimeIdentityType: context.sourceType,
        };
      }

      // Rule 1C: Require Attached Workload Identity or Workload Identity Federation
      if (
        context.sourceType !== 'ATTACHED_WORKLOAD_IDENTITY' &&
        context.sourceType !== 'WORKLOAD_IDENTITY_FEDERATION'
      ) {
        return {
          allowed: false,
          errorCode: 'ERR_UNAPPROVED_CREDENTIAL_TYPE',
          message: `Hosted production requires ATTACHED_WORKLOAD_IDENTITY or WORKLOAD_IDENTITY_FEDERATION. Received: ${context.sourceType}`,
          runtimeIdentityType: context.sourceType,
        };
      }

      // Rule 1D: Validate runtime identity against expected dedicated service account
      if (context.expectedServiceAccountEmail) {
        if (!context.principalEmail || context.principalEmail !== context.expectedServiceAccountEmail) {
          return {
            allowed: false,
            errorCode: 'ERR_RUNTIME_IDENTITY_MISMATCH',
            message: `Runtime service account '${context.principalEmail}' does not match expected identity '${context.expectedServiceAccountEmail}'. Execution refused.`,
            runtimeIdentityType: context.sourceType,
          };
        }
      }

      // Rule 1E: Reject unapproved service-account impersonation in production
      if (context.isImpersonated) {
        return {
          allowed: false,
          errorCode: 'ERR_UNAPPROVED_IMPERSONATION',
          message:
            'CRITICAL SECURITY VIOLATION: Service-account impersonation is forbidden in production runtime. Services must execute under their direct attached identity.',
          runtimeIdentityType: context.sourceType,
        };
      }

      return {
        allowed: true,
        message: 'PASSED: Production runtime identity verified via approved Attached Workload Identity / WIF.',
        verifiedPrincipal: context.principalEmail,
        runtimeIdentityType: context.sourceType,
      };
    }

    // ─── 2. CI PIPELINE WORKLOADS ───────────────────────────────────────────────
    if (context.environment === 'CI_PIPELINE') {
      // Rule 2A: Reject long-lived downloaded private keys
      if (context.sourceType === 'DOWNLOADED_SA_KEY_JSON') {
        return {
          allowed: false,
          errorCode: 'ERR_STATIC_PRIVATE_KEY_IN_CI',
          message:
            'CRITICAL SECURITY VIOLATION: Static service-account JSON keys are prohibited in CI pipelines. CI must authenticate via OIDC Workload Identity Federation.',
          runtimeIdentityType: context.sourceType,
        };
      }

      // Rule 2B: Reject developer user ADC in CI
      if (context.sourceType === 'LOCAL_USER_ADC') {
        return {
          allowed: false,
          errorCode: 'ERR_USER_ADC_IN_CI',
          message: 'Local developer user ADC is invalid in automated CI pipelines.',
          runtimeIdentityType: context.sourceType,
        };
      }

      // Rule 2C: Reject any access to production projects during CI test jobs
      if (isProdProject) {
        return {
          allowed: false,
          errorCode: 'ERR_PRODUCTION_ACCESS_FROM_CI',
          message: `CI pipelines running test or verification jobs are strictly blocked from accessing production project '${context.targetProjectId}'.`,
          runtimeIdentityType: context.sourceType,
        };
      }

      // Rule 2D: Workload Identity Federation is the mandated CI standard
      if (context.sourceType === 'WORKLOAD_IDENTITY_FEDERATION') {
        return {
          allowed: true,
          message: 'PASSED: CI pipeline identity verified via approved Workload Identity Federation.',
          verifiedPrincipal: context.principalEmail,
          runtimeIdentityType: context.sourceType,
        };
      }

      // Permitted impersonation for deployment runners if authorized
      if (context.sourceType === 'AUTHORIZED_IMPERSONATION' && context.hasExplicitSandboxAuthorization) {
        return {
          allowed: true,
          message: 'PASSED: Short-lived authorized impersonation approved for CI deployment runner.',
          verifiedPrincipal: context.principalEmail,
          runtimeIdentityType: context.sourceType,
        };
      }

      return {
        allowed: false,
        errorCode: 'ERR_UNAPPROVED_CI_CREDENTIAL',
        message: `CI execution requires approved Workload Identity Federation. Received: ${context.sourceType}`,
        runtimeIdentityType: context.sourceType,
      };
    }

    // ─── 3. LOCAL DEVELOPMENT WORKLOADS ────────────────────────────────────────
    if (context.environment === 'LOCAL_DEVELOPMENT') {
      // Rule 3A: Block silent resolution of production credentials
      if (isProdProject) {
        return {
          allowed: false,
          errorCode: 'ERR_PRODUCTION_CREDENTIAL_IN_LOCAL_DEV',
          message: `CRITICAL SAFETY VIOLATION: Local developer environment cannot target production project '${context.targetProjectId}'.`,
          runtimeIdentityType: context.sourceType,
        };
      }

      // Rule 3B: Permit approved developer user ADC for sandbox work with explicit authorization
      if (context.sourceType === 'LOCAL_USER_ADC') {
        if (!context.hasExplicitSandboxAuthorization) {
          return {
            allowed: false,
            errorCode: 'ERR_UNAUTHORIZED_SANDBOX_IDENTITY',
            message:
              'Local developer user ADC requires explicit sandbox authorization (e.g. configured sandbox project allowlist). Silent resolution denied.',
            runtimeIdentityType: context.sourceType,
          };
        }

        return {
          allowed: true,
          message: 'PASSED: Local developer user ADC approved for non-production sandbox operations.',
          verifiedPrincipal: context.principalEmail,
          runtimeIdentityType: context.sourceType,
        };
      }

      // Rule 3C: Reject unapproved sandbox identities
      if (context.principalEmail) {
        const isApproved = APPROVED_SANDBOX_IDENTITIES.some((id) =>
          context.principalEmail?.includes(id)
        );
        if (!isApproved) {
          return {
            allowed: false,
            errorCode: 'ERR_UNAPPROVED_SANDBOX_IDENTITY',
            message: `Principal '${context.principalEmail}' is not in approved sandbox identities list.`,
            runtimeIdentityType: context.sourceType,
          };
        }
      }

      return {
        allowed: true,
        message: 'PASSED: Local development credential context approved.',
        verifiedPrincipal: context.principalEmail,
        runtimeIdentityType: context.sourceType,
      };
    }

    return {
      allowed: false,
      errorCode: 'ERR_UNKNOWN_ENVIRONMENT',
      message: `Unsupported runtime environment: ${context.environment}`,
      runtimeIdentityType: context.sourceType,
    };
  }
}
