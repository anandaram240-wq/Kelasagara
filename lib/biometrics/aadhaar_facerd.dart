import 'package:flutter/services.dart';

/// Phase 5.1. Launches UIDAI's own FaceRD app. Capture, liveness and PID
/// encryption happen inside that app, not in yours. [pidOptionsXml] must be
/// built exactly as UIDAI's RD specification and "App Initiated Capture
/// Journey" page describe (your AUA/KUA server is the natural place to build
/// it). Returns the encrypted PID response to forward through your AUA/KUA
/// chain to UIDAI. Never store it, and never parse it for biometrics.
class AadhaarFaceRd {
  static const _ch = MethodChannel('in.kelasagara/aadhaar_facerd');

  Future<bool> isInstalled() async => (await _ch.invokeMethod<bool>('isInstalled')) ?? false;

  Future<String> capture(String pidOptionsXml) async {
    final res = await _ch.invokeMethod<String>('capture', {'request': pidOptionsXml});
    if (res == null || res.isEmpty) throw StateError('FaceRD returned nothing');
    return res;
  }
}
