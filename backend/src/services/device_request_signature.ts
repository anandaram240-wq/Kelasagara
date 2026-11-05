// File: backend/src/services/device_request_signature.ts
import * as crypto from 'node:crypto';
import * as admin from 'firebase-admin';
import {
  PlayIntegrityBindingParamsV2,
  PLAY_INTEGRITY_BINDING_PROTOCOL_V2,
  serializeCanonicalBinding,
  computePlayIntegrityRequestHash,
  PlayIntegrityProtectedPurpose,
} from './play_integrity_request_binding';
import { DeviceRegistrationService, DeviceKeyRecord } from './device_registration_service';

export interface VerifyDeviceSignatureParams {
  readonly bindingParams: PlayIntegrityBindingParamsV2;
  readonly signatureBase64: string;
  readonly publicKeyPem: string;
}

export interface VerifyDeviceSignatureResult {
  readonly valid: boolean;
  readonly deviceKeyId: string;
  readonly canonicalRequestHash: string;
  readonly errorCode?: string;
  readonly message?: string;
}

export interface TransactionChallenge {
  readonly challengeId: string;
  readonly challengeNonce: string;
  readonly uid: string;
  readonly deviceKeyId: string;
  readonly purpose: PlayIntegrityProtectedPurpose;
  readonly expiresAt: number; // Unix timestamp ms
  readonly consumed: boolean;
}

export const TRANSACTION_CHALLENGE_TTL_MS = 3 * 60 * 1000; // 3 minutes

export class DeviceRequestSignatureService {
  private static instance: DeviceRequestSignatureService;
  private readonly db?: admin.firestore.Firestore;
  private readonly deviceRegistrationService: DeviceRegistrationService;
  private readonly inMemoryChallenges = new Map<string, TransactionChallenge>();

  constructor(db?: admin.firestore.Firestore, deviceService?: DeviceRegistrationService) {
    this.db = db;
    this.deviceRegistrationService = deviceService ?? DeviceRegistrationService.getInstance(db);
  }

  public static getInstance(db?: admin.firestore.Firestore, deviceService?: DeviceRegistrationService): DeviceRequestSignatureService {
    if (!DeviceRequestSignatureService.instance) {
      DeviceRequestSignatureService.instance = new DeviceRequestSignatureService(db, deviceService);
    }
    return DeviceRequestSignatureService.instance;
  }

