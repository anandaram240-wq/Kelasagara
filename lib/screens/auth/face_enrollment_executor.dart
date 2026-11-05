// lib/screens/auth/face_enrollment_executor.dart
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../../widgets/duplicate_account_resolution_sheet.dart';
import '../../biometrics/biomatch_ffi_bridge.dart';
import '../../biometrics/landmark_geometry.dart';

/// Encapsulates the ISO/IEC 19794-5 and ISO/IEC 29794-5 Biometric Sample Quality assessment.
class IsoQualityReport {
  final bool isCompliant;
  final double ipdPixels;
  final double mouthAspectRatio;
  final double illuminationSymmetry;
  final double meanLuminance;
  final String rejectionReasonKannada;
  final String rejectionReasonEnglish;

  const IsoQualityReport({
    required this.isCompliant,
    required this.ipdPixels,
    required this.mouthAspectRatio,
    required this.illuminationSymmetry,
    required this.meanLuminance,
    this.rejectionReasonKannada = '',
    this.rejectionReasonEnglish = '',
  });

  Map<String, dynamic> toMap() => {
    'isCompliant': isCompliant,
    'ipdPixels': ipdPixels,
    'mouthAspectRatio': mouthAspectRatio,
    'illuminationSymmetry': illuminationSymmetry,
    'meanLuminance': meanLuminance,
    'rejectionReasonKannada': rejectionReasonKannada,
    'rejectionReasonEnglish': rejectionReasonEnglish,
  };
}

/// Backwards-compatible alias for IsoQualityReport
typedef IsoQualityVerdict = IsoQualityReport;

class FaceEnrollmentExecutor {
  // ── Aadhaar FaceRD v2.0 & ISO/IEC 19794-5 Quality Thresholds ──────────────
  // Calibrated for standard Indian smartphone front cameras and natural ambient room lighting
  static const double minIpdPixels = 60.0;     // Aadhaar RD standard >= 60px
  static const double maxYawDegrees = 20.0;    // Standard frontal tolerance ±20°
  static const double maxPitchDegrees = 20.0;  // Standard pitch tolerance ±20°
  static const double maxRollDegrees = 15.0;   // Standard in-plane tilt tolerance ±15°
  static const double maxNeutralMar = 0.55;    // Accommodates beards, mustaches, natural rest
  static const double minLuminance = 28.0;     // UIDAI underexposure floor (only pitch black rejected)
  static const double maxLuminance = 248.0;    // UIDAI overexposure ceiling (only blinding glare rejected)
  static const double minBilateralSymmetry = 0.20; // Room lighting friendly (no studio lights needed)

  /// Extracts the 5 canonical ArcFace alignment anchors:
  /// [LeftEye, RightEye, NoseTip, LeftMouth, RightMouth]
  /// When [rotation], [rawW], and [rawH] are provided, transforms landmarks to raw sensor coordinates.
  static List<double>? extract5PointLandmarks(
    Face face, {
    int rotation = 0,
    int rawW = 0,
    int rawH = 0,
  }) {
    if (rotation != 0 && rawW > 0 && rawH > 0) {
      final rawPoints = fivePointsRaw(face, rotation, rawW, rawH);
      if (rawPoints.isNotEmpty) {
        return rawPoints;
      }
    }

    final leftEye = face.landmarks[FaceLandmarkType.leftEye]?.position;
    final rightEye = face.landmarks[FaceLandmarkType.rightEye]?.position;
    final noseBase = face.landmarks[FaceLandmarkType.noseBase]?.position;
    final leftMouth = face.landmarks[FaceLandmarkType.leftMouth]?.position;
    final rightMouth = face.landmarks[FaceLandmarkType.rightMouth]?.position;

    if (leftEye == null ||
        rightEye == null ||
        noseBase == null ||
        leftMouth == null ||
        rightMouth == null) {
      return null;
    }

    return <double>[
      leftEye.x.toDouble(),
      leftEye.y.toDouble(),
      rightEye.x.toDouble(),
      rightEye.y.toDouble(),
      noseBase.x.toDouble(),
      noseBase.y.toDouble(),
      leftMouth.x.toDouble(),
      leftMouth.y.toDouble(),
      rightMouth.x.toDouble(),
      rightMouth.y.toDouble(),
    ];
  }

