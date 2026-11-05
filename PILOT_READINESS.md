# STAGE S2 PILOT READINESS DECISION & OPERATIONAL CHECKLIST
**Subsystem:** Kelasagara BioMatch V9 / Stage S2  
**Target:** Pilot Shadow Deployment (Karnataka Sovereign Pilot)  
**Date of Decision:** 10 October 2026  
**Auditor:** Principal Biometrics Architect, Application Security Engineer & ML Systems Lead

---

## 1. Executive Pilot Decision

### **OPERATIONAL DECISION: CLEARED FOR PILOT SHADOW DEPLOYMENT (STAGE S2)**

The Kelasagara BioMatch subsystem is certified as **Stage S2 Pilot Ready** under strict **PILOT_SHADOW** operating governance:
- **Zero Automated Approvals:** 100% of unique human enrollments route to `accountStatus: 'pending_review'` and require human administrative verification.
- **Fail-Closed Standard:** Zero automatic approvals on any inference failure, network timeout, corrupt frame, or nonce replay.
- **Client Vector Prohibited:** Client mobile apps are physically restricted to transmitting raw `imageBase64` camera frames. Client vectors are rejected with HTTP 400.
- **Licensed Neural Backbone:** Cleared OpenCV Zoo SFace (Apache-2.0) with redundant FP32/INT8 runtime. Random / uninitialized weights permanently segregated to `ml/research_only/`.

---

## 2. Gate Verification & Audit Checklist

| Gate Index | Area | Requirement | Status | Evidence / Artifact |
|:---:|:---|:---|:---:|:---|
| **Gate 1** | **Weight Provenance** | Pinned SHA-256 digests; zero unverified weights in execution path | **PASSED** | `AUDIT_V9.md`, `model_registry.ts` |
| **Gate 2** | **Client Security** | Zero client-side vector emissions; raw frames only | **PASSED** | Ticket T-01, `face_routes.ts`, `api_routes_integration.test.ts` (Test 2B) |
| **Gate 3** | **Injection Defense** | Cryptographic challenge nonces bound to UID with 60s TTL | **PASSED** | Ticket T-01, `session_challenge_service.ts`, `api_routes_integration.test.ts` (Test 3, 4) |
| **Gate 4** | **Preprocessing Parity** | OpenCV Zoo C++ contract: raw [0..255] RGB float, Umeyama 5-point alignment | **PASSED** | Tickets T-03 & T-04, `PREPROCESSING.md`, `golden_vector_parity.test.ts` |
| **Gate 5** | **Dual-Model Parity** | FP32 vs INT8 correlation > 0.60 on identical inputs; cross-model match forbidden | **PASSED** | Tickets T-04 & T-08, `inference_redundancy.test.ts` |
| **Gate 6** | **Decision Policy** | Zero automated approval; raw score acts as advisory metric only | **PASSED** | Tickets T-02 & T-05, `ScoreRecordPolicy`, `research_model_governance.test.ts` |
| **Gate 7** | **Audit Trail Integrity** | Tamper-evident hash-chained ledger; zero PII in audit records | **PASSED** | Ticket T-06, `audit_service.ts`, `tamper_evident_audit.test.ts` |
| **Gate 8** | **DPDPA Privacy** | Bilingual Kannada/English notice; voluntary consent V2; Document KYC alternative | **PASSED** | Ticket T-07, `face_enrollment_screen.dart`, `dpdpa_privacy_compliance.test.ts` |
| **Gate 9** | **Crypto-Shredding** | Permanent template erasure upon user request (DPDPA Sec 12) | **PASSED** | `deleteTemplate` in `firestore_biometric_repository.ts` |
| **Gate 10** | **Sovereign Hosting** | Indian cloud hosting (`asia-south1`, Mumbai); strict TLS 1.3 | **PASSED** | `ADR_DEPLOYMENT_PILOT.md` |
| **Gate 11** | **Evaluation Harness** | Full DET/ROC metrics, FNMR at FMR 1e-3/1e-4, 95% Bootstrap CIs | **PASSED** | Ticket T-11, `evaluation_harness.ts`, `phase_b_measurements.test.ts` |
| **Gate 12** | **Calibration Guard** | Startup verification of Ed25519-signed `calibration.json` | **PASSED** | Ticket T-12, `calibration_guard.ts`, `calibration.json` |
| **Gate 13** | **Dedup Scale Projections** | Cumulative platform false alarm calculations for $N \in [500, 10000]$ | **PASSED** | Ticket T-13, `dedup_calculator.ts` |
| **Gate 14** | **Quality Gate** | ISO/IEC 29794-5 (OFIQ) frame gating (IPD >= 35px, pose, blur) | **PASSED** | Ticket T-14, `quality_gate.ts` |
| **Gate 15** | **Quota Protection** | Spark free-tier daily read/write monitoring and read-throttling | **PASSED** | Ticket T-15, `quota_monitor.ts` |
| **Gate 16** | **Model Segregation** | Random PyTorch export isolated to `ml/research_only/` | **PASSED** | Ticket T-16, `ml/research_only/README.md` |
| **Gate 17** | **Device Attestation** | Hardware integrity verification + frame provenance binding | **PASSED** | Ticket T-17, `device_attestation.ts`, `phase_c_security_and_lifecycle.test.ts` |
| **Gate 18** | **Rental Defense** | Mandatory 10h shift re-verification + hardware device binding | **PASSED** | Ticket T-18, `account_lifecycle.ts`, `phase_c_security_and_lifecycle.test.ts` |
| **Gate 19** | **Interactive PAD** | Multi-gesture challenge (blink/smile/turn) with static photo block | **PASSED** | Ticket T-19, `presentation_attack_defense.ts`, `phase_c_security_and_lifecycle.test.ts` |
| **Gate 20** | **RAM Dedup Index** | In-memory cosine similarity cache shielding Spark 50k reads | **PASSED** | Ticket T-20, `in_memory_biometric_index.ts`, `phase_c_security_and_lifecycle.test.ts` |

---

## 3. Defect Remediation Summary (D1 to D8)

- **D1 (Client-Vector Emission):** RESOLVED. Authoritative server inference only.
- **D2 (Auto-Approval on Uncalibrated Weights):** RESOLVED. Tier set to `PILOT_SHADOW`. Zero auto-approval.
- **D3 (Thresholds Acting On Uncalibrated Scores):** RESOLVED. `ScoreRecordPolicy` implemented. Top-3 advisory matches stored.
- **D4 (Preprocessing Normalization Mismatch):** RESOLVED. `[0..255]` raw RGB + closed-form pure TypeScript Umeyama solver implemented.
- **D5 (Uncalibrated Random Weights in Repo):** RESOLVED. Segregated to `ml/research_only/`.
- **D6 (Lack of Granular Multilingual Consent):** RESOLVED. Consent V2 implemented with separate verification and research opt-ins in Kannada and English.
- **D7 (PII in Audit Logs):** RESOLVED. `sanitizeAuditMetadata` strips all biometric payloads and phone numbers.
- **D8 (Cross-Model Vector Pollution Risk):** RESOLVED. `modelId` and `preprocessVersion` checks enforced at repository level.

---

## 4. Runbook for Test Verification

To verify the complete test suite from terminal:
```bash
cd backend
npm run build
node --test dist/tests/golden_vector_parity.test.js
node --test dist/tests/inference_redundancy.test.js
node --test dist/tests/research_model_governance.test.js
node --test dist/tests/api_routes_integration.test.js
node --test dist/tests/phase_b_measurements.test.js
```
