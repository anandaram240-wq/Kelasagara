# KELASAGARA BIOMATCH · STAGE S7 REPOSITORY FORENSICS (S7_REPOSITORY_FORENSICS.md)

**Classification:** Advanced Defensive Biometric Research & Systems Assurance  
**Generated At:** 2026-10-11T00:44:00Z  
**Starting Commit:** `215c44501b178422da8fc9233f4f10329d16b76a`  
**Git Branch:** `biomatch/v7-hardening`  
**Working Directory:** `/Users/ananda/KELASAGARA MAJOR PROJECT/kelasagaara_v17`  
**Host Platform:** Darwin arm64 (macOS 15.6 / Apple Silicon M4)  

---

## 1. Executive Summary

This document captures the forensic baseline of the Kelasagara BioMatch repository at the entry gate of **Stage S7**. It details the canonical filesystem paths, git branch state, commit relationships, dependency lockfiles, model artifact digests, toolchain versions, and environment configurations.

Per Stage S7 Operating Contract (Part 1.1), no branches were force-pushed, no historical evidence was overwritten, and all working tree modifications from prior stages (S3 through S6) were preserved and systematically categorized.

---

## 2. Toolchain and Hardware Inventory

| Component | Detected Version / Specification | Verification Command | Exit Status |
| :--- | :--- | :--- | :---: |
| **Node.js** | `v24.14.0` | `node -v` | 0 |
| **npm** | `11.9.0` | `npm -v` | 0 |
| **Python** | `3.9.6` | `python3 --version` | 0 |
| **Host Kernel** | `Darwin 24.6.0 arm64 T8132` | `uname -a` | 0 |
| **Processor** | Apple M4 (ARM64 with NEON vector extensions) | `sysctl -n machdep.cpu.brand_string` | 0 |
| **Flutter/Dart** | Flutter SDK (Homebrew installed, read-only cache in sandbox) | `flutter --version` | Checked |

---

## 3. Git Repository Forensics

### 3.1 Git State
- **HEAD Commit SHA:** `215c44501b178422da8fc9233f4f10329d16b76a`
- **Commit Subject:** `biomatch(phase16): Deployment plan, cutover protocols, and Gate G16 final RRL-0 sign-off`
- **Active Branch:** `biomatch/v7-hardening`
- **Working Tree:** Contains 18 tracked modifications and 62 untracked files representing the S3–S6 research records, evidence catalogs, frozen analysis runners, and standalone test suites.
- **Git Tags Present:**
  - `biomatch-gate-1` through `biomatch-gate-16`
  - `biomatch-final`
  - *Historical observation:* `s4-final` and `s5-final` were not tagged in git; their artifacts are preserved directly in working-tree evidence.

### 3.2 Dependency Lockfile Integrity

| Lockfile / Manifest | Path | SHA-256 Digest |
| :--- | :--- | :--- |
| **Backend package-lock.json** | `backend/package-lock.json` | `a43d0bcf074f96a1beefdfd7e19f4d651727090f9f6ed3caa2684359bdbc819b` |
| **Backend package.json** | `backend/package.json` | `4a6388c34ac50a0d143b68b1e3f316adef8df05ed2e35b5bee3db4073de18a19` |
| **Flutter pubspec.lock** | `pubspec.lock` | `f633ac2d0899be87b133aa9a35c3613a827644127083ca8327ce9bb379ac5ff3` |
| **Flutter pubspec.yaml** | `pubspec.yaml` | `ad8fa4d2b03a7fce0ab23d9481d65c72bbbd297fcd1866d9acc5df962f81f037` |

---

## 4. Model Artifact Inventory & Digest Verification

All model files residing in `backend/models/` were audited for exact byte count and SHA-256 digest:

| Artifact Name | Relative Path | File Size | SHA-256 Digest | License & Provenance | Role |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **YuNet 2023Mar** | `backend/models/face_detection_yunet_2023mar.onnx` | 232,589 B | `8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4` | Apache-2.0 (OpenCV Zoo) | Face detection & 5 landmarks |
| **SFace 2021Dec FP32** | `backend/models/face_recognition_sface_2021dec.onnx` | 38,696,353 B | `0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79` | Apache-2.0 (OpenCV Zoo) | Primary 128-D recognizer |
| **SFace 2021Dec INT8** | `backend/models/face_recognition_sface_2021dec_int8.onnx` | 9,896,933 B | `2b0e941e6f16cc048c20aee0c8e31f569118f65d702914540f7bfdc14048d78a` | Apache-2.0 (OpenCV Zoo) | Secondary fallback recognizer |
| **Kelasagara MobileFaceNet** | `backend/models/kelasagara_mobilefacenet.onnx` | 1,172,885 B | `cde3799f041eca6a6a99bfac53d9e97eb81ff34ac450d519aa41a9c99bef7d7c` | Research / EVAL-ONLY | Benchmark comparison only |

---

## 5. Environment Variables & Secret Safety

Inspection of `backend/.env.example` and `backend/src/config.ts` identified configuration parameters without exposing secret values:
- `PORT` (Default: 5001)
- `FIREBASE_PROJECT_ID` (Default: `kelasagara-f127a`)
- `MODEL_PATH` (`models/face_recognition_sface_2021dec.onnx`)
- `FALLBACK_MODEL_PATH` (`models/face_recognition_sface_2021dec_int8.onnx`)
- `DUPLICATE_THRESHOLD` (0.74 cosine similarity)
- `AMBIGUITY_THRESHOLD` (0.65 cosine similarity)
- `MAX_GALLERY_SCAN_LIMIT` (500 per partition)
- `MAX_ENROLL_ATTEMPTS` (3 attempts)
- `ALLOW_DEV_TOKEN` (`false` in production)
- Secret scanning via `tools/secret_scan.py` confirmed **0 credentials, 0 API keys, and 0 unregistered face images** committed in git or configuration.

---

## 6. Exit Gate Assessment: S7-G01 (Forensics)

**Status:** `DONE-VERIFIED`  
**Evidence Artifact:** `evidence/s7/repository_inventory.json`  
**Verification:** Baseline captured cleanly; all hashes and metadata recorded in machine-readable format.
