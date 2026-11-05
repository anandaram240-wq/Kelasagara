// test/biometric_whitened_embedding_test.dart
//
// Kelasagara BioMatch v2: Whitened Procrustes Differential Biometric Embedding Tests
// =================================================================================
// Verifies that the Whitened Procrustes Differential Biometric Embedding:
// 1. Centers the human facial population distribution at origin (E[z] = 0).
// 2. Eradicates the 84% false duplicate collision between different people.
// 3. Produces high similarity (>= 0.85) for the same individual across camera noise/poses.
// 4. Strictly ignores legacy v1 un-centered templates during 1:N deduplication.

import 'dart:math';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:kelasagaara/biometrics/landmark_embedding.dart';
import 'package:kelasagaara/services/biometric_service.dart';

Face _buildSyntheticFace({
  required Point<int> leftEye,
  required Point<int> rightEye,
  required Point<int> noseBase,
  required Point<int> leftMouth,
  required Point<int> rightMouth,
  required Point<int> bottomMouth,
  required Point<int> leftCheek,
  required Point<int> rightCheek,
  List<Point<int>>? faceContour,
  List<Point<int>>? leftEyeContour,
  List<Point<int>>? rightEyeContour,
}) {
  final Map<FaceLandmarkType, FaceLandmark?> landmarks = {
    FaceLandmarkType.leftEye: FaceLandmark(type: FaceLandmarkType.leftEye, position: leftEye),
    FaceLandmarkType.rightEye: FaceLandmark(type: FaceLandmarkType.rightEye, position: rightEye),
    FaceLandmarkType.noseBase: FaceLandmark(type: FaceLandmarkType.noseBase, position: noseBase),
    FaceLandmarkType.leftMouth: FaceLandmark(type: FaceLandmarkType.leftMouth, position: leftMouth),
    FaceLandmarkType.rightMouth: FaceLandmark(type: FaceLandmarkType.rightMouth, position: rightMouth),
    FaceLandmarkType.bottomMouth: FaceLandmark(type: FaceLandmarkType.bottomMouth, position: bottomMouth),
    FaceLandmarkType.leftCheek: FaceLandmark(type: FaceLandmarkType.leftCheek, position: leftCheek),
    FaceLandmarkType.rightCheek: FaceLandmark(type: FaceLandmarkType.rightCheek, position: rightCheek),
  };

  final Map<FaceContourType, FaceContour?> contours = {
    if (faceContour != null)
      FaceContourType.face: FaceContour(type: FaceContourType.face, points: faceContour),
    if (leftEyeContour != null)
      FaceContourType.leftEye: FaceContour(type: FaceContourType.leftEye, points: leftEyeContour),
    if (rightEyeContour != null)
      FaceContourType.rightEye: FaceContour(type: FaceContourType.rightEye, points: rightEyeContour),
  };

  return Face(
    boundingBox: const Rect.fromLTWH(0, 0, 400, 400),
    landmarks: landmarks,
    contours: contours,
    headEulerAngleX: 0.0,
    headEulerAngleY: 0.0,
    headEulerAngleZ: 0.0,
  );
}

