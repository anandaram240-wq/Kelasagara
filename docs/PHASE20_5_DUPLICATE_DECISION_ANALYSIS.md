# PHASE 20.5 DUPLICATE DECISION ANALYSIS
## Policy Analysis: Ambiguity Handling, Privacy Protections, and Recovery Pathways

**Project:** Kelasagara Major Project  
**System:** Worker Marketplace & Multi-Factor Biometric Identity Platform  
**Phase:** 20.5 (Advanced Biometric Scientific Validation Engine)  
**Parent Phase 20.4 Commit:** `41f95bf66bd09cda8ea63d3483e567b06ba6504e`  

---

## 1. ETHICAL INVARIANT: DUPLICATE != FRAUD

A fundamental tenet of the Kelasagara Biometric Architecture is that **a biometric duplicate hit must never be equated with malicious intent or criminal fraud**:
- **Legitimate Causes of Duplicate Hits**:
  1. A worker forgets their previous account credentials and attempts to sign up again.
  2. A worker changed their SIM card or lost their phone.
  3. Close biological siblings or lookalikes presenting similarity in the ambiguous range.
- **System Policy**: Duplicate detection triggers a supportive account-linking and recovery pathway, NOT an punitive ban.

---

## 2. PRIVACY-PRESERVING ZERO-PII DISCLOSURE

When a candidate matches an existing account during registration, the application strictly suppresses sensitive personally identifiable information (PII):

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                     PRIVACY-PRESERVING DUPLICATE DISCLOSURE                     │
├───────────────────────────────┬─────────────────────────────────────────────────┤
│ Sensitive Attribute           │ Privacy-Protected Presentation                  │
├───────────────────────────────┼─────────────────────────────────────────────────┤
│ Target Account Firebase UID   │ Masked: `xK9***wXy` (First 3 + *** + Last 4)    │
│ Target Account Phone Number   │ Masked: `+91 ******2345` (Last 4 digits only)   │
│ Target Account Full Name      │ Masked: `Ana*** Kum**` (First half masked)      │
│ Target Account Email          │ Fully Withheld                                  │
│ Biometric Vector Embedding    │ Fully Withheld (Never sent to mobile client)    │
└───────────────────────────────┴─────────────────────────────────────────────────┘
```

---

## 3. AMBIGUITY AND ESCALATION FLOW (`CASE-XXXX`)

```
      Similarity Score (s)
            ▲
            │
    1.00 ───┼── DUPLICATE_HARD_BLOCK: High confidence duplicate
            │   Action: Prompt existing account login / recovery
    0.78 ───┼── DUPLICATE_BLOCK: Operational deduplication boundary
            │   Action: Initiate step-up SMS OTP to registered phone
    0.74 ───┼── DUPLICATE_WARNING: Advisory threshold
            │   Action: Flag incident CASE-XXXX for manual review
    0.65 ───┼── AMBIGUITY_HOLD: Low confidence match zone
            │   Action: Request recapture under better illumination
    0.00 ───┴── UNIQUE: Approved as new marketplace worker
```

- **Ambiguous Recapture**: Candidates in $[0.65, 0.74)$ are asked to adjust lighting and retry.
- **Step-Up Verification**: If the claimant proves ownership of the original phone via SMS OTP, accounts are linked atomically without manual compliance review.
- **Compliance Queue**: Unresolvable disputes generate a non-PII incident ticket (`CASE-XXXX`) in the `biometric_audit_log` for human compliance officer review.
