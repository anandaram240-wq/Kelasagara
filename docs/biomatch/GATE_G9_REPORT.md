# GATE G9 REPORT: SERVICES & API HARDENING

**Subsystem:** Kelasagara BioMatch V7  
**Gate:** **Gate G9** (Phase 9: Services and API)  
**Status:** **PASSED**  
**Release Readiness Level (RRL):** **RRL-0 (Research Prototype)**  
**Target Platform:** Firebase Spark Plan (Free Tier) | Standalone Node.js Tier 0 Backend  
**Branch:** `biomatch/v7-hardening`  
**Date:** 2026-10-10  

---

### 1. SUMMARY SPECIFICATION

| Field | Detail |
|---|---|
| **Gate** | **Gate G9 (Phase 9)** |
| **Status** | **PASSED** |
| **Evidence IDs** | **EV-043** (`backend/src/routes/face_routes.ts`, `backend/src/schemas/face_schemas.ts`, `backend/src/services/session_challenge_service.ts`), **EV-044** (`backend/src/tests/api_routes_integration.test.ts`), **EV-045** (`docs/biomatch/SERVICES_AND_API.md`) |
| **What Changed in Risk Register** | - **RISK-09 (API Oracle Probing & Timing Side-Channels):** Mitigated and verified via constant-time latency bucketing ($\ge 150\text{ms}$ padding on all outcomes) and uniform JSON envelope responses (Invariants I-08, I-23).<br/>- **RISK-17 (Unauthenticated Probe Injection):** Mitigated via mandatory Bearer token verification and 60s single-use cryptographic challenge nonces bound to UID and action (Invariants I-04, I-05). |
| **Decisions Needed from Owner** | Confirm Tier 0 backend deployment strategy: standalone Node.js server hosted locally during development (fanless M4 Mac), staged on external free web service container for prototype testing, while persistent database remains strictly in Cloud Firestore (`asia-south1`). |
| **Next Step** | **Proceed autonomously to PHASE 10:** Inference Redundancy, Model Lifecycle & Shadow Pipeline (`docs/biomatch/INFERENCE_REDUNDANCY.md`): design primary/shadow model execution, cold-start handling, and runtime health probing. |

---

### 2. GATE CRITERIA CHECKLIST

- [x] **Challenge Endpoint Operational:** `POST /api/biometrics/challenge` issues 60s cryptographic nonces bound to UID and action type (`ENROLLMENT` vs `VERIFICATION`).
- [x] **Injection & Replay Defense Enforced (Invariant I-04, I-05):** Cross-action and cross-user nonce usage strictly rejected (HTTP 403). Verified live in test suite.
- [x] **Constant-Time Latency Bucketing Verified (Invariant I-08, I-23):** Minimum 150ms latency floor enforced across all outcomes (including 404 and duplicate rejection), defeating timing oracle probes.
- [x] **Uniform API Envelope Adopted:** Standardized `UniformBiometricApiResponse` applied across all routes.
- [x] **1:1 Facial Verification Flow Operational:** `POST /api/biometrics/verify-1to1` (and alias `/verify-login`) matches probe vectors against enrolled templates with cosine similarity scoring.
- [x] **DPDPA Section 12 Right-to-Erasure Implemented:** `DELETE /api/biometrics/template` enforces caller authorization (cross-user deletion blocked with HTTP 403; own deletion succeeds and emits audit event).
- [x] **In-Memory IP Rate Limiter Active:** 60 req/min per IP limit protects free-tier Spark database quotas from automated abuse.
- [x] **Phase 9 Test Suite Passed Live (7/7 Passed Cleanly):** `api_routes_integration.test.ts` verified 100% cleanly.