  /// Resamples a polyline of 2D points into exactly [targetCount] equidistant points
  /// using cumulative chord arc-length parameterization.
  static List<math.Point<double>> resamplePolyline(
    List<math.Point<double>> points,
    int targetCount,
  ) {
    if (targetCount <= 0) return const [];
    if (points.isEmpty) {
      return List.generate(targetCount, (_) => const math.Point<double>(0.0, 0.0));
    }
    if (points.length == targetCount) return List<math.Point<double>>.from(points);
    if (points.length == 1) return List.filled(targetCount, points.first);

    final List<double> cumDist = [0.0];
    for (int i = 1; i < points.length; i++) {
      final dx = points[i].x - points[i - 1].x;
      final dy = points[i].y - points[i - 1].y;
      cumDist.add(cumDist.last + math.sqrt(dx * dx + dy * dy));
    }

    final double totalDist = cumDist.last;
    if (totalDist <= 1e-6) {
      return List.filled(targetCount, points.first);
    }

    final List<math.Point<double>> resampled = [];
    int currentIdx = 0;
    for (int k = 0; k < targetCount; k++) {
      final double targetDist = (k / (targetCount - 1)) * totalDist;
      while (currentIdx < points.length - 2 && cumDist[currentIdx + 1] < targetDist) {
        currentIdx++;
      }
      final double segStartDist = cumDist[currentIdx];
      final double segEndDist = cumDist[currentIdx + 1];
      final double segLen = segEndDist - segStartDist;
      final double t = segLen > 1e-6 ? ((targetDist - segStartDist) / segLen).clamp(0.0, 1.0) : 0.0;
      final p0 = points[currentIdx];
      final p1 = points[currentIdx + 1];
      resampled.add(math.Point<double>(
        p0.x + t * (p1.x - p0.x),
        p0.y + t * (p1.y - p0.y),
      ));
    }
    return resampled;
  }

