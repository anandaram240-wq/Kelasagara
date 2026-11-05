// backend/src/services/template_privacy.ts
/**
 * Track D / Stage S8: Template Privacy, Canonical AAD Binding & Cloud KMS Envelope Encryption.
 * Enforces Invariants INV-01 (Envelope Integrity), INV-02 (Context Binding), INV-03 (No Plaintext Key Persistence),
 * INV-04 (Strict Version Selection), and ISO/IEC 24745 biometric template protection standards.
 *
 * Implements:
 * 1. Length-prefixed binary canonical Additional Authenticated Data (AAD) eliminating delimiter collision risks (GAP-03).
 * 2. Cloud KMS envelope encryption architecture with wrapped Data Encryption Keys (DEKs) (GAP-02 / WP S8-C).
 * 3. Backward-compatible migration support for legacy v1 and v2 envelopes with explicit downgrade protection.
 * 4. Inversion resistance and confidentiality via AES-256-GCM authenticated cipher.
 */

import crypto from "crypto";
import { KeyProvider, LocalDevKeyProvider, WrappedDekResult } from "./kms_key_provider";

export type EnvelopeVersion = "v1_legacy" | "v2_aad_gcm" | "v3_kms_gcm";

export interface EncryptedTemplateEnvelope {
  envelopeVersion: EnvelopeVersion;
  keyVersion?: string;
  kmsKeyResourceName?: string;
  wrappedDekHex?: string;
  uid: string;
  tenantId: string;
  templatePurpose?: string;
  ciphertextHex: string;
  ivHex: string;
  authTagHex: string;
  keyDerivationSaltHex?: string; // required for v1/v2 legacy derivation
  rotated: boolean;
  encryptedAt: string;
  schemaVersion?: number;
}

export class TemplatePrivacyService {
  public static readonly AAD_DOMAIN_HEADER = "BIOMATCH_AAD_V1";
  public static readonly DEFAULT_TEMPLATE_PURPOSE = "BIOMETRIC_AUTH_V1";

  // Field Tags for Canonical Length-Prefixed Binary AAD
  public static readonly TAG_ENVELOPE_VERSION = 0x01;
  public static readonly TAG_TENANT_ID = 0x02;
  public static readonly TAG_UID = 0x03;
  public static readonly TAG_KEY_VERSION = 0x04;
  public static readonly TAG_PURPOSE = 0x05;

  private static defaultKeyProvider: KeyProvider = new LocalDevKeyProvider();

  /**
   * Sets the process-wide default KeyProvider (e.g. CloudKmsKeyProvider in production).
   */
  static setDefaultKeyProvider(provider: KeyProvider): void {
    this.defaultKeyProvider = provider;
  }

  static getDefaultKeyProvider(): KeyProvider {
    return this.defaultKeyProvider;
  }

  /**
   * Constructs canonical Additional Authenticated Data (AAD) using length-prefixed binary encoding.
   * Completely eliminates delimiter injection / field shifting vulnerabilities (GAP-03 remediation).
   *
   * Wire Format:
   * [Header: "BIOMATCH_AAD_V1" (15 bytes)]
   * [Field Count: UInt8 (1 byte)]
   * Repeat for each field:
   *   [Tag: UInt8 (1 byte)]
   *   [Length: UInt16BE (2 bytes)]
   *   [Value: UTF-8 Bytes (N bytes)]
   */
  static buildCanonicalAAD(params: {
    envelopeVersion: string;
    tenantId: string;
    uid: string;
    keyVersion: string;
    templatePurpose?: string;
  }): Buffer {
    const purpose = params.templatePurpose || this.DEFAULT_TEMPLATE_PURPOSE;
    const headerBuf = Buffer.from(this.AAD_DOMAIN_HEADER, "utf8");

    const fields: Array<{ tag: number; val: Buffer }> = [
      { tag: this.TAG_ENVELOPE_VERSION, val: Buffer.from(params.envelopeVersion, "utf8") },
      { tag: this.TAG_TENANT_ID, val: Buffer.from(params.tenantId, "utf8") },
      { tag: this.TAG_UID, val: Buffer.from(params.uid, "utf8") },
      { tag: this.TAG_KEY_VERSION, val: Buffer.from(params.keyVersion, "utf8") },
      { tag: this.TAG_PURPOSE, val: Buffer.from(purpose, "utf8") },
    ];

    // Calculate total buffer size
    let totalSize = headerBuf.length + 1; // header + field count byte
    for (const f of fields) {
      if (f.val.length > 65535) {
        throw new Error(`[TemplatePrivacy] Field length exceeds 65535 bytes (tag: ${f.tag})`);
      }
      totalSize += 1 + 2 + f.val.length; // 1 byte tag + 2 bytes length + value bytes
    }

    const aadBuf = Buffer.alloc(totalSize);
    let offset = 0;

    headerBuf.copy(aadBuf, offset);
    offset += headerBuf.length;

    aadBuf.writeUInt8(fields.length, offset);
    offset += 1;

    for (const f of fields) {
      aadBuf.writeUInt8(f.tag, offset);
      offset += 1;
      aadBuf.writeUInt16BE(f.val.length, offset);
      offset += 2;
      f.val.copy(aadBuf, offset);
      offset += f.val.length;
    }

    return aadBuf;
  }

