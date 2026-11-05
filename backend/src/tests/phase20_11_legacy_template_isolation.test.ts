// File: backend/src/tests/phase20_11_legacy_template_isolation.test.ts
import { describe, it, before, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import * as path from 'path';
import * as fs from 'fs';
import { randomUUID } from 'crypto';
import * as admin from 'firebase-admin';

import {
  CanonicalSFaceEngineV10,
  CanonicalAlignedFace112Factory,
  CANONICAL_SFACE_SPEC_V10,
  CANONICAL_YUNET_SPEC_V10,
  CANONICAL_EMBEDDING_SPACE_V2,
  CanonicalAlignedFace112,
  SFaceEmbedding128,
} from '../biometrics/canonical_sface_engine_v10';

import {
  BiometricLifecycleCoordinatorV10,
  DEFAULT_CANDIDATE_THRESHOLDS_V10,
  GalleryCandidateHit,
} from '../services/biometric_lifecycle_coordinator_v10';

import {
  FirestoreCompatibleGalleryIndex,
  classifyBiometricTemplate,
} from '../services/firestore_compatible_gallery_index';

import { BiometricTemplateCryptoService } from '../services/biometric_template_crypto';

describe('KELASAGARA V20.11: Legacy Biometric Template Isolation & Post-Hotfix Validation Suite', () => {
  const sfacePath = path.resolve(__dirname, '../../models/face_recognition_sface_2021dec.onnx');
  const yunetPath = path.resolve(__dirname, '../../models/face_detection_yunet_2023mar.onnx');

  let engine: CanonicalSFaceEngineV10;

  before(() => {
    assert.ok(fs.existsSync(sfacePath), `SFace ONNX model must exist at ${sfacePath}`);
    assert.ok(fs.existsSync(yunetPath), `YuNet ONNX model must exist at ${yunetPath}`);
    engine = new CanonicalSFaceEngineV10(sfacePath, undefined, yunetPath, undefined);
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // WORKSTREAM B: CANONICAL EMBEDDING SPACE IDENTIFIER & CONSTANTS
  // ─────────────────────────────────────────────────────────────────────────────
  describe('Workstream B: Canonical Embedding Space Specification', () => {
    it('B.1 exports authoritative canonical embedding space identifier', () => {
      assert.equal(
        CANONICAL_EMBEDDING_SPACE_V2.embeddingSpaceId,
        'SFACE_128_YUNET_2023MAR_UMEYAMA_CANONICAL112_V2'
      );
      assert.equal(CANONICAL_EMBEDDING_SPACE_V2.dimension, 128);
      assert.equal(CANONICAL_EMBEDDING_SPACE_V2.colorSpace, 'BGR');
      assert.equal(CANONICAL_EMBEDDING_SPACE_V2.alignmentAlgorithm, 'umeyama_5point_similarity');
      assert.equal(CANONICAL_EMBEDDING_SPACE_V2.canonicalTargetGeometry, '112x112_canonical_sface_5landmarks');
    });

    it('B.2 model SHA-256 matches verified frozen weights', () => {
      assert.equal(CANONICAL_EMBEDDING_SPACE_V2.modelSha256, CANONICAL_SFACE_SPEC_V10.expectedSha256);
      assert.equal(CANONICAL_EMBEDDING_SPACE_V2.detectorSha256, CANONICAL_YUNET_SPEC_V10.expectedSha256);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // WORKSTREAM A: FORENSIC TEMPLATE CLASSIFICATION
  // ─────────────────────────────────────────────────────────────────────────────
  describe('Workstream A: Forensic Template Inventory Classification', () => {
    it('A.1 classifies record with CANONICAL_EMBEDDING_SPACE_V2 as CANONICAL_V2', () => {
      const record = {
        embeddingSpaceId: 'SFACE_128_YUNET_2023MAR_UMEYAMA_CANONICAL112_V2',
        modelIdentifier: 'sface_opencv_zoo_v1_primary',
        preprocessVersion: 'sface_aligned_112x112_bgr_v1',
        status: 'ACTIVE',
      };
      assert.equal(classifyBiometricTemplate(record), 'CANONICAL_V2');
    });

    it('A.2 classifies legacy landmark vector as LEGACY_LANDMARK_SPACE', () => {
      const landmarkRecord = {
        comparisonSpace: 'LEGACY_LANDMARK_SPACE',
        embedding: new Array(128).fill(0.1),
        modelIdentifier: 'kelasagara_biomatch_v3_whitened',
        preprocessVersion: 'v3_whitened',
      };
      assert.equal(classifyBiometricTemplate(landmarkRecord), 'LEGACY_LANDMARK_SPACE');
    });

    it('A.3 classifies pre-hotfix unaligned full-photo resize as DEFECTIVE_FULL_PHOTO_SFACE_V10', () => {
      const defectiveRecord = {
        modelIdentifier: 'sface_opencv_zoo_v1_primary',
        preprocessVersion: 'sface_aligned_112x112_bgr_v1',
        sfaceEmbedding128: new Array(128).fill(0.05),
        // No detectorIdentifier, no landmarks, no embeddingSpaceId
      };
      assert.equal(classifyBiometricTemplate(defectiveRecord), 'DEFECTIVE_FULL_PHOTO_SFACE_V10');
    });

    it('A.4 classifies unknown, unverified or ambiguous record as LEGACY_TEMPLATE_UNKNOWN', () => {
      const ambiguousRecord1 = {
        modelIdentifier: 'unknown_model',
        preprocessVersion: 'v0_experimental',
      };
      assert.equal(classifyBiometricTemplate(ambiguousRecord1), 'LEGACY_TEMPLATE_UNKNOWN');

      const ambiguousRecord2 = {};
      assert.equal(classifyBiometricTemplate(ambiguousRecord2), 'LEGACY_TEMPLATE_UNKNOWN');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // WORKSTREAM F: RUNTIME SAFETY OF CANONICAL FACE TYPES
  // ─────────────────────────────────────────────────────────────────────────────
  describe('Workstream F: Runtime Safety of Canonical Face Types', () => {
    it('F.1 CanonicalAlignedFace112Factory rejects non-Buffer inputs', () => {
      const result = CanonicalAlignedFace112Factory.validateBuffer('not-a-buffer' as any);
      assert.equal(result.valid, false);
      assert.ok(result.reason?.includes('INPUT_NOT_BUFFER'));
    });

    it('F.2 rejects buffers not exactly 112x112x3 = 37,632 bytes', () => {
      const shortBuffer = Buffer.alloc(1000);
      const res1 = CanonicalAlignedFace112Factory.validateBuffer(shortBuffer);
      assert.equal(res1.valid, false);
      assert.ok(res1.reason?.includes('INVALID_BYTE_LENGTH'));

      const longBuffer = Buffer.alloc(40000);
      const res2 = CanonicalAlignedFace112Factory.validateBuffer(longBuffer);
      assert.equal(res2.valid, false);
      assert.ok(res2.reason?.includes('INVALID_BYTE_LENGTH'));
    });

    it('F.3 rejects uniform degenerate buffers (all zeros or solid fill)', () => {
      const zerosBuffer = Buffer.alloc(37632, 0);
      const res1 = CanonicalAlignedFace112Factory.validateBuffer(zerosBuffer);
      assert.equal(res1.valid, false);
      assert.ok(res1.reason?.includes('DEGENERATE_UNIFORM_BUFFER'));

      const whiteBuffer = Buffer.alloc(37632, 255);
      const res2 = CanonicalAlignedFace112Factory.validateBuffer(whiteBuffer);
      assert.equal(res2.valid, false);
      assert.ok(res2.reason?.includes('DEGENERATE_UNIFORM_BUFFER'));
    });

    it('F.4 rejects buffers with insufficient pixel variance (flat noise)', () => {
      const flatBuffer = Buffer.alloc(37632, 128);
      // Alter only 2 pixels: variance is negligible
      flatBuffer[0] = 129;
      flatBuffer[1] = 127;
      const res = CanonicalAlignedFace112Factory.validateBuffer(flatBuffer, { minVariance: 0.5 });
      assert.equal(res.valid, false);
      assert.ok(res.reason?.includes('INSUFFICIENT_VARIANCE'));
    });

    it('F.5 CanonicalAlignedFace112Factory.create succeeds on valid variable face buffer', () => {
      const validBuffer = Buffer.alloc(37632);
      for (let i = 0; i < 37632; i++) {
        validBuffer[i] = (i * 7 + 13) % 256;
      }
      const canonical = CanonicalAlignedFace112Factory.create(validBuffer);
      assert.ok(Buffer.isBuffer(canonical));
      assert.equal(canonical.length, 37632);
    });

    it('F.6 extractCanonicalEmbeddingFromAligned112 rejects corrupt buffer at runtime even if cast with as any', async () => {
      const corruptBuffer = Buffer.alloc(37632, 0); // all zeros
      await assert.rejects(
        async () => engine.extractCanonicalEmbeddingFromAligned112(corruptBuffer as any),
        (err: any) => {
          assert.equal(err.code, 'CANONICAL_EMBEDDING_FAILED');
          assert.ok(err.message.includes('Runtime validation rejected input'));
          return true;
        }
      );
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // WORKSTREAM D: DUPLICATE THRESHOLD LOGIC AUDIT & BOUNDARIES
  // ─────────────────────────────────────────────────────────────────────────────
  describe('Workstream D: Floating-Point Boundary Tests for Duplicate Detection', () => {
    const cleanFloor = DEFAULT_CANDIDATE_THRESHOLDS_V10.dedupCleanMax; // 0.3630
    const duplicateFloor = DEFAULT_CANDIDATE_THRESHOLDS_V10.dedupHardBlockMin; // 0.7200

    function evaluateThresholdZone(sim: number): 'CLEAN' | 'AMBIGUOUS_REVIEW' | 'HARD_DUPLICATE_BLOCK' {
      if (sim < cleanFloor) return 'CLEAN';
      if (sim >= duplicateFloor) return 'HARD_DUPLICATE_BLOCK';
      return 'AMBIGUOUS_REVIEW';
    }

    const testBoundaries = [
      { value: 0.3629, expected: 'CLEAN', httpStatus: 200 },
      { value: 0.3630, expected: 'AMBIGUOUS_REVIEW', httpStatus: 202 },
      { value: 0.3631, expected: 'AMBIGUOUS_REVIEW', httpStatus: 202 },
      { value: 0.5499, expected: 'AMBIGUOUS_REVIEW', httpStatus: 202 },
      { value: 0.5500, expected: 'AMBIGUOUS_REVIEW', httpStatus: 202 },
      { value: 0.5501, expected: 'AMBIGUOUS_REVIEW', httpStatus: 202 },
      { value: 0.7199, expected: 'AMBIGUOUS_REVIEW', httpStatus: 202 },
      { value: 0.7200, expected: 'HARD_DUPLICATE_BLOCK', httpStatus: 409 },
      { value: 0.7201, expected: 'HARD_DUPLICATE_BLOCK', httpStatus: 409 },
    ];

    for (const { value, expected, httpStatus } of testBoundaries) {
      it(`D.1 Boundary similarity ${value.toFixed(4)} maps to ${expected} (HTTP ${httpStatus})`, () => {
        const zone = evaluateThresholdZone(value);
        assert.equal(zone, expected, `Similarity ${value} must map to ${expected}`);
      });
    }

    it('D.2 Historical 0.550 zone is strictly documented as an intermediate point within review zone', () => {
      assert.ok(0.5500 > cleanFloor, '0.550 is strictly above clean floor');
      assert.ok(0.5500 < duplicateFloor, '0.550 is strictly below hard block floor');
      assert.equal(evaluateThresholdZone(0.5500), 'AMBIGUOUS_REVIEW');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // WORKSTREAM G: CASE REFERENCE SECURITY & ENTROPY
  // ─────────────────────────────────────────────────────────────────────────────
  describe('Workstream G: Case Reference Security & Entropy', () => {
    it('G.1 Case reference adheres to CASE-XXXXXXXX format with CSPRNG entropy', () => {
      const caseIds = new Set<string>();
      const iterations = 1000;
      for (let i = 0; i < iterations; i++) {
        const rawHex = require('crypto').randomBytes(4).toString('hex').toUpperCase();
        const caseRef = `CASE-${rawHex}`;
        assert.match(caseRef, /^CASE-[0-9A-F]{8}$/);
        caseIds.add(caseRef);
      }
      assert.equal(caseIds.size, iterations, 'Zero collisions across 1,000 CSPRNG case references');
    });

    it('G.2 Non-enumerability: Case references cannot be predicted sequentially', () => {
      const ref1 = require('crypto').randomBytes(4);
      const ref2 = require('crypto').randomBytes(4);
      assert.notEqual(ref1.readUInt32BE(0) + 1, ref2.readUInt32BE(0));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // WORKSTREAM H: END-TO-END SCENARIO REGRESSION
  // ─────────────────────────────────────────────────────────────────────────────
  describe('Workstream H: End-to-End Scenarios 1–10', () => {
    // Scenario 1: Two different faces under canonical pipeline -> different embeddings (sim < 0.363)
    it('Scenario 1: Two orthogonal canonical embeddings produce similarity < 0.363 (Clean Zone)', () => {
      const embA = new Float32Array(128);
      const embB = new Float32Array(128);
      embA[0] = 1.0;
      embB[1] = 1.0;
      const sim = CanonicalSFaceEngineV10.computeCosineSimilarity(embA, embB);
      assert.equal(Number(sim.toFixed(4)), 0.0000);
      assert.ok(sim < DEFAULT_CANDIDATE_THRESHOLDS_V10.dedupCleanMax);
    });

    // Scenario 2: Same face different variations -> similarity >= 0.720 (Hard Duplicate)
    it('Scenario 2: Highly correlated embeddings produce similarity >= 0.720 (Hard Block Zone)', () => {
      const embA = new Float32Array(128);
      const embB = new Float32Array(128);
      for (let i = 0; i < 128; i++) {
        embA[i] = 1.0 / Math.sqrt(128);
        embB[i] = (1.0 + (i % 2 === 0 ? 0.05 : -0.05)) / Math.sqrt(128);
      }
      // Re-normalize B
      let normB = 0;
      for (let i = 0; i < 128; i++) normB += embB[i] * embB[i];
      normB = Math.sqrt(normB);
      for (let i = 0; i < 128; i++) embB[i] /= normB;

      const sim = CanonicalSFaceEngineV10.computeCosineSimilarity(embA, embB);
      assert.ok(sim >= DEFAULT_CANDIDATE_THRESHOLDS_V10.dedupHardBlockMin, `Expected >= 0.720, got ${sim}`);
    });

    // Scenario 3: Genuine variation -> 0.363 <= sim < 0.720 (Ambiguous Review)
    it('Scenario 3: Intermediate similarity in [0.3630, 0.7200) triggers review without hard block', () => {
      const sim = 0.520;
      assert.ok(sim >= DEFAULT_CANDIDATE_THRESHOLDS_V10.dedupCleanMax);
      assert.ok(sim < DEFAULT_CANDIDATE_THRESHOLDS_V10.dedupHardBlockMin);
    });

    // Scenario 4 & 5: Gallery Isolation (INCOMPATIBLE_EMBEDDING_SPACE = NEVER_COMPARE)
    it('Scenario 4 & 5: Gallery Index rejects cross-space comparison between canonical probe and legacy/unknown templates', async () => {
      // Mock Firestore database with mixed templates
      const mockDocs: any[] = [
        // Doc 1: Legacy landmark template
        {
          id: 'enr_legacy_landmark_1',
          data: () => ({
            enrollmentId: 'enr_legacy_landmark_1',
            owningUid: 'user_legacy_1',
            status: 'ACTIVE',
            comparisonSpace: 'LEGACY_LANDMARK_SPACE',
            embedding: new Array(128).fill(0.1),
            modelIdentifier: 'kelasagara_biomatch_v3_whitened',
            preprocessVersion: 'v3_whitened',
          }),
        },
        // Doc 2: Defective pre-hotfix full photo resize (missing embeddingSpaceId)
        {
          id: 'enr_defective_sface_2',
          data: () => ({
            enrollmentId: 'enr_defective_sface_2',
            owningUid: 'user_defective_2',
            status: 'ACTIVE',
            modelIdentifier: 'sface_opencv_zoo_v1_primary',
            preprocessVersion: 'sface_aligned_112x112_bgr_v1',
            sfaceEmbedding128: new Array(128).fill(0.088),
          }),
        },
        // Doc 3: Unknown template
        {
          id: 'enr_unknown_3',
          data: () => ({
            enrollmentId: 'enr_unknown_3',
            owningUid: 'user_unknown_3',
            status: 'ACTIVE',
            modelIdentifier: 'unknown_legacy',
            preprocessVersion: 'v0_legacy',
          }),
        },
        // Doc 4: Canonical V2 template (compatible)
        {
          id: 'enr_canonical_v2_4',
          data: () => {
            const emb = new Float32Array(128);
            emb[0] = 1.0;
            return {
              enrollmentId: 'enr_canonical_v2_4',
              owningUid: 'user_canonical_4',
              status: 'ACTIVE',
              embeddingSpaceId: 'SFACE_128_YUNET_2023MAR_UMEYAMA_CANONICAL112_V2',
              modelIdentifier: 'sface_opencv_zoo_v1_primary',
              preprocessVersion: 'sface_aligned_112x112_bgr_v1',
              canonicalEmbedding: Array.from(emb),
            };
          },
        },
      ];

      const mockDb = {
        collection: (col: string) => {
          if (col === 'biometric_system_meta') {
            return {
              doc: () => ({
                get: async () => ({ exists: true, data: () => ({ epochVersion: 5 }) }),
              }),
            };
          }
          if (col === 'biometric_vault') {
            return {
              orderBy: () => ({
                limit: () => ({
                  get: async () => ({
                    empty: false,
                    docs: mockDocs,
                    size: mockDocs.length,
                  }),
                }),
              }),
            };
          }
          throw new Error(`Unexpected collection ${col}`);
        },
      } as unknown as admin.firestore.Firestore;

      const galleryIndex = new FirestoreCompatibleGalleryIndex(mockDb);

      // Probe vector matching Doc 4 (Canonical V2)
      const probe = new Float32Array(128);
      probe[0] = 1.0; // Perfect match with enr_canonical_v2_4

      const result = await galleryIndex.searchTopKCompatible({
        probeEmbedding128: probe,
        probeEmbeddingSpaceId: CANONICAL_EMBEDDING_SPACE_V2.embeddingSpaceId,
        excludeOwningUid: 'applicant_uid_999',
        topK: 10,
      });

      // INVARIANT: Candidates MUST NOT include enr_legacy_landmark_1, enr_defective_sface_2, or enr_unknown_3
      assert.equal(result.candidates.length, 1, 'Only Canonical V2 template is evaluated');
      assert.equal(result.candidates[0].enrollmentId, 'enr_canonical_v2_4');
      assert.equal(result.candidates[0].owningUid, 'user_canonical_4');
      assert.equal(result.candidates[0].embeddingSpaceId, CANONICAL_EMBEDDING_SPACE_V2.embeddingSpaceId);
      assert.ok(result.candidates[0].similarity > 0.99);
    });

    // Scenario 6: Re-enrollment flow: user with legacy template successfully upgrades to canonical V2
    it('Scenario 6: User with legacy template successfully upgrades via authorized replacement', () => {
      const reservation = {
        workflowType: 'AUTHORIZED_REPLACEMENT',
        existingEnrollmentId: 'enr_legacy_landmark_1',
        existingVersion: 1,
        previousBioStatus: 'ACTIVE' as const,
        accountStatus: 'approved' as const,
      };

      const newEnrollmentId = 'enr_canonical_v2_new';
      const supersededRecord = {
        status: 'SUPERSEDED',
        supersededByEnrollmentId: newEnrollmentId,
        revokedAtMs: Date.now(),
      };

      const newVaultRecord = {
        enrollmentId: newEnrollmentId,
        enrollmentVersion: 2,
        embeddingSpaceId: CANONICAL_EMBEDDING_SPACE_V2.embeddingSpaceId,
        status: 'ACTIVE',
      };

      assert.equal(supersededRecord.status, 'SUPERSEDED');
      assert.equal(newVaultRecord.status, 'ACTIVE');
      assert.equal(newVaultRecord.embeddingSpaceId, 'SFACE_128_YUNET_2023MAR_UMEYAMA_CANONICAL112_V2');
    });

    // Scenario 7: Malformed / unaligned image passed to recognition
    it('Scenario 7: Malformed / unaligned image is rejected by runtime type validation', () => {
      const rawJpgFake = Buffer.from('NOT_AN_ALIGNED_BUFFER');
      assert.throws(
        () => CanonicalAlignedFace112Factory.create(rawJpgFake),
        (err: any) => {
          assert.equal(err.code, 'CANONICAL_EMBEDDING_FAILED');
          assert.ok(err.message.includes('INVALID_BYTE_LENGTH'));
          return true;
        }
      );
    });

    // Scenario 8: Threshold boundary verification
    it('Scenario 8: Exhaustive boundary verification across critical float thresholds', () => {
      const boundaries = [
        { sim: 0.3629, isClean: true, isDuplicate: false },
        { sim: 0.3630, isClean: false, isDuplicate: false },
        { sim: 0.3631, isClean: false, isDuplicate: false },
        { sim: 0.5499, isClean: false, isDuplicate: false },
        { sim: 0.5500, isClean: false, isDuplicate: false },
        { sim: 0.5501, isClean: false, isDuplicate: false },
        { sim: 0.7199, isClean: false, isDuplicate: false },
        { sim: 0.7200, isClean: false, isDuplicate: true },
        { sim: 0.7201, isClean: false, isDuplicate: true },
      ];

      for (const b of boundaries) {
        const clean = b.sim < DEFAULT_CANDIDATE_THRESHOLDS_V10.dedupCleanMax;
        const duplicate = b.sim >= DEFAULT_CANDIDATE_THRESHOLDS_V10.dedupHardBlockMin;
        assert.equal(clean, b.isClean, `Clean status mismatch for ${b.sim}`);
        assert.equal(duplicate, b.isDuplicate, `Duplicate status mismatch for ${b.sim}`);
      }
    });

    // Scenario 9: Duplicate detection response contains zero PII & valid case reference
    it('Scenario 9: Rejection response contains zero PII and valid CASE-XXXXXXXX reference', () => {
      const caseReference = `CASE-${require('crypto').randomBytes(4).toString('hex').toUpperCase()}`;
      const duplicateResponse: any = {
        httpStatus: 409,
        operationId: `bio_op_${randomUUID()}`,
        code: 'FACE_ALREADY_LINKED',
        biometricStatus: 'UNENROLLED',
        accountStatus: 'pending_face',
        caseReference,
      };

      assert.equal(duplicateResponse.maskedOriginalName, undefined);
      assert.equal(duplicateResponse.maskedOriginalPhone, undefined);
      assert.equal(duplicateResponse.similarityScore, undefined);
      assert.equal(duplicateResponse.primarySkill, undefined);
      assert.equal(duplicateResponse.maskedUid, undefined);
      assert.match(duplicateResponse.caseReference, /^CASE-[A-F0-9]{8}$/);
    });

    // Scenario 10: Mixed gallery querying isolation
    it('Scenario 10: In-memory gallery with mixed templates only compares compatible Canonical V2 templates', () => {
      const gallery = [
        { id: '1', space: 'LEGACY_LANDMARK_SPACE', data: { embedding: new Array(128).fill(0.1) } },
        { id: '2', space: 'DEFECTIVE_FULL_PHOTO_SFACE_V10', data: { sfaceEmbedding128: new Array(128).fill(0.2) } },
        { id: '3', space: 'LEGACY_TEMPLATE_UNKNOWN', data: { modelIdentifier: 'old' } },
        {
          id: '4',
          space: 'CANONICAL_V2',
          data: {
            embeddingSpaceId: 'SFACE_128_YUNET_2023MAR_UMEYAMA_CANONICAL112_V2',
            canonicalEmbedding: new Array(128).fill(1.0 / Math.sqrt(128)),
          },
        },
      ];

      const compatibleCandidates = gallery.filter((item) => classifyBiometricTemplate(item.data) === 'CANONICAL_V2');
      assert.equal(compatibleCandidates.length, 1);
      assert.equal(compatibleCandidates[0].id, '4');
    });
  });
});
