# KELASAGARA V20.10: YUV PLANE CORRECTNESS AUDIT
## Android Subsampled Chroma Alignment, Bounds Checking, and Memory Invariants

**System:** Kelasagara Major Project  
**Phase:** 20.10  
**Auditor:** CameraX & YUV Processing Specialist  
**Date:** November 1, 2026

---

### 1. Documented Android Plane Semantics

Under the official Android Camera2/CameraX specification for `ImageFormat.YUV_420_888`:
- Plane 0 represents Luminance ($Y$), with $pixelStride = 1$ (planar) and vendor-dependent $rowStride \ge width$.
- Plane 1 represents Chroma Blue ($U$ / $C_b$), subsampled $2\times 2$.
- Plane 2 represents Chroma Red ($V$ / $C_r$), subsampled $2\times 2$.
- When $pixelStride = 2$ on Planes 1 and 2, the memory is semi-planar:
  - If Plane 1 points to byte 0 and Plane 2 points to byte 1, the layout is **NV12** ($[U_0, V_0, U_1, V_1, \dots]$).
  - If Plane 2 points to byte 0 and Plane 1 points to byte 1, the layout is **NV21** ($[V_0, U_0, V_1, U_1, \dots]$).

---

### 2. Forensic Auditing of Edge Cases & Hardening

In Phase 20.10, `Yuv420PlaneReader.kt` and `camera_capture_integrity.ts` were audited and hardened against the following critical failure modes:

#### A. Odd Crop Coordinates & 2x2 Chroma Snapping
- **The Defect:** In $4:2:0$ subsampling, one chroma sample pairs with four luma samples ($2\times 2$). If a crop rectangle specifies an odd origin (`left = 3, top = 5`) or odd dimensions (`width = 17, height = 19`), dividing by 2 causes severe subpixel phase misregistration and chroma fringing.
- **The Resolution:** All crop rectangles are deterministically snapped to the nearest even chroma boundary:
  ```kotlin
  val alignedLeft = if (rawRect.left % 2 != 0) rawRect.left - 1 else rawRect.left
  val alignedTop = if (rawRect.top % 2 != 0) rawRect.top - 1 else rawRect.top
  var alignedWidth = rawRect.width()
  var alignedHeight = rawRect.height()
  if (alignedWidth % 2 != 0) alignedWidth -= 1
  if (alignedHeight % 2 != 0) alignedHeight -= 1
  ```

#### B. Strict Buffer Boundary Validation
- **The Defect:** Malicious or corrupted camera drivers could supply an undersized buffer or mismatched $rowStride$, resulting in buffer overrun or `BufferUnderflowException`.
- **The Resolution:** Every read operation validates:
  $$\text{pos} = \text{srcOffset} + \text{col} \times \text{pixelStride} < \text{buffer.limit()}$$
  Any violation throws an immediate, typed `BUFFER_OUT_OF_BOUNDS` error fail-closed.

#### C. Bounded Memory Limits
- Allocations are capped at $4096 \times 4096$ maximum dimensions and $25\text{ MB}$ total frame memory to prevent memory exhaustion DoS attacks.
