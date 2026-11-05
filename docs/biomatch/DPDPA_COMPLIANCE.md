# KELASAGARA BIOMATCH V7: DPDPA 2023 COMPLIANCE & PRIVACY ENGINEERING SPECIFICATION

**Document Version:** 1.0.0  
**Status:** AUTHORITATIVE ARCHITECTURAL SPECIFICATION  
**Governing Statute:** The Digital Personal Data Protection Act, 2023 (Act No. 22 of 2023, Gazette of India, August 11, 2023)  
**Applicable Jurisdiction:** Republic of India  
**Target Release Readiness Level:** RRL-0 (Research Prototype)  
**Owning Role:** Data Protection Officer (DPO) & Privacy Engineering Architecture Team  

---

## 1. EXECUTIVE SUMMARY & REGULATORY CONTEXT

The **Digital Personal Data Protection Act, 2023 (DPDPA 2023)** provides the statutory framework for processing digital personal data in India. It establishes legal obligations for Data Fiduciaries, statutory rights for Data Principals, and strict penalties for non-compliance.

Under DPDPA 2023:
1. **Data Fiduciary:** Kelasagara Technologies Private Limited / Platform Operating Entity (responsible for determining the purpose and means of personal data processing).
2. **Data Principals:** Gig platform workers (unorganized labourers across carpentry, plumbing, masonry, loading, electrical work) and Hirers (householders, contractors, small business operators).
3. **Significant Data Fiduciary (SDF) Safeguards:** Even operating under Firebase Spark / research prototype tier, Kelasagara voluntarily implements SDF-grade safeguards (Data Protection Officer, Data Protection Impact Assessment, tamper-evident audit logging, and crypto-shredding).
4. **Territorial Processing:** All biometric vector processing and persistent Firestore storage are strictly anchored within the sovereign territory of India (`asia-south1` Mumbai region). Cross-border transfers of biometric embeddings are strictly prohibited.

---

## 2. SECTION-BY-SECTION DPDPA 2023 COMPLIANCE MAPPING

| DPDPA Section | Statutory Requirement | Kelasagara BioMatch V7 Implementation | Verification Mechanism |
|---|---|---|---|
| **Section 4** | **Grounds for Processing:** Lawful purpose with consent or legitimate use. | Biometric processing occurs solely upon explicit, informed consent for duplicate account prevention and voluntary identity verification. | Consent timestamp recorded prior to camera activation. |
| **Section 5** | **Notice Requirements:** Clear, plain language notice in English and 8th Schedule languages. | Bilingual notice in **Kannada (ಕನ್ನಡ)** and **English** displayed before camera permission request. Details exact purpose, data items collected, storage region, and DPO contact. | UI verification in `FaceEnrollmentScreen`; validated in `dpdpa_privacy_compliance.test.ts`. |
| **Section 6(1)** | **Consent Quality:** Free, specific, informed, unconditional, and unambiguous with clear affirmative action. | Explicit opt-in toggle required. No pre-ticked checkboxes. Consent specifically names "128-D mathematical feature vectors" and clarifies photos are never stored. | Verified in mobile UI contract and backend schema. |
| **Section 6(2)** | **Non-Conditioning / Non-Coercion:** Access to services cannot be conditioned on unnecessary data. | **Strict Non-Biometric Alternative Pathway:** Workers and Hirers who decline biometric verification retain full access via document KYC (Voter ID, DL, MNREGA card). | Verified in `dpdpa_privacy_compliance.test.ts` (Test 4). |
| **Section 6(4)** | **Right to Withdraw Consent:** Consent may be withdrawn at any time with equal ease. | One-click biometric template revocation in user account settings (`DELETE /api/biometrics/template`). | Verified in `api_routes_integration.test.ts` (Test 7) & `dpdpa_privacy_compliance.test.ts` (Test 3). |
| **Section 8(3)** | **Accuracy & Completeness:** Reasonable efforts to ensure data accuracy. | 1:N deduplication threshold calibration ($T_{\text{dup}} = 0.74$) prevents false linkings; manual review queue for ambiguous matches. | Verified in Gate G5 evaluation protocol. |
| **Section 8(5)** | **Security Safeguards:** Reasonable security safeguards to prevent data breach. | 128-D vectors isolated in `biometric_vault`; direct client access blocked (`firestore.rules`); per-subject salt and SHA-256 integrity hash; constant-time padding against side-channels. | Verified in Gate G1, Gate G8, Gate G12 tests. |
| **Section 8(7)** | **Storage Limitation & Erasure:** Erase personal data when purpose is served or upon withdrawal. | Automated crypto-shredding upon template deletion: permanent deletion of vault vector, salt, and hash. | Verified in `dpdpa_privacy_compliance.test.ts` (Test 3). |
| **Section 9** | **Processing of Children's Data:** Verifiable parental consent; no harmful tracking/profiling. | **Strict Age-Gating ($\text{age} \ge 18$):** Biometric enrollment strictly prohibited for minors under 18 years. Gig platform onboarding enforces date-of-birth threshold. | Enforced in onboarding validation; verified in `dpdpa_privacy_compliance.test.ts` (Test 5). |
| **Section 11** | **Right to Access Information:** Data principal may request summary of data processed. | User profile surfaces biometric verification status, enrollment timestamp, and masked phone association. | User profile schema and API contract. |
| **Section 12** | **Right to Correction & Erasure:** Right to have personal data erased unless retention required by law. | `DELETE /api/biometrics/template` provides instant crypto-shredding. User status resets to `PENDING_FACE` or non-biometric status. | Verified in `face_routes.ts` and automated test suites. |
| **Section 13** | **Right of Grievance Redressal:** Readily available grievance redressal mechanism. | Designated DPO email (`privacy-dpo@kelasagara.in`); mandatory 7-calendar-day grievance resolution SLA. | Documented in privacy policy and notice contract. |
| **Section 14** | **Right to Nominate:** Right to nominate individual in event of death/incapacity. | Profile nomination metadata fields supported in user document schema. | Supported in user account management. |

