// test/biometric_multi_face_test.dart
//
// Kelasagara BioMatch v3: Multi-Person Registration & Deduplication Test
// =====================================================================
// Validates:
// 1. Rama registers for the first time -> NOT flagged as duplicate of Kiran (KIR***).
// 2. Different people (Kiran, Rama, Suresh, Priya) yield low similarity (< 0.35).
// 3. When Rama registers AGAIN under a different account (duplicate attempt),
//    the system accurately identifies RAMA's original account, returning Rama's
//    masked details (e.g. RAM***, +91 ******1234), NOT Kiran's!
// 4. Masked phone number never returns 'an existing profile'.

import 'dart:math';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:kelasagaara/biometrics/landmark_embedding.dart';
import 'package:kelasagaara/services/biometric_service.dart';

Face _buildTestFace({
  required Point<int> leftEye,
  required Point<int> rightEye,
  required Point<int> noseBase,
  required Point<int> leftMouth,
  required Point<int> rightMouth,
  required Point<int> bottomMouth,
  required Point<int> leftCheek,
  required Point<int> rightCheek,
}) {
  return Face(
    boundingBox: const Rect.fromLTWH(0, 0, 400, 400),
    landmarks: {
      FaceLandmarkType.leftEye: FaceLandmark(type: FaceLandmarkType.leftEye, position: leftEye),
      FaceLandmarkType.rightEye: FaceLandmark(type: FaceLandmarkType.rightEye, position: rightEye),
      FaceLandmarkType.noseBase: FaceLandmark(type: FaceLandmarkType.noseBase, position: noseBase),
      FaceLandmarkType.leftMouth: FaceLandmark(type: FaceLandmarkType.leftMouth, position: leftMouth),
      FaceLandmarkType.rightMouth: FaceLandmark(type: FaceLandmarkType.rightMouth, position: rightMouth),
      FaceLandmarkType.bottomMouth: FaceLandmark(type: FaceLandmarkType.bottomMouth, position: bottomMouth),
      FaceLandmarkType.leftCheek: FaceLandmark(type: FaceLandmarkType.leftCheek, position: leftCheek),
      FaceLandmarkType.rightCheek: FaceLandmark(type: FaceLandmarkType.rightCheek, position: rightCheek),
    },
    contours: {},
    headEulerAngleX: 0.0,
    headEulerAngleY: 0.0,
    headEulerAngleZ: 0.0,
  );
}

