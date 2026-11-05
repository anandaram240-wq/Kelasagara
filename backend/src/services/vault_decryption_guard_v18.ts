/**
 * KELASAGARA V20.18: VAULT DECRYPTION GUARD & BEST-EFFORT MEMORY CLEARING
 *
 * Implements cryptographic blast-radius containment, length-prefixed binary AAD construction,
 * record-level ownership gating, template lifecycle fencing, and best-effort DEK memory clearing.
 *
 * Key Architectural Guarantees:
 * 1. Independent AAD Handling:
 *    - Cloud KMS wrapped-DEK AAD: Bound to tenant and encryption context.
 *    - Application AES-256-GCM Template AAD: Application-defined Kelasagara length-prefixed binary format
 *      adhering to ISO/IEC 19772:2020 authenticated associated data binding principles, binding
 *      accountUid, templateId, vaultRecordVersion, encryptionSchemaVersion, embeddingSpaceId, and approvedContext.
 *    - AAD is NEVER accepted from the client; it is constructed strictly in trusted backend memory.
 *    - Failed verification never falls back to an empty AAD or another record's context.
 * 2. Pre-KMS Lifecycle Gating:
 *    - Superseded, revoked, or inactive templates, as well as session UID mismatches in 1:1 mode,
 *      are rejected BEFORE any request is dispatched to Cloud KMS.
 * 3. Honest DEK Memory Handling:
 *    - Plaintext DEK is held only for the duration of the decipher call.
 *    - Direct best-effort clearing of the owned buffer (plaintextDek.fill(0)) is executed in 'finally' blocks.
 *    - Executed reliably on all code paths: success, cipher corruption, tag failure, or runtime errors.
 * 4. Blast-Radius Decision Architecture:
 *    - Option A: Verifier-owned decryption with hardened record authorization, rate limiting, and lifecycle fencing.
 *    - Option B: Dedicated vault decryption service.
 *    - Option C: Pilot-specific cryptographic isolation with disjoint pilot DEK wrapping keys.
 */

import * as crypto from 'crypto';

export interface TrustedAadComponentsV18 {
  accountUid: string;
  templateId: string;
  vaultRecordVersion: number;
  encryptionSchemaVersion: string; // e.g. 'v3_kms_gcm'
  embeddingSpaceId: string; // e.g. 'sface_opencv_zoo_v1_canonical112'
  approvedContext: '1to1_auth' | '1toN_dedup';
}

export interface EncryptedVaultRecordV18 {
  templateId: string;
  accountUid: string;
  vaultRecordVersion: number;
  encryptionSchemaVersion: string;
  embeddingSpaceId: string;
  lifecycleStatus: 'ACTIVE' | 'SUPERSEDED' | 'REVOKED';
  wrappedDekBase64: string;
  ciphertextBase64: string;
  ivBase64: string;
  authTagBase64: string;
}

export interface DecryptionRequestV18 {
  record: EncryptedVaultRecordV18;
  callerSessionUid: string;
  callerContext: '1to1_auth' | '1toN_dedup';
  mockKmsUnwrapFn?: (wrappedDek: Buffer, kmsAad: Buffer) => Buffer;
}

export interface DecryptedTemplateResultV18 {
  templateId: string;
  accountUid: string;
  embedding: Float32Array;
  decryptionAuditId: string;
  memoryCleared: boolean;
}

export class VaultDecryptionGuardV18 {
  /**
   * Constructs application-defined length-prefixed binary AAD adhering to ISO/IEC 19772:2020
   * authenticated associated data binding principles to prevent delimiter collision.
   */
  public constructCanonicalBinaryAad(components: TrustedAadComponentsV18): Buffer {
    const fields = [
      Buffer.from(components.accountUid, 'utf8'),
      Buffer.from(components.templateId, 'utf8'),
      Buffer.from(components.vaultRecordVersion.toString(), 'utf8'),
      Buffer.from(components.encryptionSchemaVersion, 'utf8'),
      Buffer.from(components.embeddingSpaceId, 'utf8'),
      Buffer.from(components.approvedContext, 'utf8'),
    ];

    let totalLength = 0;
    for (const f of fields) {
      totalLength += 4 + f.length; // 4 bytes big-endian length prefix + field bytes
    }

    const aadBuffer = Buffer.alloc(totalLength);
    let offset = 0;
    for (const f of fields) {
      aadBuffer.writeUInt32BE(f.length, offset);
      offset += 4;
      f.copy(aadBuffer, offset);
      offset += f.length;
    }

    return aadBuffer;
  }

