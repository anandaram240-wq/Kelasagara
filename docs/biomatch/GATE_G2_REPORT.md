# GATE G2 REPORT: REQUIREMENTS, THREAT MODEL & QUOTA WORKSHEET

**Subsystem:** Kelasagara BioMatch V7  
**Gate:** **Gate G2** (Phase 2: Requirements, Threat Model, SLOs, Tiers, Quota Math)  
**Status:** **PASSED**  
**Release Readiness Level (RRL):** **RRL-0 (Research Prototype)**  
**Target Platform:** Firebase Spark Plan (Free Tier) | Sole Database: Cloud Firestore  
**Branch:** `biomatch/v7-hardening`  
**Date:** 2026-10-10  

---

### 1. SUMMARY SPECIFICATION

| Field | Detail |
|---|---|
| **Gate** | **Gate G2 (Phase 2)** |
| **Status** | **PASSED** |
| **Evidence IDs** | **EV-018** (`docs/biomatch/THREAT_MODEL.md`), **EV-019** (`docs/biomatch/QUOTA_WORKSHEET.md`), **EV-020** (`docs/biomatch/FMEA.md`) |
| **What Changed in Risk Register** | - **RISK-01 (Client Rules Forgery):** Marked **RESOLVED & VERIFIED** (tested live with OpenJDK 27 emulator; EV-011, EV-013).<br/>- **RISK-04 (Host Lacks Java):** Marked **RESOLVED** (OpenJDK 27 installed; emulator verified live; EV-013).<br/>- **RISK-07 (Spark Quota Saturation):** Added with mitigation (enforced bounded scan $K \le 500$ + circuit breaker queueing).<br/>- **RISK-08 (Face Template Inversion R-14):** Added with mitigation (per-subject AES-256-GCM envelope encryption + crypto-shredding).<br/>- **RISK-09 (API Oracle Probing):** Added with mitigation (uniform categorical responses + constant latency bucket).<br/>- **RISK-10 (Play Integrity Quota Saturation):** Added with mitigation (client token caching + Enterprise quota escalation plan). |
| **Decisions Needed from Owner** | None blocking Phase 3. Defaults applied:<br/>- Q1 (Target Gallery): Piloting at $N = 1,000$ to $10,000$ (Hassan / Karnataka district pilot).<br/>- Q2 (Model License): Permissive code license (Apache 2.0) confirmed, but model weights provenance requires Phase 3 verification before production.<br/>- Q3 (Hosting): Standalone Node.js backend confirmed as Tier 0 (dev/shadow only); persistent database remains strictly Cloud Firestore.<br/>- Q5 (Training Data): Custom training blocked until consented dataset curated; baseline relies on pre-trained ONNX evaluation. |
| **Next Step** | **Proceed autonomously to PHASE 3:** Model, Data and License Selection (`docs/biomatch/MODEL_SELECTION.md`): evaluate candidate pretrained models (SFace, MobileFaceNet, GhostFaceNet), inspect weight licenses and training datasets, investigate Indian face demographic benchmark datasets (e.g. FairFace, Indian Movie Face Database), and formalize selection criteria. |

---

### 2. GATE CRITERIA CHECKLIST

- [x] **Threat Model Reviewed:** 8 personas (casual spoofer, motivated fraudster, repeat registrant, modified client/Frida, API oracle prober, insider/reviewer, database data thief, supply-chain attacker) evaluated under STRIDE. Mermaid data-flow diagram with trust boundaries documented in `docs/biomatch/THREAT_MODEL.md`.
- [x] **Assurance Level Per Operation Defined:** Registration, Step-Up, High-Value Booking, Payout, Phone Change, and Recovery paths specified with target FMR/FNMR hypotheses and fallback paths.
- [x] **SLO Hypotheses Documented:** Availability ($\ge 99.5\%$), p50/p95 latencies, RTO ($\le 30\text{ min}$), and RPO ($0\text{ s}$) cataloged strictly as hypotheses to validate.
- [x] **Tier Ladder Formalized:** Tier 0 (Spark/dev/shadow) through Tier 3 (regional DR) established per Part 4.4.
- [x] **Quota Worksheet Authored:** Spark Firestore kNN vector search reads per query ($\lceil E/100 \rceil + k$) computed for $N \in \{1k, 10k, 50k\}$. Bounded scan ($K \le 500$) guarantees deterministic 10 reads/query, providing headroom for 1,500 daily enrollments under normal app traffic in `docs/biomatch/QUOTA_WORKSHEET.md`.
- [x] **Pipeline FMEA Completed:** 8-stage pipeline analyzed; 5 high-priority failure modes ($\text{RPN} \ge 100$) prioritized with active architectural mitigations in `docs/biomatch/FMEA.md`.
- [x] **Invariant ID Mapping Complete:** Every single Part 5 invariant (I-01 through I-27) mapped to an owning test ID with verification method and test status.
