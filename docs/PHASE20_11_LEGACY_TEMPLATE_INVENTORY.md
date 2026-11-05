# PHASE 20.11: LEGACY TEMPLATE FORENSIC INVENTORY
**Role:** Principal Biometric Architect, Computer Vision Engineer & Data Integrity Auditor  
**System:** Kelasagara Multi-Factor Biometric Identity Platform  
**Branch:** `security/phase20.11-legacy-template-isolation`  
**Date:** November 1, 2026  

---

## 1. PURPOSE & ARCHITECTURAL SCOPE

Following the hotfix to SFace canonical preprocessing (mandatory YuNet neural detection and 5-point Umeyama alignment), existing biometric templates in the application and database repositories may have originated from earlier, disparate preprocessing pipelines. This document inventories every template format, provenance marker, storage representation, and security classification across the system.

---

## 2. COMPREHENSIVE TEMPLATE FORMAT INVENTORY

| Template Class | Lineage / Preprocessing Method | Storage Attributes | Dimensionality & Color Space | Calibrated Threshold | Forensic Classification | Deduplication Action |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Canonical V2 SFace** | 640x640 YuNet, 5-point Umeyama alignment, OpenCV BGR | `embeddingSpaceId: SFACE_128_YUNET_2023MAR_UMEYAMA_CANONICAL112_V2`, `biometricEnvelope` | 128-D Float32, L2 Unit Hypersphere | 0.720 (Hard Block), 0.363 (Clean) | `CANONICAL_V2` | **PARTICIPATES** in 1:N Search |
| **Defective Pre-Hotfix SFace** | Direct Sharp resize of full camera frame to 112x112 (no face crop or alignment) | `preprocessVersion: sface_aligned_112x112_bgr_v1`, no `embeddingSpaceId`, no detector metadata | 128-D Float32, unaligned full-scene | Corrupted (produces noise matches ~0.49-0.56) | `DEFECTIVE_FULL_PHOTO_SFACE_V10` | **ISOLATED (NEVER_COMPARE)** |
| **Legacy Landmark Geometric** | Pure-Dart 68-point or ML Kit landmark distance / ratio vector | `comparisonSpace: LEGACY_LANDMARK_SPACE`, `whitenedLandmark128`, `embedding: number[]` | 128-D Whitened Geometric Landmark Vector | 0.880 (Hard Block), 0.800 (Clean) | `LEGACY_LANDMARK_SPACE` | **ISOLATED (NEVER_COMPARE)** against SFace |
| **V10 Early Preprocessing** | Experimental Umeyama raw RGB crops (pre-V18 pipeline) | `preprocessVersion: PREPROC_V1_UMEYAMA_112_RGB_RAW255` | 128-D Float32, RGB Raw [0, 255] | Uncalibrated with V2 | `LEGACY_TEMPLATE_UNKNOWN` | **ISOLATED (NEVER_COMPARE)** |
| **Unverified / Ambiguous Records** | Legacy documents with missing metadata, custom mock scripts, or manual database entries | Missing `embeddingSpaceId`, missing detector hash, or corrupted envelope | Unknown / Unverified | Unknown | `LEGACY_TEMPLATE_UNKNOWN` | **ISOLATED (NEVER_COMPARE)** |

---

## 3. COMPATIBILITY & ISOLATION RULE: `INCOMPATIBLE_EMBEDDING_SPACE = NEVER_COMPARE`

1. **Mathematical Incompatibility:**
   Cosine similarity between vectors from different latent spaces has zero metric validity. An unaligned scene embedding compared against an Umeyama-aligned face embedding yields arbitrary pseudo-random projections that collapse into false duplicates.

2. **Classification Logic:**
   Any template where `embeddingSpaceId !== CANONICAL_EMBEDDING_SPACE_V2.embeddingSpaceId` is classified as `DEFECTIVE_FULL_PHOTO_SFACE_V10`, `LEGACY_LANDMARK_SPACE`, or `LEGACY_TEMPLATE_UNKNOWN`.

3. **Strict Query Isolation:**
   In `FirestoreCompatibleGalleryIndex.searchTopKCompatible`, any template whose classification is not `CANONICAL_V2` is bypassed before computing cosine similarity against a Canonical V2 probe vector.
