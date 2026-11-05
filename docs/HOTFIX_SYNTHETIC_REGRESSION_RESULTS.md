# KELASAGARA SYNTHETIC REGRESSION TEST RESULTS
## 36-TEST AUTOMATED COMPLIANCE AND SECURITY REGRESSION SUITE

**Phase:** Biometric Enrollment Hotfix  
**Branch:** `security/hotfix-canonical-face-preprocessing`  
**Classification:** Automated Test Matrix & Zero Human Data Certification  
**Date:** November 1, 2026  
**Auditors:** Independent Quality Assurance Engineer, Biometric Dataset Governance Specialist

---

## 1. COMPLIANCE CERTIFICATION: ZERO REAL HUMAN BIOMETRIC DATA

In strict accordance with IEC protocol restrictions, ethical research governance, and user directives:
- **ZERO real human facial photographs, videos, or raw biometric buffers were captured, stored, or processed.**
- All 36 regression test cases were executed using:
  - Synthetic geometric and color rasters generated on-the-fly via `sharp`
  - Synthetic mathematical coordinate matrices
  - Deterministic pseudo-random seed vectors
  - Programmatic mock detector harnesses

---

## 2. 36-TEST EXECUTION MATRIX & STATUS

### Track 1: Image Preprocessing & Decompression Gates (Tests 1–10)
| # | Test Description | Input Condition | Expected Result | Status |
|---|---|---|---|---|
| 1 | Rejects empty buffer | `Buffer.alloc(0)` | `UNSUPPORTED_IMAGE_FORMAT` | **PASS** (0.97ms) |
| 2 | Rejects buffer < 32 bytes | 16 bytes `0xFF` | `UNSUPPORTED_IMAGE_FORMAT` | **PASS** (0.14ms) |
| 3 | Rejects non-image buffer | 100 bytes random ascii | `UNSUPPORTED_IMAGE_FORMAT` | **PASS** (0.13ms) |
| 4 | Rejects payload > 15MB | 16MB buffer | `IMAGE_DIMENSIONS_INVALID` | **PASS** (1.20ms) |
| 5 | Rejects image width < 64px | 48x128 JPEG | `IMAGE_DIMENSIONS_INVALID` | **PASS** (3.82ms) |
| 6 | Rejects image height < 64px | 128x48 JPEG | `IMAGE_DIMENSIONS_INVALID` | **PASS** (1.61ms) |
| 7 | Rejects image width > 4096px | 4100x100 JPEG | `IMAGE_DIMENSIONS_INVALID` | **PASS** (4.45ms) |
| 8 | Rejects image height > 4096px | 100x4100 JPEG | `IMAGE_DIMENSIONS_INVALID` | **PASS** (4.13ms) |
| 9 | Decodes valid JPEG image | 320x240 RGB JPEG | Raw RGB raster (230,400 bytes) | **PASS** (2.26ms) |
| 10 | Decodes valid PNG image | 200x200 RGBA PNG | Raw RGB raster (120,000 bytes) | **PASS** (2.08ms) |

### Track 2: Face Detection, Quality Gates & Canonical Alignment (Tests 11–20)
| # | Test Description | Input Condition | Expected Result | Status |
|---|---|---|---|---|
| 11 | Rejects blank scene / no face | 320x320 uniform gray | `NO_FACE_DETECTED` | **PASS** (23.05ms) |
| 12 | Rejects multi-face image | 2 detected faces | `MULTIPLE_FACES_DETECTED` | **PASS** (3.43ms) |
| 13 | Rejects face < 60x60 | 45x50 bbox | `FACE_QUALITY_INSUFFICIENT` (`FACE_TOO_SMALL`) | **PASS** (3.08ms) |
| 14 | Rejects face out of frame | 50% outside image | `FACE_QUALITY_INSUFFICIENT` (`FACE_OUT_OF_BOUNDS`) | **PASS** (2.35ms) |
| 15 | Rejects extreme yaw pose | Yaw offset ratio > 0.45 | `FACE_QUALITY_INSUFFICIENT` (`EXTREME_POSE`) | **PASS** (2.27ms) |
| 16 | Rejects excessively blurry face | Laplacian variance < 12.0 | `FACE_QUALITY_INSUFFICIENT` (`EXCESSIVE_BLUR`) | **PASS** (3.23ms) |
| 17 | Umeyama similarity solver | 5 arbitrary valid points | Finite scale, angle, translation | **PASS** (0.26ms) |
| 18 | Rejects invalid landmark count | 2 landmarks passed | `UMEYAMA_ALIGNMENT_REQUIRES_5_LANDMARKS` | **PASS** (0.11ms) |
| 19 | Bilinear affine warp length | 320x240 image + 5 points | Exactly 112x112x3 (37,632 bytes) | **PASS** (2.05ms) |
| 20 | Warp intensity preservation | Uniform 215 intensity | Center pixel = 215 | **PASS** (1.12ms) |

