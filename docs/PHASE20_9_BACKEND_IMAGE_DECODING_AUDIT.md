# KELASAGARA V20.9: BACKEND IMAGE DECODING AUDIT
## Forensic Verification of Sharp Decoder & Pre-Processing Stages

**Document Ref:** `docs/PHASE20_9_BACKEND_IMAGE_DECODING_AUDIT.md`  
**Phase:** 20.9  
**Auditor:** Senior TypeScript Backend Engineer  
**Date:** November 1, 2026

---

### 1. Decoder Environment & Versioning

- **Backend Runtime:** Node.js v20.x
- **Image Processing Library:** `sharp` v0.35.5 (backed by `libvips` 8.16.x)
- **Decoding Configuration:**
  - `sharp(buffer).raw().toBuffer({ resolveWithObject: true })`
  - Strict color management: converts sRGB / JPEG ICC profiles to canonical linear sRGB / RGB24 buffer.
  - Fail-closed behavior on corrupted JPEG markers (`SOI`, `DQT`, `DHT`, `SOF0`, `EOI`).

---

### 2. Decoder Parity Verification

In Phase 20.9, the decoding pipeline was audited for consistency against native Android CameraX raw frames:

1. **Pixel Alignment:** Sharp raw extraction yields contiguous $W \times H \times 3$ interleaved buffer (`[R0, G0, B0, R1, G1, B1, ...]`).
2. **Channel Ordering:** Strict validation that RGB ordering is preserved (not swapped as BGR, which would corrupt SFace embedding features).
3. **Resampling Invariants:** When downsampling or cropping to $112 \times 112$ for SFace input:
   - Interpolation kernel: Bicubic interpolation (`sharp.kernel.cubic`).
   - Landmark alignment coordinates are scaled with sub-pixel floating-point precision before affine warping.
4. **Memory Management:** Sharp native allocations utilize `libvips` buffer pooling, which prevents Node.js V8 heap bloat during high-concurrency burst processing.
