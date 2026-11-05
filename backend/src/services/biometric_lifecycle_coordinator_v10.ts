// File: backend/src/services/biometric_lifecycle_coordinator_v10.ts
import * as admin from 'firebase-admin';
import { randomUUID, randomBytes, createHash } from 'crypto';
import {
  BiometricLifecycleState,
  BiometricOperationReceiptService,
  BiometricOperationState,
  BiometricWorkflowType,
  KelasagaraAccountStatus,
  StructuredBiometricCode,
} from '../biometrics/identity_contract_v10';
import {
  CANONICAL_SFACE_SPEC_V10,
  CANONICAL_YUNET_SPEC_V10,
  CANONICAL_EMBEDDING_SPACE_V2,
  CANONICAL_PREPROCESSING_MANIFEST_V2,
  CANONICAL_MANIFEST_HASH_V2,
  CanonicalSFaceEngineV10,
} from '../biometrics/canonical_sface_engine_v10';
import {
  BiometricTemplateCryptoService,
  EncryptedTemplatePersistencePackage,
} from './biometric_template_crypto';

export interface CalibrationPolicyThresholdsV10 {
  verify1to1Min: number; // Default candidate: 0.363
  dedupCleanMax: number; // Default candidate: 0.363
  dedupAmbiguousMax: number; // Default candidate: 0.550
  dedupHardBlockMin: number; // Default candidate: 0.720
  isEmpiricallyValidatedForProduction: boolean;
}

export const DEFAULT_CANDIDATE_THRESHOLDS_V10: CalibrationPolicyThresholdsV10 = {
  verify1to1Min: 0.363,
  dedupCleanMax: 0.363,
  dedupAmbiguousMax: 0.550,
  dedupHardBlockMin: 0.720,
  isEmpiricallyValidatedForProduction: false,
};

export interface GalleryCandidateHit {
  enrollmentId: string;
  owningUid: string;
  similarity: number;
  modelIdentifier: string;
  preprocessVersion: string;
  embeddingSpaceId?: string;
  comparisonSpace?: 'SFACE_NEURAL_SPACE' | 'LEGACY_LANDMARK_SPACE';
  calibratedThreshold?: number;
  isDuplicate?: boolean;
}

export interface CompatibleGalleryIndex {
  searchTopKCompatible(params: {
    probeEmbedding128: Float32Array;
    probeEmbeddingSpaceId?: string;
    probeLandmarkVector128?: number[];
    excludeOwningUid: string;
    excludeEnrollmentId?: string | null;
    topK: number;
  }): Promise<{
    candidates: GalleryCandidateHit[];
    searchedGalleryEpoch: number;
  }>;
  confirmEnrollmentVisibleInIndex(
    enrollmentId: string,
    owningUid: string,
    embedding128: Float32Array,
    committedEpoch: number
  ): Promise<boolean>;
  removeEnrollmentFromIndex(enrollmentId: string): Promise<void>;
}

export interface WorkflowExecutionResultV10 {
  httpStatus: number;
  operationId: string;
  code: StructuredBiometricCode;
  biometricStatus: BiometricLifecycleState;
  accountStatus: KelasagaraAccountStatus;
  enrollmentId?: string | null;
  enrollmentVersion?: number;
  receiptToken?: string;
  caseReference?: string;
  matchedUid?: string;
  similarityScore?: number;
  duplicateAccountDetails?: {
    maskedUid: string;
    maskedName: string;
    maskedPhone: string;
    primarySkill: string;
    dailyRateDisplay: string;
    facialSimilarityPercent: string;
    rawCosineSimilarity: number;
  };
  idempotentReplay: boolean;
  retryable: boolean;
}

export class BiometricLifecycleCoordinatorV10 {
  private static readonly USERS_COL = 'users';
  private static readonly VAULT_COL = 'biometric_vault';
  private static readonly OPS_COL = 'biometric_operations';
  private static readonly META_COL = 'biometric_system_meta';
  private static readonly GALLERY_EPOCH_DOC = 'gallery_epoch_v10';
  private static readonly CASES_COL = 'biometric_duplicate_cases';
  private static readonly LEASE_TTL_MS = 25_000;
  private static readonly MAX_CONCURRENT_EPOCH_RETRIES = 3;

  private readonly cryptoService: BiometricTemplateCryptoService;

  constructor(
    private readonly db: admin.firestore.Firestore,
    private readonly galleryIndex: CompatibleGalleryIndex,
    private readonly receiptService: BiometricOperationReceiptService,
    private readonly thresholds: CalibrationPolicyThresholdsV10 = DEFAULT_CANDIDATE_THRESHOLDS_V10,
    cryptoService?: BiometricTemplateCryptoService
  ) {
    this.cryptoService = cryptoService ?? BiometricTemplateCryptoService.getInstance();
  }

