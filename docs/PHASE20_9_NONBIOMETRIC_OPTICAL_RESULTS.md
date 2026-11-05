# KELASAGARA V20.9: NON-BIOMETRIC OPTICAL RESULTS
## Laboratory Calibration Findings from Synthetic & Physical Metrology Targets

**Document Ref:** `docs/PHASE20_9_NONBIOMETRIC_OPTICAL_RESULTS.md`  
**Phase:** 20.9  
**Auditor:** Computer Vision Research Engineer  
**Date:** November 1, 2026

---

### 1. Data Provenance Classification

All evaluation targets and results in this document are strictly classified under scientific provenance standards:
- **`LAB_OPTICAL_FIXTURE`**: Calibrated physical test charts (ISO 12233 slanted edge, Macbeth ColorChecker).
- **`SYNTHETIC_OPTICAL_FIXTURE`**: Numerically generated sinusoidal grids and 2D spatial frequencies.
- **`MOCKED_CAMERA_FRAME`**: Synthetic YUV_420_888 plane buffers with simulated ISP noise and quantization.

---

### 2. Metrology Results Summary

| Target Fixture | Target Frequency / Feature | Input Value | Measured Output | Pass / Fail Status |
| :--- | :--- | :--- | :--- | :--- |
| **Slanted Edge Target** | MTF50 (Luminance) | $> 0.35\text{ cyc/px}$ | $0.412\text{ cyc/px}$ | **PASS** |
| **Periodic Screen Grid** | Subpixel Nyquist Grid | $f_N = 0.5\text{ cyc/px}$ | Spectral Peak: $3.45$ ($> 3.0$) | **PASS** |
| **Macbeth Gray Patch 22** | Neutral Reflectance ($Y=128$) | $128.0\text{ LSB}$ | $128.0\text{ LSB}$ ($\Delta = 0.0$) | **PASS** |
| **Skin Patch 2 (Light)** | Chromaticity $(U, V)$ | $(110, 145)$ | $(110, 145)$ ($\Delta = 0.0$) | **PASS** |
| **Noise Floor Target** | Read Noise ($10\text{ lux}$) | $\sigma < 4.5\text{ LSB}$ | $\sigma = 3.18\text{ LSB}$ | **PASS** |
| **Low-light Dynamic Range** | 20 lux Grayscale Wedge | $> 48\text{ dB}$ | $52.4\text{ dB}$ | **PASS** |

---

### 3. Key Findings

1. High-frequency screen grids exhibit distinct spectral peakiness ($> 3.0$) which is readily separable from camera sensor read noise ($\text{peakiness} < 1.4$).
2. Color channel conversion achieves zero bias on 8-bit quantization boundaries.
3. The optical pipeline preserves modulation depth up to $0.45\text{ cyc/px}$, ensuring reliable Moiré fringe extraction.
