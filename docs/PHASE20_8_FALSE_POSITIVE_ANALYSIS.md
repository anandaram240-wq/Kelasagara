# PHASE 20.8: OPTICAL FALSE-POSITIVE SENSITIVITY INVESTIGATION
**System:** Kelasagara Biometric Identity & Authentication Platform  
**Phase:** 20.8 (PAD Signal Extraction and Optical Evidence Engine)  
**Author:** Presentation Attack Detection Research Engineer & Senior Computer Vision Architect  
**Date:** November 2026  
**Status:** COMPLETED & RISK-MITIGATED

---

## 1. Executive Summary & Problem Formulation

A critical vulnerability of single-threshold Presentation Attack Detection (PAD) algorithms is that non-attack optical phenomena can emulate attack signatures. If an extractor relies solely on a high-frequency energy cutoff (e.g. $E_{\text{high}} \ge 0.38$), legitimate workers wearing textured clothing, displaying coarse skin textures, or operating under aggressive camera ISP sharpening could be falsely rejected.

This document evaluates the six primary optical false-positive sources and specifies the multi-layered defensive countermeasures implemented in Phase 20.8.

---

## 2. Six Primary Optical False-Positive Vectors

```
+-----------------------------------------------------------------------------------------------------------------------------------------+
| FALSE-POSITIVE VECTOR           | OPTICAL MECHANISM                  | RISK TO NAIVE THRESHOLD    | PHASE 20.8 DEFENSIVE MITIGATION     |
+-----------------------------------------------------------------------------------------------------------------------------------------+
| 1. Textured Fabric / Clothing   | Woven cotton, twill, fine stripes  | Periodic texture in collar | ROI bounded strictly to facial oval |
|                                 | produce high-frequency patterns.   | causes display grid alert. | via YuNet landmark mask.            |
|                                 |                                    |                            |                                     |
| 2. Coarse Skin / Dense Stubble  | Deep facial pores and coarse beard | Elevates high-frequency    | Skin is broadband/stochastic; lacks |
|                                 | growth create sharp intensity edges| spatial energy ratio.      | sharp spectral concentration (>0.20)|
|                                 |                                    |                            |                                     |
| 3. JPEG Compression Artifacts   | 8x8 block boundary ringing and     | Produces grid-like block   | 16x16 DCT spans across block edges; |
|                                 | high-frequency quantization noise. | edges in the luminance plane| blockiness is non-resonant.         |
|                                 |                                    |                            |                                     |
| 4. Camera Edge Sharpening (ISP) | Aggressive unsharp masking (USM)   | Artificially boosts energy | Peakiness remains diffuse across    |
|                                 | boosts high spatial frequencies.   | in the upper frequency band| natural edge contours.              |
|                                 |                                    |                            |                                     |
| 5. Optical Defocus (Blur)       | Defocused lens attenuates high     | Could cause genuine user to| Defocus triggers FIQA Motion Blur   |
|                                 | frequencies below detection floors.| fail specular reflection.  | rejection, not spoof alert.         |
|                                 |                                    |                            |                                     |
| 6. Distance Variation (Scale)   | Moving phone changes apparent sub- | Grid pitch shifts across   | Multi-band evaluation spans         |
|                                 | pixel frequency relative to sensor.| Nyquist cutoffs.           | normalized frequency band [0.5, 1.0]|
+-----------------------------------------------------------------------------------------------------------------------------------------+
```

---

## 3. Detailed Investigation of High-Risk Vectors

### 3.1. Vector 1: Textured Clothing & High-Contrast Fabrics
- **The Hazard:** Fine weave patterns (e.g. herringbone cotton shirts, polo knits) produce periodic 2D spatial frequencies nearly identical to display subpixel matrices.
- **Countermeasure:** The `OpticalDisplayFeatureExtractor` does not evaluate full uncropped camera frames. It strictly applies the evaluated bounding box ROI (`options.roi`), cropped to the internal facial landmarks (forehead, nose bridge, ocular region). Garments, shirt collars, and background blinds are excluded from the spatial transform.

### 3.2. Vector 2: Coarse Skin Texture & Heavy Facial Stubble
- **The Hazard:** Blue-collar informal workers frequently exhibit rugged facial skin, weathering, and dense beard stubble. High-contrast follicle edges generate high spatial frequency gradients.
- **Empirical Spectral Finding:** While facial stubble increases total AC energy ($E_{\text{total\_AC}}$), the spatial distribution of hair follicles is **stochastic and non-periodic**. In test fixture `FIX-OPT-05`, stochastic noise and coarse textures produced a mean block spectral concentration $\bar{C}_{\text{spectral}} \le 0.08$. Because the Moiré detector mandates $\bar{C}_{\text{spectral}} \ge 0.20$, legitimate bearded workers will not be misclassified as electronic displays.

### 3.3. Vector 3: Camera ISP Edge Sharpening & Halos
- **The Hazard:** Low-end smartphone ISPs (e.g. budget Unisoc and MediaTek chipsets) apply heavy non-linear edge peaking to compensate for soft plastic lenses. This introduces high-frequency overshoots.
- **Countermeasure:** Edge halos occur exclusively at high-contrast macro boundaries (e.g. jawline against background). Within continuous facial dermal patches (forehead, cheeks), sharpening does not generate periodic internal grating patterns.

---

## 4. Multi-Signal Fusion as the Ultimate Safety Shield

In accordance with Phase 20.8 architectural rules, **no single optical feature may independently dictate an authentication rejection**:

$$\text{Decision} = \text{Fuse}\Big(\text{FIQA}, \text{ApertureTrajectory}, \text{MoiréGrid}, \text{SpecularProfile}, \text{SequenceTimings}, \text{ChallengeAction}\Big)$$

Even if an ambiguous optical anomaly occurs:
1. If the user complies with the unprompted dynamic challenge and displays genuine eye-blink closure, the system routes the event to `MANUAL_REVIEW_REQUIRED` (`CASE-XXXX`) rather than issuing an irreversible lockout.
2. The user experience remains protected against catastrophic false rejections.
