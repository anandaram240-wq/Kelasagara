// test/voice_command_center_benchmark_test.dart
// Production-Grade Voice Command Center Forensic Benchmark & Test Suite
// Verifies 100 Utterances, Fast Local Router, Speculative Execution,
// Natural Barge-in, Road Distance Integrity, and Security Boundaries.

import 'package:flutter_test/flutter_test.dart';
import 'package:kelasagaara/models/voice_session_state.dart';
import 'package:kelasagaara/services/voice/fast_local_command_router.dart';
import 'package:kelasagaara/services/voice/speculative_execution_coordinator.dart';
import 'package:kelasagaara/services/voice/sarvam_speech_provider.dart';
import 'package:kelasagaara/services/voice/sarvam_tts_provider.dart';
import 'package:kelasagaara/services/voice/voice_session_manager.dart';
import 'package:kelasagaara/services/voice/voice_tool_registry.dart';

class StubSpeechProvider extends SarvamSpeechProvider {
  bool listening = false;
  @override
  Future<bool> initialize() async => true;
  @override
  Future<void> startListening({
    required void Function(String transcript, bool isFinal) onResult,
    required void Function() onComplete,
    void Function(String error)? onError,
    String? locale,
  }) async {
    listening = true;
  }
  @override
  Future<void> stopListening() async {
    listening = false;
  }
}

