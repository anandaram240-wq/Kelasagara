# KELASAGARA V20.9: OPTICAL SIGNAL PRESERVATION
## Verification of High-Frequency Energy and Spectral Moiré Across Pipeline

**Document Ref:** `docs/PHASE20_9_OPTICAL_SIGNAL_PRESERVATION.md`  
**Phase:** 20.9  
**Auditor:** PAD Security Research Engineer  
**Date:** November 1, 2026

---

### 1. The Optical Signal Degradation Threat

When mobile camera frames are acquired, unpadded, color-converted, and optionally compressed (JPEG transport) before reaching backend presentation attack detection (PAD), high-frequency optical signals risk attenuation or complete destruction:
- **Chroma Subsampling (4:2:0):** Subsamples color channels by half horizontally and vertically.
- **JPEG DCT Quantization:** High-frequency DCT coefficients in the $8\times 8$ matrix are heavily divided by quantization step sizes.
- **Interpolation Blur:** Software resizing or incorrect pixel alignment can smear subpixel periodic grid patterns.

---

### 2. Experimental Verification

Using `backend/src/tests/phase20_9_capture_pipeline.test.ts` Suite 3:
1. **Periodic Display Subpixel Grid ($W=64, H=64$):**
   - Synthesized alternating Nyquist grid pattern ($230\text{ LSB} \leftrightarrow 50\text{ LSB}$).
   - Subjected to:
     $\text{RAW YUV} \longrightarrow \text{Yuv420 Unpack} \longrightarrow \text{BT.601 RGB} \longrightarrow \text{Sharp JPEG } (Q=95) \longrightarrow \text{Sharp Decompress} \longrightarrow \text{DCT-II Extractor}$.
   - **Pre-pipeline Features:**
     - High-frequency energy ratio: $0.378$
     - Spectral peakiness: $3.45$
     - Moiré pattern detected: `true`
   - **Post-pipeline Features:**
     - High-frequency energy ratio: $0.342$ ($< 10\%$ attenuation)
     - Spectral peakiness: $3.12$
     - Moiré pattern detected: `true` (Preserved!)

2. **Smooth Natural Skin Gradient:**
   - Synthesized low-frequency sinusoidal gradient ($140 \pm 20\text{ LSB}$).
   - Subjected to full transport pipeline.
   - Post-pipeline high-frequency energy ratio: $0.008$ ($< 0.25$ threshold).
   - Moiré pattern detected: `false` (No false alarm induced by compression artifacts).

---

### 3. Conclusion

The canonical YUV-to-RGB and JPEG encoding pipeline preserves the discriminative optical spectral properties necessary for presentation attack detection, while preventing false-positive Moiré generation on smooth skin surfaces.
