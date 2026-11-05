# KELASAGARA V14.0
## Statutory Mapping, Privacy Claims & Legal Realities Audit

**Audit Date:** October 23, 2026  
**Auditor:** Application Security Architect & Technical Privacy Reviewer  
**Governing Statute:** The Digital Personal Data Protection Act, 2023 (Act No. 22 of 2023)  
**Commencement Status:** Enacted 11 August 2023; Phased Commencement Notified 13 November 2025  

---

## 1. Statutory Reality of the DPDPA 2023

A forensic audit of earlier documentation revealed widespread citations of **Section 8(3)** as a general citation for memory wiping, vault security, and privacy masking. This section corrects the statutory mapping against the official Gazette of India.

### 1.1 Correct Statutory Section Mapping

| DPDPA Provision | Legislative Text / Scope | Correct Technical Application in Kelasagara | Previous Misattribution in Reports |
| :--- | :--- | :--- | :--- |
| **Section 8(3)** | *"A Data Fiduciary shall, where personal data processed by it or on its behalf is used to make a decision that affects the Data Principal... make reasonable efforts to ensure that personal data is accurate and complete."* | Applies to 1:N deduplication accuracy: ensuring false duplicate flags do not erroneously deprive legitimate gig workers of platform livelihood. | Incorrectly cited as the legal requirement to overwrite RAM buffers. |
| **Section 8(5)** | *"A Data Fiduciary shall protect personal data in its possession or under its control... by taking reasonable security safeguards to prevent personal data breach."* | Authoritative legal mandate for: sealing `firestore.rules` (`allow read, write: if false;`), Cloud KMS envelope encryption, and RAM zero-out of raw pixel buffers. | Omitted in earlier reports in favor of §8(3). |
| **Section 8(7)** | *"A Data Fiduciary shall, unless retention is necessary for compliance with any law... erase personal data, upon the Data Principal withdrawing her consent, or as soon as it is reasonable to assume that the specified purpose is no longer being served."* | Authoritative mandate for data retention limits and automated purge of orphaned biometric enrollment sessions. | Conflated with general GDPR-style right to be forgotten. |
| **Section 12(3)** | *"A Data Principal shall have the right to correction, completion, updating and erasure of her personal data for the processing of which she has previously given consent..."* | Authoritative mandate for the `DELETE /api/biometrics/template` endpoint and worker-initiated account deletion workflows. | Accurately cited in Stage S9 tests. |

---

## 2. Commencement Timeline & Legal Enforceability Status

### 2.1 The 13 November 2025 Commencement Notification
Under Section 1(2) of the DPDPA 2023, provisions come into force on dates appointed by the Central Government via notification in the Official Gazette.

- **Notification S.O. 4930(E) (Published 13 November 2025):** Notified that substantive chapters containing **Sections 3 through 17** are scheduled for phased commencement **18 months post-publication**, placing the formal statutory enforcement date on **13 May 2027**.
- **Current Legal Status (as of October 2026):**
  - The DPDPA 2023 is enacted legislation representing established parliamentary policy.
  - Substantive statutory penalties and regulatory enforcement under Sections 3–17 commence on **13 May 2027**.
  - Software controls implemented in V14.0 (consent notices, masking, right-to-erasure endpoints, sealed access rules) represent **proactive architectural alignment** with the impending statutory deadline, NOT formal legal compliance with an actively penalizing regulatory regime.

---

## 3. Separation of Technical Controls from Legal Determinations

### 3.1 Memory Zeroing vs. Legal Erasure
- **Technical Control:** In Flutter and native C++, raw pixel buffers and extracted Float32 embeddings are overwritten with zeroes (`nativeResult.embedding.fillRange(0, length, 0.0)`) immediately after inference.
- **Engineering Reality:** This is good defensive software engineering practice that minimizes the window of vulnerability to memory dumping or cold-boot attacks.
- **Legal Reality:** Overwriting a transient local buffer does not constitute enterprise-wide compliance with data erasure. Full legal erasure requires verifying database replicas, backup retention cycles, logging pipelines, and third-party processor caches.

### 3.2 Display Masking vs. Complete Anonymization
- **Technical Control:** The mobile UI renders duplicate matches as `KLS-xK9***wXy-7890`.
- **Engineering Reality:** Pseudonymization/masking prevents the current applicant from reading another worker's full phone number or unmasked UID.
- **Legal Reality:** Masking in a UI modal does not make the underlying record anonymous data; it remains personal data in the backend database and must be secured under Section 8(5).

### 3.3 ISO and UIDAI Claims
- **ISO Conformance:** Implementing formulas from ISO/IEC 29794-5 (OFIQ), ISO/IEC 30107-3 (PAD), or ISO/IEC 24745 (Template Protection) does **NOT** grant "ISO Certification". Formal certification requires independent evaluation and audit by an accredited testing laboratory (e.g. iBeta, STQC, BSI).
- **UIDAI Independence:** Kelasagara is an independent platform inspired by the public Registered Device architectural model of Aadhaar Face RD. It is **NOT** certified by STQC, affiliated with UIDAI, or connected to the Central Identities Data Repository (CIDR).

---

## 4. Ethical & Legal Prerequisites for Future Biometric Field Trials

Under no circumstances may real-world biometric data be collected or field trials conducted without:
1. **Formal Institutional Review / Legal Approval:** Review by an independent ethics committee or legal counsel.
2. **Voluntary Informed Bilingual Consent:** Consent documents clearly explaining purpose, retention period, and non-commercial usage in Kannada and English.
3. **Guaranteed Non-Biometric Alternative:** Gig workers who choose not to participate or whose facial capture fails must have full access to platform onboarding via SMS OTP and manual supervisor verification without penalty.
4. **Defined Statistical Power & Sample Size Plan:** Sample sizes must be mathematically derived from target error rates (e.g., estimating FMR $\le 0.1\%$ with $\pm 0.05\%$ precision requires specific independent trial counts, not arbitrary round numbers).
