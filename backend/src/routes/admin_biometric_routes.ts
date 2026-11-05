// backend/src/routes/admin_biometric_routes.ts
/**
 * Admin Biometric Operations & Manual Review Queue API (Gate G-08).
 *
 * Implements strict RBAC via `biometric_compliance_officer` custom claims,
 * idempotency key enforcement, and non-destructive duplicate quarantine
 * preserving alternate KYC eligibility (remediating irreversible shredding).
 */

import { Router, Request, Response, NextFunction } from 'express';
import admin from 'firebase-admin';
import { FirestoreBiometricRepository } from '../services/firestore_biometric_repository';

export interface AuthenticatedAdminRequest extends Request {
  officerUid?: string;
  officerEmail?: string;
  customClaims?: Record<string, any>;
}

/**
 * Middleware: Enforces `biometric_compliance_officer` custom claim on Firebase Auth token.
 */
export async function requireBiometricComplianceOfficer(
  req: AuthenticatedAdminRequest,
  res: Response,
  next: NextFunction
): Promise<void> {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    res.status(401).json({
      success: false,
      error: 'UNAUTHORIZED_MISSING_TOKEN',
      message: 'Bearer authorization token is required for admin biometric operations.',
    });
    return;
  }

  const token = authHeader.split('Bearer ')[1].trim();

  try {
    const decoded = await admin.auth().verifyIdToken(token);
    const isComplianceOfficer =
      decoded.biometric_compliance_officer === true ||
      (decoded.role === 'admin' && decoded.admin_role === 'compliance_officer');

    if (!isComplianceOfficer) {
      res.status(403).json({
        success: false,
        error: 'FORBIDDEN_COMPLIANCE_OFFICER_CLAIM_REQUIRED',
        message: 'Caller lacks the biometric_compliance_officer custom claim.',
      });
      return;
    }

    req.officerUid = decoded.uid;
    req.officerEmail = decoded.email;
    req.customClaims = decoded;
    next();
  } catch (err: any) {
    res.status(401).json({
      success: false,
      error: 'UNAUTHORIZED_INVALID_TOKEN',
      message: `Token verification failed: ${err.message}`,
    });
  }
}

