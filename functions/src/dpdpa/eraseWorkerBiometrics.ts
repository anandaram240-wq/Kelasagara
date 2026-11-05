import { onCall, HttpsError, CallableRequest } from 'firebase-functions/v2/https';
import * as logger from 'firebase-functions/logger';
import * as admin from 'firebase-admin';
import { KeyManagementServiceClient } from '@google-cloud/kms';
import { Storage } from '@google-cloud/storage';
import { Pool } from 'pg';
import * as crypto from 'crypto';

if (!admin.apps.length) {
  admin.initializeApp();
}

// ============================================================================
// 1. INTERFACES & STATUTORY CONSTANTS
// ============================================================================
export type ErasureTriggerType =
  | 'DPDPA_SEC_12_3_USER_REQUEST'
  | 'DPDPA_SEC_6_4_CONSENT_WITHDRAWAL'
  | 'DPDPA_SEC_8_7_PURPOSE_COMPLETED';

export interface ErasureRequestPayload {
  trigger: ErasureTriggerType;
  consentArtifactId: string;
  reasonCode?: string;
  deleteFullAccount?: boolean;
}

export interface WormAuditLeaf {
  erasureId: string;
  schemaVersion: 'v17.2-dpdpa';
  statutoryBasis: ErasureTriggerType;
  pseudonymizedSubjectHash: string; // HMAC-SHA256(pepper, uid) - zero PII
  consentArtifactId: string;
  executedAtIso: string;
  kmsShredSummary: {
    keyVersionName: string;
    isolationMode: 'DEDICATED_KEY_VERSION' | 'SHARED_COHORT_KEK';
    kmsVersionState: string;
    wrappedDekSha256: string;
    firestoreVaultOverwrittenAndDeleted: boolean;
  };
  pgVectorShredSummary: {
    templateOverwrittenAndDeleted: boolean;
    reviewQueuePurged: boolean;
  };
  legalHoldRetainedFields: string[]; // Empty array if full erasure, or ['tax_ledger_id'] under Sec 12(5)(b)
  prevChainHash: string;
  leafHash: string;
}

export interface ErasureCertificateResponse {
  erasureId: string;
  status: 'COMPLETED_IRREVERSIBLE' | 'PARTIAL_STATUTORY_RETENTION';
  executedAtIso: string;
  leafHash: string;
  kmsReceiptSignatureBase64: string;
  signingKeyVersion: string;
  wormObjectUri: string;
}

// ============================================================================
// 2. INFRASTRUCTURE SINGLETONS
// ============================================================================
const db = admin.firestore();
const kmsClient = new KeyManagementServiceClient();
const gcsStorage = new Storage();

const pgPool = new Pool({
  host: process.env.DB_HOST,
  database: process.env.DB_NAME || 'kelasagara_biometrics',
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  port: Number(process.env.DB_PORT || 5432),
  max: 15,
  idleTimeoutMillis: 30000,
  ssl: process.env.DB_REQUIRE_SSL === 'true' ? { rejectUnauthorized: true } : undefined,
});

const AUDIT_HMAC_PEPPER =
  process.env.DPDPA_AUDIT_PEPPER || 'rotate-in-secret-manager-32-byte-pepper-key';
const WORM_BUCKET_NAME =
  process.env.DPDPA_WORM_BUCKET || 'kelasagara-prod-dpdpa-worm-audit';
const KMS_AUDIT_SIGNING_KEY_VERSION =
  process.env.KMS_AUDIT_SIGNING_KEY_VERSION ||
  'projects/kelasagara-prod/locations/asia-south1/keyRings/biometrics-ring/cryptoKeys/dpdpa-audit-signer/cryptoKeyVersions/1';
const KEY_ISOLATION_MODE =
  (process.env.KMS_KEY_ISOLATION_MODE as 'DEDICATED_KEY_VERSION' | 'SHARED_COHORT_KEK') ||
  'SHARED_COHORT_KEK';

// ============================================================================
// 3. CRYPTOGRAPHIC HELPER UTILITIES
// ============================================================================

