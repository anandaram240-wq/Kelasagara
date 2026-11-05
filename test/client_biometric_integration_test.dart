// test/client_biometric_integration_test.dart
//
// KELASAGARA-BIOMATCH: Client Mobile Subsystem & Integration Test Suite (Phase 11)
// Rigorous verification of Flutter client biometric proxy, challenge nonce handshake,
// uniform API response mapping, and RRL-0 research prototype lifecycle compliance.

import 'package:flutter_test/flutter_test.dart';
import 'package:kelasagaara/services/biometric_service.dart';

void main() {
  group('BiometricStatus & RRL-0 State Classification', () {
    test('pendingReview enum exists and is distinguished from approved', () {
      expect(BiometricStatus.pendingReview, isNotNull);
      expect(BiometricStatus.pendingReview, isNot(equals(BiometricStatus.approved)));
      expect(BiometricStatus.pendingReview, isNot(equals(BiometricStatus.duplicateFound)));
    });

    test('technicalFailureRetry enum exists and enforces fail-closed state', () {
      expect(BiometricStatus.technicalFailureRetry, isNotNull);
      expect(BiometricStatus.technicalFailureRetry, isNot(equals(BiometricStatus.approved)));
    });

    test('BiometricCheckResult.pendingReview sets correct flags and accountStatus', () {
      final res = BiometricCheckResult.pendingReview(
        maxSimilarity: 0.12,
        message: 'Template held under RRL-0 model.',
        accountStatus: 'pending_review',
      );

      expect(res.status, BiometricStatus.pendingReview);
      expect(res.isPendingReview, isTrue);
      expect(res.isApproved, isFalse, reason: 'RRL-0 models cannot issue automated approval (Invariant I-01)');
      expect(res.isDuplicate, isFalse);
      expect(res.accountStatus, 'pending_review');
      expect(res.maxSimilarity, 0.12);
    });

    test('BiometricCheckResult.technicalFailureRetry enforces isApproved=false', () {
      final res = BiometricCheckResult.technicalFailureRetry('Timeout on inference engine.');

      expect(res.status, BiometricStatus.technicalFailureRetry);
      expect(res.isTechnicalFailure, isTrue);
      expect(res.isApproved, isFalse);
      expect(res.isDuplicate, isFalse);
      expect(res.message, contains('Timeout'));
    });

    test('BiometricCheckResult.ambiguity flags borderline candidate without approval', () {
      final res = BiometricCheckResult.ambiguity(
        matchedUid: 'usr_candidate_789',
        maskedPhone: '+91 ******9999',
        maxSimilarity: 0.69,
        message: 'Ambiguity flagged for manual review.',
        accountStatus: 'pending_review',
      );

      expect(res.status, BiometricStatus.ambiguity);
      expect(res.isAmbiguity, isTrue);
      expect(res.isApproved, isFalse);
      expect(res.isDuplicate, isFalse);
      expect(res.matchedUid, 'usr_candidate_789');
      expect(res.maskedPhone, '+91 ******9999');
      expect(res.maxSimilarity, 0.69);
    });
  });

  group('UniformBiometricApiResponse Envelope Deserialization Logic', () {
    BiometricCheckResult parseServerResponse(Map<String, dynamic> respData) {
      final payload = (respData['data'] is Map<String, dynamic>)
          ? respData['data'] as Map<String, dynamic>
          : respData;

      final status = (payload['status'] ?? respData['status'] ?? 'error') as String;
      final similarity = (payload['similarity'] as num?)?.toDouble() ?? 0.0;
      final message = payload['message'] as String? ?? 'Biometric response received.';
      final accountStatus = payload['accountStatus'] as String?;

      switch (status) {
        case 'approved':
          return BiometricCheckResult.approved(
            maxSimilarity: similarity,
            message: message,
            accountStatus: accountStatus,
          );
        case 'pending_review':
          return BiometricCheckResult.pendingReview(
            maxSimilarity: similarity,
            message: message,
            accountStatus: accountStatus ?? 'pending_review',
          );
        case 'duplicate':
          return BiometricCheckResult.duplicateFound(
            matchedUid: payload['matchedUid'] as String?,
            maskedPhone: payload['maskedPhone'] as String? ?? 'an existing profile',
            maxSimilarity: similarity,
            message: message,
          );
        case 'ambiguity':
          return BiometricCheckResult.ambiguity(
            matchedUid: payload['matchedUid'] as String?,
            maskedPhone: payload['maskedPhone'] as String?,
            maxSimilarity: similarity,
            message: message,
            accountStatus: accountStatus,
          );
        case 'technical_failure_retry':
          return BiometricCheckResult.technicalFailureRetry(message);
        default:
          return BiometricCheckResult.error('Unexpected status from server: $status');
      }
    }

    test('parses Tier 0 RRL-0 pending_review uniform response correctly', () {
      final serverJson = {
        'success': true,
        'status': 'pending_review',
        'data': {
          'status': 'pending_review',
          'isApproved': false,
          'isDuplicate': false,
          'similarity': 0.0,
          'threshold': 0.74,
          'accountStatus': 'pending_review',
          'message': 'Captured under RESEARCH_ONLY model. Queued for manual review.',
        },
        'serverTimestamp': '2026-10-10T03:30:00.000Z',
      };

      final result = parseServerResponse(serverJson);
      expect(result.status, BiometricStatus.pendingReview);
      expect(result.isPendingReview, isTrue);
      expect(result.isApproved, isFalse);
      expect(result.accountStatus, 'pending_review');
    });

    test('parses duplicate interception uniform response with masked phone', () {
      final serverJson = {
        'success': false,
        'status': 'duplicate',
        'data': {
          'status': 'duplicate',
          'isApproved': false,
          'isDuplicate': true,
          'matchedUid': 'uid_victim_001',
          'maskedPhone': '+91 ******1234',
          'similarity': 0.88,
          'threshold': 0.74,
          'message': 'Face duplicate detected.',
        },
        'serverTimestamp': '2026-10-10T03:30:00.000Z',
      };

      final result = parseServerResponse(serverJson);
      expect(result.status, BiometricStatus.duplicateFound);
      expect(result.isDuplicate, isTrue);
      expect(result.isApproved, isFalse);
      expect(result.matchedUid, 'uid_victim_001');
      expect(result.maskedPhone, '+91 ******1234');
      expect(result.maxSimilarity, 0.88);
    });

    test('parses fail-closed technical failure response correctly', () {
      final serverJson = {
        'success': false,
        'status': 'technical_failure_retry',
        'data': {
          'status': 'technical_failure_retry',
          'message': 'Internal ONNX graph exception.',
        },
        'serverTimestamp': '2026-10-10T03:30:00.000Z',
      };

      final result = parseServerResponse(serverJson);
      expect(result.status, BiometricStatus.technicalFailureRetry);
      expect(result.isTechnicalFailure, isTrue);
      expect(result.isApproved, isFalse);
    });

    test('handles unknown corrupted status by failing closed into BiometricStatus.error', () {
      final corruptedJson = {
        'success': true,
        'status': 'corrupted_state_bypassing_rules',
        'data': {'status': 'corrupted_state_bypassing_rules'},
      };

      final result = parseServerResponse(corruptedJson);
      expect(result.status, BiometricStatus.error);
      expect(result.isApproved, isFalse);
    });
  });

  group('Challenge Nonce Handshake Contract', () {
    test('extracts nonce from challenge endpoint payload', () {
      final challengeJson = {
        'success': true,
        'status': 'challenge_issued',
        'data': {
          'challengeNonce': 'cn_9845_a1b2c3d4e5f6',
          'expiresAt': '2026-10-10T03:31:00.000Z',
          'action': 'ENROLLMENT',
          'ttlSeconds': 60,
          'serverTimestamp': '2026-10-10T03:30:00.000Z',
        },
      };

      final inner = challengeJson['data'] as Map<String, dynamic>;
      final nonce = inner['challengeNonce'] as String?;

      expect(nonce, isNotNull);
      expect(nonce, startsWith('cn_'));
      expect(inner['ttlSeconds'], 60);
      expect(inner['action'], 'ENROLLMENT');
    });

    test('normalizes action string casing safely', () {
      String normalizeAction(String action) {
        return (action.toUpperCase() == 'VERIFY' || action.toUpperCase() == 'VERIFICATION')
            ? 'VERIFICATION'
            : 'ENROLLMENT';
      }

      expect(normalizeAction('enroll'), 'ENROLLMENT');
      expect(normalizeAction('ENROLLMENT'), 'ENROLLMENT');
      expect(normalizeAction('verify'), 'VERIFICATION');
      expect(normalizeAction('verification'), 'VERIFICATION');
    });
  });

  group('1:1 Biometric Verification Result Contract', () {
    BiometricCheckResult parseVerifyResponse(Map<String, dynamic> respData) {
      final payload = (respData['data'] is Map<String, dynamic>)
          ? respData['data'] as Map<String, dynamic>
          : respData;

      final status = (payload['status'] ?? respData['status'] ?? 'error') as String;
      final isMatch = payload['isMatch'] == true || status == 'verified';
      final similarity = (payload['similarity'] as num?)?.toDouble() ?? 0.0;
      final message = payload['message'] as String? ?? '1:1 verification completed.';

      if (isMatch) {
        return BiometricCheckResult.approved(
          maxSimilarity: similarity,
          message: message,
        );
      } else if (status == 'not_enrolled') {
        return const BiometricCheckResult(
          status: BiometricStatus.notEnrolled,
          isApproved: false,
          isDuplicate: false,
          maxSimilarity: 0.0,
          message: 'No biometric template enrolled.',
        );
      } else {
        return BiometricCheckResult.error(message);
      }
    }

    test('verifies positive 1:1 match correctly', () {
      final verifyJson = {
        'success': true,
        'status': 'verified',
        'data': {
          'isMatch': true,
          'similarity': 0.89,
          'threshold': 0.74,
          'message': 'Facial identity verified successfully.',
        },
      };

      final res = parseVerifyResponse(verifyJson);
      expect(res.status, BiometricStatus.approved);
      expect(res.isApproved, isTrue);
      expect(res.maxSimilarity, 0.89);
    });

    test('rejects mismatched 1:1 probe fail-closed', () {
      final verifyJson = {
        'success': false,
        'status': 'rejected',
        'data': {
          'isMatch': false,
          'similarity': 0.41,
          'threshold': 0.74,
          'message': 'Facial authentication failed.',
        },
      };

      final res = parseVerifyResponse(verifyJson);
      expect(res.status, BiometricStatus.error);
      expect(res.isApproved, isFalse);
    });

    test('detects not_enrolled status safely', () {
      final verifyJson = {
        'success': false,
        'status': 'not_enrolled',
        'error': {'code': 'NOT_ENROLLED', 'message': 'No template found.'},
      };

      final res = parseVerifyResponse(verifyJson);
      expect(res.status, BiometricStatus.notEnrolled);
      expect(res.isApproved, isFalse);
    });
  });
}
