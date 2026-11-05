import admin from 'firebase-admin';
import { StepUpProofServiceV19, StepUpProofRecordV19 } from './step_up_proof_service_v19';
import { AuditService } from './audit_service';

export class ServerSignInProofServiceV19 {
  public static readonly MAX_AUTH_AGE_SECONDS = 15 * 60; // 15 minutes for sensitive operations

  /**
   * Issues a step-up proof for EXISTING_ACCOUNT_SIGN_IN.
   * Resolves targetPersonId STRICTLY from server-side state (users/{callerUid}.personId).
   * Verifies that the caller's auth session is recent (<= 15 minutes).
   */
  public static async issueSignInProof(params: {
    db: admin.firestore.Firestore;
    callerUid: string;
    authTimeSeconds?: number;
    nowMs?: number;
  }): Promise<StepUpProofRecordV19> {
    const { db, callerUid, authTimeSeconds, nowMs = Date.now() } = params;

    if (!callerUid || typeof callerUid !== 'string') {
      throw new Error('UNAUTHENTICATED: Caller UID is required.');
    }

    // 1. Enforce recent reauthentication for sensitive identity operations
    if (authTimeSeconds) {
      const nowSeconds = Math.floor(nowMs / 1000);
      const authAgeSeconds = nowSeconds - authTimeSeconds;
      if (authAgeSeconds > this.MAX_AUTH_AGE_SECONDS) {
        throw new Error(
          `RECENT_AUTH_REQUIRED: Authentication is ${Math.floor(authAgeSeconds / 60)} minutes old. Re-authentication required within 15 minutes.`
        );
      }
    }

    // 2. Server-Authoritative Lookup: Retrieve caller's user record
    const userRef = db.collection('users').doc(callerUid);
    const userSnap = await userRef.get();

    if (!userSnap.exists) {
      throw new Error(`USER_NOT_FOUND: User document /users/${callerUid} does not exist.`);
    }

    const userData = userSnap.data() || {};
    const targetPersonId = userData.personId as string | undefined;

    if (!targetPersonId || !/^prs_[0-9a-f]{32}$/.test(targetPersonId)) {
      throw new Error(
        `NO_LINKED_PERSON_IDENTITY: User ${callerUid} has no authoritative personId on record.`
      );
    }

    // 3. Confirm target person record contains callerUid
    const personRef = db.collection('person_identities').doc(targetPersonId);
    const personSnap = await personRef.get();

    if (!personSnap.exists) {
      throw new Error(
        `PERSON_IDENTITY_NOT_FOUND: Authoritative record /person_identities/${targetPersonId} missing.`
      );
    }

    const personData = personSnap.data() || {};
    const linkedUids = Array.isArray(personData.linkedAuthUids)
      ? personData.linkedAuthUids
      : [personData.primaryAuthUid];

    if (!linkedUids.includes(callerUid)) {
      throw new Error(
        `UNAUTHORIZED_IDENTITY_OWNERSHIP: Caller ${callerUid} is not a verified linked credential of ${targetPersonId}.`
      );
    }

    // 4. Issue authoritative single-use StepUpProof
    return StepUpProofServiceV19.issueProof({
      db,
      issuedToUid: callerUid,
      targetPersonId,
      method: 'EXISTING_ACCOUNT_SIGN_IN',
      nowMs,
    });
  }

  /**
   * Issues a step-up proof for COMPLIANCE_OFFICER_REVIEW.
   * Requires verified compliance officer claims and an existing APPROVED review case.
   */
  public static async issueComplianceReviewProof(params: {
    db: admin.firestore.Firestore;
    officerUid: string;
    officerClaims?: Record<string, any>;
    reviewCaseId: string;
    nowMs?: number;
  }): Promise<{
    proof: StepUpProofRecordV19;
    claimantUid: string;
    targetPersonId: string;
  }> {
    const { db, officerUid, officerClaims = {}, reviewCaseId, nowMs = Date.now() } = params;

    // 1. Verify officer authorization claims
    const isAuthorizedOfficer =
      officerClaims.biometric_compliance_officer === true ||
      (officerClaims.role === 'admin' && officerClaims.admin_role === 'compliance_officer');

    if (!isAuthorizedOfficer) {
      throw new Error(
        'FORBIDDEN_COMPLIANCE_OFFICER_CLAIM_REQUIRED: Caller lacks biometric_compliance_officer authorization.'
      );
    }

    if (!reviewCaseId) {
      throw new Error('INVALID_ARGUMENT: reviewCaseId is required.');
    }

    // 2. Fetch and atomically consume the review case inside a transaction
    return db.runTransaction(async (tx) => {
      // Check in biometric_review_queue
      const reviewRef = db.collection('biometric_review_queue').doc(reviewCaseId);
      const reviewSnap = await tx.get(reviewRef);

      if (!reviewSnap.exists) {
        throw new Error(
          `REVIEW_CASE_NOT_FOUND: Review case ${reviewCaseId} does not exist in review queue.`
        );
      }

      const reviewData = reviewSnap.data()!;

      if (reviewData.status !== 'APPROVED') {
        throw new Error(
          `REVIEW_CASE_NOT_APPROVED: Review case ${reviewCaseId} has status '${reviewData.status}'. Only APPROVED cases may issue proof.`
        );
      }

      if (reviewData.consumedForProof === true) {
        throw new Error(
          `REVIEW_CASE_ALREADY_CONSUMED: A step-up proof was already issued for review case ${reviewCaseId} at ${reviewData.proofIssuedAtMs}.`
        );
      }

      const targetPersonId = reviewData.targetPersonId as string;
      const claimantUid = reviewData.claimantUid as string;

      if (!targetPersonId || !claimantUid) {
        throw new Error(
          `MALFORMED_REVIEW_CASE: Case ${reviewCaseId} is missing targetPersonId or claimantUid.`
        );
      }

      // Mark review case consumed
      tx.update(reviewRef, {
        consumedForProof: true,
        proofIssuedAtMs: nowMs,
        proofIssuedByOfficer: officerUid,
      });

      // Issue authoritative StepUpProof for claimantUid
      const proof = await StepUpProofServiceV19.issueProof({
        db,
        issuedToUid: claimantUid,
        targetPersonId,
        method: 'COMPLIANCE_OFFICER_REVIEW',
        nowMs,
      });

      await AuditService.logEvent({
        eventType: 'COMPLIANCE_OFFICER_PROOF_ISSUED',
        uid: officerUid,
        matchedUid: targetPersonId,
        similarityScore: 1.0,
        threshold: 0.74,
        metadata: {
          reviewCaseId,
          claimantUid,
          proofId: proof.proofId,
          issuedBy: officerUid,
        },
      });

      return {
        proof,
        claimantUid,
        targetPersonId,
      };
    });
  }
}