  /**
   * Legacy pipe-delimited AAD builder for backward compatibility when reading v2 records.
   * Format: `${envelopeVersion}|${tenantId}|${uid}|${keyVersion}`
   */
  static buildLegacyAAD(
    envelopeVersion: string,
    tenantId: string,
    uid: string,
    keyVersion: string
  ): Buffer {
    return Buffer.from(`${envelopeVersion}|${tenantId}|${uid}|${keyVersion}`, "utf8");
  }

  /**
   * Helper alias for legacy tests: forwards to buildLegacyAAD.
   */
  static buildAAD(
    envelopeVersion: string,
    tenantId: string,
    uid: string,
    keyVersion: string
  ): Buffer {
    return this.buildLegacyAAD(envelopeVersion, tenantId, uid, keyVersion);
  }

  /**
   * Generates a deterministic d x d orthogonal matrix R from a tenant secret.
   * Uses Gram-Schmidt orthonormalization to ensure R^T * R = I.
   * Preserves inner products: <R*u, R*v> = <u, v>.
   * Reclassified as a non-cryptographic transform; AES-256-GCM is authoritative confidentiality.
   */
  static generateOrthogonalMatrix(tenantSecret: string, dim = 128): number[][] {
    const seed = crypto.createHash("sha256").update(tenantSecret).digest();
    const cipher = crypto.createCipheriv("aes-256-ctr", seed, Buffer.alloc(16, 0));

    const randomFloats: number[] = [];
    const bufSize = dim * dim * 4;
    const stream = cipher.update(Buffer.alloc(bufSize));

    for (let i = 0; i < dim * dim; i++) {
      const intVal = stream.readInt32LE(i * 4);
      randomFloats.push(intVal / 2147483648.0);
    }

    const basis: number[][] = [];
    for (let r = 0; r < dim; r++) {
      basis.push(randomFloats.slice(r * dim, (r + 1) * dim));
    }

    const ortho: number[][] = [];
    for (let i = 0; i < dim; i++) {
      let v = [...basis[i]];
      for (let j = 0; j < i; j++) {
        let dot = 0;
        for (let d = 0; d < dim; d++) dot += basis[i][d] * ortho[j][d];
        for (let d = 0; d < dim; d++) v[d] -= dot * ortho[j][d];
      }
      let normSq = 0;
      for (let d = 0; d < dim; d++) normSq += v[d] * v[d];
      const norm = Math.max(1e-12, Math.sqrt(normSq));
      ortho.push(v.map((x) => x / norm));
    }

    return ortho;
  }

  /**
   * Applies orthogonal rotation: y = R * x.
   */
  static rotateEmbedding(embedding: number[], orthoMatrix: number[][]): number[] {
    const dim = embedding.length;
    const rotated = new Array(dim).fill(0);
    for (let r = 0; r < dim; r++) {
      let sum = 0;
      for (let c = 0; c < dim; c++) {
        sum += orthoMatrix[r][c] * embedding[c];
      }
      rotated[r] = sum;
    }
    return rotated;
  }

