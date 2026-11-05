# KELASAGARA BIOMATCH · STAGE S7 MODEL SUPPLY CHAIN AND BUILD REPRODUCIBILITY (S7_MODEL_SUPPLY_CHAIN.md)

**Classification:** Machine Learning Bill of Materials (ML-BOM) & Software Supply Chain Assurance  
**Stage:** S7  
**Date:** 2026-10-11  

---

## 1. Machine Learning Bill of Materials (ML-BOM)

To prevent supply chain poisoning and malicious model weight substitution, every neural network artifact is inventoried, signed with its SHA-256 digest, and tracked in the repository build ledger:

| Artifact Name | Canonical File Path | File Size | SHA-256 Digest | Origin / License | Role |
| :--- | :--- | :---: | :--- | :--- | :--- |
| **SFace FP32 (Primary)** | `backend/models/face_recognition_sface_2021dec.onnx` | 38,696,353 B | `0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79` | OpenCV Zoo (Apache-2.0) | 128-D Feature Embedding |
| **YuNet (Detector)** | `backend/models/face_detection_yunet_2023mar.onnx` | 232,589 B | `8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4` | OpenCV Zoo (Apache-2.0) | 5-Point Landmark Extraction |
| **SFace INT8 (Quantized)**| `backend/models/face_recognition_sface_2021dec_int8.onnx` | 9,896,933 B | `2b0e941e6f16cc048c20aee0c8e31f569118f65d702914540f7bfdc14048d78a` | OpenCV Zoo (Apache-2.0) | Resource-Constrained Fallback |

---

## 2. Integrity Enforcement at Startup (Invariant I-18)

In `backend/src/services/model_registry.ts` and `face_inference.ts`:
1. **Pre-Execution Check:** Prior to creating an `ort.InferenceSession`, the backend reads the on-disk model bytes and computes its SHA-256 digest.
2. **Fail-Closed Verification:** If the computed digest diverges by even a single bit from the committed digest, `ModelRegistry.verifyArtifactIntegrity` throws `MODEL_INTEGRITY_VIOLATION`, halting server initialization.
3. **Zero Silent Fallback:** The server will never silently load an unverified or corrupted model.

---

## 3. Exit Gate S7-G09 Sign-Off

**Status:** `DONE-VERIFIED`  
**Evidence Artifact:** `evidence/s7/model_supply_chain_tests.json`  
**Verification:** All 3 ONNX artifacts cryptographically verified and bound to signed ML-BOM.
