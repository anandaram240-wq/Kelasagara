import 'dart:typed_data';

/// One accepted frame of the burst.
class BurstFrame {
  BurstFrame({required this.cropRgb112, required this.score, required this.takenAtMs, this.rawCopy});
  final Uint8List cropRgb112; // 112*112*3 from the native aligner
  final double score; // higher = better (sharp and frontal)
  final int takenAtMs;
  Object? rawCopy; // the RawFrame behind the best score so far, for the OFIQ image
}

/// Phase 2.3. Pure logic, no camera: collects K good frames at least
/// [minGapMs] apart within [timeoutMs]. Keeps the gate where it is; if good
/// frames do not arrive in time it just times out and the screen shows guidance.
class BurstCollector {
  BurstCollector({this.k = 5, this.minGapMs = 150, this.timeoutMs = 8000, required int startMs})
      : _startMs = startMs;

  final int k;
  final int minGapMs;
  final int timeoutMs;
  final int _startMs;
  final List<BurstFrame> _frames = [];

  List<BurstFrame> get frames => List.unmodifiable(_frames);
  bool get isComplete => _frames.length >= k;
  bool isTimedOut(int nowMs) => !isComplete && nowMs - _startMs > timeoutMs;

  /// Ask BEFORE doing the expensive align/encode work for a frame.
  bool wantsFrame(int nowMs, {required bool gatePassed}) {
    if (!gatePassed || isComplete || isTimedOut(nowMs)) return false;
    return _frames.isEmpty || nowMs - _frames.last.takenAtMs >= minGapMs;
  }

  void add(BurstFrame f) {
    if (isComplete) return;
    _frames.add(f);
  }

  /// The frame with the best score (used to build the OFIQ best-frame image).
  BurstFrame get best => _frames.reduce((a, b) => a.score >= b.score ? a : b);

  /// Frontal score: sharper is better, off-axis is worse.
  static double scoreFrame({required double sharpness, required double yawDeg, required double pitchDeg}) {
    final off = (yawDeg.abs() + pitchDeg.abs()) / 30.0; // 0 = perfectly frontal, 1 = at the limit
    return sharpness * (1.0 - 0.5 * off.clamp(0.0, 1.0));
  }
}
