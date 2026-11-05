// test/face_enrollment_burst_stream_test.dart
//
// KELASAGARA BIOMATCH V19.5.1
// Isolated Test Harness Maintenance: ISO 30107-3 Ocular Kinematic PAD & Burst Collection
// Standards: ISO/IEC 30107-3:2023, ISO/IEC 29794-5:2025

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:kelasagaara/biometrics/burst_collector.dart';
import 'package:kelasagaara/biometrics/iso30107_pad_controller.dart';

/// Helper to build a test Face object with specific ocular probabilities and nose position.
Face _createTestFace({
  required double leftEyeOpen,
  required double rightEyeOpen,
  math.Point<int> nosePosition = const math.Point<int>(200, 200),
}) {
  return Face(
    boundingBox: const Rect.fromLTWH(50, 50, 300, 300),
    landmarks: {
      FaceLandmarkType.noseBase: FaceLandmark(
        type: FaceLandmarkType.noseBase,
        position: nosePosition,
      ),
      FaceLandmarkType.leftEye: FaceLandmark(
        type: FaceLandmarkType.leftEye,
        position: const math.Point<int>(150, 150),
      ),
      FaceLandmarkType.rightEye: FaceLandmark(
        type: FaceLandmarkType.rightEye,
        position: const math.Point<int>(250, 150),
      ),
    },
    contours: const {},
    leftEyeOpenProbability: leftEyeOpen,
    rightEyeOpenProbability: rightEyeOpen,
  );
}

