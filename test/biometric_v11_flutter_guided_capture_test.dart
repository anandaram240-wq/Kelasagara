// FILE: test/biometric_v11_flutter_guided_capture_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelasagaara/biometrics/biometric_v11_capture_controller.dart';
import 'package:kelasagaara/widgets/biometric_v11_liveness_scanner.dart';

void main() {
  group('BiometricV11CaptureController Tests', () {
    late BiometricV11CaptureController controller;

    setUp(() {
      controller = BiometricV11CaptureController();
    });

    tearDown(() {
      controller.dispose();
    });

    test('Initial state is idle and starts session cleanly', () {
      expect(controller.state, V11CaptureState.idle);
      controller.startSession();
      expect(controller.state, V11CaptureState.guiding);
      expect(controller.frameCount, 0);
    });

    test('Rejects blurry frame without advancing frame counter', () {
      controller.startSession();
      controller.ingestFrameSample(
        const V11FrameQualitySample(
          sharpnessVariance: 8.0, // Blurry (< 15.0)
          meanLuminance: 120.0,
          hemifaceDelta: 10.0,
          yawDeg: 0.0,
          pitchDeg: 0.0,
          rollDeg: 0.0,
          eyeOpenRatio: 0.8,
          embedding: [0.1, 0.2, 0.3],
        ),
      );

      expect(controller.frameCount, 0);
      expect(controller.guidanceMessage, contains('blurry'));
      expect(controller.state, V11CaptureState.guiding);
    });

    test('Rejects underexposed lighting and extreme pose', () {
      controller.startSession();

      // Underexposed
      controller.ingestFrameSample(
        const V11FrameQualitySample(
          sharpnessVariance: 40.0,
          meanLuminance: 20.0, // Too dark (< 40)
          hemifaceDelta: 10.0,
          yawDeg: 0.0,
          pitchDeg: 0.0,
          rollDeg: 0.0,
          eyeOpenRatio: 0.8,
          embedding: [0.1, 0.2, 0.3],
        ),
      );
      expect(controller.guidanceMessage, contains('brighter area'));

      // Extreme yaw
      controller.ingestFrameSample(
        const V11FrameQualitySample(
          sharpnessVariance: 40.0,
          meanLuminance: 120.0,
          hemifaceDelta: 10.0,
          yawDeg: 25.0, // Face turned right (> 18)
          pitchDeg: 0.0,
          rollDeg: 0.0,
          eyeOpenRatio: 0.8,
          embedding: [0.1, 0.2, 0.3],
        ),
      );
      expect(controller.guidanceMessage, contains('straight at the camera'));
    });

    test('Successfully collects 3-frame burst and completes capture', () {
      controller.startSession();

      const goodSample = V11FrameQualitySample(
        sharpnessVariance: 45.0,
        meanLuminance: 125.0,
        hemifaceDelta: 12.0,
        yawDeg: 2.0,
        pitchDeg: -1.0,
        rollDeg: 0.5,
        eyeOpenRatio: 0.85,
        embedding: [0.12, 0.34, 0.56],
      );

      // Frame 1
      controller.ingestFrameSample(goodSample);
      expect(controller.frameCount, 1);
      expect(controller.state, V11CaptureState.capturing);

      // Frame 2
      controller.ingestFrameSample(goodSample);
      expect(controller.frameCount, 2);

      // Frame 3
      controller.ingestFrameSample(goodSample);
      expect(controller.frameCount, 3);
      expect(controller.state, V11CaptureState.completed);

      // Verify burst payload
      final payload = controller.buildBurstPayload();
      expect(payload.length, 3);
      expect(payload[0]['qualityScore'], greaterThanOrEqualTo(0.75));
    });

    test('Active step-up challenge verifies blink response', () {
      controller.startSession();
      controller.triggerStepUpChallenge(
        challengeId: 'CHAL_TEST_1',
        uid: 'USR_123',
        action: V11ChallengeAction.blink,
        nonce: 'nonce_abc',
        signature: 'sig_xyz',
        expiresAtMs: DateTime.now().millisecondsSinceEpoch + 60000,
      );

      expect(controller.state, V11CaptureState.stepUpRequired);
      expect(controller.guidanceMessage, contains('blink'));

      // User blinks: eyeOpenRatio drops to 0.05
      controller.ingestFrameSample(
        const V11FrameQualitySample(
          sharpnessVariance: 45.0,
          meanLuminance: 120.0,
          hemifaceDelta: 10.0,
          yawDeg: 0.0,
          pitchDeg: 0.0,
          rollDeg: 0.0,
          eyeOpenRatio: 0.05, // Closed eyes / blink!
          embedding: [0.1, 0.2],
        ),
      );

      expect(controller.state, V11CaptureState.completed);
      expect(controller.activeChallenge?.isCompleted, isTrue);
      expect(controller.guidanceMessage, contains('Liveness confirmed'));
    });
  });

  group('BiometricV11LivenessScanner Widget Tests', () {
    testWidgets('Renders oval scanner and guidance message', (tester) async {
      final controller = BiometricV11CaptureController();
      controller.startSession();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BiometricV11LivenessScanner(controller: controller),
          ),
        ),
      );

      expect(find.byType(BiometricV11LivenessScanner), findsOneWidget);
      expect(find.text(controller.guidanceMessage), findsOneWidget);

      controller.dispose();
    });

    testWidgets('Renders countdown badge during step-up challenge', (tester) async {
      final controller = BiometricV11CaptureController();
      controller.startSession();
      controller.triggerStepUpChallenge(
        challengeId: 'CHAL_WIDGET_1',
        uid: 'USR_TEST',
        action: V11ChallengeAction.turnLeft,
        nonce: 'nonce_123',
        signature: 'sig_456',
        expiresAtMs: DateTime.now().millisecondsSinceEpoch + 60000,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BiometricV11LivenessScanner(controller: controller),
          ),
        ),
      );

      expect(find.textContaining('60s remaining'), findsOneWidget);
      expect(find.textContaining('turn your head to the left'), findsOneWidget);

      controller.dispose();
    });
  });
}