  /**
   * Envelope encryption: Encrypts embedding using AES-256-GCM.
   * Supports:
   * - 'v3_kms_gcm' (Default): Generates a fresh 256-bit DEK, binds canonical binary AAD, wraps DEK via KeyProvider.
   * - 'v2_aad_gcm' (Legacy): Uses masterKeySecret and PBKDF2 derivation with pipe-delimited AAD.
   */
  static encryptTemplate(
    uid: string,
    tenantId: string,
    embedding: number[],
    masterKeySecret?: string,
    orthoMatrix?: number[][],
    keyVersion = "k1",
    envelopeVersion: EnvelopeVersion = "v2_aad_gcm",
    keyProvider?: KeyProvider,
    templatePurpose = "BIOMETRIC_AUTH_V1"
  ): EncryptedTemplateEnvelope {
    const vectorToEncrypt = orthoMatrix
      ? this.rotateEmbedding(embedding, orthoMatrix)
      : embedding;

    // Validate vector values are finite numbers
    for (let i = 0; i < vectorToEncrypt.length; i++) {
      if (!Number.isFinite(vectorToEncrypt[i])) {
        throw new Error(`[TemplatePrivacy] Non-finite embedding value at index ${i}`);
      }
    }

    const dataBuffer = Buffer.from(new Float32Array(vectorToEncrypt).buffer);
    const iv = crypto.randomBytes(12); // 96 bits

    if (envelopeVersion === "v3_kms_gcm") {
      const provider = keyProvider || this.defaultKeyProvider;
      // 1. Generate fresh 256-bit DEK
      const dek = crypto.randomBytes(32);

      // 2. Build canonical length-prefixed binary AAD
      const aad = this.buildCanonicalAAD({
        envelopeVersion,
        tenantId,
        uid,
        keyVersion,
        templatePurpose,
      });

      // 3. Encrypt data with DEK and canonical AAD
      const cipher = crypto.createCipheriv("aes-256-gcm", dek, iv);
      cipher.setAAD(aad);
      const ciphertext = Buffer.concat([cipher.update(dataBuffer), cipher.final()]);
      const authTag = cipher.getAuthTag();

      // 4. Wrap DEK via KeyProvider bound to exact AAD context (synchronous or wrapped async)
      // Note: wrapDek is async in the provider interface; we handle the local wrapping
      const wrappedRes: WrappedDekResult = {
        wrappedDek: Buffer.alloc(60),
        kmsKeyResourceName: provider.defaultKeyResourceName,
        keyVersion,
      };

      // Wrap synchronously using provider logic for seamless caller API
      if (provider instanceof LocalDevKeyProvider) {
        // Fast synchronous path for LocalDevKeyProvider
        const kek = (provider as any).kek;
        const wrapIv = crypto.randomBytes(12);
        const wrapCipher = crypto.createCipheriv("aes-256-gcm", kek, wrapIv);
        wrapCipher.setAAD(aad);
        const wrappedCiphertext = Buffer.concat([wrapCipher.update(dek), wrapCipher.final()]);
        const wrapAuthTag = wrapCipher.getAuthTag();
        wrappedRes.wrappedDek = Buffer.concat([wrapIv, wrapAuthTag, wrappedCiphertext]);
      } else {
        throw new Error("[TemplatePrivacy] Cloud KMS encryption requires async encryptTemplateAsync().");
      }

      // 5. Zeroize plaintext DEK buffer
      dek.fill(0);

      return {
        envelopeVersion: "v3_kms_gcm",
        keyVersion,
        kmsKeyResourceName: wrappedRes.kmsKeyResourceName,
        wrappedDekHex: wrappedRes.wrappedDek.toString("hex"),
        uid,
        tenantId,
        templatePurpose,
        ciphertextHex: ciphertext.toString("hex"),
        ivHex: iv.toString("hex"),
        authTagHex: authTag.toString("hex"),
        rotated: orthoMatrix !== undefined,
        encryptedAt: new Date().toISOString(),
        schemaVersion: 3,
      };
    }

    // ── Legacy v2 / v1 Paths (Using PBKDF2 Master Key) ─────────────────────
    if (!masterKeySecret) {
      throw new Error("[TemplatePrivacy] masterKeySecret is required for legacy envelope versions (v1, v2).");
    }

    const salt = crypto.randomBytes(16);
    const userKey = crypto.pbkdf2Sync(masterKeySecret, salt, 10000, 32, "sha256");

    const cipher = crypto.createCipheriv("aes-256-gcm", userKey, iv);
    if (envelopeVersion === "v2_aad_gcm") {
      const aad = this.buildLegacyAAD(envelopeVersion, tenantId, uid, keyVersion);
      cipher.setAAD(aad);
    }

    const ciphertext = Buffer.concat([cipher.update(dataBuffer), cipher.final()]);
    const authTag = cipher.getAuthTag();

    return {
      envelopeVersion,
      keyVersion,
      uid,
      tenantId,
      ciphertextHex: ciphertext.toString("hex"),
      ivHex: iv.toString("hex"),
      authTagHex: authTag.toString("hex"),
      keyDerivationSaltHex: salt.toString("hex"),
      rotated: orthoMatrix !== undefined,
      encryptedAt: new Date().toISOString(),
      schemaVersion: envelopeVersion === "v2_aad_gcm" ? 2 : 1,
    };
  }

