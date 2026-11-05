# PHASE 20.8: 2D SPATIAL FREQUENCY & MOIRÉ EXTRACTION SPECIFICATION
**System:** Kelasagara Biometric Identity & Authentication Platform  
**Phase:** 20.8 (PAD Signal Extraction and Optical Evidence Engine)  
**Component:** `OpticalDisplayFeatureExtractor`  
**Document Code:** SPEC-MOIRE-MATH-2026-008  
**Author:** Senior Computer Vision Engineer & Mobile Camera Signal Processing Architect  
**Date:** November 2026  
**Status:** SPECIFICATION RATIFIED & IMPLEMENTED

---

## 1. Physical Principle & Optical Phenomenon

When an electronic display (such as an LCD or OLED panel on a tablet or smartphone) is imaged by a smartphone camera sensor, an optical interference pattern known as **Moiré aliasing** is produced.

This phenomenon occurs because of the spatial superposition of two discrete periodic structures:
1. **The Display Subpixel Matrix:** The periodic grid of RGB emitters with spatial pitch $p_{\text{display}}$ (typically $250 - 500\,\text{PPI}$).
2. **The Camera Sensor Matrix:** The Bayer color filter array (CFA) with sensor pixel pitch $p_{\text{sensor}}$ (typically $1.0 - 1.4\,\mu\text{m}$).

When the camera's spatial sampling frequency $f_s = 1 / p_{\text{sensor}}$ is on the same order of magnitude as the demagnified display grid frequency $f_d$, high-frequency spatial beat frequencies alias into the sensor's Nyquist band:
$$f_{\text{alias}} = |f_d - k f_s|$$

Living human facial tissue exhibits continuous, diffuse optical scattering across low-to-mid spatial frequencies with a natural power spectral density (PSD) decaying approximately as $1/f^2$. It produces zero periodic emitter grids.

---

## 2. Mathematical Formulation via 2D Discrete Cosine Transform (DCT-II)

To extract this signal with deterministic numerical stability and sub-millisecond execution without requiring floating-point FFT libraries or external C++ binaries, `OpticalDisplayFeatureExtractor` implements a block-based **2D Discrete Cosine Transform (DCT-II)**.

### 2.1. 2D Block Decomposition
Let the input grayscale luminance plane be $I(x, y)$ of dimensions $W \times H$. Within the evaluated Region of Interest (ROI), non-overlapping square blocks $B_k$ of size $N \times N$ ($N = 16\,\text{pixels}$) are extracted:
$$B_k = \{ I(x_0 + x, y_0 + y) : 0 \le x < N, 0 \le y < N \}$$

### 2.2. Fast Separable 2D DCT-II
For each block $B_k$, the 2D DCT coefficient matrix $F_k(u, v)$ is computed via separable 1D transforms:
$$F_k(u, v) = \alpha(u) \alpha(v) \sum_{x=0}^{N-1} \sum_{y=0}^{N-1} B_k(x, y) \cos\left[\frac{(2x+1)u\pi}{2N}\right] \cos\left[\frac{(2y+1)v\pi}{2N}\right]$$
where:
$$\alpha(0) = \sqrt{\frac{1}{N}}, \quad \alpha(k) = \sqrt{\frac{2}{N}} \quad (\text{for } k > 0)$$

The DC coefficient $F_k(0, 0)$ represents the mean block luminance, while all coefficients with $(u > 0 \lor v > 0)$ represent AC spatial frequency components.

---

## 3. High-Frequency Bandpass & Energy Metrics

### 3.1. Normalized Frequency Metric
The radial spatial frequency $\omega(u, v)$ is defined on a normalized scale $[0.0, 1.0]$:
$$\omega(u, v) = \frac{u + v}{2(N - 1)}$$

The high-frequency band $\Omega_{\text{high}}$ is defined by a normalized cutoff frequency $\omega_{\text{cutoff}} = 0.50$:
$$\Omega_{\text{high}} = \{ (u, v) : \omega(u, v) \ge 0.50 \}$$

### 3.2. Total AC Energy and High-Frequency Energy Ratio
For each block, the total AC energy and high-frequency energy are accumulated:
$$E_{\text{total\_AC}} = \sum_{k} \sum_{(u, v) \ne (0, 0)} |F_k(u, v)|^2$$
$$E_{\text{high}} = \sum_{k} \sum_{(u, v) \in \Omega_{\text{high}}} |F_k(u, v)|^2$$

The **Spatial High-Frequency Energy Ratio** is:
$$R_{\text{high}} = \begin{cases} \min\left(1.0, \frac{E_{\text{high}}}{E_{\text{total\_AC}}}\right), & \text{if } E_{\text{total\_AC}} \ge 1.0 \\ 0.0, & \text{if } E_{\text{total\_AC}} < 1.0 \end{cases}$$

---

## 4. Spectral Concentration & Anti-Noise Periodicity Filter

A naive high-frequency energy ratio alone can produce false positives on broadband random noise (e.g. high ISO sensor grain). In white noise, energy is spread uniformly across all 112 high-frequency bins in a $16 \times 16$ block, yielding $R_{\text{high}} \approx 0.50$.

To definitively distinguish a periodic emitter grid from broadband noise, the extractor evaluates the **Mean Block Spectral Concentration Ratio**:

$$\text{Concentration}_k = \frac{\max_{(u, v) \in \Omega_{\text{high}}} |F_k(u, v)|^2}{\sum_{(u, v) \in \Omega_{\text{high}}} |F_k(u, v)|^2}$$
$$\bar{C}_{\text{spectral}} = \frac{1}{K} \sum_{k=1}^{K} \text{Concentration}_k$$

### Physical Calibration Bounds:
1. **Electronic Display Grid (Moiré):** Energy is concentrated in a discrete harmonic peak corresponding to the subpixel pitch:
   $$\bar{C}_{\text{spectral}} \ge 0.25 - 0.65$$
2. **Broadband Sensor Noise / Film Grain:** Energy is dispersed uniformly across all high-frequency bins:
   $$\bar{C}_{\text{spectral}} \le 0.04 - 0.09$$
3. **Smooth Human Skin:** High frequency energy is near zero:
   $$R_{\text{high}} < 0.20, \quad E_{\text{high}} \approx 0$$

---

## 5. Formal Decision Rule

An affirmative electronic display grid (Moiré pattern) is declared if and only if:
$$\text{MoireDetected} = \left( E_{\text{total\_AC}} \ge 1.0 \right) \land \left( R_{\text{high}} \ge 0.38 \right) \land \left( \bar{C}_{\text{spectral}} \ge 0.20 \right)$$

This compound decision rule guarantees robust rejection of electronic screen replays while eliminating false positives from sensor noise, camera sharpening, and flat regions.
