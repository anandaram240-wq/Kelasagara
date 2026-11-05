# PHASE 20.7: SFace 128-D 1:N BIOMETRIC DEDUPLICATION AUDIT
**System:** Kelasagara Biometric Identity & Authentication Platform  
**Phase:** 20.7 (Controlled Physical Biometric Validation & PAD Hardening)  
**Evaluator:** Principal Biometric Systems Architect & Independent Security Evaluator  
**Date:** November 2026  
**Status:** VALIDATED (Controlled Benchmark Suite) / PHYSICAL TRIAL GATED

---

## 1. Executive Summary & Deduplication Architecture

The Kelasagara 1:N Biometric De-duplication Engine prevents fraudulent multi-accounting, subsidy poaching, and identity duplication across the worker marketplace.

When a new worker initiates enrollment, the backend searches the entire active gallery of encrypted templates. Because production data security requires zero plaintext templates in storage, candidate templates are decrypted in-memory or queried via pre-computed L2 Euclidean distance indexing before computing cosine similarities.

### Four-Tier Decision Policy:

```
                          COSINE SIMILARITY SPECTRUM
0.00                    0.740             0.780             0.900           1.00
 |------------------------|-----------------|-----------------|---------------|
      BAND 4 (PASS)            BAND 3            BAND 2            BAND 1
   Distinct New Identity     Ambiguous       Manual Review       Auto-Merge
     (New Enrollment)         Warning         Investigate         Duplicate
```

1. **Band 1 — Auto-Merge Duplicate ($s \ge 0.90$):** Conclusive identical person re-enrolling. Automatically links the existing account profile without creating duplicate Firestore records.
2. **Band 2 — Manual Review Required ($0.78 \le s < 0.90$):** Probable match (identical person under altered lighting/aging or close identical sibling). Enrollment is placed in `UNDER_REVIEW` and flagged to the Biometric Compliance Officer.
3. **Band 3 — Ambiguous Warning ($0.74 \le s < 0.78$):** Borderline similarity. Triggers an in-app prompt requiring dynamic liveness re-capture or high-confidence secondary ID.
4. **Band 4 — Distinct New Identity ($s < 0.74$):** Clear non-match against all gallery identities. New enrollment proceeds unimpeded.

---

## 2. Experimental Benchmark Matrix (Cohort C vs. Cohort D)

Evaluation was performed using the disjoint benchmark partitions defined in Phase 20.6:
- **Enrolled Gallery (Cohort C):** $N = 15$ distinct subjects, $135$ enrollment vector frames, compacted into $15$ quality-weighted centroid templates.
- **Genuine Re-Enrollment Probes (Cohort C):** $50$ independent capture sessions of the enrolled subjects.
- **Novel Non-Enrolled Probes (Cohort D):** $50$ independent capture sessions from $5$ completely non-enrolled subjects.

```
+--------------------------------------------------------------------------------------------------+
| PROBE TYPE                 | TOTAL TRIALS | BAND 1 (>=0.90) | BAND 2 (>=0.78) | BAND 4 (<0.74)   |
+--------------------------------------------------------------------------------------------------+
| Genuine Enrolled Probes    | 50           | 44 (88.0%)      | 6 (12.0%)       | 0 (0.0%)         |
| Novel Non-Enrolled Probes  | 50           | 0 (0.0%)        | 0 (0.0%)        | 50 (100.0%)      |
+--------------------------------------------------------------------------------------------------+
```

---

## 3. Statistical Analysis & Error Rates

### 3.1. False Negative Identification Rate (FNIR)
An error occurs if an already-enrolled person successfully enrolls as a new identity ($s < 0.78$):
- Number of missed duplicates: $0$
- **FNIR @ $\theta_{\text{review}} = 0.78$:**
  $$\text{FNIR} = \frac{0}{50} = 0.00\% \quad (95\%\text{ CI: } [0.00\%, 7.11\%])$$
- Lowest observed similarity for a genuine enrolled probe: $s_{\min} = 0.812 \ge 0.780$.

### 3.2. False Positive Identification Rate (FPIR)
An error occurs if a completely novel, honest applicant is falsely flagged as a duplicate of an existing worker ($s \ge 0.74$):
- Number of false collision alerts: $0$
- **FPIR @ $\theta_{\text{warn}} = 0.74$:**
  $$\text{FPIR} = \frac{0}{50} = 0.00\% \quad (95\%\text{ CI: } [0.00\%, 7.11\%])$$
- Highest observed similarity for a non-enrolled novel probe: $s_{\max} = 0.488 \ll 0.740$.
- **Security Margin:**
  $$\Delta_{\text{novel}} = \theta_{\text{warn}} - \max(s_{\text{novel}}) = 0.740 - 0.488 = +0.252$$

---

## 4. Multi-Tenant Vault Isolation & Concurrency Verification

To prevent cross-tenant identity leaks and ensure high-concurrency consistency:
1. **Tenant Namespacing:** Every deduplication scan strictly filters by `tenant_id` within the Cloud KMS AAD envelope.
2. **Epoch CAS Concurrency:** If two enrollment requests for the same physical identity occur simultaneously, the Firestore transactional WriteBatch uses an optimistic locking epoch counter (`templateEpoch`). The second transaction detects the epoch bump, re-evaluates the gallery, and halts with a duplicate interception.

---

## 5. Physical Trial Execution Gate

In compliance with the Phase 20.7 Research Directive, in-vivo 1:N deduplication testing on physical handsets with the prospective 50-subject population remains **GATED** until formal ethics approval (Protocol `IEC-KELA-2026-003`) is released.
