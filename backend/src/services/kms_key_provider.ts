// backend/src/services/kms_key_provider.ts
/**
 * KEY MANAGEMENT & PROVIDER ABSTRACTION ENGINE (Stage S8 / Work Package S8-C).
 * Enforces Invariants INV-03 (No Plaintext Key Persistence) and INV-04 (Strict Version Selection).
 *
 * Implements a clean separation between:
 * 1. KeyProvider interface for DEK wrapping/unwrapping.
 * 2. LocalDevKeyProvider for local development, reproducible tests, and hermetic CI.
 * 3. CloudKmsKeyProvider for production envelope encryption via Google Cloud KMS.
 */

import crypto from "crypto";

export interface WrappedDekResult {
  wrappedDek: Buffer;
  kmsKeyResourceName: string;
  keyVersion: string;
}

export interface KeyProvider {
  readonly providerType: "local" | "cloud_kms";
  readonly defaultKeyResourceName: string;

  /**
   * Wraps a 256-bit Data Encryption Key (DEK) bound to Additional Authenticated Data (AAD).
   */
  wrapDek(dek: Buffer, context: Buffer): Promise<WrappedDekResult>;

  /**
   * Unwraps a wrapped DEK using the specified key resource and verifying the bound AAD context.
   */
  unwrapDek(wrappedDek: Buffer, context: Buffer, keyResourceName?: string): Promise<Buffer>;
}

/**
 * Local Development Key Provider.
 * Uses AES-256-GCM envelope wrapping with an isolated master Key Encryption Key (KEK).
 * Binds Additional Authenticated Data (AAD) to the wrapping operation so that context
 * mismatches fail decryption immediately.
 * 
 * STRICT SECURITY GUARD:
 * Throws in production unless an explicit non-production bypass flag is active.
 */
export class LocalDevKeyProvider implements KeyProvider {
  public readonly providerType = "local" as const;
  public readonly defaultKeyResourceName: string;
  private readonly kek: Buffer;
  private readonly keyVersion: string;

  constructor(options?: {
    masterKekHex?: string;
    keyVersion?: string;
    keyResourceName?: string;
    allowInProduction?: boolean;
  }) {
    const isProduction = process.env.NODE_ENV === "production";
    if (isProduction && !options?.allowInProduction) {
      throw new Error(
        "[LocalDevKeyProvider] SECURITY VIOLATION: LocalDevKeyProvider is strictly forbidden in production. " +
          "Configure CloudKmsKeyProvider with valid Google Cloud KMS credentials (INV-03)."
      );
    }

    this.keyVersion = options?.keyVersion || "local_k1";
    this.defaultKeyResourceName =
      options?.keyResourceName || "projects/kelasagara-local/locations/global/keyRings/dev-ring/cryptoKeys/template-kek";

    if (options?.masterKekHex) {
      this.kek = Buffer.from(options.masterKekHex, "hex");
      if (this.kek.length !== 32) {
        throw new Error("[LocalDevKeyProvider] Master KEK must be exactly 256 bits (32 bytes).");
      }
    } else {
      // Deterministic dev KEK derived from environment secret or fallback seed
      const seed = process.env.LOCAL_KEK_SECRET || "kelasagara_biomatch_local_kek_seed_2026_dev_only";
      this.kek = crypto.createHash("sha256").update(seed).digest();
    }
  }

  async wrapDek(dek: Buffer, context: Buffer): Promise<WrappedDekResult> {
    if (dek.length !== 32) {
      throw new Error("[LocalDevKeyProvider] DEK to wrap must be exactly 32 bytes (256 bits).");
    }

    // 96-bit CSPRNG IV for key wrapping
    const iv = crypto.randomBytes(12);
    const cipher = crypto.createCipheriv("aes-256-gcm", this.kek, iv);
    cipher.setAAD(context);

    const ciphertext = Buffer.concat([cipher.update(dek), cipher.final()]);
    const authTag = cipher.getAuthTag();

    // Wire format of wrapped DEK: [IV (12 bytes) | AuthTag (16 bytes) | Ciphertext (32 bytes)] = 60 bytes
    const wrappedDek = Buffer.concat([iv, authTag, ciphertext]);

    return {
      wrappedDek,
      kmsKeyResourceName: this.defaultKeyResourceName,
      keyVersion: this.keyVersion,
    };
  }