---

## 3. CORE PRIVACY ENGINEERING ARCHITECTURES

### 3.1 Zero-Photo Retention Architecture (Data Minimization)
Raw facial photographs represent high-risk personal identifiers. Kelasagara BioMatch V7 enforces strict **Ephemeral Processing**:
```
[Camera Sensor]
      │ (NV21 / YUV420 Frame)
      ▼
[In-Memory RAM Buffer]
      │
      ├──> [ML Kit Face Detection & Blink Liveness] (On-Device Client)
      │
      └──> [128-D Normalized Vector Extraction] (Mathematical Reduction)
      │
      ▼
[Memory Frame Purged] (Garbage Collected Immediately; Zero Disk I/O)
      │
      ▼
[128-D Float Vector Dispatched Over TLS 1.3] (Probe Vector Only)
```

**Key Invariants:**
1. **No Image Upload:** At no point is a JPEG, PNG, NV21, or raw bitmap uploaded to Cloud Firestore, Firebase Storage, Google Cloud Storage, or any external backend.
2. **One-Way Irreversibility:** The 128-dimensional embedding vector is a mathematical projection. Generating a photographic human likeness from a 128-D normalized embedding without the generative training latent space is computationally infeasible.
3. **No Secondary Processing:** Biometric embeddings are strictly utilized for identity deduplication and authentication. Emotion recognition, demographic profiling, and sentiment analysis are strictly prohibited.

---

### 3.2 Non-Biometric Alternative Pathway (Anti-Coercion Guarantee)

Under Section 6(1) and 6(2) of DPDPA 2023, consent cannot be coerced as a condition for receiving utility services unless processing is strictly necessary. For a blue-collar gig platform, biometric face authentication is a convenience and fraud-prevention measure, but cannot be made mandatory.