  /**
   * Async envelope encryption: Used for Cloud KMS and async KeyProviders.
   */
  static async encryptTemplateAsync(
    uid: string,
    tenantId: string,
    embedding: number[],
    keyProvider?: KeyProvider,
    orthoMatrix?: number[][],
    keyVersion = "k1",
    templatePurpose = "BIOMETRIC_AUTH_V1"
  ): Promise<EncryptedTemplateEnvelope> {
    const provider = keyProvider || this.defaultKeyProvider;
    const vectorToEncrypt = orthoMatrix ? this.rotateEmbedding(embedding, orthoMatrix) : embedding;

    for (let i = 0; i < vectorToEncrypt.length; i++) {
      if (!Number.isFinite(vectorToEncrypt[i])) {
        throw new Error(`[TemplatePrivacy] Non-finite embedding value at index ${i}`);
      }
    }

    const dataBuffer = Buffer.from(new Float32Array(vectorToEncrypt).buffer);
    const iv = crypto.randomBytes(12);
    const dek = crypto.randomBytes(32);

    const aad = this.buildCanonicalAAD({
      envelopeVersion: "v3_kms_gcm",
      tenantId,
      uid,
      keyVersion,
      templatePurpose,
    });

    const cipher = crypto.createCipheriv("aes-256-gcm", dek, iv);
    cipher.setAAD(aad);
    const ciphertext = Buffer.concat([cipher.update(dataBuffer), cipher.final()]);
    const authTag = cipher.getAuthTag();

    const wrappedRes = await provider.wrapDek(dek, aad);
    dek.fill(0); // Zeroize plaintext DEK

    return {
      envelopeVersion: "v3_kms_gcm",
      keyVersion,
      kmsKeyResourceName: wrappedRes.kmsKeyResourceName,
      wrappedDekHex: wrappedRes.wrappedDek.toString("hex"),
      uid,
      tenantId,
      templatePurpose,
      ciphertextHex: ciphertext.toString("hex"),
      ivHex: iv.toString("hex"),
      authTagHex: authTag.toString("hex"),
      rotated: orthoMatrix !== undefined,
      encryptedAt: new Date().toISOString(),
      schemaVersion: 3,
    };
  }

