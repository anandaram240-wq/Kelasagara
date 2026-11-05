// File: backend/src/middleware/require_device_signature.ts
import { Response, NextFunction } from 'express';
import { AuthenticatedRequest } from '../auth/firebase_auth';
import { DeviceRegistrationService, DeviceKeyRecord } from '../services/device_registration_service';
import {
  DeviceRequestSignatureService,
  VerifyDeviceSignatureResult,
} from '../services/device_request_signature';
import {
  PlayIntegrityBindingParamsV2,
  PLAY_INTEGRITY_BINDING_PROTOCOL_V2,
  computePayloadDigest,
  PlayIntegrityProtectedPurpose,
} from '../services/play_integrity_request_binding';

export interface DeviceAuthenticatedRequest extends AuthenticatedRequest {
  deviceKey?: DeviceKeyRecord;
  deviceSignatureVerification?: VerifyDeviceSignatureResult;
}

export function createRequireDeviceSignatureMiddleware(
  deviceService?: DeviceRegistrationService,
  signatureService?: DeviceRequestSignatureService
) {
  const activeDeviceService = deviceService ?? DeviceRegistrationService.getInstance();
  const activeSigService = signatureService ?? DeviceRequestSignatureService.getInstance();

  return async (req: DeviceAuthenticatedRequest, res: Response, next: NextFunction): Promise<void> => {
    const callerUid = req.user?.uid;
    if (!callerUid) {
      res.status(401).json({
        success: false,
        code: 'UNAUTHENTICATED',
        message: 'Authentication required prior to device signature verification',
      });
      return;
    }

    const deviceKeyId = (req.headers['x-device-key-id'] as string) || req.body?.deviceKeyId;
    const deviceSignature = (req.headers['x-device-signature'] as string) || req.body?.deviceSignature;
    const challengeId =
      (req.headers['x-transaction-challenge-id'] as string) ||
      req.body?.transactionChallengeId ||
      req.body?.challengeId;
    const nonce = (req.headers['x-challenge-nonce'] as string) || req.body?.challengeNonce || req.body?.nonce || '';
    const idempotencyKey =
      (req.headers['x-idempotency-key'] as string) || req.body?.idempotencyKey || req.body?.requestId || '';

    // If device credentials are missing:
    if (!deviceKeyId || !deviceSignature) {
      // In production or staging, or when strict security is enforced, fail closed
      if (
        process.env.APP_ENV === 'PRODUCTION' ||
        process.env.APP_ENV === 'STAGING' ||
        process.env.STRICT_DEVICE_SECURITY === 'true'
      ) {
        res.status(400).json({
          success: false,
          code: 'MISSING_DEVICE_SECURITY_CREDENTIALS',
          message: 'Sensitive biometric operations require device-bound cryptographic credentials (deviceKeyId and signature)',
        });
        return;
      }
      // In local development / test mode, allow pass-through if omitted for backward compatibility
      next();
      return;
    }

    // 1. Retrieve Device Record
    const deviceRecord = await activeDeviceService.getDeviceKey(deviceKeyId);
    if (!deviceRecord) {
      res.status(403).json({
        success: false,
        code: 'DEVICE_NOT_REGISTERED',
        message: `Device key '${deviceKeyId}' is not registered in the system`,
      });
      return;
    }

    // 2. Validate Ownership (Firebase UID binding)
    if (deviceRecord.owningUid !== callerUid) {
      res.status(403).json({
        success: false,
        code: 'DEVICE_OWNERSHIP_MISMATCH',
        message: 'Device key is registered to a different worker account',
      });
      return;
    }

    // 3. Validate Lifecycle Status
    if (deviceRecord.lifecycleStatus !== 'ACTIVE') {
      res.status(403).json({
        success: false,
        code: `DEVICE_KEY_${deviceRecord.lifecycleStatus}`,
        message: `Device key has been ${deviceRecord.lifecycleStatus.toLowerCase()} and cannot be used for authentication`,
      });
      return;
    }

    // 4. Derive canonical route & purpose
    const route = (req.baseUrl || '') + (req.path || '');
    let purpose: PlayIntegrityProtectedPurpose = 'BIOMETRIC_ENROLLMENT';
    if (route.includes('verify-1to1')) {
      purpose = 'BIOMETRIC_VERIFICATION_1TO1';
    } else if (route.includes('replace')) {
      purpose = 'BIOMETRIC_REPLACEMENT';
    } else if (req.body?.purpose) {
      purpose = req.body.purpose as PlayIntegrityProtectedPurpose;
    }

    // 5. Consume Transaction Challenge if challengeId and nonce provided
    if (challengeId && nonce) {
      const challengeCheck = await activeSigService.consumeTransactionChallenge({
        challengeId,
        nonce,
        expectedUid: callerUid,
        expectedDeviceKeyId: deviceKeyId,
        expectedPurpose: purpose,
      });

      if (!challengeCheck.valid) {
        res.status(403).json({
          success: false,
          code: challengeCheck.errorCode || 'INVALID_TRANSACTION_CHALLENGE',
          message: challengeCheck.message || 'Transaction challenge validation failed',
        });
        return;
      }
    }

    // 6. Compute exact capture payload digest
    let payloadDigest: string;
    const reqAny = req as any;
    if (reqAny.file?.buffer) {
      payloadDigest = computePayloadDigest(reqAny.file.buffer);
    } else if (req.body?.imageBase64) {
      const imageBuf = Buffer.from(req.body.imageBase64, 'base64');
      payloadDigest = computePayloadDigest(imageBuf);
    } else if (req.body?.validatedSFaceEmbedding128) {
      const vec = req.body.validatedSFaceEmbedding128;
      const floatArr = Array.isArray(vec) ? new Float32Array(vec) : vec;
      payloadDigest = computePayloadDigest(floatArr);
    } else {
      payloadDigest = computePayloadDigest(JSON.stringify(req.body || {}));
    }

    const bindingParams: PlayIntegrityBindingParamsV2 = {
      protocolVersion: PLAY_INTEGRITY_BINDING_PROTOCOL_V2,
      packageName: 'com.kelasagaara.kelasagaara',
      appVersion: (req.headers['x-app-version'] as string) || req.body?.appVersion || '1.0.0',
      authenticatedUid: callerUid,
      deviceKeyId,
      challengeId: challengeId || 'none',
      challengePurpose: purpose,
      serverNonce: nonce,
      idempotencyKey: idempotencyKey.toString(),
      httpMethod: (req.method as 'POST' | 'PUT') || 'POST',
      route,
      payloadDigestSha256: payloadDigest,
    };

    // 7. Verify cryptographic signature
    const sigResult = activeSigService.verifyDeviceSignature({
      bindingParams,
      signatureBase64: deviceSignature,
      publicKeyPem: deviceRecord.publicKeyPem,
    });

    if (!sigResult.valid) {
      res.status(403).json({
        success: false,
        code: sigResult.errorCode || 'DEVICE_SIGNATURE_INVALID',
        message: sigResult.message || 'Cryptographic device signature verification failed',
      });
      return;
    }

    // 8. Record authentication activity
    await activeDeviceService.recordAuthenticationSuccess(deviceKeyId);

    req.deviceKey = deviceRecord;
    req.deviceSignatureVerification = sigResult;
    next();
  };
}

export const requireDeviceSignature = createRequireDeviceSignatureMiddleware();
