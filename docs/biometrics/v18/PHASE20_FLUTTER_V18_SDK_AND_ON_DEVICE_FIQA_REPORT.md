# KELASAGARA BIOMETRIC ENGINE V18 — PHASE 20 REPORT
## Flutter V18 Client SDK, On-Device ISO/IEC 29794-5 Optical FIQA Pre-Calculator & Live Field Calibration Mode

**Date:** October 29, 2026  
**Auditor:** Principal Mobile Biometrics Engineer & Client SDK Architect  
**Repository:** `/Users/ananda/KELASAGARA MAJOR PROJECT/kelasagaara_v17`  
**Git Branch:** `ui/polish-v1` | **HEAD Commit (pre-commit):** `96cef8b`  
**Verification Baseline:** 🟢 **665 / 665 Backend Tests Passing (125 Suites)** | 🟢 **178 / 178 Flutter Tests Passing (18 Files)**  
**Release Classification:** `CONTROLLED_TEST_BUILD_ONLY`  
**Production Calibration Gate:** `productionBiometricCalibrationApproved = false`

---

## 1. Executive Summary

Phase 20 completes the client-side integration of the Kelasagara Biometric Engine V18 by providing a pure-Dart mobile client SDK and on-device image quality assessment engine in [`lib/biometrics/biometric_v18_client_and_fiqa.dart`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/lib/biometrics/biometric_v18_client_and_fiqa.dart).

Prior to Phase 20, mobile handsets lacked on-device optical telemetry, requiring raw server transmissions even for out-of-focus, sun-clipped, or beauty-filter smoothed frames. With Phase 20:
1. **On-Device ISO/IEC 29794-5 Optical FIQA Pre-Filtering:** Mobile devices compute Discrete Laplacian focus variance, highlight clipping ratios, skin micro-contrast energy, and rolling-shutter shear directly from the $112 \times 112$ camera luma buffer before network transmission, filtering bad frames client-side with zero data cost.
2. **Unified V18 HTTP Client SDK:** Connects mobile apps to the live `/api/v18/biometrics` endpoints mounted in Phase 19, cleanly handling `200 COMMITTED`, `409 DUPLICATE_INVESTIGATION_PENDING` (with privacy-safe `auditTicketId`), `422 OPTICAL_FIQA_REJECTED`, and `503 HSM_REVOKED_LOCKDOWN`.
3. **Live Field Calibration Bridge:** Handsets can now capture and submit physical biometric frames across Tier 1 (Redmi A2), Tier 2 (Galaxy M14), and Tier 3 (Pixel 7a) directly to `/api/v18/biometrics/calibration/capture` and check `/calibration/gate-h-status`.

---

## 2. On-Device FIQA Algorithmic Specifications

```mermaid
flowchart TD
    Camera[Camera YUV420 Frame] --> LumaCrop[112x112 Aligned Luma Crop]
    LumaCrop --> Laplacian["3x3 Laplacian Kernel (Focus Sharpness)"]
    LumaCrop --> Clipping["Highlight Saturation >= 250 (Sunlight Clip)"]
    LumaCrop --> Texture["Micro-Contrast Sum (ISP Smoothing Detection)"]
    LumaCrop --> Skew["Inter-Frame Affine Shear (Rolling-Shutter)"]

    Laplacian --> Decision{"passesClientPreCheck"}
    Clipping --> Decision
    Texture --> Decision
    Skew --> Decision

    Decision -->|Fail (< 45 sharp, > 0.12 clip, < 0.18 texture)| LocalReject["Prompt User: Reposition / Clean Lens (Zero Network Call)"]
    Decision -->|Pass| ClientSDK["BiometricV18UnifiedClient.submitUnifiedEnrollment()"]
```

### 2.1 The 4 Mathematical Quality Gates

| Metric | Mathematical Kernel / Formula | Threshold | Physical Failure Detected |
| :--- | :--- | :--- | :--- |
| **Laplacian Sharpness** | $\sigma_{\nabla^2}^2 = \frac{1}{|I|} \sum (\nabla^2 I - \mu)^2$ using 4-neighbor kernel $[0, 1, 0; 1, -4, 1; 0, 1, 0]$ | $\ge 45.0$ | Fixed-focus lens blur, dirty protective glass, or hand motion blur |
| **Highlight Clipping Ratio** | $\frac{1}{N} \sum [I(x,y) \ge 250]$ | $\le 0.12$ | Overexposure from $>80,000\text{ lux}$ harsh Indian midday sunlight |
| **Skin Texture Energy** | $\frac{1}{|I|} \sum |\nabla^2 I| / 255.0$ | $\ge 0.18$ | OEM vendor aggressive "beauty mode" or Gaussian skin-smoothing filters |
| **Rolling Shutter Skew** | $\theta = \arctan(\Delta x / \Delta y)$ between burst frames | $\le 4.5^\circ$ | CMOS sensor rolling-shutter spatial skew on rapid hand movement |

---

## 3. Test Evidence & Benchmark Register

### 3.1 Flutter Test Execution (`flutter test`)

```text
00:11 +178: All tests passed!
```
- Total test files: 18 files across `test/biometric*`, `test/client*`, `test/dense*`, `test/profile*`, `test/v19*`, `test/face*`.
- **Phase 20 Suite (`biometric_v18_unified_client_and_fiqa_test.dart`):**
  - `PHASE20-01`: Verified on-device luma plane FIQA calculator. Sharp textured frame passed all 4 gates ($\ge 45.0$ sharpness, $\le 0.12$ clip, $\ge 0.18$ texture); flat blurry frame failed with `ERR_OPTICAL_MOTION_OR_LENS_BLUR`; 30% saturated frame failed with `ERR_HARSH_SUNLIGHT_HIGHLIGHT_CLIPPING`.
  - `PHASE20-02`: Tested `BiometricV18UnifiedClient` with `MockClient`. Verified proper deserialization of HTTP 200 commit (epoch 1, batch size 21), HTTP 409 privacy-safe audit ticket (`auditTicketId: AUD_TKT_99A8B7C6D5E4`, `existingAccountLocked: false`, candidate PII stripped), HTTP 503 KMS lockdown (`HSM_REVOKED_LOCKDOWN`), and Gate H status parsing.

### 3.2 Backend Test Execution (`npm test`)

```text
ℹ tests 665
ℹ suites 125
ℹ pass 665
ℹ fail 0
ℹ duration_ms 62982.037417
```
- All 665 backend tests across 125 suites continue to pass 100%.

---

## 4. Release Classification & Gate Status

- **Release Posture:** `CONTROLLED_TEST_BUILD_ONLY`
- **Calibration Status:** `productionBiometricCalibrationApproved = false`
- **Readiness:** The mobile application is now 100% prepared to run live field calibration on physical Android hardware. Once connected via USB debugging or Wi-Fi, the app can submit calibration captures to `/api/v18/biometrics/calibration/capture` to complete Gate H qualification.