  /**
   * WORKFLOW A: INITIAL ENROLLMENT AND 1:N DUPLICATE SCREENING
   */
  public async enrollInitial(params: {
    authenticatedUid: string;
    idempotencyKey: string;
    challengeNonce: string;
    validatedSFaceEmbedding128: Float32Array;
    probeLandmarkVector128?: number[];
    isReEnrollment?: boolean;
    nowMs?: number;
  }): Promise<WorkflowExecutionResultV10> {
    return this.executeEnrollmentOrReplacementInternal({
      ...params,
      workflowType: params.isReEnrollment ? 'AUTHORIZED_REPLACEMENT' : 'INITIAL_ENROLLMENT',
      stepUpAuthorized: params.isReEnrollment === true,
    });
  }

  /**
   * WORKFLOW C: AUTHORIZED FACE RE-ENROLLMENT
   * Preserves existing activeBiometricEnrollmentId on any failure.
   */
  public async replaceAuthorizedEnrollment(params: {
    authenticatedUid: string;
    idempotencyKey: string;
    challengeNonce: string;
    stepUpAuthorized: boolean;
    replacementReason: string;
    validatedSFaceEmbedding128: Float32Array;
    nowMs?: number;
  }): Promise<WorkflowExecutionResultV10> {
    if (!params.stepUpAuthorized) {
      return {
        httpStatus: 403,
        operationId: `unauth_${randomUUID()}`,
        code: 'UNAUTHORIZED',
        biometricStatus: 'ACTIVE',
        accountStatus: 'approved',
        idempotentReplay: false,
        retryable: false,
      };
    }
    return this.executeEnrollmentOrReplacementInternal({
      ...params,
      workflowType: 'AUTHORIZED_REPLACEMENT',
    });
  }

