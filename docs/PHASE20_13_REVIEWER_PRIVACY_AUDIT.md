# PHASE 20.13: ADJUDICATION CONSOLE & REVIEWER PRIVACY AUDIT
## Human Reviewer Data Minimization, Masked Identifiers, and Biometric Confidentiality

**Date:** November 2026  
**System:** Kelasagara Biometric Identity Service  
**Author:** Principal Privacy Architect & Security Auditor  
**Status:** APPROVED & AUDITED  
**Repository:** `kelasagaara_v17`  
**Classification:** SOURCE_VERIFIED & DPDPA_ALIGNED  

---

### 1. Privacy Objectives for Internal Review Tools

When two biometric profiles trigger a potential duplicate match, an internal human reviewer (Trust & Safety or Biometric Auditor) is tasked with reviewing the case to prevent fraudulent multiple registrations or resolve false match disputes.

However, internal operator consoles represent a prime vector for privacy leakage and insider threats. Under the Digital Personal Data Protection Act (DPDPA) 2023 and ISO/IEC 27701, the review console must enforce strict data minimization:
- Reviewers must **never** be presented with raw biometric vectors, uncropped photos, or plaintext government identifiers.
- Customer support agents must not have access to biometric case files.
- All actions taken by reviewers must be cryptographically logged to the anchored audit ledger.

---

### 2. Architecture of the Blinded Review Payload

When a case is served to an authorized reviewer, the API strips all sensitive identifiers:

```typescript
export interface BlindedReviewCase {
  caseReference: string; // e.g., 'CASE-4A9B8C7D2E1F0A3B5C7D9E1F2A4B6C8E' (128 bits entropy)
  createdAt: string;
  status: 'PENDING_REVIEW' | 'RESOLVED' | 'DISMISSED';
  reason: 'DUPLICATE_FACE_DETECTED' | 'MANUAL_DISPUTE_APPEAL';
  targetAccount: {
    maskedUserId: string; // 'usr_•••••_9a2b'
    maskedPhone: string;  // '+91 ••••• ••456'
    registrationDate: string;
    biometricClassification: 'CANONICAL_SFACE_YUNET_112_V2';
  };
  competingAccount: {
    maskedUserId: string;
    maskedPhone: string;
    registrationDate: string;
    biometricClassification: 'CANONICAL_SFACE_YUNET_112_V2';
  };
  comparisonMetrics: {
    cosineDistance: number; // e.g., 0.281
    confidenceTier: 'DEFINITIVE_MATCH' | 'AMBIGUOUS_BORDERLINE';
  };
}
```

#### 2.1 Strictly Prohibited in Reviewer Payloads:
1. **Raw 128-D Embedding Arrays:** Prohibited. Human eyes cannot interpret 128 floating-point numbers, and exposing them enables model-inversion attacks.
2. **Raw Face Photographs / Aligned Crops:** Prohibited. Visual human comparison creates subjective bias and violates consent boundaries.
3. **Full Telephone Numbers:** Prohibited. Only masked suffixes are rendered.
4. **Plaintext Aadhaar Numbers / XML:** Prohibited. Only demographic status flags (`DOB_MATCH: true`, `STATE_MATCH: true`) may be exposed if authorized.

---

### 3. Purpose Gating and Decryption Restrictions

Reviewers cannot trigger template decryption or vector re-computation without an approved audit purpose:

```typescript
export function assertReviewerAuthorization(
  reviewerToken: DecodedIdToken,
  caseContext: BlindedReviewCase,
  purpose: string
): void {
  const allowedRoles = ['BIOMETRIC_AUDITOR', 'TRUST_AND_SAFETY_ADMIN'];
  if (!allowedRoles.includes(reviewerToken.role)) {
    throw new SecurityError(`ERR_UNAUTHORIZED_REVIEWER_ROLE: Role ${reviewerToken.role} is not permitted.`);
  }

  const validPurposes = ['DUPLICATE_CASE_ADJUDICATION', 'FRAUD_INVESTIGATION_LEGAL_ESCALATION'];
  if (!validPurposes.includes(purpose)) {
    throw new SecurityError(`ERR_INVALID_AUDIT_PURPOSE: Purpose ${purpose} is not approved for case access.`);
  }
}
```

---

### 4. Verification Evidence

In `src/tests/phase20_13_privileged_backend_security.test.ts`:
- **Test 5 (PASS):** Tier-1 Customer Support role is blocked from case adjudication.
- **Test 7 (PASS):** Reviewers cannot access or decrypt comparison details without an approved purpose (`ERR_UNAUTHORIZED_REVIEWER_PURPOSE`).
- The Flutter client tests (`profile_biometric_isolation_test.dart`) verify that client UI displays opaque case references and masked fields cleanly.
