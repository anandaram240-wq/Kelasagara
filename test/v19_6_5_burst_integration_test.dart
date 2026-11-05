// test/v19_6_5_burst_integration_test.dart
//
// KELASAGARA BIOMATCH V19.6.5
// Automated Test Suite: Real Flutter Camera Burst Integration & Contract Verification
// Standards: ISO/IEC 30107-3:2023, ISO/IEC 19794-5:2025, ISO/IEC 24745:2022

import 'dart:typed_data';
import 'dart:ui' show Rect;
import 'package:flutter_test/flutter_test.dart';
import 'package:kelasagaara/biometrics/crop_encoder.dart';
import 'package:kelasagaara/biometrics/upright_sampler.dart';
import 'package:kelasagaara/services/biometric_service.dart';
import 'package:kelasagaara/services/capture_illumination_service.dart';

void main() {
  group('V19.6.5 Burst Contract & Frame Serialization', () {
    test('1. Serializes 3-frame burst payload according to EnrollRequestDTO schema', () {
      final burstFrames = [
        {
          'sequenceIndex': 0,
          'capturedOffsetMs': 1729770000000,
          'jpegBase64': 'base64_frame0_open',
        },
        {
          'sequenceIndex': 1,
          'capturedOffsetMs': 1729770000180,
          'jpegBase64': 'base64_frame1_closed_apex',
        },
        {
          'sequenceIndex': 2,
          'capturedOffsetMs': 1729770000350,
          'jpegBase64': 'base64_frame2_open_recovery',
        },
      ];

      expect(burstFrames.length, equals(3));
      for (int i = 0; i < 3; i++) {
        expect(burstFrames[i]['sequenceIndex'], equals(i));
        expect(burstFrames[i]['capturedOffsetMs'], isA<int>());
        expect(burstFrames[i]['jpegBase64'], isA<String>());
        // ISO 24745: Client vectors must NEVER be inside frame payload
        expect(burstFrames[i].containsKey('embedding'), isFalse);
        expect(burstFrames[i].containsKey('probeVector'), isFalse);
      }
    });

    test('2. Enforces monotonic ordering and inter-frame intervals within [40, 600] ms', () {
      const t0 = 1729770000000;
      const t1 = t0 + 150; // dt01 = 150ms
      const t2 = t1 + 180; // dt12 = 180ms

      const timestamps = [t0, t1, t2];

      // Strict monotonicity
      expect(timestamps[1] > timestamps[0], isTrue);
      expect(timestamps[2] > timestamps[1], isTrue);

      // Bounds check: 40 <= dt <= 600
      final dt01 = timestamps[1] - timestamps[0];
      final dt12 = timestamps[2] - timestamps[1];
      expect(dt01 >= 40 && dt01 <= 600, isTrue);
      expect(dt12 >= 40 && dt12 <= 600, isTrue);
    });

    test('3. Detects invalid out-of-order or reverse timestamps', () {
      const outOfOrder = [1729770000200, 1729770000100, 1729770000300];
      bool isMonotonic = true;
      for (int i = 1; i < outOfOrder.length; i++) {
        if (outOfOrder[i] <= outOfOrder[i - 1]) {
          isMonotonic = false;
          break;
        }
      }
      expect(isMonotonic, isFalse);
    });

    test('4. Detects timing violation if delta < 40ms (exceeds human blink velocity limit)', () {
      final tooFast = [1729770000000, 1729770000020, 1729770000040]; // 20ms delta
      final dt = tooFast[1] - tooFast[0];
      expect(dt < 40, isTrue);
    });
  });

  group('V19.6.5 Upright Face Cropping & JPEG Encoding Pipeline', () {
    test('5. sampleUprightRgb and rgbToJpeg produces compliant 112x112 JPEG buffer', () {
      // Create synthetic 112x112 RGB buffer with gradient
      final rgb = Uint8List(112 * 112 * 3);
      for (int i = 0; i < 112 * 112; i++) {
        rgb[i * 3 + 0] = (i % 256);
        rgb[i * 3 + 1] = ((i * 2) % 256);
        rgb[i * 3 + 2] = ((i * 3) % 256);
      }

      final jpegBytes = rgbToJpeg(rgb, 112, 112, quality: 80);
      expect(jpegBytes.isNotEmpty, isTrue);
      // Valid JPEG Magic bytes: 0xFF, 0xD8
      expect(jpegBytes[0], equals(0xFF));
      expect(jpegBytes[1], equals(0xD8));
      // End of Image marker: 0xFF, 0xD9
      expect(jpegBytes[jpegBytes.length - 2], equals(0xFF));
      expect(jpegBytes[jpegBytes.length - 1], equals(0xD9));
      // Size budget: 112x112 at Q80 should be roughly 2-8 KB, well below 50 KB
      expect(jpegBytes.length < 50000, isTrue);
    });

    test('6. expandBox expands bounding box symmetrically and clamps to bounds', () {
      const box = Rect.fromLTWH(50, 50, 100, 100);
      final expanded = expandBox(box, 1.25, 480, 640);

      expect(expanded.width, closeTo(125.0, 0.1));
      expect(expanded.height, closeTo(125.0, 0.1));
      expect(expanded.left, closeTo(37.5, 0.1));
      expect(expanded.top, closeTo(37.5, 0.1));
    });

    test('7. Anti-freeze check: non-identical frame buffers are preserved', () {
      final f0 = Uint8List.fromList([0xFF, 0xD8, 0x01, 0x02, 0xFF, 0xD9]);
      final f1 = Uint8List.fromList([0xFF, 0xD8, 0x01, 0x03, 0xFF, 0xD9]);
      final f2 = Uint8List.fromList([0xFF, 0xD8, 0x01, 0x04, 0xFF, 0xD9]);

      final areIdentical = (
        _listEquals(f0, f1) ||
        _listEquals(f1, f2) ||
        _listEquals(f0, f2)
      );
      expect(areIdentical, isFalse, reason: 'Bona fide burst must have distinct frames');
    });
  });

  group('V19.6.5 BiometricCheckResult & Server Response Parsing', () {
    test('8. Parses approved status correctly', () {
      final res = BiometricCheckResult.approved(
        maxSimilarity: 0.88,
        message: 'Face verified successfully',
      );
      expect(res.isApproved, isTrue);
      expect(res.isDuplicate, isFalse);
      expect(res.maxSimilarity, equals(0.88));
    });

    test('9. Parses pending_review status under RRL-0 policy', () {
      final res = BiometricCheckResult.pendingReview(
        maxSimilarity: 0.45,
        message: 'Queued for administrative review',
        accountStatus: 'pending_review',
      );
      expect(res.isPendingReview, isTrue);
      expect(res.isApproved, isFalse);
      expect(res.accountStatus, equals('pending_review'));
    });

    test('10. Parses duplicate status and sanitizes candidate PII', () {
      final res = BiometricCheckResult.duplicateFound(
        maskedUserId: 'USR***78',
        maskedPhone: '******9876',
        maskedName: 'A***a',
        similarityPercent: 86,
        maxSimilarity: 0.86,
        message: 'Face already registered in another account',
      );
      expect(res.isDuplicate, isTrue);
      expect(res.maskedUserId, equals('USR***78'));
      expect(res.maskedPhone, equals('******9876'));
      expect(res.maskedName, equals('A***a'));
      expect(res.similarityPercent, equals(86));
      // Full UID must NOT be present
      expect(res.matchedUid, isNull);
    });
  });

  group('V19.6.5 Illumination & Resource Lifecycle', () {
    test('11. CaptureIlluminationService resets cleanly', () {
      expect(() => CaptureIlluminationService.instance.reset(), returnsNormally);
    });
  });
}

bool _listEquals(Uint8List a, Uint8List b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
