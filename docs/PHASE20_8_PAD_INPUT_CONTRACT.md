# PHASE 20.8: BIOMETRIC PAD INPUT CONTRACT & CAMERA BUFFER SPECIFICATION
**System:** Kelasagara Biometric Identity & Authentication Platform  
**Phase:** 20.8 (PAD Signal Extraction and Optical Evidence Engine)  
**Document Code:** SPEC-PAD-INPUT-2026-008  
**Author:** Mobile Camera Signal Processing Engineer & Senior Android Architect  
**Review Status:** Production Engineering Specification  
**Status:** VALIDATED & RATIFIED

---

## 1. Executive Summary & Problem Definition

In legacy configurations and Phase 20.7 experimental test harnesses, Presentation Attack Detection (PAD) evaluations accepted externally supplied numerical telemetry (such as pre-calculated floats for `periodicScreenGridEnergy` or `activeChromaticReflectionDelta`). 

In a Zero-Trust mobile architecture, **client-supplied scalar telemetry cannot be treated as authoritative evidence**. A hostile client (or modified APK running under instrumentation) can simply synthesize benign scalar values (`periodicScreenGridEnergy = 0.05`, `userCompliedWithAction = true`) to bypass server-side security.

The **authoritative input to the PAD engine must be the actual raw camera frames**, verifiable against Android camera subsystem constraints, acquisition timestamps, and server-issued cryptographic challenge nonces.

---

## 2. The Formal `CameraFrame` Data Contract

Every frame delivered to the PAD extraction pipeline must conform to the following formal TypeScript specification:

```typescript
/**
 * Supported native camera sensor formats on Android CameraX / Camera2.
 */
export type CameraPixelFormat =
  | 'YUV_420_888'      // Standard CameraX ImageAnalysis stream format
  | 'NV21'             // Legacy Android camera preview byte layout
  | 'JPEG_COMPRESSED'  // Server-transmitted burst buffer
  | 'RAW_GRAYSCALE';   // Decoded 8-bit luminance plane (Y)

/**
 * Android CameraX plane layout representation.
 * Accommodates diverse hardware vendors (Qualcomm, MediaTek, Unisoc, Exynos).
 */
export interface YuvPlaneSpecification {
  /** Underlying byte buffer containing plane pixels */
  readonly buffer: Buffer;
  /** Row stride in bytes (may include row padding beyond width) */
  readonly rowStride: number;
  /** Pixel stride in bytes (1 for planar Y; 2 for interleaved UV / VU; 1 for semi-planar) */
  readonly pixelStride: number;
}

/**
 * Traceable CameraFrame contract representing an authentic hardware acquisition.
 */
export interface CameraFrame {
  /** Unique UUIDv4 identifying this specific captured frame */
  readonly frameId: string;

  /** Session identifier bound to the active server challenge nonce */
  readonly captureSessionId: string;

  /** Sequence index within the burst (strictly 0, 1, or 2 for a 3-frame burst) */
  readonly sequenceIndex: number;

  /** Monotonic hardware timestamp from Android SystemClock.elapsedRealtimeNanos() */
  readonly hardwareTimestampNs: bigint;

  /** Wall-clock ISO 8601 UTC timestamp of acquisition */
  readonly wallClockTimestampUtc: string;

  /** Frame width in pixels */
  readonly width: number;

  /** Frame height in pixels */
  readonly height: number;

  /** Sensor rotation relative to natural device orientation (0, 90, 180, 270 degrees) */
  readonly rotationDegrees: 0 | 90 | 180 | 270;

  /** Pixel encoding format of the underlying buffer(s) */
  readonly pixelFormat: CameraPixelFormat;

  /** Plane specifications for multi-plane YUV buffers (Y, U, V) */
  readonly planes?: [YuvPlaneSpecification, YuvPlaneSpecification, YuvPlaneSpecification];

  /** Direct byte buffer containing raw or decoded image data */
  readonly rawBuffer: Buffer;

  /** Camera sensor metadata */
  readonly cameraMetadata: {
    readonly lensFacing: 'FRONT' | 'BACK';
    readonly sensorExposureDurationNs?: bigint;
    readonly sensorSensitivityIso?: number;
    readonly focalLengthMm?: number;
  };

  /** Ephemeral memory ownership & release lifecycle flag */
  readonly isReleased: boolean;
}
```

---

