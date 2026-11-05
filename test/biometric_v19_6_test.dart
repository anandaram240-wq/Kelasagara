// test/biometric_v19_6_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelasagaara/services/capture_illumination_service.dart';
import 'package:kelasagaara/services/biometric_service.dart';
import 'package:kelasagaara/widgets/duplicate_detected_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('V19.6 Phase 3: CaptureIlluminationService Adaptive Lighting Tests', () {
    test('initializes with isIlluminating=false and handles lifecycle safely', () async {
      final service = CaptureIlluminationService.instance;
      expect(service.isIlluminating, isFalse);

      // Safe reset on initial state
      await service.reset();
      expect(service.isIlluminating, isFalse);

      // Idempotent disable
      await service.disableScreenFill();
      expect(service.isIlluminating, isFalse);
    });

    test('handles enableScreenFill and disableScreenFill idempotently without uncaught errors', () async {
      final service = CaptureIlluminationService.instance;

      // In unit test environment, method channels may fail soft or succeed
      final result = await service.enableScreenFill();
      expect(result, isA<bool>());

      // Subsequent disable restores state
      await service.disableScreenFill();
      expect(service.isIlluminating, isFalse);

      // Repeated disable is safe
      await service.disableScreenFill();
      expect(service.isIlluminating, isFalse);
    });
  });

  group('V19.6 Phase 4: BiometricChallengeTicket Active Challenge Parsing Tests', () {
    test('parses server-issued active challenge with randomized action and localized prompts', () {
      final json = {
        'success': true,
        'status': 'challenge_issued',
        'data': {
          'challengeId': 'chal_a1b2c3d4e5f6',
          'challengeNonce': 'chal_a1b2c3d4e5f6:nonce_secret_789',
          'expiresAt': 1761234567890,
          'action': 'ENROLLMENT',
          'requiredAction': 'TURN_HEAD_LEFT',
          'actionPromptEn': 'Slowly turn your head slightly to the left',
          'actionPromptKn': 'ನಿಮ್ಮ ತಲೆಯನ್ನು ನಿಧಾನವಾಗಿ ಎಡಕ್ಕೆ ತಿರುಗಿಸಿ',
          'ttlSeconds': 60,
        },
      };

      final ticket = BiometricChallengeTicket.fromJson(json);
      expect(ticket.challengeId, 'chal_a1b2c3d4e5f6');
      expect(ticket.nonce, 'chal_a1b2c3d4e5f6:nonce_secret_789');
      expect(ticket.purpose, 'ENROLLMENT');
      expect(ticket.requiredAction, 'TURN_HEAD_LEFT');
      expect(ticket.actionPromptEn, 'Slowly turn your head slightly to the left');
      expect(ticket.actionPromptKn, 'ನಿಮ್ಮ ತಲೆಯನ್ನು ನಿಧಾನವಾಗಿ ಎಡಕ್ಕೆ ತಿರುಗಿಸಿ');
    });

    test('falls back gracefully when active challenge action is omitted (backward compatibility)', () {
      final json = {
        'challengeNonce': 'chal_legacy:nonce_legacy',
        'expiresAtMs': 1761234567890,
        'purpose': 'verify_1to1',
      };

      final ticket = BiometricChallengeTicket.fromJson(json);
      expect(ticket.nonce, 'chal_legacy:nonce_legacy');
      expect(ticket.purpose, 'verify_1to1');
      expect(ticket.requiredAction, isNull);
      expect(ticket.actionPromptEn, isNull);
      expect(ticket.actionPromptKn, isNull);
    });
  });

  group('V19.6 Phase 5: DuplicateDetectedSheet Privacy Contract Tests', () {
    test('DuplicateDetectionResult strictly sanitizes PII before ownership verification', () {
      final rawBackendResponse = {
        'status': 'duplicate',
        'isApproved': false,
        'isDuplicate': true,
        'isOwnershipVerified': false, // PRE-VERIFICATION
        'recoverySessionId': 'rec_987654321',
        'maskedUserId': 'KLS-attacker-probed-id', // Attacker attempted to probe
        'maskedPhone': '+91 ******9999',
        'maskedName': 'S****** K****',
        'similarityPercent': 94,
        'message':
            'A matching facial profile is already registered. If this is your account, please sign in or verify ownership.',
        'messageKn':
            'ಈ ಮುಖದ ಪ್ರೊಫೈಲ್ ಈಗಾಗಲೇ ನೋಂದಾಯಿಸಲ್ಪಟ್ಟಿದೆ. ಇದು ನಿಮ್ಮ ಖಾತೆಯಾಗಿದ್ದರೆ, ದಯವಿಟ್ಟು ಸೈನ್ ಇನ್ ಮಾಡಿ ಅಥವಾ ಮಾಲೀಕತ್ವವನ್ನು ಪರಿಶೀಲಿಸಿ.',
      };

      final result = DuplicateDetectionResult.fromJson(rawBackendResponse);

      // Phase 5 Invariant: ZERO PII populated before ownership verification
      expect(result.isOwnershipVerified, isFalse);
      expect(result.maskedUserId, isNull, reason: 'Must not expose maskedUserId before verification');
      expect(result.maskedPhone, isNull, reason: 'Must not expose maskedPhone before verification');
      expect(result.maskedName, isNull, reason: 'Must not expose maskedName before verification');
      expect(result.similarityPercent, 0, reason: 'Must not expose similarity score before verification');
      expect(result.recoverySessionId, 'rec_987654321');
    });

    test('DuplicateDetectionResult exposes masked identifiers ONLY after verified ownership', () {
      final verifiedResponse = {
        'status': 'duplicate',
        'isApproved': false,
        'isDuplicate': true,
        'isOwnershipVerified': true, // POST-VERIFICATION (Authorized)
        'recoverySessionId': 'rec_verified_123',
        'maskedUserId': 'KLS-***-7890',
        'maskedPhone': '+91 ******7890',
        'maskedName': 'Ra*** K***',
        'similarityPercent': 92,
        'message': 'Account verified.',
      };

      final result = DuplicateDetectionResult.fromJson(verifiedResponse);
      expect(result.isOwnershipVerified, isTrue);
      expect(result.maskedUserId, 'KLS-***-7890');
      expect(result.maskedPhone, '+91 ******7890');
      expect(result.maskedName, 'Ra*** K***');
      expect(result.similarityPercent, 92);
    });

    testWidgets('DuplicateDetectedSheet widget renders generic privacy UI before ownership proof',
        (WidgetTester tester) async {
      final unverifiedResult = DuplicateDetectionResult.fromJson({
        'isOwnershipVerified': false,
        'recoverySessionId': 'rec_nonce_456',
        'maskedUserId': 'SHOULD_NOT_APPEAR',
        'maskedPhone': '9999999999',
        'similarityPercent': 95,
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DuplicateDetectedSheet(result: unverifiedResult),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check header and generic notice
      expect(find.text('ಖಾತೆ ಈಗಾಗಲೇ ನೋಂದಾಯಿಸಲ್ಪಟ್ಟಿದೆ'), findsOneWidget);
      expect(find.text('Existing Account Detected'), findsOneWidget);
      expect(find.textContaining('Privacy Notice'), findsOneWidget);

      // Check PII is completely absent from widget tree
      expect(find.text('SHOULD_NOT_APPEAR'), findsNothing);
      expect(find.text('9999999999'), findsNothing);
      expect(find.textContaining('95%'), findsNothing);

      // Check recovery action buttons
      expect(find.textContaining('Sign In to Existing Account'), findsOneWidget);
      expect(find.textContaining('Verify Ownership via OTP'), findsOneWidget);
    });
  });
}
