# KELASAGARA V15.0 BIOMETRIC ENGINE AUDIT
# REPORT 05: BIOMETRIC RECOGNITION CLAIMS & EMPIRICAL EVIDENCE AUDIT

**Document ID:** KLS-V15-EVAL-RES-001  
**Classification:** EMPIRICAL EVIDENCE & CLAIMS AUDIT  
**Target Architecture:** OpenCV SFace (128-D L2-normalized ONNX)  
**Audit Finding:** EMPIRICAL FIELD ACCURACY IS UNTESTED / CLAIMS DE-ESCALATED  
**Audit Date:** 2026-10-23  

---

## 1. FORENSIC AUDIT OF ACCURACY CLAIMS

Throughout previous engineering iterations (V10.0 through V13.0), the project documentation repeatedly stated that the Kelasagara biometric engine achieved:
- **"99.60% recognition accuracy"**
- **"Enterprise-grade Aadhaar Face RD parity"**
- **"Guaranteed 1:N deduplication up to 10,000 workers"**

The V15.0 audit investigated the origin, experimental methodology, and codebase evidence supporting these claims.

### Findings:
1. **Source of the 99.60% Figure:**  
   The 99.60% metric is cited verbatim from the published academic paper for OpenCV SFace:  
   *Zhong et al., "SFace: Sigmoid-Constrained Hypersphere Loss for Robust Face Recognition", IEEE Transactions on Biometrics, Identity, and Behavior (T-BIOM), 2021.*  
   This score was achieved on the academic **Labeled Faces in the Wild (LFW)** benchmark, which consists of high-quality, web-crawled celebrity photographs under curated conditions.
2. **IJB-C Benchmark:**  
   On the more challenging IARPA Janus Benchmark-C (IJB-C), the published SFace model achieves a True Acceptance Rate (TAR) of **92.80% at FAR = $10^{-4}$**.
3. **Repository Field Evaluation Reality:**  
   **No empirical evaluation has ever been conducted using actual or representative Indian gig workers.**  
   The repository contains zero operational test datasets, zero calibrated ROC curves, and zero demographic bias evaluations.

---

## 2. COMPARATOR TEST CORRECTNESS VS. BIOMETRIC ACCURACY

A critical distinction enforced by the V15 audit is the difference between:
- **Software Comparator Correctness:** The automated test suite (`threshold_governance.test.ts`, `biometric_matching.test.ts`) verifies that mathematical functions (`cosineSimilarity`, `dotProduct`, `evaluateVerification`) return expected boolean values when provided with synthetic floating-point arrays. These tests pass 100%.
- **Empirical Biometric Accuracy:** The real-world probability that an authentic worker in Mysore or Bengaluru will be correctly matched under midday sun or evening low-light conditions, and that two unrelated workers will not produce a false match.

**Passing software unit tests does not equal verified biometric accuracy.**

---

## 3. SUMMARY OF CURRENT EMPIRICAL EVIDENCE

```
================================================================================
EVIDENTIARY STATUS: BIOMETRIC RECOGNITION
================================================================================
[PASS]  1. Mathematical correctness of 128-D L2 normalization.
[PASS]  2. Correctness of cosine similarity comparator ([-1.0, 1.0]).
[PASS]  3. Separation of 1:1 threshold (0.363) from 1:N threshold (0.74).
[PASS]  4. SFace ONNX model integrity verified by SHA-256 hash.
--------------------------------------------------------------------------------
[UNVERIFIED] 5. False Match Rate (FMR) on South Asian / Indian demographic.
[UNVERIFIED] 6. False Non-Match Rate (FNMR) under low-cost camera sensors.
[UNVERIFIED] 7. FTA rate on darker skin tones (Fitzpatrick IV-VI).
[UNVERIFIED] 8. 1:N False Alarm Rate when gallery size N exceeds 100 templates.
================================================================================
FINAL CLASSIFICATION: FIELD ACCURACY UNTESTED (RELEASE BLOCKER)
================================================================================
```

---

## 4. RISK ASSESSMENT OF LIVE CANARY DEPLOYMENT

If the system were deployed to live identity gating using the uncalibrated reference threshold of `0.363`:
1. **Worker Disruption (False Rejections):**  
   If real-world FNMR reaches 5–10% under adverse field conditions, dozens of legitimate workers daily would be barred from clocking into shifts, causing wage loss, platform grievances, and support escalation.
2. **Fraud Risk (False Matches):**  
   If demographic clustering results in impostor similarity scores occasionally exceeding `0.363` (especially among male workers with similar facial hair or turbans), account sharing or proxy clock-ins would occur undetected.
3. **Sybil Deduplication Failures:**  
   At $\tau_{\text{dup}} = 0.74$, false duplicate alarms would increase as gallery size $N$ expands, overwhelming operations teams with false fraud flags.

---

## 5. CONCLUSION & RELEASE GATE IMPACT

Because empirical accuracy has not been validated on representative field data, the biometric engine **fails Production Gate G-01**. The system must remain strictly in **CONTROLLED TEST BUILD ONLY** mode. No live identity gating or automated worker account blocking may be enabled.
