// test/frame_budget_isolate_engine_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kelasagaara/core/performance/frame_budget_isolate_engine.dart';
import 'package:kelasagaara/widgets/voice/siri_fluid_orb.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FrameBudgetGuardian Realtime Monitor Tests', () {
    test('singleton instance exists and defaults to highPerformanceTierActive = true', () {
      final guardian = FrameBudgetGuardian.instance;
      expect(guardian.highPerformanceTierActive.value, isTrue);
    });

    test('attachToScheduler handles repeated calls safely without error', () {
      expect(() => FrameBudgetGuardian.instance.attachToScheduler(), returnsNormally);
      expect(() => FrameBudgetGuardian.instance.attachToScheduler(), returnsNormally);
    });
  });

  group('BackgroundWorkerIsolate NLP & Geospatial Engine Tests', () {
    test('singleton instance initializes correctly', () async {
      final isolate = BackgroundWorkerIsolate.instance;
      await isolate.ensureInitialized();
      expect(isolate.isInitialized, isTrue);
    });

    test('dialect pipeline correctly normalizes Kannada plumber synonyms', () async {
      final isolate = BackgroundWorkerIsolate.instance;
      final result = await isolate.speculativeParseAndMatch(
        utterance: '5 km ಒಳಗೆ ನಳ ರಿಪೇರಿ ಪ್ಲಂಬರ್ ಬೇಕು',
        userLat: 12.9716, // Bengaluru center
        userLng: 77.5946,
      );

      expect(result.detectedSkill, equals('plumber'));
      expect(result.radiusKm, equals(5.0));
      expect(result.rankedCandidates, isNotEmpty);
      expect(result.rankedCandidates.first.skill, equals('ಪ್ಲಂಬರ್'));

      // Verify sorted by distance ascending
      for (int i = 0; i < result.rankedCandidates.length - 1; i++) {
        expect(
          result.rankedCandidates[i].distanceMeters,
          lessThanOrEqualTo(result.rankedCandidates[i + 1].distanceMeters),
        );
      }
    });

    test('dialect pipeline correctly normalizes painter synonyms', () async {
      final isolate = BackgroundWorkerIsolate.instance;
      final result = await isolate.speculativeParseAndMatch(
        utterance: 'ನನಗೆ ಮನೆಗೆ ಬಣ್ಣ ಹಚ್ಚುವ ಪೇಂಟರ್ ಬೇಕು 10 km',
        userLat: 12.9716,
        userLng: 77.5946,
      );

      expect(result.detectedSkill, equals('painter'));
      expect(result.radiusKm, equals(10.0));
      expect(result.rankedCandidates.first.skill, equals('ಪೇಂಟರ್'));
    });

    test('dialect pipeline correctly normalizes electrician synonyms', () async {
      final isolate = BackgroundWorkerIsolate.instance;
      final result = await isolate.speculativeParseAndMatch(
        utterance: 'ಕರಂಟ್ ಕೆಲಸಕ್ಕೆ electrician ಹುಡುಕು',
        userLat: 12.9716,
        userLng: 77.5946,
      );

      expect(result.detectedSkill, equals('electrician'));
      expect(result.rankedCandidates.first.skill, equals('ಎಲೆಕ್ಟ್ರಿಷಿಯನ್'));
    });
  });

  group('SiriOrbState Enum & Architecture Tests', () {
    test('all 4 core conversational states exist with expected indices', () {
      expect(SiriOrbState.idle.index, equals(0));
      expect(SiriOrbState.listening.index, equals(1));
      expect(SiriOrbState.thinking.index, equals(2));
      expect(SiriOrbState.speaking.index, equals(3));
    });
  });
}