**The Three-Tier Onboarding Framework:**
```
                     ┌──────────────────────────────────┐
                     │    New Worker / Hirer Onboarding │
                     └─────────────────┬────────────────┘
                                       │
                      Can/wishes to use Face Verification?
                                       │
                    ┌──────────────────┴──────────────────┐
                 YES│                                   NO│ (DPDPA Section 6 Opt-Out)
                    ▼                                     ▼
     ┌───────────────────────────────┐     ┌───────────────────────────────┐
     │    Face Enrollment Screen     │     │ Document KYC & OTP Onboarding │
     │  - Ephemeral Liveness Check   │     │  - Voter ID / Driving License │
     │  - 128-D Vector Extraction    │     │  - MNREGA Job Card / Ration   │
     │  - 1:N Deduplication Scan     │     │  - Mobile OTP Verification    │
     └──────────────┬────────────────┘     └──────────────┬────────────────┘
                    │                                     │
                    ▼                                     ▼
     ┌───────────────────────────────┐     ┌───────────────────────────────┐
     │  Account Status: APPROVED     │     │  Account Status: APPROVED     │
     │  Verification: FACE_VERIFIED  │     │  Verification: DOC_VERIFIED   │
     └───────────────────────────────┘     └───────────────────────────────┘
                    │                                     │
                    └──────────────────┬──────────────────┘
                                       ▼
                     ┌──────────────────────────────────┐
                     │  Full Platform Parity & Booking  │
                     │  (Zero Discrimination in Engine) │
                     └──────────────────────────────────┘
```

**Parity Guarantees:**
- Workers verified via Document KYC have equal ranking eligibility in `WorkerDiscoveryService`.
- Hirers verified via Document KYC have equal booking and tracking privileges.
- In `admin_dashboard.dart`, administrators can manually review and approve KYC documents via `credential_review_screen.dart` without requiring biometric data.

---

### 3.3 Crypto-Shredding & Erasure Protocol (Section 12(3))

When a Data Principal exercises their Right to Erasure:
1. **Client Dispatch:** Authenticated user sends `DELETE /api/biometrics/template` with valid Bearer token.
2. **Authorization Boundary:** Route handler enforces `targetUid === callerUid` (unless caller holds verified `isAdmin` claim).
3. **Atomic Purge (Batch Transaction):**
   ```typescript
   const batch = db.batch();
   // 1. Permanently delete the 128-D vector, salt, and integrity hash
   batch.delete(db.collection("biometric_vault").doc(uid));
   // 2. Revoke user verification status
   batch.set(db.collection("users").doc(uid), {
     faceVerified: false,
     biometricEnrollmentState: "PENDING_FACE",
     biometricErasureRequestedAt: admin.firestore.FieldValue.serverTimestamp(),
     updatedAt: admin.firestore.FieldValue.serverTimestamp(),
   }, { merge: true });
   await batch.commit();
   ```
4. **Audit Logging with Privacy Preservation:** An audit event `TEMPLATE_DELETED` is logged into `biometric_audit_logs`. The log entry contains:
   - Event sequence number and cryptographic hash linking.
   - Pseudonymous `uid`.
   - Action timestamp.
   - Zero biometric vector data.
   - Zero plaintext phone numbers (phone numbers masked via `maskPhoneNumber`).

---

### 3.4 Phone Number Masking Specification (Section 8(5))

To protect the privacy of existing account holders when a duplicate registration attempt occurs:
- When a candidate's probe vector matches an existing vault record with cosine similarity $\ge T_{\text{dup}}$, the platform informs the candidate that an account already exists.
- The associated phone number is displayed **strictly masked** (e.g., `+91 ******1234`).
- Masking algorithm (`maskPhoneNumber`):
  1. Trims whitespace and strips formatting.
  2. Preserves the international calling code (`+91`).
  3. Obscures all intermediate digits with exactly 6 asterisks (`******`).
  4. Preserves only the terminal 4 digits for verification recognition.
  5. Truncated inputs ($< 4$ characters) return the generic string `"an existing profile"` to prevent leaking prefix data.

---

## 4. DATA PROTECTION IMPACT ASSESSMENT (DPIA)

In accordance with best practices for processing sensitive biometric identifiers, the following DPIA evaluates all identified privacy risks, their inherent severity, implemented technical safeguards, and residual risk.

