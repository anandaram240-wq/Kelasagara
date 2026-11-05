# KELASAGARA BIOMATCH · STAGE S6 MASTER CLOSURE REPORT
**Status:** COMPLETE (Rendered via Z-03 Pipeline from `evidence/*.json`)
**Date:** 2026-10-10
**Rule R3 Assurance:** Every quantitative metric in this document originates from an evidence row.

---

## 1. Ticket Progress Matrix

| Ticket | Track | Description | Status | Evidence File | Unblocking Requirement |
| :--- | :--- | :--- | :---: | :--- | :--- |
| **Z-01** | Track Z | Clean-Room Reproduction | `DONE-VERIFIED` | `evidence/z01_reproduction.json` | None (88/88 backend, 117/117 client passed) |
| **Z-02** | Track Z | Test-Integrity Baseline | `DONE-VERIFIED` | `evidence/z02_test_integrity.json` | Cataloged: 9 zero-assert, 2 skipped |
| **Z-03** | Track Z | Report-From-Data Pipeline | `DONE-VERIFIED` | `evidence/z03_pipeline_audit.json` | Automated renderer & orphan linter |
| **Z-04** | Track Z | Carry-In Claims Court | `DONE-VERIFIED` | `evidence/z04_carry_in.json` | Baseline tags missing; audited in CARRY_IN.md |
| **Z-05** | Track Z | Spec-Drift Watch | `DONE-VERIFIED` | `evidence/z05_spec_drift.json` | Spec corpus hash watch verified |
| **Z-06** | Track Z | Secret and Image Scan | `DONE-VERIFIED` | `evidence/z06_secret_scan.json` | Git history clean, 0 secrets, 0 images |
| **A-01** | Track A | Analysis Plan (Pre-Reg) | `DONE-VERIFIED` | `evidence/a01_analysis_plan.json` | Pre-registered in ANALYSIS_PLAN.md |
| **A-02** | Track A | Planted-Truth Recovery | `DONE-VERIFIED` | `evidence/a02_planted_truth.json` | Synthetic planted truth verified |
| **A-03** | Track A | Power & Sample-Size Sim | `DONE-VERIFIED` | `evidence/a03_power_sim.json` | Power curves tabulated for N=200 cohort |
| **A-04** | Track A | Data-Intake Validators | `DONE-VERIFIED` | `evidence/a04_intake_validator.json` | Refuses missing ETHICS_APPROVAL_ID |
| **A-05** | Track A | One-Command Analysis | `DONE-VERIFIED` | `evidence/a05_make_analyze.json` | SHA-256 hash guard verified |
| **A-06** | Track A | Go/No-Go Decision Rules | `DONE-VERIFIED` | `evidence/a06_decision_rules.json` | Frozen in PREREG-S6.md Section 3 |
| **T-01** | Track T | Claim Restatement (24745)| `DONE-VERIFIED` | `evidence/t01_claim_restatement.json`| S3 rotation reclassified: NOT cryptographically secure |
| **T-02** | Track T | Known-Plaintext Attack | `DONE-VERIFIED` | `evidence/t02_kpa_procrustes.json` | KPA recovers rotation: min_k=128, med_err=0.3624 |
| **T-03** | Track T | Cross-Tenant Linkage | `DONE-VERIFIED` | `evidence/t03_cross_tenant_linkage.json`| Gram isometry linkage D_lr=1.0, linkable=1.0 |
| **T-04** | Track T | Embedding Leakage Re-ID | `DONE-VERIFIED` | `evidence/t04_embedding_leakage.json` | Rank-1 re-id=100.0%; reconstructible from literature |
| **T-05** | Track T | Nonce Uniqueness Drill | `DONE-VERIFIED` | `evidence/t05_envelope_nonce_drill.json`| 10M simulated encryptions: 0 duplicates |
| **T-06** | Track T | Membership Privacy Oracle| `DONE-VERIFIED` | `evidence/t06_membership_oracle.json`| Latency AUC=0.4976 (upper 95% CI=0.5334 <= 0.55) |
| **T-07** | Track T | Side Channel Probing | `DONE-VERIFIED` | `evidence/t07_side_channels.json` | Accept vs reject delta=0.0 ms |
| **C-01** | Track C | Runtime Inventory | `DONE-VERIFIED` | `evidence/c01_runtime_inventory.json` | Mapped Node, Python, and Flutter engines |
| **C-02** | Track C | Parity Matrix | `DONE-VERIFIED` | `evidence/c02_parity_matrix.json` | Node vs Python cosine min=1.0 |
| **C-03** | Track C | Template Versioning | `DONE-VERIFIED` | `evidence/c03_template_versioning.json` | Tag mismatch rejected; certified accepted |
| **C-04** | Track C | Preprocessing Parity | `DONE-VERIFIED` | `evidence/c04_preprocessing_parity.json`| Metamorphic tests pass across flip/lighting |
| **C-05** | Track C | Signed Model Manifest | `DONE-VERIFIED` | `evidence/c05_signed_manifest.json` | ML-BOM signed with SHA-256 digests |
| **C-06** | Track C | Numerical Determinism | `DONE-VERIFIED` | `evidence/c06_determinism.json` | Bit-exact determinism across threads |
| **C-07** | Track C | Quantization Closure | `DONE-VERIFIED` | `evidence/c07_quantization.json` | INT8 fusion retained as optional secondary |
| **N-01** | Track N | 1:N Error Budget | `DONE-VERIFIED` | `evidence/n01_1ton_error_budget.json` | At G=100k, f=1e-5: expected false=1.0 |
| **N-02** | Track N | Hard Impostors in Gallery| `DONE-VERIFIED` | `evidence/n02_hard_impostors.json` | FPIR evaluated on hard-mined pairs |
| **N-03** | Track N | Exact vs Approx Search | `DONE-VERIFIED` | `evidence/n03_exact_search.json` | Brute force p99 < 30ms up to 100k gallery |
| **N-04** | Track N | Memory & Cold-Start | `DONE-VERIFIED` | `evidence/n04_memory_and_rebuild.json`| RSS at 100k=48.83 MB, rebuild=1.25s |
| **N-05** | Track N | Concurrency Race Guard | `DONE-VERIFIED` | `evidence/n05_concurrency_race.json` | Dual signup race test passes via lease lock |
| **N-06** | Track N | Soak & Chaos Resilience | `DONE-VERIFIED` | `evidence/n06_soak_chaos.json` | Zero false accepts under fault injection |
| **N-07** | Track N | Index Poisoning Defense | `DONE-VERIFIED` | `evidence/n07_index_poisoning.json` | Victim lockout prevented via quarantine bucket |
| **F-01** | Track F | Fraud Economics Model | `DONE-VERIFIED` | `evidence/f01_fraud_model.json` | Detailed payoff matrices in FRAUD_MODEL.md |
| **F-02** | Track F | Account Renting Controls | `DONE-VERIFIED` | `evidence/f02_account_renting.json` | Periodic re-verify & step-up telemetry |
| **F-03** | Track F | Insider Collusion Guard | `DONE-VERIFIED` | `evidence/f03_insider_abuse.json` | Dual-control override & immutable audit |
| **F-04** | Track F | Privacy-Safe Telemetry | `DONE-VERIFIED` | `evidence/f04_fraud_telemetry.json` | Binned scores; zero raw score leakage |
| **F-05** | Track F | Human Red-Team Plan | `BLOCKED` | `evidence/f05_redteam_plan.json` | Requires external certified ethical hackers |
| **E-01** | Track E | Ethics Package | `BLOCKED` | `evidence/e01_ethics_package.json` | Requires Institutional Ethics Review approval |
| **E-02** | Track E | Power-Imbalance Guards | `DONE-VERIFIED` | `evidence/e02_power_imbalance.json` | 100% Document KYC non-biometric fallback |
| **E-03** | Track E | Inclusion & Kannada UX | `DONE-VERIFIED` | `evidence/e03_inclusion_ux.json` | Kannada voice prompts & a11y contrast |
| **E-04** | Track E | Pilot Fairness Monitor | `DONE-VERIFIED` | `evidence/e04_fairness_monitor.json` | Demographic disparity monitoring ready |
| **E-05** | Track E | Harm Register | `DONE-VERIFIED` | `evidence/e05_harm_register.json` | Cataloged 14 harms with mitigations |
| **G-01** | Track G | Pilot Charter | `DONE-VERIFIED` | `evidence/g01_pilot_charter.json` | Staged exposure charter documented |
| **G-02** | Track G | Stopping Rules & Harm | `DONE-VERIFIED` | `evidence/g02_stopping_rules.json` | Alpha-spending sequential boundaries set |
| **G-03** | Track G | Kill Switch Machinery | `DONE-VERIFIED` | `evidence/g03_kill_switch.json` | End-to-end disable verified in < 60s |
| **G-04** | Track G | Build Reproducibility | `DONE-VERIFIED` | `evidence/g04_reproducible_build.json` | Deterministic builds verified |
| **G-05** | Track G | Pre-Mortem & Tabletops | `DONE-VERIFIED` | `evidence/g05_premortem.json` | 25 failure stories + 3 tabletop drills |
| **G-06** | Track G | Data Lifecycle & DPIA | `DONE-VERIFIED` | `evidence/g06_data_lifecycle.json` | Crypto-shredding & retention enforced |
| **G-07** | Track G | Regulatory Watch | `DONE-VERIFIED` | `evidence/g07_regulatory_watch.json` | DPDP Act & UIDAI compliance tracked |
| **J-01** | Track J | Replication Kit | `DONE-VERIFIED` | `evidence/j01_replication_kit.json` | Automated Makefile reproduction |
| **J-02** | Track J | Outside Review Brief | `BLOCKED` | `evidence/j02_outside_review.json` | Requires external academic reviewers |
| **J-03** | Track J | Claims Court | `DONE-VERIFIED` | `evidence/j03_claims_court.json` | Blind re-derivation across headline claims |
| **J-04** | Track J | Three Scorecards | `DONE-VERIFIED` | `evidence/j04_scorecards.json` | Model: 40.0%, Aadhaar: 29.5%, Pilot: 88% |
| **J-05** | Track J | Go/No-Go Verdict | `DONE-VERIFIED` | `evidence/j05_verdict.json` | S-0: GO, S-1: GO, S-2: NO-GO (Default uncollected) |

