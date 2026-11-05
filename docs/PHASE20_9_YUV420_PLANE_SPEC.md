# KELASAGARA V20.9: YUV_420_888 PLANE SPECIFICATION
## Hardware Plane Unpacking, Subsampling, and Normalization Invariants

**Document Ref:** `docs/PHASE20_9_YUV420_PLANE_SPEC.md`  
**Phase:** 20.9  
**Auditor:** CameraX & YUV Processing Specialist  
**Date:** November 1, 2026

---

### 1. Problem Statement: Android Hardware Heterogeneity

On the Android platform, `ImageFormat.YUV_420_888` is a generic multi-plane format that camera hardware vendors implement in radically different memory topologies:
- **Qualcomm Snapdragon:** Typically delivers semi-planar NV12 or NV21 layouts with 64-byte aligned padded row strides (e.g., width 640 has `rowStride = 704` or `768`).
- **MediaTek Dimensity / Helio:** Often uses contiguous planar I420 with 16-byte alignment or semi-planar NV12.
- **Samsung Exynos:** Uses custom row padding and variable chroma plane offsets.
- **Unisoc / Entry-level SoCs:** Often exhibits non-zero buffer starting positions and odd dimension cropping.

Any naive implementation that assumes `rowStride == width` or `pixelStride == 1` causes catastrophic memory corruption, diagonal shearing, or green tint artifacting.

---

### 2. Formal Memory Layouts

#### Planar I420 (YV12 variant)
- $Y$ Plane: $W \times H$ contiguous bytes ($pixelStride = 1$).
- $U$ (Cb) Plane: $(W/2) \times (H/2)$ contiguous bytes ($pixelStride = 1$).
- $V$ (Cr) Plane: $(W/2) \times (H/2)$ contiguous bytes ($pixelStride = 1$).

#### Semi-Planar NV12
- $Y$ Plane: $W \times H$ contiguous bytes.
- $UV$ Plane: $(W/2) \times (H/2) \times 2$ bytes interleaved as $[U_0, V_0, U_1, V_1, \dots]$.
- $U$ Plane buffer starts at index 0, $pixelStride = 2$.
- $V$ Plane buffer starts at index 1, $pixelStride = 2$.

#### Semi-Planar NV21
- Identical to NV12, except chroma is swapped: $[V_0, U_0, V_1, U_1, \dots]$.
- $V$ Plane buffer starts at index 0, $pixelStride = 2$.
- $U$ Plane buffer starts at index 1, $pixelStride = 2$.

---

### 3. Canonical Unpacking Algorithm

`Yuv420PlaneReader.kt` and `CameraCaptureIntegrity.ts` implement the following unpadding formula:

```kotlin
// For Y-plane:
for (row in 0 until cropH) {
    val srcRowOffset = (cropTop + row) * yRowStride + cropLeft * yPixelStride
    val dstRowOffset = row * cropW
    if (yPixelStride == 1) {
        yBuffer.position(srcRowOffset)
        yBuffer.get(yOut, dstRowOffset, cropW)
    } else {
        for (col in 0 until cropW) {
            yOut[dstRowOffset + col] = yBuffer.get(srcRowOffset + col * yPixelStride)
        }
    }
}

// For Chroma planes (U and V):
for (row in 0 until (cropH / 2)) {
    val uSrcRowOffset = (cropTop / 2 + row) * uRowStride + (cropLeft / 2) * uPixelStride
    val vSrcRowOffset = (cropTop / 2 + row) * vRowStride + (cropLeft / 2) * vPixelStride
    val dstRowOffset = row * (cropW / 2)
    for (col in 0 until (cropW / 2)) {
        uOut[dstRowOffset + col] = uBuffer.get(uSrcRowOffset + col * uPixelStride)
        vOut[dstRowOffset + col] = vBuffer.get(vSrcRowOffset + col * vPixelStride)
    }
}
```

---

### 4. Rotation Normalization

To ensure invariant face detector performance across landscape, portrait, and reverse orientations:
- Sensor rotation degrees ($0^\circ, 90^\circ, 180^\circ, 270^\circ$) are read from CameraX `ImageInfo.rotationDegrees`.
- Planes are transformed prior to hashing and transmission so that all output frames are upright.
- $90^\circ$ and $270^\circ$ rotations swap output width and height ($W' = H, H' = W$).
- Downstream models always receive correctly oriented biometric feature inputs.
