import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

enum PadVerdict {
  collectingFrames,
  spoofPrintPaperDetected,
  spoofDigitalScreenMoireDetected,
  spoofAbnormalBlinkTiming,
  spoofHeadPoseOutOfBounds,
  bonaFideLiveHuman,
}

class Iso30107PadGate {
  static const double minLaplacianVariance = 40.0;   // Below = matte paper / defocus spoof
  static const double maxLaplacianVariance = 3800.0; // Above = OLED/LCD subpixel moiré grid
  static const double eyeClosedThreshold = 0.22;
  static const double eyeOpenThreshold = 0.72;
  static const int minBlinkDurationMs = 90;
  static const int maxBlinkDurationMs = 450;

  DateTime? _blinkStartTimestamp;
  bool _hasCompletedValidBlink = false;
  bool _eyesWereOpenInitially = false;
  final List<double> _recentLaplacianVariances = [];

  void reset() {
    _blinkStartTimestamp = null;
    _hasCompletedValidBlink = false;
    _eyesWereOpenInitially = false;
    _recentLaplacianVariances.clear();
  }

  PadVerdict evaluateFrame({
    required Face face,
    required double laplacianVariance,
    required DateTime frameTimestamp,
  }) {
    // 1. Enforce strict frontal pose bounds (|yaw| <= 15 deg, |roll| <= 12 deg)
    final double yaw = (face.headEulerAngleY ?? 0.0).abs();
    final double roll = (face.headEulerAngleZ ?? 0.0).abs();
    if (yaw > 15.0 || roll > 12.0) {
      return PadVerdict.spoofHeadPoseOutOfBounds;
    }

    // 2. Stage-2 Texture & Frequency Gate (Print Paper & Screen Moiré)
    if (laplacianVariance < minLaplacianVariance) {
      return PadVerdict.spoofPrintPaperDetected;
    }
    if (laplacianVariance > maxLaplacianVariance) {
      return PadVerdict.spoofDigitalScreenMoireDetected;
    }

    _recentLaplacianVariances.add(laplacianVariance);
    if (_recentLaplacianVariances.length > 10) {
      _recentLaplacianVariances.removeAt(0);
    }

    // 3. Stage-1 Dynamic Blink Hysteresis State Machine
    final double leftOpen = face.leftEyeOpenProbability ?? -1.0;
    final double rightOpen = face.rightEyeOpenProbability ?? -1.0;
    if (leftOpen < 0.0 || rightOpen < 0.0) {
      return PadVerdict.collectingFrames;
    }

    final double meanEyeOpen = (leftOpen + rightOpen) * 0.5;

    if (!_eyesWereOpenInitially) {
      if (meanEyeOpen >= eyeOpenThreshold) {
        _eyesWereOpenInitially = true;
      }
      return PadVerdict.collectingFrames;
    }

    if (!_hasCompletedValidBlink) {
      if (meanEyeOpen <= eyeClosedThreshold && _blinkStartTimestamp == null) {
        _blinkStartTimestamp = frameTimestamp;
        return PadVerdict.collectingFrames;
      }

      if (meanEyeOpen >= eyeOpenThreshold && _blinkStartTimestamp != null) {
        final int blinkMs =
            frameTimestamp.difference(_blinkStartTimestamp!).inMilliseconds;
        _blinkStartTimestamp = null;

        if (blinkMs < minBlinkDurationMs || blinkMs > maxBlinkDurationMs) {
          return PadVerdict.spoofAbnormalBlinkTiming;
        }
        _hasCompletedValidBlink = true;
      }
    }

    if (_hasCompletedValidBlink && _recentLaplacianVariances.length >= 5) {
      return PadVerdict.bonaFideLiveHuman;
    }

    return PadVerdict.collectingFrames;
  }
}
