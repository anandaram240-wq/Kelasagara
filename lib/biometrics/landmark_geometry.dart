import 'dart:ui' show Offset;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// ML Kit reports points in the UPRIGHT image. The native warper samples the
/// RAW sensor buffer. [rotation] is the clockwise degrees (0/90/180/270) you
/// gave ML Kit as the InputImage rotation. Verified against numpy
/// (native/verify_rotation.py) and against a synthetic-frame warp
/// (native/test_align.cpp). MUST match upright_to_raw() in align_crop.h.
Offset uprightToRaw(Offset p, int rotation, int rawW, int rawH) {
  switch (rotation) {
    case 90:
      return Offset(p.dy, rawH - 1 - p.dx);
    case 180:
      return Offset(rawW - 1 - p.dx, rawH - 1 - p.dy);
    case 270:
      return Offset(rawW - 1 - p.dy, p.dx);
    default:
      return p;
  }
}

/// Five landmarks in RAW-frame coordinates, as [x0,y0,...,x4,y4], ordered
/// image-left eye, image-right eye, nose, image-left mouth, image-right mouth.
/// Sorting by x means we never depend on ML Kit's left/right naming.
/// Returns an empty list when any landmark is missing.
List<double> fivePointsRaw(Face f, int rotation, int rawW, int rawH) {
  Offset? pt(FaceLandmarkType t) {
    final p = f.landmarks[t]?.position;
    return p == null ? null : Offset(p.x.toDouble(), p.y.toDouble());
  }

  final le = pt(FaceLandmarkType.leftEye);
  final re = pt(FaceLandmarkType.rightEye);
  final nose = pt(FaceLandmarkType.noseBase);
  final lm = pt(FaceLandmarkType.leftMouth);
  final rm = pt(FaceLandmarkType.rightMouth);
  if (le == null || re == null || nose == null || lm == null || rm == null) {
    return const <double>[];
  }
  final eyes = [le, re]..sort((a, b) => a.dx.compareTo(b.dx));
  final mouth = [lm, rm]..sort((a, b) => a.dx.compareTo(b.dx));
  final pts = [eyes[0], eyes[1], nose, mouth[0], mouth[1]]
      .map((p) => uprightToRaw(p, rotation, rawW, rawH))
      .toList();
  return <double>[for (final p in pts) ...[p.dx, p.dy]];
}