| Risk ID | Privacy Threat / Vulnerability | Inherent Likelihood (1-5) | Inherent Impact (1-5) | Inherent Risk (L x I) | Technical & Organizational Mitigations | Residual Likelihood (1-5) | Residual Impact (1-5) | Residual Risk (L x I) | Risk Decision |
|---|---|:---:|:---:|:---:|---|:---:|:---:|:---:|---|
| **DPIA-01** | **Unauthorized Vault Ingress:** Direct client access to biometric templates via compromised app token. | 4 | 5 | 20 | Complete denial rule in `firestore.rules` (`allow read, write: if false`). Access restricted strictly to Admin SDK backend. | 1 | 5 | 5 | **ACCEPTED (Tolerable)** |
| **DPIA-02** | **Reverse Facial Reconstruction:** Inversion of 128-D feature vectors to synthesize human likeness. | 2 | 4 | 8 | Vector dimensionality reduction; no raw photos saved; per-subject cryptographic salting; irreversibility. | 1 | 2 | 2 | **ACCEPTED (Negligible)** |
| **DPIA-03** | **Coerced Consent / Service Denial:** Worker excluded from gig opportunities for declining face scan. | 3 | 4 | 12 | Non-biometric document onboarding path; full platform parity; admin manual review option. | 1 | 2 | 2 | **ACCEPTED (Negligible)** |
| **DPIA-04** | **Replay / Injected Facial Probe Attack:** Malicious actor replays intercepted biometric vector. | 4 | 4 | 16 | 60-second short-TTL cryptographic challenge nonces bound to UID and action; single-use invalidation. | 1 | 2 | 2 | **ACCEPTED (Negligible)** |
| **DPIA-05** | **Cross-Border Data Spill:** Biometric embeddings inadvertently replicated outside India. | 3 | 5 | 15 | Firestore database fixed strictly to `asia-south1` (Mumbai); no external cloud vector databases permitted (ADR-001). | 1 | 5 | 5 | **ACCEPTED (Tolerable)** |
| **DPIA-06** | **Indefinite Data Retention:** Stale biometric templates retained post-account deletion. | 3 | 4 | 12 | `DELETE /api/biometrics/template` crypto-shredding; automated user-initiated erasure; batch purge. | 1 | 2 | 2 | **ACCEPTED (Negligible)** |
| **DPIA-07** | **PII Leakage in Audit Trails:** Plaintext phone numbers or vectors exposed in operational logs. | 3 | 3 | 9 | Invariant I-24: `maskPhoneNumber` sanitizes all phone numbers before audit persistence; zero vector logging. | 1 | 2 | 2 | **ACCEPTED (Negligible)** |
| **DPIA-08** | **Minor Biometric Processing:** Onboarding and facial capture of children under 18 years. | 3 | 5 | 15 | Mandatory date-of-birth validation ($\ge 18$); fail-closed age gating at onboarding. | 1 | 4 | 4 | **ACCEPTED (Tolerable)** |
| **DPIA-09** | **Timing Oracle Side-Channel:** Attacker probes vector API to infer registered phone identities. | 3 | 3 | 9 | Constant-time latency padding ($\ge 150\text{ms}$) on all outcomes including 404; uniform response envelope. | 1 | 2 | 2 | **ACCEPTED (Negligible)** |
| **DPIA-10** | **Audit Log Tampering:** Malicious insider alters or deletes biometric access history. | 2 | 4 | 8 | Invariant I-17: SHA-256 hash-chained immutable audit ledger; genesis anchor; fail-closed verification. | 1 | 2 | 2 | **ACCEPTED (Negligible)** |

---

## 5. BILINGUAL NOTICE & CONSENT SPECIFICATION

### 5.1 English Notice Specification
> **Privacy & Biometric Notice (DPDPA 2023):**  
> Kelasagara uses facial verification solely to prevent duplicate accounts and verify your profile.  
> - **What we collect:** A 128-dimensional mathematical feature vector extracted on your device. We **never** store or upload your face photograph.  
> - **Where it is stored:** Cloud Firestore in Mumbai, India (`asia-south1`).  
> - **Voluntary Option:** Facial verification is completely voluntary. If you prefer not to use face verification, select **Document Verification** to register using your government-issued ID card.  
> - **Your Rights:** You have the right to withdraw consent and delete your biometric template at any time in Account Settings.  
> - **Contact DPO:** privacy-dpo@kelasagara.in  