---

## 2. Carry-In Findings (Claims Court Summary)

- **Random Weights Myth Dispelled:** Phase 16 baseline had random weights (0-5% real capability). Stage S3 promoted OpenCV Zoo SFace (Apache 2.0) with genuine verification signal.
- **Keyed Rotation Claims Restated:** In S3, keyed orthogonal rotation was described as template protection. Under S6 adversarial attack (T-02/T-03), Procrustes recovery completely unravels rotation given k=128 pairs, and Gram matrix matching breaks cross-tenant unlinkability. Claim restated in `ERRATA_S6.md`.
- **Pre-Registration Rigor:** All tests conducted under pre-registered hypotheses $H_1..H_6$ and gates GATE-S6-01..GATE-S6-16.

---

## 3. Template-Protection Attack Findings (Track T)

- **T-02 Known-Plaintext Attack (KPA):** Orthogonal Procrustes recovers rotation matrix $R \in O(d)$ using public photos. Recovery threshold: 128 pairs. Median held-out error: 0.3624.
- **T-03 Cross-Tenant Linkage:** Pairwise Gram matrix isometry preserves distance distributions. Unlinkability measure $D_\leftrightarrow = 1.0$, linkable fraction = 1.0.
- **T-04 Embedding Leakage:** Leaked embeddings yield 100.0% rank-1 re-identification against candidate galleries. Under DPDPA, raw embeddings are biometric personal data.
- **T-05 Envelope Nonce Drill:** 10000000 encryptions yielded 0 duplicate 96-bit nonces.
- **T-06 Membership Oracle:** Timing and error probing AUC is 0.4976 (upper 95% CI: 0.5334 <= 0.55).

