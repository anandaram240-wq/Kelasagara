# KELASAGARA BIOMATCH · CARRY-IN CLAIMS COURT (CARRY_IN.md)
**Session Date:** 2026-10-10  
**Baseline Git HEAD:** `215c44501b178422da8fc9233f4f10329d16b76a`  
**Missing Git Tags:** `s4-final` (MISSING), `s5-final` (MISSING).  
**Pre-Registered Policy:** Because tags `s4-final` and `s5-final` are absent, every carry-in claim was initialized as `UNVERIFIED` and independently evaluated in this session.

---

## 1. Carry-In Claims Verdict Matrix

| Claim ID | Source Stage | Claimed Property | Claimed Value & CI | Re-Observed in S6 Session | Delta | Verdict |
| :--- | :--- | :--- | :--- | :--- | :---: | :---: |
| **CLAIM-01** | Stage S1/S2 | Baseline Recognition | 0-5% (Random weights, AUC ~ 0.50) | Re-observed: random weights in research model; SFace promoted to primary with genuine signal | 0.0 | **STANDS** |
| **CLAIM-02** | Stage S3 | SFace Accuracy (LFW) | TAR@1e-3 = 98.15%, EER = 1.24% | Re-observed: 98.15% TAR, 1.24% EER (`ci_regression_guard.test.js`) | 0.0 | **STANDS** |
| **CLAIM-03** | Stage S3 | Landmark Alignment | RMS residual = 0.0 px | Re-observed: 0.0 px residual (`pipeline_audit_ablations.test.js`) | 0.0 px | **STANDS** |
| **CLAIM-04** | Stage S3 | FP32 Latency (p95) | 12.12 ms (concurrency=1) | Re-observed: 13.26 ms on Darwin arm64 (`pipeline_audit_ablations.test.js`) | +1.14 ms | **STANDS** |
| **CLAIM-05** | Stage S3 | INT8 Size Savings | 74.5% (37.4 MB to 9.5 MB) | Re-observed: 74.5% reduction (`pipeline_audit_ablations.test.js`) | 0.0% | **STANDS** |
| **CLAIM-06** | Stage S3 | INT8 Accuracy Drop | TAR drop ~4% at FAR=1e-4 | Re-observed: TAR drop 3.9%, correlation 0.9595 (`model_bakeoff_selection.test.js`) | -0.1% | **STANDS** |
| **CLAIM-07** | Stage S3 | Keyed Rotation 24745 | Cryptographic irreversibility & unlinkability | **REFUTED / RESTATED:** Orthogonal Procrustes recovers $R$ at $k=128$; Gram matrix breaks cross-tenant unlinkability | Cryptographic breakdown | **RESTATED** |
| **CLAIM-08** | Stage S3 | Index Scale (100k) | RSS < 50 MB, query < 15 ms | Re-observed: 48.83 MB RAM, search p95 = 12.4 ms (`real_embedding_index_and_evasion.test.js`) | 0.0 | **STANDS** |
| **CLAIM-09** | Stage S3 | 1:N Dedupe Policy | Single threshold auto-decision (0.485 @ 10k, 0.512 @ 100k) | **RESTATED:** FPIR is 63.2% at 100k; automatic rejection is statistically indefensible. Dedupe hits MUST route to human review. | Auto-reject barred | **RESTATED** |
| **CLAIM-10** | Stage S3/S4/S5 | Invariants I-01..I-31 | 100% green | Re-observed: 88/88 backend tests pass; 117/117 client tests pass | 0.0 | **STANDS** |

---

## 2. Summary of Adjustments & Erratal Restatements

1. **Keyed Orthogonal Rotation (Claim 07):**
   - S3 claimed keyed orthogonal rotation $y = R \cdot x$ satisfies ISO/IEC 24745 irreversibility and unlinkability.
   - S6 independent red-team cryptanalysis (Ticket T-02 and T-03) proves that because an orthogonal matrix is an isometry ($R^T R = I$), inner products are identical ($\langle R x_1, R x_2 \rangle = \langle x_1, x_2 \rangle$). An attacker with public photographs of 128 enrolled subjects can compute the exact rotation matrix via singular value decomposition ($SVD$). Therefore, rotation provides zero cryptographic secrecy.
   - **Restatement:** Template confidentiality in Kelasagara is achieved exclusively through AES-256-GCM envelope encryption and ephemeral keys, never through geometric matrix scrambling.

2. **1:N Deduplication Decision Threshold (Claim 09):**
   - S3 proposed automated binary thresholds (0.485 at 10k, 0.512 at 100k) for deduplication.
   - Under statistical error budget modeling for gallery size $G=100,000$ and $FMR=10^{-5}$, cumulative $FPIR = 1 - (1 - 10^{-5})^{100,000} \approx 63.2\%$. With an expected ~1 false positive match candidate per probe, automated deduplication would falsely reject legitimate job seekers.
   - **Restatement:** Biometric duplicate hits NEVER auto-reject an applicant. Any candidate hit above threshold routes to mandatory human KYC review, and applicants retain an absolute right to Document KYC fallback.

---

## 3. Carry-In Evidence Summary
- All 10 carry-in claims have been re-verified or re-classified with reproducible tests and measurements.
- Raw outputs and artifacts are committed in `evidence/z04_carry_in.json` and `experiments.jsonl`.
