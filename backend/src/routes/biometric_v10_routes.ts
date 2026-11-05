// File: backend/src/routes/biometric_v10_routes.ts
import { Router, Request, Response } from 'express';
import * as admin from 'firebase-admin';
import { randomBytes, randomUUID } from 'crypto';
import {
  authenticateFirebaseToken,
  AuthenticatedRequest,
} from '../auth/firebase_auth';
import {
  BiometricLifecycleCoordinatorV10,
} from '../services/biometric_lifecycle_coordinator_v10';
import {
  CanonicalSFaceEngineV10,
  BiometricPreprocessingError,
} from '../biometrics/canonical_sface_engine_v10';
import {
  BiometricOperationReceiptService,
} from '../biometrics/identity_contract_v10';
import { requirePlayIntegrity } from '../middleware/require_play_integrity';
import { createRequireDeviceSignatureMiddleware } from '../middleware/require_device_signature';
import { DeviceRegistrationService } from '../services/device_registration_service';
import { DeviceRequestSignatureService } from '../services/device_request_signature';

export interface BiometricV10RouterDependencies {
  db: admin.firestore.Firestore;
  coordinator: BiometricLifecycleCoordinatorV10;
  engine: CanonicalSFaceEngineV10;
  receiptService: BiometricOperationReceiptService;
  deviceService?: DeviceRegistrationService;
  signatureService?: DeviceRequestSignatureService;
}

