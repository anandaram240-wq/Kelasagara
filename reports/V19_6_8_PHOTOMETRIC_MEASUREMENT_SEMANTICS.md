# KELASAGARA BIOMATCH V19.6.8: PHOTOMETRIC MEASUREMENT SEMANTICS & SCIENTIFIC AUDIT
**Date:** 2026-10-24  
**Author:** Antigravity Senior Biometrics & Computer Vision Research Engineer  
**Baseline Commit:** `9b29fb9` (V19.6.7)  
**Target File:** [`backend/src/services/experimental_photometric_pad_service.ts`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/backend/src/services/experimental_photometric_pad_service.ts)  
**Safety Status:** `CONTROLLED_TEST_BUILD_ONLY` | `isEnforcing: false` | `experimentOnly: true`

---

## 1. Executive Summary & Semantic Correction

In earlier milestones (V19.6.6 and V19.6.7), an experimental photometric presentation-attack-detection (PAD) feasibility service was introduced to observe client-side screen-flash illumination changes. However, an engineering audit identified a critical scientific defect in measurement nomenclature:

- **The Defect:** Pixels with 8-bit luma $\ge 245$ were counted and reported as `specularPixelCount`, and their fraction was reported as `specularSaturationRatio`.
- **The Scientific Reality:** Counting pixels with intensity $\ge 245$ merely measures **high-luminance pixel saturation (sensor clipping)**. It does **NOT** measure Fresnel optical glass reflectance, polarization, or surface microstructure. Calling this metric "specular saturation" created a false implication of physical proof that display replay had been detected.
- **The V19.6.8 Correction:** All physical measurements have been renamed to `highLumaPixelCount` and `highLumaPixelRatio`. Legacy names are retained strictly as `@deprecated` aliases to preserve backward compatibility.
- **Image Quality Verification:** The quality guard has been extended to evaluate **both** baseline and illuminated frames for severe underexposure, overexposure, and contrast span.

---

## 2. Mathematical Formulations & Measurement Semantics

All frames are cropped to the standardized facial region and decoded to an uncompressed 8-bit single-channel grayscale raster of dimensions $112 \times 112$ ($N = 12,544$ pixels).

### 2.1 Grayscale Luminance Conversion
For each pixel $i \in \{1, \dots, N\}$, the 8-bit ITU-R BT.601 luma $L(i)$ is computed by the image decoding pipeline:
$$L(i) = \text{round}(0.299 \cdot R_i + 0.587 \cdot G_i + 0.114 \cdot B_i) \in [0, 255]$$

### 2.2 Baseline and Illuminated Mean Luminance
The spatial mean luma for baseline frame $\mathbf{L}_{base}$ and illuminated frame $\mathbf{L}_{illum}$ are defined as:
$$\bar{L}_{base} = \frac{1}{N} \sum_{i=1}^N L_{base}(i) \in [0, 255]$$
$$\bar{L}_{illum} = \frac{1}{N} \sum_{i=1}^N L_{illum}(i) \in [0, 255]$$

### 2.3 Luminance Deltas
- **Absolute Luma Delta ($\Delta L_{abs}$):**
  $$\Delta L_{abs} = \bar{L}_{illum} - \bar{L}_{base} \in [-255, 255]$$
  Scale: 8-bit luma intensity units.
- **Relative Luma Delta ($\Delta L_{rel}$):**
  $$\Delta L_{rel} = \frac{\Delta L_{abs}}{\max(\bar{L}_{base}, 1.0)}$$
  Scale: Dimensionless relative ratio. The denominator floor $\max(\bar{L}_{base}, 1.0)$ eliminates division-by-zero, NaN, and $\pm\infty$ on dark frames.

### 2.4 Physical High-Luma Pixel Saturation
High-luma pixels are defined strictly as pixels whose intensity meets or exceeds the clipping threshold:
$$N_{\ge 245} = \sum_{i=1}^N \mathbb{I}(L_{illum}(i) \ge \tau_{cutoff}), \quad \text{where } \tau_{cutoff} = 245$$

The High-Luma Pixel Ratio is:
$$R_{high\_luma} = \frac{N_{\ge 245}}{N} \in [0.0, 1.0]$$

---

## 3. Physical Critique: High-Luma Pixel Ratio vs. Specular Fresnel Reflection

