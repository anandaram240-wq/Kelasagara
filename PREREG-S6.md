# KELASAGARA BIOMATCH · STAGE S6 PRE-REGISTRATION (PREREG-S6.md)
**Document Version:** 1.0.0  
**Date:** 10 October 2026  
**Repository Baseline:** `215c44501b178422da8fc9233f4f10329d16b76a`  
**Missing Tags Recorded:** `s4-final` (MISSING), `s5-final` (MISSING). All prior S3/S4/S5 claims default to UNVERIFIED until re-observed in this session.  
**Rule Compliance:** R1–R20 strictly enforced.

---

## 1. Hypotheses (Pre-Registered)

- **$H_1$ (Test Integrity):** At least one test in the baseline repository exhibits tautological, mock-on-unit, or assertion-free patterns that must be cataloged in `TAUTOLOGY_REPORT.md`.
- **$H_2$ (Template Attackability - ISO/IEC 24745):** Keyed orthogonal rotation $R \in O(d)$ does not provide cryptographic irreversibility or unlinkability under a Known-Plaintext Attack (KPA); estimating $R$ via Orthogonal Procrustes requires $k \le 128$ noisy (photo, embedding) pairs.
- **$H_3$ (Cross-Tenant Linkability):** Two tenant databases with independent orthogonal rotations preserve identical pairwise Gram similarity structures, permitting unsupervised or few-shot cross-database identity linkage.
- **$H_4$ (Membership Privacy Oracle):** Verification endpoints without calibrated latency padding and uniform error envelopes exhibit measurable timing or response discrepancies that an attacker can exploit (target: upper 95% CI on AUC $\le 0.55$).
- **$H_5$ (1:N Deduplication Scalability):** For gallery size $G = 100,000$ and single-comparison $FMR = 10^{-5}$, false positive identification rate exceeds acceptable single-decision bounds unless candidate hits route to human review or step-up verification.
- **$H_6$ (Cross-Runtime Numerical Parity):** Evaluating the same face crops across differing CPU architectures or ONNX Runtime execution providers produces non-zero float divergence; cross-runtime verification degrades unless preprocessing and interpolation are bit-exact.

---

## 2. Pre-Registered Gates (GATE-S6-01 through GATE-S6-16)

| Gate ID | Description | Success Criterion | Failure Action |
| :--- | :--- | :--- | :--- |
| **GATE-S6-01** | Clean-Room Reproduction | Full suite passes in session; all discrepancies logged in `ERRATA_S6.md`. | Stop; record regression. |
| **GATE-S6-02** | Report-From-Data Pipeline | Zero orphan numbers in rendered reports (`no-orphan-numbers` passes). | Fail report generation. |
| **GATE-S6-03** | Planted-Truth Recovery | Analysis pipeline recovers planted ground truth with 95% CI coverage $\in [0.93, 0.97]$; all planted leakage bugs detected; negative controls fail loudly. | Fail Track A; do not accept analysis engine. |
| **GATE-S6-04** | Frozen Analysis Code | SHA-256 of `analysis/` frozen in ledger; tool refuses execution on hash mismatch. | Abort analysis. |
| **GATE-S6-05** | Template Attacks T-02..T-04 | KPA Procrustes recovery and cross-tenant linkage executed on public data; limitations published. | Reclassify S3 claims as REFUTED / RESTATED. |
| **GATE-S6-06** | Membership Privacy Oracle | Automated probe timing & status leak test achieves upper 95% CI of AUC $\le 0.55$. | Patch latency jitter; retest. |
| **GATE-S6-07** | Cross-Runtime Parity | Evaluated across $\ge 2$ runtimes/architectures; template version tags strictly enforced; tampered models rejected. | Enforce dual-tag gating. |
| **GATE-S6-08** | 1:N Error Budget & Dedupe Policy | FPIR tabulated for $G \in [10^3, 10^6]$; duplicate hit strictly routes to human review (never auto-reject). | Block auto-rejection path. |
| **GATE-S6-09** | Soak & Chaos Resilience | Degraded modes fail closed or step up; exactly zero false accepts under fault injection. | Fail Track N. |
| **GATE-S6-10** | Adversary Fraud Economics | Complete threat model covering account renting; MODEL results strictly barred from headline metrics. | Disqualify unverified numbers. |
| **GATE-S6-11** | Ethics & Ingest Control | Ingest tool strictly rejects data lacking valid `ETHICS_APPROVAL_ID` and consent linkage hash. | Abort ingestion. |
| **GATE-S6-12** | Kill Switch Verification | End-to-end disablement tested; time-to-disable measured; fail-safe fallback verified. | Block pilot clearance. |
| **GATE-S6-13** | Build Reproducibility | Two clean builds produce bit-identical artifact digests or explain platform differences. | Log non-determinism errata. |
| **GATE-S6-14** | Replication Kit | `make replicate` reproduces all headline tables and scores from raw files twice with identical hashes. | Invalidate unreplicable claims. |
| **GATE-S6-15** | Claims Court & Re-derivation | Every headline claim evaluated under 3 counter-arguments and blinds re-derived. | Downgrade to DONE-UNVERIFIED or WITHDRAWN. |
| **GATE-S6-16** | BLOCKED Checklist Complete | Every human-dependent or external-authority ticket has an unblocking checklist with named owner and prerequisite. | Default to BLOCKED; do not fake. |

---

## 3. Go / No-Go Decision Rules (Frozen Before Real Data)

### Stage S-0: Shadow Mode (Passive Observer, Zero User Impact)
- **GO Requirements:** Gates GATE-S6-01 through GATE-S6-07 PASS; zero crashes in shadow worker thread; p95 latency $\le 30$ ms; zero raw images stored.
- **NO-GO Condition:** Any unhandled crash, memory leak $> 50$ MB/hour, or raw image retention.

### Stage S-1: Opt-In Limited Pilot (Explicit Consent, 100% Fallback Path Active)
- **GO Requirements:** S-0 GO achieved; GATE-S6-08 through GATE-S6-12 PASS; human review operational; fallback Document KYC button verified; kill switch operational with disable time $< 60$ seconds.
- **NO-GO Condition:** Any un-reviewed duplicate rejection, absence of non-biometric alternative, or failure of kill switch.

### Stage S-2: Limited Enforcement (Gradual Production Shift Verification)
- **GO Requirements:** S-1 GO achieved; in-domain consented cohort $\ge 200$ subjects collected with approved `ETHICS_APPROVAL_ID`; end-to-end FNMR $\le 3.0\%$ at $FMR \le 10^{-4}$ with 95% upper CI $\le 5.0\%$; zero group disparity violations ($FNMR_{worst} / FNMR_{overall} \le 2.0\times$).
- **NO-GO Condition (Default):** In-domain data uncollected or ethics approval absent $\rightarrow$ **AUTOMATIC NO-GO**.

---

## 4. Stopping and Amending Rules
- Amendments to this pre-registration are permitted only as dated, append-only entries with an explicit justification.
- Silent edits to hypotheses, gates, or decision rules violate Invariant I-01 and trigger immediate audit failure.
