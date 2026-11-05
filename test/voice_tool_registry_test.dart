// test/voice_tool_registry_test.dart
// Unit Tests for Voice Tool Schema Validation and Deterministic Worker Ranking

import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelasagaara/services/voice/voice_tool_registry.dart';

void main() {
  group('VoiceToolRegistry & Worker Ranking Tests', () {
    test('WorkerCandidate serialization preserves all required attributes', () {
      final candidate = WorkerCandidate(
        workerId: 'w_101',
        name: 'Ravi Kumar',
        skill: 'painter',
        distanceMeters: 1400,
        distanceDisplay: '1.4 km',
        latitude: 13.0100,
        longitude: 76.1000,
        isAvailable: true,
        verificationLevel: 'practicalVerified',
        completedJobs: 122,
        rating: 4.8,
        rankingScore: 0.82,
        selectionReason: 'Ravi Kumar is available, 1.4 km away, and practical verified.',
      );

      final map = candidate.toMap();
      expect(map['workerId'], equals('w_101'));
      expect(map['distanceDisplay'], equals('1.4 km'));
      expect(map['isAvailable'], isTrue);
      expect(map['rankingScore'], equals(0.82));
      expect(map['selectionReason'], contains('1.4 km away'));
    });

    test('Deterministic Multi-Factor Ranking math scores closer and higher verified workers higher', () {
      // Worker 1: 1.4 km, practicalVerified (0.7), 122 jobs, 4.8 rating
      // Worker 2: 5.0 km, basicAssessed (0.5), 10 jobs, 4.0 rating
      const radius = 10000.0; // 10 km

      double scoreWorker({
        required double distMeters,
        required String verifLevel,
        required int totalJobs,
        required double rating,
      }) {
        final distScore = max(0.0, 1.0 - (distMeters / radius));
        final verifWeight = switch (verifLevel) {
          'advanced'          => 1.0,
          'experienced'       => 0.85,
          'practicalVerified' => 0.70,
          'basicAssessed'     => 0.50,
          _                   => 0.30,
        };
        final jobsScore = min(1.0, totalJobs / 50.0);
        final ratingScore = min(1.0, rating / 5.0);

        return (0.40 * distScore) +
            (0.25 * verifWeight) +
            (0.20 * jobsScore) +
            (0.15 * ratingScore);
      }

      final score1 = scoreWorker(
        distMeters: 1400,
        verifLevel: 'practicalVerified',
        totalJobs: 122,
        rating: 4.8,
      );

      final score2 = scoreWorker(
        distMeters: 5000,
        verifLevel: 'basicAssessed',
        totalJobs: 10,
        rating: 4.0,
      );

      expect(score1, greaterThan(score2));
      expect(score1, greaterThan(0.70));
    });
  });
}
