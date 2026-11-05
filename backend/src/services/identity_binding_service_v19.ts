import admin from 'firebase-admin';
import {
  PersonIdentityDomainV19,
  PersonIdentityRecordV19,
  MarketplaceRole,
  RoleLinkingPolicy,
  StepUpVerificationProof,
} from '../models/person_identity_v19';
import { AuditService } from './audit_service';
import { StepUpProofServiceV19 } from './step_up_proof_service_v19';

export interface LinkRoleResult {
  success: boolean;
  person: PersonIdentityRecordV19;
  roleLinked: MarketplaceRole;
  auditEventId?: string;
}

export class IdentityBindingServiceV19 {
  private static readonly PERSON_COLLECTION = 'person_identities';
  private static readonly USERS_COLLECTION = 'users';

  /**
   * Protected fields that ordinary clients are strictly forbidden from writing or updating.
   * Enforces Phase 4 database authorization invariants.
   */
  public static readonly PROTECTED_CLIENT_FIELDS = new Set<string>([
    'personId',
    'primaryAuthUid',
    'linkedAuthUids',
    'activeBiometricEnrollmentId',
    'activeTemplateGeneration',
    'biometricLifecycleStatus',
    'faceVerified',
    'faceEnrolled',
    'accountStatus',
    'approvedBy',
    'approvedAt',
    'rejectedBy',
  ]);

  /**
   * Asserts that an incoming client request does not attempt to directly modify
   * protected person-ownership or biometric-lifecycle fields.
   */
  public static assertNoClientWritableProtectedFields(
    payload: Record<string, any>
  ): void {
    if (!payload || typeof payload !== 'object') return;
    const attemptedKeys = Object.keys(payload);
    for (const key of attemptedKeys) {
      if (this.PROTECTED_CLIENT_FIELDS.has(key)) {
        throw new Error(
          `SECURITY_VIOLATION: Direct client modification of protected field '${key}' is forbidden.`
        );
      }
    }
  }

