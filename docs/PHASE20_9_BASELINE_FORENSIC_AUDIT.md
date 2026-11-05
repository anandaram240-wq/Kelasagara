# KELASAGARA V20.9: BASELINE FORENSIC AUDIT
## Phase 20.9 Camera Capture Integrity & Hardware Optical Bench Engine

**System:** Kelasagara Major Project  
**Repository Working Tree:** `kelasagaara_v17`  
**Current Working Branch:** `security/phase20.9-camera-capture-integrity`  
**Parent Commit:** `32b928b` (`feat(v20.8): pad signal extraction and optical evidence engine`)  
**Protected Release Tag:** `v19.2.3-release` (`8634a1813c84fccc73b8944803b6bd541f5e2326`)  
**Protected Release APK:** `Kelasagara-v19.2.3-release.apk`  
**Date:** November 1, 2026

---

### 1. Cryptographic Baseline Verification

Before initiating any implementation or verification in Phase 20.9, cryptographic hashes for all core artifacts were verified:

| Artifact Name | Path | SHA-256 Checksum | Status |
| :--- | :--- | :--- | :--- |
| Protected Release APK | `Kelasagara-v19.2.3-release.apk` | `739f85746df3cd1fb6c315590147907918a3829976d0381b8eae358c743176ce` | **INTACT & UNMODIFIED** |
| SFace Primary Model | `assets/models/sface.onnx` | `0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79` | **INTACT & UNMODIFIED** |
| YuNet Detector Model | `assets/models/yunet.onnx` | `8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4` | **INTACT & UNMODIFIED** |
| V20.8 Optical Extractor | `backend/src/biometric-evaluation/optical_display_feature_extractor.ts` | `6bc46f0ed46be006792a599e51296d157d3ba915bceb477e09257f4cb9d1237b` | **INTACT & VERIFIED** |

---

### 2. Upstream Verification & Regression Status

- **Backend Test Baseline:** 791/791 tests passing prior to Phase 20.9 inception.
- **Flutter Test Baseline:** 113/113 tests passing cleanly across all biometric and contract suites.
- **Android Gradle Compilation:** `compileDebugKotlin` verified passing on Kotlin 1.9 / AGP 9.x / compileSdk 36.
- **Hardware Attestation Probe:** `adb devices -l` executed $\rightarrow$ **0 physical devices attached**. Physical handset testing gate remains strictly **BLOCKED**.
- **IEC Clinical Protocol Status:** Protocol `IEC-KELA-2026-003` remains `SUBMITTED`. Human subject biometric data collection remains strictly **BLOCKED**.

---

### 3. Forensic Scope Boundaries

Phase 20.9 is strictly an end-to-end capture integrity, buffer normalization, and physical optical bench engineering phase.
1. No production thresholds are modified (`0.363` 1:1 verify, `0.74` duplicate warn, `0.78` / `0.90` block).
2. Production face recognition models (SFace 128-D) and face detection models (YuNet) remain unchanged.
3. Candidate PAD logic remains in test mode and is not activated for production rejection decisions.
4. All optical evaluation fixtures remain categorized as synthetic, non-biometric physical charts, or mocked camera frames.
