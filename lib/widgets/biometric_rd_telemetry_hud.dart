// lib/widgets/biometric_rd_telemetry_hud.dart
import 'package:flutter/material.dart';

class BiometricRdTelemetryData {
  final double laplacianVariance; // ISO/IEC 30107-3 Passive Liveness [40.0, 3800.0]
  final String blinkState;        // OPEN_INIT -> CLOSED_DETECTED -> BLINK_VERIFIED
  final int openFrames;
  final int closedFrames;
  final double svdAlignmentMs;    // C++17 Umeyama 5-point SVD latency
  final double onnxInferenceMs;   // IndicFace128 INT8 QDQ inference latency
  final double vectorL2Norm;      // Must equal 1.0000 on S^127 hypersphere
  final double maxCosineScore;    // 1:N Gallery highest similarity score
  final String wadhDigestPrefix;  // SHA-256("2.5FYYNN") hex prefix
  final String frameDigestPrefix; // Embedded FIPS 180-4 SHA-256 frame hash
  final List<double> embeddingPreview; // First 6 dimensions of 128-D vector

  const BiometricRdTelemetryData({
    required this.laplacianVariance,
    required this.blinkState,
    required this.openFrames,
    required this.closedFrames,
    required this.svdAlignmentMs,
    required this.onnxInferenceMs,
    required this.vectorL2Norm,
    required this.maxCosineScore,
    required this.wadhDigestPrefix,
    required this.frameDigestPrefix,
    required this.embeddingPreview,
  });
}

class BiometricRdTelemetryHud extends StatelessWidget {
  final BiometricRdTelemetryData data;
  final VoidCallback onTriggerRdIntentDemo;

  const BiometricRdTelemetryHud({
    super.key,
    required this.data,
    required this.onTriggerRdIntentDemo,
  });

  @override
  Widget build(BuildContext context) {
    final bool padPass =
        data.laplacianVariance >= 40.0 && data.laplacianVariance <= 3800.0;
    final bool isDuplicate = data.maxCosineScore >= 0.74;
    final bool isAmbiguous =
        data.maxCosineScore >= 0.65 && data.maxCosineScore < 0.74;

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDuplicate ? Colors.redAccent : Colors.greenAccent,
          width: 1.5,
        ),
      ),
      child: DefaultTextStyle(
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 11,
          color: Colors.greenAccent,
          height: 1.35,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '⚡ KELASAGARA BIOMATCH v17 [C++17 FFI + RD L0]',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontSize: 11.5,
                  ),
                ),
                GestureDetector(
                  onTap: onTriggerRdIntentDemo,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.blueAccent.withValues(alpha: 0.3),
                      border: Border.all(color: Colors.lightBlueAccent),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'TEST RD PID XML',
                      style: TextStyle(color: Colors.lightBlueAccent, fontSize: 10),
                    ),
                  ),
                ),
              ],
            ),
            const Divider(color: Colors.white24, height: 10),
            Text(
              '1. C++17 UMEYAMA SVD (112x112) : ${data.svdAlignmentMs.toStringAsFixed(2)} ms | SHA256: ${data.frameDigestPrefix}',
            ),
            Text(
              '2. ISO-30107 PAD LAPLACIAN σ²  : ${data.laplacianVariance.toStringAsFixed(1)} [40..3800] -> ${padPass ? "LIVE SKIN" : "SPOOF/MOIRÉ REJECT"}',
              style: TextStyle(color: padPass ? Colors.greenAccent : Colors.orangeAccent),
            ),
            Text(
              '3. ACTIVE EAR BLINK FSM        : ${data.blinkState} (O:${data.openFrames}/8, C:${data.closedFrames}/2)',
            ),
            Text(
              '4. INDICFACE-128 QAT INFERENCE : ${data.onnxInferenceMs.toStringAsFixed(2)} ms | ||v||₂ = ${data.vectorL2Norm.toStringAsFixed(4)}',
            ),
            Text(
              '5. S¹²⁷ EMBEDDING [0..5]       : [${data.embeddingPreview.map((e) => e.toStringAsFixed(3)).join(", ")}...]',
              style: const TextStyle(color: Colors.white70),
            ),
            Text(
              '6. 1:N GALLERY COSINE θ_max    : ${data.maxCosineScore.toStringAsFixed(4)} -> ${isDuplicate ? "SYBIL BLOCK (>=0.74)" : isAmbiguous ? "RRL-0 MANUAL REVIEW" : "UNIQUE WORKER (<0.65)"}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isDuplicate
                    ? Colors.redAccent
                    : isAmbiguous
                        ? Colors.amberAccent
                        : Colors.greenAccent,
              ),
            ),
            Text(
              '7. UIDAI FaceRD WADH (2.5FYYNN): ${data.wadhDigestPrefix}... | ZeroMemory: ARMED',
              style: const TextStyle(color: Colors.cyanAccent),
            ),
          ],
        ),
      ),
    );
  }
}
