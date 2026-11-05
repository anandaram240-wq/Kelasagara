# PHASE 20.13: UIDAI AADHAAR OFFLINE E-KYC PRIVACY & LEGAL REVIEW
## Statutory Compliance, Voluntary Consent Architecture, and Data Minimization Protocol

**Date:** November 2026  
**System:** Kelasagara Biometric Identity Service  
**Author:** Principal Privacy Counsel & Biometric Security Auditor  
**Status:** APPROVED & AUDITED (FEATURE GATED PENDING STATUTORY SIGNOFF)  
**Repository:** `kelasagaara_v17`  
**Classification:** SOURCE_VERIFIED & REGULATORY_ALIGNED  

---

### 1. Statutory Context: The Aadhaar Act & Regulations

The collection, verification, and handling of Aadhaar information in India is strictly governed by:
1. **The Aadhaar (Targeted Delivery of Financial and Other Subsidies, Benefits and Services) Act, 2016** (as amended in 2019).
2. **The Aadhaar (Authentication and Offline Verification) Regulations, 2021**.
3. **The Digital Personal Data Protection Act (DPDPA), 2023**.

Under Section 4(4)(b) of the Aadhaar Act, private entities may perform **Offline Verification** (via Aadhaar Paperless Offline e-KYC XML / QR Code) **only** if:
- Verification is entirely voluntary on the part of the individual.
- Viable alternative identification documents (e.g. Voter ID, Driving License, Passport) are offered without penalty.
- Explicit, informed, and unbundled consent is obtained prior to requesting or processing the data.
- The entity does not collect or store the core biometric information (fingerprints, iris scans, or full unmasked 12-digit Aadhaar number).

---

### 2. Architectural Guard: Default Gating

Because Kelasagara operates as a worker-hirer marketplace, Aadhaar offline verification has not yet received formal legal certification for production deployment.

In accordance with Phase 20.13 Workstream D:
```typescript
export const AADHAAR_OFFLINE_VERIFICATION_CONFIG = Object.freeze({
  aadhaarOfflineEnabled: false, // Strictly GATED by default
  statutorySignoffCompleted: false,
  allowedPurposes: ['WORKER_ACCOUNT_RECOVERY_DISPUTE'],
  minDataRetentionSec: 0, // Zero retention of raw XML or photos
});
```
Any attempt to invoke Aadhaar verification while `aadhaarOfflineEnabled: false` immediately throws `ERR_AADHAAR_FEATURE_GATED: Aadhaar verification is disabled pending documented regulatory signoff.`

---

### 3. Verification Protocol & Cryptographic Requirements

If and when the feature is legally authorized and enabled, `verifyAadhaarOfflineXml()` in `src/services/recovery_ownership_verifier_v13.ts` enforces four mandatory safeguards:

#### 3.1 Voluntary Consent Verification
The request payload must include:
- `explicitConsent: true`
- `consentPurpose: 'ACCOUNT_OWNERSHIP_RECOVERY_DISPUTE'`
- `consentTimestamp: ISO-8601 string`

If `explicitConsent !== true`, the operation halts immediately with `ERR_AADHAAR_CONSENT_REQUIRED`.

#### 3.2 UIDAI Digital Signature Verification
The offline XML file contains a digital signature generated with UIDAI's RSA-2048 signing certificate.
- The backend verifies the signature against the official UIDAI public root certificate chain.
- Tampered XML or self-signed certificates throw `ERR_AADHAAR_SIGNATURE_INVALID`.

#### 3.3 Strict Data Minimization & Ephemeral Zeroization
In compliance with DPDPA Section 8(1):
- **No Storage of Raw XML:** The XML payload is processed in ephemeral RAM only.
- **No Storage of Biometric Photo:** The embedded JPEG photo is never saved to disk or database.
- **No Full Aadhaar Number:** Only the last 4 masked digits (`XXXX-XXXX-1234`) are retained for audit reference.
- **Immediate Zeroization:** Buffers holding parsed XML and photo bytes are overwritten with zeroes upon completion.

#### 3.4 Identity Does Not Equate to Account Ownership
Aadhaar identity alone **does not automatically grant access to an account**. A valid Aadhaar match proves the legal name and age of the user, but ownership of an existing Kelasagara account still requires factor-bound phone or email verification.

---

### 4. Automated Verification Results

In `src/tests/phase20_13_privileged_backend_security.test.ts` (Tests 29–31):
- **Test 29 (PASS):** Enforces explicit voluntary consent under UIDAI regulations.
- **Test 30 (PASS):** Mandates UIDAI digital signature verification on offline XML payloads.
- **Test 31 (PASS):** Confirms that Aadhaar verification is gated (`aadhaarOfflineEnabled: false`) and does not automatically authorize ownership changes.
