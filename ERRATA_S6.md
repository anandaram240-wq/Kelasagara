# KELASAGARA BIOMATCH · STAGE S6 ERRATA & FORMAL RESTATEMENTS (ERRATA_S6.md)
**Publication Date:** 2026-10-10  
**Baseline Git HEAD:** `215c44501b178422da8fc9233f4f10329d16b76a`  
**Governing Rule:** Rule R7 (Errata, Not Rewrites)  

---

## 1. Formal Restatement: Keyed Orthogonal Rotation vs ISO/IEC 24745
- **Original Claim (Stage S3):** Keyed orthogonal rotation $R \in O(d)$ provides ISO/IEC 24745 template protection (irreversibility, unlinkability, renewability) prior to storage.
- **Errata / Finding (Stage S6 Track T Attacks):**
  1. **Irreversibility Refuted:** Because an orthogonal matrix is an isometry ($R^T R = I$), an attacker holding public face images of enrolled subjects can recover $R$ via Orthogonal Procrustes using $k \le 128$ noisy pairs (Attack T-02).
  2. **Unlinkability Refuted:** The inner products between vectors are identical before and after rotation ($\langle R x_1, R x_2 \rangle = \langle x_1, x_2 \rangle$). An attacker with databases from two distinct tenants can link identical subjects via Gram matrix matching with Gomez-Barrero $D_\leftrightarrow = 1.0$ (Attack T-03).
- **Corrected Architecture:** Template privacy and confidentiality in Kelasagara are enforced **strictly through AES-256-GCM envelope encryption** and per-user ephemeral data keys wrapped in hardware HSM / KMS, never through linear algebraic transformations.

---

## 2. Formal Restatement: 1:N Deduplication Decision Policy
- **Original Claim (Stage S3):** Single-threshold automated deduplication (0.485 at 10k, 0.512 at 100k) for applicant acceptance or rejection.
- **Errata / Finding (Stage S6 Track N Error Budget):**
  - For gallery size $G = 100,000$ and single-comparison $FMR = 10^{-5}$, cumulative $FPIR = 1 - (1 - 10^{-5})^{100,000} \approx 63.2\%$.
  - This yields an expected $\approx 1.0$ false candidate match per inquiry. Automated rejection at scale would systematically disenfranchise legitimate workers.
- **Corrected Policy:** Biometric deduplication duplicate hits **NEVER automatically reject an applicant**. All flagged duplicate candidates route to mandatory human KYC review, and applicants retain an absolute right to Document KYC fallback.

---

## 3. Errata: Missing Baseline Git Tags
- **Notice:** Git tags `s4-final` and `s5-final` were absent at session start.
- **Action Taken:** Per Stage S6 non-negotiable rules, all carry-in metrics were downgraded to `UNVERIFIED` and independently re-observed via the report-from-data pipeline.
