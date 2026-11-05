// KELASAGARA BIOMETRIC ENGINE V12.0 — PHASE 12.4 FLUTTER TEST SUITE
// File: test/biometric_v12_edge_isolate_test.dart

import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelasagaara/biometrics/biometric_v12_edge_isolate.dart';

void main() {
  group('KELASAGARA V12 PHASE 12.4 EDGE ISOLATE PRE-WARPING SUITE', () {
    // Helper to generate synthetic YUV420 frame (e.g. 640x480)
    Yuv420FramePayloadV12 createSyntheticYuvFrame({
      int width = 320,
      int height = 240,
      required List<List<double>> landmarks,
    }) {
      final yPlane = Uint8List(width * height);
      // Fill Y plane with a gradient to test luminance and Laplacian variance
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          yPlane[y * width + x] = ((x * 255) ~/ width).clamp(0, 255);
        }
      }

      final uvSize = (width ~/ 2) * (height ~/ 2);
      final uPlane = Uint8List(uvSize)..fillRange(0, uvSize, 128); // neutral chroma
      final vPlane = Uint8List(uvSize)..fillRange(0, uvSize, 128);

      return Yuv420FramePayloadV12(
        yPlane: yPlane,
        uPlane: uPlane,
        vPlane: vPlane,
        width: width,
        height: height,
        yRowStride: width,
        uvRowStride: width ~/ 2,
        uvPixelStride: 1,
        fivePointLandmarks: landmarks,
      );
    }

    final validLandmarks = [
      [110.0, 90.0],  // left eye
      [210.0, 90.0],  // right eye
      [160.0, 130.0], // nose
      [120.0, 175.0], // left mouth
      [200.0, 175.0], // right mouth
    ];

    test('FLUTTER-V12-01: Synchronous 3-frame burst pre-warping yields exact 112x112 RGB patches', () {
      final burst = [
        createSyntheticYuvFrame(landmarks: validLandmarks),
        createSyntheticYuvFrame(landmarks: validLandmarks),
        createSyntheticYuvFrame(landmarks: validLandmarks),
      ];

      final result = BiometricV12EdgeIsolateWarper.warpBurstSynchronously(burst);

      expect(result.patches.length, 3);
      for (int i = 0; i < 3; i++) {
        final patch = result.patches[i];
        expect(patch.frameIndex, i);
        // Canonical 112x112 RGB = 112 * 112 * 3 = 37,632 bytes
        expect(patch.rgb112Bytes.length, 37632);
        expect(patch.luminanceMean, greaterThan(0));
        expect(patch.sharpnessLaplacian, greaterThanOrEqualTo(0));
        expect(patch.hemifaceDelta, greaterThanOrEqualTo(0));

        final wireJson = patch.toCompactWireJson();
        expect(wireJson['frameIndex'], i);
        expect(wireJson['patch112Base64'], isA<String>());
        expect(wireJson['patch112Base64'].toString().isNotEmpty, true);
      }

      // Raw source bytes for 320x240 RGB = 320 * 240 * 3 * 3 = 691,200 bytes
      expect(result.rawUncompressedBytes, 320 * 240 * 3 * 3);
      // Wire payload bytes = 3 * 37,632 = 112,896 bytes
      expect(result.wirePayloadBytes, 112896);
      expect(result.compressionRatio, greaterThan(5.0)); // > 5x reduction
    });

    test('FLUTTER-V12-02: Background Isolate pre-warping executes asynchronously without blocking UI', () async {
      final burst = [
        createSyntheticYuvFrame(landmarks: validLandmarks),
        createSyntheticYuvFrame(landmarks: validLandmarks),
      ];

      final result = await BiometricV12EdgeIsolateWarper.warpBurstInBackgroundIsolate(burst);

      expect(result.patches.length, 2);
      expect(result.patches[0].rgb112Bytes.length, 37632);
      expect(result.patches[1].rgb112Bytes.length, 37632);
    });

    test('FLUTTER-V12-03: Throws ArgumentError on empty burst or invalid landmarks', () {
      expect(
        () => BiometricV12EdgeIsolateWarper.warpBurstSynchronously([]),
        throwsA(isA<ArgumentError>()),
      );

      final invalidFrame = createSyntheticYuvFrame(
        landmarks: [
          [100.0, 100.0], // only 1 landmark
        ],
      );

      expect(
        () => BiometricV12EdgeIsolateWarper.warpBurstSynchronously([invalidFrame]),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
