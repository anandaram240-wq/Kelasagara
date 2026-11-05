# KELASAGARA BIOMATCH V7: LICENSE & PROVENANCE MATRIX

**Document ID:** `LM-BIOMATCH-V7-001`  
**Phase:** Phase 3 (Model, Data and License Selection)  
**As-of Date:** 2026-10-10  
**Release Readiness Level:** **RRL-0 (Research Prototype)**  
**Standard of Admissibility:** No model, weight artifact, or dataset may be classified as `CLEARED` without verifiable proof of:
1. Permissive code license (e.g. Apache 2.0, MIT, BSD).
2. Permissive model weight redistribution license for commercial production.
3. Consented, legally authorized training-data provenance free of non-commercial academic restrictions or copyright infringement claims.

Any component failing any of these three pillars is strictly classified as **`RESEARCH_ONLY`** or **`PROHIBITED`**. CI and release scripts MUST fail if any `RESEARCH_ONLY` model is included in a production release bundle.

---

## 1. COMPREHENSIVE COMPONENT LICENSE MATRIX

| Component Name | Pipeline Role | Code License | Weight / Model License | Training Data License & Provenance | Commercial Status | Evidence URL / Primary Reference | Access Date | Operational Disposition |
|---|---|---|---|---|---|---|---|---|
| **Google ML Kit Face Detection** | On-device Face Detection & 2D Landmarks | Apache 2.0 / Google Terms of Service | Google Play Services On-Device Runtime | Google Proprietary Consented Internal Datasets | **`CLEARED`** | `developers.google.com/ml-kit/terms` | 2026-10-10 | Primary on-device client face detector & EAR eye blink tracker. |
| **MediaPipe Face Mesh (Google)** | 468-point 3D Facial Landmark Tracking | Apache 2.0 | Apache 2.0 | Google Proprietary Consented Datasets | **`CLEARED`** | `github.com/google-ai-edge/mediapipe` | 2026-10-10 | Cleared alternative for dense landmark extraction on Android/iOS. |
| **OpenCV YuNet (`face_detection_yunet_2023mar.onnx`)** | Lightweight Face Detection (Server / Edge) | Apache 2.0 (OpenCV Zoo) | Apache 2.0 | **WIDER FACE** (academic non-commercial license [R-11]) | **`UNCLEARED`** / `RESEARCH_ONLY` | `github.com/opencv/opencv_zoo/tree/main/models/face_detection_yunet` | 2026-10-10 | Permitted in research harness only. Prohibited in commercial releases until retrained. |
| **InsightFace ArcFace Packs (`buffalo_l`, `antelopev2`)** | Deep Face Recognition (512-D) | MIT (Repository Code) | **Non-Commercial Research Only** | MS1MV2 / Glint360k (retracted / non-commercial [R-09]) | **`PROHIBITED`** | `github.com/deepinsight/insightface/blob/master/LICENSE` | 2026-10-10 | **STRICTLY FORBIDDEN.** Commercial use violates upstream license terms. Do not use. |
| **OpenCV Zoo SFace (`face_recognition_sface_2021dec.onnx`)** | 128-D Cosine Face Recognizer (Zhong et al.) | Apache 2.0 (OpenCV Zoo) | Apache 2.0 | **CASIA-WebFace** (academic research only, taken down [R-10]) | **`UNCLEARED`** / `RESEARCH_ONLY` | `github.com/opencv/opencv_zoo/tree/main/models/face_recognition_sface` | 2026-10-10 | Benchmark & harness evaluation only. Blocked from automated production clearance. |
| **Kelasagara MobileFaceNet (`kelasagara_mobilefacenet.onnx`)** | 128-D Unit Hypersphere ArcFace Recognizer | Apache 2.0 (Kelasagara Implementation) | Apache 2.0 | **Random Uninitialized Weights** (Exported from PyTorch init; EV-007) | **`RESEARCH_ONLY`** | Repository `backend/models/kelasagara_mobilefacenet.onnx` | 2026-10-10 | Registered as `RESEARCH_ONLY`; `clearedForAutomatedApproval: false`. Harness testing only. |
| **MiniFASNet (Silent-Face-Anti-Spoofing)** | Presentation Attack Detection (Liveness) | Apache 2.0 | Apache 2.0 | **CASIA-SURF** (non-commercial research agreement) | **`UNCLEARED`** / `RESEARCH_ONLY` | `github.com/minivision-ai/Silent-Face-Anti-Spoofing` | 2026-10-10 | Labeled `RESEARCH_ONLY`. Production liveness relies on ML Kit EAR blink + reflection. |
| **BSI OFIQ (ISO/IEC 29794-5)** | Face Image Quality Assessment | BSD 3-Clause | BSD 3-Clause | Reference datasets vetted by German Federal BSI | **`CLEARED`** | `github.com/BSI-OFIQ/OFIQ-Project` | 2026-10-10 | Cleared for international standardized quality scoring. |
| **DigiFace-1M Dataset (Microsoft Research)** | 1.2M Synthetic Face Images (110k synthetic identities) | CC-BY 4.0 | CC-BY 4.0 | 100% Synthetic CGI Renderings (No human subjects scraped) | **`CLEARED`** | `github.com/microsoft/DigiFace-1M` | 2026-10-10 | **Recommended training source** for training Kelasagara proprietary weights legally. |
| **FairFace Dataset (Kärkkäinen & Joo)** | 108k Diverse Demographic Faces | CC-BY 4.0 | CC-BY 4.0 | Flickr image crawl (Creative Commons CC-BY licenses) | **`UNCLEARED`** / `RESEARCH_ONLY` | `github.com/joojs/fairface` | 2026-10-10 | Cleared for research evaluation of Indian demographic bias; commercial training unverified. |
| **CASIA-WebFace / MS1MV2 / Glint360k** | Historical Academic Face Datasets | N/A | N/A | Non-consented web scraping (Formal takedown / research-only) | **`PROHIBITED`** | Retracted by original institutions (Microsoft, CASIA) | 2026-10-10 | Strictly banned from any Kelasagara training pipeline. |

---

## 2. STATUS SUMMARY & CI RELEASE POLICY

1. **Production Cleared Subsystems:**
   - Client Face Detection: Google ML Kit Face Detection (`CLEARED`).
   - Client Liveness: Dynamic Eye Aspect Ratio (EAR) Blink Engine (`CLEARED`).
   - Quality Assessment: BSI OFIQ / Custom Geometric Landmarks (`CLEARED`).
2. **Research-Only Subsystems (Active Harness):**
   - Recognition Feature Extractor: `kelasagara_mobilefacenet.onnx` (`RESEARCH_ONLY`).
   - SFace OpenCV Zoo Evaluation Model (`RESEARCH_ONLY`).
3. **CI Enforcement Rail:**
   - Any CI build targeting production release (e.g. `flutter build apk --release` or backend production container build) executes `ModelRegistry.assertClearedForAutomatedApproval()`.
   - If any active model is tagged `RESEARCH_ONLY`, the build fails immediately, preventing premature deployment of uncalibrated or uncleared biometric models.
