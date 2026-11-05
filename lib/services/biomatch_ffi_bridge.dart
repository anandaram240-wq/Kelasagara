import 'dart:io';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../biometrics/biomatch_ffi_bridge.dart' as native;

class BioMatchInferenceResult {
  final Float32List embedding;
  final double laplacianVariance;
  final double qualityNorm;
  final double padLivenessScore;
  final String captureDigestHex;
  final bool isSuccess;

  const BioMatchInferenceResult({
    required this.embedding,
    required this.laplacianVariance,
    this.qualityNorm = 24.5,
    this.padLivenessScore = 1.0,
    this.captureDigestHex = '',
    this.isSuccess = true,
  });
}

class BiomatchNativeBridge {
  static final BiomatchNativeBridge instance = BiomatchNativeBridge._();
  BiomatchNativeBridge._();

  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;
    if (!Platform.isAndroid) return;
    try {
      await native.BiomatchNativeBridge.initializeModel();
      _isInitialized = true;
    } catch (_) {
      // In non-native test environments, continue with client fallback
    }
  }

  Future<BioMatchInferenceResult?> extractFromCameraImageAsync(
    CameraImage image,
    Face detectedFace,
  ) async {
    if (!Platform.isAndroid || image.planes.length < 3) return null;

    final leftEye = detectedFace.landmarks[FaceLandmarkType.leftEye]?.position;
    final rightEye = detectedFace.landmarks[FaceLandmarkType.rightEye]?.position;
    final noseBase = detectedFace.landmarks[FaceLandmarkType.noseBase]?.position;
    final leftMouth = detectedFace.landmarks[FaceLandmarkType.leftMouth]?.position;
    final rightMouth = detectedFace.landmarks[FaceLandmarkType.rightMouth]?.position;

    if (leftEye == null ||
        rightEye == null ||
        noseBase == null ||
        leftMouth == null ||
        rightMouth == null) {
      return null;
    }

    try {
      final payload = native.FrameIsolatePayload(
        yBytes: image.planes[0].bytes,
        yRowStride: image.planes[0].bytesPerRow,
        uBytes: image.planes[1].bytes,
        vBytes: image.planes[2].bytes,
        uvRowStride: image.planes[1].bytesPerRow,
        uvPixelStride: image.planes[1].bytesPerPixel ?? 1,
        width: image.width,
        height: image.height,
        landmarks10: [
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
        ],
      );

      final out = await native.BiomatchNativeBridge.processAndInferAsync(payload);
      return BioMatchInferenceResult(
        embedding: out.embedding,
        laplacianVariance: out.laplacianVariance,
        qualityNorm: out.qualityNorm,
        padLivenessScore: out.padLivenessScore,
        captureDigestHex: out.captureDigestHex,
        isSuccess: out.isSuccess,
      );
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    try {
      native.BiomatchNativeBridge.dispose();
    } catch (_) {}
  }
}
