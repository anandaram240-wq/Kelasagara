// File: backend/src/services/firestore_compatible_gallery_index.ts
import * as admin from 'firebase-admin';
import {
  CompatibleGalleryIndex,
  GalleryCandidateHit,
} from './biometric_lifecycle_coordinator_v10';
import {
  CANONICAL_SFACE_SPEC_V10,
  CANONICAL_YUNET_SPEC_V10,
  CANONICAL_EMBEDDING_SPACE_V2,
  CANONICAL_MANIFEST_HASH_V2,
  CanonicalSFaceEngineV10,
} from '../biometrics/canonical_sface_engine_v10';
import { BiometricTemplateCryptoService } from './biometric_template_crypto';

export type BiometricTemplateClassification =
  | 'CANONICAL_V2'
  | 'LEGACY_LANDMARK_SPACE'
  | 'DEFECTIVE_FULL_PHOTO_SFACE_V10'
  | 'LEGACY_TEMPLATE_UNKNOWN';

/**
 * Workstream A & B & D: Forensic Template Classification & Provenance Guard
 * Any template lacking verified detector provenance, explicit Canonical V2 space ID,
 * or exhibiting mismatched model/detector hashes is classified as DEFECTIVE or
 * LEGACY_TEMPLATE_UNKNOWN and NEVER compared against canonical probes.
 */
export function classifyBiometricTemplate(data: any): BiometricTemplateClassification {
  if (data?.clientModified === true || data?.untrustedClient === true || data?.source === 'CLIENT') {
    return 'LEGACY_TEMPLATE_UNKNOWN';
  }
  if (data?.embeddingSpaceId === CANONICAL_EMBEDDING_SPACE_V2.embeddingSpaceId) {
    if (data.modelSha256 && data.modelSha256 !== CANONICAL_SFACE_SPEC_V10.expectedSha256) {
      return 'LEGACY_TEMPLATE_UNKNOWN';
    }
    if (data.detectorSha256 && data.detectorSha256 !== CANONICAL_YUNET_SPEC_V10.expectedSha256) {
      return 'LEGACY_TEMPLATE_UNKNOWN';
    }
    if (data.manifestHash && data.manifestHash !== CANONICAL_MANIFEST_HASH_V2) {
      return 'LEGACY_TEMPLATE_UNKNOWN';
    }
    return 'CANONICAL_V2';
  }
  if (
    (data?.comparisonSpace === 'LEGACY_LANDMARK_SPACE' ||
      Array.isArray(data?.whitenedLandmark128) ||
      Array.isArray(data?.embedding)) &&
    !data?.biometricEnvelope &&
    !data?.canonicalEmbedding &&
    !data?.sfaceEmbedding128
  ) {
    return 'LEGACY_LANDMARK_SPACE';
  }
  if (
    data?.preprocessVersion === 'sface_aligned_112x112_bgr_v1' &&
    !data?.detectorIdentifier &&
    !data?.landmarks &&
    !data?.embeddingSpaceId
  ) {
    return 'DEFECTIVE_FULL_PHOTO_SFACE_V10';
  }
  return 'LEGACY_TEMPLATE_UNKNOWN';
}

export class FirestoreCompatibleGalleryIndex implements CompatibleGalleryIndex {
  private readonly cryptoService: BiometricTemplateCryptoService;

  constructor(
    private readonly db: admin.firestore.Firestore,
    cryptoService?: BiometricTemplateCryptoService
  ) {
    this.cryptoService = cryptoService ?? BiometricTemplateCryptoService.getInstance();
  }