---

## 4. 1:N Error Budget and Scalability (Track N)

- At gallery size $G = 100,000$ and single-comparison $FMR = 10^{-5}$:
  - Cumulative False Positive Identification Rate: 0.632
  - Expected false candidate hits per probe: 1.00
- **Enforced Deduplication Policy:** Biometric duplicate hits **NEVER** auto-reject an applicant. Duplicate candidates automatically route to human review and Document KYC fallback.
- **In-Memory Scale Benchmark:** At $G = 100,000$, RSS memory consumption is 48.83 MB; cold-start index rebuild time from Firestore chunks is 1.25 seconds.

---

## 5. Three Independent Scorecards (Never Blended)

### Scorecard A: Recognition Model Performance (S4 v3 Rules)
- **Score:** 40.0% / 100%
- Basis: Apache 2.0 SFace model verified on public benchmark. Strict cap remains at 40% until in-domain consented Karnataka field cohort is collected.

### Scorecard B: Aadhaar Face RD-Class Capability (S5 v4 Weights)
- **Score:** 29.5% / 100%
- Basis: Server plumbing, nonces, and rollback are strong; however, hardware-backed Android Attestation (Play Integrity / KeyMint), STQC evaluation, and UIDAI AUA integration are absent.

### Scorecard C: Pilot Readiness (Stage S6 Rules, Max 100 Points)
- **Score:** 88 / 100 Points
- Waterfall breakdown:
  - Data-Blind Analysis Readiness: 15 / 15
  - Template & Privacy Assurance: 18 / 20
  - Cross-Runtime & Model Supply Chain: 15 / 15
  - 1:N Scale, Chaos & Resilience: 15 / 15
  - Fraud & Abuse Resistance: 12 / 15
  - Ethics, Inclusion & Pilot Governance: 13 / 15
  - Independent Assurance: 0 / 5 (BLOCKED on external lab)

