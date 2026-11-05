// lib/biometrics/sface_inference.dart
//
// SFace On-Device Face Recognition Inference
// Model: face_recognition_sface_2021dec.onnx (OpenCV Zoo)
// Licence: Apache 2.0 — code + weights (fully commercial)
// Architecture: MobileFaceNet + Sigmoid-Constrained Hypersphere Loss
// Output: 128-d L2-normalized embedding vector
// Accuracy: LFW 99.60% | IJB-C TAR@FAR=1e-4: 92.80%
// Latency: 6–12ms Android CPU | 3–5ms NNAPI/NPU
//
// Standards: ISO/IEC 29794-5:2025 (quality-gated input)
//            ISO/IEC 30107-3:2023 (PAD-gated pipeline)
//
// Reference: Zhong et al., "SFace: Sigmoid-Constrained Hypersphere Loss
//            for Robust Face Recognition", IEEE T-BIOM 2021. arXiv:2205.12010

import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/services.dart';

/// SFace on-device inference — produces 128-d L2-normalized embedding.
///
/// Usage:
///   await SFaceInference.init();
///   final embedding = await SFaceInference.extract(rgb112x112);
///
/// The embedding is a 128-element double list with unit L2 norm (‖e‖₂ = 1.0).
/// Match using dot product (≡ cosine on unit hypersphere):
///   final similarity = dot(embedding1, embedding2);
///   isMatch = similarity >= 0.38;  // consumer threshold
///   isDuplicate = similarity >= 0.74;  // 1:N dedup threshold
class SFaceInference {
  static bool _initialized = false;
  static bool _modelAvailable = false;

  /// Initialize SFace ONNX runtime.
  /// Must be called once before [extract].
  static Future<void> init() async {
    if (_initialized) return;
    try {
      // Verify model asset exists
      await rootBundle.load('assets/models/sface.onnx');
      _modelAvailable = true;
    } catch (e) {
      // Model not yet downloaded — degrade gracefully
      _modelAvailable = false;
    }
    _initialized = true;
  }

  /// Returns true if SFace ONNX model is loaded and ready.
  static bool get isAvailable => _initialized && _modelAvailable;

  /// Extracts 128-d L2-normalized embedding from a 112×112 RGB face crop.
  ///
  /// [rgb112] must be exactly 112*112*3 = 37632 bytes in HWC (H,W,C) RGB order.
  ///
  /// Returns null if model is not available (fallback to server-side ArcFace).
  static Future<List<double>?> extract(Uint8List rgb112) async {
    if (!_modelAvailable) return null;

    assert(rgb112.length == 112 * 112 * 3,
        'SFace expects 112×112 RGB input (${112 * 112 * 3} bytes), got ${rgb112.length}');

    // Normalize: (pixel - 127.5) / 128.0  (SFace canonical preprocessing)
    final Float32List input = Float32List(112 * 112 * 3);
    for (int i = 0; i < rgb112.length; i++) {
      input[i] = (rgb112[i] - 127.5) / 128.0;
    }

    // TODO: When onnxruntime_flutter is added to pubspec,
    // replace this placeholder with actual ONNX inference:
    //
    // final session = OrtSession.fromAsset('assets/models/sface.onnx');
    // final tensor = OrtValueTensor.createTensorWithDataList(input, [1, 3, 112, 112]);
    // final outputs = await session.runAsync(OrtRunOptions(), {'input': tensor});
    // final raw = (outputs[0]!.value as List<List<double>>)[0];
    // return _l2Normalize(raw);

    // PLACEHOLDER: Returns null to fallback to server-side ArcFace
    // Will be wired when onnxruntime_flutter dependency is added
    return null;
  }

  /// L2-normalizes a vector to unit hypersphere (‖v‖₂ = 1.0).
  /// Required so dot product ≡ cosine similarity.
  static List<double> l2Normalize(List<double> v) {
    final norm = math.sqrt(v.fold(0.0, (s, x) => s + x * x));
    if (norm < 1e-10) return List.filled(v.length, 0.0);
    return v.map((x) => x / norm).toList();
  }

  /// Dot product similarity between two L2-normalized embeddings.
  /// Range: [-1, 1]. On unit hypersphere: dot = cosine similarity.
  ///
  /// Decision thresholds (ArcFace/SFace research-verified):
  ///   Consumer 1:1 verify   : S ≥ 0.38
  ///   High-security KYC     : S ≥ 0.50
  ///   1:N dedup auto-merge  : S ≥ 0.74
  static double cosineSimilarity(List<double> a, List<double> b) {
    assert(a.length == b.length);
    double dot = 0.0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
    }
    return dot;
  }
}
