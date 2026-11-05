/**
 * KELASAGARA V20.17: VAULT DECRYPTION GUARD & AAD LIFECYCLE ENGINE
 *
 * Implements cryptographic blast-radius containment, length-prefixed binary AAD construction,
 * record-level ownership gating, template lifecycle fencing, and DEK buffer hygiene.
 *
 * Key Invariants:
 * 1. Trusted Backend AAD Construction: AAD is NEVER accepted from the client. It is constructed
 *    exclusively by backend code from verified session claims and vault record metadata.
 * 2. Blast-Radius Containment: Prevents a compromised verifier from decrypting arbitrary records
 *    by requiring matching session identity, active lifecycle status, and embedding-space validation.
 * 3. Memory Hygiene: Plaintext DEKs are held in memory only for the duration of the template
 *    decryption call and immediately cleared with crypto.randomFillSync / buffer.fill(0).
 */

import * as crypto from 'crypto';

export interface TrustedAadComponents {
  accountUid: string;
  templateId: string;
  vaultRecordVersion: number;
  encryptionSchemaVersion: string; // e.g. 'v3_kms_gcm'
  embeddingSpaceId: string; // e.g. 'sface_opencv_zoo_v1_canonical112'
  approvedContext: '1to1_auth' | '1toN_dedup';
}

export interface EncryptedVaultRecord {
  templateId: string;
  accountUid: string;
  vaultRecordVersion: number;
  encryptionSchemaVersion: string;
  embeddingSpaceId: string;
  isActive: boolean;
  wrappedDekBase64: string;
  ciphertextBase64: string;
  ivBase64: string;
  authTagBase64: string;
}

export interface DecryptionRequest {
  record: EncryptedVaultRecord;
  callerSessionUid: string;
  callerContext: '1to1_auth' | '1toN_dedup';
  mockKmsUnwrapFn?: (wrappedDek: Buffer, aad: Buffer) => Buffer; // Local dev / test mock
}

export interface DecryptedTemplateResult {
  templateId: string;
  accountUid: string;
  embedding: Float32Array;
  decryptionAuditId: string;
}

