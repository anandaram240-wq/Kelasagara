/**
 * KELASAGARA V20.15: FIRESTORE NAMED DATABASE ROUTER & ISOLATION ENGINE
 *
 * Enforces explicit database selection across subsystems:
 * - biometric-vault-db: Isolated database for biometric vault records
 * - audit-ledger-db: Isolated database for append-only audit events
 * - (default): General application database (jobs, applications, chat)
 *
 * Prevents accidental or unauthorized fallback to (default) and enforces
 * strict database identity mapping for least-privilege Cloud IAM boundaries.
 */

export type SubsystemServiceRole =
  | 'BIOMETRIC_ENROLLMENT'
  | 'BIOMETRIC_VERIFIER'
  | 'AUDIT_NOTARY'
  | 'VAULT_INVENTORY'
  | 'GENERAL_APP';

export const APPROVED_FIRESTORE_DATABASES = [
  'biometric-vault-db',
  'audit-ledger-db',
  '(default)',
] as const;

export type ApprovedFirestoreDatabaseId = (typeof APPROVED_FIRESTORE_DATABASES)[number];

export const SERVICE_ROLE_DATABASE_MAPPING: Record<SubsystemServiceRole, ApprovedFirestoreDatabaseId> = {
  BIOMETRIC_ENROLLMENT: 'biometric-vault-db',
  BIOMETRIC_VERIFIER: 'biometric-vault-db',
  AUDIT_NOTARY: 'audit-ledger-db',
  VAULT_INVENTORY: 'biometric-vault-db',
  GENERAL_APP: '(default)',
};

export interface DatabaseSecurityEvent {
  timestampIso: string;
  eventType: 'SECURITY_DATABASE_MISMATCH' | 'SECURITY_UNAUTHORIZED_FALLBACK' | 'SECURITY_UNKNOWN_DATABASE';
  serviceRole: SubsystemServiceRole;
  attemptedDatabaseId: string | null | undefined;
  expectedDatabaseId: string;
  actionTaken: 'HALTED_FAIL_CLOSED';
}

const capturedSecurityEvents: DatabaseSecurityEvent[] = [];

export function getRecordedDatabaseSecurityEvents(): readonly DatabaseSecurityEvent[] {
  return [...capturedSecurityEvents];
}

export function clearRecordedDatabaseSecurityEvents(): void {
  capturedSecurityEvents.length = 0;
}

export class FirestoreDatabaseRoutingError extends Error {
  constructor(message: string) {
    super(`FIRESTORE_DATABASE_ROUTING_ERROR: ${message}`);
    this.name = 'FirestoreDatabaseRoutingError';
  }
}

/**
 * Resolves and validates the target Firestore database ID for a given service role.
 * Strictly prevents implicit fallback to (default) for privileged biometric roles.
 */
export function resolveTargetFirestoreDatabase(
  serviceRole: SubsystemServiceRole,
  configuredDatabaseId?: string | null
): { databaseId: ApprovedFirestoreDatabaseId; authorized: boolean } {
  const expectedDb = SERVICE_ROLE_DATABASE_MAPPING[serviceRole];

  // 1. Missing configuration fails closed
  if (!configuredDatabaseId || configuredDatabaseId.trim() === '') {
    const event: DatabaseSecurityEvent = {
      timestampIso: new Date().toISOString(),
      eventType: 'SECURITY_UNAUTHORIZED_FALLBACK',
      serviceRole,
      attemptedDatabaseId: configuredDatabaseId,
      expectedDatabaseId: expectedDb,
      actionTaken: 'HALTED_FAIL_CLOSED',
    };
    capturedSecurityEvents.push(event);

    throw new FirestoreDatabaseRoutingError(
      `ERR_MISSING_DATABASE_CONFIG: Service role '${serviceRole}' did not provide explicit database configuration. Implicit fallback to '(default)' is strictly forbidden.`
    );
  }

  const cleanDbId = configuredDatabaseId.trim();

  // 2. Reject unknown database identifiers
  if (!APPROVED_FIRESTORE_DATABASES.includes(cleanDbId as any)) {
    const event: DatabaseSecurityEvent = {
      timestampIso: new Date().toISOString(),
      eventType: 'SECURITY_UNKNOWN_DATABASE',
      serviceRole,
      attemptedDatabaseId: cleanDbId,
      expectedDatabaseId: expectedDb,
      actionTaken: 'HALTED_FAIL_CLOSED',
    };
    capturedSecurityEvents.push(event);

    throw new FirestoreDatabaseRoutingError(
      `ERR_UNKNOWN_FIRESTORE_DATABASE: Target database ID '${cleanDbId}' is not an approved Firestore database.`
    );
  }

  // 3. Prevent unauthorized database selection / cross-database pollution
  if (cleanDbId !== expectedDb) {
    const event: DatabaseSecurityEvent = {
      timestampIso: new Date().toISOString(),
      eventType: 'SECURITY_DATABASE_MISMATCH',
      serviceRole,
      attemptedDatabaseId: cleanDbId,
      expectedDatabaseId: expectedDb,
      actionTaken: 'HALTED_FAIL_CLOSED',
    };
    capturedSecurityEvents.push(event);

    if (cleanDbId === '(default)' && serviceRole !== 'GENERAL_APP') {
      throw new FirestoreDatabaseRoutingError(
        `ERR_UNAUTHORIZED_DEFAULT_DATABASE_FALLBACK: Privileged service role '${serviceRole}' attempted to target '(default)'. Biometric records must reside exclusively in '${expectedDb}'.`
      );
    }

    throw new FirestoreDatabaseRoutingError(
      `ERR_DATABASE_ROLE_MISMATCH: Service role '${serviceRole}' is mapped to '${expectedDb}', but target was configured as '${cleanDbId}'.`
    );
  }

  return { databaseId: cleanDbId as ApprovedFirestoreDatabaseId, authorized: true };
}

/**
 * Validates whether cross-database operations are attempted between isolated trust domains.
 */
export function validateCrossDatabaseBoundary(
  sourceDatabase: string,
  targetDatabase: string
): { boundaryPreserved: boolean } {
  if (sourceDatabase !== targetDatabase) {
    throw new FirestoreDatabaseRoutingError(
      `ERR_CROSS_DATABASE_VIOLATION: Cross-database transaction attempted between '${sourceDatabase}' and '${targetDatabase}'. Isolated databases cannot participate in shared transactions.`
    );
  }
  return { boundaryPreserved: true };
}
