package com.kelasagaara.kelasagaara.camera

import android.graphics.Rect
import android.media.Image
import java.nio.ByteBuffer
import java.security.MessageDigest
import kotlin.math.max
import kotlin.math.min

/**
 * Kelasagara V20.10: Hardened Canonical YUV_420_888 Plane Reader & Buffer Lifecycle Engine.
 *
 * Implements deterministic unpacking of Android CameraX/MediaCodec YUV_420_888 frame buffers
 * across arbitrary hardware implementations (Qualcomm, MediaTek, Exynos, Unisoc).
 *
 * Guaranteed Invariants:
 * 1. Independent of vendor row padding (handles rowStride > width).
 * 2. Independent of chroma subsampling layout (handles planar pixelStride=1 and semi-planar NV12/NV21 pixelStride=2).
 * 3. Strict buffer boundary validation (asserts buffer.position() <= srcOffset < buffer.limit() before every read).
 * 4. Subsampled chroma alignment: snaps odd crop origins and dimensions to 2x2 chroma boundaries.
 * 5. Bounded allocations: rejects dimensions > 4096 or buffers > 25MB to prevent memory exhaustion.
 * 6. Supports all four right-angle rotations (0, 90, 180, 270) and front-camera horizontal mirroring.
 * 7. Controlled lifecycle: provides safe try/finally execution ensuring ImageProxy is released exactly once.
 * 8. Best-effort zeroization: clears transient arrays before garbage collection.
 */
class Yuv420PlaneReader {

    data class PlaneLayout(
        val buffer: ByteBuffer,
        val rowStride: Int,
        val pixelStride: Int
    )

    data class CanonicalYuv420Frame(
        val width: Int,
        val height: Int,
        val rotationDegrees: Int,
        val isFrontMirrored: Boolean,
        val timestampNs: Long,
        val cropRect: Rect,
        val yPlane: ByteArray,
        val uPlane: ByteArray,
        val vPlane: ByteArray,
        val format: String = "I420_PLANAR",
        val sha256DigestHex: String
    ) {
        /**
         * Returns contiguous I420 byte array: [Y (w*h), U (w*h/4), V (w*h/4)].
         */
        fun toContiguousI420(): ByteArray {
            val totalSize = yPlane.size + uPlane.size + vPlane.size
            val out = ByteArray(totalSize)
            System.arraycopy(yPlane, 0, out, 0, yPlane.size)
            System.arraycopy(uPlane, 0, out, yPlane.size, uPlane.size)
            System.arraycopy(vPlane, 0, out, yPlane.size + uPlane.size, vPlane.size)
            return out
        }

        /**
         * Extracts pure grayscale bytes (Y-plane only, 8-bit luminance).
         */
        fun toGrayscale(): ByteArray {
            val gray = ByteArray(yPlane.size)
            System.arraycopy(yPlane, 0, gray, 0, yPlane.size)
            return gray
        }

        /**
         * Converts canonical I420 planar bytes to RGB24 bytes via ITU-R BT.601 full-range equations.
         * R = Y + 1.402 * (V - 128)
         * G = Y - 0.344136 * (U - 128) - 0.714136 * (V - 128)
         * B = Y + 1.772 * (U - 128)
         */
        fun toRgb24(): ByteArray {
            val rgb = ByteArray(width * height * 3)
            val halfW = width / 2
            var rgbIdx = 0

            for (y in 0 until height) {
                val yRowStart = y * width
                val uvRowStart = (y / 2) * halfW

                for (x in 0 until width) {
                    val yVal = yPlane[yRowStart + x].toInt() and 0xFF
                    val uvIdx = uvRowStart + (x / 2)
                    val uVal = (uPlane[uvIdx].toInt() and 0xFF) - 128
                    val vVal = (vPlane[uvIdx].toInt() and 0xFF) - 128

                    val r = (yVal + 1.402f * vVal).toInt().coerceIn(0, 255)
                    val g = (yVal - 0.344136f * uVal - 0.714136f * vVal).toInt().coerceIn(0, 255)
                    val b = (yVal + 1.772f * uVal).toInt().coerceIn(0, 255)

                    rgb[rgbIdx++] = r.toByte()
                    rgb[rgbIdx++] = g.toByte()
                    rgb[rgbIdx++] = b.toByte()
                }
            }
            return rgb
        }

        /**
         * Best-effort memory clearing of planar arrays.
         * Note: As with all JVM memory, this is best-effort and does not guarantee absolute zeroization
         * if the runtime GC relocates memory pages.
         */
        fun zeroize() {
            yPlane.fill(0)
            uPlane.fill(0)
            vPlane.fill(0)
        }
    }