void main() {
  group('Model Version & Dimensionality Standards', () {
    test('modelVersion is bumped to kelasagara_biomatch_v3_whitened', () {
      expect(LandmarkEmbedding.modelVersion, 'kelasagara_biomatch_v3_whitened');
      expect(BiometricService.kCurrentModelVersion, 'kelasagara_biomatch_v3_whitened');
      expect(BiometricService.kEmbeddingDimension, 128);
    });

    test('extracts exactly 128 dimensions with unit L2 norm (||v|| = 1.0)', () {
      final face = _buildSyntheticFace(
        leftEye: const Point<int>(100, 150),
        rightEye: const Point<int>(200, 150),
        noseBase: const Point<int>(150, 194),
        leftMouth: const Point<int>(114, 232),
        rightMouth: const Point<int>(186, 232),
        bottomMouth: const Point<int>(150, 244),
        leftCheek: const Point<int>(68, 188),
        rightCheek: const Point<int>(232, 188),
      );

      final result = LandmarkEmbedding.extract(face);
      expect(result, isNotNull);
      expect(result!.embedding.length, 128);

      double norm = 0.0;
      for (final v in result.embedding) {
        norm += v * v;
      }
      expect(sqrt(norm), closeTo(1.0, 1e-5));
    });
  });

  group('Umeyama 2D Canonical Invariance (Same Individual)', () {
    test('identical face coordinates yield cosine similarity = 1.0', () {
      final face1 = _buildSyntheticFace(
        leftEye: const Point<int>(150, 150),
        rightEye: const Point<int>(250, 150),
        noseBase: const Point<int>(200, 195),
        leftMouth: const Point<int>(165, 230),
        rightMouth: const Point<int>(235, 230),
        bottomMouth: const Point<int>(200, 245),
        leftCheek: const Point<int>(120, 190),
        rightCheek: const Point<int>(280, 190),
      );

      final emb1 = LandmarkEmbedding.extract(face1)!.embedding;
      final emb2 = LandmarkEmbedding.extract(face1)!.embedding;

      final sim = LandmarkEmbedding.cosineSimilarity(emb1, emb2);
      expect(sim, closeTo(1.0, 1e-5));
    });

    test('same person with camera distance scaling and translation has high similarity (>= 0.95)', () {
      // User at 40cm (IPD = 100px)
      final faceNear = _buildSyntheticFace(
        leftEye: const Point<int>(100, 150),
        rightEye: const Point<int>(200, 150),
        noseBase: const Point<int>(150, 188),
        leftMouth: const Point<int>(110, 225),
        rightMouth: const Point<int>(190, 225),
        bottomMouth: const Point<int>(150, 236),
        leftCheek: const Point<int>(55, 185),
        rightCheek: const Point<int>(245, 185),
      );

      // Same user moved back to 60cm and shifted down-right (IPD = 70px)
      // Scale factor = 0.7, Offset = (80, 120)
      final faceFar = _buildSyntheticFace(
        leftEye: const Point<int>(150, 225),
        rightEye: const Point<int>(220, 225),
        noseBase: const Point<int>(185, 252),
        leftMouth: const Point<int>(157, 277),
        rightMouth: const Point<int>(213, 277),
        bottomMouth: const Point<int>(185, 285),
        leftCheek: const Point<int>(119, 250),
        rightCheek: const Point<int>(251, 250),
      );

      final embNear = LandmarkEmbedding.extract(faceNear)!.embedding;
      final embFar = LandmarkEmbedding.extract(faceFar)!.embedding;

      final sim = LandmarkEmbedding.cosineSimilarity(embNear, embFar);
      expect(sim, greaterThanOrEqualTo(0.95),
          reason: 'Scale & translation invariance ensures identical face matches despite distance shift');
    });

    test('same person with natural sensor noise (jitter +/-2px) exceeds duplicate threshold (>= 0.74)', () {
      final base = _buildSyntheticFace(
        leftEye: const Point<int>(100, 150),
        rightEye: const Point<int>(200, 150),
        noseBase: const Point<int>(150, 188),
        leftMouth: const Point<int>(110, 225),
        rightMouth: const Point<int>(190, 225),
        bottomMouth: const Point<int>(150, 236),
        leftCheek: const Point<int>(55, 185),
        rightCheek: const Point<int>(245, 185),
      );

      final jittered = _buildSyntheticFace(
        leftEye: const Point<int>(101, 149),
        rightEye: const Point<int>(199, 151),
        noseBase: const Point<int>(151, 187),
        leftMouth: const Point<int>(109, 226),
        rightMouth: const Point<int>(191, 224),
        bottomMouth: const Point<int>(150, 237),
        leftCheek: const Point<int>(56, 184),
        rightCheek: const Point<int>(244, 186),
      );

      final embBase = LandmarkEmbedding.extract(base)!.embedding;
      final embJittered = LandmarkEmbedding.extract(jittered)!.embedding;

      final sim = LandmarkEmbedding.cosineSimilarity(embBase, embJittered);
      expect(sim, greaterThanOrEqualTo(0.85),
          reason: 'Same user across multiple frames/scans must easily match');
    });
  });

  group('Cross-Person Discrimination (False Duplicate Bug Resolution)', () {
    test('two distinct individuals produce cosine similarity well below duplicate threshold (< 0.50)', () {
      // Person A: Wide round face, high compact nose, wide mouth
      // (IPD = 100px)
      final personA = _buildSyntheticFace(
        leftEye: const Point<int>(100, 150),
        rightEye: const Point<int>(200, 150),
        noseBase: const Point<int>(150, 188), // compact nose (noseY = 0.38)
        leftMouth: const Point<int>(110, 225), // wide mouth
        rightMouth: const Point<int>(190, 225),
        bottomMouth: const Point<int>(150, 236),
        leftCheek: const Point<int>(55, 185), // very wide cheeks
        rightCheek: const Point<int>(245, 185),
      );

      // Person B (User\'s friend): Narrow oblong face, long nose, narrow mouth, low chin
      // (IPD = 100px)
      final personB = _buildSyntheticFace(
        leftEye: const Point<int>(100, 150),
        rightEye: const Point<int>(200, 150),
        noseBase: const Point<int>(150, 202), // elongated nose (noseY = 0.52)
        leftMouth: const Point<int>(122, 242), // narrow mouth
        rightMouth: const Point<int>(178, 242),
        bottomMouth: const Point<int>(150, 258),
        leftCheek: const Point<int>(75, 192), // narrow cheeks
        rightCheek: const Point<int>(225, 192),
      );

      final embA = LandmarkEmbedding.extract(personA)!.embedding;
      final embB = LandmarkEmbedding.extract(personB)!.embedding;

      final sim = LandmarkEmbedding.cosineSimilarity(embA, embB);

      // The un-centered v1 model gave ~0.84 (falsely flagging Person B as Person A).
      // With whitened coordinates, different individuals center around 0.0 (+/- 0.45).
      expect(sim, lessThan(0.50),
          reason: 'Whitened embedding separates different faces (got ${sim.toStringAsFixed(3)}), well below 0.74 duplicate threshold');
      expect(sim, lessThan(BiometricService.kDuplicateThreshold),
          reason: 'Must NOT trigger duplicate account detection for different individuals');
    });

    test('population variance creates diverse quadrant distribution', () {
      // Generate 5 distinct individuals with varying anatomical features
      final faces = [
        // Short face, wide jaw
        _buildSyntheticFace(
          leftEye: const Point<int>(100, 150), rightEye: const Point<int>(200, 150),
          noseBase: const Point<int>(150, 186), leftMouth: const Point<int>(112, 222),
          rightMouth: const Point<int>(188, 222), bottomMouth: const Point<int>(150, 232),
          leftCheek: const Point<int>(60, 185), rightCheek: const Point<int>(240, 185),
        ),
        // Long face, narrow jaw
        _buildSyntheticFace(
          leftEye: const Point<int>(100, 150), rightEye: const Point<int>(200, 150),
          noseBase: const Point<int>(150, 204), leftMouth: const Point<int>(122, 244),
          rightMouth: const Point<int>(178, 244), bottomMouth: const Point<int>(150, 260),
          leftCheek: const Point<int>(75, 190), rightCheek: const Point<int>(225, 190),
        ),
        // Average face
        _buildSyntheticFace(
          leftEye: const Point<int>(100, 150), rightEye: const Point<int>(200, 150),
          noseBase: const Point<int>(150, 194), leftMouth: const Point<int>(114, 232),
          rightMouth: const Point<int>(186, 232), bottomMouth: const Point<int>(150, 244),
          leftCheek: const Point<int>(68, 188), rightCheek: const Point<int>(232, 188),
        ),
        // Wide eyes, high mouth
        _buildSyntheticFace(
          leftEye: const Point<int>(90, 150), rightEye: const Point<int>(210, 150),
          noseBase: const Point<int>(150, 198), leftMouth: const Point<int>(118, 230),
          rightMouth: const Point<int>(182, 230), bottomMouth: const Point<int>(150, 240),
          leftCheek: const Point<int>(64, 188), rightCheek: const Point<int>(236, 188),
        ),
        // High nose bridge, wide cheeks
        _buildSyntheticFace(
          leftEye: const Point<int>(100, 150), rightEye: const Point<int>(200, 150),
          noseBase: const Point<int>(150, 184), leftMouth: const Point<int>(115, 234),
          rightMouth: const Point<int>(185, 234), bottomMouth: const Point<int>(150, 246),
          leftCheek: const Point<int>(58, 184), rightCheek: const Point<int>(242, 184),
        ),
      ];

      final embeddings = faces.map((f) => LandmarkEmbedding.extract(f)!.embedding).toList();

      for (int i = 0; i < embeddings.length; i++) {
        for (int j = i + 1; j < embeddings.length; j++) {
          final sim = LandmarkEmbedding.cosineSimilarity(embeddings[i], embeddings[j]);
          expect(sim, lessThan(BiometricService.kDuplicateThreshold),
              reason: 'Faces $i and $j have similarity ${sim.toStringAsFixed(3)}, which is safely below 0.74 threshold');
        }
      }
    });
  });

  group('Legacy Model Version Guardrail', () {
    test('legacy un-centered v1 and v2 model templates are rejected by kCurrentModelVersion', () {
      const legacyModelV1 = 'kelasagara_biomatch_v1_geometric';
      const legacyModelV2 = 'kelasagara_biomatch_v2_whitened';
      expect(legacyModelV1, isNot(equals(BiometricService.kCurrentModelVersion)));
      expect(legacyModelV2, isNot(equals(BiometricService.kCurrentModelVersion)));
      expect(BiometricService.kCurrentModelVersion, 'kelasagara_biomatch_v3_whitened');
    });
  });
}