| Dimension | Physical High-Luma Ratio ($R_{high\_luma}$) | True Specular Glass Reflection |
|:---|:---|:---|
| **What is measured** | Digital sensor clipping ($L \ge 245$) in 8-bit space | Polarized, angle-dependent Fresnel reflection ($R = \left|\frac{n_1 - n_2}{n_1 + n_2}\right|^2$) |
| **Causes of saturation** | • Direct sunlight or overhead lighting<br>• Camera auto-exposure latency/overshoot<br>• Sebum oil on nasal bridge or forehead<br>• Electronic display specular reflection | • Smooth dielectric boundary (glass screen $n \approx 1.5$)<br>• Planar mirror-like wavefront coherence |
| **False positive vulnerabilities** | Normal oily skin, sweat, shiny makeup, ambient light reflections | Minimally affected if cross-polarizers or bidirectional reflectance (BRDF) are used |
| **False negative vulnerabilities** | Matte anti-glare screen protectors, low screen brightness | Diffuse screen reflections without clipping |
| **Scientific validity status** | Objective mathematical property of the captured image buffer | **Unproven hypothesis** without physical spectrophotometric calibration |

> [!WARNING]
> High-luma pixel counting must **never** be cited as evidence of liveness or presentation attack detection in production certification. It remains strictly an unvalidated telemetry exploratory signal.

---

## 4. Enhanced Dual-Frame Image Quality Guards

In V19.6.7, quality checks inspected only the baseline frame. In V19.6.8, quality guards inspect **both** the baseline and illuminated frames:

```typescript
const baselineUnderexposed = baselineLuma < 15;
const baselineOverexposed = baselineLuma > 240;
const baselineHasContrast = maxBase - minBase >= 20;

const illuminatedUnderexposed = illuminatedLuma < 15;
const illuminatedOverexposed = illuminatedLuma > 240;
const illuminatedHasContrast = maxIllum - minIllum >= 20;

const isSeverelyUnderexposed = baselineUnderexposed || illuminatedUnderexposed;
const isSeverelyOverexposed = baselineOverexposed || illuminatedOverexposed;
const hasValidContrast = baselineHasContrast && illuminatedHasContrast;
const isQualityAcceptable = !isSeverelyUnderexposed && !isSeverelyOverexposed;
```

### Quality Decision Table
| Condition | Quality Indicator | Interpretation Decision | Rationale |
|:---|:---:|:---:|:---|
| $\bar{L}_{base} < 15$ or $\bar{L}_{illum} < 15$ | `isSeverelyUnderexposed: true` | `INCONCLUSIVE` | Underexposure causes sensor noise floor dominance |
| $\bar{L}_{base} > 240$ or $\bar{L}_{illum} > 240$ | `isSeverelyOverexposed: true` | `INCONCLUSIVE` | Sensor blowout prevents differential measurement |
| $\max(L) - \min(L) < 20$ in either frame | `hasValidContrast: false` | Telemetry flag | Flat uniform image indicates occlusion or camera error |

---

## 5. Backward Compatibility & Code Deprecation Strategy

To ensure existing test suites and telemetry parsers remain stable, the following deprecation mapping is active in [`experimental_photometric_pad_service.ts`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/backend/src/services/experimental_photometric_pad_service.ts):

| New Canonical Field / Constant | Deprecated Alias | Type | Status |
|:---|:---|:---:|:---:|
| `highLumaPixelCount` | `specularPixelCount` | `number` | Maintained for backward compatibility |
| `highLumaPixelRatio` | `specularSaturationRatio` | `number` | Maintained for backward compatibility |
| `HIGH_LUMA_CUTOFF` ($245$) | `SPECULAR_LUMA_CUTOFF` | `number` | Deprecated static constant |
| `CANDIDATE_DIFFUSE_HIGH_LUMA_RATIO_MAX` ($0.03$) | `CANDIDATE_DIFFUSE_SPECULAR_RATIO_MAX` | `number` | Deprecated static constant |
| `CANDIDATE_REPLAY_HIGH_LUMA_RATIO_MIN` ($0.05$) | `CANDIDATE_REPLAY_SPECULAR_RATIO_MIN` | `number` | Deprecated static constant |

---

## 6. Verification and Non-Enforcement Invariants

The V19.6.8 test suite [`backend/src/tests/v19_6_8_photometric_semantics_and_safety.test.ts`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/backend/src/tests/v19_6_8_photometric_semantics_and_safety.test.ts) verified:
1. `highLumaPixelCount` and `highLumaPixelRatio` exactly equal their deprecated aliases.
2. Illuminated-frame overexposure ($\bar{L}_{illum} = 245$) is flagged as `isSeverelyOverexposed: true` and yields `classification: "INCONCLUSIVE"`.
3. Illuminated-frame underexposure ($\bar{L}_{illum} = 10$) is flagged as `isSeverelyUnderexposed: true` and yields `classification: "INCONCLUSIVE"`.
4. Contrast span is independently tracked across baseline and illuminated frames.
5. Zero-luma baseline frames compute without division by zero.
6. The service is strictly non-enforcing (`isEnforcing: false`, `experimentOnly: true`), leaving `verificationThreshold` ($0.363$), `duplicateThreshold` ($0.740$), and `duplicateBlockThreshold` ($0.900$) untouched.