### Track 3: SFace Inference, Nominal Typing & Embedding Pipeline (Tests 21–28)
| # | Test Description | Input Condition | Expected Result | Status |
|---|---|---|---|---|
| 21 | extractCanonicalEmbedding unaligned reject | Length !== 37632 | `CANONICAL_EMBEDDING_FAILED` | **PASS** (0.22ms) |
| 22 | SFace forward pass dimension | Valid 112x112x3 buffer | Length 128 Float32Array | **PASS** (17.01ms) |
| 23 | L2 unit normalization | Valid SFace output | $\|\mathbf{e}\|_2 = 1.000000 \pm 10^{-5}$ | **PASS** (10.30ms) |
| 24 | Self-similarity invariant | $\mathbf{e} \cdot \mathbf{e}$ | $\text{sim} = 1.0000$ | **PASS** (9.68ms) |
| 25 | Orthogonal & distinct vectors | Orthogonal pair + 2 images | Clean Zone (< 0.363) & < 0.720 | **PASS** (19.58ms) |
| 26 | Full pipeline orchestration | JPEG image + mock detector | Output embedding + metadata | **PASS** (15.88ms) |
| 27 | SFace artifact SHA-256 reject | Corrupt hash passed | `MODEL_UNAVAILABLE: SHA-256 mismatch` | **PASS** (30.98ms) |
| 28 | YuNet artifact SHA-256 verify | Production model file | Verified against `8f2383e4...` | **PASS** (0.08ms) |

### Track 4: Deduplication Policy, Zone Classification & Privacy (Tests 29–36)
| # | Test Description | Input Condition | Expected Result | Status |
|---|---|---|---|---|
| 29 | Clean Zone evaluation | Sim = 0.150 | $< 0.363$ (Unique individual) | **PASS** (0.09ms) |
| 30 | Ambiguous Zone evaluation | Sim = 0.450 | $0.363 \le s < 0.720 \rightarrow$ HTTP 202 | **PASS** (0.05ms) |
| 31 | Hard Duplicate Zone evaluation | Sim = 0.850 | $\ge 0.720 \rightarrow$ HTTP 409 | **PASS** (0.04ms) |
| 32 | duplicateFloor threshold audit | Sim = 0.600 | Does NOT trigger 409 hard block | **PASS** (0.03ms) |
| 33 | Zero PII returned in response | 409 response payload | No phone, name, UID, skill, rate | **PASS** (0.06ms) |
| 34 | Zero raw similarity scores | 409 response payload | No score or clamped % | **PASS** (0.05ms) |
| 35 | Opaque case reference format | Generated reference | Matches `^CASE-[A-Z0-9]{8}$` | **PASS** (0.08ms) |
| 36 | Client resolution sheet contract | Sheet view model | Dual-language text, zero PII | **PASS** (0.05ms) |

---

## 3. SUMMARY RESULT

- **Total Tests Executed:** 36
- **Total Tests Passed:** 36 (100.0%)
- **Total Tests Failed:** 0 (0.0%)
- **Total Execution Duration:** 273.37 ms
- **Backend Global Suite:** 880 tests passed across 192 suites in 36.85 seconds.