  /**
   * Constructs KMS encryption context / AAD for wrapping the DEK.
   */
  public constructKmsWrappedDekAad(tenantId: string, accountUid: string, templateId: string): Buffer {
    return Buffer.from(`kms:tenant=${tenantId}:account=${accountUid}:template=${templateId}`, 'utf8');
  }

  /**
   * Encrypts a raw 128-dim Float32Array template using simulated KMS envelope encryption.
   */
  public encryptTemplateSnapshot(
    accountUid: string,
    templateId: string,
    embedding: Float32Array,
    approvedContext: '1to1_auth' | '1toN_dedup' = '1to1_auth'
  ): EncryptedVaultRecordV18 {
    const rawVectorBytes = Buffer.from(embedding.buffer, embedding.byteOffset, embedding.byteLength);

    // Generate random 256-bit DEK
    const plaintextDek = crypto.randomBytes(32);
    const iv = crypto.randomBytes(12);

    try {
      const aadComponents: TrustedAadComponentsV18 = {
        accountUid,
        templateId,
        vaultRecordVersion: 1,
        encryptionSchemaVersion: 'v3_kms_gcm',
        embeddingSpaceId: 'sface_opencv_zoo_v1_canonical112',
        approvedContext,
      };
      const templateAad = this.constructCanonicalBinaryAad(aadComponents);

      const cipher = crypto.createCipheriv('aes-256-gcm', plaintextDek, iv);
      cipher.setAAD(templateAad);
      const ciphertext = Buffer.concat([cipher.update(rawVectorBytes), cipher.final()]);
      const authTag = cipher.getAuthTag();

      // Wrap DEK with KMS simulated context
      const kmsAad = this.constructKmsWrappedDekAad('kelasagara', accountUid, templateId);
      const wrappedDek = Buffer.concat([
        Buffer.from('KMS_WRAPPED:'),
        plaintextDek,
        Buffer.from(':SIG='),
        crypto.createHash('sha256').update(plaintextDek).update(kmsAad).digest().subarray(0, 8),
      ]);

      return {
        templateId,
        accountUid,
        vaultRecordVersion: 1,
        encryptionSchemaVersion: 'v3_kms_gcm',
        embeddingSpaceId: 'sface_opencv_zoo_v1_canonical112',
        lifecycleStatus: 'ACTIVE',
        wrappedDekBase64: wrappedDek.toString('base64'),
        ciphertextBase64: ciphertext.toString('base64'),
        ivBase64: iv.toString('base64'),
        authTagBase64: authTag.toString('base64'),
      };
    } finally {
      // Direct best-effort clearing of owned buffer in finally block
      plaintextDek.fill(0);
    }
  }