  private async executeEnrollmentOrReplacementInternal(params: {
    authenticatedUid: string;
    idempotencyKey: string;
    challengeNonce: string;
    workflowType: 'INITIAL_ENROLLMENT' | 'AUTHORIZED_REPLACEMENT';
    stepUpAuthorized: boolean;
    replacementReason?: string;
    validatedSFaceEmbedding128: Float32Array;
    probeLandmarkVector128?: number[];
    nowMs?: number;
  }): Promise<WorkflowExecutionResultV10> {
    const {
      authenticatedUid,
      idempotencyKey,
      challengeNonce,
      workflowType,
      validatedSFaceEmbedding128,
    } = params;

    const unitProbe = CanonicalSFaceEngineV10.extractAndNormalizeOutputTensor({
      type: 'float32',
      data: validatedSFaceEmbedding128,
    });

    const deterministicOpId = `op_${authenticatedUid}_${idempotencyKey.replace(/[^a-zA-Z0-9_-]/g, '').slice(0, 48)}`;
    const opRef = this.db.collection(BiometricLifecycleCoordinatorV10.OPS_COL).doc(deterministicOpId);
    const userRef = this.db.collection(BiometricLifecycleCoordinatorV10.USERS_COL).doc(authenticatedUid);
    const metaRef = this.db
      .collection(BiometricLifecycleCoordinatorV10.META_COL)
      .doc(BiometricLifecycleCoordinatorV10.GALLERY_EPOCH_DOC);

    // STEP 1–3: Verify account eligibility & reserve operation record atomically
    const reservation = await this.db.runTransaction(async (tx) => {
      const nowMs = params.nowMs ?? Date.now();
      const [userSnap, opSnap] = await Promise.all([
        tx.get(userRef),
        tx.get(opRef),
      ]);

      // Phase 3D2: Account existence requirement. Never default a missing user document to eligible.
      if (!userSnap.exists) {
        return {
          earlyReturn: {
            httpStatus: 404,
            operationId: deterministicOpId,
            code: 'INVALID_OPERATION_STATE' as StructuredBiometricCode,
            biometricStatus: 'UNENROLLED' as BiometricLifecycleState,
            accountStatus: 'pending_profile' as KelasagaraAccountStatus,
            idempotentReplay: false,
            retryable: false,
          },
        };
      }

      const userData = userSnap.data()!;
      const accountStatus: KelasagaraAccountStatus =
        userData.accountStatus ?? 'pending_face';
      const currentBioStatus: BiometricLifecycleState =
        userData.biometricStatus ??
        (userData.faceVerified === true ? 'ACTIVE' : 'UNENROLLED');
      const existingEnrollmentId: string | null =
        userData.activeBiometricEnrollmentId ?? null;
      const existingVersion: number = Number(userData.activeEnrollmentVersion ?? 0);

      // Phase 3D1: Immutable Request Fingerprint
      const requestFingerprint = createHash('sha256')
        .update(JSON.stringify({ authenticatedUid, workflowType, challengeNonce }))
        .digest('hex');

      // Check idempotent operation state (Part 5.4 & Phase 3D1)
      if (opSnap.exists) {
        const opData = opSnap.data()!;

        // If key was reused with a different request payload, reject conflict
        if (opData.requestFingerprint && opData.requestFingerprint !== requestFingerprint) {
          return {
            earlyReturn: {
              httpStatus: 409,
              operationId: deterministicOpId,
              code: 'INVALID_OPERATION_STATE' as StructuredBiometricCode,
              biometricStatus: currentBioStatus,
              accountStatus,
              idempotentReplay: false,
              retryable: false,
            },
          };
        }

        if (opData.state === 'COMMITTED') {
          return {
            earlyReturn: {
              httpStatus: 200,
              operationId: deterministicOpId,
              code: 'NO_MATCH' as StructuredBiometricCode,
              biometricStatus: 'ACTIVE' as BiometricLifecycleState,
              accountStatus,
              enrollmentId: opData.enrollmentId as string,
              enrollmentVersion: Number(opData.enrollmentVersion ?? 1),
              receiptToken: opData.receiptToken as string,
              idempotentReplay: true,
              retryable: false,
            },
          };
        }
        if (opData.state === 'REJECTED') {
          return {
            earlyReturn: {
              httpStatus: opData.httpStatus ?? 409,
              operationId: deterministicOpId,
              code: opData.rejectionCode as StructuredBiometricCode,
              biometricStatus: currentBioStatus,
              accountStatus,
              caseReference: opData.caseReference as string | undefined,
              idempotentReplay: true,
              retryable: false,
            },
          };
        }
        if (
          opData.state === 'IN_PROGRESS' &&
          nowMs < Number(opData.leaseExpiresAtMs ?? 0)
        ) {
          return {
            earlyReturn: {
              httpStatus: 409,
              operationId: deterministicOpId,
              code: 'RETRY_REQUIRED' as StructuredBiometricCode,
              biometricStatus: currentBioStatus,
              accountStatus,
              idempotentReplay: false,
              retryable: true,
            },
          };
        }
      }

      // Reject suspended or locked accounts (Part 3.2)
      if (accountStatus === 'suspended' || currentBioStatus === 'LOCKED' || currentBioStatus === 'REVOKED') {
        return {
          earlyReturn: {
            httpStatus: 403,
            operationId: deterministicOpId,
            code: 'INVALID_OPERATION_STATE' as StructuredBiometricCode,
            biometricStatus: currentBioStatus,
            accountStatus,
            idempotentReplay: false,
            retryable: false,
          },
        };
      }

      // Invariant 3: Initial enrollment cannot overwrite an existing ACTIVE enrollment
      if (
        workflowType === 'INITIAL_ENROLLMENT' &&
        currentBioStatus === 'ACTIVE' &&
        existingEnrollmentId !== null
      ) {
        return {
          earlyReturn: {
            httpStatus: 200,
            operationId: deterministicOpId,
            code: 'ALREADY_ENROLLED' as StructuredBiometricCode,
            biometricStatus: 'ACTIVE' as BiometricLifecycleState,
            accountStatus,
            enrollmentId: existingEnrollmentId,
            enrollmentVersion: existingVersion,
            idempotentReplay: false,
            retryable: false,
          },
        };
      }

      // Workflow C guard: Re-enrollment requires an existing enrollment or RECOVERY_REQUIRED state
      if (
        workflowType === 'AUTHORIZED_REPLACEMENT' &&
        currentBioStatus !== 'ACTIVE' &&
        currentBioStatus !== 'RECOVERY_REQUIRED' &&
        currentBioStatus !== 'RE_ENROLLMENT_PENDING' &&
        currentBioStatus !== 'UNENROLLED'
      ) {
        return {
          earlyReturn: {
            httpStatus: 400,
            operationId: deterministicOpId,
            code: 'INVALID_OPERATION_STATE' as StructuredBiometricCode,
            biometricStatus: currentBioStatus,
            accountStatus,
            idempotentReplay: false,
            retryable: false,
          },
        };
      }

      const pendingBioStatus: BiometricLifecycleState =
        workflowType === 'AUTHORIZED_REPLACEMENT'
          ? 'RE_ENROLLMENT_PENDING'
          : 'ENROLLMENT_PENDING';

      tx.set(opRef, {
        operationId: deterministicOpId,
        uid: authenticatedUid,
        workflowType,
        idempotencyKey,
        challengeNonce,
        requestFingerprint,
        state: 'IN_PROGRESS' as BiometricOperationState,
        previousBiometricStatus: currentBioStatus,
        previousEnrollmentId: existingEnrollmentId,
        previousEnrollmentVersion: existingVersion,
        leaseExpiresAtMs: nowMs + BiometricLifecycleCoordinatorV10.LEASE_TTL_MS,
        createdAtMs: nowMs,
        updatedAtMs: nowMs,
      });

      // Keep activeBiometricEnrollmentId intact during RE_ENROLLMENT_PENDING (Invariant 5)
      tx.set(
        userRef,
        {
          uid: authenticatedUid,
          biometricStatus: pendingBioStatus,
          updatedAtMs: nowMs,
        },
        { merge: true }
      );

      return {
        earlyReturn: null,
        accountStatus,
        previousBioStatus: currentBioStatus,
        existingEnrollmentId,
        existingVersion,
      };
    });

    if (reservation.earlyReturn) {
      return reservation.earlyReturn;
    }

    // STEP 8–12: Search Compatible SFace Gallery & Commit with Epoch Fencing (Part 5.2)
    for (
      let attempt = 0;
      attempt < BiometricLifecycleCoordinatorV10.MAX_CONCURRENT_EPOCH_RETRIES;
      attempt++
    ) {
      let searchResult: {
        candidates: GalleryCandidateHit[];
        searchedGalleryEpoch: number;
      };
      try {
        searchResult = await this.galleryIndex.searchTopKCompatible({
          probeEmbedding128: unitProbe,
          probeEmbeddingSpaceId: CANONICAL_EMBEDDING_SPACE_V2.embeddingSpaceId,
          probeLandmarkVector128: params.probeLandmarkVector128,
          excludeOwningUid: authenticatedUid,
          excludeEnrollmentId: reservation.existingEnrollmentId,
          topK: 5,
        });
      } catch {
        await this.restorePreviousUserStateOnFailure(
          authenticatedUid,
          deterministicOpId,
          reservation.previousBioStatus
        );
        return {
          httpStatus: 503,
          operationId: deterministicOpId,
          code: 'INDEX_UNAVAILABLE',
          biometricStatus: reservation.previousBioStatus,
          accountStatus: reservation.accountStatus,
          enrollmentId: reservation.existingEnrollmentId,
          idempotentReplay: false,
          retryable: true,
        };
      }

      // Phase 3D5: Authoritative candidate validation against biometric_vault
      const validCandidates: GalleryCandidateHit[] = [];
      for (const cand of searchResult.candidates) {
        const candSnap = await this.db
          .collection(BiometricLifecycleCoordinatorV10.VAULT_COL)
          .doc(cand.enrollmentId)
          .get();
        if (candSnap.exists) {
          const cData = candSnap.data()!;
          const candStatus = cData.status || (cData.embedding ? 'ACTIVE' : 'UNKNOWN');
          const candOwner = cData.owningUid || cData.uid || candSnap.id;
          if (candStatus === 'ACTIVE' && candOwner === cand.owningUid) {
            validCandidates.push(cand);
          }
        }
      }

      const topHit = validCandidates[0];
      const maxSim = topHit ? topHit.similarity : 0.0;
      const cleanFloor = (topHit?.comparisonSpace === 'LEGACY_LANDMARK_SPACE')
        ? 0.80
        : this.thresholds.dedupCleanMax;
      const duplicateFloor = (topHit?.comparisonSpace === 'LEGACY_LANDMARK_SPACE')
        ? (topHit?.calibratedThreshold ?? 0.88)
        : this.thresholds.dedupHardBlockMin;

      // Evaluate Duplicate Policy BEFORE writing any template to biometric_vault (Part 2.4 & 6A)
      if (maxSim >= cleanFloor) {
        const isDuplicateBlock = maxSim >= duplicateFloor;
        const rejectionCode: StructuredBiometricCode = isDuplicateBlock
          ? 'FACE_ALREADY_LINKED'
          : 'AMBIGUOUS_MATCH';

        const caseReference = `CASE-${randomBytes(16).toString('hex').toUpperCase()}`;
        const caseReferenceHash = createHash('sha256').update(caseReference).digest('hex');
        const restoredBioStatus: BiometricLifecycleState =
          workflowType === 'AUTHORIZED_REPLACEMENT'
            ? reservation.previousBioStatus // Preserve existing ACTIVE template on replacement failure!
            : isDuplicateBlock
            ? 'UNENROLLED'
            : 'REVIEW_REQUIRED';

        const nowMs = params.nowMs ?? Date.now();
        await this.db.runTransaction(async (tx) => {
          const caseRef = this.db
            .collection(BiometricLifecycleCoordinatorV10.CASES_COL)
            .doc(caseReference);
          const caseSnap = await tx.get(caseRef);
          if (caseSnap.exists) {
            throw new Error(`CRITICAL_CASE_COLLISION: Case reference ${caseReference} already exists.`);
          }

          tx.set(
            caseRef,
            {
              caseId: caseReference,
              caseReference,
              caseReferenceHash,
              operationId: deterministicOpId,
              applicantUid: authenticatedUid,
              workflowType,
              matchedEnrollmentId: topHit.enrollmentId,
              matchedOwningUid: topHit.owningUid,
              similarityScore: Number(maxSim.toFixed(6)),
              appliedThreshold: isDuplicateBlock
                ? this.thresholds.dedupHardBlockMin
                : this.thresholds.dedupCleanMax,
              modelIdentifier: CANONICAL_SFACE_SPEC_V10.modelIdentifier,
              preprocessVersion: CANONICAL_SFACE_SPEC_V10.preprocessVersion,
              embeddingSpaceId: CANONICAL_EMBEDDING_SPACE_V2.embeddingSpaceId,
              manifestVersion: CANONICAL_PREPROCESSING_MANIFEST_V2.manifestVersion,
              manifestHash: CANONICAL_MANIFEST_HASH_V2,
              status: 'CREATED',
              caseType: isDuplicateBlock ? 'DUPLICATE_DISPUTE' : 'AMBIGUOUS_REVIEW',
              ownershipVerification: {
                verified: false,
                verifiedAtMs: null,
                method: null,
              },
              resolution: {
                resolvedBy: null,
                resolvedAtMs: null,
                action: null,
                notes: null,
              },
              auditEvents: [
                {
                  event: 'CASE_CREATED',
                  timestampMs: nowMs,
                  actor: 'SYSTEM',
                  details: {
                    workflowType,
                    appliedThreshold: isDuplicateBlock
                      ? this.thresholds.dedupHardBlockMin
                      : this.thresholds.dedupCleanMax,
                  },
                },
              ],
              classification: rejectionCode,
              reviewStatus: 'OPEN',
              createdAtMs: nowMs,
              expiresAtMs: nowMs + 30 * 24 * 60 * 60 * 1000,
            }
          );

          tx.update(opRef, {
            state: 'REJECTED' as BiometricOperationState,
            rejectionCode,
            caseReference,
            httpStatus: isDuplicateBlock ? 409 : 202,
            updatedAtMs: nowMs,
          });

          tx.set(
            userRef,
            {
              biometricStatus: restoredBioStatus,
              updatedAtMs: nowMs,
            },
            { merge: true }
          );
        });

        // PRIVACY ENFORCEMENT: Never return matched account PII, phone, name, or raw scores to applicant.
        return {
          httpStatus: isDuplicateBlock ? 409 : 202,
          operationId: deterministicOpId,
          code: rejectionCode,
          biometricStatus: restoredBioStatus,
          accountStatus: reservation.accountStatus,
          enrollmentId:
            workflowType === 'AUTHORIZED_REPLACEMENT'
              ? reservation.existingEnrollmentId
              : null,
          caseReference,
          idempotentReplay: false,
          retryable: false,
        };
      }

      // Candidate is NO_MATCH (< 0.363) at searchedGalleryEpoch -> Attempt fenced CAS commit
      const newEnrollmentId = `enr_${randomUUID()}`;
      const newVersion = reservation.existingVersion + 1;
      const nowMs = params.nowMs ?? Date.now();

      // KELASAGARA V20.1 (Gate 4 & 6): Prepare authenticated encrypted envelope before entering transaction
      let encryptionPackage: EncryptedTemplatePersistencePackage;
      try {
        encryptionPackage = await this.cryptoService.encryptTemplate({
          templateId: newEnrollmentId,
          ownerUid: authenticatedUid,
          embedding128: unitProbe,
          modelId: CANONICAL_SFACE_SPEC_V10.modelIdentifier,
          modelVersion: CANONICAL_SFACE_SPEC_V10.preprocessVersion,
          nowMs,
        });
      } catch (kmsErr: any) {
        // Fail-closed (Gate 11): Never write plaintext, never advance epoch, never approve user
        await this.restorePreviousUserStateOnFailure(
          authenticatedUid,
          deterministicOpId,
          reservation.previousBioStatus
        );
        return {
          httpStatus: 503,
          operationId: deterministicOpId,
          code: 'KMS_UNAVAILABLE',
          biometricStatus: reservation.previousBioStatus,
          accountStatus: reservation.accountStatus,
          enrollmentId: reservation.existingEnrollmentId,
          idempotentReplay: false,
          retryable: true,
        };
      }

      const signedReceipt = this.receiptService.issueSignedReceipt({
        uid: authenticatedUid,
        operationId: deterministicOpId,
        enrollmentId: newEnrollmentId,
        enrollmentVersion: newVersion,
        nowMs,
      });

      const commitOutcome = await this.db.runTransaction(async (tx) => {
        // ALL READS FIRST: Read meta, user, operation, and existing vault record if replacement
        const oldVaultRef = reservation.existingEnrollmentId
          ? this.db.collection(BiometricLifecycleCoordinatorV10.VAULT_COL).doc(reservation.existingEnrollmentId)
          : null;

        const [metaSnap, userSnap, opSnap, oldVaultSnap] = await Promise.all([
          tx.get(metaRef),
          tx.get(userRef),
          tx.get(opRef),
          oldVaultRef ? tx.get(oldVaultRef) : Promise.resolve(null),
        ]);

        const currentEpoch = metaSnap.exists
          ? Number(metaSnap.data()?.epochVersion ?? 0)
          : 0;

        // Concurrent enrollment guard (Part 5.2): If gallery changed since our search, abort commit and re-search!
        if (currentEpoch !== searchResult.searchedGalleryEpoch) {
          return { status: 'EPOCH_CHANGED_RECHECK' as const, currentEpoch };
        }

        const opData = opSnap.data();
        if (!opData || opData.state !== 'IN_PROGRESS') {
          return { status: 'OPERATION_LEASE_LOST' as const };
        }

        // Validate existing template state if this is an AUTHORIZED_REPLACEMENT
        if (workflowType === 'AUTHORIZED_REPLACEMENT' && oldVaultRef) {
          if (!oldVaultSnap || !oldVaultSnap.exists) {
            return { status: 'REPLACEMENT_TARGET_MISSING' as const };
          }
          const oldData = oldVaultSnap.data()!;
          if (oldData.owningUid !== authenticatedUid) {
            return { status: 'REPLACEMENT_OWNER_MISMATCH' as const };
          }
          if (oldData.status === 'SUPERSEDED') {
            return { status: 'REPLACEMENT_ALREADY_SUPERSEDED' as const };
          }
        }

        const userData = userSnap.exists ? userSnap.data()! : {};
        const currentAccStatus: KelasagaraAccountStatus =
          userData.accountStatus ?? 'pending_face';

        // Separate account approval from biometric enrollment (Part 2.5 & 3.2):
        // Only advance accountStatus if it was specifically waiting on 'pending_face'.
        const nextAccountStatus: KelasagaraAccountStatus =
          currentAccStatus === 'pending_face' ? 'approved' : currentAccStatus;

        const nextEpoch = currentEpoch + 1;
        const newVaultRef = this.db
          .collection(BiometricLifecycleCoordinatorV10.VAULT_COL)
          .doc(newEnrollmentId);

        // Supersede old template if this is an AUTHORIZED_REPLACEMENT
        if (oldVaultRef) {
          tx.set(
            oldVaultRef,
            {
              status: 'SUPERSEDED',
              revokedAtMs: nowMs,
              supersededByEnrollmentId: newEnrollmentId,
            },
            { merge: true }
          );
        }

        // KELASAGARA V20.12 (Gate 6): Persist zero-plaintext encrypted vault record with complete provenance
        tx.set(newVaultRef, {
          schemaVersion: encryptionPackage.schemaVersion,
          enrollmentId: newEnrollmentId,
          owningUid: authenticatedUid,
          enrollmentVersion: newVersion,
          biometricEnvelope: encryptionPackage.biometricEnvelope,
          metadata: encryptionPackage.metadata,
          modelIdentifier: CANONICAL_SFACE_SPEC_V10.modelIdentifier,
          modelSha256: CANONICAL_SFACE_SPEC_V10.expectedSha256,
          preprocessVersion: CANONICAL_SFACE_SPEC_V10.preprocessVersion,
          embeddingSpaceId: CANONICAL_EMBEDDING_SPACE_V2.embeddingSpaceId,
          manifestVersion: CANONICAL_PREPROCESSING_MANIFEST_V2.manifestVersion,
          manifestHash: CANONICAL_MANIFEST_HASH_V2,
          detectorIdentifier: CANONICAL_YUNET_SPEC_V10.modelIdentifier,
          detectorSha256: CANONICAL_YUNET_SPEC_V10.expectedSha256,
          status: 'ACTIVE',
          committedAtEpoch: nextEpoch,
          operationId: deterministicOpId,
          createdAtMs: nowMs,
          revokedAtMs: null,
        });

        tx.set(
          metaRef,
          {
            epochVersion: nextEpoch,
            lastCommittedEnrollmentId: newEnrollmentId,
            updatedAtMs: nowMs,
          },
          { merge: true }
        );

        tx.set(
          userRef,
          {
            uid: authenticatedUid,
            activeBiometricEnrollmentId: newEnrollmentId,
            activeEnrollmentVersion: newVersion,
            biometricStatus: 'ACTIVE' as BiometricLifecycleState,
            faceVerified: true,
            accountStatus: nextAccountStatus,
            updatedAtMs: nowMs,
          },
          { merge: true }
        );

        tx.update(opRef, {
          state: 'COMMITTED' as BiometricOperationState,
          enrollmentId: newEnrollmentId,
          enrollmentVersion: newVersion,
          committedAtEpoch: nextEpoch,
          receiptToken: signedReceipt.receiptToken,
          updatedAtMs: nowMs,
        });

        return {
          status: 'COMMITTED' as const,
          nextEpoch,
          nextAccountStatus,
        };
      });

      if (commitOutcome.status === 'EPOCH_CHANGED_RECHECK') {
        continue;
      }

      if (commitOutcome.status !== 'COMMITTED') {
        await this.restorePreviousUserStateOnFailure(
          authenticatedUid,
          deterministicOpId,
          reservation.previousBioStatus
        );
        return {
          httpStatus: 409,
          operationId: deterministicOpId,
          code: 'RETRY_REQUIRED',
          biometricStatus: reservation.previousBioStatus,
          accountStatus: reservation.accountStatus,
          idempotentReplay: false,
          retryable: true,
        };
      }

      // STEP 13: Make newly active enrollment searchable & evict superseded template
      if (reservation.existingEnrollmentId) {
        await this.galleryIndex.removeEnrollmentFromIndex(
          reservation.existingEnrollmentId
        );
      }
      try {
        const isVisible = await this.galleryIndex.confirmEnrollmentVisibleInIndex(
          newEnrollmentId,
          authenticatedUid,
          unitProbe,
          commitOutcome.nextEpoch
        );
        if (!isVisible) {
          // Phase 3D4: Record index sync outbox entry if projection is lagging
          await this.db
            .collection('biometric_index_outbox')
            .doc(newEnrollmentId)
            .set({
              enrollmentId: newEnrollmentId,
              owningUid: authenticatedUid,
              status: 'OUTBOX_PENDING',
              committedEpoch: commitOutcome.nextEpoch,
              createdAtMs: nowMs,
            });
        }
      } catch (idxErr) {
        await this.db
          .collection('biometric_index_outbox')
          .doc(newEnrollmentId)
          .set({
            enrollmentId: newEnrollmentId,
            owningUid: authenticatedUid,
            status: 'OUTBOX_PENDING',
            committedEpoch: commitOutcome.nextEpoch,
            createdAtMs: nowMs,
          });
      }

      return {
        httpStatus: 200,
        operationId: deterministicOpId,
        code: 'NO_MATCH',
        biometricStatus: 'ACTIVE',
        accountStatus: commitOutcome.nextAccountStatus,
        enrollmentId: newEnrollmentId,
        enrollmentVersion: newVersion,
        receiptToken: signedReceipt.receiptToken,
        idempotentReplay: false,
        retryable: false,
      };
    }

    // Exceeded concurrent epoch contention retries -> restore previous valid state safely
    await this.restorePreviousUserStateOnFailure(
      authenticatedUid,
      deterministicOpId,
      reservation.previousBioStatus
    );
    return {
      httpStatus: 503,
      operationId: deterministicOpId,
      code: 'RETRY_REQUIRED',
      biometricStatus: reservation.previousBioStatus,
      accountStatus: reservation.accountStatus,
      enrollmentId: reservation.existingEnrollmentId,
      idempotentReplay: false,
      retryable: true,
    };
  }