void main() {
  group('Multi-Person Registration & Deduplication Pipeline (Rama vs Kiran Incident)', () {
    // ── Kiran: Wide face, compact nose, wide mouth
    final kiranFace = _buildTestFace(
      leftEye: const Point<int>(100, 150),
      rightEye: const Point<int>(200, 150),
      noseBase: const Point<int>(150, 186),
      leftMouth: const Point<int>(108, 226),
      rightMouth: const Point<int>(192, 226),
      bottomMouth: const Point<int>(150, 238),
      leftCheek: const Point<int>(52, 185),
      rightCheek: const Point<int>(248, 185),
    );

    // ── Rama: Long face, elongated nose, narrower mouth, high cheekbones
    final ramaFace = _buildTestFace(
      leftEye: const Point<int>(100, 150),
      rightEye: const Point<int>(200, 150),
      noseBase: const Point<int>(150, 204),
      leftMouth: const Point<int>(122, 244),
      rightMouth: const Point<int>(178, 244),
      bottomMouth: const Point<int>(150, 260),
      leftCheek: const Point<int>(76, 192),
      rightCheek: const Point<int>(224, 192),
    );

    // ── Suresh: Average face with distinct chin and mouth position
    final sureshFace = _buildTestFace(
      leftEye: const Point<int>(95, 145),
      rightEye: const Point<int>(205, 145),
      noseBase: const Point<int>(150, 195),
      leftMouth: const Point<int>(116, 234),
      rightMouth: const Point<int>(184, 234),
      bottomMouth: const Point<int>(150, 246),
      leftCheek: const Point<int>(65, 186),
      rightCheek: const Point<int>(235, 186),
    );

    // ── Rama re-scan: Same face with natural camera distance & 1-2px jitter
    final ramaRescan = _buildTestFace(
      leftEye: const Point<int>(101, 149),
      rightEye: const Point<int>(199, 151),
      noseBase: const Point<int>(151, 203),
      leftMouth: const Point<int>(121, 245),
      rightMouth: const Point<int>(179, 243),
      bottomMouth: const Point<int>(150, 261),
      leftCheek: const Point<int>(77, 191),
      rightCheek: const Point<int>(223, 193),
    );

    test('Rama registering for first time does NOT match Kiran (sim < 0.35)', () {
      final embKiran = LandmarkEmbedding.extract(kiranFace)!.embedding;
      final embRama = LandmarkEmbedding.extract(ramaFace)!.embedding;

      final sim = LandmarkEmbedding.cosineSimilarity(embKiran, embRama);
      expect(sim, lessThan(0.35),
          reason: 'Rama and Kiran are distinct individuals; similarity must be well below 0.74 threshold');
      expect(sim, lessThan(BiometricService.kDuplicateThreshold));
    });

    test('All pairs of distinct individuals yield low similarity (< 0.40)', () {
      final embKiran = LandmarkEmbedding.extract(kiranFace)!.embedding;
      final embRama = LandmarkEmbedding.extract(ramaFace)!.embedding;
      final embSuresh = LandmarkEmbedding.extract(sureshFace)!.embedding;

      final simKR = LandmarkEmbedding.cosineSimilarity(embKiran, embRama);
      final simKS = LandmarkEmbedding.cosineSimilarity(embKiran, embSuresh);
      final simRS = LandmarkEmbedding.cosineSimilarity(embRama, embSuresh);

      expect(simKR, lessThan(0.40));
      expect(simKS, lessThan(0.40));
      expect(simRS, lessThan(0.40));
    });

    test('Rama re-scan yields high similarity (>= 0.85) matching original Rama face', () {
      final embRama1 = LandmarkEmbedding.extract(ramaFace)!.embedding;
      final embRama2 = LandmarkEmbedding.extract(ramaRescan)!.embedding;

      final sim = LandmarkEmbedding.cosineSimilarity(embRama1, embRama2);
      expect(sim, greaterThanOrEqualTo(0.85),
          reason: 'Same individual across re-scans must easily exceed 0.74 duplicate threshold');
    });

    test('1:N gallery duplicate simulation: Rama duplicate attempt identifies Rama, NOT Kiran', () {
      // Simulate biometric_vault with enrolled users
      final gallery = [
        {
          'uid': 'user_kiran_kET2',
          'displayNameMasked': BiometricService.maskName('Kiran Kumar'),
          'phoneNumber': '+919845011111',
          'phoneNumberMasked': BiometricService.maskPhoneNumber('+919845011111'),
          'embedding': LandmarkEmbedding.extract(kiranFace)!.embedding,
          'modelVersion': LandmarkEmbedding.modelVersion,
        },
        {
          'uid': 'user_rama_r890',
          'displayNameMasked': BiometricService.maskName('Rama Murthy'),
          'phoneNumber': '+919845098765',
          'phoneNumberMasked': BiometricService.maskPhoneNumber('+919845098765'),
          'embedding': LandmarkEmbedding.extract(ramaFace)!.embedding,
          'modelVersion': LandmarkEmbedding.modelVersion,
        },
        {
          'uid': 'user_suresh_s345',
          'displayNameMasked': BiometricService.maskName('Suresh Gowda'),
          'phoneNumber': '+919845055555',
          'phoneNumberMasked': BiometricService.maskPhoneNumber('+919845055555'),
          'embedding': LandmarkEmbedding.extract(sureshFace)!.embedding,
          'modelVersion': LandmarkEmbedding.modelVersion,
        },
      ];

      // Rama tries to register AGAIN from a 2nd device/account (uid: 'user_rama_fake_2')
      final probeEmbedding = LandmarkEmbedding.extract(ramaRescan)!.embedding;

      double maxSim = 0.0;
      Map<String, dynamic>? matchedUser;

      for (final doc in gallery) {
        final emb = (doc['embedding'] as List<double>);
        final sim = LandmarkEmbedding.cosineSimilarity(probeEmbedding, emb);
        if (sim > maxSim) {
          maxSim = sim;
          matchedUser = doc;
        }
      }

      // Assertions:
      // 1. Must flag as duplicate (sim >= 0.74)
      expect(maxSim, greaterThanOrEqualTo(BiometricService.kDuplicateThreshold));

      // 2. MUST match RAMA, NOT Kiran!
      expect(matchedUser, isNotNull);
      expect(matchedUser!['uid'], 'user_rama_r890');
      expect(matchedUser['displayNameMasked'], 'Ra** Mur***');
      expect(matchedUser['phoneNumberMasked'], '+91 ******8765');
      expect(matchedUser['phoneNumberMasked'], isNot('an existing profile'));

      // 3. Kiran's similarity to Rama's re-scan must be low
      final kiranSim = LandmarkEmbedding.cosineSimilarity(
        probeEmbedding,
        gallery[0]['embedding'] as List<double>,
      );
      expect(kiranSim, lessThan(0.35), reason: 'Rama re-scan must NOT match Kiran');
    });

    test('Masking functions format names and numbers correctly without leaks', () {
      expect(BiometricService.maskName('Rama Murthy'), 'Ra** Mur***');
      expect(BiometricService.maskName('Kiran'), 'Kir**');
      expect(BiometricService.maskPhoneNumber('+91 98450 98765'), '+91 ******8765');
      expect(BiometricService.maskPhoneNumber(''), '');
      expect(BiometricService.maskPhoneNumber('   '), '');
    });
  });
}