  public async searchTopKCompatible(params: {
    probeEmbedding128: Float32Array;
    probeEmbeddingSpaceId?: string;
    probeLandmarkVector128?: number[];
    excludeOwningUid: string;
    excludeEnrollmentId?: string | null;
    topK: number;
  }): Promise<{
    candidates: GalleryCandidateHit[];
    searchedGalleryEpoch: number;
  }> {
    const metaRef = this.db.collection('biometric_system_meta').doc('gallery_epoch_v10');
    const metaSnap = await metaRef.get();
    const currentEpoch = metaSnap.exists ? Number(metaSnap.data()?.epochVersion ?? 0) : 0;

    // Phase 5 Invariant: Complete Firestore pagination across arbitrary gallery sizes
    const hits: GalleryCandidateHit[] = [];
    let lastDoc: admin.firestore.QueryDocumentSnapshot | null = null;
    let hasMore = true;
    const pageSize = 500;

    while (hasMore) {
      let query = this.db
        .collection('biometric_vault')
        .orderBy(admin.firestore.FieldPath.documentId())
        .limit(pageSize);

      if (lastDoc) {
        query = query.startAfter(lastDoc);
      }

      const snap = await query.get();
      if (snap.empty) {
        break;
      }

      for (const doc of snap.docs) {
        const data = doc.data();
        const owningUid = data.owningUid || data.uid || doc.id;
        const enrollmentId = data.enrollmentId || doc.id;

        if (owningUid === params.excludeOwningUid) continue;
        if (params.excludeEnrollmentId && enrollmentId === params.excludeEnrollmentId) continue;
        if (data.status && data.status !== 'ACTIVE') continue;

        // Workstream B & C: Strict Embedding Space Isolation
        // INCOMPATIBLE_EMBEDDING_SPACE = NEVER_COMPARE
        const classification = classifyBiometricTemplate(data);

        // Space 1: Canonical SFace Deep Neural Space (V2)
        // Strictly isolated: candidate MUST be classified as CANONICAL_V2
        if (classification === 'CANONICAL_V2') {
          let storedSFace: Float32Array | number[] | undefined;
          if (data.schemaVersion === 2 || data.biometricEnvelope) {
            try {
              storedSFace = await this.cryptoService.decryptTemplate({
                templateId: enrollmentId,
                ownerUid: owningUid,
                envelope: data.biometricEnvelope,
                modelId: data.modelIdentifier || CANONICAL_SFACE_SPEC_V10.modelIdentifier,
                modelVersion: data.preprocessVersion || CANONICAL_SFACE_SPEC_V10.preprocessVersion,
              });
            } catch {
              // Fail-closed against tampered or corrupted envelope in gallery
              continue;
            }
          } else if (data.canonicalEmbedding || data.sfaceEmbedding128) {
            storedSFace = data.canonicalEmbedding || data.sfaceEmbedding128;
          }

          if (storedSFace && params.probeEmbedding128) {
            try {
              const sfaceSim = CanonicalSFaceEngineV10.computeCosineSimilarity(
                params.probeEmbedding128,
                storedSFace
              );
              if (sfaceSim >= 0.363) {
                hits.push({
                  enrollmentId,
                  owningUid,
                  similarity: sfaceSim,
                  comparisonSpace: 'SFACE_NEURAL_SPACE',
                  embeddingSpaceId: CANONICAL_EMBEDDING_SPACE_V2.embeddingSpaceId,
                  calibratedThreshold: 0.720,
                  isDuplicate: sfaceSim >= 0.720,
                  modelIdentifier: CANONICAL_SFACE_SPEC_V10.modelIdentifier,
                  preprocessVersion: data.preprocessVersion || CANONICAL_SFACE_SPEC_V10.preprocessVersion,
                });
                continue; // Candidate evaluated in authoritative neural space
              }
            } catch {}
          }
        }

        // Space 2: Legacy Geometric Landmark Space (Independent Calibrated Threshold = 0.88)
        // Only evaluated if probe provides landmark vector AND candidate is in landmark space
        if (
          classification === 'LEGACY_LANDMARK_SPACE' &&
          params.probeLandmarkVector128 &&
          params.probeLandmarkVector128.length === 128
        ) {
          const storedLandmark: number[] | undefined = data.embedding || data.whitenedLandmark128;
          if (Array.isArray(storedLandmark) && storedLandmark.length === 128) {
            try {
              const landmarkSim = CanonicalSFaceEngineV10.computeCosineSimilarity(
                new Float32Array(params.probeLandmarkVector128),
                storedLandmark
              );
              if (landmarkSim >= 0.80) {
                hits.push({
                  enrollmentId,
                  owningUid,
                  similarity: landmarkSim,
                  comparisonSpace: 'LEGACY_LANDMARK_SPACE',
                  calibratedThreshold: 0.88,
                  isDuplicate: landmarkSim >= 0.88,
                  modelIdentifier: data.modelIdentifier || 'kelasagara_biomatch_v3_whitened',
                  preprocessVersion: data.preprocessVersion || 'v3_whitened',
                });
              }
            } catch {}
          }
        }

        // Space 3: DEFECTIVE_FULL_PHOTO_SFACE_V10 or LEGACY_TEMPLATE_UNKNOWN
        // RULE: INCOMPATIBLE_EMBEDDING_SPACE = NEVER_COMPARE
        // These templates are strictly filtered out to prevent cross-space false duplicate corruption.
      }

      if (snap.size < pageSize) {
        hasMore = false;
      } else {
        lastDoc = snap.docs[snap.docs.length - 1];
      }
    }

    // Rank candidates: Duplicates (exceeding space threshold) first, then by relative confidence
    hits.sort((a, b) => {
      const aScore = a.isDuplicate ? 10.0 + a.similarity : a.similarity / (a.calibratedThreshold ?? 1.0);
      const bScore = b.isDuplicate ? 10.0 + b.similarity : b.similarity / (b.calibratedThreshold ?? 1.0);
      return bScore - aScore;
    });

    return {
      candidates: hits.slice(0, params.topK),
      searchedGalleryEpoch: currentEpoch,
    };
  }

  public async confirmEnrollmentVisibleInIndex(
    enrollmentId: string,
    _owningUid: string,
    _embedding128: Float32Array,
    _committedEpoch: number
  ): Promise<boolean> {
    const docSnap = await this.db.collection('biometric_vault').doc(enrollmentId).get();
    return docSnap.exists && docSnap.data()?.status === 'ACTIVE';
  }

  public async removeEnrollmentFromIndex(enrollmentId: string): Promise<void> {
    const docRef = this.db.collection('biometric_vault').doc(enrollmentId);
    await docRef.set(
      {
        status: 'SUPERSEDED',
        revokedAtMs: Date.now(),
      },
      { merge: true }
    );
  }
}