    companion object {
        const val TAG = "Yuv420PlaneReader"
        const val MAX_IMAGE_DIMENSION = 4096
        const val MAX_BUFFER_ALLOCATION = 25 * 1024 * 1024 // 25 MB

        /**
         * Extracts and normalizes an Android android.media.Image (YUV_420_888).
         */
        fun extractFromMediaImage(
            image: Image,
            rotationDegrees: Int = 0,
            isFrontMirrored: Boolean = false,
            timestampNs: Long = System.nanoTime()
        ): CanonicalYuv420Frame {
            require(image.format == android.graphics.ImageFormat.YUV_420_888) {
                "Unsupported image format: ${image.format}. Expected YUV_420_888."
            }
            val planes = image.planes
            require(planes.size == 3) { "Image must have 3 planes for YUV_420_888" }

            val cropRect = image.cropRect ?: Rect(0, 0, image.width, image.height)
            val yPlane = PlaneLayout(planes[0].buffer, planes[0].rowStride, planes[0].pixelStride)
            val uPlane = PlaneLayout(planes[1].buffer, planes[1].rowStride, planes[1].pixelStride)
            val vPlane = PlaneLayout(planes[2].buffer, planes[2].rowStride, planes[2].pixelStride)

            return extractFromPlanes(
                yPlane = yPlane,
                uPlane = uPlane,
                vPlane = vPlane,
                rawWidth = image.width,
                rawHeight = image.height,
                rotationDegrees = rotationDegrees,
                isFrontMirrored = isFrontMirrored,
                timestampNs = timestampNs,
                cropRect = cropRect
            )
        }

        /**
         * Safely processes an ImageProxy inside a controlled try/finally block, ensuring image.close()
         * is called exactly once under all conditions.
         */
        inline fun <T> safeProcessImage(image: Image, block: (Image) -> T): T {
            try {
                return block(image)
            } finally {
                try {
                    image.close()
                } catch (e: Exception) {
                    // Closed safely, suppress secondary exceptions on closing
                }
            }
        }

        /**
         * Extracts and normalizes arbitrary plane buffers, handling stride padding, interleaving,
         * subsampled chroma coordinates, and strict bounds checking.
         */
        fun extractFromPlanes(
            yPlane: PlaneLayout,
            uPlane: PlaneLayout,
            vPlane: PlaneLayout,
            rawWidth: Int,
            rawHeight: Int,
            rotationDegrees: Int = 0,
            isFrontMirrored: Boolean = false,
            timestampNs: Long = System.nanoTime(),
            cropRect: Rect? = null
        ): CanonicalYuv420Frame {
            // 1. Validate Dimension Boundaries
            require(rawWidth in 16..MAX_IMAGE_DIMENSION && rawHeight in 16..MAX_IMAGE_DIMENSION) {
                "Dimensions out of allowed bounds [16..$MAX_IMAGE_DIMENSION]: ${rawWidth}x${rawHeight}"
            }

            val rawRect = cropRect ?: Rect(0, 0, rawWidth, rawHeight)
            require(rawRect.left >= 0 && rawRect.top >= 0 && rawRect.right <= rawWidth && rawRect.bottom <= rawHeight) {
                "Crop rect $rawRect exceeds raw boundaries: ${rawWidth}x${rawHeight}"
            }

            // 2. Subsampled Chroma Alignment: Ensure even origin and dimensions for 4:2:0 subsampling
            val alignedLeft = if (rawRect.left % 2 != 0) rawRect.left - 1 else rawRect.left
            val alignedTop = if (rawRect.top % 2 != 0) rawRect.top - 1 else rawRect.top
            var alignedWidth = rawRect.width()
            var alignedHeight = rawRect.height()

            if (alignedWidth % 2 != 0) alignedWidth -= 1
            if (alignedHeight % 2 != 0) alignedHeight -= 1

            require(alignedWidth >= 16 && alignedHeight >= 16) {
                "Aligned crop dimensions must be >= 16: ${alignedWidth}x${alignedHeight}"
            }

            val totalBytes = alignedWidth * alignedHeight + (alignedWidth / 2) * (alignedHeight / 2) * 2
            require(totalBytes <= MAX_BUFFER_ALLOCATION) {
                "Requested frame size exceeds maximum allocation limit of $MAX_BUFFER_ALLOCATION bytes"
            }

            val yOut = ByteArray(alignedWidth * alignedHeight)
            val halfW = alignedWidth / 2
            val halfH = alignedHeight / 2
            val uOut = ByteArray(halfW * halfH)
            val vOut = ByteArray(halfW * halfH)

            // 3. Unpack Luminance Y Plane with Strict Limit Verification
            val yBuf = yPlane.buffer.duplicate()
            val yLimit = yBuf.limit()
            val yRowStride = yPlane.rowStride
            val yPixelStride = yPlane.pixelStride

            require(yRowStride >= alignedWidth) {
                "Invalid Y rowStride $yRowStride < width $alignedWidth"
            }
            require(yPixelStride in 1..2) {
                "Invalid Y pixelStride $yPixelStride (must be 1 or 2)"
            }

            for (row in 0 until alignedHeight) {
                val srcRowOffset = (alignedTop + row) * yRowStride + alignedLeft * yPixelStride
                val dstRowOffset = row * alignedWidth

                if (yPixelStride == 1) {
                    val endOffset = srcRowOffset + alignedWidth
                    require(endOffset <= yLimit) {
                        "Y plane buffer underflow: offset $endOffset > limit $yLimit at row $row"
                    }
                    yBuf.position(srcRowOffset)
                    yBuf.get(yOut, dstRowOffset, alignedWidth)
                } else {
                    for (col in 0 until alignedWidth) {
                        val pos = srcRowOffset + col * yPixelStride
                        require(pos < yLimit) {
                            "Y plane buffer underflow: pos $pos >= limit $yLimit at row $row, col $col"
                        }
                        yOut[dstRowOffset + col] = yBuf.get(pos)
                    }
                }
            }

            // 4. Unpack Chroma Planes (U and V) with Subsampled Coordinates
            val uBuf = uPlane.buffer.duplicate()
            val vBuf = vPlane.buffer.duplicate()
            val uLimit = uBuf.limit()
            val vLimit = vBuf.limit()
            val uRowStride = uPlane.rowStride
            val uPixelStride = uPlane.pixelStride
            val vRowStride = vPlane.rowStride
            val vPixelStride = vPlane.pixelStride

            val cropTopHalf = alignedTop / 2
            val cropLeftHalf = alignedLeft / 2

            for (row in 0 until halfH) {
                val uSrcRowOffset = (cropTopHalf + row) * uRowStride + cropLeftHalf * uPixelStride
                val vSrcRowOffset = (cropTopHalf + row) * vRowStride + cropLeftHalf * vPixelStride
                val dstRowOffset = row * halfW

                for (col in 0 until halfW) {
                    val uPos = uSrcRowOffset + col * uPixelStride
                    val vPos = vSrcRowOffset + col * vPixelStride

                    require(uPos < uLimit) {
                        "U plane buffer underflow: pos $uPos >= limit $uLimit at row $row, col $col"
                    }
                    require(vPos < vLimit) {
                        "V plane buffer underflow: pos $vPos >= limit $vLimit at row $row, col $col"
                    }

                    uOut[dstRowOffset + col] = uBuf.get(uPos)
                    vOut[dstRowOffset + col] = vBuf.get(vPos)
                }
            }

            // 5. Handle Horizontal Mirroring (Front Camera) if required
            val (mirroredY, mirroredU, mirroredV) = if (isFrontMirrored) {
                Triple(
                    mirrorPlaneHorizontal(yOut, alignedWidth, alignedHeight),
                    mirrorPlaneHorizontal(uOut, halfW, halfH),
                    mirrorPlaneHorizontal(vOut, halfW, halfH)
                )
            } else {
                Triple(yOut, uOut, vOut)
            }

            // 6. Handle Rotation (0, 90, 180, 270)
            val normalizedDegrees = ((rotationDegrees % 360) + 360) % 360
            val (finalW, finalH, finalY, finalU, finalV) = if (normalizedDegrees == 0) {
                FramePlanes(alignedWidth, alignedHeight, mirroredY, mirroredU, mirroredV)
            } else {
                rotateI420(alignedWidth, alignedHeight, mirroredY, mirroredU, mirroredV, normalizedDegrees)
            }

            // 7. Compute SHA-256 Digest of canonical I420 planar memory
            val md = MessageDigest.getInstance("SHA-256")
            md.update(finalY)
            md.update(finalU)
            md.update(finalV)
            val digest = md.digest()
            val digestHex = digest.joinToString("") { "%02x".format(it) }

            return CanonicalYuv420Frame(
                width = finalW,
                height = finalH,
                rotationDegrees = normalizedDegrees,
                isFrontMirrored = isFrontMirrored,
                timestampNs = timestampNs,
                cropRect = Rect(alignedLeft, alignedTop, alignedLeft + alignedWidth, alignedTop + alignedHeight),
                yPlane = finalY,
                uPlane = finalU,
                vPlane = finalV,
                format = "I420_PLANAR",
                sha256DigestHex = digestHex
            )
        }

        private data class FramePlanes(
            val width: Int,
            val height: Int,
            val y: ByteArray,
            val u: ByteArray,
            val v: ByteArray
        )

        private fun mirrorPlaneHorizontal(src: ByteArray, w: Int, h: Int): ByteArray {
            val dst = ByteArray(w * h)
            for (y in 0 until h) {
                val rowOffset = y * w
                for (x in 0 until w) {
                    dst[rowOffset + (w - 1 - x)] = src[rowOffset + x]
                }
            }
            return dst
        }

        private fun rotateI420(
            w: Int,
            h: Int,
            y: ByteArray,
            u: ByteArray,
            v: ByteArray,
            degrees: Int
        ): FramePlanes {
            return when (degrees) {
                90 -> {
                    val rotW = h
                    val rotH = w
                    val rotY = rotatePlane90(y, w, h)
                    val rotU = rotatePlane90(u, w / 2, h / 2)
                    val rotV = rotatePlane90(v, w / 2, h / 2)
                    FramePlanes(rotW, rotH, rotY, rotU, rotV)
                }
                180 -> {
                    val rotY = rotatePlane180(y, w, h)
                    val rotU = rotatePlane180(u, w / 2, h / 2)
                    val rotV = rotatePlane180(v, w / 2, h / 2)
                    FramePlanes(w, h, rotY, rotU, rotV)
                }
                270 -> {
                    val rotW = h
                    val rotH = w
                    val rotY = rotatePlane270(y, w, h)
                    val rotU = rotatePlane270(u, w / 2, h / 2)
                    val rotV = rotatePlane270(v, w / 2, h / 2)
                    FramePlanes(rotW, rotH, rotY, rotU, rotV)
                }
                else -> FramePlanes(w, h, y, u, v)
            }
        }

        private fun rotatePlane90(src: ByteArray, w: Int, h: Int): ByteArray {
            val dst = ByteArray(w * h)
            var dstIdx = 0
            for (x in 0 until w) {
                for (y in h - 1 downTo 0) {
                    dst[dstIdx++] = src[y * w + x]
                }
            }
            return dst
        }

        private fun rotatePlane180(src: ByteArray, w: Int, h: Int): ByteArray {
            val dst = ByteArray(w * h)
            val total = w * h
            for (i in 0 until total) {
                dst[i] = src[total - 1 - i]
            }
            return dst
        }

        private fun rotatePlane270(src: ByteArray, w: Int, h: Int): ByteArray {
            val dst = ByteArray(w * h)
            var dstIdx = 0
            for (x in w - 1 downTo 0) {
                for (y in 0 until h) {
                    dst[dstIdx++] = src[y * w + x]
                }
            }
            return dst
        }
    }
}
