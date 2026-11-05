// test/biometric_deduplication_engine_test.dart
//
// KELASAGARA-BIOMATCH: 1:N Biometric De-Duplication Engine Tests
// Comprehensive verification of mathematical metric learning primitives,
// threshold calibration, phone masking, and Sybil fraud interception.

import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelasagaara/services/biometric_service.dart';

void main() {
  group('Biometric Constants & Standards', () {
    test('embedding dimensionality is exactly 128', () {
      expect(BiometricService.kEmbeddingDimension, 128);
    });

    test('duplicate threshold matches Aadhaar/NIST calibration (0.74)', () {
      expect(BiometricService.kDuplicateThreshold, 0.74);
    });

    test('ambiguity threshold is 0.65', () {
      expect(BiometricService.kAmbiguityThreshold, 0.65);
      expect(BiometricService.kAmbiguityThreshold, lessThan(BiometricService.kDuplicateThreshold));
    });
  });

  group('Vector L2 Normalization (Unit Hypersphere S^127)', () {
    test('normalizes any non-zero vector to unit length ||v|| = 1.0', () {
      final raw = List.generate(128, (i) => (i + 1).toDouble());
      final normalized = BiometricService.l2Normalize(raw);

      expect(normalized.length, 128);

      double norm = 0.0;
      for (final v in normalized) {
        norm += v * v;
      }
      expect(sqrt(norm), closeTo(1.0, 1e-6));
    });

    test('already normalized vector remains unchanged', () {
      final unit = List.filled(128, 0.0);
      unit[0] = 1.0; // ||v|| = 1.0
      final normalized = BiometricService.l2Normalize(unit);
      expect(normalized[0], 1.0);
      expect(normalized[1], 0.0);
    });

    test('zero vector handles gracefully without division by zero', () {
      final zeros = List.filled(128, 0.0);
      final normalized = BiometricService.l2Normalize(zeros);
      expect(normalized.length, 128);
      expect(normalized.every((v) => v == 0.0), isTrue);
    });
  });

  group('Cosine Similarity Metric Primitives', () {
    test('identical vectors yield cosine similarity = 1.0', () {
      final v1 = BiometricService.l2Normalize(List.generate(128, (i) => sin(i.toDouble())));
      final sim = BiometricService.cosineSimilarity(v1, v1);
      expect(sim, closeTo(1.0, 1e-5));
    });

    test('orthogonal vectors yield cosine similarity = 0.0', () {
      final v1 = List.filled(128, 0.0);
      final v2 = List.filled(128, 0.0);
      v1[0] = 1.0;
      v2[1] = 1.0;

      final sim = BiometricService.cosineSimilarity(v1, v2);
      expect(sim, closeTo(0.0, 1e-6));
    });

    test('opposite vectors yield cosine similarity = -1.0', () {
      final v1 = List.filled(128, 0.0);
      final v2 = List.filled(128, 0.0);
      v1[0] = 1.0;
      v2[0] = -1.0;

      final sim = BiometricService.cosineSimilarity(v1, v2);
      expect(sim, closeTo(-1.0, 1e-6));
    });

    test('same human with micro-variations (88% similarity) is recognized as duplicate', () {
      // Base facial vector
      final base = BiometricService.l2Normalize(List.generate(128, (i) => sin(i * 0.1)));
      // Perturbed vector representing minor lighting/angle change (same human)
      final perturbed = BiometricService.l2Normalize(
        List.generate(128, (i) => base[i] + (i % 5 == 0 ? 0.08 : -0.02)),
      );

      final sim = BiometricService.cosineSimilarity(base, perturbed);
      expect(sim, greaterThanOrEqualTo(BiometricService.kDuplicateThreshold));
      expect(sim, greaterThan(0.80));
    });

    test('completely different stranger (32% similarity) is recognized as distinct', () {
      final personA = BiometricService.l2Normalize(List.generate(128, (i) => sin(i * 0.2)));
      final personB = BiometricService.l2Normalize(List.generate(128, (i) => cos(i * 0.7 + 1.2)));

      final sim = BiometricService.cosineSimilarity(personA, personB);
      expect(sim, lessThan(BiometricService.kAmbiguityThreshold));
      expect(sim, lessThan(0.50));
    });
  });

  group('Phone Masking (DPDPA 2023 Privacy Compliance)', () {
    test('masks standard 10-digit Indian mobile number', () {
      expect(BiometricService.maskPhoneNumber('9845012345'), '******2345');
    });

    test('masks +91 prefixed mobile number', () {
      expect(BiometricService.maskPhoneNumber('+919845012345'), '+91 ******2345');
    });

    test('masks formatted mobile with spaces', () {
      expect(BiometricService.maskPhoneNumber('+91 98450 12345'), '+91 ******2345');
    });

    test('handles short/empty input safely', () {
      expect(BiometricService.maskPhoneNumber(''), '');
      expect(BiometricService.maskPhoneNumber('12'), '');
    });
  });

  group('Landmark Metric Feature Encoder', () {
    test('generates unit-normalized 128-D vector', () {
      final vec = BiometricService.generateEmbeddingFromLandmarks(
        eyeDistance: 0.42,
        eyeToNoseRatio: 0.35,
        eyeToMouthRatio: 0.58,
        mouthWidth: 0.38,
        jawCurvature: 1.15,
        headEulerYaw: 2.5,
        headEulerRoll: -1.2,
      );

      expect(vec.length, 128);

      double norm = 0.0;
      for (final v in vec) {
        norm += v * v;
      }
      expect(sqrt(norm), closeTo(1.0, 1e-5));
    });

    test('same person with identical facial landmarks yields 1.0 similarity', () {
      final vec1 = BiometricService.generateEmbeddingFromLandmarks(
        eyeDistance: 0.44,
        eyeToNoseRatio: 0.36,
        eyeToMouthRatio: 0.59,
        mouthWidth: 0.40,
        jawCurvature: 1.10,
        headEulerYaw: 0.0,
        headEulerRoll: 0.0,
      );

      final vec2 = BiometricService.generateEmbeddingFromLandmarks(
        eyeDistance: 0.44,
        eyeToNoseRatio: 0.36,
        eyeToMouthRatio: 0.59,
        mouthWidth: 0.40,
        jawCurvature: 1.10,
        headEulerYaw: 0.0,
        headEulerRoll: 0.0,
      );

      final sim = BiometricService.cosineSimilarity(vec1, vec2);
      expect(sim, closeTo(1.0, 1e-5));
    });

    test('two completely different facial structures produce distinct vectors (Sim < 0.65)', () {
      // Person 1: Narrow face, wide eyes
      final person1 = BiometricService.generateEmbeddingFromLandmarks(
        eyeDistance: 0.55,
        eyeToNoseRatio: 0.28,
        eyeToMouthRatio: 0.48,
        mouthWidth: 0.32,
        jawCurvature: 0.75,
        headEulerYaw: 0.0,
        headEulerRoll: 0.0,
      );

      // Person 2: Broad face, close eyes, tall midface
      final person2 = BiometricService.generateEmbeddingFromLandmarks(
        eyeDistance: 0.32,
        eyeToNoseRatio: 0.45,
        eyeToMouthRatio: 0.72,
        mouthWidth: 0.48,
        jawCurvature: 1.45,
        headEulerYaw: 5.0,
        headEulerRoll: 3.0,
      );

      final sim = BiometricService.cosineSimilarity(person1, person2);
      expect(sim, lessThan(BiometricService.kDuplicateThreshold));
      expect(sim, lessThan(0.65));
    });

    test('same person with natural camera distance & pose jitter (2-4%) yields similarity >= 0.74 (intercepted as duplicate)', () {
      final session1 = BiometricService.generateEmbeddingFromLandmarks(
        eyeDistance: 0.44,
        eyeToNoseRatio: 0.36,
        eyeToMouthRatio: 0.59,
        mouthWidth: 0.40,
        jawCurvature: 1.10,
        headEulerYaw: 0.0,
        headEulerRoll: 0.0,
      );

      // Session 2: 2-3% natural shift from phone distance, slight yaw/roll
      final session2 = BiometricService.generateEmbeddingFromLandmarks(
        eyeDistance: 0.448,
        eyeToNoseRatio: 0.364,
        eyeToMouthRatio: 0.585,
        mouthWidth: 0.405,
        jawCurvature: 1.09,
        headEulerYaw: 0.5,
        headEulerRoll: -0.3,
      );

      final sim = BiometricService.cosineSimilarity(session1, session2);
      expect(sim, greaterThanOrEqualTo(BiometricService.kDuplicateThreshold));
      expect(sim, greaterThan(0.80));
    });
  });

  group('Sybil Attack & De-Duplication Simulation Contract', () {
    test('BiometricCheckResult duplicateFound payload contract', () {
      final res = BiometricCheckResult.duplicateFound(
        matchedUid: 'user_ramu_original',
        maskedPhone: '+91 ******4812',
        maxSimilarity: 0.89,
        message: 'Duplicate face detected',
      );

      expect(res.isDuplicate, isTrue);
      expect(res.isApproved, isFalse);
      expect(res.matchedUid, 'user_ramu_original');
      expect(res.maskedPhone, '+91 ******4812');
      expect(res.maxSimilarity, 0.89);
      expect(res.status, BiometricStatus.duplicateFound);
    });

    test('BiometricCheckResult duplicateFound preserves all 6 masked candidate details', () {
      final res = BiometricCheckResult.duplicateFound(
        matchedUid: 'user_ramu_original',
        maskedPhone: '+91 ••••••4812',
        maskedName: 'Ra••• Ku•••',
        maskedUserId: '@ram••••',
        primarySkill: 'Plumber',
        dailyRateDisplay: '₹850/day',
        similarityPercent: 91,
        maxSimilarity: 0.912,
        message: 'Duplicate face detected',
      );

      expect(res.isDuplicate, isTrue);
      expect(res.isApproved, isFalse);
      expect(res.matchedUid, 'user_ramu_original');
      expect(res.maskedPhone, '+91 ••••••4812');
      expect(res.maskedName, 'Ra••• Ku•••');
      expect(res.maskedUserId, '@ram••••');
      expect(res.primarySkill, 'Plumber');
      expect(res.dailyRateDisplay, '₹850/day');
      expect(res.similarityPercent, 91);
      expect(res.maxSimilarity, 0.912);
      expect(res.status, BiometricStatus.duplicateFound);
    });

    test('BiometricCheckResult approved payload contract', () {
      final res = BiometricCheckResult.approved(maxSimilarity: 0.42);

      expect(res.isApproved, isTrue);
      expect(res.isDuplicate, isFalse);
      expect(res.matchedUid, isNull);
      expect(res.maxSimilarity, 0.42);
      expect(res.status, BiometricStatus.approved);
    });

    test('BiometricCheckResult error payload contract', () {
      final res = BiometricCheckResult.error('Database connection timed out');

      expect(res.isApproved, isFalse);
      expect(res.isDuplicate, isFalse);
      expect(res.status, BiometricStatus.error);
      expect(res.message, contains('timed out'));
    });
  });

  // ────────────────────────────────────────────────────────────────
  // SECTION: Realistic End-to-End 1:N Gallery Duplicate Search Test
  // ────────────────────────────────────────────────────────────────
  group('1:N Biometric Gallery Duplicate Identification in Action', () {
    test('identifies duplicate face when user creates 2nd account with new phone', () {
      // 1. Simulating registered users in biometric_vault
      final gallery = <Map<String, dynamic>>[
        {
          'uid': 'user_suresh_001',
          'phoneNumber': '+91 98450 11111',
          'embedding': BiometricService.generateEmbeddingFromLandmarks(
            eyeDistance: 0.35, eyeToNoseRatio: 0.40, eyeToMouthRatio: 0.60,
            mouthWidth: 0.35, jawCurvature: 1.10, headEulerYaw: 0.0, headEulerRoll: 0.0,
          ),
        },
        {
          'uid': 'user_ramu_original',
          'phoneNumber': '+91 98450 22222',
          // Ramu's registered face
          'embedding': BiometricService.generateEmbeddingFromLandmarks(
            eyeDistance: 0.48, eyeToNoseRatio: 0.32, eyeToMouthRatio: 0.52,
            mouthWidth: 0.42, jawCurvature: 0.95, headEulerYaw: 0.0, headEulerRoll: 0.0,
          ),
        },
        {
          'uid': 'user_manjunath_003',
          'phoneNumber': '+91 98450 33333',
          'embedding': BiometricService.generateEmbeddingFromLandmarks(
            eyeDistance: 0.40, eyeToNoseRatio: 0.45, eyeToMouthRatio: 0.68,
            mouthWidth: 0.38, jawCurvature: 1.30, headEulerYaw: 0.0, headEulerRoll: 0.0,
          ),
        },
      ];

      // 2. Ramu buys a new SIM card (+91 98450 99999) and tries to register account 2
      // His face has slight variations (lighting, slight head tilt = 2 degrees)
      final ramuSecondAccountFace = BiometricService.generateEmbeddingFromLandmarks(
        eyeDistance: 0.48, eyeToNoseRatio: 0.32, eyeToMouthRatio: 0.52,
        mouthWidth: 0.42, jawCurvature: 0.95, headEulerYaw: 2.0, headEulerRoll: 1.0,
      );

      // 3. Perform 1:N Search across gallery
      double maxSim = -1.0;
      Map<String, dynamic>? matchedUser;

      for (final candidate in gallery) {
        final enrolled = candidate['embedding'] as List<double>;
        final sim = BiometricService.cosineSimilarity(ramuSecondAccountFace, enrolled);
        if (sim > maxSim) {
          maxSim = sim;
          matchedUser = candidate;
        }
      }

      // 4. Verify Duplicate IS IDENTIFIED
      expect(maxSim, greaterThanOrEqualTo(BiometricService.kDuplicateThreshold),
        reason: 'Cosine similarity must exceed 0.74 duplicate threshold');
      expect(matchedUser, isNotNull);
      expect(matchedUser!['uid'], 'user_ramu_original',
        reason: 'Must match Ramu\'s original account UID');

      // 5. Verify masked phone is formatted properly for UI alert
      final masked = BiometricService.maskPhoneNumber(matchedUser['phoneNumber'] as String);
      expect(masked, '+91 ******2222',
        reason: 'Must mask Ramu\'s original phone number to protect privacy');
    });

    test('permits registration when a genuinely new person registers', () {
      final gallery = <Map<String, dynamic>>[
        {
          'uid': 'user_ramu_original',
          'phoneNumber': '+91 98450 22222',
          'embedding': BiometricService.generateEmbeddingFromLandmarks(
            eyeDistance: 0.48, eyeToNoseRatio: 0.32, eyeToMouthRatio: 0.52,
            mouthWidth: 0.42, jawCurvature: 0.95, headEulerYaw: 0.0, headEulerRoll: 0.0,
          ),
        },
      ];

      // New person with completely different face geometry
      final newStrangerFace = BiometricService.generateEmbeddingFromLandmarks(
        eyeDistance: 0.31, eyeToNoseRatio: 0.48, eyeToMouthRatio: 0.70,
        mouthWidth: 0.34, jawCurvature: 1.40, headEulerYaw: 0.0, headEulerRoll: 0.0,
      );

      double maxSim = -1.0;
      for (final candidate in gallery) {
        final enrolled = candidate['embedding'] as List<double>;
        final sim = BiometricService.cosineSimilarity(newStrangerFace, enrolled);
        if (sim > maxSim) maxSim = sim;
      }

      // Verify new person is NOT identified as duplicate
      expect(maxSim, lessThan(BiometricService.kDuplicateThreshold));
      expect(maxSim, lessThan(0.65),
        reason: 'Distinct stranger must have low similarity');
    });
  });
}