  /**
   * Envelope decryption: Supports v3 (KMS/LocalDevKeyProvider), v2 (AAD GCM), and v1 (legacy).
   * Enforces downgrade protection if minEnvelopeVersion is set.
   */
  static decryptTemplate(
    envelope: EncryptedTemplateEnvelope,
    masterKeySecret?: string,
    orthoMatrix?: number[][],
    strictV2OrHigher = false,
    keyProvider?: KeyProvider,
    minEnvelopeVersion?: EnvelopeVersion
  ): number[] {
    const envelopeVersion = envelope.envelopeVersion || "v1_legacy";

    // Strict Downgrade Protection (INV-04)
    if (minEnvelopeVersion) {
      const versionRanks: Record<EnvelopeVersion, number> = {
        v1_legacy: 1,
        v2_aad_gcm: 2,
        v3_kms_gcm: 3,
      };
      if (versionRanks[envelopeVersion] < versionRanks[minEnvelopeVersion]) {
        throw new Error(
          `ENVELOPE_DOWNGRADE_REJECTED: Received '${envelopeVersion}' but minimum required version is '${minEnvelopeVersion}' (INV-04).`
        );
      }
    }

    if (strictV2OrHigher && envelopeVersion === "v1_legacy") {
      throw new Error(`ENVELOPE_DOWNGRADE_REJECTED: Legacy envelope format '${envelopeVersion}' is prohibited in strict v2+ mode.`);
    }

    // Parameter and length validation
    if (!envelope.ivHex || envelope.ivHex.length !== 24) {
      throw new Error("INVALID_IV_LENGTH: AES-GCM IV must be exactly 96 bits (24 hex characters).");
    }
    if (!envelope.authTagHex || envelope.authTagHex.length !== 32) {
      throw new Error("INVALID_AUTH_TAG_LENGTH: AES-GCM authentication tag must be exactly 128 bits (32 hex characters).");
    }
    if (!envelope.ciphertextHex || envelope.ciphertextHex.length === 0 || envelope.ciphertextHex.length % 8 !== 0) {
      throw new Error("INVALID_CIPHERTEXT: Ciphertext length must be a non-empty multiple of 4 bytes (8 hex characters).");
    }

    const iv = Buffer.from(envelope.ivHex, "hex");
    const authTag = Buffer.from(envelope.authTagHex, "hex");
    const ciphertext = Buffer.from(envelope.ciphertextHex, "hex");

    let decryptedBuf: Buffer;

    // ── Branch A: v3_kms_gcm Decryption ────────────────────────────────────
    if (envelopeVersion === "v3_kms_gcm") {
      if (!envelope.wrappedDekHex || envelope.wrappedDekHex.length === 0) {
        throw new Error("INVALID_ENVELOPE: v3_kms_gcm envelope missing wrappedDekHex.");
      }

      const provider = keyProvider || this.defaultKeyProvider;
      const keyVersion = envelope.keyVersion || "k1";
      const aad = this.buildCanonicalAAD({
        envelopeVersion: "v3_kms_gcm",
        tenantId: envelope.tenantId,
        uid: envelope.uid,
        keyVersion,
        templatePurpose: envelope.templatePurpose,
      });

      const wrappedDek = Buffer.from(envelope.wrappedDekHex, "hex");
      let dek: Buffer;

      if (provider instanceof LocalDevKeyProvider) {
        // Fast synchronous unwrap for LocalDevKeyProvider
        const kek = (provider as any).kek;
        if (wrappedDek.length !== 60) {
          throw new Error(`[TemplatePrivacy] Invalid wrapped DEK length: ${wrappedDek.length}`);
        }
        const wrapIv = wrappedDek.subarray(0, 12);
        const wrapAuthTag = wrappedDek.subarray(12, 28);
        const wrapCiphertext = wrappedDek.subarray(28);

        const wrapDecipher = crypto.createDecipheriv("aes-256-gcm", kek, wrapIv);
        wrapDecipher.setAuthTag(wrapAuthTag);
        wrapDecipher.setAAD(aad);
        try {
          dek = Buffer.concat([wrapDecipher.update(wrapCiphertext), wrapDecipher.final()]);
        } catch (wrapErr: any) {
          throw new Error(`AUTHENTICATION_TAG_VERIFICATION_FAILED: DEK unwrap failed (${wrapErr.message})`);
        }
      } else {
        throw new Error("[TemplatePrivacy] Cloud KMS decryption requires async decryptTemplateAsync().");
      }

      const decipher = crypto.createDecipheriv("aes-256-gcm", dek, iv);
      decipher.setAuthTag(authTag);
      decipher.setAAD(aad);

      try {
        decryptedBuf = Buffer.concat([decipher.update(ciphertext), decipher.final()]);
      } catch (err: any) {
        throw new Error(`AUTHENTICATION_TAG_VERIFICATION_FAILED: ${err.message}`);
      } finally {
        dek.fill(0); // Zeroize plaintext DEK buffer immediately
      }
    } else {
      // ── Branch B: Legacy v2 / v1 Decryption ───────────────────────────────
      if (!masterKeySecret) {
        throw new Error("[TemplatePrivacy] masterKeySecret is required for legacy envelope decryption.");
      }
      if (!envelope.keyDerivationSaltHex || envelope.keyDerivationSaltHex.length !== 32) {
        throw new Error("INVALID_SALT_LENGTH: Key derivation salt must be exactly 128 bits (32 hex characters).");
      }

      const salt = Buffer.from(envelope.keyDerivationSaltHex, "hex");
      const userKey = crypto.pbkdf2Sync(masterKeySecret, salt, 10000, 32, "sha256");

      const decipher = crypto.createDecipheriv("aes-256-gcm", userKey, iv);
      decipher.setAuthTag(authTag);

      if (envelopeVersion === "v2_aad_gcm") {
        const keyVersion = envelope.keyVersion || "k1";
        const aad = this.buildLegacyAAD(envelopeVersion, envelope.tenantId, envelope.uid, keyVersion);
        decipher.setAAD(aad);
      }

      try {
        decryptedBuf = Buffer.concat([decipher.update(ciphertext), decipher.final()]);
      } catch (err: any) {
        throw new Error(`AUTHENTICATION_TAG_VERIFICATION_FAILED: ${err.message}`);
      }
    }

    const float32Array = new Float32Array(
      decryptedBuf.buffer,
      decryptedBuf.byteOffset,
      decryptedBuf.byteLength / 4
    );
    const rawVector = Array.from(float32Array);

    if (envelope.rotated && orthoMatrix) {
      const dim = rawVector.length;
      const unrotated = new Array(dim).fill(0);
      for (let r = 0; r < dim; r++) {
        let sum = 0;
        for (let c = 0; c < dim; c++) {
          sum += orthoMatrix[c][r] * rawVector[c]; // R^T
        }
        unrotated[r] = sum;
      }
      return unrotated;
    }

    return rawVector;
  }

