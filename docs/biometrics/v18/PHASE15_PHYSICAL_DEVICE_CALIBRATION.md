# PHASE 15 — GATE H: PHYSICAL CAMERA CALIBRATION AND OPTICAL HARNESS AUDIT

**Author:** Principal Hardware & Optical Biometric Systems Lead  
**Workspace:** `kelasagaara_v17`  
**Classification:** BLOCKED_NO_PHYSICAL_DEVICE (`productionBiometricCalibrationApproved = false`)  
**Release Posture:** CONTROLLED_TEST_BUILD_ONLY  
**Timestamp:** 2026-10-29  

---

## 1. Executive Discovery & Physical Device Inventory

In accordance with Phase 15 release controls, an automated physical device discovery probe was executed across all local hardware interfaces:

```bash
$ adb devices -l
List of devices attached
[EMPTY — 0 PHYSICAL DEVICES CONNECTED]
```

### Discovery Status: `BLOCKED_NO_PHYSICAL_DEVICE`

Under the immutable release controls of Phase 15:
> **"If no physical device is available, report `BLOCKED_NO_PHYSICAL_DEVICE`. Do not substitute emulator results for field calibration."**
> **"Do not approve production thresholds solely because software tests pass or a score such as `0.90` appears conservative."**

Consequently, **physical camera calibration remains an active release blocker**. Production release approval is **STRICTLY WITHHELD**, preserving:
- `productionBiometricCalibrationApproved = false`
- Release Posture: `CONTROLLED_TEST_BUILD_ONLY`

---

## 2. Why Emulators & Unit Tests Cannot Substitute for Physical Hardware

While the Kelasagara backend and Flutter suites pass 100% of automated tests (including ONNX inference, FIQA filters, and passive PAD algorithms), software test harnesses operate on synthetic or pre-recorded image frames. 

In production field operations across Karnataka gig workers, physical hardware introduces distinct physical and optical distortion modes that cannot be modeled in software:

```
[FIELD SENSOR NOISE MODES IN LOW-COST ANDROID OPTICS]
┌─────────────────────────────────┬────────────────────────────────────────────────────────┐
│ Hardware Distortion Mode        │ Physical Cause & Impact on Biometric Embeddings        │
├─────────────────────────────────┼────────────────────────────────────────────────────────┤
│ Rolling-Shutter Skew            │ High-speed worker hand motion or bus vibrations        │
│                                 │ skews 5-point landmark coordinates ($P$).              │
├─────────────────────────────────┼────────────────────────────────────────────────────────┤
│ Extreme Midday Backlighting     │ Harsh tropical sun behind worker causes severe lens    │
│ (Karnataka Sun > 80,000 lux)    │ flare, washing out periocular textures and IPD detail. │
├─────────────────────────────────┼────────────────────────────────────────────────────────┤
│ Fixed-Focus Lens Quantization   │ Low-cost (<₹8,000) Android front cameras lack autofocus,│
│ (< 5MP fixed focal plane)       │ resulting in optical blur outside a 35–45 cm range.   │
├─────────────────────────────────┼────────────────────────────────────────────────────────┤
│ Hardware ISP Noise Filtering    │ OEM-specific aggressive skin-smoothing algorithms      │
│ (aggressive noise gating)       │ destroy high-frequency facial gradients used by SFace. │
└─────────────────────────────────┴────────────────────────────────────────────────────────┘
```

Without empirical physical-device qualification across a representative hardware matrix, deploying static cosine thresholds ($\tau_{1:1} = 0.363, \tau_{\text{warn}} = 0.72, \tau_{\text{block}} = 0.90$) to uncalibrated phone sensors risks intolerable False Rejection Rates (FRR) or severe Failure-to-Acquire (FTA) spikes.

---

## 3. Approved Physical Device Field Protocol & Governance Plan

To unlock Gate H in a subsequent hardware validation phase, the field evaluation must strictly adhere to the following human-governed protocol:

