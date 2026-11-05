# KELASAGARA FORENSIC AUDIT REPORT
## ROOT-CAUSE INVESTIGATION: FALSE DUPLICATE DETECTION AND PII LEAKAGE

**Phase:** Biometric Enrollment Hotfix  
**Branch:** `security/hotfix-canonical-face-preprocessing`  
**Classification:** P0 Security & Enrollment Correctness  
**Date:** November 1, 2026  
**Auditors:** Principal Biometric Systems Engineer, Senior Computer Vision Engineer, Backend Security Architect

---

## 1. EXECUTIVE SUMMARY & INCIDENT OVERVIEW

A critical issue was reported during cross-account biometric testing:
> *"same problem i regiterd face one account after i tetsed with my bro in diffrent taccount face registerd trigger duplicate acconut my deatils like first face registration succesfull after for all faces same problem form starting pf this face auth model test please find root cause"*

When Account 1 was registered, enrollment succeeded. Subsequently, when Account 2 was registered with a completely different individual (the user's brother), the backend rejected the attempt with `DUPLICATE_ACCOUNT_DETECTED` / `FACE_ALREADY_LINKED` (HTTP 409). Furthermore, the client displayed a dialog disclosing Account 1's masked phone number, name, primary skill, daily rate, and a fabricated similarity percentage.

Our forensic investigation confirms three compounding root-cause defects:
1. **Severe Model Input Distortion (Squashing Scene to 112x112):** Unaligned full camera photographs (JPEG rasters up to 12MP) bypassed authoritative face detection and 5-point landmark alignment. Instead, full images were passed directly into `extractCanonicalEmbeddingFromAligned112()`, where Sharp squished the entire scene into 112x112 pixels (`fit: 'cover'`). Because high-level background scene geometry, aspect ratios, and lighting envelopes dominated the 112x112 raster, SFace extracted scene-level embeddings yielding an artificial **0.9596 (96%) cosine similarity** across two completely different human beings.
2. **Coordinator Threshold Inversion Bug:** In `BiometricLifecycleCoordinatorV10.enrollInitial`, the duplicate decision gate evaluated `maxSim >= duplicateFloor`. However, `duplicateFloor` was improperly assigned to `this.thresholds.dedupAmbiguousMax` (0.550) instead of `this.thresholds.dedupHardBlockMin` (0.720). Consequently, any candidate score $\ge 0.550$ triggered a hard 409 block, eliminating the ambiguous review safety zone.
3. **Severe Account PII Leakage:** Upon triggering duplicate detection, the backend fetched the matched user's profile from the `users` Firestore collection and returned `maskedPhone`, `maskedName`, `maskedUid`, `primarySkill`, `dailyRateDisplay`, and a clamped synthetic similarity percentage `Math.min(99, Math.max(74, ...))` to the unauthenticated applicant.

---

## 2. CALL GRAPH & DEFECT REPRODUCTION

### A. Execution Trace
```
Flutter Client: FaceEnrollmentScreen._captureAndSave()
  ├── Line 885: _camCtrl!.takePicture() captures full 12MP camera photo
  ├── Line 935: Base64 encodes full image into payload
  └── Line 931: BiometricService.instance.enrollBiometric(...)
        └── POST $baseUrl/enroll (/api/biometrics/v10/enroll)
              │
Backend: biometric_v10_routes.ts
  ├── Line 396: const imageBuffer = Buffer.from(imageBase64, 'base64');
  └── Line 398: await deps.engine.extractCanonicalEmbeddingFromAligned112(imageBuffer)
        │
        └── [DEFECT 1] CanonicalSFaceEngineV10:
              Line 155-160: sharp(aligned112ImageBuffer).resize(112, 112, { fit: 'cover' })
              Squishes full-body scene to 112x112 without face detection or alignment!
              SFace outputs distorted vector e_scene.
              │
Coordinator: BiometricLifecycleCoordinatorV10.enrollInitial()
  ├── Line 435: 1:N gallery search against active vault templates
  │     Cosine similarity(e_scene1, e_scene2) = 0.9596 (96%)!
  ├── Line 460: [DEFECT 2] duplicateFloor = this.thresholds.dedupAmbiguousMax (0.550)
  │     Since 0.9596 >= 0.550, isDuplicateBlock = true (HTTP 409)!
  └── Line 522-555: [DEFECT 3] Fetches Account 1 profile from Firestore
        Populates maskedPhone, maskedName, dailyRate, and simPercent!
```

### B. Empirical Reproduction Evidence
Running SFace on two unaligned room photos of distinct individuals resized directly to 112x112:
- Cosine similarity: **0.9596 (95.96%)**
- Expected genuine face similarity across sessions: $0.72 - 0.90$
- Expected impostor face similarity across individuals: $0.05 - 0.35$

Because the squashed images contained no aligned facial geometry, SFace treated the common environmental lighting and torso framing as the primary biometric feature, rendering the 1:N deduplication engine completely incapable of distinguishing different users.

---

## 3. REMEDIATION SUMMARY

1. **Mandatory Canonical Preprocessing (`CanonicalSFaceEngineV10`):**
   - Implemented `safeDecodeAndValidateImage`: enforces format magic bytes (JPEG/PNG/WebP), dimension bounds ($64 \le W, H \le 4096$), and decompression bomb limits ($\le 15\text{MB}$).
   - Implemented `detectFacesYuNet`: executes multi-scale YuNet neural detection ($[1, 3, 640, 640]$ BGR, strides 8, 16, 32) and NMS ($IoU \le 0.3$).
   - Implemented quality gates: rejects `NO_FACE_DETECTED`, `MULTIPLE_FACES_DETECTED`, `FACE_TOO_SMALL` ($< 60\times 60$), `FACE_OUT_OF_BOUNDS` ($< 85\%$ in frame), `EXTREME_POSE` ($yaw > 45^\circ$), and `EXCESSIVE_BLUR` (Laplacian variance $< 12.0$).
   - Implemented `alignFaceToCanonical112`: 5-point Umeyama similarity transform and bilinear affine warp to $112\times 112\times 3$ RGB.
   - Enforced nominal typing: `extractCanonicalEmbeddingFromAligned112` strictly requires `CanonicalAlignedFace112` ($112\times 112\times 3 = 37,632$ bytes). Raw buffers are rejected with `CANONICAL_EMBEDDING_FAILED`.

2. **Threshold Re-alignment (`BiometricLifecycleCoordinatorV10`):**
   - Corrected `duplicateFloor`: evaluates against `dedupHardBlockMin` (0.720) for `FACE_ALREADY_LINKED` (HTTP 409).
   - Scores between `dedupCleanMax` (0.363) and 0.720 yield `AMBIGUOUS_MATCH` (HTTP 202).
   - Scores $< 0.363$ proceed to clean enrollment.

3. **Privacy Leakage Elimination:**
   - Deleted all Firestore user profile reads in duplicate rejection handlers.
   - Removed all PII (`maskedPhone`, `maskedName`, `maskedUid`, `primarySkill`, `dailyRateDisplay`, `facialSimilarityPercent`, `rawCosineSimilarity`) from duplicate responses.
   - Returns an opaque, non-enumerable case reference: `CASE-[A-Z0-9]{8}`.
   - Updated Flutter client to display `DuplicateAccountResolutionSheet` with opaque case reference and zero PII.

---

## 4. SIGN-OFF & VERIFICATION

| Check | Expected | Observed | Status |
|---|---|---|---|
| Backend Test Suite | 880 passing | 880 passing (0 failing) | PASS |
| Regression Test Suite | 36 passing | 36 passing (0 failing) | PASS |
| Android Kotlin Compile | BUILD SUCCESSFUL | BUILD SUCCESSFUL (15s) | PASS |
| v19.2.3 Tag Hash | `8634a1813c84...` | `8634a1813c84...` | VERIFIED |
| v19.2.3 Release APK SHA-256 | `739f85746df3...` | `739f85746df3...` | VERIFIED |