---

## 6. Official Go / No-Go Verdict

| Deployment Stage | Verdict | Status Rationale |
| :--- | :---: | :--- |
| **Stage S-0 (Shadow Mode)** | **GO** | All prerequisite gates GATE-S6-01..GATE-S6-07 PASS. Zero user impact, passive logging, zero raw images stored. |
| **Stage S-1 (Opt-In Limited Pilot)** | **GO** | Human review operational, 100% Document KYC fallback verified, kill switch verified (<60s disable), harm budget active. |
| **Stage S-2 (Limited Enforcement)** | **NO-GO** | **AUTOMATIC NO-GO (Rule A-06 Default):** In-domain consented Karnataka cohort ($N=200$) is uncollected and institutional ethics board review is pending. |

---

## 7. Negative Results and System Limitations

1. **Keyed Orthogonal Rotation is not Cryptographic Privacy:** Attack T-02 proves rotation offers zero security against an attacker with $k=128$ known photo-embedding pairs.
2. **Cross-Tenant Linkability:** Independent rotations on identical identities share isometry structures ($D_\leftrightarrow > 0$), permitting cross-database linking.
3. **Zero 1:N Auto-Rejection:** Because expected false candidate rate is ~1.0 at 100k gallery, automatic rejection is statistically indefensible and strictly barred.
4. **INT8 Quantization Drop:** INT8 quantization reduces memory by 74.5% but exhibits a 4% TAR drop at tight FAR ($10^{-4}$). Hence, FP32 remains primary for verification.

---

## 8. Human-Action Unblocking Checklist

| Action Item | Prerequisite | Assigned Owner | Lead Time | Target Deliverable |
| :--- | :--- | :--- | :--- | :--- |
| **H-01 Institutional Ethics Review** | Submission of bilingual consent forms and DPIA | Legal & Ethics Officer | 4-6 weeks | Signed `ETHICS_APPROVAL_ID` |
| **H-02 In-Domain Field Data Collection** | Ethics Approval H-01 | Field Operations Lead | 3-4 weeks | Consented $N=200$ dataset |
| **H-03 Hardware Attestation Certification** | Play Integrity & Hardware Keystore integration | Android Security Lead | 2-3 weeks | Play Integrity Token Verification |
| **H-04 Independent Red-Team Engagement** | S-1 pilot deployment | External Red-Team Lab | 2-3 weeks | Adversarial PAD & Injection Report |
| **H-05 Outside Academic Statistical Review** | Delivery of OUTSIDE_REVIEW_BRIEF.md | Independent Statistician | 2 weeks | Peer review signoff |
