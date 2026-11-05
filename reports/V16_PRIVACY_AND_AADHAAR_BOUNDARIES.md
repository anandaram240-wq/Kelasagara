# KELASAGARA V16: PRIVACY ARCHITECTURE & REGULATORY BOUNDARIES

**Document ID:** `reports/V16_PRIVACY_AND_AADHAAR_BOUNDARIES.md`  
**Execution Phase:** Legal Compliance & Statutory Alignment  
**Author:** Principal Application Security Engineer & Biometrics Architect  
**Classification:** `CONTROLLED_TEST_BUILD_ONLY`

---

## 1. STATUTORY CONTEXT (DPDPA 2023)

Under the **Digital Personal Data Protection Act, 2023 (DPDPA 2023)** of India:
- Biometric data (facial images and derived mathematical feature vectors) is classified as personal data requiring explicit, informed, affirmative consent (§6).
- Data Fiduciaries must implement appropriate technical and organizational measures to ensure data security and integrity (§8(4)).
- Data Principals possess statutory rights of grievance redressal, right of access, right of correction, and right of erasure (§12).
- Data Fiduciaries must not make the provision of goods/services contingent on consent to process data unnecessary for that purpose (§6(1)).

---

## 2. ABSOLUTE SEPARATION FROM UIDAI / AADHAAR

### Critical Regulatory Statement
**Kelasagara is NOT an Aadhaar Requesting Entity (AUA), Sub-AUA, or KYC User Agency (KUA).**

The biometric engine implemented within this repository:
1. **Never Calls UIDAI Endpoints:** No requests are sent to CIDR, UIDAI Face Authentication APIs, or any government biometric database.
2. **Never Captures or Stores Aadhaar Numbers:** The 12-digit Aadhaar number is strictly forbidden from collection, input, transmission, or persistence.
3. **No UIDAI Registered Device (RD) Service:** The Flutter client does not implement or integrate with any UIDAI RD Service or FaceRD application.
4. **Proprietary Commercial Biometrics:** Recognition and duplicate prevention are executed exclusively within Kelasagara's private infrastructure using OpenCV SFace ONNX on volunteer worker profiles.

Any claims in legacy documentation or tickets comparing Kelasagara's challenge nonces to "WADH" or "UIDAI FaceRD v2.0" are **purely illustrative cryptographic analogies**, not statutory certifications.

---

## 3. DPDPA COMPLIANCE & PRIVACY ARCHITECTURE

### 3.1 Right to Erasure & Cryptographic Shredding (§12)
When a worker exercises their statutory Right to Erasure under DPDPA §12:
1. Client issues authenticated request to `POST /api/biometrics/erase-my-data`.
2. The server invalidates the user's template in the encrypted vault (`biometric_vault/{uid}`).
3. The DEK and ciphertext are zeroized, making previous backups permanently unrecoverable (cryptographic shredding).
4. The volatile matcher index purges the vector from RAM immediately.
5. The immutable audit ledger records the erasure event with anonymized metadata.

### 3.2 Non-Exclusivity & Alternate KYC (§6(1))
In accordance with DPDPA §6(1):
- Biometric face verification is **never mandatory** for platform participation.
- If a worker declines biometric enrollment, or if their enrollment fails due to lighting, device quality, or false duplicate suspicion:
  - The worker's account is flagged with `alternateVerificationEligible: true`.
  - The worker is seamlessly routed to alternative non-biometric verification (e.g. government photo ID document inspection, mobile OTP verification, or community hub vetting).

### 3.3 Data Residency & KMS Sovereignty
- All Cloud KMS Keyrings and Cloud Run computing resources are restricted to Google Cloud region `asia-south1` (Mumbai, India).
- Biometric templates never transit or reside in foreign cloud jurisdictions.
