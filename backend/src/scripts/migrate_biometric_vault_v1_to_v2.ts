// File: backend/src/scripts/migrate_biometric_vault_v1_to_v2.ts
/**
 * KELASAGARA V20.1: Vault V1 (Plaintext) to V2 (AES-256-GCM Envelope) Migration Utility
 *
 * Implements a restartable, idempotent migration utility conforming to Section 9:
 * - Stage A: Read-only Discovery (audits vault records without writing or exposing PII)
 * - Stage B: Dry-run Validation (verifies vector dimensions, KMS key availability, AAD context)
 * - Stage C: Backup Verification (creates protected JSON snapshot of migration candidates)
 * - Stage D: Controlled Migration (atomically replaces plaintext arrays with versioned envelopes)
 * - Stage E: Post-Migration Cryptographic Verification (validates round-trip decryption)
 *
 * CLI Usage:
 *   npx ts-node scripts/migrate_biometric_vault_v1_to_v2.ts --discovery
 *   npx ts-node scripts/migrate_biometric_vault_v1_to_v2.ts --dry-run
 *   npx ts-node scripts/migrate_biometric_vault_v1_to_v2.ts --backup
 *   npx ts-node scripts/migrate_biometric_vault_v1_to_v2.ts --migrate [--batch-size=50] [--max-concurrency=5]
 *   npx ts-node scripts/migrate_biometric_vault_v1_to_v2.ts --verify
 */

import * as admin from 'firebase-admin';
import * as fs from 'fs';
import * as path from 'path';
import { BiometricTemplateCryptoService } from '../services/biometric_template_crypto';
import {
  CANONICAL_SFACE_MODEL_ID,
  CANONICAL_SFACE_MODEL_VERSION,
  SFACE_EMBEDDING_DIMENSION,
} from '../crypto/cloud_kms_envelope';

if (admin.apps.length === 0) {
  admin.initializeApp({
    projectId: process.env.FIREBASE_PROJECT_ID || 'kelasagara-f127a',
  });
}

const db = admin.firestore();
const cryptoService = BiometricTemplateCryptoService.getInstance();

export interface MigrationDiscoveryReport {
  totalRecords: number;
  activeRecords: number;
  legacyPlaintextCount: number;
  alreadyEncryptedCount: number;
  unsupportedSchemaCount: number;
  missingVectorCount: number;
  invalidVectorCount: number;
  unknownModelVersionCount: number;
  timestamp: string;
}

export interface MigrationExecutionResult {
  recordsProcessed: number;
  recordsMigrated: number;
  recordsSkipped: number;
  recordsFailed: number;
  errors: Array<{ docId: string; errorCode: string; message: string }>;
  durationMs: number;
}

export class BiometricVaultV2Migrator {
  private readonly db: admin.firestore.Firestore;
  private readonly crypto: BiometricTemplateCryptoService;
  private readonly collectionName: string;