/**
 * Generates a normalized 128-D random unit vector on S^127 to overwrite
 * the pgvector heap slot before issuing SQL DELETE.
 */
function generateCsprngUnitVector128(): string {
  const rawFloats = new Float32Array(128);
  const randBytes = crypto.randomBytes(128 * 4);
  let normSq = 0.0;

  for (let i = 0; i < 128; i++) {
    // Map random uint32 to [-1.0, 1.0]
    const uintVal = randBytes.readUInt32LE(i * 4);
    const val = (uintVal / 0xffffffff) * 2.0 - 1.0;
    rawFloats[i] = val;
    normSq += val * val;
  }

  const invNorm = 1.0 / Math.sqrt(Math.max(normSq, 1e-12));
  const formatted: string[] = new Array(128);
  for (let i = 0; i < 128; i++) {
    formatted[i] = (rawFloats[i] * invNorm).toFixed(8);
  }
  return `[${formatted.join(',')}]`;
}

/**
 * Computes an irreversible pseudonymized subject token: HMAC-SHA256(pepper, uid)
 * Satisfies DPDP Rules Rule 8(3) 1-year log retention without storing PII.
 */
function computePseudonymizedSubjectHash(uid: string): string {
  return crypto.createHmac('sha256', AUDIT_HMAC_PEPPER).update(uid, 'utf8').digest('hex');
}

/**
 * Signs the canonical WORM audit leaf hash using an asymmetric HSM key
 * (`EC_SIGN_P256_SHA256`) in Google Cloud KMS.
 */
async function signAuditLeafWithKms(leafHashHex: string): Promise<string> {
  const digestBuffer = Buffer.from(leafHashHex, 'hex');
  const [signResponse] = await kmsClient.asymmetricSign({
    name: KMS_AUDIT_SIGNING_KEY_VERSION,
    digest: {
      sha256: digestBuffer,
    },
  });

  if (!signResponse.signature) {
    throw new Error('Cloud KMS failed to produce an asymmetric audit signature.');
  }
  return Buffer.from(signResponse.signature).toString('base64');
}

