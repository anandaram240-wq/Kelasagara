// Reference implementation of the Phase 1.3 / 1.4 warper: raw camera frame
// (NV21 or I420, any row stride) + 5 landmarks in RAW-FRAME pixel coordinates
// -> 112x112 RGB crop aligned to the ArcFace template. Pure C++17, no Android
// dependencies, so it is unit-testable on a laptop (see test_align.cpp).
//
// If your existing biomatch_ffi_bridge.cpp already has a warper, keep it, but
// make it pass test_align.cpp (rotation cases and the reflection/degenerate
// guards). Then the bridge should hand BOTH this RGB crop (for PNG upload) and
// the embedding back to Dart.
#pragma once
#include <algorithm>
#include <cmath>
#include <cstdint>
#include "model_contract.h"

namespace biomatch {

struct YuvFrame {
  const uint8_t* y;
  int yRowStride;
  const uint8_t* u;       // NV21: base + frameSize + 1 ; I420: the U plane
  const uint8_t* v;       // NV21: base + frameSize     ; I420: the V plane
  int uvRowStride;
  int uvPixelStride;      // NV21: 2 ; I420: 1
  int width;
  int height;
};

// Least-squares similarity (rotation + uniform scale + translation, NO
// reflection) mapping src -> dst:  x' = a*x - b*y + tx ,  y' = b*x + a*y + ty.
// Complex-number form of Umeyama's solution; exact for 2D.
struct Similarity { float a, b, tx, ty; float rms; };

inline bool estimate_similarity(const float src[5][2], const float dst[5][2], Similarity* out) {
  double msx = 0, msy = 0, mdx = 0, mdy = 0;
  for (int i = 0; i < 5; i++) { msx += src[i][0]; msy += src[i][1]; mdx += dst[i][0]; mdy += dst[i][1]; }
  msx /= 5; msy /= 5; mdx /= 5; mdy /= 5;
  double num_a = 0, num_b = 0, den = 0;
  for (int i = 0; i < 5; i++) {
    const double sx = src[i][0] - msx, sy = src[i][1] - msy, dx = dst[i][0] - mdx, dy = dst[i][1] - mdy;
    num_a += sx * dx + sy * dy;
    num_b += sx * dy - sy * dx;
    den += sx * sx + sy * sy;
  }
  if (den < 1e-9) return false;
  const double a = num_a / den, b = num_b / den;
  const double tx = mdx - (a * msx - b * msy), ty = mdy - (b * msx + a * msy);
  double sse = 0;
  for (int i = 0; i < 5; i++) {
    const double px = a * src[i][0] - b * src[i][1] + tx, py = b * src[i][0] + a * src[i][1] + ty;
    sse += (px - dst[i][0]) * (px - dst[i][0]) + (py - dst[i][1]) * (py - dst[i][1]);
  }
  *out = {(float)a, (float)b, (float)tx, (float)ty, (float)std::sqrt(sse / 5)};
  return true;
}

inline void yuv_to_rgb(int Y, int U, int V, float rgb[3]) {  // BT.601 full range (JFIF), as Android camera output
  const float y = (float)Y, u = (float)U - 128.f, v = (float)V - 128.f;
  rgb[0] = y + 1.402f * v;
  rgb[1] = y - 0.344136f * u - 0.714136f * v;
  rgb[2] = y + 1.772f * u;
}

inline void sample_rgb(const YuvFrame& f, int x, int y, float rgb[3]) {
  x = std::min(std::max(x, 0), f.width - 1);
  y = std::min(std::max(y, 0), f.height - 1);
  const int Y = f.y[y * f.yRowStride + x];
  const int uvOff = (y / 2) * f.uvRowStride + (x / 2) * f.uvPixelStride;
  yuv_to_rgb(Y, f.u[uvOff], f.v[uvOff], rgb);
}

enum AlignStatus { ALIGN_OK = 0, ALIGN_DEGENERATE = 1, ALIGN_BAD_SCALE = 2, ALIGN_NOT_A_FACE_SHAPE = 3 };

// landmarksRaw: x0,y0,...,x4,y4 in raw-buffer pixels, order: image-left eye,
// image-right eye, nose, image-left mouth corner, image-right mouth corner.
// outRgb: 112*112*3 bytes, row-major HWC. outOfFrame: fraction of crop pixels
// that fell outside the camera frame (reject captures where this is > ~0.02).
inline AlignStatus align_crop_rgb112(const YuvFrame& f, const float landmarksRaw[10], uint8_t* outRgb, float* outOfFrame) {
  float dst[5][2];
  for (int i = 0; i < 5; i++) { dst[i][0] = landmarksRaw[2 * i]; dst[i][1] = landmarksRaw[2 * i + 1]; }
  Similarity m;
  if (!estimate_similarity(kAlignTemplate112, dst, &m)) return ALIGN_DEGENERATE;
  const float scale = std::sqrt(m.a * m.a + m.b * m.b);  // template px -> raw px
  if (!(scale > 0.5f && scale < 20.f)) return ALIGN_BAD_SCALE;
  // A mirrored or mis-ordered landmark set is not a similarity of the template
  // and leaves a large residual. Typical genuine faces stay well under 6%.
  const float eyeDistRaw = scale * 35.2f;
  if (!(m.rms / eyeDistRaw < 0.12f)) return ALIGN_NOT_A_FACE_SHAPE;

  const int n = kInputSize;
  int outside = 0;
  for (int v = 0; v < n; v++) {
    for (int u = 0; u < n; u++) {
      const float sx = m.a * u - m.b * v + m.tx, sy = m.b * u + m.a * v + m.ty;
      if (sx < 0 || sy < 0 || sx > f.width - 1 || sy > f.height - 1) outside++;
      const int x0 = (int)std::floor(sx), y0 = (int)std::floor(sy);
      const float fx = sx - x0, fy = sy - y0;
      float c00[3], c10[3], c01[3], c11[3];
      sample_rgb(f, x0, y0, c00); sample_rgb(f, x0 + 1, y0, c10);
      sample_rgb(f, x0, y0 + 1, c01); sample_rgb(f, x0 + 1, y0 + 1, c11);
      for (int c = 0; c < 3; c++) {
        const float top = c00[c] * (1 - fx) + c10[c] * fx, bot = c01[c] * (1 - fx) + c11[c] * fx;
        const float val = top * (1 - fy) + bot * fy;
        outRgb[(v * n + u) * 3 + c] = (uint8_t)std::min(255.f, std::max(0.f, val + 0.5f));
      }
    }
  }
  if (outOfFrame) *outOfFrame = (float)outside / (float)(n * n);
  return ALIGN_OK;
}

// RGB crop -> float CHW tensor exactly as the server does (see model_contract.ts).
inline void rgb_to_tensor(const uint8_t* rgb, float* out) {
  const int plane = kInputSize * kInputSize;
  for (int i = 0; i < plane; i++) {
    const float r = rgb[i * 3], g = rgb[i * 3 + 1], b = rgb[i * 3 + 2];
    out[i] = ((kBgr ? b : r) - kMean) / kStd;
    out[plane + i] = (g - kMean) / kStd;
    out[2 * plane + i] = ((kBgr ? r : b) - kMean) / kStd;
  }
}

// ML Kit returns points in the UPRIGHT image. `rotation` is the clockwise
// degrees (0/90/180/270) you told ML Kit the raw frame needs to look upright.
// MUST match uprightToRaw() in app/lib/biometrics/landmark_geometry.dart.
inline void upright_to_raw(float xu, float yu, int rotation, int rawW, int rawH, float* x, float* y) {
  switch (rotation) {
    case 90:  *x = yu;               *y = rawH - 1 - xu; break;
    case 180: *x = rawW - 1 - xu;    *y = rawH - 1 - yu; break;
    case 270: *x = rawW - 1 - yu;    *y = xu;            break;
    default:  *x = xu;               *y = yu;            break;
  }
}

}  // namespace biomatch
