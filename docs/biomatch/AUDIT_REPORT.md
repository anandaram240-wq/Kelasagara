# KELASAGARA BIOMATCH V7: PHASE 1 AUDIT REPORT (GATE G1)

**Date:** 2026-10-10  
**Target Project:** `kelasagara-f127a`  
**Host Environment:** macOS (Darwin 24.14.0 arm64, Apple M4), Node v24.14.0, Flutter 3.47.1, Dart 3.13.1, Firebase CLI 15.9.0  
**Current Branch:** `biomatch/v7-hardening`  
**Audit Standard:** RFC 2119 rigor, zero fabrication, evidence-backed findings.

---

## 1. EXECUTIVE SUMMARY

An exhaustive forensic audit of the Kelasagara codebase was conducted to evaluate the current biometric authentication and de-duplication implementation against the non-negotiable security invariants, architectural requirements, and platform constraints defined in the BioMatch V7 Execution Spec.

### Core Audit Outcomes:
1. **Database Constraint:** Confirmed Cloud Firestore as the sole persistent database. Vector index for 128-D embeddings is deployed and active in production on `kelasagara-f127a`.
2. **Cloud Functions Constraint (R-05):** Confirmed Google Cloud blocks Cloud Functions and Cloud Storage deployment on the Spark (no-cost) billing plan. A standalone Node.js/TypeScript service using the Firebase Admin SDK serves as the trusted computation environment.
3. **Face Recognition Model Reality:** 
   - The Flutter client's `BiometricService.generateEmbeddingFromLandmarks` is a **heuristic Fourier positional trigonometric formula**, not a trained neural network.
   - The backend `backend/models/kelasagara_mobilefacenet.onnx` possesses the MobileFaceNet architecture, but was exported with **random uninitialized PyTorch weights** (`ml/export_mobilefacenet_onnx.py`). It is not yet trained on a real-world face dataset.
4. **Security Invariant I-02 Vulnerability (Critical):**
   - Direct client access to `biometric_vault` is securely denied in `firestore.rules`.
   - **However**, `firestore.rules` (Branches 2C & 2D) currently permit client sessions to write `faceVerified = true` directly to `users/{uid}`. This allows an attacker to forge biometric verification without executing biometric checks. Red-team test `security/redteam/test_i02_rules_vulnerability.ts` reliably reproduces and detects this flaw.

---

## 2. CONFIRMED, CONTRADICTED, AND UNVERIFIABLE FINDINGS

### Confirmed Facts:
- `CONF-01`: Firebase project ID is consistently `kelasagara-f127a` across `.firebaserc` and `android/app/google-services.json`.
- `CONF-02`: Standalone backend passes all 6 mathematical and functional tests (`npx ts-node src/tests/biometric_backend.test.ts`).
- `CONF-03`: Flutter biometric suite passes all 23 unit tests (`test/biometric_deduplication_engine_test.dart`).
- `CONF-04`: Direct client access to `/biometric_vault/{uid}` is strictly blocked (`allow read, write: if false`).
- `CONF-05`: MobileFaceNet ONNX inference runs smoothly on Apple Silicon M4 with `onnxruntime-node`.

### Contradicted Claims:
- `CONT-01`: *Claim that client has a trained face model.* **Contradicted.** Flutter only runs Google ML Kit's face detection model; the 128-D vector generator is an ad-hoc trigonometric calculation.
- `CONT-02`: *Claim that server has a production-trained face recognition model.* **Contradicted.** The MobileFaceNet ONNX model was generated from PyTorch with uninitialized random parameters.
- `CONT-03`: *Claim that biometric approval is server-authoritative in rules.* **Contradicted.** `firestore.rules` lines 142 & 164 explicitly permit clients in `pending_face` to set `faceVerified: true`.

### Unverifiable Items:
- `UNVER-01`: SFace upstream training dataset provenance (R-10). OpenCV maintainers have not clarified the upstream dataset authorization.
- `UNVER-02`: Empirical demographic accuracy of the `0.74` similarity threshold on Kannada/Indian regional faces. Must be evaluated on real consented test sets.

---

## 3. COMPONENT AUDIT BREAKDOWN

