/**
 * KELASAGARA V20.16: FIRESTORE DATABASE AUTHORIZATION & PRINCIPAL BOUNDARY
 *
 * Implements strict application-layer authorization across the three named databases:
 * 1. biometric-vault-db: Isolated biometric vectors and template snapshots.
 * 2. audit-ledger-db: Cryptographic audit trails and blinded review queues.
 * 3. (default): General application documents (jobs, applications, chat).
 *
 * Enforces dual verification:
 * - Deterministic database routing per service role.
 * - Calling principal identity assertion against approved service accounts.
 * - Explicit fail-closed rejection on implicit default database fallback.
 */

import {
  APPROVED_FIRESTORE_DATABASES,
  ApprovedFirestoreDatabaseId,
  DatabaseSecurityEvent,
  FirestoreDatabaseRoutingError,
  clearRecordedDatabaseSecurityEvents,
  getRecordedDatabaseSecurityEvents,
} from './firestore_database_router_v15';

export type ApplicationWorkflowRole =
  | 'BIOMETRIC_ENROLLMENT'
  | 'BIOMETRIC_VERIFIER'
  | 'VAULT_INVENTORY'
  | 'AUDIT_NOTARY'
  | 'RECOVERY'
  | 'MANUAL_REVIEW'
  | 'GENERAL_APP';

export interface WorkflowRoleAuthorizationRule {
  targetDatabase: ApprovedFirestoreDatabaseId;
  expectedServiceAccountPrefix: string;
  isReadOnly: boolean;
  requiresDualCustody?: boolean;
}

export const WORKFLOW_ROLE_RULES: Record<ApplicationWorkflowRole, WorkflowRoleAuthorizationRule> = {
  BIOMETRIC_ENROLLMENT: {
    targetDatabase: 'biometric-vault-db',
    expectedServiceAccountPrefix: 'sa-biometrics-enrollment',
    isReadOnly: false,
  },
  BIOMETRIC_VERIFIER: {
    targetDatabase: 'biometric-vault-db',
    expectedServiceAccountPrefix: 'sa-biometrics-verifier',
    isReadOnly: true,
  },
  VAULT_INVENTORY: {
    targetDatabase: 'biometric-vault-db',
    expectedServiceAccountPrefix: 'sa-biometrics-inventory',
    isReadOnly: true,
  },
  AUDIT_NOTARY: {
    targetDatabase: 'audit-ledger-db',
    expectedServiceAccountPrefix: 'sa-biometrics-audit-notary',
    isReadOnly: false,
  },
  RECOVERY: {
    targetDatabase: 'biometric-vault-db',
    expectedServiceAccountPrefix: 'sa-biometrics-reviewer',
    isReadOnly: false,
    requiresDualCustody: true,
  },
  MANUAL_REVIEW: {
    targetDatabase: 'audit-ledger-db',
    expectedServiceAccountPrefix: 'sa-biometrics-reviewer',
    isReadOnly: false,
  },
  GENERAL_APP: {
    targetDatabase: '(default)',
    expectedServiceAccountPrefix: 'app-engine-or-general',
    isReadOnly: false,
  },
};

export interface DatabaseSessionContext {
  role: ApplicationWorkflowRole;
  configuredDatabaseId?: string | null;
  callerPrincipalEmail: string;
  hasDualCustodyToken?: boolean;
  operation: 'READ' | 'WRITE' | 'DELETE' | 'TRANSACTION';
}

export interface DatabaseSessionValidationResult {
  authorized: boolean;
  targetDatabase: ApprovedFirestoreDatabaseId;
  callerPrincipal: string;
  isReadOnlyEnforced: boolean;
  message: string;
}

export class FirestoreDatabaseAuthorizationEngine {
  /**
   * Validates a proposed database session against role mappings, calling principal,
   * operation permissions, and dual custody requirements.
   */
  public validateDatabaseSession(context: DatabaseSessionContext): DatabaseSessionValidationResult {
    const rule = WORKFLOW_ROLE_RULES[context.role];
    if (!rule) {
      throw new FirestoreDatabaseRoutingError(`ERR_UNKNOWN_WORKFLOW_ROLE: Unsupported role '${context.role}'.`);
    }

    // 1. Missing or empty configured database ID: FAIL CLOSED
    if (!context.configuredDatabaseId || context.configuredDatabaseId.trim() === '') {
      throw new FirestoreDatabaseRoutingError(
        `ERR_MISSING_DATABASE_CONFIG: Role '${context.role}' did not configure an explicit database. Implicit fallback to '(default)' is prohibited.`
      );
    }

    const cleanDbId = context.configuredDatabaseId.trim();

    // 2. Reject unapproved database names
    if (!APPROVED_FIRESTORE_DATABASES.includes(cleanDbId as any)) {
      throw new FirestoreDatabaseRoutingError(
        `ERR_UNKNOWN_FIRESTORE_DATABASE: Target database ID '${cleanDbId}' is not approved.`
      );
    }

    // 3. Database Role Routing Enforcement
    if (cleanDbId !== rule.targetDatabase) {
      if (cleanDbId === '(default)' && context.role !== 'GENERAL_APP') {
        throw new FirestoreDatabaseRoutingError(
          `ERR_UNAUTHORIZED_DEFAULT_DATABASE_FALLBACK: Privileged role '${context.role}' cannot fall back to '(default)'. Must target '${rule.targetDatabase}'.`
        );
      }
      throw new FirestoreDatabaseRoutingError(
        `ERR_DATABASE_ROLE_MISMATCH: Role '${context.role}' must target '${rule.targetDatabase}', but '${cleanDbId}' was provided.`
      );
    }

    // 4. Principal Identity Verification
    const callerEmail = context.callerPrincipalEmail.toLowerCase().trim();
    if (context.role !== 'GENERAL_APP') {
      if (!callerEmail.includes(rule.expectedServiceAccountPrefix)) {
        throw new FirestoreDatabaseRoutingError(
          `ERR_UNAUTHORIZED_CALLER_PRINCIPAL: Caller '${context.callerPrincipalEmail}' is not authorized for role '${context.role}'. Expected service account containing '${rule.expectedServiceAccountPrefix}'.`
        );
      }
    }

    // 5. Read-Only Boundary Enforcement
    if (rule.isReadOnly && (context.operation === 'WRITE' || context.operation === 'DELETE')) {
      throw new FirestoreDatabaseRoutingError(
        `ERR_READONLY_DATABASE_VIOLATION: Role '${context.role}' is strictly read-only on database '${rule.targetDatabase}'. Operation '${context.operation}' denied.`
      );
    }

    // 6. Dual-Custody Requirement for Recovery
    if (rule.requiresDualCustody && !context.hasDualCustodyToken) {
      throw new FirestoreDatabaseRoutingError(
        `ERR_DUAL_CUSTODY_REQUIRED: Role '${context.role}' on database '${rule.targetDatabase}' requires dual-custody authorization token.`
      );
    }

    return {
      authorized: true,
      targetDatabase: rule.targetDatabase,
      callerPrincipal: context.callerPrincipalEmail,
      isReadOnlyEnforced: rule.isReadOnly,
      message: `PASSED: Session authorized for role '${context.role}' on database '${rule.targetDatabase}'.`,
    };
  }
}
