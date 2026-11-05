# PHASE 20.7 CONSENT PROTOCOL
## Standard Operating Procedure for Voluntary Informed Consent and Legal Evidence Management

**Project:** Kelasagara Major Project  
**System:** Multi-Factor Biometric Identity and Authentication Platform  
**Phase:** 20.7 (Controlled Physical Biometric Validation & PAD Hardening)  
**Standard:** India DPDPA 2023 (§6 Consent Architecture) & GDPR Article 9(2)(a)  
**Date:** 2026-11-01  

---

## 1. CONSENT ACQUISITION PROTOCOL (SOP)

The following sequence of steps must be strictly executed by the designated Principal Investigator or research administrator prior to acquiring any physical biometric sample:

```
Step 1: Hand Participant Information Sheet (PIS) to volunteer.
Step 2: Allow volunteer sufficient time (minimum 10 minutes) to review.
Step 3: Verbally confirm volunteer is an adult (aged 18 or above).
Step 4: Explicitly explain that participation does NOT affect Kelasagara marketplace services.
Step 5: Review the 6 explicit consent checkboxes with the volunteer.
Step 6: Volunteer physically signs two identical copies of the Consent Form.
Step 7: Researcher signs as witness; one original copy is given to the volunteer.
Step 8: Compute SHA-256 digest of signed physical form; record in Tier 1 Consent Ledger.
Step 9: Assign randomly generated opaque research identifier (e.g. SUBJ-C-014).
Step 10: Store signed physical form in locked, fireproof department cabinet.
```

---

## 2. CANONICAL INFORMED CONSENT DOCUMENT TEMPLATE

```
========================================================================================
           VOLUNTARY INFORMED CONSENT FOR BIOMETRIC RESEARCH PARTICIPATION
========================================================================================

Study Title: Controlled Empirical Validation and Presentation Attack Detection
             Evaluation of the Kelasagara Biometric Platform
Institution: University Department of Computer Science & Engineering
Principal Investigator: [Designated University Faculty Member]

PARTICIPANT STATEMENT & CHECKBOXES (All boxes must be checked by participant):

[ ] 1. I confirm that I have read and understood the Participant Information Sheet (PIS)
       dated 2026-11-01 for the above study. I have had the opportunity to ask questions
       and my questions have been answered satisfactorily.

[ ] 2. I understand that my participation is completely voluntary and that I am free to
       withdraw at any time, without giving any reason, and without my legal rights or
       Kelasagara platform account standing being affected in any way.

[ ] 3. I explicitly consent to the collection of digital facial photographs and the
       generation of mathematical numerical embeddings (biometric vectors) strictly
       for academic research purposes.

[ ] 4. I understand that my data will be assigned an anonymous opaque research identifier
       and that my personal contact details and legal name will never appear in any
       academic publication, presentation, or source code repository.

[ ] 5. I understand that all research biometric imagery will be stored in an offline,
       encrypted volume and will be permanently deleted 90 days after study completion.

[ ] 6. I confirm that I am aged 18 years or older.

----------------------------------------------------------------------------------------
Participant Legal Name: ________________________________________________________________

Participant Signature:  ________________________________  Date: ________________________

Researcher Name:        ________________________________________________________________

Researcher Signature:   ________________________________  Date: ________________________
========================================================================================
```

---

## 3. SEPARATION OF CONSENT FROM RESEARCH BIOMETRICS

To ensure complete privacy and zero data leakage:
- **Tier 1 (Consent & Mapping Ledger):** Physical paper forms and encrypted SQLite ledger containing legal names, phone numbers, and assigned opaque IDs (`SUBJ-X-YY`). Stored exclusively on an offline, air-gapped machine locked in a restricted university laboratory.
- **Tier 2 (Research Feature Vault):** Manifest files and floating-point embedding vectors. Contains **only** opaque IDs (`SUBJ-X-YY`), session indices, and calculated cosine similarities. Zero personal identifiable information (PII) is permitted.
- **Cryptographic Link:** The research manifest contains only the SHA-256 digest of the signed consent form (`consentDocumentId = SHA256(form)`), ensuring one-way verification without exposing personal identity.
