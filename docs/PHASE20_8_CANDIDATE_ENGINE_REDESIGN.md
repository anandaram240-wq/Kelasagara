# PHASE 20.8: CANDIDATE PAD HARDENED ENGINE REDESIGN REPORT
**System:** Kelasagara Biometric Identity & Authentication Platform  
**Phase:** 20.8 (PAD Signal Extraction and Optical Evidence Engine)  
**Component:** `CandidatePadHardenedEngine`  
**Author:** Senior TypeScript Engineer & Principal Biometric Systems Architect  
**Date:** November 2026  
**Status:** IMPLEMENTED, REFACTORED & VERIFIED

---

## 1. Executive Summary & Forensic Defect Analysis

In Phase 20.7, the initial implementation of `CandidatePadHardenedEngine` suffered from an architectural limitation: it operated strictly as a threshold evaluation function over externally supplied scalar telemetry (`periodicScreenGridEnergy`, `activeChromaticReflectionDelta`). It contained no native capability to extract spatial frequencies or reflection profiles from raw camera pixels.

In Phase 20.8, `CandidatePadHardenedEngine` has been completely refactored into a **modular, multi-stage biometric processing engine**:

```
+--------------------------------------------------------------------------------------------------+
| PHASE 20.8 MODULAR PAD PIPELINE                                                                 |
+--------------------------------------------------------------------------------------------------+
  [STAGE A: Raw-Frame Feature Extraction] (OpticalDisplayFeatureExtractor.extractFromGrayscalePlane)
                             |
                             v
  [STAGE B: Feature Validation & Invariant Checking] (Range clamping & sanity boundaries)
                             |
                             v
  [STAGE C: Dynamic Challenge & Sequence Validation] (validateFrameSequenceContinuity)
                             |
                             v
  [STAGE D: Multi-Signal Decision Fusion] (fusePadSignals -> ISO/IEC 30107-3 Outcomes)
                             |
                             v
  [STAGE E: Isolated Policy Comparison] (comparePoliciesInIsolatedMode -> Telemetry Output)
```

---

## 2. Detailed Stage Responsibilities

### 2.1. Stage A: Raw-Frame Feature Extraction
- **Module:** [`OpticalDisplayFeatureExtractor`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/backend/src/biometric-evaluation/optical_display_feature_extractor.ts)
- **Role:** Directly processes 8-bit grayscale pixel arrays or encoded JPEG Buffers.
- **Output:** Fully typed `OpticalDisplayFeatures` object containing:
  - `spatialHighFrequencyEnergy` ($R_{\text{high}}$)
  - `spectralPeakiness`
  - `moirePatternDetected`
  - `specularHighlightFeatureScore` (Image-derived heuristic)
  - `isLowQualityOrCorrupt`

### 2.2. Stage B: Feature Validation & Boundary Checks
- Validates that high-frequency energy and specular metrics are finite numbers within $[0.0, 1.0]$.
- Rejects any malformed inputs or `NaN` occurrences.

### 2.3. Stage C: Dynamic Challenge & Sequence Validation
- **Method:** `validateFrameSequenceContinuity(timestampsMs, issuedAtMs, expiresAtMs)`
- Validates timestamp monotonicity ($T_0 < T_1 < T_2$).
- Enforces physical inter-frame interval boundaries ($40\,\text{ms} \le \Delta T \le 350\,\text{ms}$).
- Verifies frame submission timestamps against server challenge expiration.

### 2.4. Stage D: Multi-Signal Decision Fusion
- **Method:** `fusePadSignals(input: MultiSignalFusionInput)`
- Synthesizes FIQA, landmark aperture, spatial frequency, specular profile, sequence timings, and dynamic challenge compliance into standard typed outcomes (`BONA_FIDE_CANDIDATE`, `PRESENTATION_ATTACK_SUSPECTED`, `CAPTURE_QUALITY_INSUFFICIENT`, etc.).

### 2.5. Stage E: Isolated Policy Comparison Mode
- **Method:** `comparePoliciesInIsolatedMode(input: CandidatePadEvaluationInput)`
- Executes baseline policy and candidate hardened policy side-by-side on the same burst input.
- Emits structured diagnostic telemetry logging policy agreement and vulnerability interception without altering the production authentication outcome.

---

## 3. Backwards Compatibility & Verification

1. **Legacy Compatibility:** Preserves existing method signatures (`evaluateBaselinePolicy`, `evaluateCandidateHardenedPolicy`), ensuring that all 6 tests in `phase20_7_pad_hardening.test.ts` pass without regression.
2. **Adversarial Verification:** Verified across all 20 test cases in `backend/src/tests/phase20_8_optical_pad.test.ts` with zero failures.
