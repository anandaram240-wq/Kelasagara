import { Router, Request, Response } from 'express';
import admin from 'firebase-admin';
import { IdentityBindingServiceV19 } from '../services/identity_binding_service_v19';
import { RegisteredPhoneOtpServiceV19 } from '../services/registered_phone_otp_service_v19';
import { ServerSignInProofServiceV19 } from '../services/server_sign_in_proof_service_v19';
import { StepUpProofServiceV19 } from '../services/step_up_proof_service_v19';
import { requireBiometricComplianceOfficer } from './admin_biometric_routes';

export interface AuthenticatedUserRequest extends Request {
  user?: {
    uid: string;
    auth_time?: number;
    email?: string;
    phone_number?: string;
    [key: string]: any;
  };
}

/**
 * Middleware: Authenticates Firebase ID Token and extracts user identity and auth_time.
 */
export async function authenticateFirebaseUser(
  req: AuthenticatedUserRequest,
  res: Response,
  next: Function
): Promise<void> {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    res.status(401).json({
      success: false,
      error: 'UNAUTHORIZED_MISSING_TOKEN',
      message: 'Bearer authorization token is required.',
    });
    return;
  }

  const token = authHeader.split('Bearer ')[1].trim();
  try {
    const decoded = await admin.auth().verifyIdToken(token);
    req.user = decoded;
    next();
  } catch (err: any) {
    res.status(401).json({
      success: false,
      error: 'UNAUTHORIZED_INVALID_TOKEN',
      message: `Token verification failed: ${err.message}`,
    });
  }
}