// ============================================================================
// 4. MAIN CLOUD FUNCTION: `eraseWorkerBiometrics` (DPDPA SEC. 12 & SEC. 8(7))
// ============================================================================
export const eraseWorkerBiometrics = onCall(
  {
    region: 'asia-south1', // Mumbai region for Indian data residency compliance
    memory: '512MiB',
    timeoutSeconds: 60,
    enforceAppCheck: true, // Enforces Google Play Integrity attestation via Firebase App Check
  },
  async (request: CallableRequest<ErasureRequestPayload>): Promise<ErasureCertificateResponse> => {
    // ------------------------------------------------------------------------
    // STEP 1: AUTHENTICATION & FRESHNESS VERIFICATION
    // ------------------------------------------------------------------------
    if (!request.auth || !request.auth.uid) {
      throw new HttpsError(
        'unauthenticated',
        'ದೃಢೀಕರಣ ಅಗತ್ಯವಿದೆ (Authentication required to invoke Right to Erasure).'
      );
    }

    const uid = request.auth.uid;
    const authTimeSeconds = Number(request.auth.token.auth_time || 0);
    const nowSeconds = Math.floor(Date.now() / 1000);

    // Require fresh authentication (< 5 minutes) to prevent session-hijack deletion
    if (nowSeconds - authTimeSeconds > 300) {
      throw new HttpsError(
        'permission-denied',
        'ಭದ್ರತಾ ಕಾರಣಗಳಿಗಾಗಿ ದಯವಿಟ್ಟು ಮತ್ತೆ OTP ಲಾಗಿನ್ ಮಾಡಿ (Please re-authenticate within the last 5 minutes before erasing biometric data).'
      );
    }

    const { trigger, consentArtifactId, deleteFullAccount = true } = request.data || {};
    if (!trigger || !consentArtifactId) {
      throw new HttpsError(
        'invalid-argument',
        'Missing mandatory DPDPA erasure parameters: trigger and consentArtifactId.'
      );
    }

    const erasureId = crypto.randomUUID();
    const subjectHash = computePseudonymizedSubjectHash(uid);

    // ------------------------------------------------------------------------
    // STEP 2: STATUTORY EXCEPTION CHECK (DPDPA SECTION 12(5)(b))
    // ------------------------------------------------------------------------
    const userRef = db.collection('users').doc(uid);
    const vaultRef = db.collection('biometric_vault').doc(uid);
    const reviewQueueRef = db.collection('biometric_review_queue').doc(uid);

    const [userSnap, vaultSnap] = await Promise.all([userRef.get(), vaultRef.get()]);

    if (!userSnap.exists && !vaultSnap.exists) {
      throw new HttpsError('not-found', 'No active biometric or user record exists for this UID.');
    }

    const userData = userSnap.data() || {};

    // If account is under an active law-enforcement or judicial hold (Sec. 12(5)(b)),
    // refuse erasure completely.
    if (userData.judicialHold === true || userData.lawEnforcementFreeze === true) {
      throw new HttpsError(
        'failed-precondition',
        'Erasure blocked under DPDPA Section 12(5)(b): Account is subject to an active statutory or judicial preservation order.'
      );
    }

    // Check if worker has completed financial payouts that must be retained for 6 years
    // under the Income Tax Act, 1961. Note: Even when financial records are retained,
    // raw 128-D biometric templates are ALWAYS erased immediately upon consent withdrawal!
    const hasTaxablePayouts = Number(userData.totalPayoutsInr || 0) > 0;
    const legalHoldRetainedFields: string[] = hasTaxablePayouts
      ? ['financial_ledger_reference_id', 'tax_fy_summary']
      : [];

    // ------------------------------------------------------------------------
    // STEP 3: CLOUD KMS CRYPTO-SHREDDING & FIRESTORE VAULT OVERWRITE
    // ------------------------------------------------------------------------
    let keyVersionName = 'NONE';
    let wrappedDekSha256 = crypto.createHash('sha256').update(uid).digest('hex');
    let kmsVersionState = 'NOT_APPLICABLE';
    let firestoreVaultShredded = false;

    if (vaultSnap.exists) {
      const vaultData = vaultSnap.data()!;
      keyVersionName = String(vaultData.keyVersionName || '');
      const wrappedDekBase64 = String(vaultData.wrappedDek || '');
      const aadContext = String(vaultData.aadContext || '');

      wrappedDekSha256 = crypto
        .createHash('sha256')
        .update(`${wrappedDekBase64}:${aadContext}`, 'utf8')
        .digest('hex');

      // Path A: Dedicated KMS CryptoKeyVersion per worker -> Destroy in Cloud KMS HSM
      if (KEY_ISOLATION_MODE === 'DEDICATED_KEY_VERSION' && keyVersionName.includes('/cryptoKeyVersions/')) {
        try {
          const [destroyedVersion] = await kmsClient.destroyCryptoKeyVersion({
            name: keyVersionName,
          });
          kmsVersionState = String(destroyedVersion.state || 'DESTROY_SCHEDULED');
        } catch (kmsErr: any) {
          // Handle idempotent retries if version is already DESTROY_SCHEDULED or DESTROYED
          if (kmsErr?.code === 9 || String(kmsErr?.message).includes('DESTROY')) {
            kmsVersionState = 'ALREADY_DESTROY_SCHEDULED';
          } else {
            logger.error('KMS destroyCryptoKeyVersion failed', { erasureId, error: kmsErr });
            throw new HttpsError('internal', 'Failed to execute Cloud KMS key destruction.');
          }
        }
      } else {
        // Path B: Shared Cohort KEK -> Wrapped DEK is permanently revoked in pgvector transaction below
        kmsVersionState = 'DEK_REVOKED_AND_SHREDDED';
      }

      // Overwrite Firestore `biometric_vault/{uid}` with CSPRNG bytes BEFORE deleting
      // so underlying storage SSTables flush random noise over the old ciphertext.
      await vaultRef.set(
        {
          ciphertext: crypto.randomBytes(512).toString('base64'),
          wrappedDek: crypto.randomBytes(128).toString('base64'),
          iv: crypto.randomBytes(12).toString('base64'),
          tag: crypto.randomBytes(16).toString('base64'),
          aadContext: 'SHREDDED_DPDPA_SEC_12',
          keyVersionName: 'SHREDDED',
          shreddedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: false }
      );

      await vaultRef.delete();
      firestoreVaultShredded = true;
    }

    // ------------------------------------------------------------------------
    // STEP 4: POSTGRESQL 16 `pgvector` IN-PLACE SCRUB & HARD DELETE
    // ------------------------------------------------------------------------
    const noiseVectorLiteral = generateCsprngUnitVector128();
    let pgTemplateShredded = false;

    const pgClient = await pgPool.connect();
    try {
      await pgClient.query('BEGIN');
      const shredRes = await pgClient.query(
        `SELECT shred_worker_biometric_template($1, $2::vector, $3, $4, $5) AS shredded;`,
        [uid, noiseVectorLiteral, wrappedDekSha256, subjectHash, keyVersionName]
      );
      pgTemplateShredded = Boolean(shredRes.rows[0]?.shredded);
      await pgClient.query('COMMIT');
    } catch (pgErr) {
      await pgClient.query('ROLLBACK');
      logger.error('pgvector biometric shredding transaction failed', { erasureId, error: pgErr });
      throw new HttpsError('internal', 'Failed to purge biometric vector index.');
    } finally {
      pgClient.release();
    }

    // Purge any pending manual fraud/ambiguity queue entry
    await reviewQueueRef.delete();

    // ------------------------------------------------------------------------
    // STEP 5: SCRUB USER PROFILE PII & REVOKE CONSENT ARTIFACT
    // ------------------------------------------------------------------------
    const consentRef = db.collection('consent_ledger').doc(consentArtifactId);
    const consentSnap = await consentRef.get();

    const profileBatch = db.batch();

    if (deleteFullAccount && !hasTaxablePayouts) {
      // Overwrite PII fields before deleting the document
      profileBatch.set(
        userRef,
        {
          name: 'ERASED_DPDPA',
          username: `erased_${erasureId.slice(0, 8)}`,
          phone: 'ERASED',
          skills: [],
          district: 'ERASED',
          faceVerified: false,
          accountStatus: 'erased_dpdpa_sec12',
        },
        { merge: false }
      );
      profileBatch.delete(userRef);
    } else {
      // Partial erasure under DPDPA Sec. 12(5)(b) (biometrics + PII erased, tax reference kept)
      profileBatch.set(
        userRef,
        {
          name: 'ERASED_DPDPA_SEC12',
          username: `erased_${erasureId.slice(0, 8)}`,
          phone: 'ERASED',
          faceVerified: false,
          accountStatus: 'erased_biometrics_tax_retained',
          biometricConsentId: admin.firestore.FieldValue.delete(),
          biometricEraseReceiptId: erasureId,
          erasedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    }

    // Record immutable withdrawal event in `consent_revocations` (since `consent_ledger` is WORM)
    if (consentSnap.exists) {
      const revocationRef = db.collection('consent_revocations').doc(consentArtifactId);
      profileBatch.set(revocationRef, {
        consentArtifactId,
        pseudonymizedSubjectHash: subjectHash,
        trigger,
        erasureId,
        revokedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    await profileBatch.commit();

    // ------------------------------------------------------------------------
    // STEP 6: APPEND HASH-CHAINED WORM AUDIT RECORD & KMS SIGNATURE
    // ------------------------------------------------------------------------
    const executedAtIso = new Date().toISOString();

    const wormLeaf: WormAuditLeaf = await db.runTransaction(async (tx) => {
      const chainHeadRef = db.collection('worm_erasure_meta').doc('chain_head');
      const chainHeadSnap = await tx.get(chainHeadRef);
      const prevChainHash = chainHeadSnap.exists
        ? String(chainHeadSnap.data()?.lastLeafHash || '0'.repeat(64))
        : '0'.repeat(64);

      const unsignedLeaf: Omit<WormAuditLeaf, 'leafHash'> = {
        erasureId,
        schemaVersion: 'v17.2-dpdpa',
        statutoryBasis: trigger,
        pseudonymizedSubjectHash: subjectHash,
        consentArtifactId,
        executedAtIso,
        kmsShredSummary: {
          keyVersionName,
          isolationMode: KEY_ISOLATION_MODE,
          kmsVersionState,
          wrappedDekSha256,
          firestoreVaultOverwrittenAndDeleted: firestoreVaultShredded,
        },
        pgVectorShredSummary: {
          templateOverwrittenAndDeleted: pgTemplateShredded,
          reviewQueuePurged: true,
        },
        legalHoldRetainedFields,
        prevChainHash,
      };

      const canonicalJson = JSON.stringify(unsignedLeaf);
      const leafHash = crypto
        .createHash('sha256')
        .update(`${prevChainHash}:${canonicalJson}`, 'utf8')
        .digest('hex');

      const fullLeaf: WormAuditLeaf = {
        ...unsignedLeaf,
        leafHash,
      };

      const ledgerDocRef = db.collection('worm_erasure_ledger').doc(erasureId);
      tx.create(ledgerDocRef, fullLeaf);
      tx.set(chainHeadRef, {
        lastLeafHash: leafHash,
        lastErasureId: erasureId,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      return fullLeaf;
    });

    // Sign the leaf hash with Cloud KMS ECDSA P-256 key
    const kmsReceiptSignatureBase64 = await signAuditLeafWithKms(wormLeaf.leafHash);

    // Persist WORM archive object to Google Cloud Storage Bucket with Object Retention Lock
    const datePrefix = executedAtIso.slice(0, 10); // YYYY-MM-DD
    const objectName = `dpdpa-sec12-erasures/${datePrefix}/${erasureId}.json`;
    const wormBucket = gcsStorage.bucket(WORM_BUCKET_NAME);
    const wormFile = wormBucket.file(objectName);

    await wormFile.save(
      JSON.stringify(
        {
          ...wormLeaf,
          kmsReceiptSignatureBase64,
          signingKeyVersion: KMS_AUDIT_SIGNING_KEY_VERSION,
        },
        null,
        2
      ),
      {
        contentType: 'application/json',
        resumable: false,
        metadata: {
          cacheControl: 'no-store',
          metadata: {
            dpdpaSection: '12_3_AND_8_7',
            subjectHash,
            leafHash: wormLeaf.leafHash,
          },
        },
      }
    );

    // ------------------------------------------------------------------------
    // STEP 7: REVOKE FIREBASE AUTH SESSIONS & DELETE/DISABLE IDENTITY
    // ------------------------------------------------------------------------
    await admin.auth().revokeRefreshTokens(uid);
    if (deleteFullAccount && !hasTaxablePayouts) {
      await admin.auth().deleteUser(uid);
    } else {
      await admin.auth().setCustomUserClaims(uid, { biometricAttested: false });
      await admin.auth().updateUser(uid, { disabled: true });
    }

    logger.info('DPDPA Section 12 Biometric Crypto-Shredding Completed', {
      erasureId,
      subjectHash,
      leafHash: wormLeaf.leafHash,
    });

    return {
      erasureId,
      status: hasTaxablePayouts ? 'PARTIAL_STATUTORY_RETENTION' : 'COMPLETED_IRREVERSIBLE',
      executedAtIso,
      leafHash: wormLeaf.leafHash,
      kmsReceiptSignatureBase64,
      signingKeyVersion: KMS_AUDIT_SIGNING_KEY_VERSION,
      wormObjectUri: `gs://${WORM_BUCKET_NAME}/${objectName}`,
    };
  }
);
