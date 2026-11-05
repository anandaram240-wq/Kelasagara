# KELASAGARA BIOMETRIC ENGINE V12.0
# Formal Contradiction Register & Architecture Discrepancy Matrix
## Systematic Reconciliation of Conflicting Code Paths, Mismatched Schemas, and Unsupported Claims

**Document ID:** `REP-V12-CONTRADICTION-01`  
**System:** Kelasagara Biometric Platform  
**Status:** Approved Remediation Register  
**Version:** 12.0.0-AUDIT  
**Date:** 2026-10-23  

---

## 1. Executive Summary

This register formally documents the eight critical contradictions identified during the V12.0 audit between previous documentation (V8.0/V10.0), client-side Flutter implementation, backend TypeScript service implementation, and deployed Firestore security configurations.

---

## 2. Contradiction Register Matrix

| ID | Title / Domain | Previous Claim / Client Assumption | Actual Code / Backend Reality | Forensic Root Cause | Required V12.0 Remediation |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **C-01** | **Forbidden Vector Policy vs Request Payload** | `face_enrollment_screen.dart` sends `probeVector: nativeResult.embedding.toList()` to `enrollBiometric`. | `backend/src/routes/face_routes.ts` applies `checkForbiddenVectorFields` middleware, rejecting `probeVector` with HTTP 400. | Backend author added Ticket T-01 security rule without removing `probeVector` parameter from client Flutter service. | **Remove `probeVector` from client network payload.** Pass only bona fide `imageBase64` for server inference. |
| **C-02** | **Representation Schism (SFace vs Geometric)** | V10.0 claimed SFace ONNX is the primary model, while unit tests and client fallback evaluated Whitened Procrustes landmarks. | Both models produce 128-d vectors, but SFace resides on a convolutional feature manifold, while Procrustes resides on an orthogonal geometric manifold. | Conflation of dimensionality ($D=128$) with representation equivalence. | **Designate SFace as the single authoritative recognition model in `biometric_vault`.** Restrict geometry strictly to on-device quality gating. |
| **C-03** | **Biometric Vault Read Permissions** | V8.0 claimed zero client reads of `biometric_vault` (`allow read, write: if false;`). | Commit `1020693` updated `firestore.rules` to `allow read: if isSignedIn();` to facilitate client fallback 1:N scan. | Developer unblocked permission denial on client fallback by relaxing security rules rather than routing through trusted backend. | **Lock down `firestore.rules` immediately.** Set `allow read, write: if false;` on `biometric_vault`. Admin SDK only. |
| **C-04** | **Client-Side 1:N Vault Download** | Architecture claims Aadhaar-inspired server-authoritative matching. | `biometric_service.dart` (`_directFirestoreEnroll` & `crossAccountCheck`) downloads 200–500 biometric templates to the mobile device. | Failure-handling fallback attempted to replicate complete backend deduplication engine on mobile client. | **Eliminate client-side vault downloads.** If backend is unreachable, fail closed with `technicalFailureRetry`. |
| **C-05** | **Cross-Account Endpoint Contract Mismatch** | Flutter `crossAccountCheck` posts `{'embeddingBase64': base64img}` (Float32 buffer). | Backend route `POST /cross-account-check` expects `{'imageBase64': string}` (JPEG/PNG image buffer). | Independent development of client and backend endpoints without shared contract test. | **Align contract to `imageBase64`.** Client transmits transient face crop; server runs SFace inference. |
| **C-06** | **Universal Biometric Threshold Conflation** | System deployed thresholds `0.38`, `0.74`, and `0.90` interchangeably across models. | `0.38` is SFace cosine threshold on LFW; `0.74` was calibrated on synthetic landmark geometry; `0.90` was an arbitrary hard block cutoff. | Transferring empirical thresholds across disjoint representation spaces without revalidation. | **Separate score functions.** Calibrate 1:1 verify at $	au_{	ext{verify}} = 0.38$ and 1:N duplicate screening at $	au_{	ext{dedup}} = 0.68$ on SFace. |
| **C-07** | **Synthetic Unit Tests vs Biometric Performance** | V10.0 claimed $0.00\%$ FMR and $0.00\%$ FNMR based on 100 jitter trials and 500 stranger pairs. | The 100 trials were synthetic noise perturbations on one landmark set; the 500 pairs were generated from two artificial archetypes. | Failure to distinguish unit/regression tests from ISO/IEC 19795-1 statistical evaluations on independent subjects. | **Relabel test evidence.** Document sample size upper bounds ($3/N$) and declare production operational bounds honestly. |
| **C-08** | **YuNet Model License Discrepancy** | V10.0 License Audit CSV claimed YuNet is licensed under Apache 2.0. | Official OpenCV Zoo model directory README states YuNet is licensed under **MIT License**. | Assumption that all OpenCV Zoo models share SFace's Apache 2.0 license. | **Correct license manifest.** YuNet is MIT licensed; SFace is Apache 2.0 licensed. Both are commercially permissible. |
