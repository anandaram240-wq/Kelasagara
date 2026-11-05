// FILE: lib/biometrics/biometric_v11_capture_controller.dart

import 'dart:async';
import 'package:flutter/foundation.dart';

enum V11CaptureState {
  idle,
  guiding,
  capturing,
  fusing,
  stepUpRequired,
  completed,
  rejected,
}

enum V11ChallengeAction {
  blink,
  turnLeft,
  turnRight,
  nod,
}

class V11FrameQualitySample {
  final double sharpnessVariance;
  final double meanLuminance;
  final double hemifaceDelta;
  final double yawDeg;
  final double pitchDeg;
  final double rollDeg;
  final double eyeOpenRatio;
  final List<double> embedding;

  const V11FrameQualitySample({
    required this.sharpnessVariance,
    required this.meanLuminance,
    required this.hemifaceDelta,
    required this.yawDeg,
    required this.pitchDeg,
    required this.rollDeg,
    required this.eyeOpenRatio,
    required this.embedding,
  });

  bool get isSharp => sharpnessVariance >= 15.0;
  bool get isWellLit => meanLuminance >= 40.0 && meanLuminance <= 220.0 && hemifaceDelta <= 65.0;
  bool get isPoseCentered => yawDeg.abs() <= 18.0 && pitchDeg.abs() <= 18.0 && rollDeg.abs() <= 15.0;
  bool get areEyesOpen => eyeOpenRatio >= 0.20;

  bool get isAcceptable => isSharp && isWellLit && isPoseCentered && areEyesOpen;

  double get computedScore {
    if (!isAcceptable) return 0.2;
    final sharpNorm = (sharpnessVariance / 60.0).clamp(0.0, 1.0);
    final illumNorm = 1.0 - ((meanLuminance - 128.0).abs() / 128.0).clamp(0.0, 1.0);
    return ((0.5 * sharpNorm + 0.5 * illumNorm) * 0.95).clamp(0.75, 1.0);
  }
}

class V11ActiveChallengeState {
  final String challengeId;
  final String uid;
  final V11ChallengeAction action;
  final String nonce;
  final String signature;
  final int expiresAtMs;
  double observedMagnitude = 0.0;
  bool isCompleted = false;

  V11ActiveChallengeState({
    required this.challengeId,
    required this.uid,
    required this.action,
    required this.nonce,
    required this.signature,
    required this.expiresAtMs,
  });

  bool get isExpired => DateTime.now().millisecondsSinceEpoch > expiresAtMs;
}

/// Real-time capture controller for Phase 11 3-frame centroid fusion,
/// pre-inference FIQA gating, and active step-up challenges.
class BiometricV11CaptureController extends ChangeNotifier {
  static const int requiredFrames = 3;

  V11CaptureState _state = V11CaptureState.idle;
  String _guidanceMessage = "Position your face in the oval";
  final List<V11FrameQualitySample> _capturedFrames = [];
  V11ActiveChallengeState? _activeChallenge;
  Timer? _challengeCountdownTimer;
  int _challengeSecondsRemaining = 60;

  V11CaptureState get state => _state;
  String get guidanceMessage => _guidanceMessage;
  List<V11FrameQualitySample> get capturedFrames => List.unmodifiable(_capturedFrames);
  int get frameCount => _capturedFrames.length;
  V11ActiveChallengeState? get activeChallenge => _activeChallenge;
  int get challengeSecondsRemaining => _challengeSecondsRemaining;

  void startSession() {
    _capturedFrames.clear();
    _activeChallenge = null;
    _state = V11CaptureState.guiding;
    _guidanceMessage = "Align your face inside the guide";
    notifyListeners();
  }

