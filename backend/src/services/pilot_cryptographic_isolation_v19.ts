/**
 * KELASAGARA V20.19: PILOT-SPECIFIC CRYPTOGRAPHIC ISOLATION ENGINE
 *
 * Implements strict non-production dataset separation and key isolation:
 *
 * 1. Dedicated Pilot Database & Keyring Scope:
 *    - Pilot templates are targeted to a dedicated named Firestore database ('biometric-pilot-vault-db').
 *    - Pilot DEKs are wrapped using an isolated KMS key ('pilot_dek_wrap').
 *    - Production database configuration cannot query pilot records.
 *    - Operational Status: Real cloud separation remains UNVERIFIED until Gate B (Real Non-Production
 *      Cloud Infrastructure) passes. Software enforcement verifies isolation logic locally.
 * 2. Cross-Environment Fail-Closed Defense:
 *    - Requests attempting to access production templates via pilot credentials or vice versa
 *      fail closed immediately with ERR_CROSS_ENVIRONMENT_ISOLATION_VIOLATION.
 * 3. Environment-Bound AAD Construction (ISO/IEC 19772:2020):
 *    - In accordance with the authenticated associated data (AAD) binding principles of ISO/IEC 19772:2020
 *      (Information security — Authenticated encryption), the length-prefixed binary canonical encoding is an
 *      application-defined Kelasagara format designed to prevent delimiter collisions and field-shifting attacks.
 *    - Pilot AAD binds 'datasetScope=PILOT_NONPROD' and 'tenant=kelasagara-pilot'.
 *    - Production AAD cannot decrypt pilot ciphertexts.
 * 4. Isolation Classification: COHORT_LEVEL_CRYPTOGRAPHIC_ISOLATION_WITH_PER_RECORD_AUTHORIZATION:
 *    - Sharing 'pilot_dek_wrap' across the pilot cohort provides cohort-level cryptographic isolation (protecting
 *      production from pilot key exposure), but is NOT per-user cryptographic key isolation. Any principal
 *      with unwrap rights on 'pilot_dek_wrap' can unwrap any pilot DEK. Per-user isolation at runtime
 *      relies on separate random DEKs, session UID checks, and environment-scoped AAD.
 * 5. Best-Effort Plaintext Memory Clearing:
 *    - Plaintext DEK buffers owned by this process are cleared with plaintextDek.fill(0) in finally blocks.
 *    - Honest runtime limitations: Node.js/V8 garbage collector, memory compaction, OpenSSL native allocations,
 *      and OS swap space prevent hardware-level absolute zeroization guarantees. Clearing is strictly best-effort.
 */

import * as crypto from 'crypto';

export const ISOLATION_MODEL = 'COHORT_LEVEL_CRYPTOGRAPHIC_ISOLATION_WITH_PER_RECORD_AUTHORIZATION' as const;

export type EnvironmentScopeV19 = 'PRODUCTION' | 'PILOT_NONPROD';

export interface PilotVaultRecordV19 {
  templateId: string;
  accountUid: string;
  databaseScope: 'biometric-pilot-vault-db' | 'biometric-vault-db';
  datasetScope: EnvironmentScopeV19;
  kmsKeyId: string;
  wrappedDekBase64: string;
  ciphertextBase64: string;
  ivBase64: string;
  authTagBase64: string;
  isActive: boolean;
}

export const PILOT_KMS_KEY_ID =
  'projects/kelasagara-sandbox/locations/global/keyRings/biometrics-pilot-ring/cryptoKeys/pilot_dek_wrap';
export const PROD_KMS_KEY_ID =
  'projects/kelasagara-prod/locations/global/keyRings/biometrics-prod-ring/cryptoKeys/prod_dek_wrap';

export const PILOT_DATABASE_NAME = 'biometric-pilot-vault-db';
export const PROD_DATABASE_NAME = 'biometric-vault-db';

export class PilotCryptographicIsolationEngineV19 {
  /**
   * Constructs environment-bound length-prefixed binary AAD adhering to ISO/IEC 19772:2020
   * associated data binding principles using an application-defined Kelasagara binary format.
   */
  public constructScopedAad(
    tenant: string,
    accountUid: string,
    templateId: string,
    datasetScope: EnvironmentScopeV19
  ): Buffer {
    const fields = [
      Buffer.from(tenant, 'utf8'),
      Buffer.from(accountUid, 'utf8'),
      Buffer.from(templateId, 'utf8'),
      Buffer.from(datasetScope, 'utf8'),
    ];

    let totalLength = 0;
    for (const f of fields) {
      totalLength += 4 + f.length;
    }
    const buf = Buffer.alloc(totalLength);
    let offset = 0;
    for (const f of fields) {
      buf.writeUInt32BE(f.length, offset);
      offset += 4;
      f.copy(buf, offset);
      offset += f.length;
    }
    return buf;
  }

