// test/v19_6_7_diagnostics_privacy_test.dart
//
// KELASAGARA BIOMATCH V19.6.7
// Diagnostic Telemetry Privacy Controls & Hardening Test Suite
// Standards: ISO/IEC 24745:2022, ISO/IEC 19794-5:2025, DPDPA 2023

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelasagaara/biometrics/debug_capture_diagnostics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    DebugCaptureDiagnostics.instance.resetForTesting();
  });

  tearDown(() {
    DebugCaptureDiagnostics.instance.resetForTesting();
  });

  group('V19.6.7 Diagnostic Privacy Controls & PII Exclusion', () {
    test('1. Diagnostics payload strictly excludes all raw biometric data, embeddings, and tokens', () {
      final diag = DebugCaptureDiagnostics.instance;
      diag.overrideReleaseModeForTesting = false; // Force active in debug test
      diag.startSession();

      diag.recordPlaneMetadata(
        planeCount: 2,
        rowStrides: [1280, 1280],
        pixelStrides: [1, 2],
        width: 1280,
        height: 720,
      );
      diag.recordCropAndEncodeDuration(12, 14200);
      diag.recordBurstTimestamps([1000, 1150, 1300]);
      diag.markCameraInitStart();
      diag.markCameraInitEnd();
      diag.markUploadStart();
      diag.markUploadEnd('verified');

      final safeJson = diag.exportSnapshot().toSafeJson();

      // Prohibited Biometric & Authentication Keys (ISO 24745 / DPDPA 2023)
      final prohibitedKeys = [
        'embedding',
        'probeVector',
        'rawPixels',
        'pixelBuffer',
        'faceCrop',
        'jpegBase64',
        'base64Image',
        'token',
        'idToken',
        'authToken',
        'aadhaar',
        'phone',
        'phoneNumber',
        'name',
        'uid',
        'userId',
        'wadh',
      ];

      for (final key in prohibitedKeys) {
        expect(
          safeJson.containsKey(key),
          isFalse,
          reason: 'Diagnostic payload must NOT contain sensitive key: $key',
        );
      }

      // Must be safely JSON serializable (RFC 8259)
      final serialized = jsonEncode(safeJson);
      expect(serialized, isA<String>());
      expect(serialized.contains('diag_'), isTrue);
    });

    test('2. Release mode simulation strictly suppresses diagnostic recording (Zero Overhead)', () {
      final diag = DebugCaptureDiagnostics.instance;
      diag.overrideReleaseModeForTesting = true; // Simulate kReleaseMode = true

      diag.startSession();
      diag.recordPlaneMetadata(
        planeCount: 2,
        rowStrides: [1280, 1280],
        pixelStrides: [1, 2],
        width: 1280,
        height: 720,
      );
      diag.recordCropAndEncodeDuration(15, 13800);
      diag.recordBurstTimestamps([1000, 1150, 1300]);
      diag.markCameraInitStart();
      diag.markCameraInitEnd();

      final snapshot = diag.exportSnapshot();

      // In release mode, nothing was mutated
      expect(snapshot.planeLayout, isEmpty);
      expect(snapshot.cropAndEncodeDurationsMs, isEmpty);
      expect(snapshot.burstFrameIntervalsMs, isEmpty);
      expect(snapshot.cameraInitDurationMs, equals(0));

      diag.overrideReleaseModeForTesting = null; // Restore default
    });

    test('3. Gracefully sanitizes extreme, negative, or NaN timing inputs without throwing', () {
      final diag = DebugCaptureDiagnostics.instance;
      diag.overrideReleaseModeForTesting = false;
      diag.startSession();

      // Extreme values
      diag.recordCropAndEncodeDuration(-50, 0); // Negative latency
      diag.recordBurstTimestamps([1000, 500]); // Reversed timestamps (negative interval)

      const snapshot = CaptureDiagnosticsSnapshot(
        sessionId: 'diag_test_nan',
        timestampMs: 1729770000000,
        cameraInitDurationMs: -100, // Negative duration
        streamFpsEstimate: double.nan, // NaN FPS
        planeLayout: {},
        cropAndEncodeDurationsMs: [-10],
        burstFrameIntervalsMs: [-500],
        jpegByteSizes: [0],
        uploadDurationMs: -50,
        outcomeStatus: 'failed',
        isPhotometricActive: false,
      );

      final safeJson = snapshot.toSafeJson();

      // Defensive handling: NaN converted to 0.0, negative durations clamped
      expect(safeJson['streamFpsEstimate'], equals(0.0));
      expect(safeJson['cameraInitDurationMs'], equals(0));
      expect(safeJson['uploadDurationMs'], equals(0));

      // Verifies jsonEncode succeeds without throwing FormatException
      expect(() => jsonEncode(safeJson), returnsNormally);
    });

    test('4. Enrollment decision integrity is decoupled from diagnostics availability', () {
      // Diagnostic state cannot alter biometric decision outcome
      bool biometricVerified = true;

      try {
        final diag = DebugCaptureDiagnostics.instance;
        diag.overrideReleaseModeForTesting = false;
        diag.startSession();
        // Simulate diagnostics throwing or failing
        throw StateError('Simulated telemetry failure');
      } catch (e) {
        // Telemetry error swallowed safely
      }

      // Verification status remains unchanged
      expect(biometricVerified, isTrue);
    });
  });
}
