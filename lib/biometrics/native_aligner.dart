import 'dart:ffi' as ffi;
import 'dart:isolate';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'raw_frame.dart';

enum AlignStatus { ok, degenerate, badScale, notAFaceShape, error }

class AlignResult {
  const AlignResult(this.status, this.rgb112, this.outOfFrame);
  final AlignStatus status;
  final Uint8List? rgb112; // 112*112*3
  final double outOfFrame; // reject when > ~0.02
  bool get isOk => status == AlignStatus.ok && rgb112 != null;
}

typedef _AlignC = ffi.Int32 Function(
    ffi.Pointer<ffi.Uint8>, ffi.Int32, ffi.Pointer<ffi.Uint8>, ffi.Pointer<ffi.Uint8>,
    ffi.Int32, ffi.Int32, ffi.Int32, ffi.Int32,
    ffi.Pointer<ffi.Float>, ffi.Pointer<ffi.Uint8>, ffi.Pointer<ffi.Float>);
typedef _AlignDart = int Function(
    ffi.Pointer<ffi.Uint8>, int, ffi.Pointer<ffi.Uint8>, ffi.Pointer<ffi.Uint8>,
    int, int, int, int,
    ffi.Pointer<ffi.Float>, ffi.Pointer<ffi.Uint8>, ffi.Pointer<ffi.Float>);

/// Phase 1.4. Runs the C++ warper in a background isolate. [landmarksRaw10]
/// must come from fivePointsRaw() (RAW-frame coordinates).
abstract class NativeAligner {
  Future<AlignResult> alignCrop(RawFrame frame, List<double> landmarksRaw10);
}

class FfiNativeAligner implements NativeAligner {
  FfiNativeAligner({this.libraryName = 'libbiomatch_align.so'});
  final String libraryName;

  @override
  Future<AlignResult> alignCrop(RawFrame f, List<double> lm) async {
    if (lm.length != 10) return const AlignResult(AlignStatus.error, null, 1);
    // Copy the planes into plain lists that can cross the isolate boundary.
    final args = _Args(
      f.y, f.u, f.v, f.yRowStride, f.uvRowStride, f.uvPixelStride, f.width, f.height, lm,
      libraryName,
    );
    return Isolate.run(() => _alignInIsolate(args));
  }
}

class _Args {
  _Args(this.y, this.u, this.v, this.yStride, this.uvStride, this.uvPix, this.w, this.h, this.lm, this.lib);
  final Uint8List y, u, v;
  final int yStride, uvStride, uvPix, w, h;
  final List<double> lm;
  final String lib;
}

AlignResult _alignInIsolate(_Args a) {
  ffi.DynamicLibrary lib;
  try {
    lib = ffi.DynamicLibrary.open(a.lib);
  } catch (_) {
    try {
      lib = ffi.DynamicLibrary.open('libbiomatch_native.so');
    } catch (_) {
      lib = ffi.DynamicLibrary.process();
    }
  }
  final fn = lib.lookupFunction<_AlignC, _AlignDart>('bm_align_crop');
  final py = malloc<ffi.Uint8>(a.y.length)..asTypedList(a.y.length).setAll(0, a.y);
  final pu = malloc<ffi.Uint8>(a.u.length)..asTypedList(a.u.length).setAll(0, a.u);
  final pv = malloc<ffi.Uint8>(a.v.length)..asTypedList(a.v.length).setAll(0, a.v);
  final plm = malloc<ffi.Float>(10);
  for (var i = 0; i < 10; i++) { plm[i] = a.lm[i]; }
  final out = malloc<ffi.Uint8>(112 * 112 * 3);
  final oof = malloc<ffi.Float>(1);
  try {
    final st = fn(py, a.yStride, pu, pv, a.uvStride, a.uvPix, a.w, a.h, plm, out, oof);
    final status = switch (st) {
      0 => AlignStatus.ok,
      1 => AlignStatus.degenerate,
      2 => AlignStatus.badScale,
      3 => AlignStatus.notAFaceShape,
      _ => AlignStatus.error,
    };
    if (status != AlignStatus.ok) return AlignResult(status, null, 1);
    return AlignResult(status, Uint8List.fromList(out.asTypedList(112 * 112 * 3)), oof.value);
  } finally {
    malloc.free(py); malloc.free(pu); malloc.free(pv);
    malloc.free(plm); malloc.free(out); malloc.free(oof);
  }
}