export function createBiometricV10Router(deps: BiometricV10RouterDependencies): Router {
  const router = Router();
  const db = deps.db;
  const deviceService = deps.deviceService ?? DeviceRegistrationService.getInstance(db);
  const signatureService = deps.signatureService ?? DeviceRequestSignatureService.getInstance(db, deviceService);
  const requireDeviceSignature = createRequireDeviceSignatureMiddleware(deviceService, signatureService);

  // ─────────────────────────────────────────────────────────────────────────────
  // 0. GET /health
  // ─────────────────────────────────────────────────────────────────────────────
  router.get('/health', (_req: Request, res: Response) => {
    res.status(200).json({
      success: true,
      status: 'healthy',
      subsystem: 'v10_canonical_sface',
      timestamp: new Date().toISOString(),
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // 1. POST /challenge
  // ─────────────────────────────────────────────────────────────────────────────
  router.post(
    '/challenge',
    authenticateFirebaseToken,
    async (req: AuthenticatedRequest, res: Response): Promise<void> => {
      try {
        const uid = req.user?.uid;
        if (!uid) {
          res.status(401).json({
            success: false,
            code: 'UNAUTHENTICATED',
            message: 'Verified user credentials required.',
          });
          return;
        }

        const purpose = (req.body?.purpose || 'INITIAL_ENROLLMENT').toString();
        const validPurposes = [
          'INITIAL_ENROLLMENT',
          'EXISTING_ACCOUNT_VERIFY_1TO1',
          'AUTHORIZED_REPLACEMENT',
        ];
        if (!validPurposes.includes(purpose)) {
          res.status(400).json({
            success: false,
            code: 'INVALID_CHALLENGE_PURPOSE',
            message: `Invalid challenge purpose. Allowed: ${validPurposes.join(', ')}`,
          });
          return;
        }

        const challengeId = `ch_${randomUUID()}`;
        const nonce = randomBytes(16).toString('base64url');
        const nowMs = Date.now();
        const expiresAtMs = nowMs + 5 * 60 * 1000; // 5-minute TTL

        await db.collection('biometric_challenges').doc(challengeId).set({
          challengeId,
          nonce,
          uid,
          purpose,
          expiresAtMs,
          consumed: false,
          consumedAtMs: null,
          createdAtMs: nowMs,
        });

        res.status(200).json({
          success: true,
          challengeId,
          nonce,
          purpose,
          expiresAtMs,
        });
      } catch (err: any) {
        res.status(500).json({
          success: false,
          code: 'CHALLENGE_ERROR',
          message: err.message,
        });
      }
    }
  );

  // Helper to atomically consume single-use challenge
  async function consumeChallenge(
    challengeId: string,
    nonce: string,
    expectedUid: string,
    expectedPurpose: string | string[]
  ): Promise<{ valid: boolean; code?: string; message?: string }> {
    return db.runTransaction(async (tx) => {
      const challengeRef = db.collection('biometric_challenges').doc(challengeId);
      const snap = await tx.get(challengeRef);
      if (!snap.exists) {
        return { valid: false, code: 'CHALLENGE_NOT_FOUND', message: 'Challenge does not exist.' };
      }
      const data = snap.data()!;
      if (data.consumed === true) {
        return { valid: false, code: 'CHALLENGE_ALREADY_CONSUMED', message: 'Challenge nonce has already been consumed.' };
      }
      if (data.uid !== expectedUid) {
        return { valid: false, code: 'CHALLENGE_UID_MISMATCH', message: 'Challenge was issued to a different identity.' };
      }
      if (data.nonce !== nonce) {
        return { valid: false, code: 'CHALLENGE_NONCE_MISMATCH', message: 'Invalid challenge nonce.' };
      }
      const allowed = Array.isArray(expectedPurpose) ? expectedPurpose : [expectedPurpose];
      if (!allowed.includes(data.purpose)) {
        return { valid: false, code: 'CHALLENGE_PURPOSE_MISMATCH', message: 'Challenge purpose does not match request.' };
      }
      if (Date.now() > Number(data.expiresAtMs ?? 0)) {
        return { valid: false, code: 'CHALLENGE_EXPIRED', message: 'Challenge nonce has expired.' };
      }

      tx.update(challengeRef, {
        consumed: true,
        consumedAtMs: Date.now(),
      });
      return { valid: true };
    });
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // 1A. POST /request-device-registration-challenge
  // ─────────────────────────────────────────────────────────────────────────────
  router.post(
    '/request-device-registration-challenge',
    authenticateFirebaseToken,
    async (req: AuthenticatedRequest, res: Response): Promise<void> => {
      try {
        const uid = req.user?.uid;
        if (!uid) {
          res.status(401).json({ success: false, code: 'UNAUTHENTICATED' });
          return;
        }

        const challenge = await deviceService.issueRegistrationChallenge(uid);
        res.status(200).json({
          success: true,
          challengeId: challenge.challengeId,
          challengeNonce: challenge.challengeNonce,
          expiresAt: challenge.expiresAt,
        });
      } catch (err: any) {
        res.status(500).json({ success: false, code: 'CHALLENGE_ERROR', message: err.message });
      }
    }
  );

  // ─────────────────────────────────────────────────────────────────────────────
  // 1B. POST /register-device
  // ─────────────────────────────────────────────────────────────────────────────
  router.post(
    '/register-device',
    authenticateFirebaseToken,
    async (req: AuthenticatedRequest, res: Response): Promise<void> => {
      try {
        const uid = req.user?.uid;
        if (!uid) {
          res.status(401).json({ success: false, code: 'UNAUTHENTICATED' });
          return;
        }

        const { challengeId, challengeNonce, certificateChainBase64, applicationPackage, deviceModel, osVersion } = req.body || {};
        if (!challengeId || !challengeNonce || !certificateChainBase64) {
          res.status(400).json({
            success: false,
            code: 'MISSING_REQUIRED_FIELDS',
            message: 'challengeId, challengeNonce, and certificateChainBase64 are required.',
          });
          return;
        }

        const regResult = await deviceService.registerDevice({
          authenticatedUid: uid,
          challengeId,
          challengeNonce,
          certificateChainBase64,
          applicationPackage,
          deviceModel,
          osVersion,
        });

        if (!regResult.success) {
          res.status(400).json({
            success: false,
            code: regResult.errorCode || 'REGISTRATION_FAILED',
            message: regResult.message,
          });
          return;
        }

        res.status(200).json({
          success: true,
          deviceKeyId: regResult.deviceKeyId,
          attestationLevel: regResult.attestationLevel,
          attestationStatus: regResult.attestationStatus,
          lifecycleStatus: regResult.lifecycleStatus,
        });
      } catch (err: any) {
        res.status(500).json({ success: false, code: 'REGISTRATION_ERROR', message: err.message });
      }
    }
  );

  // ─────────────────────────────────────────────────────────────────────────────
  // 1C. POST /request-device-challenge
  // ─────────────────────────────────────────────────────────────────────────────
  router.post(
    '/request-device-challenge',
    authenticateFirebaseToken,
    async (req: AuthenticatedRequest, res: Response): Promise<void> => {
      try {
        const uid = req.user?.uid;
        if (!uid) {
          res.status(401).json({ success: false, code: 'UNAUTHENTICATED' });
          return;
        }

        const { deviceKeyId, purpose } = req.body || {};
        if (!deviceKeyId || !purpose) {
          res.status(400).json({
            success: false,
            code: 'MISSING_REQUIRED_FIELDS',
            message: 'deviceKeyId and purpose are required.',
          });
          return;
        }

        const challenge = await signatureService.issueTransactionChallenge({
          uid,
          deviceKeyId,
          purpose,
        });

        res.status(200).json({
          success: true,
          challengeId: challenge.challengeId,
          challengeNonce: challenge.challengeNonce,
          expiresAt: challenge.expiresAt,
        });
      } catch (err: any) {
        res.status(400).json({ success: false, code: 'TRANSACTION_CHALLENGE_ERROR', message: err.message });
      }
    }
  );

  // ─────────────────────────────────────────────────────────────────────────────
  // 1D. POST /revoke-device
  // ─────────────────────────────────────────────────────────────────────────────
  router.post(
    '/revoke-device',
    authenticateFirebaseToken,
    async (req: AuthenticatedRequest, res: Response): Promise<void> => {
      try {
        const uid = req.user?.uid;
        if (!uid) {
          res.status(401).json({ success: false, code: 'UNAUTHENTICATED' });
          return;
        }

        const { deviceKeyId, reason } = req.body || {};
        if (!deviceKeyId) {
          res.status(400).json({ success: false, code: 'MISSING_DEVICE_KEY_ID' });
          return;
        }

        const revResult = await deviceService.revokeDeviceKey(deviceKeyId, uid, reason);
        if (!revResult.success) {
          res.status(400).json({ success: false, code: revResult.errorCode, message: revResult.message });
          return;
        }

        res.status(200).json({ success: true, deviceKeyId, lifecycleStatus: 'REVOKED' });
      } catch (err: any) {
        res.status(500).json({ success: false, code: 'REVOCATION_ERROR', message: err.message });
      }
    }
  );

  // ─────────────────────────────────────────────────────────────────────────────
  // 1E. GET /devices
  // ─────────────────────────────────────────────────────────────────────────────
  router.get(
    '/devices',
    authenticateFirebaseToken,
    async (req: AuthenticatedRequest, res: Response): Promise<void> => {
      try {
        const uid = req.user?.uid;
        if (!uid) {
          res.status(401).json({ success: false, code: 'UNAUTHENTICATED' });
          return;
        }

        const devices = await deviceService.getActiveDevicesForUser(uid);
        res.status(200).json({ success: true, count: devices.length, devices });
      } catch (err: any) {
        res.status(500).json({ success: false, code: 'DEVICES_FETCH_ERROR', message: err.message });
      }
    }
  );

  // ─────────────────────────────────────────────────────────────────────────────
  // 2. POST /enroll
  // ─────────────────────────────────────────────────────────────────────────────
  router.post(
    '/enroll',
    authenticateFirebaseToken,
    requirePlayIntegrity,
    requireDeviceSignature,
    async (req: AuthenticatedRequest, res: Response): Promise<void> => {
      try {
        const uid = req.user?.uid;
        if (!uid) {
          res.status(401).json({
            success: false,
            code: 'UNAUTHENTICATED',
            message: 'Verified user credentials required.',
          });
          return;
        }

        // Phase 3C1: Reject client-supplied raw embedding vectors!
        if (req.body?.embedding || req.body?.vector) {
          res.status(400).json({
            success: false,
            code: 'CLIENT_VECTOR_REJECTED',
            message: 'Client-supplied biometric embeddings are strictly prohibited. The trusted server performs authoritative feature extraction.',
          });
          return;
        }

        const { challengeId, nonce, idempotencyKey, imageBase64, isReEnrollment, probeVector } = req.body || {};
        if (!challengeId || !nonce || !idempotencyKey || !imageBase64) {
          res.status(400).json({
            success: false,
            code: 'MISSING_REQUIRED_FIELDS',
            message: 'challengeId, nonce, idempotencyKey, and imageBase64 are required.',
          });
          return;
        }

        // Phase 3C2: Consume challenge atomically
        const allowedPurposes = isReEnrollment
          ? ['INITIAL_ENROLLMENT', 'AUTHORIZED_REPLACEMENT', 'EXISTING_ACCOUNT_VERIFY_1TO1']
          : ['INITIAL_ENROLLMENT'];
        const challengeCheck = await consumeChallenge(
          challengeId,
          nonce,
          uid,
          allowedPurposes
        );
        if (!challengeCheck.valid) {
          res.status(403).json({
            success: false,
            code: challengeCheck.code,
            message: challengeCheck.message,
          });
          return;
        }

        // Server-side authoritative SFace feature extraction via canonical detection and alignment
        const imageBuffer = Buffer.from(imageBase64, 'base64');
        const { embedding: validatedSFaceEmbedding128 } =
          await deps.engine.extractCanonicalEmbeddingFromOriginalImage(imageBuffer);

        const outcome = await deps.coordinator.enrollInitial({
          authenticatedUid: uid,
          idempotencyKey,
          challengeNonce: nonce,
          validatedSFaceEmbedding128,
          probeLandmarkVector128: Array.isArray(probeVector) && probeVector.length === 128 ? probeVector : undefined,
          isReEnrollment: Boolean(isReEnrollment),
        });

        res.status(outcome.httpStatus).json(outcome);
      } catch (err: any) {
        if (err instanceof BiometricPreprocessingError) {
          res.status(400).json({
            success: false,
            code: err.code,
            message: err.message,
            details: err.details,
          });
          return;
        }
        res.status(500).json({
          success: false,
          code: 'ENROLLMENT_INTERNAL_ERROR',
          message: err.message,
        });
      }
    }
  );

  // ─────────────────────────────────────────────────────────────────────────────
  // 3. POST /verify-1to1
  // ─────────────────────────────────────────────────────────────────────────────
  router.post(
    '/verify-1to1',
    authenticateFirebaseToken,
    requirePlayIntegrity,
    requireDeviceSignature,
    async (req: AuthenticatedRequest, res: Response): Promise<void> => {
      try {
        const uid = req.user?.uid;
        if (!uid) {
          res.status(401).json({
            success: false,
            code: 'UNAUTHENTICATED',
            message: 'Verified user credentials required.',
          });
          return;
        }

        if (req.body?.embedding || req.body?.vector) {
          res.status(400).json({
            success: false,
            code: 'CLIENT_VECTOR_REJECTED',
            message: 'Client-supplied biometric embeddings are strictly prohibited.',
          });
          return;
        }

        const { challengeId, nonce, imageBase64 } = req.body || {};
        if (!challengeId || !nonce || !imageBase64) {
          res.status(400).json({
            success: false,
            code: 'MISSING_REQUIRED_FIELDS',
            message: 'challengeId, nonce, and imageBase64 are required.',
          });
          return;
        }

        const challengeCheck = await consumeChallenge(
          challengeId,
          nonce,
          uid,
          'EXISTING_ACCOUNT_VERIFY_1TO1'
        );
        if (!challengeCheck.valid) {
          res.status(403).json({
            success: false,
            code: challengeCheck.code,
            message: challengeCheck.message,
          });
          return;
        }

        const imageBuffer = Buffer.from(imageBase64, 'base64');
        const { embedding: validatedSFaceEmbedding128 } =
          await deps.engine.extractCanonicalEmbeddingFromOriginalImage(imageBuffer);

        const outcome = await deps.coordinator.verifyExistingAccount1to1({
          authenticatedUid: uid,
          challengeNonce: nonce,
          validatedSFaceEmbedding128,
        });

        res.status(outcome.httpStatus).json(outcome);
      } catch (err: any) {
        if (err instanceof BiometricPreprocessingError) {
          res.status(400).json({
            success: false,
            code: err.code,
            message: err.message,
            details: err.details,
          });
          return;
        }
        res.status(500).json({
          success: false,
          code: 'VERIFICATION_INTERNAL_ERROR',
          message: err.message,
        });
      }
    }
  );

  // ─────────────────────────────────────────────────────────────────────────────
  // 4. POST /replace (Authorized Re-enrollment)
  // ─────────────────────────────────────────────────────────────────────────────
  router.post(
    '/replace',
    authenticateFirebaseToken,
    requirePlayIntegrity,
    requireDeviceSignature,
    async (req: AuthenticatedRequest, res: Response): Promise<void> => {
      try {
        const uid = req.user?.uid;
        if (!uid) {
          res.status(401).json({
            success: false,
            code: 'UNAUTHENTICATED',
            message: 'Verified user credentials required.',
          });
          return;
        }

        // Phase 3C3: Never trust client boolean stepUpAuthorized!
        const stepUpProofToken = req.body?.stepUpProofToken;
        if (!stepUpProofToken || typeof stepUpProofToken !== 'string') {
          res.status(403).json({
            success: false,
            code: 'MISSING_STEP_UP_PROOF',
            message: 'A cryptographically verified stepUpProofToken is required for authorized face replacement.',
          });
          return;
        }

        // Verify step-up proof record in Firestore
        const proofSnap = await db.collection('step_up_proofs').doc(stepUpProofToken).get();
        if (!proofSnap.exists) {
          res.status(403).json({
            success: false,
            code: 'INVALID_STEP_UP_PROOF',
            message: 'Step-up authentication proof was not found or has expired.',
          });
          return;
        }

        const proofData = proofSnap.data()!;
        if (
          proofData.uid !== uid ||
          proofData.consumed === true ||
          Date.now() > Number(proofData.expiresAtMs ?? 0)
        ) {
          res.status(403).json({
            success: false,
            code: 'UNAUTHORIZED_STEP_UP',
            message: 'Step-up proof is invalid, expired, or belongs to another user.',
          });
          return;
        }

        const { challengeId, nonce, idempotencyKey, replacementReason, imageBase64 } = req.body || {};
        if (!challengeId || !nonce || !idempotencyKey || !imageBase64) {
          res.status(400).json({
            success: false,
            code: 'MISSING_REQUIRED_FIELDS',
            message: 'challengeId, nonce, idempotencyKey, and imageBase64 are required.',
          });
          return;
        }

        const challengeCheck = await consumeChallenge(
          challengeId,
          nonce,
          uid,
          'AUTHORIZED_REPLACEMENT'
        );
        if (!challengeCheck.valid) {
          res.status(403).json({
            success: false,
            code: challengeCheck.code,
            message: challengeCheck.message,
          });
          return;
        }

        // Mark proof consumed atomically
        await db.collection('step_up_proofs').doc(stepUpProofToken).update({
          consumed: true,
          consumedAtMs: Date.now(),
        });

        const imageBuffer = Buffer.from(imageBase64, 'base64');
        const { embedding: validatedSFaceEmbedding128 } =
          await deps.engine.extractCanonicalEmbeddingFromOriginalImage(imageBuffer);

        const outcome = await deps.coordinator.replaceAuthorizedEnrollment({
          authenticatedUid: uid,
          idempotencyKey,
          challengeNonce: nonce,
          stepUpAuthorized: true,
          replacementReason: replacementReason || 'User requested authorized face replacement',
          validatedSFaceEmbedding128,
        });

        res.status(outcome.httpStatus).json(outcome);
      } catch (err: any) {
        if (err instanceof BiometricPreprocessingError) {
          res.status(400).json({
            success: false,
            code: err.code,
            message: err.message,
            details: err.details,
          });
          return;
        }
        res.status(500).json({
          success: false,
          code: 'REPLACEMENT_INTERNAL_ERROR',
          message: err.message,
        });
      }
    }
  );

  // ─────────────────────────────────────────────────────────────────────────────
  // 5. POST /redeem-receipt
  // ─────────────────────────────────────────────────────────────────────────────
  router.post(
    '/redeem-receipt',
    authenticateFirebaseToken,
    async (req: AuthenticatedRequest, res: Response): Promise<void> => {
      try {
        const uid = req.user?.uid;
        if (!uid) {
          res.status(401).json({ success: false, code: 'UNAUTHENTICATED' });
          return;
        }

        const { receiptToken } = req.body || {};
        if (!receiptToken || typeof receiptToken !== 'string') {
          res.status(400).json({ success: false, code: 'MISSING_RECEIPT_TOKEN' });
          return;
        }

        let payload;
        try {
          payload = deps.receiptService.verifySignedReceipt(receiptToken, uid);
        } catch (err: any) {
          res.status(403).json({ success: false, code: 'INVALID_RECEIPT_SIGNATURE', message: err.message });
          return;
        }

        // Phase 3C4: Authoritative atomic one-time redemption check
        const redemptionOutcome = await db.runTransaction(async (tx) => {
          const redRef = db.collection('biometric_receipt_redemptions').doc(payload.oneTimeRedemptionNonce);
          const snap = await tx.get(redRef);
          if (snap.exists) {
            return { alreadyRedeemed: true };
          }
          tx.set(redRef, {
            nonce: payload.oneTimeRedemptionNonce,
            uid,
            enrollmentId: payload.enrollmentId,
            operationId: payload.operationId,
            redeemedAtMs: Date.now(),
          });
          return { alreadyRedeemed: false };
        });

        if (redemptionOutcome.alreadyRedeemed) {
          res.status(409).json({
            success: false,
            code: 'RECEIPT_ALREADY_REDEEMED',
            message: 'This enrollment receipt has already been redeemed.',
          });
          return;
        }

        res.status(200).json({
          success: true,
          redeemed: true,
          enrollmentId: payload.enrollmentId,
          enrollmentVersion: payload.enrollmentVersion,
        });
      } catch (err: any) {
        res.status(500).json({ success: false, code: 'REDEMPTION_ERROR', message: err.message });
      }
    }
  );

  return router;
}