  /// Ingests a camera frame evaluation sample.
  void ingestFrameSample(V11FrameQualitySample sample) {
    if (_state == V11CaptureState.stepUpRequired) {
      _processChallengeFrame(sample);
      return;
    }

    if (_state != V11CaptureState.guiding && _state != V11CaptureState.capturing) {
      return;
    }

    // 1. Evaluate FIQA criteria
    if (!sample.isSharp) {
      _guidanceMessage = "Hold steady — image is blurry";
      notifyListeners();
      return;
    }

    if (sample.meanLuminance < 40.0) {
      _guidanceMessage = "Move to a brighter area";
      notifyListeners();
      return;
    }

    if (sample.meanLuminance > 220.0 || sample.hemifaceDelta > 65.0) {
      _guidanceMessage = "Avoid strong direct sun or glare";
      notifyListeners();
      return;
    }

    if (!sample.isPoseCentered) {
      _guidanceMessage = "Look straight at the camera";
      notifyListeners();
      return;
    }

    if (!sample.areEyesOpen) {
      _guidanceMessage = "Please keep your eyes open";
      notifyListeners();
      return;
    }

    // 2. High quality frame acquired
    _state = V11CaptureState.capturing;
    _capturedFrames.add(sample);
    _guidanceMessage = "Hold still! Frame ${_capturedFrames.length} of $requiredFrames";
    notifyListeners();

    if (_capturedFrames.length >= requiredFrames) {
      _state = V11CaptureState.completed;
      _guidanceMessage = "Capture complete! Verifying biometric identity...";
      notifyListeners();
    }
  }

  /// Transitions into Grey-Zone Step-Up Active Challenge.
  void triggerStepUpChallenge({
    required String challengeId,
    required String uid,
    required V11ChallengeAction action,
    required String nonce,
    required String signature,
    required int expiresAtMs,
  }) {
    _activeChallenge = V11ActiveChallengeState(
      challengeId: challengeId,
      uid: uid,
      action: action,
      nonce: nonce,
      signature: signature,
      expiresAtMs: expiresAtMs,
    );

    _state = V11CaptureState.stepUpRequired;
    _challengeSecondsRemaining = 60;
    _guidanceMessage = _getChallengeInstruction(action);

    _challengeCountdownTimer?.cancel();
    _challengeCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_challengeSecondsRemaining > 0) {
        _challengeSecondsRemaining--;
        notifyListeners();
      } else {
        timer.cancel();
        _state = V11CaptureState.rejected;
        _guidanceMessage = "Challenge timed out. Please try again.";
        notifyListeners();
      }
    });

    notifyListeners();
  }

  void _processChallengeFrame(V11FrameQualitySample sample) {
    if (_activeChallenge == null || _activeChallenge!.isExpired) return;

    switch (_activeChallenge!.action) {
      case V11ChallengeAction.blink:
        // Eye closure ratio drops below 0.15
        if (sample.eyeOpenRatio < 0.15) {
          _activeChallenge!.observedMagnitude = 1.0 - sample.eyeOpenRatio;
          _completeChallenge();
        }
        break;
      case V11ChallengeAction.turnLeft:
        if (sample.yawDeg < -12.0) {
          _activeChallenge!.observedMagnitude = sample.yawDeg.abs();
          _completeChallenge();
        }
        break;
      case V11ChallengeAction.turnRight:
        if (sample.yawDeg > 12.0) {
          _activeChallenge!.observedMagnitude = sample.yawDeg;
          _completeChallenge();
        }
        break;
      case V11ChallengeAction.nod:
        if (sample.pitchDeg > 12.0) {
          _activeChallenge!.observedMagnitude = sample.pitchDeg;
          _completeChallenge();
        }
        break;
    }
  }

  void _completeChallenge() {
    _activeChallenge?.isCompleted = true;
    _challengeCountdownTimer?.cancel();
    _state = V11CaptureState.completed;
    _guidanceMessage = "Liveness confirmed! Processing enrollment...";
    notifyListeners();
  }

  String _getChallengeInstruction(V11ChallengeAction action) {
    switch (action) {
      case V11ChallengeAction.blink:
        return "Slowly blink your eyes now";
      case V11ChallengeAction.turnLeft:
        return "Gently turn your head to the left";
      case V11ChallengeAction.turnRight:
        return "Gently turn your head to the right";
      case V11ChallengeAction.nod:
        return "Slowly nod your head down";
    }
  }

  /// Converts captured burst into API payload.
  List<Map<String, dynamic>> buildBurstPayload() {
    return _capturedFrames.map((f) => {
      'embedding': f.embedding,
      'qualityScore': f.computedScore,
    }).toList();
  }

  @override
  void dispose() {
    _challengeCountdownTimer?.cancel();
    super.dispose();
  }
}
