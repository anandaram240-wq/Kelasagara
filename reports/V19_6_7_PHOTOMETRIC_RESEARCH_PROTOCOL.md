# KELASAGARA BIOMATCH V19.6.7
## Pre-Registered Scientific Research Protocol: Experimental Photometric Presentation Attack Detection

**Milestone:** V19.6.7 — Evidence Integrity & Scientific Audit  
**Date:** 2026-10-24  
**Release Gate Status:** `CONTROLLED_TEST_BUILD_ONLY`  
**Production Calibration Approved:** `false`  
**Standards Alignment:** ISO/IEC 30107-3:2023, ISO/IEC 19794-5:2025, ISO/IEC 24745:2022  
**Document Nature:** Pre-Registered Experimental Protocol (Not a Report of Completed Physical Experiments)  

---

### 1. Narrow Scientific Hypothesis & Falsifiability Statement

#### Hypothesis
> *"Controlled changes in smartphone screen-fill illumination may produce measurable image features (such as relative luminance change and specular saturation ratio) that differ between some genuine live-face captures and some electronic-display replay captures under controlled conditions."*

#### Explicit Falsifiability & Known Limitations
This hypothesis may be falsified if:
1. Smartphone camera Auto-Exposure (AE) and Auto-White-Balance (AWB) dynamically compensate for screen brightness increases faster than the frame capture interval, dampening the observable skin luminance delta.
2. High ambient illuminance ($> 500\text{ lx}$) overpowers the luminous flux of standard mobile displays ($~300\text{--}600\text{ nits}$), reducing the signal-to-noise ratio to indistinguishable levels.
3. Anti-reflective coatings or matte screen protectors on replay devices attenuate specular glass glare below detection cutoffs.
4. Physical variations in facial oiliness, cosmetics, skin tone (Fitzpatrick IV–VI), or eyeglasses cause live subjects to exhibit specular glares resembling screen reflections.

**Non-Generalization Warning:** Evidence gathered from electronic display replay captures cannot be used to infer protection against 2D printed paper attacks, silicone 3D masks, deepfake synthetic video injections, or virtual camera emulator bypasses.

---

### 2. Operational & Physical Variables

#### A. Independent Variables
1. **Presentation Type:**
   - Bona fide consenting live participant.
   - Electronic display replay: Smartphone (AMOLED), Tablet (IPS LCD), Laptop screen.
2. **Illumination Condition:**
   - Baseline frame ($I_0$): Natural ambient light, display at default OS brightness.
   - Illuminated frame ($I_1$): Controlled white screen-fill overlay at application-scoped brightness = 1.0.
3. **Ambient Lighting Level (Measured via calibrated lux meter at subject plane):**
   - Dim / Low-light: $5\text{--}15\text{ lx}$
   - Typical indoor office: $150\text{--}300\text{ lx}$
   - Bright indoor / Daylit: $500\text{--}1,000\text{ lx}$
4. **Subject Distance:**
   - Standard: $30\text{ cm} \pm 2\text{ cm}$
   - Boundary checks: $20\text{ cm}$ and $45\text{ cm}$

#### B. Dependent Variables & Mathematical Formulations
All calculations operate strictly on standardized 112×112 8-bit grayscale pixel matrices ($N = 12,544\text{ pixels}$):

1. **Mean 8-Bit Luminance ($L$):**
   $$\bar{L}_{base} = \frac{1}{N} \sum_{i=0}^{N-1} I_{base}(i), \quad \bar{L}_{illum} = \frac{1}{N} \sum_{i=0}^{N-1} I_{illum}(i) \quad [0, 255]$$

2. **Absolute Luminance Delta ($\Delta L_{abs}$):**
   $$\Delta L_{abs} = \bar{L}_{illum} - \bar{L}_{base} \quad [-255, 255]$$

3. **Relative Luminance Delta ($\Delta L_{rel}$):**
   $$\Delta L_{rel} = \frac{\bar{L}_{illum} - \bar{L}_{base}}{\max(\bar{L}_{base}, 1.0)} \quad [\text{dimensionless ratio}]$$