void main() {
  group('PadKinematicState: ISO 30107-3 Eyelid Kinematic State Machine', () {
    late PadKinematicState pad;

    setUp(() {
      pad = PadKinematicState();
    });

    test('verifies bona fide blink with 5 open frames, 2 closed apex frames, and re-opening', () {
      final baseTime = DateTime(2026, 10, 24, 12, 0, 0);

      // 1. Establish open eyes baseline (>= 5 frames with avgEyeOpen >= 0.58)
      for (int i = 0; i < 5; i++) {
        final openFace = _createTestFace(leftEyeOpen: 0.90, rightEyeOpen: 0.90);
        final verified = pad.processFrame(openFace, baseTime.add(Duration(milliseconds: i * 33)));
        expect(verified, isFalse, reason: 'Must not verify before blink closure');
      }
      expect(pad.consecutiveOpenFrames, equals(5));

      // 2. Closed apex frame 1 (t = 165ms, avgEyeOpen <= 0.28)
      final closedFace1 = _createTestFace(leftEyeOpen: 0.12, rightEyeOpen: 0.15);
      final vClosed1 = pad.processFrame(closedFace1, baseTime.add(const Duration(milliseconds: 165)));
      expect(vClosed1, isFalse);
      expect(pad.consecutiveClosedFrames, equals(1));
      expect(pad.blinkClosureStart, isNotNull);

      // Closed apex frame 2 (t = 200ms)
      final closedFace2 = _createTestFace(leftEyeOpen: 0.10, rightEyeOpen: 0.08);
      final vClosed2 = pad.processFrame(closedFace2, baseTime.add(const Duration(milliseconds: 200)));
      expect(vClosed2, isFalse);
      expect(pad.consecutiveClosedFrames, equals(2));

      // 3. Eyes re-open at t = 345ms (duration = 180ms within [80ms, 500ms] window)
      final reopenFace = _createTestFace(leftEyeOpen: 0.88, rightEyeOpen: 0.85);
      final verified = pad.processFrame(reopenFace, baseTime.add(const Duration(milliseconds: 345)));

      expect(verified, isTrue, reason: 'Valid bona fide kinematic blink must be verified');
      expect(pad.kineticBlinkVerified, isTrue);
      expect(pad.lastBlinkDurationMs, equals(180));
    });

    test('rejects blink when eyes stay closed longer than 500ms (deliberate sleep/hold spoof)', () {
      final baseTime = DateTime(2026, 10, 24, 12, 0, 0);

      // Open baseline
      for (int i = 0; i < 5; i++) {
        pad.processFrame(
          _createTestFace(leftEyeOpen: 0.85, rightEyeOpen: 0.85),
          baseTime.add(Duration(milliseconds: i * 33)),
        );
      }

      // Closure at t = 165ms
      pad.processFrame(
        _createTestFace(leftEyeOpen: 0.15, rightEyeOpen: 0.15),
        baseTime.add(const Duration(milliseconds: 165)),
      );
      pad.processFrame(
        _createTestFace(leftEyeOpen: 0.10, rightEyeOpen: 0.10),
        baseTime.add(const Duration(milliseconds: 200)),
      );

      // Re-opening too late at t = 800ms (duration = 635ms > 500ms limit)
      final verified = pad.processFrame(
        _createTestFace(leftEyeOpen: 0.85, rightEyeOpen: 0.85),
        baseTime.add(const Duration(milliseconds: 800)),
      );

      expect(verified, isFalse, reason: 'Excessive blink duration (>500ms) must fail and reset');
      expect(pad.kineticBlinkVerified, isFalse);
      expect(pad.consecutiveOpenFrames, equals(0)); // Reset state
    });

    test('rejects blink when head moves > 12px during blink (photo-tilting presentation attack)', () {
      final baseTime = DateTime(2026, 10, 24, 12, 0, 0);

      // Open baseline at nose (200, 200)
      for (int i = 0; i < 5; i++) {
        pad.processFrame(
          _createTestFace(leftEyeOpen: 0.85, rightEyeOpen: 0.85, nosePosition: const math.Point(200, 200)),
          baseTime.add(Duration(milliseconds: i * 33)),
        );
      }

      // Closure at t = 165ms
      pad.processFrame(
        _createTestFace(leftEyeOpen: 0.15, rightEyeOpen: 0.15, nosePosition: const math.Point(200, 200)),
        baseTime.add(const Duration(milliseconds: 165)),
      );
      pad.processFrame(
        _createTestFace(leftEyeOpen: 0.10, rightEyeOpen: 0.10, nosePosition: const math.Point(200, 200)),
        baseTime.add(const Duration(milliseconds: 200)),
      );

      // Re-opening with significant nose shift (220, 200) -> distance = 20px (> 12px limit)
      final verified = pad.processFrame(
        _createTestFace(leftEyeOpen: 0.85, rightEyeOpen: 0.85, nosePosition: const math.Point(220, 200)),
        baseTime.add(const Duration(milliseconds: 320)),
      );

      expect(verified, isFalse, reason: 'Nose shift > 12px during blink indicates head jerk or photo tilt');
      expect(pad.kineticBlinkVerified, isFalse);
    });

    test('validates 2D Laplacian texture variance bounds per ISO 29794-5', () {
      // Too blurry (< 35) -> reject
      expect(PadKinematicState.isTextureBonaFide(15.0), isFalse);
      // Valid sharp face -> accept
      expect(PadKinematicState.isTextureBonaFide(150.0), isTrue);
      // High-contrast live edge -> accept
      expect(PadKinematicState.isTextureBonaFide(850.0), isTrue);
      // Screen moiré / extreme noise (> 2800) -> reject
      expect(PadKinematicState.isTextureBonaFide(3200.0), isFalse);
    });
  });

  group('BurstCollector: Multi-Frame Temporal Capture Logic', () {
    test('collects K frames respecting minGapMs and scores best frontal frame', () {
      final collector = BurstCollector(k: 3, minGapMs: 100, timeoutMs: 2000, startMs: 0);
      final dummyRgb = Uint8List(112 * 112 * 3);

      expect(collector.isComplete, isFalse);

      // t = 0ms: Frame 1
      expect(collector.wantsFrame(0, gatePassed: true), isTrue);
      collector.add(BurstFrame(cropRgb112: dummyRgb, score: 80.0, takenAtMs: 0));

      // t = 50ms (< 100ms gap): Must reject
      expect(collector.wantsFrame(50, gatePassed: true), isFalse);

      // t = 110ms (>= 100ms gap): Frame 2 (higher score = 95.0)
      expect(collector.wantsFrame(110, gatePassed: true), isTrue);
      collector.add(BurstFrame(cropRgb112: dummyRgb, score: 95.0, takenAtMs: 110));

      // t = 220ms: Frame 3
      expect(collector.wantsFrame(220, gatePassed: true), isTrue);
      collector.add(BurstFrame(cropRgb112: dummyRgb, score: 85.0, takenAtMs: 220));

      expect(collector.isComplete, isTrue);
      expect(collector.frames.length, equals(3));
      expect(collector.best.score, equals(95.0), reason: 'Best frame must have highest frontal score');

      // Once complete, wantsFrame must return false
      expect(collector.wantsFrame(350, gatePassed: true), isFalse);
    });

    test('scores frontal frames higher than off-axis yaw/pitch frames', () {
      final frontalScore = BurstCollector.scoreFrame(sharpness: 100.0, yawDeg: 0.0, pitchDeg: 0.0);
      final offAxisScore = BurstCollector.scoreFrame(sharpness: 100.0, yawDeg: 15.0, pitchDeg: 10.0);

      expect(frontalScore, equals(100.0));
      expect(offAxisScore, lessThan(frontalScore));
    });
  });
}