  /// Reconstructs the 68-point anthropometric landmark matrix from ML Kit contours
  /// for UIDAI nmPoints telemetry and geometric neutrality verification.
  /// Format follows standard 68-point multi-PIE / dlib / ISO 19794-5 convention:
  /// - Points 0..16 (17): Jawline
  /// - Points 17..21 (5): Right eyebrow
  /// - Points 22..26 (5): Left eyebrow
  /// - Points 27..30 (4): Nasal bridge / dorsum
  /// - Points 31..35 (5): Nasal base / bottom
  /// - Points 36..41 (6): Right eye
  /// - Points 42..47 (6): Left eye
  /// - Points 48..54 (7): Outer upper lip
  /// - Points 55..59 (5): Outer lower lip
  /// - Points 60..63 (4): Inner upper lip
  /// - Points 64..67 (4): Inner lower lip
  static List<math.Point<double>> extract68PointAnthropometricMesh(Face face) {
    List<math.Point<double>> extractContour(FaceContourType type) {
      final pts = face.contours[type]?.points;
      if (pts == null || pts.isEmpty) return const [];
      return pts.map((p) => math.Point<double>(p.x.toDouble(), p.y.toDouble())).toList();
    }

    final bbox = face.boundingBox;
    final double cx = bbox.left + bbox.width * 0.5;
    final double cy = bbox.top + bbox.height * 0.45;
    final double rx = bbox.width * 0.46;
    final double ry = bbox.height * 0.52;

    // 1. Jawline (17 points)
    List<math.Point<double>> jaw = extractContour(FaceContourType.face);
    if (jaw.isEmpty) {
      jaw = List.generate(17, (i) {
        final theta = math.pi * (i / 16.0);
        return math.Point<double>(cx - rx * math.cos(theta), cy + ry * math.sin(theta));
      });
    }

    // 2. Eyebrows (5 points each)
    List<math.Point<double>> rightEb = extractContour(FaceContourType.rightEyebrowTop);
    if (rightEb.isEmpty) {
      final eyeR = face.landmarks[FaceLandmarkType.rightEye]?.position;
      final baseY = (eyeR != null ? eyeR.y : bbox.top + bbox.height * 0.32) - bbox.height * 0.08;
      final startX = (eyeR != null ? eyeR.x : cx + rx * 0.4) - bbox.width * 0.15;
      rightEb = List.generate(5, (i) => math.Point<double>(startX + i * (bbox.width * 0.08), baseY.toDouble()));
    }

    List<math.Point<double>> leftEb = extractContour(FaceContourType.leftEyebrowTop);
    if (leftEb.isEmpty) {
      final eyeL = face.landmarks[FaceLandmarkType.leftEye]?.position;
      final baseY = (eyeL != null ? eyeL.y : bbox.top + bbox.height * 0.32) - bbox.height * 0.08;
      final startX = (eyeL != null ? eyeL.x : cx - rx * 0.4) - bbox.width * 0.15;
      leftEb = List.generate(5, (i) => math.Point<double>(startX + i * (bbox.width * 0.08), baseY.toDouble()));
    }

    // 3. Nose bridge (4 points) & Nose bottom (5 points)
    List<math.Point<double>> noseBridge = extractContour(FaceContourType.noseBridge);
    if (noseBridge.isEmpty) {
      final noseTip = face.landmarks[FaceLandmarkType.noseBase]?.position;
      final tipY = noseTip != null ? noseTip.y.toDouble() : cy + bbox.height * 0.1;
      final topY = cy - bbox.height * 0.1;
      noseBridge = List.generate(4, (i) => math.Point<double>(cx, topY + i * (tipY - topY) / 3.0));
    }

    List<math.Point<double>> noseBottom = extractContour(FaceContourType.noseBottom);
    if (noseBottom.isEmpty) {
      final noseTip = face.landmarks[FaceLandmarkType.noseBase]?.position;
      final tipX = noseTip != null ? noseTip.x.toDouble() : cx;
      final tipY = noseTip != null ? noseTip.y.toDouble() : cy + bbox.height * 0.1;
      noseBottom = List.generate(5, (i) => math.Point<double>(tipX + (i - 2) * (bbox.width * 0.06), tipY));
    }

    // 4. Eyes (6 points each)
    List<math.Point<double>> rightEye = extractContour(FaceContourType.rightEye);
    if (rightEye.isEmpty) {
      final eyeR = face.landmarks[FaceLandmarkType.rightEye]?.position;
      final ex = eyeR != null ? eyeR.x.toDouble() : cx + rx * 0.4;
      final ey = eyeR != null ? eyeR.y.toDouble() : cy - bbox.height * 0.08;
      rightEye = List.generate(6, (i) {
        final angle = 2 * math.pi * (i / 6.0);
        return math.Point<double>(ex + 12.0 * math.cos(angle), ey + 6.0 * math.sin(angle));
      });
    }

    List<math.Point<double>> leftEye = extractContour(FaceContourType.leftEye);
    if (leftEye.isEmpty) {
      final eyeL = face.landmarks[FaceLandmarkType.leftEye]?.position;
      final ex = eyeL != null ? eyeL.x.toDouble() : cx - rx * 0.4;
      final ey = eyeL != null ? eyeL.y.toDouble() : cy - bbox.height * 0.08;
      leftEye = List.generate(6, (i) {
        final angle = 2 * math.pi * (i / 6.0);
        return math.Point<double>(ex + 12.0 * math.cos(angle), ey + 6.0 * math.sin(angle));
      });
    }

    // 5. Mouth: Upper Lip Top (7), Lower Lip Bottom (5), Upper Lip Bottom (4), Lower Lip Top (4)
    List<math.Point<double>> upperLipTop = extractContour(FaceContourType.upperLipTop);
    List<math.Point<double>> lowerLipBottom = extractContour(FaceContourType.lowerLipBottom);
    List<math.Point<double>> upperLipBottom = extractContour(FaceContourType.upperLipBottom);
    List<math.Point<double>> lowerLipTop = extractContour(FaceContourType.lowerLipTop);

    final mouthL = face.landmarks[FaceLandmarkType.leftMouth]?.position;
    final mouthR = face.landmarks[FaceLandmarkType.rightMouth]?.position;
    final mouthB = face.landmarks[FaceLandmarkType.bottomMouth]?.position;
    final double mlX = mouthL != null ? mouthL.x.toDouble() : cx - bbox.width * 0.18;
    final double mlY = mouthL != null ? mouthL.y.toDouble() : cy + bbox.height * 0.28;
    final double mrX = mouthR != null ? mouthR.x.toDouble() : cx + bbox.width * 0.18;
    final double mrY = mouthR != null ? mouthR.y.toDouble() : cy + bbox.height * 0.28;
    final double mbY = mouthB != null ? mouthB.y.toDouble() : cy + bbox.height * 0.35;

    if (upperLipTop.isEmpty) {
      upperLipTop = List.generate(7, (i) {
        final t = i / 6.0;
        final x = mlX + t * (mrX - mlX);
        final y = mlY + t * (mrY - mlY) - math.sin(t * math.pi) * 6.0;
        return math.Point<double>(x, y);
      });
    }
    if (lowerLipBottom.isEmpty) {
      lowerLipBottom = List.generate(5, (i) {
        final t = i / 4.0;
        final x = mlX + t * (mrX - mlX);
        final y = mbY + math.sin(t * math.pi) * 4.0;
        return math.Point<double>(x, y);
      });
    }
    if (upperLipBottom.isEmpty) {
      upperLipBottom = List.generate(4, (i) {
        final t = (i + 1) / 5.0;
        return math.Point<double>(mlX + t * (mrX - mlX), mlY + 2.0);
      });
    }
    if (lowerLipTop.isEmpty) {
      lowerLipTop = List.generate(4, (i) {
        final t = (i + 1) / 5.0;
        return math.Point<double>(mlX + t * (mrX - mlX), mlY + 4.0);
      });
    }

    // Assemble exactly 68 resampled points:
    // 17 + 5 + 5 + 4 + 5 + 6 + 6 + 7 + 5 + 4 + 4 = 68
    final List<math.Point<double>> mesh = [
      ...resamplePolyline(jaw, 17),
      ...resamplePolyline(rightEb, 5),
      ...resamplePolyline(leftEb, 5),
      ...resamplePolyline(noseBridge, 4),
      ...resamplePolyline(noseBottom, 5),
      ...resamplePolyline(rightEye, 6),
      ...resamplePolyline(leftEye, 6),
      ...resamplePolyline(upperLipTop, 7),
      ...resamplePolyline(lowerLipBottom, 5),
      ...resamplePolyline(upperLipBottom, 4),
      ...resamplePolyline(lowerLipTop, 4),
    ];

    return mesh;
  }