4. **Specular Saturation Pixel Count ($N_{spec}$):**
   $$N_{spec} = \sum_{i=0}^{N-1} \mathbb{I}(I_{illum}(i) \ge 245)$$

5. **Specular Saturation Ratio ($\mathcal{R}_{spec}$):**
   $$\mathcal{R}_{spec} = \frac{N_{spec}}{N} \quad [0.0, 1.0]$$

---

### 3. Subject Privacy, Consent & Data Governance

In strict accordance with the **Digital Personal Data Protection Act (DPDPA) 2023** and **ISO/IEC 24745:2022**:
1. **Informed Consent:** Explicit, voluntary consent in Kannada and English must be executed before capturing any research participant.
2. **Data Minimization:** No raw video streams or unaligned high-resolution camera frames may be retained in research datasets.
3. **Transient Feature Extraction:** Frames are converted into anonymized numeric feature vectors (`baselineLuma`, `deltaLuma`, `specularRatio`) on-device or in memory.
4. **Immediate Deletion Policy:** Temporary test frames must be deleted within 24 hours of protocol completion. Replay videos of consented subjects must not be stored on public repositories or unsecured storage buckets.

---

### 4. Experimental Presentation Matrix & Protocols

| Presentation Condition | Subject / Target Setup | Capture Distance | Environmental Lux | Trials per Subject | Specific Confounders Observed |
|------------------------|------------------------|------------------|-------------------|-------------------|--------------------------------|
| **C1: Bona Fide Baseline** | Consenting live subject, no glasses | $30\text{ cm}$ | $150\text{--}300\text{ lx}$ | 10 | Natural eye micro-movement |
| **C2: Bona Fide Low-Light** | Consenting live subject | $30\text{ cm}$ | $5\text{--}15\text{ lx}$ | 10 | Camera shutter lag & ISO noise |
| **C3: Bona Fide Eyeglasses**| Consenting live subject wearing spectacles | $30\text{ cm}$ | $150\text{--}300\text{ lx}$ | 10 | Spectacle lens reflections |
| **C4: Replay (OLED Phone)** | High-res video of subject on iPhone/Pixel | $30\text{ cm}$ | $150\text{--}300\text{ lx}$ | 10 | Glass Fresnel reflection, display refresh |
| **C5: Replay (LCD Tablet)** | High-res video of subject on iPad/Galaxy Tab | $30\text{ cm}$ | $150\text{--}300\text{ lx}$ | 10 | Anti-glare coating differences |
| **C6: Replay (Angle Tilt)** | Electronic display tilted at $15^\circ$ yaw | $30\text{ cm}$ | $150\text{--}300\text{ lx}$ | 10 | Directional specular beam shift |

---

### 5. Statistical Analysis & Reporting Plan

1. **Separation of Cohorts:**
   - **Exploratory Cohort (30% of data):** Used solely to inspect distributions, verify quality indicator thresholds, and refine hypotheses.
   - **Confirmatory Cohort (70% of data):** Held out; tested once against pre-registered hypotheses with zero parameter re-tuning.
2. **Distribution Characterization:**
   - Report Mean, Standard Deviation, Median, Interquartile Range (IQR), and 95% Confidence Intervals for $\Delta L_{rel}$ and $\mathcal{R}_{spec}$ separately for live and replay presentations.
3. **Receiver Operating Characteristic (ROC):**
   - Plot True Positive Rate (bona fide passed) vs False Positive Rate (spoof passed).
   - Report Attack Presentation Classification Error Rate (APCER) and Bona Fide Presentation Classification Error Rate (BPCER) per ISO/IEC 30107-3.
4. **Inconclusive Band Definition:**
   - Define regions where live and replay distributions overlap (e.g. $|\Delta L_{rel}| < 0.03$ under high ambient light) as explicitly `INCONCLUSIVE`. Such samples must not result in security bypasses or unfair user lockouts.

---

### 6. Protocol Status

- **Status:** **PRE-REGISTERED & PENDING PHYSICAL DEVICE EXECUTION**
- Under no circumstances will software mocks or synthetic test buffers be reported as physical validation results.
