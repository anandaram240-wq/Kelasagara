import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart' as crypt;

class UidaiPidBlockGenerator {
  static const String pidVersion = '2.0';

  /// Computes the 256-bit Window Authentication Device Hash (WADH)
  /// binding application context, Sub-AUA identity, challenge nonce, and timestamp.
  static String computeWadh({
    required String appId,
    required String subAuaCode,
    required String challengeNonce,
    required String isoTimestamp,
    required String txnId,
  }) {
    final String canonicalPreimage =
        '$appId|$subAuaCode|$pidVersion|$isoTimestamp|$txnId|$challengeNonce';
    final Digest digest = sha256.convert(utf8.encode(canonicalPreimage));
    return base64.encode(digest.bytes);
  }

  /// Builds a compliant UIDAI FaceRD L0 <PidData> XML envelope using AES-256-GCM.
  static Future<String> buildSignedPidDataXml({
    required Float32List cancelableEmbedding128,
    required String isoTimestamp,
    required String txnId,
    required String deviceCode,
    required String modelId,
    required String certExpiryIdentifier, // ci attribute (YYYYMMDD)
    required Uint8List encryptedSessionKeyBytes,
    required String wadhBase64,
    required double padScore,
  }) async {
    // 1. Generate ephemeral 256-bit AES-GCM Session Key & 96-bit IV (last 12 bytes of ts)
    final Random csprng = Random.secure();
    final Uint8List aesSessionKey =
        Uint8List.fromList(List<int>.generate(32, (_) => csprng.nextInt(256)));

    final Uint8List tsBytes = utf8.encode(isoTimestamp);
    final Uint8List ivBytes = Uint8List.fromList(
        tsBytes.sublist(tsBytes.length >= 12 ? tsBytes.length - 12 : 0, tsBytes.length));
    final Uint8List aadBytes = Uint8List.fromList(
        tsBytes.sublist(tsBytes.length >= 16 ? tsBytes.length - 16 : 0, tsBytes.length));

    // Pad IV to 12 bytes if timestamp was short
    final Uint8List fixedIv = Uint8List(12);
    for (int i = 0; i < 12; i++) {
      fixedIv[i] = i < ivBytes.length ? ivBytes[i] : (i * 17) & 0xFF;
    }

    // 2. Construct Inner Plaintext <Pid> XML
    final ByteData embByteData = cancelableEmbedding128.buffer.asByteData();
    final String bioPayloadBase64 = base64.encode(embByteData.buffer.asUint8List());

    final String innerPidXml =
        '<Pid ts="$isoTimestamp" ver="$pidVersion" wadh="$wadhBase64">'
        '<Bios dih="KELASAGARA-RD-L0">'
        '<Bio type="FACE" posh="FACE" bs="$bioPayloadBase64"/>'
        '</Bios>'
        '</Pid>';

    final Uint8List pidPlainBytes = utf8.encode(innerPidXml);

    // 3. Compute SHA-256 of plaintext PID block, then encrypt HMAC and PID with AES-256-GCM
    final Uint8List pidSha256Bytes =
        Uint8List.fromList(sha256.convert(pidPlainBytes).bytes);

    final aesGcm = crypt.AesGcm.with256bits();
    final secretKey = crypt.SecretKey(aesSessionKey);

    final encryptedPidBox = await aesGcm.encrypt(
      pidPlainBytes,
      secretKey: secretKey,
      nonce: fixedIv,
      aad: aadBytes,
    );

    final encryptedHmacBox = await aesGcm.encrypt(
      pidSha256Bytes,
      secretKey: secretKey,
      nonce: fixedIv,
      aad: aadBytes,
    );

    // Append timestamp bytes header to encrypted PID payload per FaceRD v2.0 spec
    final BytesBuilder dataBlockBuilder = BytesBuilder()
      ..add(utf8.encode(isoTimestamp))
      ..add(encryptedPidBox.cipherText)
      ..add(encryptedPidBox.mac.bytes);

    final String skeyB64 = base64.encode(encryptedSessionKeyBytes);
    final String hmacB64 = base64.encode(
        [...encryptedHmacBox.cipherText, ...encryptedHmacBox.mac.bytes]);
    final String dataB64 = base64.encode(dataBlockBuilder.toBytes());

    // Scrub ephemeral key from memory
    aesSessionKey.fillRange(0, aesSessionKey.length, 0);

    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
        '<PidData>\n'
        '  <Resp errCode="0" errInfo="Success" fCount="0" fType="0" iCount="0" pCount="1" pType="0" qScore="${(padScore * 100).round()}"/>\n'
        '  <DeviceInfo dpId="IN.KELASAGARA.RD" rdsId="IN.KELASAGARA.FACERD.L0" rdsVer="17.0.0" dc="$deviceCode" mi="$modelId" mc="">\n'
        '    <additional_info>\n'
        '      <Param name="txnId" value="$txnId"/>\n'
        '      <Param name="wadh" value="$wadhBase64"/>\n'
        '      <Param name="padStandard" value="ISO/IEC-30107-3"/>\n'
        '    </additional_info>\n'
        '  </DeviceInfo>\n'
        '  <Skey ci="$certExpiryIdentifier">$skeyB64</Skey>\n'
        '  <Hmac>$hmacB64</Hmac>\n'
        '  <Data type="X">$dataB64</Data>\n'
        '</PidData>';
  }
}
