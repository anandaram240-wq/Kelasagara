// C ABI around align_crop.h so Dart (dart:ffi) can call it. Add this file and
// align_crop.h + model_contract.h to the same CMake target as your existing
// biomatch_ffi_bridge.cpp. Returns AlignStatus (0 = OK).
#include "align_crop.h"

extern "C" __attribute__((visibility("default"))) __attribute__((used))
int bm_align_crop(const uint8_t* y, int yRowStride, const uint8_t* u, const uint8_t* v,
                  int uvRowStride, int uvPixelStride, int width, int height,
                  const float* landmarksRaw10, uint8_t* outRgb112, float* outOfFrame) {
  if (!y || !u || !v || !landmarksRaw10 || !outRgb112 || width <= 0 || height <= 0) return 1;
  biomatch::YuvFrame f{y, yRowStride, u, v, uvRowStride, uvPixelStride, width, height};
  return (int)biomatch::align_crop_rgb112(f, landmarksRaw10, outRgb112, outOfFrame);
}