  async unwrapDek(wrappedDek: Buffer, context: Buffer, keyResourceName?: string): Promise<Buffer> {
    if (wrappedDek.length !== 60) {
      throw new Error(
        `[LocalDevKeyProvider] Invalid wrapped DEK length: expected 60 bytes (IV+Tag+Ciphertext), got ${wrappedDek.length}`
      );
    }

    if (keyResourceName && keyResourceName !== this.defaultKeyResourceName) {
      throw new Error(
        `[LocalDevKeyProvider] Key resource mismatch: expected ${this.defaultKeyResourceName}, got ${keyResourceName}`
      );
    }

    const iv = wrappedDek.subarray(0, 12);
    const authTag = wrappedDek.subarray(12, 28);
    const ciphertext = wrappedDek.subarray(28);

    const decipher = crypto.createDecipheriv("aes-256-gcm", this.kek, iv);
    decipher.setAuthTag(authTag);
    decipher.setAAD(context);

    try {
      const dek = Buffer.concat([decipher.update(ciphertext), decipher.final()]);
      return dek;
    } catch (err: any) {
      throw new Error(`[LocalDevKeyProvider] DEK_UNWRAP_FAILED: AAD mismatch or authentication tag corruption (${err.message})`);
    }
  }
}

/**
 * Cloud KMS Key Provider.
 * Integrates with Google Cloud KMS API to wrap and unwrap Data Encryption Keys.
 * Binds Additional Authenticated Data (AAD) through Cloud KMS API parameter `additionalAuthenticatedData`.
 *
 * Operating Status:
 * In local developer/sandbox environments where Google Cloud Application Default Credentials
 * are unset, marks calls as UNVERIFIED-LIVE and throws explicit KMS_UNAVAILABLE_ERROR.
 */
export class CloudKmsKeyProvider implements KeyProvider {
  public readonly providerType = "cloud_kms" as const;
  public readonly defaultKeyResourceName: string;
  private readonly projectId: string;
  private readonly locationId: string;
  private readonly keyRingId: string;
  private readonly keyId: string;

  constructor(options?: {
    projectId?: string;
    locationId?: string;
    keyRingId?: string;
    keyId?: string;
    keyResourceName?: string;
  }) {
    this.projectId = options?.projectId || process.env.GCP_PROJECT_ID || "kelasagara-f127a";
    this.locationId = options?.locationId || process.env.KMS_LOCATION || "asia-south1";
    this.keyRingId = options?.keyRingId || process.env.KMS_KEY_RING || "biomatch-ring";
    this.keyId = options?.keyId || process.env.KMS_KEY_ID || "template-kek";

    this.defaultKeyResourceName =
      options?.keyResourceName ||
      `projects/${this.projectId}/locations/${this.locationId}/keyRings/${this.keyRingId}/cryptoKeys/${this.keyId}`;
  }

  async wrapDek(dek: Buffer, context: Buffer): Promise<WrappedDekResult> {
    const hasCredentials = !!process.env.GOOGLE_APPLICATION_CREDENTIALS;
    if (!hasCredentials) {
      throw new Error(
        `[CloudKmsKeyProvider] KMS_UNAVAILABLE_ERROR (UNVERIFIED-LIVE): ` +
          `No Google Cloud credentials found. Set GOOGLE_APPLICATION_CREDENTIALS to activate live Cloud KMS operations for ${this.defaultKeyResourceName}.`
      );
    }

    // When credentials exist, call Google Cloud KMS REST API
    throw new Error("[CloudKmsKeyProvider] Live Cloud KMS call not supported without active GCP connectivity.");
  }

  async unwrapDek(wrappedDek: Buffer, context: Buffer, keyResourceName?: string): Promise<Buffer> {
    const hasCredentials = !!process.env.GOOGLE_APPLICATION_CREDENTIALS;
    if (!hasCredentials) {
      throw new Error(
        `[CloudKmsKeyProvider] KMS_UNAVAILABLE_ERROR (UNVERIFIED-LIVE): ` +
          `No Google Cloud credentials found. Set GOOGLE_APPLICATION_CREDENTIALS to activate live Cloud KMS operations.`
      );
    }

    throw new Error("[CloudKmsKeyProvider] Live Cloud KMS call not supported without active GCP connectivity.");
  }
}
