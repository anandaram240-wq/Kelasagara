# KELASAGARA BIOMATCH V19.6.7
## Evidence Integrity & Claims Audit: Distinguishing Code, Tests, and Physical Reality

**Milestone:** V19.6.7 — Evidence Integrity & Scientific Audit  
**Date:** 2026-10-24  
**Release Gate Status:** `CONTROLLED_TEST_BUILD_ONLY`  
**Production Calibration Approved:** `false`  
**Target:** Systematic Audit of Engineering Claims Across V19.6.5, V19.6.6, and V19.6.7  

---

### 1. Taxonomy of Evidence Categories

To eliminate ambiguous "verified" claims and ensure absolute scientific integrity, all engineering statements across the Kelasagara BioMatch repository are categorized according to the following 6-tier evidentiary taxonomy:

1. **Category 1 (SRC):** Source-Code Inspection (Static code analysis, AST inspection, variable presence).
2. **Category 2 (UNT):** Automated Unit Tests (In-memory algorithmic checks, synthetic data).
3. **Category 3 (INT):** API / Router Integration Tests (Express supertest, HTTP request/response).
4. **Category 4 (SIM):** Emulator / Simulated Capture Tests (Synthetic frames, mock camera streams).
5. **Category 5 (HW):** Physical Android Hardware Measurements (Real silicon, ADB execution, sensor timings).
6. **Category 6 (FLD):** Consent-Based Field & Demographic Evaluation (Multi-subject, varied lux, real-world population).

---

### 2. Systematic Audit of Critical Claims

| # | Specific Engineering Claim | Claimed Level | Actual Evidence Source | Truth Status & Correction Required | Corrected Status in V19.6.7 |
|---|---------------------------|---------------|------------------------|------------------------------------|-----------------------------|
| **1** | **Enrollment API Route is `POST /api/v1/face/enroll`** | API Contract | V19.6.3 & V19.6.5 Markdown Reports | **DOCUMENTATION DEFECT.** Both Flutter and Express implement `POST /api/biometrics/enroll`. `/api/v1/face/enroll` is not mounted and returns 404. | **RECONCILED (INT)**: `POST /api/biometrics/enroll` |
| **2** | **Photometric PAD Thresholds ($\Delta L \ge 0.04, \mathcal{R}_{spec} \le 3\%$) Distinguish Skin vs Screen** | Biometric PAD | Synthetic in-memory JPEG buffers in unit test | **UNVALIDATED HYPOTHESIS.** Zero physical measurements on human skin or smartphone cameras exist. Cannot be used as a security gate. | **UNVALIDATED HYPOTHESIS (UNT)**: Labeled uncalibrated research telemetry only |
| **3** | **Android Camera Pipeline Verified on Handset** | Hardware Capture | Successful APK compilation (`assembleDebug`) | **OVERSTATED.** An APK build does not prove camera stream stability or driver compatibility on real hardware. `adb devices -l` showed 0 devices. | **PENDING (HW)**: `BLOCKED_ON_PHYSICAL_DEVICE` |
| **4** | **3-Frame Burst Eliminates Video Replay Attacks** | Security Boundary | Server unit tests on Sobel vertical aperture | **PARTIAL DEFENSE ONLY.** Intercepts static photos, cut transitions, and frozen frames. Does not prevent high-resolution video of a user blinking on an iPad held at $30\text{ cm}$. | **ACTIVE DEFENSE (UNT)**: Intercepts still photo & cut replay; screen blink attack remains residual risk |
| **5** | **Zero-PII Telemetry Guarantees Legal Compliance** | Compliance | Unit test assertions on `toSafeJson()` | **OVERSTATED.** Technical sanitization prevents accidental logging, but does not substitute for a formal Data Protection Impact Assessment (DPIA). | **HARDENED TECHNICAL CONTROL (UNT)**: Technical privacy controls verified; DPIA required for field |
| **6** | **Photometric PAD Cannot Authorize Enrollment** | Release Invariant | Source inspection & call graph audit | **FULLY SUPPORTED.** Service is non-enforcing (`isEnforcing: false`), decoupled from enrollment pipeline, and tested via regression. | **CONFIRMED (SRC / UNT)**: Non-enforcing |

---

### 3. Detailed Audit Findings

#### Finding A: The API Route Discrepancy
- **Audit Findings:** The V19.6.5 integration report claimed that Flutter was routed to `POST /api/v1/face/enroll`. Tracing `lib/services/biometric_service.dart` revealed that the base URL was `kProductionBackendUrl = 'https://api.kelasagara.com/api/biometrics'` and the endpoint was `/enroll`, which resolves to `POST /api/biometrics/enroll`.
- **Server Audit:** `backend/src/server.ts` mounts `faceRouter` at `/api/biometrics`. In `face_routes.ts`, line 221 registers `faceRouter.post("/enroll", ...)`.
- **Integration Test:** An Express-level supertest in `v19_6_7_api_contract_reconciliation.test.ts` proved that `POST /api/biometrics/enroll` executes with authentication, and `POST /api/v1/face/enroll` returns `404 Not Found`.

#### Finding B: The Photometric PAD Claim
- **Audit Findings:** The V19.6.6 report suggested candidate thresholds of $\Delta L \ge 0.04$ for skin and $\mathcal{R}_{spec} \ge 0.05$ for screens. Because no physical device was connected, these numbers were purely speculative configuration defaults tested against synthetic buffers.
- **Refactor:** In V19.6.7, `ExperimentalPhotometricPadService` was refactored to cleanly separate objective `PhotometricFeatureMeasurement` from isolated `PhotometricExperimentalInterpretation`. The provenance was explicitly set to `UNVALIDATED_THEORETICAL_HYPOTHESIS`.

#### Finding C: Android Hardware Status
- **Audit Findings:** The workstation `adb devices -l` command returned zero devices. Automated tests on a macOS host do not substitute for physical execution on ARM64 Android chipsets (e.g. MediaTek Helio, Qualcomm Snapdragon).
- **Status:** All physical device validation remains explicitly marked `PENDING` / `BLOCKED_ON_PHYSICAL_DEVICE`.

---

### 4. Conclusion

By separating static code inspection, synthetic automated tests, and physical hardware evidence, V19.6.7 restores absolute truthfulness and evidentiary integrity to the repository.
