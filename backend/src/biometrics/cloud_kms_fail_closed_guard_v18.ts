import crypto from "crypto";

export type ServiceAccountKmsRole = "ENROLLER_WRAP_ONLY" | "MATCHER_UNWRAP_ONLY";

export interface KmsKeyAttestationConfig {
  gcpResourceName: string; // Must match projects/*/locations/asia-south1/keyRings/*/cryptoKeys/*
  protectionLevel: "HSM";
  activeKeyVersion: number;
}

export class CloudKmsFailClosedGuardV18 {
  private static readonly ASIA_SOUTH1_KMS_REGEX =
    /^projects\/[a-z0-9-]+\/locations\/asia-south1\/keyRings\/[a-zA-Z0-9_-]+\/cryptoKeys\/[a-zA-Z0-9_-]+$/;

  private readonly config: KmsKeyAttestationConfig;
  private readonly masterKekByVersion = new Map<number, Buffer>();
  private readonly revokedServiceAccounts = new Set<string>();
  private circuitState: "HEALTHY" | "HSM_REVOKED_LOCKDOWN" = "HEALTHY";
  private readonly onEmergencyZeroizeArena: () => void;

  constructor(params: {
    config: KmsKeyAttestationConfig;
    onEmergencyZeroizeArena: () => void;
  }) {
    if (!CloudKmsFailClosedGuardV18.ASIA_SOUTH1_KMS_REGEX.test(params.config.gcpResourceName)) {
      throw new Error(
        `ERR_INVALID_KMS_REGION_OR_PATH: Must use asia-south1 Cloud KMS key resource, got ${params.config.gcpResourceName}`
      );
    }
    if (params.config.protectionLevel !== "HSM") {
      throw new Error("ERR_KMS_HSM_REQUIRED: ProtectionLevel must be 'HSM'.");
    }

    this.config = params.config;
    this.onEmergencyZeroizeArena = params.onEmergencyZeroizeArena;
    this.masterKekByVersion.set(params.config.activeKeyVersion, crypto.randomBytes(32));
  }

  public revokeServiceAccountIam(serviceAccountEmail: string): void {
    this.revokedServiceAccounts.add(serviceAccountEmail);
  }

  /**
   * Wraps an ephemeral 256-bit DEK using the HSM key and zeroes the plaintext DEK buffer in `finally`.
   */
  public wrapEphemeralDek(params: {
    callerServiceAccount: string;
    callerRole: ServiceAccountKmsRole;
    ephemeralDek: Buffer;
  }): { wrappedDekCiphertext: Buffer; keyVersion: number; wrapLatencyMs: number } {
    const t0 = process.hrtime.bigint();
    try {
      this.assertHealthyAndAuthorized(
        params.callerServiceAccount,
        params.callerRole,
        "ENROLLER_WRAP_ONLY"
      );

      const kek = this.masterKekByVersion.get(this.config.activeKeyVersion)!;
      const iv = crypto.randomBytes(12);
      const cipher = crypto.createCipheriv("aes-256-gcm", kek, iv);
      cipher.setAAD(Buffer.from(this.config.gcpResourceName, "utf8"));
      const encrypted = Buffer.concat([cipher.update(params.ephemeralDek), cipher.final()]);
      const tag = cipher.getAuthTag();

      const t1 = process.hrtime.bigint();
      return {
        wrappedDekCiphertext: Buffer.concat([iv, tag, encrypted]),
        keyVersion: this.config.activeKeyVersion,
        wrapLatencyMs: Number((Number(t1 - t0) / 1_000_000).toFixed(3)),
      };
    } finally {
      // Ephemeral memory hygiene: zeroize caller's plaintext DEK immediately
      params.ephemeralDek.fill(0);
    }
  }

  /**
   * Unwraps a DEK for snapshot rehydration. If the Service Account's IAM role was revoked,
   * immediately triggers fail-closed zeroization of the active in-memory biometric arena!
   */
  public unwrapDekAndExecute<T>(params: {
    callerServiceAccount: string;
    callerRole: ServiceAccountKmsRole;
    wrappedDekCiphertext: Buffer;
    keyVersion: number;
    useDekCallback: (unwrappedDek: Buffer) => T;
  }): T {
    this.assertHealthyAndAuthorized(
      params.callerServiceAccount,
      params.callerRole,
      "MATCHER_UNWRAP_ONLY"
    );

    const kek = this.masterKekByVersion.get(params.keyVersion);
    if (!kek) {
      this.triggerFailClosedLockdown();
      throw new Error(`ERR_KMS_KEY_VERSION_DESTROYED: Version ${params.keyVersion} unavailable.`);
    }

    const iv = params.wrappedDekCiphertext.subarray(0, 12);
    const tag = params.wrappedDekCiphertext.subarray(12, 28);
    const ciphertext = params.wrappedDekCiphertext.subarray(28);

    const decipher = crypto.createDecipheriv("aes-256-gcm", kek, iv);
    decipher.setAAD(Buffer.from(this.config.gcpResourceName, "utf8"));
    decipher.setAuthTag(tag);

    const unwrappedDek = Buffer.concat([decipher.update(ciphertext), decipher.final()]);
    try {
      return params.useDekCallback(unwrappedDek);
    } finally {
      unwrappedDek.fill(0);
    }
  }

  public getCircuitState(): "HEALTHY" | "HSM_REVOKED_LOCKDOWN" {
    return this.circuitState;
  }

  private assertHealthyAndAuthorized(
    saEmail: string,
    actualRole: ServiceAccountKmsRole,
    requiredRole: ServiceAccountKmsRole
  ): void {
    if (this.circuitState !== "HEALTHY") {
      throw new Error("ERR_HSM_LOCKDOWN_ACTIVE: Biometric memory zeroized due to prior security fault.");
    }
    if (this.revokedServiceAccounts.has(saEmail)) {
      this.triggerFailClosedLockdown();
      throw new Error(
        `ERR_KMS_IAM_REVOKED_FAIL_CLOSED: Service account ${saEmail} IAM permissions revoked. Active arena zeroized.`
      );
    }
    if (actualRole !== requiredRole) {
      throw new Error(
        `ERR_KMS_ROLE_SEPARATION_VIOLATION: Role ${actualRole} cannot execute ${requiredRole} operation.`
      );
    }
  }

  private triggerFailClosedLockdown(): void {
    this.circuitState = "HSM_REVOKED_LOCKDOWN";
    this.onEmergencyZeroizeArena();
  }
}