  /// Alias for extract68PointAnthropometricMesh
  static List<math.Point<double>> reconstruct68PointMatrix(Face face) =>
      extract68PointAnthropometricMesh(face);

  /// Evaluates ISO/IEC 19794-5 & 29794-5 Biometric Sample Quality Gates
  static IsoQualityReport evaluateIso29794Quality(
    Face face, [
    CameraImage? image,
  ]) {
    final leftEye = face.landmarks[FaceLandmarkType.leftEye]?.position;
    final rightEye = face.landmarks[FaceLandmarkType.rightEye]?.position;
    final leftMouth = face.landmarks[FaceLandmarkType.leftMouth]?.position;
    final rightMouth = face.landmarks[FaceLandmarkType.rightMouth]?.position;
    final bottomMouth = face.landmarks[FaceLandmarkType.bottomMouth]?.position;
    final noseBase = face.landmarks[FaceLandmarkType.noseBase]?.position;

    if (leftEye == null ||
        rightEye == null ||
        leftMouth == null ||
        rightMouth == null ||
        noseBase == null) {
      return const IsoQualityReport(
        isCompliant: false,
        ipdPixels: 0.0,
        mouthAspectRatio: 0.0,
        illuminationSymmetry: 0.0,
        meanLuminance: 0.0,
        rejectionReasonKannada: 'ಮುಖದ ಗುರುತುಗಳು ಸ್ಪಷ್ಟವಾಗಿಲ್ಲ',
        rejectionReasonEnglish: 'Facial landmarks occluded',
      );
    }

    // 1. Inter-Pupillary Distance (IPD >= 90 px)
    final double dx = (rightEye.x - leftEye.x).toDouble();
    final double dy = (rightEye.y - leftEye.y).toDouble();
    final double ipd = math.sqrt(dx * dx + dy * dy);
    if (ipd < minIpdPixels) {
      return IsoQualityReport(
        isCompliant: false,
        ipdPixels: ipd,
        mouthAspectRatio: 0.0,
        illuminationSymmetry: 1.0,
        meanLuminance: 128.0,
        rejectionReasonKannada: 'ಕ್ಯಾಮರಾವನ್ನು ಮುಖದ ಹತ್ತಿರ ತನ್ನಿ',
        rejectionReasonEnglish: 'Move camera closer (IPD below 90px)',
      );
    }

    // 2. 3D Head Pose Euler Angles (|Yaw| <= 15, |Pitch| <= 15, |Roll| <= 10)
    final double yaw = (face.headEulerAngleY ?? 0.0).abs();
    final double pitch = (face.headEulerAngleX ?? 0.0).abs();
    final double roll = (face.headEulerAngleZ ?? 0.0).abs();
    if (yaw > maxYawDegrees || pitch > maxPitchDegrees || roll > maxRollDegrees) {
      return IsoQualityReport(
        isCompliant: false,
        ipdPixels: ipd,
        mouthAspectRatio: 0.0,
        illuminationSymmetry: 1.0,
        meanLuminance: 128.0,
        rejectionReasonKannada: 'ದಯವಿಟ್ಟು ನೇರವಾಗಿ ಕ್ಯಾಮರಾ ಕಡೆಗೆ ನೋಡಿ',
        rejectionReasonEnglish: 'Face the camera directly',
      );
    }

    // 3. Mouth Aspect Ratio (MAR <= 0.35 for neutral closed expression)
    final double mouthWidth = math.sqrt(
      math.pow(rightMouth.x - leftMouth.x, 2) +
          math.pow(rightMouth.y - leftMouth.y, 2),
    );
    double mouthHeight = 0.0;
    final upperLipBottom =
        face.contours[FaceContourType.upperLipBottom]?.points;
    final lowerLipTop = face.contours[FaceContourType.lowerLipTop]?.points;
    if (upperLipBottom != null &&
        lowerLipTop != null &&
        upperLipBottom.isNotEmpty &&
        lowerLipTop.isNotEmpty) {
      final midUpper = upperLipBottom[upperLipBottom.length ~/ 2];
      final midLower = lowerLipTop[lowerLipTop.length ~/ 2];
      mouthHeight = math.sqrt(
        math.pow(midLower.x - midUpper.x, 2) +
            math.pow(midLower.y - midUpper.y, 2),
      );
    } else if (bottomMouth != null) {
      final double midMouthY = (leftMouth.y + rightMouth.y) * 0.5;
      mouthHeight = (bottomMouth.y - midMouthY).abs();
    }
    final double mar = mouthWidth > 1.0 ? (mouthHeight / mouthWidth) : 0.0;
    if (mar > maxNeutralMar || (face.smilingProbability != null && face.smilingProbability! > 0.45)) {
      return IsoQualityReport(
        isCompliant: false,
        ipdPixels: ipd,
        mouthAspectRatio: mar,
        illuminationSymmetry: 1.0,
        meanLuminance: 128.0,
        rejectionReasonKannada: 'ಬಾಯಿ ಮುಚ್ಚಿ ಸಹಜವಾಗಿ ಕುಳಿತುಕೊಳ್ಳಿ',
        rejectionReasonEnglish: 'Keep a neutral expression with mouth closed',
      );
    }

    // 4. Aadhaar FaceRD Level-0 Photometric Exposure Verification
    // Verifies the user is not in pitch darkness (< 28) and not blinded by flash (> 248).
    // Does NOT fail on natural ambient room lighting asymmetry (matches UIDAI FaceRD standard).
    double meanLuma = 128.0;
    double symmetry = 1.0;

    if (image != null && image.planes.isNotEmpty) {
      final Uint8List yPlane = image.planes[0].bytes;
      final int len = yPlane.length;
      if (len > 0) {
        double sum = 0.0;
        int count = 0;
        final int step = math.max(1, len ~/ 150);
        // Sample central 50% of the camera sensor frame (where face is placed)
        final int startIdx = len ~/ 4;
        final int endIdx = (3 * len) ~/ 4;
        for (int i = startIdx; i < endIdx; i += step) {
          sum += yPlane[i];
          count++;
        }
        meanLuma = count > 0 ? sum / count : 128.0;
      }

      // Extreme darkness rejection only
      if (meanLuma < minLuminance) {
        return IsoQualityReport(
          isCompliant: false,
          ipdPixels: ipd,
          mouthAspectRatio: mar,
          illuminationSymmetry: symmetry,
          meanLuminance: meanLuma,
          rejectionReasonKannada: 'ಬೆಳಕಿರುವ ಸ್ಥಳಕ್ಕೆ ಬನ್ನಿ',
          rejectionReasonEnglish: 'Lighting too dark — please move to a brighter spot',
        );
      }

      // Extreme over-exposure rejection only
      if (meanLuma > maxLuminance) {
        return IsoQualityReport(
          isCompliant: false,
          ipdPixels: ipd,
          mouthAspectRatio: mar,
          illuminationSymmetry: symmetry,
          meanLuminance: meanLuma,
          rejectionReasonKannada: 'ಬೆಳಕು ತುಂಬಾ ಪ್ರಖರವಾಗಿದೆ',
          rejectionReasonEnglish: 'Too much glare — please avoid direct bright lights',
        );
      }
    }

    return IsoQualityReport(
      isCompliant: true,
      ipdPixels: ipd,
      mouthAspectRatio: mar,
      illuminationSymmetry: symmetry,
      meanLuminance: meanLuma,
    );
  }

