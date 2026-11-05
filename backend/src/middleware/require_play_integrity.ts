// File: backend/src/middleware/require_play_integrity.ts
import { Response, NextFunction } from 'express';
import { AuthenticatedRequest } from '../auth/firebase_auth';
import {
  PlayIntegrityVerifier,
  PlayIntegrityVerificationResult,
} from '../services/play_integrity_verifier';
import {
  PlayIntegrityBindingParams,
  PlayIntegrityProtectedPurpose,
  PLAY_INTEGRITY_BINDING_PROTOCOL_V2,
  computePayloadDigest,
} from '../services/play_integrity_request_binding';

export interface PlayIntegrityProtectedRequest extends AuthenticatedRequest {
  playIntegrity?: PlayIntegrityVerificationResult;
}

export function createRequirePlayIntegrityMiddleware(verifier?: PlayIntegrityVerifier) {
  const activeVerifier = verifier ?? PlayIntegrityVerifier.getInstance();

  return async (req: PlayIntegrityProtectedRequest, res: Response, next: NextFunction): Promise<void> => {
    const callerUid = req.user?.uid;
    if (!callerUid) {
      res.status(401).json({
        success: false,
        code: 'UNAUTHENTICATED',
        message: 'Authentication required prior to integrity verification',
      });
      return;
    }

    const token =
      (req.headers['x-play-integrity-token'] as string) ||
      req.body?.playIntegrityToken ||
      req.body?.integrityToken;

    // Fail closed if token is missing in PRODUCTION or STAGING
    if (!token) {
      if (process.env.APP_ENV === 'PRODUCTION' || process.env.APP_ENV === 'STAGING') {
        res.status(400).json({
          success: false,
          code: 'MISSING_PLAY_INTEGRITY_TOKEN',
          message: 'Sensitive biometric operations require a valid Google Play Integrity token',
        });
        return;
      }
      // In LOCAL test mode, permit pass-through when token is omitted for legacy suite compatibility
      next();
      return;
    }

    const deviceKeyId = (req.headers['x-device-key-id'] as string) || req.body?.deviceKeyId;
    const challengeId = (req.body?.challengeId || req.body?.challengeTicketId || req.headers['x-transaction-challenge-id'] || 'none').toString();
    const challengePurpose: PlayIntegrityProtectedPurpose =
      (req.body?.purpose || req.body?.challengePurpose || 'INITIAL_ENROLLMENT') as PlayIntegrityProtectedPurpose;
    const serverNonce = (req.body?.challengeNonce || req.body?.nonce || req.headers['x-challenge-nonce'] || '').toString();
    const idempotencyKey = (req.body?.idempotencyKey || req.headers['x-idempotency-key'] || '').toString();
    const route = (req.baseUrl || '') + (req.path || '');

    // Compute payload digest (raw capture image bytes or request body)
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

    let bindingParams: PlayIntegrityBindingParams;

    if (deviceKeyId) {
      bindingParams = {
        protocolVersion: PLAY_INTEGRITY_BINDING_PROTOCOL_V2,
        packageName: 'com.kelasagaara.kelasagaara',
        appVersion: (req.headers['x-app-version'] as string) || req.body?.appVersion || '1.0.0',
        authenticatedUid: callerUid,
        deviceKeyId,
        challengeId,
        challengePurpose,
        serverNonce,
        idempotencyKey,
        httpMethod: (req.method as 'POST' | 'PUT') || 'POST',
        route,
        payloadDigestSha256: payloadDigest,
      };
    } else {
      bindingParams = {
        authenticatedUid: callerUid,
        challengeId,
        challengePurpose,
        serverNonce,
        idempotencyKey,
        httpMethod: (req.method as 'POST' | 'PUT') || 'POST',
        route,
        payloadDigestSha256: payloadDigest,
      };
    }

    const result = await activeVerifier.verifyRequestIntegrity({
      integrityToken: token,
      bindingParams,
      callerUid,
    });

    if (!result.allowed) {
      res.status(result.httpStatus).json({
        success: false,
        code: result.errorCode || 'INTEGRITY_CHECK_FAILED',
        message: result.message,
        outcome: result.outcome,
      });
      return;
    }

    req.playIntegrity = result;
    next();
  };
}

export const requirePlayIntegrity = createRequirePlayIntegrityMiddleware();