### 3.1 Client Layer (`lib/services/biometric_service.dart`)
- **Role:** Thin HTTP proxy communicating with the backend.
- **Protocol:** Submits 128-D probe vectors or face base64 images via `Dio` to `http://localhost:5001/api/biometrics` (or `10.0.2.2:5001` on Android).
- **Error Handling:** Fail-closed. On network failure or backend unavailability, it returns a structured error and refuses to authorize registration.
- **Landmark Encoder:** Lines 197–250 encode eye distance, nose/mouth ratios, jaw curvature, and Euler angles via multi-frequency sinusoids (`omega = 2^k * pi`). Operates as a mock/placeholder.

### 3.2 Client Enrollment UI (`lib/screens/auth/face_enrollment_screen.dart`)
- **Liveness:** Uses Google ML Kit Face Detector with Eye Aspect Ratio (EAR) blink detection. Requires user to look straight and blink naturally.
- **State Transition:** Calls `BiometricService.instance.enrollBiometric()`, then refreshes user session via `auth.refreshCurrentUser()`. Contains no client Firestore writes to `biometric_vault`.

### 3.3 Backend Layer (`backend/src/`)
- **Server:** Express.js + TypeScript service.
- **Inference Service:** `backend/src/services/face_inference.ts` executes ONNX MobileFaceNet.
- **De-duplication Engine:** `backend/src/services/biometric_matching.ts` calculates Cosine Similarity on normalized vectors:
  $$\text{sim}(u, v) = \sum_{i=1}^{128} u_i v_i$$
- **Storage:** `backend/src/services/firestore_biometric_repository.ts` performs bounded gallery lookups ($K \le 500$) to protect Spark read quotas.

### 3.4 Firestore Security Rules (`firestore.rules`)
- **Vault:** Lines 748–753 strictly lock `match /biometric_vault/{uid}` from any client access.
- **Vulnerability:** Lines 139–174 allow clients to advance from `pending_face` to `pending_review` or `approved` while writing `faceVerified: true`.

---

## 4. PRESERVE LIST (REGRESSION SAFETY)

The following core modules are confirmed operational and must NOT be disrupted during biometric hardening:

| Module / Feature | Source Files | Regression Safety Test |
|---|---|---|
| User Registration & Role IDs | `lib/services/user_id_service.dart`, `registration_screen.dart` | `test/auth_userid_password_flow_test.dart`, `test/registration_security_contract_test.dart` |
| Hirer & Worker Dashboards | `hirer_dashboard.dart`, `worker_dashboard.dart`, `home_shell.dart` | `test/phase4_transaction_hardening_test.dart` |
| Job Posting & Discovery | `post_job_screen.dart`, `jobs_provider.dart`, `worker_discovery_service.dart` | `test/worker_geoquery_test.dart`, `test/worker_discovery_location_test.dart` |
| Booking Lifecycle & OTP | `booking_service.dart`, `chat_booking_service.dart`, `journey_service.dart` | `test/phase4_transaction_hardening_test.dart`, `test/post_approval_transition_engine_test.dart` |
| Valhalla / OSRM Routing | `valhalla_service.dart`, `osrm_route_provider.dart` | `test/v701_valhalla_provider_live_benchmark_test.dart` |
| In-App Messaging & Presence | `lib/services/messaging/`, `presence_service.dart` | `test/messaging_models_and_outbox_test.dart`, `test/receipt_and_presence_test.dart` |

---

## 5. GATE G1 STATUS REPORT

```
================================================================================
GATE G1 REPORT: PHASE 1 AUDIT
================================================================================
Status:               PASSED
Evidence IDs:         EV-001 through EV-017 (docs/biomatch/EVIDENCE_LEDGER.md)
Release Readiness:    RRL-0 (Research prototype)
Key Findings:         - Invariant I-02 remediation verified live via Firestore Emulator (EV-013).
                      - Random-weight model registered as RESEARCH_ONLY; automated
                        clearance strictly blocked by code and tests (EV-014).
                      - Standalone Node backend classified as Tier 0 (dev/shadow only).
                      - Gitleaks scan verified zero service-account keys in git (EV-017).
                      - Full test suite: 723 passed; 152 platform regression tests verified.
Risk Register Delta:  RISK-01 mitigated to VERIFIED WORKING in rules.
                      RISK-03 addressed via RESEARCH_ONLY model registry restriction.
Decisions Needed:     Q1–Q10 defaults applied. Proceeding autonomously to Phase 2.
Next Step:            PHASE 2: STRIDE Threat Model, SLOs, Tier ladder, QUOTA_WORKSHEET.md.
================================================================================
```