  /**
   * WORKFLOW B: EXISTING-ACCOUNT 1:1 VERIFICATION
   * Retrieves the active enrollment associated with `authenticatedUid` and compares
   * using the 1:1 verification policy. Never alters or erases the template on mismatch.
   */
  public async verifyExistingAccount1to1(params: {
    authenticatedUid: string;
    challengeNonce: string;
    validatedSFaceEmbedding128: Float32Array;
  }): Promise<WorkflowExecutionResultV10> {
    const { authenticatedUid, validatedSFaceEmbedding128 } = params;
    const operationId = `ver_${randomUUID()}`;

    const unitProbe = CanonicalSFaceEngineV10.extractAndNormalizeOutputTensor({
      type: 'float32',
      data: validatedSFaceEmbedding128,
    });

    const userSnap = await this.db
      .collection(BiometricLifecycleCoordinatorV10.USERS_COL)
      .doc(authenticatedUid)
      .get();

    if (!userSnap.exists) {
      return {
        httpStatus: 404,
        operationId,
        code: 'INVALID_OPERATION_STATE',
        biometricStatus: 'UNENROLLED',
        accountStatus: 'pending_profile',
        idempotentReplay: false,
        retryable: false,
      };
    }

    const userData = userSnap.data()!;
    const accountStatus: KelasagaraAccountStatus =
      userData.accountStatus ?? 'pending_face';
    const bioStatus: BiometricLifecycleState =
      userData.biometricStatus ?? 'UNENROLLED';
    const activeEnrollmentId: string | null =
      userData.activeBiometricEnrollmentId ?? null;

    if (bioStatus === 'RECOVERY_REQUIRED') {
      return {
        httpStatus: 409,
        operationId,
        code: 'RECOVERY_REQUIRED',
        biometricStatus: 'RECOVERY_REQUIRED',
        accountStatus,
        idempotentReplay: false,
        retryable: false,
      };
    }

    if (bioStatus !== 'ACTIVE' || !activeEnrollmentId) {
      return {
        httpStatus: 400,
        operationId,
        code: 'INVALID_OPERATION_STATE',
        biometricStatus: bioStatus,
        accountStatus,
        idempotentReplay: false,
        retryable: false,
      };
    }

    const vaultSnap = await this.db
      .collection(BiometricLifecycleCoordinatorV10.VAULT_COL)
      .doc(activeEnrollmentId)
      .get();

    if (!vaultSnap.exists) {
      return {
        httpStatus: 409,
        operationId,
        code: 'RECOVERY_REQUIRED',
        biometricStatus: 'RECOVERY_REQUIRED',
        accountStatus,
        idempotentReplay: false,
        retryable: false,
      };
    }

    const vaultData = vaultSnap.data()!;
    if (
      vaultData.owningUid !== authenticatedUid ||
      vaultData.status !== 'ACTIVE' ||
      vaultData.modelIdentifier !== CANONICAL_SFACE_SPEC_V10.modelIdentifier
    ) {
      return {
        httpStatus: 409,
        operationId,
        code: 'RECOVERY_REQUIRED',
        biometricStatus: 'RECOVERY_REQUIRED',
        accountStatus,
        idempotentReplay: false,
        retryable: false,
      };
    }

    let storedEmbedding: Float32Array | number[];
    if (vaultData.schemaVersion === 2 || vaultData.biometricEnvelope) {
      try {
        storedEmbedding = await this.cryptoService.decryptTemplate({
          templateId: activeEnrollmentId,
          ownerUid: authenticatedUid,
          envelope: vaultData.biometricEnvelope,
          modelId: CANONICAL_SFACE_SPEC_V10.modelIdentifier,
          modelVersion: CANONICAL_SFACE_SPEC_V10.preprocessVersion,
        });
      } catch (decryptErr: any) {
        // Fail-closed (Gate 9 & 11): Decryption failure must NEVER be interpreted as match or bypass
        return {
          httpStatus: 503,
          operationId,
          code: 'KMS_UNAVAILABLE',
          biometricStatus: 'ACTIVE',
          accountStatus,
          enrollmentId: activeEnrollmentId,
          idempotentReplay: false,
          retryable: true,
        };
      }
    } else if (Array.isArray(vaultData.canonicalEmbedding)) {
      // Legacy unmigrated plaintext reading compatibility
      storedEmbedding = vaultData.canonicalEmbedding;
    } else {
      return {
        httpStatus: 409,
        operationId,
        code: 'RECOVERY_REQUIRED',
        biometricStatus: 'RECOVERY_REQUIRED',
        accountStatus,
        idempotentReplay: false,
        retryable: false,
      };
    }

    const similarity = CanonicalSFaceEngineV10.computeCosineSimilarity(
      unitProbe,
      storedEmbedding
    );

    const matched = similarity >= this.thresholds.verify1to1Min;
    return {
      httpStatus: matched ? 200 : 403,
      operationId,
      code: matched ? 'VERIFIED_1TO1' : 'GENUINE_USER_MISMATCH',
      biometricStatus: 'ACTIVE', // Active template remains untouched on mismatch!
      accountStatus,
      enrollmentId: activeEnrollmentId,
      enrollmentVersion: Number(vaultData.enrollmentVersion ?? 1),
      idempotentReplay: false,
      retryable: !matched,
    };
  }

  private async restorePreviousUserStateOnFailure(
    uid: string,
    operationId: string,
    previousBioStatus: BiometricLifecycleState
  ): Promise<void> {
    const nowMs = Date.now();
    const batch = this.db.batch();
    batch.set(
      this.db.collection(BiometricLifecycleCoordinatorV10.USERS_COL).doc(uid),
      {
        biometricStatus: previousBioStatus,
        updatedAtMs: nowMs,
      },
      { merge: true }
    );
    batch.set(
      this.db
        .collection(BiometricLifecycleCoordinatorV10.OPS_COL)
        .doc(operationId),
      {
        state: 'RETRYABLE_FAILURE' as BiometricOperationState,
        updatedAtMs: nowMs,
      },
      { merge: true }
    );
    await batch.commit();
  }
}