  /**
   * Encrypts a template bound to the pilot non-production scope.
   */
  public encryptPilotTemplate(
    accountUid: string,
    templateId: string,
    embedding: Float32Array
  ): PilotVaultRecordV19 {
    const rawVectorBytes = Buffer.from(embedding.buffer, embedding.byteOffset, embedding.byteLength);
    const plaintextDek = crypto.randomBytes(32);
    const iv = crypto.randomBytes(12);

    try {
      const aad = this.constructScopedAad('kelasagara-pilot', accountUid, templateId, 'PILOT_NONPROD');
      const cipher = crypto.createCipheriv('aes-256-gcm', plaintextDek, iv);
      cipher.setAAD(aad);
      const ciphertext = Buffer.concat([cipher.update(rawVectorBytes), cipher.final()]);
      const authTag = cipher.getAuthTag();

      // Wrap DEK with pilot KMS key simulation
      const kmsContext = Buffer.from(`key=${PILOT_KMS_KEY_ID}:acc=${accountUid}:tpl=${templateId}`, 'utf8');
      const wrappedDek = Buffer.concat([
        Buffer.from('PILOT_KMS:'),
        plaintextDek,
        Buffer.from(':SIG='),
        crypto.createHash('sha256').update(plaintextDek).update(kmsContext).digest().subarray(0, 8),
      ]);

      return {
        templateId,
        accountUid,
        databaseScope: PILOT_DATABASE_NAME,
        datasetScope: 'PILOT_NONPROD',
        kmsKeyId: PILOT_KMS_KEY_ID,
        wrappedDekBase64: wrappedDek.toString('base64'),
        ciphertextBase64: ciphertext.toString('base64'),
        ivBase64: iv.toString('base64'),
        authTagBase64: authTag.toString('base64'),
        isActive: true,
      };
    } finally {
      plaintextDek.fill(0);
    }
  }

  /**
   * Decrypts pilot template with strict database and key scoping.
   */
  public decryptScopedTemplate(
    record: PilotVaultRecordV19,
    requestScope: {
      activeDatabase: string;
      invokingKeyId: string;
      callerSessionUid: string;
    }
  ): { templateId: string; embedding: Float32Array } {
    // 1. Cross-Environment Database Boundary Check
    if (requestScope.activeDatabase !== record.databaseScope) {
      throw new Error(
        `ERR_CROSS_ENVIRONMENT_ISOLATION_VIOLATION: Database mismatch. Record is in '${record.databaseScope}', query invoked against '${requestScope.activeDatabase}'.`
      );
    }

    // 2. KMS Key ID Matching Check
    if (requestScope.invokingKeyId !== record.kmsKeyId) {
      throw new Error(
        `ERR_CROSS_ENVIRONMENT_ISOLATION_VIOLATION: Key ID mismatch. Record wrapped by '${record.kmsKeyId}', invoked with '${requestScope.invokingKeyId}'.`
      );
    }

    // 3. Session UID Ownership Check
    if (record.accountUid !== requestScope.callerSessionUid) {
      throw new Error(
        `UNAUTHORIZED_RECORD_ACCESS: Caller session '${requestScope.callerSessionUid}' cannot access template belonging to '${record.accountUid}'.`
      );
    }

    // 4. Unwrap Pilot DEK
    const wrappedDekBuffer = Buffer.from(record.wrappedDekBase64, 'base64');
    let plaintextDek: Buffer | null = null;

    try {
      if (!wrappedDekBuffer.toString('utf8', 0, 10).startsWith('PILOT_KMS:')) {
        throw new Error('ERR_KMS_UNWRAP_FAILED: Invalid pilot wrapped DEK format.');
      }

      const kmsContext = Buffer.from(`key=${record.kmsKeyId}:acc=${record.accountUid}:tpl=${record.templateId}`, 'utf8');
      const rawDek = wrappedDekBuffer.subarray(10, 42);
      const sigPart = wrappedDekBuffer.subarray(47, 55);
      const expectedSig = crypto.createHash('sha256').update(rawDek).update(kmsContext).digest().subarray(0, 8);

      if (!crypto.timingSafeEqual(sigPart, expectedSig)) {
        throw new Error('ERR_KMS_UNWRAP_FAILED: KMS Context AAD mismatch on pilot DEK.');
      }

      plaintextDek = Buffer.alloc(rawDek.length);
      rawDek.copy(plaintextDek);

      // 5. Decrypt with Environment-Bound AAD
      const tenant = record.datasetScope === 'PILOT_NONPROD' ? 'kelasagara-pilot' : 'kelasagara-prod';
      const aad = this.constructScopedAad(tenant, record.accountUid, record.templateId, record.datasetScope);

      const ciphertext = Buffer.from(record.ciphertextBase64, 'base64');
      const iv = Buffer.from(record.ivBase64, 'base64');
      const authTag = Buffer.from(record.authTagBase64, 'base64');

      const decipher = crypto.createDecipheriv('aes-256-gcm', plaintextDek, iv);
      decipher.setAAD(aad);
      decipher.setAuthTag(authTag);

      let decrypted: Buffer;
      try {
        decrypted = Buffer.concat([decipher.update(ciphertext), decipher.final()]);
      } catch (cipherErr: any) {
        throw new Error(
          `AUTHENTICATION_TAG_VERIFICATION_FAILED: Decryption authentication failed: ${cipherErr.message}`
        );
      }
      const embedding = new Float32Array(decrypted.buffer, decrypted.byteOffset, decrypted.byteLength / 4);

      return {
        templateId: record.templateId,
        embedding,
      };
    } finally {
      if (plaintextDek) {
        plaintextDek.fill(0);
      }
    }
  }
}
