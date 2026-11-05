// File: test/play_integrity_binding_test.dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelasagaara/services/play_integrity_request_binding.dart';

void main() {
  group('Play Integrity Request Binding Parity Suite', () {
    test('computes deterministic, URL-safe base64 requestHash in Dart (V1)', () {
      final params = PlayIntegrityBindingParams(
        protocolVersion: kPlayIntegrityBindingProtocolVersionV1,
        authenticatedUid: 'usr_alice_12345',
        challengeId: 'chl_session_001',
        challengePurpose: 'INITIAL_ENROLLMENT',
        serverNonce: 'nonce_server_16b_rand',
        idempotencyKey: 'idem_key_778899',
        httpMethod: 'POST',
        route: '/auth/biometrics/v10/enroll',
        payloadDigestSha256: computeEmbeddingPayloadDigest(List.filled(128, 0.0883883)),
      );

      final hash1 = computePlayIntegrityRequestHash(params);
      final hash2 = computePlayIntegrityRequestHash(params);

      expect(hash1, equals(hash2));
      expect(hash1.length, equals(43));
      expect(RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(hash1), isTrue);
    });

    test('computes deterministic requestHash in Dart for PLAY_INTEGRITY_BINDING_V2 with raw capture bytes', () {
      final dummyCaptureBytes = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
      final captureDigest = computeCaptureImagePayloadDigest(dummyCaptureBytes);

      final paramsV2 = PlayIntegrityBindingParams(
        protocolVersion: kPlayIntegrityBindingProtocolVersionV2,
        appVersion: '1.0.0',
        authenticatedUid: 'usr_alice_12345',
        deviceKeyId: 'devkey_hw_strongbox_001',
        challengeId: 'chl_session_v2_001',
        challengePurpose: 'BIOMETRIC_ENROLLMENT',
        serverNonce: 'nonce_server_32b_rand_value',
        idempotencyKey: 'idem_key_v2_9999',
        httpMethod: 'POST',
        route: '/api/biometrics/v10/enroll',
        payloadDigestSha256: captureDigest,
      );

      final hashV2_1 = computePlayIntegrityRequestHash(paramsV2);
      final hashV2_2 = computePlayIntegrityRequestHash(paramsV2);

      expect(hashV2_1, equals(hashV2_2));
      expect(hashV2_1.length, equals(43));
      expect(RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(hashV2_1), isTrue);
    });

    test('tampering any field in V2 changes requestHash', () {
      final baseParams = PlayIntegrityBindingParams(
        protocolVersion: kPlayIntegrityBindingProtocolVersionV2,
        appVersion: '1.0.0',
        authenticatedUid: 'usr_alice_12345',
        deviceKeyId: 'devkey_hw_strongbox_001',
        challengeId: 'chl_session_v2_001',
        challengePurpose: 'BIOMETRIC_ENROLLMENT',
        serverNonce: 'nonce_server_32b_rand_value',
        idempotencyKey: 'idem_key_v2_9999',
        httpMethod: 'POST',
        route: '/api/biometrics/v10/enroll',
        payloadDigestSha256: 'abc123payload',
      );

      final baseHash = computePlayIntegrityRequestHash(baseParams);

      final tamperedDevice = PlayIntegrityBindingParams(
        protocolVersion: kPlayIntegrityBindingProtocolVersionV2,
        appVersion: '1.0.0',
        authenticatedUid: 'usr_alice_12345',
        deviceKeyId: 'devkey_compromised_attacker_key',
        challengeId: baseParams.challengeId,
        challengePurpose: baseParams.challengePurpose,
        serverNonce: baseParams.serverNonce,
        idempotencyKey: baseParams.idempotencyKey,
        httpMethod: baseParams.httpMethod,
        route: baseParams.route,
        payloadDigestSha256: baseParams.payloadDigestSha256,
      );

      expect(computePlayIntegrityRequestHash(tamperedDevice), isNot(equals(baseHash)));
    });
  });
}