  /**
   * Safely unwraps and decrypts an encrypted vault template under strict pre-KMS boundary gates.
   */
  public decryptTemplate(req: DecryptionRequestV18): DecryptedTemplateResultV18 {
    const { record, callerSessionUid, callerContext } = req;

    // 1. Pre-KMS Gate: Caller Session Ownership Check (1:1 auth mode)
    if (callerContext === '1to1_auth' && record.accountUid !== callerSessionUid) {
      throw new Error(
        `UNAUTHORIZED_RECORD_ACCESS: Caller session '${callerSessionUid}' is not authorized to decrypt template belonging to '${record.accountUid}'.`
      );
    }

    // 2. Pre-KMS Gate: Template Lifecycle Fencing (Reject SUPERSEDED or REVOKED before KMS)
    if (record.lifecycleStatus !== 'ACTIVE') {
      throw new Error(
        `LIFECYCLE_GATE_REJECTED: Template '${record.templateId}' is in status '${record.lifecycleStatus}'. Decryption denied prior to KMS invocation.`
      );
    }

    // 3. Pre-KMS Gate: Embedding Space Validation
    if (record.embeddingSpaceId !== 'sface_opencv_zoo_v1_canonical112') {
      throw new Error(
        `EMBEDDING_SPACE_MISMATCH: Unsupported embedding space '${record.embeddingSpaceId}'. Expected 'sface_opencv_zoo_v1_canonical112'.`
      );
    }

    // 4. Construct trusted AAD from verified backend metadata (NEVER accept client-supplied AAD)
    const trustedTemplateAad = this.constructCanonicalBinaryAad({
      accountUid: record.accountUid,
      templateId: record.templateId,
      vaultRecordVersion: record.vaultRecordVersion,
      encryptionSchemaVersion: record.encryptionSchemaVersion,
      embeddingSpaceId: record.embeddingSpaceId,
      approvedContext: callerContext,
    });

    const trustedKmsAad = this.constructKmsWrappedDekAad('kelasagara', record.accountUid, record.templateId);

    // 5. Cloud KMS DEK Unwrap
    const wrappedDekBuffer = Buffer.from(record.wrappedDekBase64, 'base64');
    let plaintextDek: Buffer | null = null;
    let memoryCleared = false;

    try {
      if (req.mockKmsUnwrapFn) {
        plaintextDek = req.mockKmsUnwrapFn(wrappedDekBuffer, trustedKmsAad);
      } else {
        // Default unwrap validation
        const prefix = wrappedDekBuffer.toString('utf8', 0, 12);
        if (!prefix.startsWith('KMS_WRAPPED:')) {
          throw new Error('KMS_UNWRAP_FAILED: Invalid ciphertext format on wrapped DEK.');
        }

        // Validate simulated KMS AAD signature
        const rawDek = wrappedDekBuffer.subarray(12, 44);
        const sigPart = wrappedDekBuffer.subarray(49, 57);
        const expectedSig = crypto
          .createHash('sha256')
          .update(rawDek)
          .update(trustedKmsAad)
          .digest()
          .subarray(0, 8);

        if (!crypto.timingSafeEqual(sigPart, expectedSig)) {
          throw new Error('KMS_UNWRAP_FAILED: KMS Context AAD mismatch on wrapped DEK.');
        }

        plaintextDek = Buffer.alloc(rawDek.length);
        rawDek.copy(plaintextDek);
      }

      // 6. Decrypt ciphertext with AES-256-GCM
      const ciphertext = Buffer.from(record.ciphertextBase64, 'base64');
      const iv = Buffer.from(record.ivBase64, 'base64');
      const authTag = Buffer.from(record.authTagBase64, 'base64');

      const decipher = crypto.createDecipheriv('aes-256-gcm', plaintextDek, iv);
      decipher.setAAD(trustedTemplateAad);
      decipher.setAuthTag(authTag);

      let decryptedVectorBytes: Buffer;
      try {
        decryptedVectorBytes = Buffer.concat([decipher.update(ciphertext), decipher.final()]);
      } catch (err: any) {
        throw new Error(`AUTHENTICATION_TAG_VERIFICATION_FAILED: ${err.message}`);
      }

      // Convert decrypted bytes back to Float32Array
      const floatArray = new Float32Array(
        decryptedVectorBytes.buffer,
        decryptedVectorBytes.byteOffset,
        decryptedVectorBytes.byteLength / 4
      );

      return {
        templateId: record.templateId,
        accountUid: record.accountUid,
        embedding: floatArray,
        decryptionAuditId: `audit-decrypt-${crypto.randomBytes(8).toString('hex')}`,
        memoryCleared: true,
      };
    } finally {
      // Best-effort clearing of owned buffer in finally block
      if (plaintextDek) {
        plaintextDek.fill(0);
        memoryCleared = true;
      }
    }
  }
}