### 5.2 Kannada Notice Specification (೮ನೇ ಅನುಸೂಚಿ ಅನುಸರಣೆ)
> **ಗೌಪ್ಯತೆ ಮತ್ತು ಬಯೋಮೆಟ್ರಿಕ್ ಸೂಚನೆ (DPDPA 2023):**  
> ಕೇಲಸಾಗಾರವು ನಕಲಿ ಖಾತೆಗಳನ್ನು ತಡೆಗಟ್ಟಲು ಮತ್ತು ನಿಮ್ಮ ಪ್ರೊಫೈಲ್ ಪರಿಶೀಲಿಸಲು ಮಾತ್ರ ಮುಖ ಪರಿಶೀಲನೆಯನ್ನು ಬಳಸುತ್ತದೆ.  
> - **ನಾವು ಸಂಗ್ರಹಿಸುವುದು:** ನಿಮ್ಮ ಸಾಧನದಲ್ಲಿ ಲೆಕ್ಕಾಚಾರ ಮಾಡಿದ 128-ಆಯಾಮದ ಗಣಿತ ವೆಕ್ಟರ್ ಮಾತ್ರ. ನಾವು ನಿಮ್ಮ ಮುಖದ ಫೋಟೋವನ್ನು **ಎಂದಿಗೂ ಉಳಿಸುವುದಿಲ್ಲ ಅಥವಾ ಅಪ್‌ಲೋಡ್ ಮಾಡುವುದಿಲ್ಲ**.  
> - **ಡೇಟಾ ಸಂಗ್ರಹ ಸ್ಥಳ:** ಮುಂಬೈ, ಭಾರತದಲ್ಲಿರುವ ಕ್ಲೌಡ್ ಫೈರ್‌ಸ್ಟೋರ್ (`asia-south1`).  
> - **ಸ್ವಯಂಪ್ರೇರಿತ ಆಯ್ಕೆ:** ಮುಖ ಪರಿಶೀಲನೆಯು ಸಂಪೂರ್ಣವಾಗಿ ಐಚ್ಛಿಕವಾಗಿದೆ. ನೀವು ಬಯಸದಿದ್ದರೆ, ಸರ್ಕಾರಿ ಗುರುತಿನ ಚೀಟಿ ಬಳಸಿ ನೋಂದಾಯಿಸಲು **ದಾಖಲೆ ಪರಿಶೀಲನೆ (Document Verification)** ಆಯ್ಕೆಮಾಡಿ.  
> - **ನಿಮ್ಮ ಹಕ್ಕುಗಳು:** ನೀವು ಯಾವುದೇ ಸಮಯದಲ್ಲಿ ನಿಮ್ಮ ಬಯೋಮೆಟ್ರಿಕ್ ಡೇಟಾವನ್ನು ಅಳಿಸಲು (ಡಿಲೀಟ್ ಮಾಡಲು) ಪೂರ್ಣ ಹಕ್ಕನ್ನು ಹೊಂದಿರುತ್ತೀರಿ.  
> - **ದೂರು ಸಂಪರ್ಕ:** privacy-dpo@kelasagara.in  

---

## 6. DATA PROTECTION OFFICER & GRIEVANCE ESCALATION SLA

In accordance with Section 13 of DPDPA 2023:
- **Designated DPO:** Head of Information Security & Privacy Architecture  
- **Email Contact:** `privacy-dpo@kelasagara.in`  
- **Physical Address:** Kelasagara Privacy Operations Center, Bengaluru / Hassan, Karnataka, India  
- **Escalation Turnaround Times:**
  - **Acknowledgment:** Within 24 hours of grievance receipt.
  - **Erasure / Crypto-Shredding Confirmation:** Within 48 hours of verified request.
  - **Substantive Investigation & Redressal:** Maximum 7 calendar days.
  - **Regulatory Escalation:** If unsatisfied, Data Principals may escalate to the Data Protection Board of India (DPBI).

---

## 7. GATE G14 AUDIT ASSERTIONS & VERIFICATION SIGN-OFF

To pass Gate G14, the implementation must satisfy all of the following empirical criteria:
1. `backend/src/tests/dpdpa_privacy_compliance.test.ts` passes 6/6 test suites live.
2. Phone number masking verified across all formatting variations.
3. Raw biometric embeddings verified absent from audit trails.
4. Crypto-shredding verified to permanently eliminate templates and update user verification status.
5. Non-biometric document onboarding path verified to function without platform denial.
6. Age-gating verified to reject minors under 18 years.
7. Sovereign regional confinement verified (`asia-south1` Mumbai).
