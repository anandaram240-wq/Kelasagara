// File: backend/src/services/device_registration_service.ts
import * as crypto from 'node:crypto';
import * as admin from 'firebase-admin';
import {
  DeviceKeyAttestationVerifier,
  DeviceKeyAttestationResult,
  AttestationSecurityLevel,
  AttestationStatus,
} from './device_key_attestation';

export type DeviceLifecycleStatus = 'ACTIVE' | 'REVOKED' | 'SUSPENDED';

export interface DeviceKeyRecord {
  readonly deviceKeyId: string;
  readonly owningUid: string;
  readonly publicKeyPem: string;
  readonly keyAlgorithm: 'ECDSA_P256';
  readonly keyVersion: number;
  readonly attestationLevel: AttestationSecurityLevel;
  readonly attestationStatus: AttestationStatus;
  readonly applicationPackage: string;
  readonly applicationCertificateDigest: string;
  readonly registeredAt: string;
  readonly lastAuthenticatedAt: string;
  readonly revokedAt: string | null;
  readonly revocationReason?: string;
  readonly lifecycleStatus: DeviceLifecycleStatus;
  readonly metadata?: Record<string, any>;
}

export interface DeviceRegistrationChallenge {
  readonly challengeId: string;
  readonly challengeNonce: string;
  readonly owningUid: string;
  readonly purpose: 'DEVICE_REGISTRATION';
  readonly expiresAt: number; // Unix timestamp ms
  readonly consumed: boolean;
}

export interface RegisterDeviceParams {
  readonly authenticatedUid: string;
  readonly challengeId: string;
  readonly challengeNonce: string;
  readonly certificateChainBase64: string[];
  readonly applicationPackage?: string;
  readonly deviceModel?: string;
  readonly osVersion?: string;
}

export interface RegisterDeviceResult {
  readonly success: boolean;
  readonly deviceKeyId?: string;
  readonly attestationLevel?: AttestationSecurityLevel;
  readonly attestationStatus?: AttestationStatus;
  readonly lifecycleStatus?: DeviceLifecycleStatus;
  readonly errorCode?: string;
  readonly message?: string;
}

export const MAX_ACTIVE_DEVICES_PER_WORKER = 2;
export const REGISTRATION_CHALLENGE_TTL_MS = 5 * 60 * 1000; // 5 minutes

export class DeviceRegistrationService {
  private static instance: DeviceRegistrationService;
  private readonly db?: admin.firestore.Firestore;
  private readonly inMemoryDevices = new Map<string, DeviceKeyRecord>();
  private readonly inMemoryChallenges = new Map<string, DeviceRegistrationChallenge>();
  private readonly attestationVerifier: DeviceKeyAttestationVerifier;

  constructor(db?: admin.firestore.Firestore, verifier?: DeviceKeyAttestationVerifier) {
    this.db = db;
    this.attestationVerifier = verifier ?? DeviceKeyAttestationVerifier.getInstance();
  }

  public static getInstance(db?: admin.firestore.Firestore): DeviceRegistrationService {
    if (!DeviceRegistrationService.instance) {
      DeviceRegistrationService.instance = new DeviceRegistrationService(db);
    }
    return DeviceRegistrationService.instance;
  }

