// test/biometric_contract_test.dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kelasagaara/services/biometric_service.dart';

void main() {
  group('Biometric Client Contract & Gate G-02 Burst Protocol', () {
    test('BurstFramePayloadItem serializes exactly into backend contract schema', () {
      const item = BurstFramePayloadItem(
        sequenceIndex: 1,
        capturedOffsetMs: 120,
        jpegBase64: 'dGVzdF9mcmFtZV8x',
      );

      final json = item.toJson();
      expect(json['sequenceIndex'], 1);
      expect(json['capturedOffsetMs'], 120);
      expect(json['jpegBase64'], 'dGVzdF9mcmFtZV8x');
      // Must not contain any client-computed vector fields
      expect(json.containsKey('embedding'), isFalse);
      expect(json.containsKey('probeVector'), isFalse);
      expect(json.containsKey('landmarks'), isFalse);
    });

    test('BiometricChallengeTicket parses backend challenge ticket correctly', () {
      final backendResponse = {
        'success': true,
        'status': 'challenge_issued',
        'data': {
          'challengeId': 'chal_a1b2c3d4e5f6',
          'challengeNonce': 'nonce_xyz789',
          'expiresAtMs': 1770000000000,
          'expectedFrameCount': 3,
          'purpose': 'verify_1to1',
        },
      };

      final ticket = BiometricChallengeTicket.fromJson(backendResponse);
      expect(ticket.challengeId, 'chal_a1b2c3d4e5f6');
      expect(ticket.nonce, 'nonce_xyz789');
      expect(ticket.expiresAtMs, 1770000000000);
      expect(ticket.expectedFrameCount, 3);
      expect(ticket.purpose, 'verify_1to1');
    });

    test('requestChallenge acquires ticket using MockClient without exception', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path.endsWith('/challenge'), isTrue);
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['purpose'], 'verify_1to1');

        return http.Response(
          jsonEncode({
            'success': true,
            'status': 'challenge_issued',
            'data': {
              'challengeId': 'mock_chal_100',
              'challengeNonce': 'mock_nonce_100',
              'expiresAtMs': 1770000000000,
              'expectedFrameCount': 3,
              'purpose': 'verify_1to1',
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final ticket = await BiometricService.instance.requestChallenge(
        purpose: 'verify_1to1',
        client: mockClient,
      );

      expect(ticket, isNotNull);
      expect(ticket!.challengeId, 'mock_chal_100');
      expect(ticket.nonce, 'mock_nonce_100');
    });

    test('submitChallengeBurst sends 3 frames and correctly parses verified outcome', () async {
      final frames = [
        const BurstFramePayloadItem(sequenceIndex: 0, capturedOffsetMs: 0, jpegBase64: 'frame0'),
        const BurstFramePayloadItem(sequenceIndex: 1, capturedOffsetMs: 120, jpegBase64: 'frame1'),
        const BurstFramePayloadItem(sequenceIndex: 2, capturedOffsetMs: 250, jpegBase64: 'frame2'),
      ];

      final mockClient = MockClient((request) async {
        expect(request.url.path.endsWith('/verify-1to1'), isTrue);
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['challengeId'], 'chal_mock_1');
        expect(body['nonce'], 'nonce_mock_1');
        expect(body['frames'], hasLength(3));
        // Verify Invariant T-01: No client vectors
        expect(body.containsKey('probeVector'), isFalse);
        expect(body.containsKey('embedding'), isFalse);

        return http.Response(
          jsonEncode({
            'success': true,
            'status': 'verified',
            'data': {
              'isMatch': true,
              'similarity': 0.72,
              'threshold': 0.363,
              'telemetry': {'earTrajectory': [0.28, 0.08, 0.28]},
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final result = await BiometricService.instance.submitChallengeBurst(
        endpoint: '/verify-1to1',
        challengeId: 'chal_mock_1',
        nonce: 'nonce_mock_1',
        frames: frames,
        client: mockClient,
      );

      expect(result.outcome, BiometricServerOutcome.approved);
      expect(result.isSuccess, isTrue);
      expect(result.similarity, 0.72);
      expect(result.threshold, 0.363);
    });

    test('submitChallengeBurst parses mismatch when SFace similarity < threshold', () async {
      final frames = [
        const BurstFramePayloadItem(sequenceIndex: 0, capturedOffsetMs: 0, jpegBase64: 'frame0'),
        const BurstFramePayloadItem(sequenceIndex: 1, capturedOffsetMs: 120, jpegBase64: 'frame1'),
        const BurstFramePayloadItem(sequenceIndex: 2, capturedOffsetMs: 250, jpegBase64: 'frame2'),
      ];

      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': false,
            'status': 'mismatch',
            'data': {
              'isMatch': false,
              'similarity': 0.21,
              'threshold': 0.363,
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final result = await BiometricService.instance.submitChallengeBurst(
        endpoint: '/verify-1to1',
        challengeId: 'chal_mock_2',
        nonce: 'nonce_mock_2',
        frames: frames,
        client: mockClient,
      );

      expect(result.outcome, BiometricServerOutcome.mismatch);
      expect(result.isSuccess, isFalse);
      expect(result.similarity, 0.21);
    });

    test('submitChallengeBurst parses PAD rejection fail-closed', () async {
      final frames = [
        const BurstFramePayloadItem(sequenceIndex: 0, capturedOffsetMs: 0, jpegBase64: 'frame0'),
        const BurstFramePayloadItem(sequenceIndex: 1, capturedOffsetMs: 120, jpegBase64: 'frame1'),
        const BurstFramePayloadItem(sequenceIndex: 2, capturedOffsetMs: 250, jpegBase64: 'frame2'),
      ];

      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': false,
            'status': 'pad_rejected',
            'error': {
              'code': 'BLINK_TRAJECTORY_NOT_SATISFIED',
              'message': 'Blink trajectory not satisfied',
            },
          }),
          400,
          headers: {'content-type': 'application/json'},
        );
      });

      final result = await BiometricService.instance.submitChallengeBurst(
        endpoint: '/verify-1to1',
        challengeId: 'chal_mock_3',
        nonce: 'nonce_mock_3',
        frames: frames,
        client: mockClient,
      );

      expect(result.outcome, BiometricServerOutcome.padRejected);
      expect(result.isSuccess, isFalse);
      expect(result.rejectionCode, 'BLINK_TRAJECTORY_NOT_SATISFIED');
    });

    test('submitChallengeBurst parses duplicate 409 response', () async {
      final frames = [
        const BurstFramePayloadItem(sequenceIndex: 0, capturedOffsetMs: 0, jpegBase64: 'frame0'),
        const BurstFramePayloadItem(sequenceIndex: 1, capturedOffsetMs: 120, jpegBase64: 'frame1'),
        const BurstFramePayloadItem(sequenceIndex: 2, capturedOffsetMs: 250, jpegBase64: 'frame2'),
      ];

      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': false,
            'status': 'duplicate',
            'error': {
              'code': 'BIOMETRIC_DUPLICATE_FOUND',
              'message': 'Same individual already enrolled under another account',
            },
          }),
          409,
          headers: {'content-type': 'application/json'},
        );
      });

      final result = await BiometricService.instance.submitChallengeBurst(
        endpoint: '/enroll-biometric',
        challengeId: 'chal_mock_4',
        nonce: 'nonce_mock_4',
        frames: frames,
        client: mockClient,
      );

      expect(result.outcome, BiometricServerOutcome.duplicate);
      expect(result.isSuccess, isFalse);
    });

    test('submitChallengeBurst handles network exception fail-closed with serviceUnavailable', () async {
      final frames = [
        const BurstFramePayloadItem(sequenceIndex: 0, capturedOffsetMs: 0, jpegBase64: 'frame0'),
        const BurstFramePayloadItem(sequenceIndex: 1, capturedOffsetMs: 120, jpegBase64: 'frame1'),
        const BurstFramePayloadItem(sequenceIndex: 2, capturedOffsetMs: 250, jpegBase64: 'frame2'),
      ];

      final mockClient = MockClient((request) async {
        throw http.ClientException('Connection refused');
      });

      final result = await BiometricService.instance.submitChallengeBurst(
        endpoint: '/verify-1to1',
        challengeId: 'chal_mock_5',
        nonce: 'nonce_mock_5',
        frames: frames,
        client: mockClient,
      );

      expect(result.outcome, BiometricServerOutcome.serviceUnavailable);
      expect(result.isSuccess, isFalse);
    });
  });
}
