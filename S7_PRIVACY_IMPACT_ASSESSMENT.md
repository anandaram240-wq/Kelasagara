# KELASAGARA BIOMATCH · STAGE S7 DATA PROTECTION & PRIVACY IMPACT ASSESSMENT (S7_PRIVACY_IMPACT_ASSESSMENT.md)

**Classification:** Statutory DPIA under Digital Personal Data Protection (DPDP) Act 2023 (India)  
**Stage:** S7  
**Date:** 2026-10-11  

---

## 1. Statutory Scope and Purpose of Processing

The Kelasagara marketplace facilitates employment matching for informal blue-collar gig workers (electricians, plumbers, carpenters, masonry workers) across Karnataka.

Biometric processing serves two strictly defined purposes:
1. **1:1 Identity Verification:** Confirming that the individual reporting for a high-trust job matches the credentialed worker.
2. **1:N Duplicate Prevention:** Detecting fraudulent Sybil accounts and identity theft to protect marketplace integrity.

---

## 2. Data Lifecycle and Proportionality Matrix

| Data Category | Collection Point | Necessity & Purpose | Storage Mode | Retention Period | Deletion Technical Control |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Raw Camera Frames** | Mobile App Camera Burst | Facial landmark detection & feature embedding | **Ephemeral RAM only** (Never written to disk/DB) | Dropped immediately upon inference ($\le 2\text{s}$) | Garbage collected in V8 heap |
| **128-D Face Embedding** | Server ONNX Output | Biometric identity reference | **AES-256-GCM Envelope** in Firestore Vault | Duration of active worker registration | Crypto-shredding (Salt & ciphertext deleted) |
| **Similarity Scores** | Verification Engine | Advisory matching decision | **Omitted from client**; non-sensitive binned logs | 30 days in audit log | Automatic Firestore TTL |
| **Challenge Nonces** | Session Handshake | Replay attack prevention | Key-value store with TTL | 300 seconds | Atomic consume / TTL expiry |

---

## 3. Risk Assessment and Harm Mitigation

1. **Risk of Mass Biometric Data Breach:**
   - *Mitigation:* Zero raw images stored. All templates encrypted at rest via AES-256-GCM with per-user derived keys and Additional Authenticated Data binding.
2. **Risk of False Rejection & Worker Livelihood Disruption:**
   - *Mitigation:* **Invariant I-14:** Biometric non-match or duplicate flag **never** terminates an account. Immediate 100% Document KYC (physical card upload) fallback guaranteed.
3. **Risk of Function Creep:**
   - *Mitigation:* Purpose limitation codified in `ETHICS_PACKAGE/`. No commercial selling, secondary analytics, or third-party transfer permitted.

---

## 4. Exit Gate S7-G11 Assessment

**Status:** `DONE-VERIFIED`  
**Evidence Artifact:** `evidence/s7/regulatory_requirements_matrix.json`  
**Summary:** Full data minimization, purpose limitation, and sovereign crypto-shredding conform to DPDPA 2023 requirements.