  /**
   * Issues a fresh, transaction-bound challenge tied to a specific UID, deviceKeyId, and purpose.
   */
  public async issueTransactionChallenge(params: {
    uid: string;
    deviceKeyId: string;
    purpose: PlayIntegrityProtectedPurpose;
    ttlMs?: number;
  }): Promise<TransactionChallenge> {
    const { uid, deviceKeyId, purpose, ttlMs = TRANSACTION_CHALLENGE_TTL_MS } = params;

    if (!uid || !deviceKeyId || !purpose) {
      throw new Error('uid, deviceKeyId, and purpose are required to issue a transaction challenge');
    }

    // Verify that the deviceKey exists and is currently ACTIVE
    const deviceRecord = await this.deviceRegistrationService.getDeviceKey(deviceKeyId);
    if (!deviceRecord) {
      throw new Error(`Device key not found: ${deviceKeyId}`);
    }
    if (deviceRecord.lifecycleStatus !== 'ACTIVE') {
      throw new Error(`Device key is ${deviceRecord.lifecycleStatus}, cannot issue challenge`);
    }
    if (deviceRecord.owningUid !== uid) {
      throw new Error('Device key is not registered to the requesting user');
    }

    const challengeId = `tx_chal_${crypto.randomUUID()}`;
    const challengeNonce = crypto.randomBytes(32).toString('hex');
    const expiresAt = Date.now() + ttlMs;

    const challenge: TransactionChallenge = {
      challengeId,
      challengeNonce,
      uid,
      deviceKeyId,
      purpose,
      expiresAt,
      consumed: false,
    };

    if (this.db) {
      try {
        await this.db.collection('biometric_transaction_challenges').doc(challengeId).set({
          ...challenge,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      } catch {
        this.inMemoryChallenges.set(challengeId, challenge);
      }
    } else {
      this.inMemoryChallenges.set(challengeId, challenge);
    }

    return challenge;
  }

  /**
   * Atomically verifies and consumes a single-use transaction challenge.
   */
  public async consumeTransactionChallenge(params: {
    challengeId: string;
    nonce: string;
    expectedUid: string;
    expectedDeviceKeyId: string;
    expectedPurpose: PlayIntegrityProtectedPurpose;
  }): Promise<{ valid: boolean; errorCode?: string; message?: string }> {
    const { challengeId, nonce, expectedUid, expectedDeviceKeyId, expectedPurpose } = params;

    if (!challengeId || !nonce) {
      return { valid: false, errorCode: 'MISSING_CHALLENGE_CREDENTIALS', message: 'Challenge credentials missing' };
    }

    let challenge: TransactionChallenge | null = null;

    if (this.db) {
      try {
        const ref = this.db.collection('biometric_transaction_challenges').doc(challengeId);
        const res = await this.db.runTransaction(async (txn) => {
          const doc = await txn.get(ref);
          if (!doc.exists) return null;
          const data = doc.data() as TransactionChallenge;
          if (data.consumed) return { ...data, alreadyConsumed: true };
          txn.update(ref, { consumed: true, consumedAt: admin.firestore.FieldValue.serverTimestamp() });
          return data;
        });

        if (res) {
          if ((res as any).alreadyConsumed) {
            return { valid: false, errorCode: 'CHALLENGE_REPLAYED', message: 'Transaction challenge already consumed' };
          }
          challenge = res as TransactionChallenge;
        }
      } catch {
        challenge = this.inMemoryChallenges.get(challengeId) || null;
      }
    } else {
      challenge = this.inMemoryChallenges.get(challengeId) || null;
    }

    if (!challenge) {
      return { valid: false, errorCode: 'CHALLENGE_NOT_FOUND', message: 'Transaction challenge not found' };
    }

    if (challenge.consumed) {
      return { valid: false, errorCode: 'CHALLENGE_REPLAYED', message: 'Transaction challenge already consumed' };
    }

    if (Date.now() > challenge.expiresAt) {
      return { valid: false, errorCode: 'CHALLENGE_EXPIRED', message: 'Transaction challenge has expired' };
    }

    if (challenge.uid !== expectedUid) {
      return { valid: false, errorCode: 'CHALLENGE_UID_MISMATCH', message: 'Challenge was issued to a different UID' };
    }

    if (challenge.deviceKeyId !== expectedDeviceKeyId) {
      return { valid: false, errorCode: 'CHALLENGE_DEVICE_MISMATCH', message: 'Challenge was issued for a different device' };
    }

    if (challenge.purpose !== expectedPurpose) {
      return { valid: false, errorCode: 'CHALLENGE_PURPOSE_MISMATCH', message: `Challenge purpose ${challenge.purpose} does not match ${expectedPurpose}` };
    }

    if (challenge.challengeNonce !== nonce) {
      return { valid: false, errorCode: 'CHALLENGE_NONCE_MISMATCH', message: 'Challenge nonce does not match' };
    }

    this.inMemoryChallenges.set(challengeId, { ...challenge, consumed: true });
    return { valid: true };
  }

  /**
   * Verifies an ECDSA P-256 signature generated by an Android Keystore hardware-backed private key
   * across the canonical binary transaction representation.
   */
  public verifyDeviceSignature(params: VerifyDeviceSignatureParams): VerifyDeviceSignatureResult {
    const { bindingParams, signatureBase64, publicKeyPem } = params;

    if (!signatureBase64 || typeof signatureBase64 !== 'string') {
      return {
        valid: false,
        deviceKeyId: bindingParams.deviceKeyId,
        canonicalRequestHash: '',
        errorCode: 'MISSING_DEVICE_SIGNATURE',
        message: 'Device signature is required',
      };
    }

    if (!publicKeyPem || typeof publicKeyPem !== 'string') {
      return {
        valid: false,
        deviceKeyId: bindingParams.deviceKeyId,
        canonicalRequestHash: '',
        errorCode: 'MISSING_PUBLIC_KEY',
        message: 'Device public key is required for signature verification',
      };
    }

    const canonicalBytes = serializeCanonicalBinding(bindingParams);
    const canonicalRequestHash = computePlayIntegrityRequestHash(bindingParams);

    let sigBuffer: Buffer;
    try {
      sigBuffer = Buffer.from(signatureBase64, 'base64');
    } catch (e: any) {
      return {
        valid: false,
        deviceKeyId: bindingParams.deviceKeyId,
        canonicalRequestHash,
        errorCode: 'INVALID_SIGNATURE_ENCODING',
        message: `Failed to decode signature base64: ${e.message}`,
      };
    }

    try {
      const verified = crypto.verify('sha256', canonicalBytes, publicKeyPem, sigBuffer);
      if (!verified) {
        return {
          valid: false,
          deviceKeyId: bindingParams.deviceKeyId,
          canonicalRequestHash,
          errorCode: 'DEVICE_SIGNATURE_INVALID',
          message: 'Cryptographic signature verification failed for device key',
        };
      }

      return {
        valid: true,
        deviceKeyId: bindingParams.deviceKeyId,
        canonicalRequestHash,
      };
    } catch (e: any) {
      return {
        valid: false,
        deviceKeyId: bindingParams.deviceKeyId,
        canonicalRequestHash,
        errorCode: 'SIGNATURE_VERIFICATION_ERROR',
        message: `Cryptographic error during signature verification: ${e.message}`,
      };
    }
  }
}