### 3.1 Adult-Volunteer Consent & Governance Protocol
1. **Zero Real Worker / Aadhaar Data:** Testing must **never** use production worker images or government Aadhaar records.
2. **Voluntary Consented Cohort:** An experimental cohort of at least $N = 30$ adult volunteers representing diverse ages, skin reflectance (Fitzpatrick types III–VI), and genders.
3. **Explicit Consent & Revocation:** Participants sign an explicit, revocable consent form permitting transient research captures, with guaranteed cryptographic zeroization upon study completion.
4. **Isolated Storage:** All raw frame captures remain on encrypted local test rigs with zero connection to production Firestore databases.

### 3.2 Target Physical Device Hardware Matrix

When hardware becomes available, the evaluation must execute across the following representative device tiers:

| Tier | Representative Target Devices | Chipset / Architecture | Front Camera Specs | Target OS |
| :---: | :--- | :--- | :--- | :---: |
| **Tier 1 (Ultra-Budget)** | Redmi A2 / Realme C30 | MediaTek Helio G36 (arm64-v8a) | 5 MP, f/2.2, fixed focus | Android 13 (Go) |
| **Tier 2 (Mid-Range)** | Samsung Galaxy M14 / Redmi Note 12 | Exynos 1330 / Snapdragon 4 Gen 1 | 13 MP, f/2.0, autofocus | Android 14 |
| **Tier 3 (Enterprise)** | Google Pixel 7a / Samsung A54 | Tensor G2 / Exynos 1380 | 13 MP, f/2.2, ultrawide | Android 14 / 15 |

---

## 4. Required Field Capture Scenarios & Metrics

For each device tier, four environmental illumination conditions must be benchmarked:
1. **Direct Tropical Sunlight:** Outdoor midday ($\approx 80,000\text{ lux}$).
2. **Backlit Twilight:** Dusk / golden hour with sunlight behind subject ($\approx 2,500\text{ lux}$).
3. **Low-Light Indoor:** Fluorescent / LED room lighting ($\approx 150\text{ lux}$).
4. **Severe Dim Light:** Nighttime street lighting ($\approx 15\text{ lux}$).

### Metrics to Record:
- **Total Capture Attempts:** Total camera burst sequences initiated.
- **Failure-to-Acquire (FTA) Rate:** Percentage of attempts rejected by pre-inference FIQA ($\sigma^2_{\nabla^2 I} < 15.0$ or IPD $< 60\text{ px}$).
- **Retry Frequency:** Average number of capture attempts required per volunteer to achieve a valid enrollment.
- **Genuine Accept Rate (GAR) at Fixed FAR ($10^{-3}$):** Empirically observed verification success on registered volunteers.
- **Potential Duplicate Trigger Rate:** Frequency of legitimate lookalike warnings ($\cos \in [0.72, 0.89]$) generated by the candidate threshold.
- **P50 / P95 End-to-End Latency:** Wall-clock time from shutter tap to server enrollment confirmation.

---

## 5. Formal Separation of Failure Modes

The future physical test suite must strictly distinguish between camera failure and biometric algorithmic inaccuracy:

$$\text{Total System Failure Rate} = \text{FTA} + (1 - \text{FTA}) \times \text{FRR}$$

- **Failure-to-Acquire ($\text{FTA}$):** Optical or environmental failure (e.g., lens smudged, subject out of frame, illumination $< 15\text{ lux}$). The model is never invoked.
- **False Non-Match ($\text{FRR}$):** Algorithmic failure. High-quality face extracted, but similarity score fell below threshold ($\cos < 0.363$).
- **False Match ($\text{FAR}$):** Algorithmic security failure. Different individuals produce $\cos \ge 0.363$.

Conflating camera optical failure with algorithmic false-rejection produces erroneous threshold tuning.

---

## 6. Gate H Conclusion & Release Status

- **Device Discovery Probe:** Executed (`adb devices -l`). Zero physical devices connected.
- **Substitutions Rejected:** Refused to substitute synthetic data or emulators for physical optical calibration.
- **Gate Status:** **BLOCKED_NO_PHYSICAL_DEVICE**.
- **Impact on Release:** **PRODUCTION RELEASE STRICTLY BLOCKED**. System remains locked in `CONTROLLED_TEST_BUILD_ONLY` with `productionBiometricCalibrationApproved = false`.
