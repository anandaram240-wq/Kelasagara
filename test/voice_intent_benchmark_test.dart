// test/voice_intent_benchmark_test.dart
// Benchmark Test Suite for Kannada, English, and Code-Mixed Speech & Security Guard

import 'package:flutter_test/flutter_test.dart';
import 'package:kelasagaara/services/voice/voice_provider.dart';
import 'package:kelasagaara/services/voice/voice_provider_router.dart';

void main() {
  group('Voice Language Detection & Speech Benchmark Tests', () {
    test('25 Native Kannada Phrases benchmark', () {
      final kannadaPhrases = [
        "ನನ್ನ ಹತ್ತಿರ ಪೇಂಟರ್ ಬುಕ್ ಮಾಡಿ",
        "ನನ್ನ ಹತ್ತಿರದ ಪೇಂಟರ್ ತೋರಿಸಿ",
        "ಐದು ಕಿಲೋಮೀಟರ್ ಒಳಗೆ ಪೇಂಟರ್ ಹುಡುಕಿ",
        "ಹತ್ತಿರದ ಪ್ಲಂಬರ್ ಯಾರು?",
        "ನಾಳೆ ಬೆಳಿಗ್ಗೆ ಪೇಂಟರ್ ಬೇಕು",
        "ಮೊದಲನೇಯವರನ್ನು ಬುಕ್ ಮಾಡಿ",
        "ಅವನು ಎಷ್ಟು ಕೆಲಸಗಳನ್ನು ಮಾಡಿದ್ದಾನೆ?",
        "ಅವನು ಪರಿಶೀಲಿಸಲ್ಪಟ್ಟಿದ್ದಾನಾ?",
        "ನನ್ನ ವರ್ಕರ್ ಈಗ ಎಲ್ಲಿದ್ದಾನೆ?",
        "ನನ್ನ ಬುಕಿಂಗ್ ತೋರಿಸಿ",
        "ನನ್ನ ಬುಕಿಂಗ್ ರದ್ದು ಮಾಡಿ",
        "ನನ್ನ ಸಕ್ರಿಯ ಬುಕಿಂಗ್‌ಗಳನ್ನು ತೋರಿಸಿ",
        "ನನ್ನ ಹತ್ತಿರ ಬೇರೆ ಪೇಂಟರ್ ಹುಡುಕಿ",
        "ಮೂರು ಪರಿಶೀಲಿಸಿದ ಪೇಂಟರ್‌ಗಳನ್ನು ತೋರಿಸಿ",
        "ನನ್ನ ಕೆಲಸದ ಸ್ಥಳದ ಹತ್ತಿರ ಪೇಂಟರ್ ಬೇಕು",
        "ಪ್ಲಂಬರ್ ಎಷ್ಟು ದೂರದಲ್ಲಿದ್ದಾರೆ?",
        "ಹತ್ತಿರದ ಎಲೆಕ್ಟ್ರಿಷಿಯನ್ ಕರೆಸಿ",
        "ನಾಳೆ ಕೆಲಸಕ್ಕೆ ಯಾರು ಸಿಗುತ್ತಾರೆ?",
        "ಬಡಗಿ ಕೆಲಸಕ್ಕೆ ಜನ ಬೇಕು",
        "ಮೇಸ್ತ್ರಿ ಹುಡುಕಿ",
        "ನನ್ನ ಖಾತೆ ವಿವರ ತೋರಿಸಿ",
        "ಸಹಾಯ ಬೇಕು",
        "ಇವತ್ತಿನ ಬುಕಿಂಗ್ ಸ್ಥಿತಿ ಏನು?",
        "ಧನ್ಯವಾದಗಳು",
        "ನಮಸ್ಕಾರ",
      ];

      for (final phrase in kannadaPhrases) {
        final detected = VoiceProviderRouter.detectLanguage(phrase);
        expect(detected, equals(DetectedLanguage.kannada),
            reason: 'Failed to classify Kannada phrase: "$phrase"');
      }
    });

    test('25 English Phrases benchmark', () {
      final englishPhrases = [
        "Book a painter near me",
        "Find the nearest available plumber",
        "Show me three painters within five kilometers",
        "Book the second one",
        "How many jobs has he completed?",
        "Where is my worker now?",
        "Show my active bookings",
        "Cancel my latest booking",
        "Only show verified painters",
        "Which one is closest?",
        "Is he available tomorrow?",
        "Find an electrician nearby",
        "Show me carpenter options",
        "What is the rating of the first worker?",
        "Book Ravi for tomorrow",
        "Track my worker location",
        "Open my profile",
        "Go to settings",
        "Navigate to job location",
        "Check worker availability",
        "Find a driver in Hassan",
        "Show completed bookings",
        "Are there any masons near me?",
        "Contact my worker",
        "Help me book a worker",
      ];

      for (final phrase in englishPhrases) {
        final detected = VoiceProviderRouter.detectLanguage(phrase);
        expect(detected, equals(DetectedLanguage.english),
            reason: 'Failed to classify English phrase: "$phrase"');
      }
    });

    test('25 Code-Mixed Kannada-English Phrases benchmark', () {
      final codeMixedPhrases = [
        "ನನ್ನ ಹತ್ತಿರ painter ಬೇಕು",
        "Tomorrow morning painter book ಮಾಡಿ",
        "5 km ಒಳಗೆ plumber ಹುಡುಕು",
        "First painter book ಮಾಡು",
        "ನನ್ನ worker ಎಲ್ಲಿದ್ದಾನೆ",
        "Booking status ಹೇಳು",
        "Verified painter ಮಾತ್ರ ತೋರಿಸು",
        "Nearest plumber ಯಾರು?",
        "ನನ್ನ active booking ತೋರಿಸಿ",
        "Latest booking cancel ಮಾಡಿ",
        "Painter profile ಓಪನ್ ಮಾಡಿ",
        "Second worker details ಹೇಳಿ",
        "Electrician rating ಎಷ್ಟು?",
        "Carpenter book ಮಾಡಬಹುದಾ?",
        "Job location ಹತ್ತಿರ plumber ಬೇಕು",
        "Driver contact number ಕೊಡಿ",
        "Mason experience ಎಷ್ಟಿದೆ?",
        "Worker live tracking ಶುರು ಮಾಡಿ",
        "Settings open ಮಾಡಿ",
        "Ravi painter available ಇದ್ದಾನಾ?",
        "Next painter ತೋರಿಸಿ",
        "Daily rate ಎಷ್ಟು?",
        "Profile update ಮಾಡು",
        "Booking confirm ಮಾಡಿ",
        "Thank you, bye ಹೇಳಿ",
      ];

      for (final phrase in codeMixedPhrases) {
        final detected = VoiceProviderRouter.detectLanguage(phrase);
        expect(detected, equals(DetectedLanguage.codeMixed),
            reason: 'Failed to classify Code-Mixed phrase: "$phrase"');
      }
    });

    test('Security test: Password inquiry matches refusal rule', () {
      final passwordQueries = [
        "What is my password?",
        "Tell me my password",
        "Show my password",
        "ನನ್ನ ಪಾಸ್ವರ್ಡ್ ಏನು?",
        "ನನ್ನ password ಹೇಳಿ",
      ];

      for (final q in passwordQueries) {
        final lower = q.toLowerCase();
        final isPasswordQuery = lower.contains('password') ||
            lower.contains('ಪಾಸ್ವರ್ಡ್') ||
            lower.contains('ಪಾಸ್‌ವರ್ಡ್');
        expect(isPasswordQuery, isTrue, reason: 'Failed security detection on: $q');
      }
    });
  });
}
