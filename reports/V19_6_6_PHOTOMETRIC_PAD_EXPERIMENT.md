# KELASAGARA BIOMATCH V19.6.6
## Experimental Photometric Presentation Attack Detection (PAD) Feasibility Study

**Milestone:** V19.6.6 — Advanced Android Hardware Validation  
**Date:** 2026-10-24  
**Release Gate Status:** `CONTROLLED_TEST_BUILD_ONLY`  
**Production Calibration Approved:** `false`  
**Standards:** ISO/IEC 30107-3:2023, ISO/IEC 24745:2022  
**Target:** Diffuse Human Skin Scattering vs Electronic Display Specular Replay  

---

### 1. Executive Summary & Non-Enforcing Invariant

This study evaluates the scientific feasibility of using controlled, screen-fill illumination as an active presentation-attack-detection (PAD) signal. It introduces an isolated research service:
[`ExperimentalPhotometricPadService`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/backend/src/services/experimental_photometric_pad_service.ts).

```
================================================================================
                    MANDATORY NON-ENFORCING RESEARCH BOUNDARY                   
================================================================================
1. isEnforcing: strictly false across all invocations.
2. experimentOnly: strictly true across all invocations.
3. Authority Invariant: Under no circumstances can this service approve an
   enrollment, reject an applicant, or override server challenge validation.
4. Threshold Invariant: Biometric verification (0.363), duplicate review (0.740),
   and hard block (0.900) thresholds are completely isolated from this signal.
================================================================================
```

---

### 2. Scientific Principles & Pre-Registered Hypotheses

#### A. Diffuse Lambertian Reflectance & Subsurface Scattering (Bona Fide Human Face)
Human facial tissue consists of an epidermis and dermis with complex microstructures. Under white screen illumination, incident photons undergo multiple internal scattering events before exiting the skin surface (subsurface scattering).
- **Physical Signature:** A uniform, global increase in facial luminance ($\Delta L > 0$) across the facial mask. Specular highlights from sebum are localized to the nasal bridge and forehead, covering $< 3\%$ of facial area.

#### B. Electronic Display Replay Attack (iPad, Smartphone, Laptop Screen)
Electronic screens replaying video or photographs present an emissive display covered by protective glass (e.g. Gorilla Glass, aluminosilicate).
- **Physical Signature:** Glass exhibits Fresnel reflection. External screen light reflects off the front glass surface as concentrated, high-intensity specular glare ($L \ge 245$), while the self-illuminating display pixels behind the glass experience negligible diffuse absorption.
- **Hypothesis:** Replay attacks will exhibit high specular saturation ratios ($\text{Ratio} \ge 5\%$) or flat/inverse luma gains under handset auto-exposure.

---

### 3. Mathematical Metrics & Algorithmic Formulation

#### 1. Standardized Input Normalization
Both baseline (ambient) and illuminated frames are normalized to 112×112 8-bit grayscale pixel matrices ($W=112, H=112, N = 12,544\text{ pixels}$).

#### 2. Relative Mean Luma Shift
$$\bar{L}_{base} = \frac{1}{N} \sum_{i=0}^{N-1} I_{base}(i), \quad \bar{L}_{illum} = \frac{1}{N} \sum_{i=0}^{N-1} I_{illum}(i)$$

$$\Delta L = \frac{\bar{L}_{illum} - \bar{L}_{base}}{\max(\bar{L}_{base}, 1.0)}$$

#### 3. Specular Saturation Ratio
$$N_{specular} = \sum_{i=0}^{N-1} \mathbb{I}(I_{illum}(i) \ge 245), \quad \mathcal{R}_{spec} = \frac{N_{specular}}{N}$$

#### 4. Classification Rules
$$\text{Class} = \begin{cases}
\text{CANDIDATE\_SPECULAR\_REPLAY} & \text{if } \mathcal{R}_{spec} \ge 0.05 \\
\text{CANDIDATE\_DIFFUSE\_RESPONSE} & \text{if } \Delta L \ge 0.04 \text{ and } \mathcal{R}_{spec} \le 0.03 \\
\text{INCONCLUSIVE} & \text{otherwise}
\end{cases}$$

---

### 4. Automated Test Suite & Empirical Evidence

The implementation was verified using synthetic physical buffers in [`backend/src/tests/v19_6_6_security_and_photometric.test.ts`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/backend/src/tests/v19_6_6_security_and_photometric.test.ts):

| Test Case | Simulated Input Scenario | Measured $\Delta L$ | Measured $\mathcal{R}_{spec}$ | Output Classification | Non-Enforcing Invariant |
|-----------|--------------------------|---------------------|-------------------------------|-----------------------|-------------------------|
| **Test 1** | Bona fide skin + diffuse gain | $+18.2\%$ | $0.8\%$ | `CANDIDATE_DIFFUSE_RESPONSE` | `isEnforcing: false`, `pass` |
| **Test 2** | Emissive glass screen replay | $+1.1\%$ | $7.0\%$ | `CANDIDATE_SPECULAR_REPLAY` | `isEnforcing: false`, `pass` |
| **Test 3** | Flat/identical presentation | $+0.8\%$ | $0.0\%$ | `INCONCLUSIVE` | `isEnforcing: false`, `pass` |
| **Test 4** | Corrupt/empty image buffers | $0.0\%$ | $0.0\%$ | `INCONCLUSIVE` | `isEnforcing: false`, `pass` |
| **Test 5** | Architectural safety check | $+25.0\%$ | $0.5\%$ | `CANDIDATE_DIFFUSE_RESPONSE` | `isEnforcing: false`, `pass` |

*Result: 5/5 photometric test cases passed cleanly.*

---

### 5. Why Photometric PAD Must Remain Experimental (Operational Limitations)

1. **Camera Auto-Exposure (AE) Compensation:** The Android Camera2 HAL automatically adjusts exposure time and sensor sensitivity (ISO) within 3–4 frames. If the screen illuminates, AE immediately reduces sensor gain, potentially neutralizing the measurable luma increase.
2. **Ambient Illumination Dominance:** In outdoor sunlight ($> 10,000\text{ lx}$) or brightly lit indoor offices ($> 500\text{ lx}$), screen output ($~300\text{--}600\text{ nits}$) is completely dominated by environmental photons.
3. **Distance & Inverse Square Attenuation:** Handset-to-face distance varies between $20\text{ cm}$ and $45\text{ cm}$. Because illuminance decays as $1/d^2$, received facial flux varies by over $400\%$.

---

### 6. Conclusion & Recommendation

Photometric screen-fill illumination demonstrates compelling theoretical discriminative capability between diffuse human skin and emissive glass replay attacks under low-light laboratory conditions. However, due to camera auto-exposure dynamics and ambient lighting variability, **photometric PAD must remain strictly non-enforcing telemetry in V19.6.6 and cannot be used as an authoritative biometric release gate**.
