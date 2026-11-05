# KELASAGARA V20.12: MANUAL REVIEW WORKFLOW & PRIVACY SHIELD SPECIFICATION

**Project:** Kelasagara Biometric Security Architecture  
**Phase:** V20.12  
**Parent Phase:** V20.11 (`412def0`)  
**Working Branch:** `security/phase20.12-biometric-trust-provenance`  
**Classification:** Operational Trust & Privacy Architecture Specification  

---

## 1. AMBIGUOUS ZONE RESOLUTION WORKFLOW

In biometric matching, similarity scores fall into three statistically calibrated zones:
1. **Clean Zone ($\text{similarity} < 0.363$):** Instant approval; no duplicate conflict.
2. **Ambiguous Review Zone ($0.363 \le \text{similarity} < 0.720$):** Indeterminate match (e.g., identical twins, biological siblings, extreme lighting variance). Enqueues a case in `biometric_duplicate_cases` and returns HTTP 202 `REVIEW_REQUIRED`.
3. **Hard Duplicate Block ($\text{similarity} \ge 0.720$):** High confidence duplicate match. Enqueues a dispute case and returns HTTP 409 `FACE_ALREADY_LINKED`.

---

## 2. PRIVACY-SHIELDED REVIEW INTERFACE

Human reviewers inspecting cases in the administrative console are strictly shielded from sensitive PII:

### What Reviewers CAN See:
- Opaque Case ID (`CASE-XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX`)
- Masked Applicant Handle (`KS-••••-4910`)
- Masked Candidate Handle (`KS-••••-8821`)
- Masked First Names (`Ra•••• Ku••••` vs `Su•••• Ve••••`)
- Trade / Skill (`Electrician` vs `Plumber`)
- Cosine Similarity Score (e.g. `0.5842`) and Preprocessing Manifest Version
- Ownership verification status (`SMS_OTP: VERIFIED`)

### What Reviewers CANNOT See (Strict Privacy Shield):
- Raw RGB facial photographs (never stored or presented)
- Raw 128-D embedding vectors
- Full Aadhaar numbers or government document scans
- Full telephone numbers or email addresses

---

## 3. CRYPTOGRAPHIC TAMPER-EVIDENT AUDIT LEDGER

Every adjudication action (`APPROVE_AS_DISTINCT_PERSON`, `CONFIRM_DUPLICATE_ROUTE_TO_RECOVERY`, `REQUEST_FRESH_RECAPTURE`) appends a record to the tamper-evident hash chain:

```
Genesis: "GENESIS_HASH_KS_V10"
   |
   v
Entry 1: SHA-256(Case1 | UID1 | Reviewer1 | APPROVE | Justification | Genesis | Timestamp1)
   |
   v
Entry 2: SHA-256(Case2 | UID2 | Reviewer2 | DUPLICATE | Justification | Entry1_Hash | Timestamp2)
```

If an unauthorized administrator modifies a past decision in the database, `verifyAuditChainIntegrity()` immediately detects the hash mismatch and alerts compliance officers.