  /**
   * Idempotently retrieves or initializes the authoritative PersonIdentityRecord
   * bound to an authenticated Firebase UID inside a pure Firestore transaction.
   */
  public static async getOrInitPersonIdentity(params: {
    db: admin.firestore.Firestore;
    authUid: string;
    initialRole: MarketplaceRole;
    initialRoleProfileId?: string;
    nowMs?: number;
  }): Promise<PersonIdentityRecordV19> {
    const {
      db,
      authUid,
      initialRole,
      initialRoleProfileId = authUid,
      nowMs = Date.now(),
    } = params;

    return db.runTransaction(async (tx) => {
      const userRef = db.collection(this.USERS_COLLECTION).doc(authUid);
      const userSnap = await tx.get(userRef);

      if (!userSnap.exists) {
        throw new Error(
          `USER_DOC_NOT_FOUND: Cannot initialize person identity for non-existent user /users/${authUid}.`
        );
      }

      const userData = userSnap.data() || {};
      const existingPersonId = userData.personId as string | undefined;

      if (existingPersonId && /^prs_[0-9a-f]{32}$/.test(existingPersonId)) {
        const personRef = db
          .collection(this.PERSON_COLLECTION)
          .doc(existingPersonId);
        const personSnap = await tx.get(personRef);
        if (personSnap.exists) {
          return personSnap.data() as PersonIdentityRecordV19;
        }
      }

      // Mint fresh opaque personId (never derived from biometric vectors)
      const freshPersonId = PersonIdentityDomainV19.mintOpaquePersonId();
      const freshPerson: PersonIdentityRecordV19 = {
        personId: freshPersonId,
        primaryAuthUid: authUid,
        linkedAuthUids: [authUid],
        workerId: initialRole === 'WORKER' ? initialRoleProfileId : null,
        hirerId: initialRole === 'HIRER' ? initialRoleProfileId : null,
        activeBiometricEnrollmentId: null,
        activeTemplateGeneration: 0,
        biometricLifecycleStatus: 'FACE_ENROLLMENT_REQUIRED',
        createdAtMs: nowMs,
        updatedAtMs: nowMs,
      };

      const personRef = db.collection(this.PERSON_COLLECTION).doc(freshPersonId);
      tx.set(personRef, freshPerson);
      tx.update(userRef, {
        personId: freshPersonId,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      return freshPerson;
    });
  }

  /**
   * Links a second marketplace role (Worker <-> Hirer) to an existing personId.
   *
   * CRITICAL SECURITY INVARIANT (Phase 2 & Phase 3):
   * 1. A similarity match alone NEVER authorizes account or role linking.
   * 2. An OTP to a newly entered, unverified phone NEVER authorizes linking to an existing person.
   * 3. Linking requires existing-account proof of control (session ownership or OTP to the
   *    PREVIOUSLY REGISTERED phone on record for targetPersonId).
   */
  public static async linkAuthorizedSecondRole(params: {
    db: admin.firestore.Firestore;
    callerUid: string;
    targetPersonId: string;
    newRole: MarketplaceRole;
    newRoleProfileId: string;
    rolePolicy: RoleLinkingPolicy;
    stepUpProof: StepUpVerificationProof;
    nowMs?: number;
  }): Promise<LinkRoleResult> {
    const {
      db,
      callerUid,
      targetPersonId,
      newRole,
      newRoleProfileId,
      rolePolicy,
      stepUpProof,
      nowMs = Date.now(),
    } = params;

    PersonIdentityDomainV19.assertValidOpaquePersonId(targetPersonId);

    // Strict pre-transaction proof-of-control validation (Phase 2)
    if (!stepUpProof.verified) {
      throw new Error(
        'UNAUTHORIZED_PROOF_OF_CONTROL: Step-up proof of control is required before role linking.'
      );
    }
    if (stepUpProof.verifiedTargetPersonId !== targetPersonId) {
      throw new Error(
        'PROOF_MISMATCH: Step-up verification target does not match target personId.'
      );
    }

    return db.runTransaction(async (tx) => {
      // 1. Transaction Read First
      const personRef = db
        .collection(this.PERSON_COLLECTION)
        .doc(targetPersonId);
      const personSnap = await tx.get(personRef);

      if (!personSnap.exists) {
        throw new Error(
          `PERSON_NOT_FOUND: Authoritative person identity /person_identities/${targetPersonId} does not exist.`
        );
      }

      const currentPerson = personSnap.data() as PersonIdentityRecordV19;

      // 2. Validate caller or proof relationship
      const isCallerAlreadyLinked =
        currentPerson.linkedAuthUids.includes(callerUid);

      if (!isCallerAlreadyLinked && stepUpProof.method === 'EXISTING_ACCOUNT_SIGN_IN') {
        throw new Error(
          'UNAUTHORIZED_SESSION: Caller UID is not an authorized linked credential of the target person.'
        );
      }

      // 2b. Server-Authoritative Step-Up Proof Verification and Atomic Consumption (V19.2)
      if (stepUpProof.proofId) {
        const verifiedRecord = await StepUpProofServiceV19.verifyAndConsumeInTransaction({
          tx,
          db,
          proofId: stepUpProof.proofId,
          callerUid,
          targetPersonId,
          nowMs,
        });
        stepUpProof.method = verifiedRecord.method;
      } else if (!isCallerAlreadyLinked) {
        throw new Error(
          'FORGED_PROOF_REJECTED: Untrusted client-supplied verified:true without valid server proofId is forbidden.'
        );
      }

      // 3. Delegate to Domain Model state transitions
      const updatedPerson = PersonIdentityDomainV19.linkAuthorizedRoleToPerson({
        person: currentPerson,
        newRole,
        newRoleProfileId,
        stepUpProof,
        rolePolicy,
        nowMs,
      });

      // If callerUid is a new authorized credential passing OTP to the registered phone,
      // atomically append it to linkedAuthUids
      if (!updatedPerson.linkedAuthUids.includes(callerUid)) {
        updatedPerson.linkedAuthUids.push(callerUid);
      }

      // 4. Atomic Transaction Writes
      tx.set(personRef, updatedPerson);

      const callerUserRef = db.collection(this.USERS_COLLECTION).doc(callerUid);
      tx.update(callerUserRef, {
        personId: targetPersonId,
        role: newRole.toLowerCase(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      return {
        success: true,
        person: updatedPerson,
        roleLinked: newRole,
      };
    });
  }

  /**
   * Safely links an additional Firebase Auth UID to an existing personId.
   * Enforces:
   * 1. Target person exists.
   * 2. New UID is not already claimed by a conflicting personId.
   * 3. Existing account control verified.
   */
  public static async linkSecondaryAuthUid(params: {
    db: admin.firestore.Firestore;
    existingPersonId: string;
    newAuthUid: string;
    stepUpProof: StepUpVerificationProof;
    nowMs?: number;
  }): Promise<PersonIdentityRecordV19> {
    const {
      db,
      existingPersonId,
      newAuthUid,
      stepUpProof,
      nowMs = Date.now(),
    } = params;

    PersonIdentityDomainV19.assertValidOpaquePersonId(existingPersonId);

    if (
      !stepUpProof.verified ||
      stepUpProof.verifiedTargetPersonId !== existingPersonId
    ) {
      throw new Error(
        'UNAUTHORIZED_IDENTITY_LINKING: Valid proof of control over the existing identity is required.'
      );
    }

    return db.runTransaction(async (tx) => {
      const personRef = db
        .collection(this.PERSON_COLLECTION)
        .doc(existingPersonId);
      const newUserRef = db.collection(this.USERS_COLLECTION).doc(newAuthUid);

      const personSnap = await tx.get(personRef);
      const newUserSnap = await tx.get(newUserRef);

      if (!personSnap.exists) {
        throw new Error(
          `TARGET_PERSON_NOT_FOUND: /person_identities/${existingPersonId} does not exist.`
        );
      }

      const personData = personSnap.data() as PersonIdentityRecordV19;

      // 1b. Server-Authoritative Step-Up Proof Verification and Atomic Consumption (V19.2)
      if (stepUpProof.proofId) {
        const verifiedRecord = await StepUpProofServiceV19.verifyAndConsumeInTransaction({
          tx,
          db,
          proofId: stepUpProof.proofId,
          callerUid: newAuthUid,
          targetPersonId: existingPersonId,
          nowMs,
        });
        stepUpProof.method = verifiedRecord.method;
      } else {
        throw new Error(
          'FORGED_PROOF_REJECTED: Untrusted client-supplied verified:true without valid server proofId is forbidden.'
        );
      }

      if (newUserSnap.exists) {
        const newUserData = newUserSnap.data() || {};
        const existingBoundPerson = newUserData.personId as string | undefined;
        if (
          existingBoundPerson &&
          existingBoundPerson !== existingPersonId
        ) {
          throw new Error(
            'CONFLICTING_IDENTITY_BINDING: New UID is already bound to a different person identity.'
          );
        }
      }

      if (!personData.linkedAuthUids.includes(newAuthUid)) {
        personData.linkedAuthUids.push(newAuthUid);
        personData.updatedAtMs = nowMs;
        tx.update(personRef, {
          linkedAuthUids: personData.linkedAuthUids,
          updatedAtMs: nowMs,
        });
      }

      if (newUserSnap.exists) {
        tx.update(newUserRef, {
          personId: existingPersonId,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      return personData;
    });
  }
}