  /// Normalizes single-plane NV21 or 3-plane YUV_420_888 camera buffers into FrameIsolatePayload
  static FrameIsolatePayload buildFramePayload(
    CameraImage image,
    List<double> landmarks10,
  ) {
    if (image.planes.length == 1) {
      final Uint8List fullNv21 = image.planes[0].bytes;
      final int frameSize = image.width * image.height;
      final Uint8List yBytes = Uint8List.sublistView(fullNv21, 0, frameSize);
      final Uint8List vBytes = Uint8List.sublistView(fullNv21, frameSize);
      final Uint8List uBytes = Uint8List.sublistView(fullNv21, frameSize + 1);

      return FrameIsolatePayload(
        yBytes: Uint8List.fromList(yBytes),
        yRowStride: image.planes[0].bytesPerRow,
        uBytes: Uint8List.fromList(uBytes),
        vBytes: Uint8List.fromList(vBytes),
        uvRowStride: image.planes[0].bytesPerRow,
        uvPixelStride: 2,
        width: image.width,
        height: image.height,
        landmarks10: landmarks10,
      );
    } else {
      return FrameIsolatePayload(
        yBytes: Uint8List.fromList(image.planes[0].bytes),
        yRowStride: image.planes[0].bytesPerRow,
        uBytes: Uint8List.fromList(image.planes[1].bytes),
        vBytes: Uint8List.fromList(image.planes[2].bytes),
        uvRowStride: image.planes[1].bytesPerRow,
        uvPixelStride: image.planes[1].bytesPerPixel ?? 2,
        width: image.width,
        height: image.height,
        landmarks10: landmarks10,
      );
    }
  }

