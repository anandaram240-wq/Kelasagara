# KELASAGARA V15.0: THRESHOLD & CONFIGURATION AUDIT REPORT

**Project:** Kelasagara Worker Marketplace Biometric Subsystem  
**Audit Date:** October 23, 2026  
**Auditor:** Principal Biometric Systems Architect & Security Reviewer  
**Classification:** CONTROLLED TEST BUILD ONLY — RELEASE BLOCKER REMEDIATION  
**Primary Files Audited:**
- [`backend/src/config.ts`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/backend/src/config.ts)
- [`backend/src/routes/face_routes.ts`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/backend/src/routes/face_routes.ts)
- [`backend/src/services/account_lifecycle.ts`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/backend/src/services/account_lifecycle.ts)
- [`backend/src/services/biometric_matching.ts`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/backend/src/services/biometric_matching.ts)
- [`backend/src/services/biometric_enrollment.ts`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/backend/src/services/biometric_enrollment.ts)

---

## 1. Executive Summary & Critical Finding

During the V15 forensic audit of all code paths that make biometric matching decisions, an independent investigation uncovered that while the V14 remediation successfully corrected the 1:1 login verification endpoint (`/verify-1to1`), **a critical secondary threshold conflation bug remained in the worker shift re-verification service** (`AccountLifecycleService.reVerifyWorker` in [`backend/src/services/account_lifecycle.ts`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/backend/src/services/account_lifecycle.ts#L142)).

Specifically, `reVerifyWorker` evaluated 1:1 worker identity re-verification against `config.duplicateThreshold` (`0.74`) rather than `config.verificationThreshold` (`0.363`). As a result, genuine workers exhibiting authentic biometric similarity scores between `0.363` and `0.739` were rejected and denied shift activation.

This defect has been remediated in V15 and verified through targeted unit and integration regression tests. Additionally, bulletproof runtime configuration governance was implemented in `config.ts` to prevent silent corruption, out-of-range thresholds, `NaN` vulnerabilities, and accidental production activation without approved calibration.

---

## 2. Comprehensive Code Path Audit

Every matching and threshold evaluation path across the entire backend repository was inspected:

| Subsystem / Endpoint | Code Location | Claimed Metric | Threshold Used | Operational Policy | Status in V15 |
|:---|:---|:---|:---:|:---|:---:|
| **1:1 Login Verification** (`/verify-1to1`, `/verify`) | [`backend/src/routes/face_routes.ts#L368`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/backend/src/routes/face_routes.ts#L368) | Cosine Sim $\mathbb{S}^{127}$ | $\tau = 0.363$ | `isMatch = similarity >= verificationThreshold` | **REPRODUCED & VERIFIED** |
| **1:1 Worker Shift Re-verification** (`/re-verify`) | [`backend/src/services/account_lifecycle.ts#L142`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/backend/src/services/account_lifecycle.ts#L142) | Cosine Sim $\mathbb{S}^{127}$ | $\tau = 0.363$ (Was 0.74) | Shift activation for 10 hours if $\ge \tau_{\text{verify}}$ | **DEFECT FIXED IN V15** |
| **1:N Registration Duplicate Screening** (`/enroll`) | [`backend/src/services/biometric_enrollment.ts#L202`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/backend/src/services/biometric_enrollment.ts#L202) | Cosine Sim $\mathbb{S}^{127}$ | $\tau_{\text{dup}} = 0.74$<br>$\tau_{\text{hard}} = 0.90$ | Intercept duplicate, route to `pending_review`, zero automated approval | **VERIFIED SEPARATE** |
| **1:N Cross-Account Fraud Screening** (`/cross-account-check`) | [`backend/src/routes/face_routes.ts#L874`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/backend/src/routes/face_routes.ts#L874) | Cosine Sim $\mathbb{S}^{127}$ | $\tau_{\text{dup}} = 0.74$<br>$\tau_{\text{hard}} = 0.90$ | $s \ge 0.90 \to \text{HARD BLOCK}$<br>$0.74 \le s < 0.90 \to \text{FLAG REVIEW}$ | **VERIFIED SEPARATE** |
| **1:N Registration Ambiguity Review** | [`backend/src/services/biometric_matching.ts#L118`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/backend/src/services/biometric_matching.ts#L118) | Cosine Sim $\mathbb{S}^{127}$ | $\tau_{\text{amb}} = 0.65$ | Routes to administrative review (`RRL-0` Policy) | **VERIFIED SEPARATE** |
| **1:N Advisory Score Floor** | [`backend/src/services/firestore_biometric_repository.ts#L330`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/backend/src/services/firestore_biometric_repository.ts#L330) | Cosine Sim $\mathbb{S}^{127}$ | $\tau_{\text{floor}} = 0.363$ | Logs top-3 candidates for empirical score audit | **VERIFIED SEPARATE** |

---

## 3. Metric and Vector Compatibility Verification

1. **Similarity Function:**
   Authoritative matching uses [`cosineSimilarity(a, b)`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/backend/src/services/biometric_matching.ts#L8):
   $$\text{sim}(a, b) = \frac{a \cdot b}{\|a\|_2 \|b\|_2}$$
   Because all vectors produced by OpenCV SFace and the backend preprocessing pipeline are L2-normalized onto the unit hypersphere $\mathbb{S}^{127}$ ($\|v\|_2 = 1.0$), this metric is identical to the Euclidean dot product.
2. **Directionality:**
   Similarity values range in $[-1.0, 1.0]$. A value of $+1.0$ indicates identical direction (exact match); $0.0$ indicates orthogonality; negative values indicate opposite vectors. The decision rule is strictly monotonic:
   $$\text{Decision}(s) = \begin{cases} \text{MATCH / ACCEPT} & \text{if } s \ge \tau \\ \text{REJECT / NON-MATCH} & \text{if } s < \tau \end{cases}$$
3. **Pipeline Invariance (Invariant I-06):**
   The compared vectors are generated strictly by:
   - Model: OpenCV Zoo SFace 2021dec (`face_recognition_sface_2021dec.onnx`), 128-D Float32 output.
   - Preprocessing: `PREPROC_V1_UMEYAMA_112_RGB_RAW255` (Umeyama 5-point affine transformation to 112×112 RGB with $[0, 255]$ raw scaling).
   - Invariant I-06 rejects comparisons between vectors generated by different model IDs or preprocessing IDs.

---

## 4. Client Tampering and Influence Analysis

- **Client Vector Submission:** Strictly blocked. The backend middleware [`checkForbiddenVectorFields`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/backend/src/routes/face_routes.ts#L42) intercepts any client request containing `probeVector`, `embedding`, or `vector` and rejects it with `400 Bad Request`.
- **Client Threshold Submission:** No client request parameter or header can specify, modify, or override the matching threshold. All thresholds are loaded server-side exclusively from environment variables or trusted configuration.
- **Client Fallback Matching:** Audited and confirmed: The Flutter client contains **zero local fallback gallery scans**. The `biometric_vault` collection is blocked to client reads (`allow read, write: if false;` in [`firestore.rules`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/firestore.rules#L718)).

---

## 5. Threshold Provenance & Governance Framework

The threshold configuration in [`backend/src/config.ts`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/backend/src/config.ts) was restructured to enforce strict governance:

### A. Four-Tier Threshold Classification
1. **Published Reference Threshold (`0.363`):**
   Derived from the official OpenCV Zoo SFace documentation (`face_recognition_sface_2021dec.onnx`). Documented on standard academic benchmarks (LFW 99.60%, IJB-C TAR 92.80% @ FAR 1e-4). **It is NOT production-calibrated for Kelasagara workers.**
2. **Development / Test Threshold (`0.363`):**
   Used by hermetic automated test suites and local integration harnesses to assert deterministic comparator behavior.
3. **Candidate Evaluation Threshold:**
   Tracked in calibration manifests during offline empirical evaluations against representative target datasets.
4. **Production Calibrated Threshold:**
   Requires formal sign-off on an empirical evaluation report across the target population, lighting distributions, and camera hardware. Currently **UNVALIDATED**.

### B. Safe Parsing & Bounds Enforcement
The helper function `parseThreshold()` prevents silent configuration failures:
- Empty strings (`"   "`) $\to$ throws explicit `[ThresholdGovernance]` error.
- Non-numeric strings (`"abc"`, `"NaN"`) $\to$ throws explicit error.
- Infinite values (`"Infinity"`, `"-Infinity"`) $\to$ throws explicit error.
- Out-of-bounds values ($< 0.10$ or $> 0.80$ for verification) $\to$ throws explicit error.

### C. Hierarchy and Monotonicity Checks
`validateThresholdGovernance()` enforces mathematical consistency:
$$\tau_{\text{verify}} < \tau_{\text{dup}} < \tau_{\text{hard}}$$
$$\tau_{\text{ambiguity}} \le \tau_{\text{dup}}$$
$$\tau_{\text{advisoryFloor}} \le \tau_{\text{verify}}$$

### D. Production Fail-Safe Gate
If `process.env.NODE_ENV === "production"`, biometric identity gating cannot be activated unless `PRODUCTION_BIOMETRIC_CALIBRATION_APPROVED === "true"`. If an operator attempts to enable automated identity gating in production without approved calibration, the service **fails closed and halts startup**.

---

## 6. Audit Conclusion

The threshold configuration has been hardened and proven safe against misconfiguration, silent degradation, and malicious input. The 1:1 worker re-verification bug has been completely remediated. Automated identity gating remains safely disabled in production.