export class VaultDecryptionGuard {
  /**
   * Constructs length-prefixed binary AAD adhering to ISO/IEC 19772 to prevent delimiter collision.
   */
  public constructCanonicalBinaryAad(components: TrustedAadComponents): Buffer {
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
      totalLength += 4 + f.length; // 4 bytes big-endian length prefix + field
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
   * Encrypts a raw 128-dim Float32Array template using simulated KMS envelope encryption.
   */
  public encryptTemplateSnapshot(
    accountUid: string,
    templateId: string,
    embedding: Float32Array,
    approvedContext: '1to1_auth' | '1toN_dedup' = '1to1_auth'
  ): EncryptedVaultRecord {
    const rawVectorBytes = Buffer.from(embedding.buffer, embedding.byteOffset, embedding.byteLength);

    // Generate random 256-bit DEK
    const plaintextDek = crypto.randomBytes(32);
    const iv = crypto.randomBytes(12);

    const aadComponents: TrustedAadComponents = {
      accountUid,
      templateId,
      vaultRecordVersion: 1,
      encryptionSchemaVersion: 'v3_kms_gcm',
      embeddingSpaceId: 'sface_opencv_zoo_v1_canonical112',
      approvedContext,
    };
    const aad = this.constructCanonicalBinaryAad(aadComponents);

    const cipher = crypto.createCipheriv('aes-256-gcm', plaintextDek, iv);
    cipher.setAAD(aad);
    const ciphertext = Buffer.concat([cipher.update(rawVectorBytes), cipher.final()]);
    const authTag = cipher.getAuthTag();

    // Mock wrapping of DEK (in real cloud, wrapped via KMS encrypt)
    const wrappedDek = Buffer.concat([Buffer.from('KMS_WRAPPED:'), plaintextDek]);

    // Memory hygiene: wipe plaintext DEK
    plaintextDek.fill(0);

    return {
      templateId,
      accountUid,
      vaultRecordVersion: 1,
      encryptionSchemaVersion: 'v3_kms_gcm',
      embeddingSpaceId: 'sface_opencv_zoo_v1_canonical112',
      isActive: true,
      wrappedDekBase64: wrappedDek.toString('base64'),
      ciphertextBase64: ciphertext.toString('base64'),
      ivBase64: iv.toString('base64'),
      authTagBase64: authTag.toString('base64'),
    };
  }

  /**
   * Safely unwraps and decrypts an encrypted vault template under strict boundary gates.
   */
  public decryptTemplate(req: DecryptionRequest): DecryptedTemplateResult {
    const { record, callerSessionUid, callerContext } = req;

    // 1. Record-Level Ownership Gate (in 1:1 auth, caller MUST match record owner)
    if (callerContext === '1to1_auth' && record.accountUid !== callerSessionUid) {
      throw new Error(
        `UNAUTHORIZED_RECORD_ACCESS: Caller session '${callerSessionUid}' is not authorized to decrypt template belonging to '${record.accountUid}'.`
      );
    }

    // 2. Lifecycle Gate: Reject superseded or inactive templates
    if (!record.isActive) {
      throw new Error(
        `SUPERSEDED_TEMPLATE_REJECTED: Template '${record.templateId}' is marked inactive/superseded. Decryption denied.`
      );
    }

    // 3. Schema & Embedding-Space Verification
    if (record.embeddingSpaceId !== 'sface_opencv_zoo_v1_canonical112') {
      throw new Error(
        `EMBEDDING_SPACE_MISMATCH: Unsupported embedding space '${record.embeddingSpaceId}'. Expected 'sface_opencv_zoo_v1_canonical112'.`
      );
    }

    // 4. Construct trusted AAD from backend record metadata
    const trustedAad = this.constructCanonicalBinaryAad({
      accountUid: record.accountUid,
      templateId: record.templateId,
      vaultRecordVersion: record.vaultRecordVersion,
      encryptionSchemaVersion: record.encryptionSchemaVersion,
      embeddingSpaceId: record.embeddingSpaceId,
      approvedContext: callerContext,
    });

    // 5. Cloud KMS DEK Unwrap (simulated / mocked in test environment)
    const wrappedDekBuffer = Buffer.from(record.wrappedDekBase64, 'base64');
    let plaintextDek: Buffer;

    if (req.mockKmsUnwrapFn) {
      plaintextDek = req.mockKmsUnwrapFn(wrappedDekBuffer, trustedAad);
    } else {
      // Default unwrap simulation: strip 'KMS_WRAPPED:' prefix
      if (!wrappedDekBuffer.toString('utf8', 0, 12).startsWith('KMS_WRAPPED:')) {
        throw new Error('KMS_UNWRAP_FAILED: Invalid ciphertext format on wrapped DEK.');
      }
      plaintextDek = Buffer.from(wrappedDekBuffer.subarray(12));
    }

    // 6. Decrypt ciphertext with AES-256-GCM
    const ciphertext = Buffer.from(record.ciphertextBase64, 'base64');
    const iv = Buffer.from(record.ivBase64, 'base64');
    const authTag = Buffer.from(record.authTagBase64, 'base64');

    let decryptedVectorBytes: Buffer;
    try {
      const decipher = crypto.createDecipheriv('aes-256-gcm', plaintextDek, iv);
      decipher.setAAD(trustedAad);
      decipher.setAuthTag(authTag);
      decryptedVectorBytes = Buffer.concat([decipher.update(ciphertext), decipher.final()]);
    } catch (err: any) {
      // Memory hygiene: wipe DEK on error before throwing
      plaintextDek.fill(0);
      throw new Error(`AUTHENTICATION_TAG_VERIFICATION_FAILED: ${err.message}`);
    }

    // Memory hygiene: wipe plaintext DEK immediately after decipher.final()
    crypto.randomFillSync(plaintextDek);
    plaintextDek.fill(0);

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
    };
  }
}
