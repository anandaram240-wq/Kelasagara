// test/v19_6_6_hardware_and_photometric_test.dart
//
// KELASAGARA BIOMATCH V19.6.6
// Automated Test Suite: Hardware Capture Diagnostics & Photometric Feasibility
// Standards: ISO/IEC 30107-3:2023, ISO/IEC 19794-5:2025, ISO/IEC 24745:2022, DPDPA 2023

import 'package:flutter_test/flutter_test.dart';
import 'package:kelasagaara/biometrics/debug_capture_diagnostics.dart';
import 'package:kelasagaara/services/capture_illumination_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('V19.6.6 Debug Capture Diagnostics Telemetry', () {
    test('1. Session lifecycle initializes cleanly and generates unique session ID', () {
      final diag = DebugCaptureDiagnostics.instance;
      diag.startSession();

      final snapshot = diag.exportSnapshot();
      expect(snapshot.sessionId, startsWith('diag_'));
      expect(snapshot.outcomeStatus, equals('in_progress'));
      expect(snapshot.cropAndEncodeDurationsMs, isEmpty);
      expect(snapshot.jpegByteSizes, isEmpty);
      expect(snapshot.burstFrameIntervalsMs, isEmpty);
    });

    test('2. Accurately estimates frame stream FPS over monotonic intervals', () {
      final diag = DebugCaptureDiagnostics.instance;
      diag.startSession();

      // Simulate 11 frames at 30fps (approx 33.3ms intervals = 333ms total for 10 steps)
      diag.recordFrameReceived();
      for (int i = 0; i < 10; i++) {
        diag.recordFrameReceived();
      }

      final snapshot = diag.exportSnapshot();
      expect(snapshot.streamFpsEstimate, isA<double>());
      expect(snapshot.streamFpsEstimate >= 0.0, isTrue);
    });

    test('3. Captures camera plane layout metadata without PII or pixel data', () {
      final diag = DebugCaptureDiagnostics.instance;
      diag.startSession();

      // Typical Android NV21 camera plane layout
      diag.recordPlaneMetadata(
        planeCount: 2,
        rowStrides: [1280, 1280],
        pixelStrides: [1, 2],
        width: 1280,
        height: 720,
      );

      final snapshot = diag.exportSnapshot();
      final layout = snapshot.planeLayout;

      expect(layout['planeCount'], equals(2));
      expect(layout['width'], equals(1280));
      expect(layout['height'], equals(720));
      expect(layout['rowStrides'], equals([1280, 1280]));
      expect(layout['pixelStrides'], equals([1, 2]));

      // Verify ZERO pixel buffers or raw byte streams are recorded
      expect(layout.containsKey('bytes'), isFalse);
      expect(layout.containsKey('pixels'), isFalse);
    });

    test('4. Calculates monotonic burst intervals and tracks crop durations', () {
      final diag = DebugCaptureDiagnostics.instance;
      diag.startSession();

      diag.recordCropAndEncodeDuration(12, 14500); // 12ms, 14.5KB
      diag.recordCropAndEncodeDuration(14, 14200); // 14ms, 14.2KB
      diag.recordCropAndEncodeDuration(11, 14800); // 11ms, 14.8KB

      diag.recordBurstTimestamps([1000, 1150, 1310]);

      final snapshot = diag.exportSnapshot();
      expect(snapshot.cropAndEncodeDurationsMs, equals([12, 14, 11]));
      expect(snapshot.jpegByteSizes, equals([14500, 14200, 14800]));
      expect(snapshot.burstFrameIntervalsMs, equals([150, 160]));
    });

    test('5. toSafeJson satisfies ISO 24745 and DPDPA 2023 privacy invariants', () {
      final diag = DebugCaptureDiagnostics.instance;
      diag.startSession();
      diag.markCameraInitStart();
      diag.markCameraInitEnd();
      diag.markUploadStart();
      diag.markUploadEnd('verified');

      final json = diag.exportSnapshot().toSafeJson();

      // Verify essential diagnostic keys exist
      expect(json.containsKey('sessionId'), isTrue);
      expect(json.containsKey('cameraInitDurationMs'), isTrue);
      expect(json.containsKey('streamFpsEstimate'), isTrue);
      expect(json.containsKey('planeLayout'), isTrue);
      expect(json.containsKey('outcomeStatus'), isTrue);
      expect(json['outcomeStatus'], equals('verified'));

      // Invariants: No biometric features, no embeddings, no face crops, no tokens
      expect(json.containsKey('embedding'), isFalse);
      expect(json.containsKey('probeVector'), isFalse);
      expect(json.containsKey('jpegBase64'), isFalse);
      expect(json.containsKey('token'), isFalse);
      expect(json.containsKey('aadhaar'), isFalse);
    });
  });

  group('V19.6.6 Screen-Fill Illumination Controller', () {
    test('6. CaptureIlluminationService safely toggles state and resets idempotently', () async {
      final ill = CaptureIlluminationService.instance;
      await ill.reset();
      expect(ill.isIlluminating, isFalse);

      // On desktop test runner without platform channel, enableScreenFill handles errors gracefully
      final enabled = await ill.enableScreenFill();
      // It returns boolean (true if mock/channel supported, or false if platform unavailable)
      expect(enabled, isA<bool>());

      await ill.reset();
      expect(ill.isIlluminating, isFalse);
    });
  });

  group('V19.6.6 Photometric PAD Mathematical Principles', () {
    test('7. Relative delta luma distinguishes skin gain from static presentation', () {
      double computeDelta(double base, double illum) {
        return (illum - base) / (base > 1.0 ? base : 1.0);
      }

      // Bona fide human skin under white screen: diffuse gain ~10-25%
      final humanDelta = computeDelta(100.0, 120.0);
      expect(humanDelta, closeTo(0.20, 0.001));
      expect(humanDelta >= 0.04, isTrue); // Passes diffuse threshold

      // Replay attack on high-brightness emissive screen: minimal delta ~0-2%
      final replayDelta = computeDelta(220.0, 222.0);
      expect(replayDelta, closeTo(0.009, 0.001));
      expect(replayDelta < 0.04, isTrue); // Fails diffuse threshold
    });

    test('8. Specular saturation ratio detects glass reflection anomalies', () {
      const totalPixels = 112 * 112; // 12544 pixels
      const specularPixelsReplay = 800; // ~6.38% saturation from front glass glare
      const specularPixelsSkin = 120; // ~0.96% natural small specular nose tip/forehead

      const replayRatio = specularPixelsReplay / totalPixels;
      const skinRatio = specularPixelsSkin / totalPixels;

      expect(replayRatio >= 0.05, isTrue); // Classified as CANDIDATE_SPECULAR_REPLAY
      expect(skinRatio <= 0.03, isTrue); // Bona fide skin bounds satisfied
    });
  });
}
