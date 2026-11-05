# KELASAGARA BIOMATCH · CROSS-RUNTIME PARITY & MODEL SUPPLY CHAIN (PARITY_REPORT.md)
**Audit Date:** 2026-10-10  
**Status:** COMPLETE (Track C Closure)  
**Governing Rule:** Gate GATE-S6-07  

---

## 1. Runtime Parity Matrix (Ticket C-02)

| Compared Runtimes | Test Samples ($N$) | Min Cosine | p1 Cosine | Median Cosine | Tolerance | Status |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| Node.js onnxruntime-node vs Python 3 onnxruntime | 200 | 1.0 | 1.0 | 1.0 | >= 0.9990 | **PASS** |

- **Cross-Runtime FNMR Shift:** 0.0% (Zero decision boundary flips detected).

---

## 2. Machine Learning Bill of Materials (ML-BOM) (Ticket C-05)

| Model Identifier | SHA-256 Digest | License | Provenance Source | Production Status |
| :--- | :--- | :---: | :--- | :---: |
| `yunet_2023mar` | `8f2383e4dd3cfbb4...` | Apache-2.0 | OpenCV Zoo (ShiqiYu) | **APPROVED PRIMARY DETECTOR** |
| `sface_2021dec` (FP32) | `0ba9fbfa01b5270c...` | Apache-2.0 | OpenCV Zoo (Zhong et al.) | **APPROVED PRIMARY RECOGNIZER** |
| `sface_2021dec_int8` | `2b0e941e6f16cc04...` | Apache-2.0 | ONNX Runtime Static PTQ | **APPROVED SECONDARY FILTER** |
| `mobilefacenet` | `cde3799f041eca6a...` | Non-Commercial | InsightFace MS1MV2 | **PROHIBITED IN PRODUCTION** |

- **Tamper Protection:** The inference engine strictly checks model SHA-256 digests on startup. Tampered weights immediately halt initialization.

---

## 3. Template Versioning & Migration (Ticket C-03)
- Active template tag: `sface_v1:0ba9fbfa:v1_bgr112:fp32`
- System refuses cross-model comparisons. Any migration requires full re-enrollment.

---

## 4. Quantization & Model Selection Closure (Ticket C-07)
- SFace INT8 yields **74.5% storage reduction** (37.4 MB -> 9.5 MB), but exhibits a **3.9% TAR drop** at tight FAR ($10^{-4}$).
- **Ship Decision:** FP32 SFace is selected as the primary verification engine. INT8 is retained exclusively as an optional candidate filter for 1:N deduplication.
