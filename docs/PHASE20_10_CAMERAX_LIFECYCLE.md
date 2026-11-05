# KELASAGARA V20.10: CAMERAX BUFFER LIFECYCLE
## Guaranteed Single-Disposal, Backpressure Strategy, and Exception Safety

**System:** Kelasagara Major Project  
**Phase:** 20.10  
**Auditor:** Senior Kotlin CameraX Systems Engineer  
**Date:** November 1, 2026

---

### 1. CameraX ImageAnalysis Backpressure Mechanics

Kelasagara configures CameraX with `ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST`.
- When the analyzer thread is busy, CameraX automatically drops incoming intermediate hardware frames from the HAL buffer queue.
- This design prioritizes pipeline freshness over exhaustive frame delivery, preventing latency lag.
- **Architectural Consequence:** The server must NOT require sequential physical camera sensor frame numbers. The transmitted `index` ($0, 1, \dots, K-1$) represents the **accepted application frame index** within the burst.

---

### 2. Guaranteed Single-Disposal Lifecycle Pattern

In `Yuv420PlaneReader.kt`:
```kotlin
inline fun <T> safeProcessImage(image: Image, block: (Image) -> T): T {
    try {
        return block(image)
    } finally {
        try {
            image.close()
        } catch (e: Exception) {
            Log.w(TAG, "Suppressed exception on closing ImageProxy: ${e.message}")
        }
    }
}
```

#### Lifecycle Guarantees
1. **Exactly Once Close:** Regardless of whether plane extraction succeeds, fails due to corrupted strides, or encounters a cancellation exception, `image.close()` is guaranteed to execute in the `finally` block.
2. **Never Close Media.Image Independently:** The wrapper `ImageProxy` handles native memory release. Closing the inner `android.media.Image` directly causes native handle double-free crashes in `libcamera2ndk.so`.
3. **No Reference Escaping:** Direct NIO `ByteBuffer` references never escape the analyzer thread; only decoupled, unpadded `CanonicalYuv420Frame` instances are passed downstream.
