// File: lib/services/device_request_signature.dart
import 'dart:convert';
import 'package:flutter/services.dart';
import 'play_integrity_request_binding.dart';

/// Flutter client service for Android Keystore Device-Bound Trust (Phase 20.3)
class DeviceRequestSignatureService {
  static const MethodChannel _channel = MethodChannel('kelasagara/device_key');
  static const String defaultAlias = 'kelasagara_device_bound_key_v1';

  static final DeviceRequestSignatureService _instance = DeviceRequestSignatureService._internal();
  factory DeviceRequestSignatureService() => _instance;
  DeviceRequestSignatureService._internal();

  /// Generates a device-bound ECDSA P-256 key pair with Android Key Attestation
  /// using the provided server-issued registration challenge.
  Future<Map<String, dynamic>> generateDeviceKey({
    String alias = defaultAlias,
    required String challenge,
  }) async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'generateDeviceKey',
        {
          'alias': alias,
          'challenge': challenge,
        },
      );
      if (result == null) {
        throw Exception('Native key generation returned null');
      }
      return Map<String, dynamic>.from(result);
    } on PlatformException catch (e) {
      throw Exception('Failed to generate device key: ${e.code} - ${e.message}');
    }
  }

  /// Retrieves the exportable SPKI PEM-encoded public key.
  Future<String?> getPublicKey({String alias = defaultAlias}) async {
    try {
      final pem = await _channel.invokeMethod<String>(
        'getPublicKey',
        {'alias': alias},
      );
      return pem;
    } on PlatformException catch (_) {
      return null;
    }
  }

  /// Retrieves the X.509 certificate chain as Base64-encoded DER strings.
  Future<List<String>> getCertificateChain({String alias = defaultAlias}) async {
    try {
      final list = await _channel.invokeListMethod<String>(
        'getCertificateChain',
        {'alias': alias},
      );
      return list ?? [];
    } on PlatformException catch (_) {
      return [];
    }
  }

  /// Signs arbitrary canonical data using the hardware-backed private key.
  /// Returns Base64-encoded ASN.1 DER ECDSA signature.
  Future<String> signData({
    String alias = defaultAlias,
    required Uint8List canonicalData,
  }) async {
    try {
      final base64Data = base64Encode(canonicalData);
      final sig = await _channel.invokeMethod<String>(
        'signTransaction',
        {
          'alias': alias,
          'canonicalData': base64Data,
        },
      );
      if (sig == null) {
        throw Exception('Native signature generation returned null');
      }
      return sig;
    } on PlatformException catch (e) {
      throw Exception('Failed to sign transaction: ${e.code} - ${e.message}');
    }
  }

  /// Serializes the canonical V2 transaction binding, signs it with the local device private key,
  /// and produces the signature and request hash headers.
  Future<Map<String, String>> signCanonicalTransaction(
    PlayIntegrityBindingParams params, {
    String alias = defaultAlias,
  }) async {
    final canonicalBytes = serializeCanonicalBinding(params);
    final signatureBase64 = await signData(alias: alias, canonicalData: canonicalBytes);
    final requestHash = computePlayIntegrityRequestHash(params);

    return {
      'x-device-key-id': params.deviceKeyId ?? 'unbound_devkey',
      'x-device-signature': signatureBase64,
      'x-canonical-request-hash': requestHash,
      'x-transaction-challenge-id': params.challengeId,
      'x-idempotency-key': params.idempotencyKey,
    };
  }

  /// Checks if a device key currently exists under the specified alias.
  Future<bool> hasDeviceKey({String alias = defaultAlias}) async {
    try {
      final exists = await _channel.invokeMethod<bool>(
        'hasDeviceKey',
        {'alias': alias},
      );
      return exists ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  /// Deletes the local device key.
  Future<bool> deleteDeviceKey({String alias = defaultAlias}) async {
    try {
      final deleted = await _channel.invokeMethod<bool>(
        'deleteDeviceKey',
        {'alias': alias},
      );
      return deleted ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }
}
