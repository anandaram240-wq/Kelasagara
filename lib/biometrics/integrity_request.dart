import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

/// Phase 3.3. MUST match computeRequestHash() in backend/src/services/integrity.ts
/// byte for byte (both are tested against the same fixed vector).
String computeRequestHash({
  required String uid,
  required String action,
  required String nonce,
  required List<Uint8List> crops,
  required Uint8List bestFrame,
}) {
  final cropsDigest = sha256Hex(utf8.encode(crops.map(sha256Hex).join(',')));
  final canonical = ['v1', uid, action, nonce, cropsDigest, sha256Hex(bestFrame)].join('|');
  return base64Url.encode(sha256.convert(utf8.encode(canonical)).bytes).replaceAll('=', '');
}

/// Builds a canonical Play Integrity requestHash that cryptographically binds:
/// - PAD liveness verdict (blink detection result)
/// - Laplacian variance (passive anti-spoofing metric)
/// - Frame SHA-256 digest (tamper evidence)
/// - IPD pixels (ISO 29794-5 quality)
/// - Session nonce (replay attack prevention)
///
/// This satisfies UIDAI FaceRD v2.0 WADH (Work Area Data Hash) requirements
/// and ISO/IEC 30107-3 PAD cryptographic binding.
String buildPadBoundRequestHash({
  required String uid,
  required String serverNonce,
  required String frameDigestHex,
  required double laplacianVariance,
  required bool blinkDetected,
  required double ipdPixels,
  String preprocessingId = 'PREPROC_V1_UMEYAMA_112_RGB_RAW255',
}) {
  final fields = [
    'blink=${blinkDetected ? 1 : 0}',
    'frame=${frameDigestHex.length >= 16 ? frameDigestHex.substring(0, 16) : frameDigestHex}',
    'ipd=${ipdPixels.toStringAsFixed(2)}',
    'laplacian=${laplacianVariance.toStringAsFixed(2)}',
    'nonce=$serverNonce',
    'preproc=$preprocessingId',
    'uid=$uid',
  ]..sort();
  final canonical = fields.join('|');
  final digest = sha256.convert(utf8.encode(canonical));
  return digest.toString().substring(0, 32);
}