export function createIdentityRouter(db: admin.firestore.Firestore = admin.firestore()): Router {
  const router = Router();

  /**
   * POST /api/identity/request-registered-phone-otp
   * Dispatches OTP to the registered mobile number on record for targetPersonId.
   */
  router.post(
    '/request-registered-phone-otp',
    authenticateFirebaseUser,
    async (req: AuthenticatedUserRequest, res: Response) => {
      try {
        const callerUid = req.user!.uid;
        const { targetPersonId } = req.body || {};

        if (!targetPersonId) {
          return res.status(400).json({
            success: false,
            error: 'MISSING_TARGET_PERSON_ID',
            message: 'targetPersonId is required.',
          });
        }

        const result = await RegisteredPhoneOtpServiceV19.requestOtpForRegisteredPhone({
          db,
          callerUid,
          targetPersonId,
        });

        return res.status(200).json({
          success: true,
          data: result,
          serverTimestamp: new Date().toISOString(),
        });
      } catch (err: any) {
        return res.status(400).json({
          success: false,
          error: 'REQUEST_OTP_FAILED',
          message: err.message,
        });
      }
    }
  );

  /**
   * POST /api/identity/verify-registered-phone-otp
   * Validates submitted OTP and issues authoritative StepUpProofRecordV19.
   */
  router.post(
    '/verify-registered-phone-otp',
    authenticateFirebaseUser,
    async (req: AuthenticatedUserRequest, res: Response) => {
      try {
        const callerUid = req.user!.uid;
        const { sessionId, code } = req.body || {};

        if (!sessionId || !code) {
          return res.status(400).json({
            success: false,
            error: 'MISSING_OTP_ARGUMENTS',
            message: 'sessionId and code are required.',
          });
        }

        const proof = await RegisteredPhoneOtpServiceV19.verifyOtpAndIssueProof({
          db,
          sessionId,
          callerUid,
          code: String(code).trim(),
        });

        return res.status(200).json({
          success: true,
          data: {
            proofId: proof.proofId,
            method: proof.method,
            targetPersonId: proof.targetPersonId,
            expiresAtMs: proof.expiresAtMs,
          },
          serverTimestamp: new Date().toISOString(),
        });
      } catch (err: any) {
        return res.status(400).json({
          success: false,
          error: 'VERIFY_OTP_FAILED',
          message: err.message,
        });
      }
    }
  );

  /**
   * POST /api/identity/issue-sign-in-proof
   * Issues a step-up proof for an actively authenticated session (<= 15 minutes old).
   */
  router.post(
    '/issue-sign-in-proof',
    authenticateFirebaseUser,
    async (req: AuthenticatedUserRequest, res: Response) => {
      try {
        const callerUid = req.user!.uid;
        const authTimeSeconds = req.user!.auth_time;

        const proof = await ServerSignInProofServiceV19.issueSignInProof({
          db,
          callerUid,
          authTimeSeconds,
        });

        return res.status(200).json({
          success: true,
          data: {
            proofId: proof.proofId,
            method: proof.method,
            targetPersonId: proof.targetPersonId,
            expiresAtMs: proof.expiresAtMs,
          },
          serverTimestamp: new Date().toISOString(),
        });
      } catch (err: any) {
        const status = err.message.includes('RECENT_AUTH_REQUIRED') ? 401 : 400;
        return res.status(status).json({
          success: false,
          error: 'SIGN_IN_PROOF_FAILED',
          message: err.message,
        });
      }
    }
  );

  /**
   * POST /api/identity/link-second-role
   * Links a second marketplace role (Worker <-> Hirer) using verified proofId.
   */
  router.post(
    '/link-second-role',
    authenticateFirebaseUser,
    async (req: AuthenticatedUserRequest, res: Response) => {
      try {
        const callerUid = req.user!.uid;
        const { proofId, targetPersonId, newRole, newRoleProfileId, rolePolicy } = req.body || {};

        // Reject client-injected protected fields
        IdentityBindingServiceV19.assertNoClientWritableProtectedFields(req.body);

        if (!proofId || !targetPersonId || !newRole || !newRoleProfileId) {
          return res.status(400).json({
            success: false,
            error: 'MISSING_LINK_ARGUMENTS',
            message: 'proofId, targetPersonId, newRole, and newRoleProfileId are required.',
          });
        }

        const result = await IdentityBindingServiceV19.linkAuthorizedSecondRole({
          db,
          callerUid,
          targetPersonId,
          newRole,
          newRoleProfileId,
          rolePolicy: rolePolicy || 'ALLOW_DUAL_ROLE_WITH_STEP_UP_AUTH',
          stepUpProof: {
            verified: true,
            proofId,
            method: 'EXISTING_ACCOUNT_SIGN_IN', // Validated against proof record
            verifiedTargetPersonId: targetPersonId,
            verifiedAtMs: Date.now(),
          },
        });

        return res.status(200).json({
          success: true,
          data: {
            personId: result.person.personId,
            roleLinked: result.roleLinked,
            workerId: result.person.workerId,
            hirerId: result.person.hirerId,
          },
          serverTimestamp: new Date().toISOString(),
        });
      } catch (err: any) {
        return res.status(400).json({
          success: false,
          error: 'ROLE_LINK_FAILED',
          message: err.message,
        });
      }
    }
  );

  /**
   * POST /api/identity/link-secondary-uid
   * Links a new Firebase Auth UID to an existing person identity using verified proofId.
   */
  router.post(
    '/link-secondary-uid',
    authenticateFirebaseUser,
    async (req: AuthenticatedUserRequest, res: Response) => {
      try {
        const newAuthUid = req.user!.uid;
        const { proofId, existingPersonId } = req.body || {};

        IdentityBindingServiceV19.assertNoClientWritableProtectedFields(req.body);

        if (!proofId || !existingPersonId) {
          return res.status(400).json({
            success: false,
            error: 'MISSING_LINK_ARGUMENTS',
            message: 'proofId and existingPersonId are required.',
          });
        }

        const person = await IdentityBindingServiceV19.linkSecondaryAuthUid({
          db,
          existingPersonId,
          newAuthUid,
          stepUpProof: {
            verified: true,
            proofId,
            method: 'REGISTERED_PHONE_OTP',
            verifiedTargetPersonId: existingPersonId,
            verifiedAtMs: Date.now(),
          },
        });

        return res.status(200).json({
          success: true,
          data: {
            personId: person.personId,
            linkedAuthUids: person.linkedAuthUids,
          },
          serverTimestamp: new Date().toISOString(),
        });
      } catch (err: any) {
        return res.status(400).json({
          success: false,
          error: 'SECONDARY_UID_LINK_FAILED',
          message: err.message,
        });
      }
    }
  );

  /**
   * POST /api/admin/identity/issue-compliance-proof
   * Compliance officer endpoint to issue a proof following manual out-of-band verification.
   */
  router.post(
    '/compliance/issue-proof',
    requireBiometricComplianceOfficer,
    async (req: any, res: Response) => {
      try {
        const officerUid = req.officerUid!;
        const officerClaims = req.customClaims || {};
        const { reviewCaseId } = req.body || {};

        if (!reviewCaseId) {
          return res.status(400).json({
            success: false,
            error: 'MISSING_REVIEW_CASE_ID',
            message: 'reviewCaseId is required.',
          });
        }

        const result = await ServerSignInProofServiceV19.issueComplianceReviewProof({
          db,
          officerUid,
          officerClaims,
          reviewCaseId,
        });

        return res.status(200).json({
          success: true,
          data: {
            proofId: result.proof.proofId,
            claimantUid: result.claimantUid,
            targetPersonId: result.targetPersonId,
            expiresAtMs: result.proof.expiresAtMs,
          },
          serverTimestamp: new Date().toISOString(),
        });
      } catch (err: any) {
        const status = err.message.includes('FORBIDDEN') ? 403 : 400;
        return res.status(status).json({
          success: false,
          error: 'COMPLIANCE_PROOF_ISSUANCE_FAILED',
          message: err.message,
        });
      }
    }
  );

  return router;
}