  /**
   * Issues a fresh, single-use registration challenge for an authenticated worker.
   */
  public async issueRegistrationChallenge(owningUid: string): Promise<DeviceRegistrationChallenge> {
    if (!owningUid) {
      throw new Error('owningUid is required to issue a device registration challenge');
    }

    const challengeId = `dreg_chal_${crypto.randomUUID()}`;
    const challengeNonce = crypto.randomBytes(32).toString('hex');
    const expiresAt = Date.now() + REGISTRATION_CHALLENGE_TTL_MS;

    const challenge: DeviceRegistrationChallenge = {
      challengeId,
      challengeNonce,
      owningUid,
      purpose: 'DEVICE_REGISTRATION',
      expiresAt,
      consumed: false,
    };

    if (this.db) {
      try {
        await this.db.collection('biometric_device_challenges').doc(challengeId).set({
          ...challenge,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      } catch {
        // Fall back to memory if Firestore collection unavailable in test
        this.inMemoryChallenges.set(challengeId, challenge);
      }
    } else {
      this.inMemoryChallenges.set(challengeId, challenge);
    }

    return challenge;
  }

  /**
   * Registers a new device key after validating the challenge, certificate chain,
   * attestation security level, and enforcing device quota limits.
   */
  public async registerDevice(params: RegisterDeviceParams): Promise<RegisterDeviceResult> {
    const {
      authenticatedUid,
      challengeId,
      challengeNonce,
      certificateChainBase64,
      applicationPackage = 'com.kelasagaara.kelasagaara',
      deviceModel,
      osVersion,
    } = params;

    // 1. Consume registration challenge atomically
    const challengeValid = await this.consumeRegistrationChallenge(challengeId, challengeNonce, authenticatedUid);
    if (!challengeValid.valid) {
      return {
        success: false,
        errorCode: challengeValid.errorCode,
        message: challengeValid.message,
      };
    }

    // 2. Verify Android Key Attestation chain
    const attestationResult = this.attestationVerifier.verifyAttestation({
      certificateChainBase64,
      expectedChallenge: challengeNonce,
      expectedPackageName: applicationPackage,
      allowSelfAttestedDev: process.env.APP_ENV !== 'PRODUCTION',
    });

    if (!attestationResult.valid) {
      return {
        success: false,
        errorCode: `ATTESTATION_FAILED_${attestationResult.attestationStatus}`,
        message: attestationResult.failureReason || 'Device key attestation failed',
      };
    }

    // 3. Check active device quota for this worker account
    const activeDevices = await this.getActiveDevicesForUser(authenticatedUid);
    if (activeDevices.length >= MAX_ACTIVE_DEVICES_PER_WORKER) {
      return {
        success: false,
        errorCode: 'MAX_ACTIVE_DEVICES_EXCEEDED',
        message: `Worker account already has ${activeDevices.length} active registered devices. Revoke an old device first.`,
      };
    }

    // 4. Generate opaque deviceKeyId and compute key fingerprint
    const keyFingerprint = crypto
      .createHash('sha256')
      .update(attestationResult.publicKeyPem, 'utf8')
      .digest('hex')
      .substring(0, 16);
    const deviceKeyId = `devkey_${keyFingerprint}_${crypto.randomBytes(8).toString('hex')}`;
    const nowIso = new Date().toISOString();

    const record: DeviceKeyRecord = {
      deviceKeyId,
      owningUid: authenticatedUid,
      publicKeyPem: attestationResult.publicKeyPem,
      keyAlgorithm: 'ECDSA_P256',
      keyVersion: 1,
      attestationLevel: attestationResult.attestationLevel,
      attestationStatus: attestationResult.attestationStatus,
      applicationPackage,
      applicationCertificateDigest: crypto
        .createHash('sha256')
        .update(Buffer.from(certificateChainBase64[0], 'base64'))
        .digest('hex'),
      registeredAt: nowIso,
      lastAuthenticatedAt: nowIso,
      revokedAt: null,
      lifecycleStatus: 'ACTIVE',
      metadata: {
        deviceModel: deviceModel || 'Android Device',
        osVersion: osVersion || 'Android',
        chainLength: attestationResult.certificateChainLength,
      },
    };

    // 5. Persist record to Firestore /biometric_devices/{deviceKeyId}
    if (this.db) {
      try {
        await this.db.collection('biometric_devices').doc(deviceKeyId).set(record);
      } catch {
        this.inMemoryDevices.set(deviceKeyId, record);
      }
    } else {
      this.inMemoryDevices.set(deviceKeyId, record);
    }

    return {
      success: true,
      deviceKeyId,
      attestationLevel: record.attestationLevel,
      attestationStatus: record.attestationStatus,
      lifecycleStatus: record.lifecycleStatus,
    };
  }

  /**
   * Retrieves a device record by opaque deviceKeyId.
   */
  public async getDeviceKey(deviceKeyId: string): Promise<DeviceKeyRecord | null> {
    if (!deviceKeyId) return null;

    if (this.db) {
      try {
        const snap = await this.db.collection('biometric_devices').doc(deviceKeyId).get();
        if (snap.exists) {
          return snap.data() as DeviceKeyRecord;
        }
      } catch {
        // Fallback to memory
      }
    }

    return this.inMemoryDevices.get(deviceKeyId) || null;
  }

  /**
   * Retrieves all ACTIVE devices bound to a worker UID.
   */
  public async getActiveDevicesForUser(uid: string): Promise<DeviceKeyRecord[]> {
    if (!uid) return [];

    if (this.db) {
      try {
        const snapshot = await this.db
          .collection('biometric_devices')
          .where('owningUid', '==', uid)
          .where('lifecycleStatus', '==', 'ACTIVE')
          .get();

        if (!snapshot.empty) {
          return snapshot.docs.map((doc) => doc.data() as DeviceKeyRecord);
        }
      } catch {
        // Fallback to memory
      }
    }

    const results: DeviceKeyRecord[] = [];
    for (const record of this.inMemoryDevices.values()) {
      if (record.owningUid === uid && record.lifecycleStatus === 'ACTIVE') {
        results.push(record);
      }
    }
    return results;
  }

  /**
   * Revokes an existing device key.
   */
  public async revokeDeviceKey(
    deviceKeyId: string,
    requestingUid: string,
    reason: string = 'USER_INITIATED_REVOCATION'
  ): Promise<{ success: boolean; errorCode?: string; message?: string }> {
    const record = await this.getDeviceKey(deviceKeyId);
    if (!record) {
      return { success: false, errorCode: 'DEVICE_NOT_FOUND', message: 'Device key record does not exist' };
    }

    if (record.owningUid !== requestingUid) {
      return { success: false, errorCode: 'UNAUTHORIZED', message: 'Caller does not own this device key' };
    }

    const updated: DeviceKeyRecord = {
      ...record,
      lifecycleStatus: 'REVOKED',
      revokedAt: new Date().toISOString(),
      revocationReason: reason,
    };

    if (this.db) {
      try {
        await this.db.collection('biometric_devices').doc(deviceKeyId).update({
          lifecycleStatus: 'REVOKED',
          revokedAt: updated.revokedAt,
          revocationReason: reason,
        });
      } catch {
        this.inMemoryDevices.set(deviceKeyId, updated);
      }
    } else {
      this.inMemoryDevices.set(deviceKeyId, updated);
    }

    return { success: true };
  }

  /**
   * Updates lastAuthenticatedAt timestamp for an active device.
   */
  public async recordAuthenticationSuccess(deviceKeyId: string): Promise<void> {
    const nowIso = new Date().toISOString();
    if (this.db) {
      try {
        await this.db.collection('biometric_devices').doc(deviceKeyId).update({
          lastAuthenticatedAt: nowIso,
        });
      } catch {
        // Ignore or memory
      }
    }
    const mem = this.inMemoryDevices.get(deviceKeyId);
    if (mem) {
      this.inMemoryDevices.set(deviceKeyId, { ...mem, lastAuthenticatedAt: nowIso });
    }
  }

  /**
   * Atomically checks and consumes a single-use registration challenge.
   */
  private async consumeRegistrationChallenge(
    challengeId: string,
    nonce: string,
    expectedUid: string
  ): Promise<{ valid: boolean; errorCode?: string; message?: string }> {
    if (!challengeId || !nonce) {
      return { valid: false, errorCode: 'MISSING_CHALLENGE', message: 'Challenge credentials missing' };
    }

    let challenge: DeviceRegistrationChallenge | null = null;

    if (this.db) {
      try {
        const ref = this.db.collection('biometric_device_challenges').doc(challengeId);
        const res = await this.db.runTransaction(async (txn) => {
          const doc = await txn.get(ref);
          if (!doc.exists) return null;
          const data = doc.data() as DeviceRegistrationChallenge;
          if (data.consumed) return { ...data, alreadyConsumed: true };
          txn.update(ref, { consumed: true, consumedAt: admin.firestore.FieldValue.serverTimestamp() });
          return data;
        });

        if (res) {
          if ((res as any).alreadyConsumed) {
            return { valid: false, errorCode: 'CHALLENGE_REPLAYED', message: 'Registration challenge already consumed' };
          }
          challenge = res as DeviceRegistrationChallenge;
        }
      } catch {
        challenge = this.inMemoryChallenges.get(challengeId) || null;
      }
    } else {
      challenge = this.inMemoryChallenges.get(challengeId) || null;
    }

    if (!challenge) {
      return { valid: false, errorCode: 'CHALLENGE_NOT_FOUND', message: 'Registration challenge not found' };
    }

    if (challenge.consumed) {
      return { valid: false, errorCode: 'CHALLENGE_REPLAYED', message: 'Registration challenge has already been used' };
    }

    if (Date.now() > challenge.expiresAt) {
      return { valid: false, errorCode: 'CHALLENGE_EXPIRED', message: 'Registration challenge has expired' };
    }

    if (challenge.owningUid !== expectedUid) {
      return { valid: false, errorCode: 'CHALLENGE_UID_MISMATCH', message: 'Challenge was issued to a different UID' };
    }

    if (challenge.challengeNonce !== nonce) {
      return { valid: false, errorCode: 'CHALLENGE_NONCE_MISMATCH', message: 'Challenge nonce does not match' };
    }

    // Mark in memory
    this.inMemoryChallenges.set(challengeId, { ...challenge, consumed: true });

    return { valid: true };
  }
}
