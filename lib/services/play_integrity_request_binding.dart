// File: lib/services/play_integrity_request_binding.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

const String kPlayIntegrityBindingProtocolVersionV1 = 'PLAY_INTEGRITY_BINDING_V1';
const String kPlayIntegrityBindingProtocolVersionV2 = 'PLAY_INTEGRITY_BINDING_V2';
const String kPlayIntegrityBindingProtocolVersion = kPlayIntegrityBindingProtocolVersionV2;
const String kDefaultPackageName = 'com.kelasagaara.kelasagaara';

class PlayIntegrityBindingParams {
  final String? protocolVersion;
  final String? packageName;
  final String? appVersion;
  final String authenticatedUid;
  final String? deviceKeyId;
  final String challengeId;
  final String challengePurpose;
  final String serverNonce;
  final String idempotencyKey;
  final String httpMethod;
  final String route;
  final String payloadDigestSha256;

  const PlayIntegrityBindingParams({
    this.protocolVersion,
    this.packageName,
    this.appVersion,
    required this.authenticatedUid,
    this.deviceKeyId,
    required this.challengeId,
    required this.challengePurpose,
    required this.serverNonce,
    required this.idempotencyKey,
    required this.httpMethod,
    required this.route,
    required this.payloadDigestSha256,
  });
}

/// Length-prefixed canonical binary serialization matching backend TypeScript implementation exactly.
/// Guarantees 100% deterministic binary representation across languages, immune to delimiter collisions.
Uint8List serializeCanonicalBinding(PlayIntegrityBindingParams params) {
  final isV2 = (params.protocolVersion ?? kPlayIntegrityBindingProtocolVersion) == kPlayIntegrityBindingProtocolVersionV2;
  final protocol = params.protocolVersion ?? kPlayIntegrityBindingProtocolVersion;
  final pkg = params.packageName ?? kDefaultPackageName;

  final nonceHash = sha256.convert(utf8.encode(params.serverNonce)).toString();

  List<String> fields;

  if (isV2) {
    fields = [
      protocol,
      pkg,
      params.appVersion ?? '1.0.0',
      params.authenticatedUid,
      params.deviceKeyId ?? 'unbound_devkey',
      params.challengeId,
      params.challengePurpose,
      nonceHash,
      params.httpMethod.toUpperCase(),
      params.route.toLowerCase(),
      params.idempotencyKey,
      params.payloadDigestSha256,
    ];
  } else {
    fields = [
      protocol,
      pkg,
      params.authenticatedUid,
      params.challengeId,
      params.challengePurpose,
      nonceHash,
      params.idempotencyKey,
      params.httpMethod.toUpperCase(),
      params.route.toLowerCase(),
      params.payloadDigestSha256,
    ];
  }

  final builder = BytesBuilder(copy: false);
  for (final field in fields) {
    final fieldBytes = utf8.encode(field);
    final lenBytes = ByteData(4)..setUint32(0, fieldBytes.length, Endian.big);
    builder.add(lenBytes.buffer.asUint8List());
    builder.add(fieldBytes);
  }

  return builder.toBytes();
}

/// Computes the Base64Url-encoded SHA-256 digest (URL-safe, without '=') for Google Play Standard Integrity.
String computePlayIntegrityRequestHash(PlayIntegrityBindingParams params) {
  final canonicalBytes = serializeCanonicalBinding(params);
  final digest = sha256.convert(canonicalBytes);
  return base64UrlEncode(digest.bytes).replaceAll('=', '');
}

/// Computes a standardized SHA-256 hex digest for exact submitted raw capture image bytes.
/// MANDATED BY V20.3: Never extract client-side vectors; bind the exact camera bytes transmitted to backend.
String computeCaptureImagePayloadDigest(Uint8List imageBytes) {
  return sha256.convert(imageBytes).toString();
}

/// Computes a standardized SHA-256 hex digest for a 128-D Float32List or List<double> (legacy fallback).
String computeEmbeddingPayloadDigest(List<double> embedding) {
  final byteData = ByteData(embedding.length * 4);
  for (int i = 0; i < embedding.length; i++) {
    byteData.setFloat32(i * 4, embedding[i], Endian.little);
  }
  return sha256.convert(byteData.buffer.asUint8List()).toString();
}
