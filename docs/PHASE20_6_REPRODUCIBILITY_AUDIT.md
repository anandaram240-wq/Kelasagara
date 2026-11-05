# PHASE 20.6 REPRODUCIBILITY AUDIT
## Independent Evaluator Reproduction Manual & Pipeline Execution Guide

**Project:** Kelasagara Major Project  
**System:** Worker Marketplace & Biometric Identity Platform  
**Phase:** 20.6 (Biometric Evidence Integrity & Controlled Pilot Readiness)  
**Lead Auditor:** Independent Quality Assurance Engineer & Statistical Auditor  
**Date:** 2026-10-31  

---

## 1. REPRODUCIBILITY PROTOCOL FOR INDEPENDENT EVALUATORS

A clean third-party auditor, academic examiner, or regulatory evaluator can independently verify the entire Kelasagara Phase 20.6 findings by executing the following 10-step protocol:

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                        TEN-STEP REPRODUCIBILITY EVALUATION SUITE                       │
├────────────────────────────────────────────────────────────────────────────────────────┤
│ Step 1: Check out branch: git checkout research/phase20.6-evidence-integrity          │
│ Step 2: Verify model digests against docs/PHASE20_6_ARTIFACT_HASH_MANIFEST.md          │
│ Step 3: Run typescript compiler: npm run build in backend/                             │
│ Step 4: Run dataset partition validator: verifies zero cross-partition subject leakage │
│ Step 5: Run corpus availability check: verifySourceCorpusAvailability()                │
│ Step 6: Verify provenance guard activation: triggers PROVENANCE_ERROR on synthetic run │
│ Step 7: Run statistical math suite: verifies exact Clopper-Pearson Lanczos inversion   │
│ Step 8: Run 1:N population probe test: verifies distinct unenrolled probe isolation    │
│ Step 9: Run PAD disaggregation test: verifies per-PAI error bounds (13.3% tablet PAI) │
│ Step 10: Run full platform regression: 753 backend tests, 113 Flutter tests pass       │
└────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. STEP-BY-STEP TERMINAL EXECUTION

### Step 1: Model Hash Verification
```bash
cd backend
shasum -a 256 models/face_recognition_sface_2021dec.onnx
# Expected: 0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79

shasum -a 256 models/face_detection_yunet_2023mar.onnx
# Expected: 8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4
```

### Step 2: Build and Test Phase 20.6 Evidence Integrity Suite
```bash
npm run build
node --test dist/tests/phase20_6_evidence_integrity.test.js
```
**Expected Terminal Output:**
```
✔ 1.1: Identifies and supports all 6 mandatory provenance categories
✔ 1.2: Canonical manifest classifies itself as BENCHMARK_FIXTURE with sourceCorpusAvailable=false
✔ 1.3: verifySourceCorpusAvailability detects missing raw image frames on disk
✔ 2.1: Automatically classifies synthetic manifest runs as SYNTHETIC_PIPELINE_BENCHMARK
✔ 2.2: generateEmpiricalHumanAccuracyReport strictly throws PROVENANCE_ERROR on synthetic data
✔ 2.3: Accepts real consented data when sourceCorpusAvailable=true and REAL_CONSENTED_HUMAN_DATA
✔ 3.1: Distinguishes two-sided exact Clopper-Pearson (~1.22%) and one-sided 95% upper bound (~0.994%)
✔ 3.2: Confirms 0/300 comparisons cannot mathematically validate a 1:10,000 FMR claim
✔ 3.3: Planning calculation proves ~29,956 independent trials required for 1:10,000 bound
✔ 4.1: Flags invalid probe design where non-enrolled probes overlap with seen subjects
✔ 4.2: Enforces that non-enrolled holdout probes must be completely distinct from gallery
✔ 5.1: Evaluates APCER per PAI category and isolates software injection from physical
ℹ pass 12 | fail 0 | cancelled 0
```

### Step 3: Full Platform Regression
```bash
# Backend Regression (753 tests across 157 suites)
npm test

# Flutter Biometric & Play Integrity Regression (113 tests)
cd ..
flutter test test/biometric*
flutter test test/play_integrity*

# Android Kotlin Compilation
cd android
./gradlew compileDebugKotlin
```

---

## 3. AUDIT OF NON-SILENT FALLBACK

A critical scientific integrity requirement is that **the pipeline must identify when the original corpus is unavailable and never silently substitute synthetic data**.

In Phase 20.6:
1. When `verifySourceCorpusAvailability()` inspects the local workspace, it finds 0 physical raw frames on disk.
2. It outputs: `status = UNAVAILABLE_MISSING_RAW_IMAGES`, `isCorpusAvailable = false`.
3. The report generator refuses to emit an empirical claim, injecting:
   `PROVENANCE GUARD ACTIVATED: Evaluation executed against SYNTHETIC_VECTOR_TEST / BENCHMARK_FIXTURE.`
4. Evaluators are explicitly alerted to the synthetic nature of the test vectors. Silent substitution is **100% prevented**.
