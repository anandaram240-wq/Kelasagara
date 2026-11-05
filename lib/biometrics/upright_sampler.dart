import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset, Rect;
import 'landmark_geometry.dart';
import 'raw_frame.dart';

int _clamp(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);

/// Luma sampled over [boxUpright] (in UPRIGHT coordinates) onto an n x n grid.
/// Going through uprightToRaw means left/right and top/bottom in the result
/// are the user's, whatever the sensor rotation is.
Uint8List sampleUprightLuma(RawFrame f, Rect boxUpright, int n) {
  final out = Uint8List(n * n);
  for (var r = 0; r < n; r++) {
    for (var c = 0; c < n; c++) {
      final up = Offset(
        boxUpright.left + (c + 0.5) / n * boxUpright.width,
        boxUpright.top + (r + 0.5) / n * boxUpright.height,
      );
      final raw = uprightToRaw(up, f.rotation, f.width, f.height);
      final x = _clamp(raw.dx.round(), 0, f.width - 1);
      final y = _clamp(raw.dy.round(), 0, f.height - 1);
      out[r * n + c] = f.y[y * f.yRowStride + x];
    }
  }
  return out;
}

/// RGB (HWC, BT.601 full range) sampled over [boxUpright] onto outW x outH.
Uint8List sampleUprightRgb(RawFrame f, Rect boxUpright, int outW, int outH) {
  final out = Uint8List(outW * outH * 3);
  var o = 0;
  for (var r = 0; r < outH; r++) {
    for (var c = 0; c < outW; c++) {
      final up = Offset(
        boxUpright.left + (c + 0.5) / outW * boxUpright.width,
        boxUpright.top + (r + 0.5) / outH * boxUpright.height,
      );
      final raw = uprightToRaw(up, f.rotation, f.width, f.height);
      final x = _clamp(raw.dx.round(), 0, f.width - 1);
      final y = _clamp(raw.dy.round(), 0, f.height - 1);
      final yy = f.y[y * f.yRowStride + x];
      final uvOff = (y ~/ 2) * f.uvRowStride + (x ~/ 2) * f.uvPixelStride;
      final u = f.u[uvOff] - 128;
      final v = f.v[uvOff] - 128;
      out[o++] = _clamp((yy + 1.402 * v).round(), 0, 255);
      out[o++] = _clamp((yy - 0.344136 * u - 0.714136 * v).round(), 0, 255);
      out[o++] = _clamp((yy + 1.772 * u).round(), 0, 255);
    }
  }
  return out;
}

/// Grow a face box about its centre (for OFIQ best frame and challenge frames).
Rect expandBox(Rect b, double factor, double maxW, double maxH) {
  final cx = b.center.dx, cy = b.center.dy;
  final w = b.width * factor, h = b.height * factor;
  final left = math.max(0.0, cx - w / 2), top = math.max(0.0, cy - h / 2);
  final right = math.min(maxW, cx + w / 2), bottom = math.min(maxH, cy + h / 2);
  return Rect.fromLTRB(left, top, right, bottom);
}