## 3. Physical Hardware Handling: Stride, Rotation, and Layout Variations

Android device manufacturers implement diverse hardware memory layouts for CameraX `ImageAnalysis` buffers:

```
+--------------------------------------------------------------------------------------------------+
| PHYSICAL ROW PADDING AND PIXEL STRIDE HANDLING                                                   |
+--------------------------------------------------------------------------------------------------+
  Width: 640 pixels
  [---------------------------------------------------------]
  Row Stride: 704 bytes (640 bytes active pixels + 64 bytes vendor padding)
  [---------------------------------------------------------|---------]
                                                            ^ Padding bytes (must be ignored)
```

### 3.1. Plane Row Stride & Pixel Stride Conversion
- **The Stride Hazard:** Assuming `data.length == width * height` causes memory corruption and diagonal shearing artifacts on devices where GPU/ISP alignment pads rows (e.g. `rowStride = 704` for `width = 640`).
- **Standardized Luminance Plane Extraction:**
  To extract a dense $W \times H$ grayscale buffer from a YUV plane with arbitrary row and pixel strides:
  ```typescript
  export function extractDenseLuminancePlane(
    plane: YuvPlaneSpecification,
    width: number,
    height: number
  ): Uint8Array {
    const dense = new Uint8Array(width * height);
    const { buffer, rowStride, pixelStride } = plane;

    for (let y = 0; y < height; y++) {
      const srcRowStart = y * rowStride;
      const dstRowStart = y * width;
      for (let x = 0; x < width; x++) {
        dense[dstRowStart + x] = buffer[srcRowStart + x * pixelStride];
      }
    }
    return dense;
  }
  ```

### 3.2. Sensor Orientation Normalization
Smartphone front cameras are physically mounted in landscape orientation ($270^\circ$ or $90^\circ$ relative to portrait). The input contract mandates that landmark coordinates and spatial frequency regions-of-interest (ROIs) are rotated to upright portrait coordinates before optical analysis.

---

## 4. Temporal Sequence Continuity & Monotonicity Rules

A valid 3-frame burst must satisfy three mathematical temporal invariants:

1. **Hardware Timestamp Monotonicity (`INV-TIME-01`):**
   $$T_0 < T_1 < T_2$$
   The hardware timestamps must be strictly monotonically increasing. If $T_{i+1} \le T_i$, the burst is rejected with `NON_MONOTONIC_TIMESTAMPS` (detects frame replay or race conditions).
2. **Inter-Frame Interval Bounds (`INV-TIME-02`):**
   $$\Delta T_{01} = T_1 - T_0, \quad \Delta T_{12} = T_2 - T_1$$
   $$\forall i \in \{01, 12\}: \quad 40\,\text{ms} \le \Delta T_i \le 350\,\text{ms}$$
   Intervals shorter than $40\,\text{ms}$ indicate synthetic frame injection (surpassing physical $30\,\text{FPS}$ sensor rates). Intervals exceeding $350\,\text{ms}$ indicate frame drops or user disruption.
3. **Session Monotonicity & Nonce Freshness (`INV-TIME-03`):**
   $$T_{\text{submission}} - T_{\text{challenge\_issued}} \le 3500\,\text{ms}$$
   All frames must be captured within the challenge validity window issued by the backend.

---

## 5. Ephemeral Buffer Memory & Crypto-Shredding Contract

In accordance with Phase 20.7 data retention and zero-plaintext biometrics policies:

1. **In-Memory Lifespan:** `CameraFrame` buffers reside solely in volatile heap memory for the duration of the request processing cycle ($< 250\,\text{ms}$).
2. **Deterministic Release:**
   Once spatial frequency features, landmark apertures, and SFace vectors are extracted, the application must execute an explicit release:
   ```typescript
   export function releaseCameraFrame(frame: CameraFrame): void {
     if (!frame.isReleased && frame.rawBuffer) {
       frame.rawBuffer.fill(0); // Zeroize native memory bytes
     }
   }
   ```
3. **Storage Prohibition:** Neither raw frames nor uncompressed pixel arrays may ever be serialized to SQLite, SharedPreferences, cloud object storage, or file system temp directories.

---

## 6. Contract Enforcement & Status

The `CameraFrame` contract establishes the boundary between client hardware and backend evaluation. In Phase 20.8, all subsequent optical feature extractors must accept this contract directly, ensuring complete decoupling from simulated telemetry.
