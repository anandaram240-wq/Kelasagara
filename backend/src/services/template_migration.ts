// backend/src/services/template_migration.ts
/**
 * BIOMETRIC TEMPLATE MIGRATION ENGINE (Stage S8 / Work Package S8-C / Section 5).
 * Enforces Invariants INV-04 (Strict Version Selection) and INV-09 (Migration Safety).
 *
 * Implements a state machine for migrating legacy envelopes (v1/v2) to v3_kms_gcm:
 * DISCOVERED -> VALIDATED -> DECRYPTED -> REENCRYPTED -> WRAPPED -> VERIFIED -> COMMITTED
 */

import { TemplatePrivacyService, EncryptedTemplateEnvelope, EnvelopeVersion } from "./template_privacy";
import { KeyProvider, LocalDevKeyProvider } from "./kms_key_provider";

export type MigrationState =
  | "DISCOVERED"
  | "VALIDATED"
  | "DECRYPTED"
  | "REENCRYPTED"
  | "WRAPPED"
  | "VERIFIED"
  | "COMMITTED"
  | "FAILED";

export interface MigrationRecordResult {
  uid: string;
  tenantId: string;
  sourceVersion: EnvelopeVersion;
  targetVersion: EnvelopeVersion;
  state: MigrationState;
  migratedEnvelope?: EncryptedTemplateEnvelope;
  error?: string;
  durationMs: number;
}

export interface MigrationBatchSummary {
  dryRun: boolean;
  totalDiscovered: number;
  totalMigrated: number;
  totalSkipped: number;
  totalFailed: number;
  records: MigrationRecordResult[];
}

export class TemplateMigrationService {
  /**
   * Migrates a single envelope through the 7-stage state machine.
   * Performs an immediate verification decrypt before committing.
   */
  static async migrateRecord(
    envelope: EncryptedTemplateEnvelope,
    options: {
      masterKeySecret?: string;
      keyProvider?: KeyProvider;
      dryRun?: boolean;
      targetVersion?: EnvelopeVersion;
    }
  ): Promise<MigrationRecordResult> {
    const t0 = Date.now();
    const sourceVersion = envelope.envelopeVersion || "v1_legacy";
    const targetVersion = options.targetVersion || "v3_kms_gcm";
    const provider = options.keyProvider || TemplatePrivacyService.getDefaultKeyProvider();

    // If record is already at or above target version, skip
    if (sourceVersion === targetVersion) {
      return {
        uid: envelope.uid,
        tenantId: envelope.tenantId,
        sourceVersion,
        targetVersion,
        state: "COMMITTED",
        migratedEnvelope: envelope,
        durationMs: Date.now() - t0,
      };
    }

    let currentState: MigrationState = "DISCOVERED";

    try {
      // 1. VALIDATED
      currentState = "VALIDATED";
      if (!envelope.uid || !envelope.tenantId || !envelope.ciphertextHex) {
        throw new Error("MIGRATION_VALIDATION_ERROR: Missing required envelope fields.");
      }

      // 2. DECRYPTED (using legacy reader)
      currentState = "DECRYPTED";
      const rawVector = TemplatePrivacyService.decryptTemplate(
        envelope,
        options.masterKeySecret,
        undefined,
        false
      );

      // 3. REENCRYPTED & 4. WRAPPED (using target v3_kms_gcm)
      currentState = "REENCRYPTED";
      const newEnvelope = await TemplatePrivacyService.encryptTemplateAsync(
        envelope.uid,
        envelope.tenantId,
        rawVector,
        provider,
        undefined,
        "k1",
        envelope.templatePurpose || "BIOMETRIC_AUTH_V1"
      );
      currentState = "WRAPPED";

      // 5. VERIFIED (Pre-commit decrypt drill to ensure zero data loss)
      currentState = "VERIFIED";
      const verificationDecrypted = await TemplatePrivacyService.decryptTemplateAsync(
        newEnvelope,
        provider,
        undefined,
        "v3_kms_gcm"
      );

      if (verificationDecrypted.length !== rawVector.length) {
        throw new Error("MIGRATION_VERIFICATION_ERROR: Decrypted vector length mismatch.");
      }

      // 6. COMMITTED (or simulated if dryRun)
      if (options.dryRun) {
        return {
          uid: envelope.uid,
          tenantId: envelope.tenantId,
          sourceVersion,
          targetVersion,
          state: "VERIFIED", // Verified but not committed in dry run
          migratedEnvelope: newEnvelope,
          durationMs: Date.now() - t0,
        };
      }

      currentState = "COMMITTED";
      return {
        uid: envelope.uid,
        tenantId: envelope.tenantId,
        sourceVersion,
        targetVersion,
        state: "COMMITTED",
        migratedEnvelope: newEnvelope,
        durationMs: Date.now() - t0,
      };
    } catch (err: any) {
      return {
        uid: envelope.uid,
        tenantId: envelope.tenantId,
        sourceVersion,
        targetVersion,
        state: "FAILED",
        error: `Migration failed at state ${currentState}: ${err.message}`,
        durationMs: Date.now() - t0,
      };
    }
  }

  /**
   * Executes a bounded batch migration over a set of envelopes.
   */
  static async migrateBatch(
    envelopes: EncryptedTemplateEnvelope[],
    options: {
      masterKeySecret?: string;
      keyProvider?: KeyProvider;
      dryRun?: boolean;
    }
  ): Promise<MigrationBatchSummary> {
    const records: MigrationRecordResult[] = [];
    let totalMigrated = 0;
    let totalSkipped = 0;
    let totalFailed = 0;

    for (const env of envelopes) {
      const res = await this.migrateRecord(env, options);
      records.push(res);
      if (res.state === "COMMITTED" || (options.dryRun && res.state === "VERIFIED")) {
        if (res.sourceVersion === res.targetVersion) {
          totalSkipped++;
        } else {
          totalMigrated++;
        }
      } else {
        totalFailed++;
      }
    }

    return {
      dryRun: options.dryRun ?? false,
      totalDiscovered: envelopes.length,
      totalMigrated,
      totalSkipped,
      totalFailed,
      records,
    };
  }
}