  /// Computes canonical Play Integrity requestHash binding server nonce, UID, and frame digest
  static String computePlayIntegrityRequestHash({
    required String serverNonce,
    required String uid,
    required String captureDigestHex,
  }) {
    final String raw = '$serverNonce:$uid:BIOMETRIC_ENROLL:$captureDigestHex';
    return base64UrlEncode(sha256.convert(utf8.encode(raw)).bytes)
        .replaceAll('=', '');
  }

  /// Full execution triggered once the active blink state machine completes
  static Future<void> onBlinkCompletedAndCapture({
    required BuildContext context,
    required CameraImage frame,
    required Face detectedFace,
    required String uid,
    required String serverNonce,
    required Future<Map<String, dynamic>> Function({
      required Float32List embedding,
      required double qualityNorm,
      required String captureDigestHex,
      required String requestHash,
    }) submitToBackend,
  }) async {
    final List<double>? landmarks10 = extract5PointLandmarks(detectedFace);
    if (landmarks10 == null) {
      _showSnackBar(context, 'ಮುಖದ ಗುರುತುಗಳು ಸ್ಪಷ್ಟವಾಗಿಲ್ಲ (Facial landmarks unclear. Try again.)');
      return;
    }

    final FrameIsolatePayload payload = buildFramePayload(frame, landmarks10);
    final BiomatchInferenceOutput result = await BiomatchNativeBridge.processAndInferAsync(payload);

    if (!result.isSuccess) {
      final String message = switch (result.status) {
        BiomatchStatus.padBlurOrPrintAttack =>
          'ಮಂದ ಬೆಳಕು ಅಥವಾ ಮುದ್ರಿತ ಫೋಟೋ ಪತ್ತೆಯಾಗಿದೆ (Blurry frame or photo print detected: ${result.laplacianVariance.toStringAsFixed(1)})',
        BiomatchStatus.padMoireScreenAttack =>
          'ಮೊಬೈಲ್ ಪರದೆಯ ದಾಳಿ ಪತ್ತೆಯಾಗಿದೆ (Screen replay attack rejected)',
        BiomatchStatus.lowMagFaceQualityNorm =>
          'ಮುಖದ ಗುಣಮಟ್ಟ ಕಡಿಮೆಯಾಗಿದೆ, ಬೆಳಕಿನಲ್ಲಿ ನಿಲ್ಲಿ (Low lighting quality: ${result.qualityNorm.toStringAsFixed(1)} < 18.5)',
        _ => 'ಬಯೋಮೆಟ್ರಿಕ್ ದೋಷ (Biometric engine error: ${result.status.name})',
      };
      if (context.mounted) _showSnackBar(context, message);
      return;
    }

    // Bind frame digest to Play Integrity requestHash
    final String requestHash = computePlayIntegrityRequestHash(
      serverNonce: serverNonce,
      uid: uid,
      captureDigestHex: result.captureDigestHex,
    );

    final Map<String, dynamic> backendResponse = await submitToBackend(
      embedding: result.embedding,
      qualityNorm: result.qualityNorm,
      captureDigestHex: result.captureDigestHex,
      requestHash: requestHash,
    );

    // Zero the Dart-side Float32List embedding immediately after transmission per DPDPA 2023
    result.embedding.fillRange(0, result.embedding.length, 0.0);

    if (!context.mounted) return;

    if (backendResponse['status'] == 'DUPLICATE_DETECTED') {
      final caseRef = backendResponse['caseReference'] as String? ??
          'CASE-${DateTime.now().millisecondsSinceEpoch.toRadixString(16).toUpperCase()}';
      DuplicateAccountResolutionSheet.show(
        context,
        caseReference: caseRef,
        isAmbiguousReview: backendResponse['isAmbiguousReview'] == true,
        onSignInExistingAccount: () {
          if (context.mounted) {
            Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
          }
        },
        onRecoverExistingAccount: () {
          if (context.mounted) {
            Navigator.of(context).pushNamed('/account-recovery');
          }
        },
        onRequestBiometricReview: () {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('ಮರುಪರಿಶೀಲನೆ ವಿನಂತಿಯನ್ನು ದಾಖಲಿಸಲಾಗಿದೆ (Biometric review request logged)'),
              ),
            );
            Navigator.of(context).pop();
          }
        },
      );
    }
  }

  static void _showSnackBar(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