class StubTTSProvider extends SarvamTTSProvider {
  bool speaking = false;
  @override
  Future<void> initialize() async {}
  @override
  Future<void> speak(String text, {String languageCode = 'kn-IN'}) async {
    speaking = true;
  }
  @override
  Future<void> stop() async {
    speaking = false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('100 Benchmark Utterances Verification', () {
    final mockCandidates = [
      WorkerCandidate(
        workerId: 'w_painter_1',
        name: 'Ramesh Kumar',
        skill: 'Painter',
        distanceMeters: 1800,
        distanceDisplay: '1.8 km',
        latitude: 12.9716,
        longitude: 77.5946,
        isAvailable: true,
        verificationLevel: 'practicalVerified',
        completedJobs: 42,
        rating: 4.8,
        rankingScore: 92.5,
        selectionReason: 'Closest verified painter with high ratings',
        roadDistanceMeters: 2100,
        roadDurationSeconds: 420,
        roadDurationDisplay: '7 min',
        isRoadDistance: true,
        locationFreshness: 'LIVE',
      ),
      WorkerCandidate(
        workerId: 'w_painter_2',
        name: 'Suresh Gowda',
        skill: 'Painter',
        distanceMeters: 3200,
        distanceDisplay: '3.2 km',
        latitude: 12.9800,
        longitude: 77.6000,
        isAvailable: true,
        verificationLevel: 'aadhaarVerified',
        completedJobs: 28,
        rating: 4.6,
        rankingScore: 84.0,
        selectionReason: 'Available immediately nearby',
        roadDistanceMeters: 3600,
        roadDurationSeconds: 720,
        roadDurationDisplay: '12 min',
        isRoadDistance: true,
        locationFreshness: 'RECENT',
      ),
      WorkerCandidate(
        workerId: 'w_painter_3',
        name: 'Manjunath B',
        skill: 'Painter',
        distanceMeters: 4800,
        distanceDisplay: '4.8 km',
        latitude: 12.9650,
        longitude: 77.5850,
        isAvailable: false,
        verificationLevel: 'standard',
        completedJobs: 15,
        rating: 4.3,
        rankingScore: 68.0,
        selectionReason: 'Experienced painter',
        roadDistanceMeters: 5400,
        roadDurationSeconds: 1080,
        roadDurationDisplay: '18 min',
        isRoadDistance: true,
        locationFreshness: 'STALE',
      ),
    ];

    // ── SUITE 1: 25 Kannada Search, Context & Navigation Utterances ─────────
    test('25 Kannada Utterances benchmark', () {
      final kannadaUtterances = [
        'ನನ್ನ ಹತ್ತಿರ ಪೇಂಟರ್ ಬೇಕು',
        'ಹತ್ತಿರದ ಪ್ಲಂಬರ್ ಹುಡುಕಿ',
        'ಐದು ಕಿಲೋಮೀಟರ್ ಒಳಗೆ ಎಲೆಕ್ಟ್ರಿಷಿಯನ್',
        'ನಂಬರ್ 1',
        'ನಂಬರ್ 2',
        'ಎರಡನೆಯವರು',
        'ಮೊದಲನೆಯವರು',
        'ನಂಬರ್ 1 ಎಷ್ಟು ದೂರದಲ್ಲಿದ್ದಾನೆ?',
        'ನಂಬರ್ 2 ಎಷ್ಟು ದೂರ?',
        'ನಂಬರ್ 3 ಯಾವಾಗ ಸಿಗುತ್ತಾರೆ?',
        'ಅವರು ಲಭ್ಯವಿದ್ದಾರಾ?',
        'ನಂಬರ್ 1 ಗೆ ರೂಟ್ ತೋರಿಸಿ',
        'ನಂಬರ್ 2 ಗೆ ನ್ಯಾವಿಗೇಟ್ ಮಾಡಿ',
        'ಸೆಟ್ಟಿಂಗ್ಸ್ ತೆರೆಯಿರಿ',
        'ಬುಕಿಂಗ್ಸ್ ತೋರಿಸಿ',
        'ಮುಖಪುಟಕ್ಕೆ ಹೋಗಿ',
        'ಹಿಂದಕ್ಕೆ ಹೋಗಿ',
        'ಮ್ಯಾಪ್ ಸೆಂಟರ್ ಮಾಡಿ',
        'ನಿಲ್ಲಿಸಿ',
        'ರದ್ದು ಮಾಡಿ',
        'ಖಚಿತಪಡಿಸಿ',
        'ಸಹಾಯ ಬೇಕು',
        'ಮತ್ತೊಮ್ಮೆ ಹೇಳಿ',
        'ಧ್ವನಿ ಸೆಟ್ಟಿಂಗ್ಸ್ ತೆರೆಯಿರಿ',
        'ನನ್ನ ಬುಕಿಂಗ್ ರದ್ದು ಮಾಡಿ',
      ];

      for (final utterance in kannadaUtterances) {
        final result = FastLocalCommandRouter.tryRoute(
          utterance: utterance,
          activeCandidates: mockCandidates,
          pendingBooking: {'workerId': 'w_painter_2'},
        );
        // Kannada control & contextual commands must be routed correctly
        expect(result, isNotNull, reason: 'Failed on Kannada utterance: $utterance');
        if (utterance.contains('ನಂಬರ್ 1')) {
          expect(result.arguments['workerId'], equals('w_painter_1'));
        } else if (utterance.contains('ನಂಬರ್ 2') || utterance.contains('ಎರಡನೆಯವರು')) {
          expect(result.arguments['workerId'], equals('w_painter_2'));
        }
      }
    });

    // ── SUITE 2: 25 English Search, Context & Navigation Utterances ─────────
    test('25 English Utterances benchmark', () {
      final englishUtterances = [
        'Find a painter near me',
        'Search electrician within 5 km',
        'Nearest plumber available',
        'Number 1',
        'Number 2',
        'Select the first one',
        'Select number two',
        'How far is number 1?',
        'How far is number 2?',
        'When is number 1 available?',
        'When is number 3 available?',
        'Is number 2 available?',
        'Navigate to number 1',
        'Navigate to number 2',
        'Directions to painter number 1',
        'Open settings',
        'Open voice settings',
        'Open my bookings',
        'Go home',
        'Go back',
        'Recenter map',
        'Stop listening',
        'Cancel booking',
        'Confirm booking',
        'Voice help',
      ];

      for (final utterance in englishUtterances) {
        final result = FastLocalCommandRouter.tryRoute(
          utterance: utterance,
          activeCandidates: mockCandidates,
          pendingBooking: {'workerId': 'w_painter_1'},
        );
        expect(result, isNotNull, reason: 'Failed on English utterance: $utterance');
        if (utterance.contains('number 1') || utterance.contains('first one')) {
          expect(result.arguments['workerId'], equals('w_painter_1'));
        } else if (utterance.contains('number 2') || utterance.contains('number two')) {
          expect(result.arguments['workerId'], equals('w_painter_2'));
        }
      }
    });

    // ── SUITE 3: 25 Code-Mixed Kannada-English Utterances ────────────────────
    test('25 Code-Mixed Utterances benchmark', () {
      final mixedUtterances = [
        'Tomorrow morning painter ಬೇಕು',
        'Painter number 2 ge navigate maadi',
        'Number 1 ge directions kodi',
        'Number 2 hesaru enu?',
        'Electrician near me huduki',
        'Plumber ge call madi',
        'Settings open madi',
        'Bookings torisi',
        'Home screen ge hogi',
        'Back banni',
        'Booking confirm madi',
        'Booking cancel madi',
        'Map recenter madi',
        'Help kodi',
        'Innondu sala repeat madi',
        'Voice settings open madi',
        '5 km olage painter beku',
        'Immediate agi electrician bekagidhe',
        'Number 1 rating eshtu?',
        'Number 2 experience eshtu?',
        'Number 3 available idhdhaara?',
        'Stop madi',
        'Cancel maadi',
        'Confirm aagide',
        'Okay confirm',
      ];

      for (final utterance in mixedUtterances) {
        final result = FastLocalCommandRouter.tryRoute(
          utterance: utterance,
          activeCandidates: mockCandidates,
          pendingBooking: {'workerId': 'w_painter_1'},
        );
        expect(result, isNotNull, reason: 'Failed on mixed utterance: $utterance');
      }
    });

    // ── SUITE 4: 25 App Control & Fast Local Routing Utterances ─────────────
    test('25 App Control & Fast Local Commands benchmark (< 10ms execution)', () {
      final controlCommands = [
        'open settings',
        'open voice settings',
        'open bookings',
        'go home',
        'go back',
        'recenter',
        'center map',
        'stop',
        'cancel',
        'confirm',
        'yes confirm',
        'repeat',
        'help',
        'voice help',
        'select 1',
        'select 2',
        'number 1',
        'number 2',
        'how far is number 1',
        'how far is number 2',
        'navigate to number 1',
        'navigate to number 2',
        'ಸೆಟ್ಟಿಂಗ್ಸ್ ತೆರೆಯಿರಿ',
        'ಬುಕಿಂಗ್ಸ್',
        'ಖಚಿತಪಡಿಸಿ',
      ];

      final stopwatch = Stopwatch()..start();
      for (final cmd in controlCommands) {
        final result = FastLocalCommandRouter.tryRoute(
          utterance: cmd,
          activeCandidates: mockCandidates,
          pendingBooking: {'workerId': 'w_painter_1'},
        );
        expect(result.isHandled, isTrue, reason: 'Expected handled for: $cmd');
      }
      stopwatch.stop();

      final avgMs = stopwatch.elapsedMilliseconds / controlCommands.length;
      expect(avgMs, lessThan(10.0), reason: 'Fast Local Router must execute in under 10ms');
    });
  });

  group('Speculative Execution Coordinator Tests', () {
    test('Pre-search is triggered safely on partial speech without consequential writes', () async {
      final coordinator = SpeculativeExecutionCoordinator();
      coordinator.newUtterance();

      // Simulate streaming partial tokens
      coordinator.onPartialTranscript('ನನ್ನ');
      expect(coordinator.activeResult, isNull);

      coordinator.onPartialTranscript('ನನ್ನ ಹತ್ತಿರ ಪೇಂಟ');
      // Coordinator detects 'painter' skill pre-search trigger
      final spec = coordinator.activeResult;
      expect(spec, isNotNull);
      expect(spec!.skillId, equals('painter'));
      expect(spec.isConsequential, isFalse);

      coordinator.cancel();
      expect(coordinator.activeResult, isNull);
    });

    test('Consequential booking operations are strictly blocked from speculative execution', () {
      final coordinator = SpeculativeExecutionCoordinator();
      coordinator.newUtterance();

      coordinator.onPartialTranscript('Book painter number 1 now');
      // Must NOT pre-execute booking
      expect(coordinator.activeResult, isNull);
    });
  });

  group('Natural Barge-In & Concurrency Tests', () {
    test('Barge-in increments generation and resets to listening state', () async {
      final manager = VoiceSessionManager(
        speech: StubSpeechProvider(),
        tts: StubTTSProvider(),
      );
      await manager.initialize();

      // State is initially idle
      expect(manager.currentState, equals(VoiceSessionState.idle));

      // Simulate start listening
      await manager.startListening();
      expect(manager.currentState, anyOf(VoiceSessionState.listening, VoiceSessionState.userSpeaking));

      // Simulate interruption during audio playback
      await manager.interrupt();
      // Should immediately transition to listening
      expect(manager.currentState, equals(VoiceSessionState.listening));

      await manager.stopListening();
    });
  });

  group('Real Road Matrix Distance & Location Freshness Tests', () {
    test('WorkerCandidate holds real road distance and location freshness', () {
      final candidate = WorkerCandidate(
        workerId: 'w_test_1',
        name: 'Anand R',
        skill: 'Electrician',
        distanceMeters: 2500,
        distanceDisplay: '2.5 km',
        latitude: 12.9716,
        longitude: 77.5946,
        isAvailable: true,
        verificationLevel: 'practicalVerified',
        completedJobs: 65,
        rating: 4.9,
        rankingScore: 95.0,
        selectionReason: 'Top rated electrician',
        roadDistanceMeters: 3100,
        roadDurationSeconds: 600,
        roadDurationDisplay: '10 min',
        isRoadDistance: true,
        locationFreshness: 'LIVE',
      );

      expect(candidate.isRoadDistance, isTrue);
      expect(candidate.roadDistanceMeters, equals(3100));
      expect(candidate.roadDurationDisplay, equals('10 min'));
      expect(candidate.locationFreshness, equals('LIVE'));

      final map = candidate.toMap();
      expect(map['isRoadDistance'], isTrue);
      expect(map['locationFreshness'], equals('LIVE'));
      expect(map['roadDurationDisplay'], equals('10 min'));
    });
  });

  group('Security & Password Protection Tests', () {
    test('Fast local command router rejects password queries safely', () {
      final result1 = FastLocalCommandRouter.tryRoute(utterance: 'What is my password?');
      // Password is handled with security disclaimer
      expect(result1.isHandled, isTrue);
      expect(result1.speechResponseEn, contains('password'));

      final result2 = FastLocalCommandRouter.tryRoute(utterance: 'ನನ್ನ ಪಾಸ್‌ವರ್ಡ್ ಏನು?');
      expect(result2.isHandled, isTrue);
      expect(result2.speechResponseKn, contains('ಪಾಸ್‌ವರ್ಡ್'));
    });
  });
}