export function createAdminBiometricRouter(): Router {
  const router = Router();
  const db = admin.firestore();

  /**
   * GET /api/admin/biometrics/duplicate-queue
   * Paginated list of accounts soft-flagged in the 0.74 <= s < 0.90 review band.
   */
  router.get(
    '/api/admin/biometrics/duplicate-queue',
    requireBiometricComplianceOfficer,
    async (req: AuthenticatedAdminRequest, res: Response) => {
      try {
        const limit = Math.min(100, Math.max(1, Number(req.query.limit) || 25));
        const snapshot = await db
          .collection('biometric_review_queue')
          .where('status', '==', 'PENDING_REVIEW')
          .orderBy('createdAt', 'desc')
          .limit(limit)
          .get();

        const items = snapshot.docs.map((doc) => {
          const d = doc.data();
          return {
            reviewId: doc.id,
            claimantUidMasked: maskIdentifier(d.claimantUid),
            matchedUidMasked: maskIdentifier(d.matchedUid),
            similarityScore: Number(Number(d.similarityScore).toFixed(4)),
            createdAt: d.createdAt,
          };
        });

        return res.status(200).json({ count: items.length, queue: items });
      } catch (err: any) {
        return res.status(500).json({ error: err.message });
      }
    }
  );

  /**
   * POST /api/admin/biometrics/review-decision
   * Resolves a flagged duplicate via:
   * - APPROVE_GENUINE: Whitelists distinct pair, activates account.
   * - QUARANTINE_DUPLICATE_SUSPICION: Non-destructive quarantine preserving alternate KYC.
   *
   * Idempotency is strictly enforced via `Idempotency-Key` header or body field.
   */
  router.post(
    '/api/admin/biometrics/review-decision',
    requireBiometricComplianceOfficer,
    async (req: AuthenticatedAdminRequest, res: Response) => {
      const idempotencyKey =
        (req.headers['idempotency-key'] as string) ||
        (req.body && req.body.idempotencyKey);

      if (!idempotencyKey || typeof idempotencyKey !== 'string' || idempotencyKey.trim().length < 8) {
        return res.status(400).json({
          error: 'MISSING_IDEMPOTENCY_KEY',
          message: 'An Idempotency-Key header or field of at least 8 characters is mandatory.',
        });
      }

      const { reviewId, action, officerNotes } = req.body ?? {};
      const officerUid = req.officerUid || 'admin_compliance_officer';

      const validActions = ['APPROVE_GENUINE', 'QUARANTINE_DUPLICATE_SUSPICION', 'CONFIRM_FRAUD'];
      if (
        typeof reviewId !== 'string' ||
        !reviewId.trim() ||
        !validActions.includes(action) ||
        typeof officerNotes !== 'string' ||
        officerNotes.trim().length < 5
      ) {
        return res.status(400).json({
          error: 'INVALID_REVIEW_DECISION_PAYLOAD',
          message: 'Payload must specify valid reviewId, supported action, and officerNotes (min 5 chars).',
        });
      }

      const idempotencyRef = db.collection('biometric_admin_idempotency').doc(idempotencyKey);
      const reviewRef = db.collection('biometric_review_queue').doc(reviewId);

      try {
        const result = await db.runTransaction(async (tx) => {
          // 1. Idempotency Check
          const idempDoc = await tx.get(idempotencyRef);
          if (idempDoc.exists) {
            const data = idempDoc.data()!;
            return {
              isIdempotentReplay: true,
              statusCode: data.statusCode || 200,
              responseBody: data.responseBody,
            };
          }

          // 2. Review Record Verification
          const reviewSnap = await tx.get(reviewRef);
          if (!reviewSnap.exists) {
            return { errorStatus: 404, errorCode: 'REVIEW_ITEM_NOT_FOUND' };
          }

          const reviewData = reviewSnap.data()!;
          if (reviewData.status !== 'PENDING_REVIEW') {
            return { errorStatus: 409, errorCode: 'REVIEW_ALREADY_RESOLVED', details: reviewData.status };
          }

          const claimantUid: string = reviewData.claimantUid;
          const matchedUid: string = reviewData.matchedUid;
          const nowIso = new Date().toISOString();

          let resolutionOutcome = action;

          if (action === 'APPROVE_GENUINE') {
            // 1. Whitelist the distinct pair in cleared distinct pairs and whitelisted pairs
            const pairKey = [claimantUid, matchedUid].sort().join('__');
            const pairData = {
              uidA: claimantUid,
              uidB: matchedUid,
              approvedBy: officerUid,
              officerNotes,
              createdAt: nowIso,
            };
            tx.set(db.collection('biometric_cleared_distinct_pairs').doc(pairKey), pairData);
            tx.set(db.collection('biometric_whitelisted_pairs').doc(pairKey), pairData);

            // 2. Activate worker template and user record
            tx.update(db.collection('biometric_vault').doc(claimantUid), {
              status: 'active',
              biometricEnrollmentStatus: 'enrolled',
              updatedAt: nowIso,
            });
            tx.update(db.collection('users').doc(claimantUid), {
              accountStatus: 'active',
              biometricEnrollmentStatus: 'enrolled',
              faceVerified: true,
              biometricReviewPending: false,
              alternateVerificationEligible: false,
              updatedAt: nowIso,
            });

            // 3. Immutable audit ledger record
            tx.set(db.collection('biometric_audit_ledger').doc(), {
              eventType: 'ADMIN_WHITELIST_PAIR',
              reviewId,
              claimantUidMasked: maskIdentifier(claimantUid),
              matchedUidMasked: maskIdentifier(matchedUid),
              officerUid,
              officerNotes,
              timestamp: nowIso,
            });

            tx.update(reviewRef, {
              status: 'APPROVED',
              resolvedBy: officerUid,
              officerNotes,
              resolvedAt: nowIso,
            });
          } else {
            // Non-destructive quarantine: preserve template for forensics, route to alternate KYC
            resolutionOutcome = 'QUARANTINED_DUPLICATE_SUSPICION';

            tx.update(db.collection('biometric_vault').doc(claimantUid), {
              status: 'quarantined',
              quarantineReason: 'DUPLICATE_SUSPICION',
              quarantinedBy: officerUid,
              quarantinedAt: nowIso,
              updatedAt: nowIso,
            });

            tx.update(db.collection('users').doc(claimantUid), {
              accountStatus: 'quarantined_duplicate_suspicion',
              biometricEnrollmentStatus: 'quarantined',
              alternateVerificationEligible: true, // Worker can verify via document / alternate KYC
              reEnrollmentRequired: false,
              biometricReviewPending: false,
              quarantineNotes: officerNotes,
              updatedAt: nowIso,
            });

            tx.set(db.collection('biometric_audit_ledger').doc(), {
              eventType: 'ADMIN_QUARANTINE_DUPLICATE_SUSPICION',
              reviewId,
              claimantUidMasked: maskIdentifier(claimantUid),
              matchedUidMasked: maskIdentifier(matchedUid),
              officerUid,
              officerNotes,
              timestamp: nowIso,
            });

            tx.update(reviewRef, {
              status: 'QUARANTINED_DUPLICATE_SUSPICION',
              resolvedBy: officerUid,
              officerNotes,
              resolvedAt: nowIso,
            });
          }

          const responsePayload = {
            success: true,
            reviewId,
            resolution: resolutionOutcome,
            claimantUidMasked: maskIdentifier(claimantUid),
            resolvedAt: nowIso,
          };

          // Record Idempotency Result
          tx.set(idempotencyRef, {
            idempotencyKey,
            officerUid,
            reviewId,
            statusCode: 200,
            responseBody: responsePayload,
            createdAt: nowIso,
          });

          return { isIdempotentReplay: false, responseBody: responsePayload };
        });

        if ('errorStatus' in result) {
          return res.status(result.errorStatus!).json({
            error: result.errorCode,
            details: (result as any).details,
          });
        }

        FirestoreBiometricRepository.invalidateCache?.(req.body.reviewId);

        return res.status(200).json(result.responseBody);
      } catch (err: any) {
        return res.status(500).json({ error: err.message });
      }
    }
  );

  return router;
}

function maskIdentifier(id: string): string {
  if (!id || id.length <= 6) return '***';
  return `${id.slice(0, 3)}***${id.slice(-3)}`;
}