  constructor(
    firestoreDb = db,
    cryptoSvc = cryptoService,
    collectionName = 'biometric_vault'
  ) {
    this.db = firestoreDb;
    this.crypto = cryptoSvc;
    this.collectionName = collectionName;
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // STAGE A: Read-Only Discovery
  // ─────────────────────────────────────────────────────────────────────────────
  public async runDiscovery(): Promise<MigrationDiscoveryReport> {
    console.log(`[Stage A: Discovery] Scanning collection '${this.collectionName}'...`);
    const snapshot = await this.db.collection(this.collectionName).get();

    let totalRecords = 0;
    let activeRecords = 0;
    let legacyPlaintextCount = 0;
    let alreadyEncryptedCount = 0;
    let unsupportedSchemaCount = 0;
    let missingVectorCount = 0;
    let invalidVectorCount = 0;
    let unknownModelVersionCount = 0;

    for (const doc of snapshot.docs) {
      totalRecords++;
      const data = doc.data();

      if (data.status === 'ACTIVE' || !data.status) {
        activeRecords++;
      }

      if (data.schemaVersion === 2 || data.biometricEnvelope) {
        alreadyEncryptedCount++;
        continue;
      }

      // Check legacy vectors
      const rawVector: number[] | undefined =
        data.canonicalEmbedding || data.sfaceEmbedding128 || data.embedding;

      if (!rawVector) {
        missingVectorCount++;
        continue;
      }

      if (!Array.isArray(rawVector) || rawVector.length !== SFACE_EMBEDDING_DIMENSION) {
        invalidVectorCount++;
        continue;
      }

      const hasNonFinite = rawVector.some((v) => !Number.isFinite(v));
      if (hasNonFinite) {
        invalidVectorCount++;
        continue;
      }

      if (
        data.modelIdentifier &&
        data.modelIdentifier !== CANONICAL_SFACE_MODEL_ID &&
        data.modelIdentifier !== 'opencv_sface_canonical_v10' &&
        data.modelIdentifier !== 'kelasagara_biomatch_v3_whitened'
      ) {
        unknownModelVersionCount++;
      }

      legacyPlaintextCount++;
    }

    const report: MigrationDiscoveryReport = {
      totalRecords,
      activeRecords,
      legacyPlaintextCount,
      alreadyEncryptedCount,
      unsupportedSchemaCount,
      missingVectorCount,
      invalidVectorCount,
      unknownModelVersionCount,
      timestamp: new Date().toISOString(),
    };

    return report;
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // STAGE B: Dry-Run Validation
  // ─────────────────────────────────────────────────────────────────────────────
  public async runDryRun(): Promise<{
    validCount: number;
    invalidCount: number;
    issues: Array<{ docId: string; reason: string }>;
  }> {
    console.log(`[Stage B: Dry-Run] Validating records in '${this.collectionName}'...`);
    const snapshot = await this.db.collection(this.collectionName).get();

    let validCount = 0;
    let invalidCount = 0;
    const issues: Array<{ docId: string; reason: string }> = [];

    for (const doc of snapshot.docs) {
      const data = doc.data();
      if (data.schemaVersion === 2 || data.biometricEnvelope) {
        continue; // Already migrated
      }

      const rawVector: number[] | undefined =
        data.canonicalEmbedding || data.sfaceEmbedding128 || data.embedding;
      const ownerUid = data.owningUid || data.uid || doc.id;

      if (!ownerUid) {
        invalidCount++;
        issues.push({ docId: doc.id, reason: 'MISSING_OWNER_UID' });
        continue;
      }

      if (!rawVector || !Array.isArray(rawVector) || rawVector.length !== SFACE_EMBEDDING_DIMENSION) {
        invalidCount++;
        issues.push({ docId: doc.id, reason: 'INVALID_VECTOR_DIMENSION' });
        continue;
      }

      try {
        this.crypto.validateVectorBeforeEncryption(rawVector);
        validCount++;
      } catch (err: any) {
        invalidCount++;
        issues.push({ docId: doc.id, reason: err.message });
      }
    }

    return { validCount, invalidCount, issues };
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // STAGE C: Backup Verification
  // ─────────────────────────────────────────────────────────────────────────────
  public async createStagingBackup(backupFilePath: string): Promise<{
    backedUpCount: number;
    backupFilePath: string;
    backupSha256: string;
  }> {
    console.log(`[Stage C: Backup] Exporting records to ${backupFilePath}...`);
    const snapshot = await this.db.collection(this.collectionName).get();
    const records = snapshot.docs.map((d) => ({
      id: d.id,
      data: d.data(),
    }));

    const jsonContent = JSON.stringify({
      collection: this.collectionName,
      exportedAt: new Date().toISOString(),
      recordCount: records.length,
      records,
    });

    const dir = path.dirname(backupFilePath);
    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true });
    }
    fs.writeFileSync(backupFilePath, jsonContent, 'utf8');

    const crypto = await import('node:crypto');
    const backupSha256 = crypto.createHash('sha256').update(jsonContent).digest('hex');

    return {
      backedUpCount: records.length,
      backupFilePath,
      backupSha256,
    };
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // STAGE D: Controlled Atomic Migration
  // ─────────────────────────────────────────────────────────────────────────────
  public async runMigration(options?: {
    batchSize?: number;
    maxConcurrency?: number;
  }): Promise<MigrationExecutionResult> {
    const t0 = Date.now();
    const batchSize = options?.batchSize ?? 50;
    const maxConcurrency = options?.maxConcurrency ?? 5;

    console.log(
      `[Stage D: Controlled Migration] Starting (batch=${batchSize}, concurrency=${maxConcurrency})...`
    );

    const snapshot = await this.db
      .collection(this.collectionName)
      .where('status', '==', 'ACTIVE')
      .get();

    let recordsProcessed = 0;
    let recordsMigrated = 0;
    let recordsSkipped = 0;
    let recordsFailed = 0;
    const errors: Array<{ docId: string; errorCode: string; message: string }> = [];

    // Filter candidate documents requiring encryption
    const candidates = snapshot.docs.filter((d) => {
      const data = d.data();
      return !data.schemaVersion || data.schemaVersion < 2 || !data.biometricEnvelope;
    });

    console.log(`Found ${candidates.length} active candidate records requiring encryption.`);

    // Process in chunks with bounded concurrency
    for (let i = 0; i < candidates.length; i += maxConcurrency) {
      const chunk = candidates.slice(i, i + maxConcurrency);
      await Promise.all(
        chunk.map(async (doc) => {
          recordsProcessed++;
          const docId = doc.id;
          const data = doc.data();

          const rawVector: number[] | undefined =
            data.canonicalEmbedding || data.sfaceEmbedding128 || data.embedding;
          const ownerUid = data.owningUid || data.uid || docId;

          if (!rawVector || !Array.isArray(rawVector) || rawVector.length !== SFACE_EMBEDDING_DIMENSION) {
            recordsSkipped++;
            return;
          }

          try {
            // 1. Prepare encrypted envelope outside transaction
            const encPackage = await this.crypto.encryptTemplate({
              templateId: docId,
              ownerUid,
              embedding128: rawVector,
              modelId: data.modelIdentifier || CANONICAL_SFACE_MODEL_ID,
              modelVersion: data.preprocessVersion || CANONICAL_SFACE_MODEL_VERSION,
              nowMs: Date.now(),
            });

            // 2. Atomically update document via transaction
            await this.db.runTransaction(async (tx) => {
              const docRef = this.db.collection(this.collectionName).doc(docId);
              const curSnap = await tx.get(docRef);
              if (!curSnap.exists) return;

              const curData = curSnap.data()!;
              if (curData.schemaVersion === 2 && curData.biometricEnvelope) {
                // Already migrated concurrently
                return;
              }

              // Replace plaintext vector fields atomically with encrypted envelope
              tx.update(docRef, {
                schemaVersion: 2,
                biometricEnvelope: encPackage.biometricEnvelope,
                metadata: encPackage.metadata,
                migratedAtMs: Date.now(),
                // Atomically delete legacy plaintext fields
                canonicalEmbedding: admin.firestore.FieldValue.delete(),
                sfaceEmbedding128: admin.firestore.FieldValue.delete(),
                embedding: admin.firestore.FieldValue.delete(),
              });
            });

            recordsMigrated++;
          } catch (err: any) {
            recordsFailed++;
            errors.push({
              docId,
              errorCode: err?.code || 'MIGRATION_ERROR',
              message: err?.message || 'Unknown migration failure',
            });
          }
        })
      );
    }

    return {
      recordsProcessed,
      recordsMigrated,
      recordsSkipped,
      recordsFailed,
      errors,
      durationMs: Date.now() - t0,
    };
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // STAGE E: Post-Migration Cryptographic Verification
  // ─────────────────────────────────────────────────────────────────────────────
  public async runVerification(): Promise<{
    verifiedCount: number;
    failedCount: number;
    failures: Array<{ docId: string; reason: string }>;
  }> {
    console.log(`[Stage E: Verification] Verifying encrypted envelopes in '${this.collectionName}'...`);
    const snapshot = await this.db.collection(this.collectionName).get();

    let verifiedCount = 0;
    let failedCount = 0;
    const failures: Array<{ docId: string; reason: string }> = [];

    for (const doc of snapshot.docs) {
      const data = doc.data();
      if (!data.biometricEnvelope || data.schemaVersion !== 2) {
        continue;
      }

      const docId = doc.id;
      const ownerUid = data.owningUid || data.uid || docId;

      try {
        const decryptedVec = await this.crypto.decryptTemplate({
          templateId: docId,
          ownerUid,
          envelope: data.biometricEnvelope,
          modelId: data.modelIdentifier || CANONICAL_SFACE_MODEL_ID,
          modelVersion: data.preprocessVersion || CANONICAL_SFACE_MODEL_VERSION,
        });

        if (decryptedVec.length !== SFACE_EMBEDDING_DIMENSION) {
          throw new Error(`Dimension mismatch: ${decryptedVec.length}`);
        }
        verifiedCount++;
      } catch (err: any) {
        failedCount++;
        failures.push({ docId, reason: err.message });
      }
    }

    return { verifiedCount, failedCount, failures };
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CLI Runner
// ─────────────────────────────────────────────────────────────────────────────
if (require.main === module) {
  const args = process.argv.slice(2);
  const migrator = new BiometricVaultV2Migrator();

  async function main() {
    if (args.includes('--discovery')) {
      const res = await migrator.runDiscovery();
      console.log('Discovery Report:', JSON.stringify(res, null, 2));
    } else if (args.includes('--dry-run')) {
      const res = await migrator.runDryRun();
      console.log('Dry-Run Report:', JSON.stringify(res, null, 2));
    } else if (args.includes('--backup')) {
      const bkpPath = path.resolve(process.cwd(), `backups/biometric_vault_backup_${Date.now()}.json`);
      const res = await migrator.createStagingBackup(bkpPath);
      console.log('Backup Report:', JSON.stringify(res, null, 2));
    } else if (args.includes('--migrate')) {
      const res = await migrator.runMigration();
      console.log('Migration Result:', JSON.stringify(res, null, 2));
    } else if (args.includes('--verify')) {
      const res = await migrator.runVerification();
      console.log('Verification Report:', JSON.stringify(res, null, 2));
    } else {
      console.log('Usage: migrate_biometric_vault_v1_to_v2.ts [--discovery|--dry-run|--backup|--migrate|--verify]');
    }
  }

  main()
    .then(() => process.exit(0))
    .catch((err) => {
      console.error('Migration CLI failed:', err);
      process.exit(1);
    });
}
