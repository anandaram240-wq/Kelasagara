# KELASAGARA BIOMATCH · STAGE S7 ASSURANCE CASE (S7_ASSURANCE_CASE.md)

**Classification:** Structured Goal Structuring Notation (GSN) Assurance Case  
**Stage:** S7  
**Date:** 2026-10-11  
**Framework:** Claims, Arguments, Evidence, Defeaters, and Explicit Epistemic Statuses

---

## 1. Assurance Methodology

Per Stage S7 Operating Contract (Part 2.4), no security or performance claim is accepted solely because a test or module name asserts it. Every claim must establish:
- **Formal Claim Statement:** Measurable invariant or property.
- **Argument / Rationale:** Mechanism of enforcement.
- **Supporting Evidence:** Exact test or observation artifact.
- **Assumptions & Trust Boundaries:** Environmental prerequisites.
- **Defeaters & Counterexamples:** Known attack paths or theoretical limitations.
- **Status:** Controlled vocabulary (`PROVEN_WITHIN_SCOPE`, `REPRODUCED`, `PARTIALLY_SUPPORTED`, `EXTERNALLY_BLOCKED`).

---

## 2. Structured Claims Matrix

### Claim 1: Zero Raw Image Persistence (DPDPA Sections 6 & 8)
- **Status:** `PROVEN_WITHIN_SCOPE`
- **Claim:** Raw camera images and cropped faces are never stored on persistent disk, database, or analytics collections.
- **Argument:** In `backend/src/routes/face_routes.ts` and `face_preprocessing.ts`, image buffers reside solely in volatile heap memory during landmark detection and 128-D embedding extraction. Once inference completes, buffers are dropped. Firestore stores only AES-256-GCM encrypted 128-D float32 vectors.
- **Evidence:** `evidence/z06_secret_scan.json` (580 files scanned, 0 images found), `backend/src/services/firestore_biometric_repository.ts`.
- **Assumptions:** Node.js V8 garbage collector frees memory without swapping buffers to unencrypted disk swap.
- **Defeater:** Cold-boot RAM capture on compromised physical server hardware.

### Claim 2: Authenticated Cryptographic Protection at Rest (ISO/IEC 24745)
- **Status:** `PROVEN_WITHIN_SCOPE`
- **Claim:** Biometric templates at rest cannot be decrypted or substituted across users or tenants without detection.
- **Argument:** Templates are protected via AES-256-GCM envelope encryption using a per-user derived key (PBKDF2/SHA-256), a unique 96-bit CSPRNG IV per encryption, and Additional Authenticated Data (AAD) binding `${envelopeVersion}|${tenantId}|${uid}|${keyVersion}`.
- **Evidence:** `evidence/s7/crypto_test_results.json` (Exhaustive positive and negative tests: bit flips, AAD swaps, corrupted tags).
- **Assumptions:** Server master encryption key (`MASTER_KEY_SECRET`) remains confidential.
- **Defeater:** Host application memory compromise exposing the active master key in RAM.

### Claim 3: Server-Side Authoritative Decision-Making (Invariant I-03)
- **Status:** `PROVEN_WITHIN_SCOPE`
- **Claim:** The mobile client cannot forge verification scores or inject pre-computed embeddings.
- **Argument:** The API accepts only raw image bursts and fresh single-use challenge nonces (`chal_*`). Client-submitted vector payloads or thresholds are unconditionally rejected with HTTP 400 Bad Request.
- **Evidence:** `backend/src/tests/api_routes_integration.test.ts` (Test 2B: Client vector submission rejection).
- **Assumptions:** TLS 1.3 transport security prevents man-in-the-middle vector tampering.
- **Defeater:** Compromised backend server process executing unauthorized code.

### Claim 4: Invariant-Guarded Duplicate Candidate Review (Invariant I-14)
- **Status:** `PROVEN_WITHIN_SCOPE`
- **Claim:** A 1:N biometric candidate match never causes automatic, irreversible rejection or banning of a worker.
- **Argument:** The deduplication engine (`in_memory_biometric_index.ts`) routes matches above duplicate threshold ($0.74$) to a quarantine queue for human administrative adjudication. The worker is offered immediate 100% Document KYC fallback.
- **Evidence:** `evidence/n01_1ton_error_budget.json`, `ETHICS_PACKAGE/02_INFORMED_CONSENT_KANNADA.md`.
- **Assumptions:** Human administrative review operators adhere to the operational review standard.
- **Defeater:** Human reviewer negligence or biased adjudication without supervisory oversight.

### Claim 5: In-Domain Accuracy for Karnataka Workers (Fitzpatrick IV–VI)
- **Status:** `EXTERNALLY_BLOCKED`
- **Claim:** SFace recognizer achieves $\ge 98\%$ True Accept Rate at $\text{FAR} \le 10^{-3}$ on Karnataka blue-collar workers.
- **Argument:** SFace demonstrates 98.15% TAR@FAR=1e-3 on the public LFW benchmark. However, this cannot certify performance under Karnataka rural conditions (Fitzpatrick IV–VI, dust, perspiration, direct sun) without in-domain field data.
- **Evidence:** `evidence/j04_scorecards.json`, `PREREG-S6.md`.
- **Assumptions:** None (governance rule A-06 prohibits unverified extrapolation).
- **Defeater:** High failure-to-acquire (FTA) or elevated False Non-Match Rate (FNMR) on outdoor worker populations.
- **Unblocking Action:** Human action H-01 (Institutional Ethics Committee review) and H-02 ($N \ge 200$ field cohort collection).

---

## 3. Exit Gate Assessment: S7-G02 (Assurance Case)

**Status:** `DONE-VERIFIED`  
**Evidence Artifact:** `evidence/s7/assurance_claims.json`  
**Review Summary:** 5 core claims formally structured with explicit arguments, evidence links, assumptions, and defeaters. Unverified field accuracy correctly classified as `EXTERNALLY_BLOCKED`.
