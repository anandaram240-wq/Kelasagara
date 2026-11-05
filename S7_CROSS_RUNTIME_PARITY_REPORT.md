# KELASAGARA BIOMATCH · STAGE S7 CROSS-RUNTIME PARITY REPORT (S7_CROSS_RUNTIME_PARITY_REPORT.md)

**Classification:** Differential Numerical Testing & Execution Engine Parity  
**Stage:** S7  
**Date:** 2026-10-11  
**Environments Compared:** Node.js v24.14.0 (`onnxruntime-node`) vs Python 3.9.6 (`onnxruntime`) on Apple Silicon M4.

---

## 1. Differential Testing Methodology

Cross-runtime divergence occurs when differing compiler optimizations, SIMD dispatching (NEON vs AVX), or float precision routines introduce small numerical deviations between inference runtimes. In biometric matching, if two identical face images produce divergent embeddings across runtimes, verification decisions near the decision threshold can drift.

Stage S7 measured differential numerical behavior using:
1. **Mathematical Cosine Metric:**
   $$\cos(a, b) = \frac{a \cdot b}{\|a\|_2 \|b\|_2}$$
2. **200 Golden Test Vectors:** Evaluated across identical model weights (`face_recognition_sface_2021dec.onnx`).
3. **Sequential Execution Repeatability:** Comparing multi-pass runs under identical thread counts.

---

## 2. Parity Test Results

| Parity Metric | Measured Value | Pre-Registered Tolerance Gate | Verdict |
| :--- | :---: | :---: | :---: |
| **Minimum Cosine Similarity** | `0.999998` | $\ge 0.9990$ | `PASS` |
| **1st Percentile Cosine** | `0.999999` | $\ge 0.9995$ | `PASS` |
| **Median Cosine Similarity** | `1.000000` | $\ge 0.9999$ | `PASS` |
| **Maximum Absolute Error (MAE)** | $4.17 \times 10^{-7}$ | $< 1.0 \times 10^{-4}$ | `PASS` |
| **Decision Disagreement Rate** | `0.0%` | $0.0\%$ | `PASS` |
| **Consecutive Pass Repeatability Delta** | `0.0` | $< 1.0 \times 10^{-5}$ | `PASS` |

---

## 3. Threshold Semantics and Authoritative Control

### 3.1 Cosine vs Distance
- The system operates strictly in **cosine similarity space** ($\in [-1.0, 1.0]$) over normalized vectors on the unit hypersphere $\mathbb{S}^{127}$.
- Higher values indicate greater facial similarity.
- For two normalized vectors $u, v$, Euclidean distance relates directly via:
  $$d^2(u, v) = 2 - 2(u \cdot v)$$

### 3.2 Authoritative Thresholds (Server-Enforced)
- **1:1 Verification Floor:** $0.74$ cosine similarity (provisional shadow-mode operating point).
- **1:N Duplicate Flagging Threshold:** $0.74$ cosine similarity.
- **Ambiguity Band:** $[0.65, 0.74]$ flags near-threshold candidates for manual inspection.
- Clients are strictly barred from supplying or altering decision thresholds.

### 3.3 Degenerate and Multiple-Face Inputs
- **Missing or Degenerate Faces:** If face detection fails to locate 5 landmarks or if cropped dimensions are $< 112\text{px}$, the request fails immediately at the quality gate with HTTP 400 (`FACE_NOT_DETECTED` or `POOR_QUALITY`).
- **Multiple Faces:** If the server detects $> 1$ face in the capture frame, the request fails closed with HTTP 400 (`MULTIPLE_FACES_DETECTED`) to prevent identity ambiguity.

---

## 4. Exit Gate S7-G04 Sign-Off

**Status:** `DONE-VERIFIED`  
**Evidence Artifact:** `evidence/s7/golden_vector_results.json`  
**Summary:** Bit-exact determinism across passes and cross-runtime parity ($\min \cos \ge 0.999998$) verified. Zero decision disagreement across runtimes.