  /**
   * Async envelope decryption: Used for Cloud KMS and async KeyProviders.
   */
  static async decryptTemplateAsync(
    envelope: EncryptedTemplateEnvelope,
    keyProvider?: KeyProvider,
    orthoMatrix?: number[][],
    minEnvelopeVersion?: EnvelopeVersion,
    masterKeySecret?: string
  ): Promise<number[]> {
    const envelopeVersion = envelope.envelopeVersion || "v1_legacy";
    if (minEnvelopeVersion) {
      const versionRanks: Record<EnvelopeVersion, number> = {
        v1_legacy: 1,
        v2_aad_gcm: 2,
        v3_kms_gcm: 3,
      };
      if (versionRanks[envelopeVersion] < versionRanks[minEnvelopeVersion]) {
        throw new Error(
          `ENVELOPE_DOWNGRADE_REJECTED: Received '${envelopeVersion}' but minimum required version is '${minEnvelopeVersion}' (INV-04).`
        );
      }
    }

    if (envelopeVersion === "v3_kms_gcm") {
      const provider = keyProvider || this.defaultKeyProvider;
      const keyVersion = envelope.keyVersion || "k1";
      const aad = this.buildCanonicalAAD({
        envelopeVersion: "v3_kms_gcm",
        tenantId: envelope.tenantId,
        uid: envelope.uid,
        keyVersion,
        templatePurpose: envelope.templatePurpose,
      });

      const wrappedDek = Buffer.from(envelope.wrappedDekHex!, "hex");
      const dek = await provider.unwrapDek(wrappedDek, aad, envelope.kmsKeyResourceName);

      const iv = Buffer.from(envelope.ivHex, "hex");
      const authTag = Buffer.from(envelope.authTagHex, "hex");
      const ciphertext = Buffer.from(envelope.ciphertextHex, "hex");

      const decipher = crypto.createDecipheriv("aes-256-gcm", dek, iv);
      decipher.setAuthTag(authTag);
      decipher.setAAD(aad);

      let decryptedBuf: Buffer;
      try {
        decryptedBuf = Buffer.concat([decipher.update(ciphertext), decipher.final()]);
      } catch (err: any) {
        throw new Error(`AUTHENTICATION_TAG_VERIFICATION_FAILED: ${err.message}`);
      } finally {
        dek.fill(0);
      }

      const float32Array = new Float32Array(
        decryptedBuf.buffer,
        decryptedBuf.byteOffset,
        decryptedBuf.byteLength / 4
      );
      const rawVector = Array.from(float32Array);
      if (envelope.rotated && orthoMatrix) {
        const dim = rawVector.length;
        const unrotated = new Array(dim).fill(0);
        for (let r = 0; r < dim; r++) {
          let sum = 0;
          for (let c = 0; c < dim; c++) {
            sum += orthoMatrix[c][r] * rawVector[c];
          }
          unrotated[r] = sum;
        }
        return unrotated;
      }
      return rawVector;
    }

    // Fall back to synchronous path for legacy formats
    return this.decryptTemplate(envelope, masterKeySecret, orthoMatrix, false, keyProvider, minEnvelopeVersion);
  }
}
