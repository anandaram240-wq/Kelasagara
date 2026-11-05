# KELASAGARA DUPLICATE RESPONSE PRIVACY AUDIT
## COMPLETE REMOVAL OF PII DISCLOSURE AND OPAQUE CASE REFERENCE LIFECYCLE

**Phase:** Biometric Enrollment Hotfix  
**Branch:** `security/hotfix-canonical-face-preprocessing`  
**Classification:** Privacy Architecture & DPDPA 2023 Compliance  
**Date:** November 1, 2026  
**Auditors:** Privacy and Security Architect, Independent Security Auditor

---

## 1. COMPLIANCE VIOLATION IDENTIFIED

In previous revisions, when an applicant’s biometric sample matched an existing enrolled user during deduplication:
1. The backend queried Firestore: `this.db.collection('users').doc(topHit.owningUid).get()`.
2. The response payload extracted and returned:
   - `maskedPhone` (e.g. `+91 ••••••2233`)
   - `maskedName` (e.g. `Su••• Go•••`)
   - `maskedUid` (e.g. `KS-••••-4910`)
   - `primarySkill` (e.g. `Plumber`)
   - `dailyRateDisplay` (e.g. `₹900/day`)
   - `facialSimilarityPercent` (e.g. `88% Biometric Match`)
   - `rawCosineSimilarity` (e.g. `0.8845`)
3. The mobile application displayed this data in a pop-up dialog (`DuplicateAccountDetectedDialog`).

### Legal & Security Impact:
- **Digital Personal Data Protection Act (DPDPA 2023) Violation:** Disclosing another citizen's contact details, professional rates, and identity tokens to an unauthenticated applicant without lawful basis.
- **Account Enumeration / Social Engineering Oracle:** An attacker could submit arbitrary facial photos to probe whether a target person has an account, discover their partial phone number, skill, and rate.
- **Cognitive Confusion for Genuine Families:** When two brothers or family members tested the app, the brother was presented with the other brother's personal details, creating extreme confusion and trust erosion.

---

## 2. RECTIFIED PRIVACY ARCHITECTURE

Under the hotfix architecture:
1. **Zero Profile Queries:** When a duplicate match occurs, the backend NEVER queries the `users` collection to retrieve the matched party's personal information.
2. **Zero PII Returned in Public Payloads:** No phone number (masked or unmasked), name, user ID, skill, daily rate, or raw similarity score is returned in the API response.
3. **Opaque Case Reference:** The system generates an un-guessable, high-entropy reference token:
   $$\text{caseReference} = \text{"CASE-" + randomUUID().slice(0, 8).toUpperCase()}$$
   Example: `CASE-D3A8F1C2`.
4. **Internal-Only Case Audit:** The mapping between `caseReference`, `applicantUid`, `matchedOwningUid`, and exact similarity score is written exclusively to the internal Firestore collection `biometric_duplicate_cases`, which is protected by admin-only security rules.

### Public API Response Contract (HTTP 409):
```json
{
  "httpStatus": 409,
  "operationId": "op_9f8a2c1b",
  "code": "FACE_ALREADY_LINKED",
  "biometricStatus": "UNENROLLED",
  "accountStatus": "pending_profile",
  "enrollmentId": null,
  "caseReference": "CASE-D3A8F1C2",
  "idempotentReplay": false,
  "retryable": false,
  "requiresStepUp": true,
  "resolutionPath": "CONTACT_SUPPORT_OR_USE_PREVIOUS_ACCOUNT",
  "message": "This biometric profile appears to match an existing registered account. Please sign in to your original account or contact support with your case reference."
}
```

---

## 3. VERIFICATION EVIDENCE

- **Regression Test 33:** Validates that `maskedPhone`, `maskedName`, `maskedUid`, `primarySkill`, `dailyRateDisplay`, and `duplicateAccountDetails` are strictly undefined (PASS).
- **Regression Test 34:** Validates that `similarityScore`, `rawCosineSimilarity`, and `similarityPercent` are strictly undefined (PASS).
- **Regression Test 35:** Validates that `caseReference` conforms to pattern `^CASE-[A-Z0-9]{8}$` (PASS).
- **Flutter Widget Audit:** `DuplicateAccountResolutionSheet` displays the opaque case reference and dual-language guidance without displaying any third-party personal details (PASS).
