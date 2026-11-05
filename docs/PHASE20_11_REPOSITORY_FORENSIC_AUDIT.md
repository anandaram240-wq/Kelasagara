# PHASE 20.11: REPOSITORY FORENSIC AUDIT REPORT
**Role:** Principal Biometric Architect, Computer Vision Engineer, Backend Security Engineer & Data Integrity Auditor  
**System:** Kelasagara Multi-Factor Biometric Identity & Authentication Platform  
**Branch:** `security/phase20.11-legacy-template-isolation`  
**Parent Commit:** `e205b68e557896e4513f2d344c50fe576bbc7a77`  
**Grandparent Commit:** `56ea4792c8a54ca5e76a1f62de3dcd621f386260`  
**Parent Phase:** V20.10 Capture Wire Contract & Hotfix  
**Date:** November 1, 2026  

---

## 1. EXECUTIVE SUMMARY & ANCESTRY VERIFICATION

Before applying any code changes for Phase 20.11, a complete cryptographic and git forensic audit of the repository state was conducted. The ancestry chain from protected release `v19.2.3-release` through V20.9, V20.10, and the canonical face preprocessing hotfix was verified without deviation.

```
(v19.2.3-release: 8634a18) ───► ... ───► (V20.9: af84761)
                                              │
                                              ▼
                                    (V20.10: 56ea479)
                                              │
                                              ▼
                             (Hotfix Canonical: e205b68)
                                              │
                                              ▼
                      [Phase 20.11 Legacy Isolation: HEAD]
```

### 1.1 Verified Cryptographic Checksums & Artifacts

| Artifact | Location | Expected SHA-256 Checksum | Verified Runtime Checksum | Status |
| :--- | :--- | :--- | :--- | :--- |
| **Protected Release Tag** | `v19.2.3-release` | Commit `8634a1813c84fccc73b8944803b6bd541f5e2326` | Commit `8634a1813c84fccc73b8944803b6bd541f5e2326` | **VERIFIED PASS** |
| **Release APK** | `Kelasagara-v19.2.3-release.apk` | `739f85746df3cd1fb6c315590147907918a3829976d0381b8eae358c743176ce` | `739f85746df3cd1fb6c315590147907918a3829976d0381b8eae358c743176ce` | **VERIFIED PASS** |
| **SFace ONNX Model** | `backend/models/face_recognition_sface_2021dec.onnx` | `0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79` | `0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79` | **VERIFIED PASS** |
| **YuNet ONNX Model** | `backend/models/face_detection_yunet_2023mar.onnx` | `8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4` | `8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4` | **VERIFIED PASS** |

---

## 2. FORENSIC INSPECTION OF HOTFIX COMMIT (`e205b68`)

Inspection of `git diff 56ea479..e205b68` confirmed that commit `e205b68` addressed the root cause of the false duplicate-account detection defect across 23 committed source files (+3,212 insertions, -124 deletions):

1. **Mandatory Neural Face Detection & 5-Point Umeyama Alignment:**
   - Pre-hotfix callers in `BiometricService` bypassed face detection and resized full camera scenes directly into 112x112 crops.
   - Hotfix introduced `extractCanonicalEmbeddingFromOriginalImage` which enforces YuNet neural face detection (at 640x640), quality gates (single face, >=60x60, in-bounds >=85%, yaw <=45 deg, Laplacian variance >=12.0), and 5-point Umeyama canonical landmark alignment before SFace 128-D embedding extraction.

2. **Deduplication Threshold Restoration:**
   - Corrected `duplicateFloor` in `BiometricLifecycleCoordinatorV10` from `this.thresholds.dedupAmbiguousMax` (0.550) to `this.thresholds.dedupHardBlockMin` (0.720).
   - Re-established the designated ambiguous review zone $[0.3630, 0.7200)$ returning HTTP 202 instead of hard-blocking with HTTP 409.

3. **PII Elimination in Duplicate Rejection Payloads:**
   - Eradicated leakage of matched account name, phone number, primary skill, masked UID, and clamped similarity score percentages.
   - Replaced with opaque `CASE-XXXXXXXX` references and privacy-safe resolution sheets in Flutter.

---

## 3. AUDIT CONCLUSION

The repository ancestry is unbroken and fully consistent with all protected release rules. No production writes, migrations, or deployments were performed. All frozen ONNX neural model hashes match the official OpenCV Zoo frozen weights.
