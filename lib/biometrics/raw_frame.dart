import 'dart:typed_data';

/// One camera frame exactly as the camera plugin delivers it (sensor
/// orientation, NOT upright), plus the rotation you told ML Kit.
class RawFrame {
  RawFrame({
    required this.y,
    required this.yRowStride,
    required this.u,
    required this.v,
    required this.uvRowStride,
    required this.uvPixelStride,
    required this.width,
    required this.height,
    required this.rotation,
    this.nv21Single = false,
    this.nv21Base,
  });

  final Uint8List y;
  final int yRowStride;
  final Uint8List u;
  final Uint8List v;
  final int uvRowStride;
  final int uvPixelStride;
  final int width; // raw buffer width
  final int height; // raw buffer height
  final int rotation; // clockwise degrees to make it upright: 0/90/180/270

  /// For single-plane NV21 the camera plugin gives one buffer: Y then VU.
  /// [nv21Base] is that whole buffer; [u] and [v] are views into it.
  final bool nv21Single;
  final Uint8List? nv21Base;

  /// Build from the `camera` plugin's planes (Android: nv21 single plane or yuv420 three planes).
  factory RawFrame.fromPlanes({
    required List<Uint8List> planes,
    required List<int> rowStrides,
    required List<int?> pixelStrides,
    required int width,
    required int height,
    required int rotation,
  }) {
    if (planes.length == 1) {
      final all = planes[0];
      final frameSize = rowStrides[0] * height; // Y plane incl. row padding
      return RawFrame(
        y: Uint8List.sublistView(all, 0, frameSize),
        yRowStride: rowStrides[0],
        v: Uint8List.sublistView(all, frameSize),
        u: Uint8List.sublistView(all, frameSize + 1),
        uvRowStride: rowStrides[0],
        uvPixelStride: 2,
        width: width,
        height: height,
        rotation: rotation,
        nv21Single: true,
        nv21Base: all,
      );
    }
    return RawFrame(
      y: planes[0],
      yRowStride: rowStrides[0],
      u: planes[1],
      v: planes[2],
      uvRowStride: rowStrides[1],
      uvPixelStride: pixelStrides[1] ?? 2,
      width: width,
      height: height,
      rotation: rotation,
    );
  }

  /// Deep copy, so the frame survives after the camera recycles its buffers.
  RawFrame copy() {
    if (nv21Single && nv21Base != null) {
      final all = Uint8List.fromList(nv21Base!);
      return RawFrame.fromPlanes(
        planes: [all],
        rowStrides: [yRowStride],
        pixelStrides: [uvPixelStride],
        width: width,
        height: height,
        rotation: rotation,
      );
    }
    return RawFrame(
      y: Uint8List.fromList(y),
      yRowStride: yRowStride,
      u: Uint8List.fromList(u),
      v: Uint8List.fromList(v),
      uvRowStride: uvRowStride,
      uvPixelStride: uvPixelStride,
      width: width,
      height: height,
      rotation: rotation,
    );
  }
}
