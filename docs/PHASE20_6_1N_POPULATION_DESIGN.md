# PHASE 20.6 1:N POPULATION DESIGN
## Resolving Probe-Gallery Identity Overlap and Designing Independent 1:N Identification Protocols

**Project:** Kelasagara Major Project  
**System:** Worker Marketplace & Biometric Identity Platform  
**Phase:** 20.6 (Biometric Evidence Integrity & Controlled Pilot Readiness)  
**Standard:** ISO/IEC 19795-1:2021 (§8 1:N Identification Performance)  
**Lead Auditor:** Principal Biometric Research Engineer & Senior Computer Vision Engineer  
**Date:** 2026-10-31  

---

## 1. THE CRITICAL DATASET DEFECT IDENTIFIED IN V20.5

The Phase 20.5 evaluation report (`PHASE20_5_1N_IDENTIFICATION_REPORT.md`) claimed:
> *"1:N identification evaluation conducted against an enrolled gallery of 25 holdout subjects, tested across 100 non-enrolled identification probes (FPIR = 0.00%) and 100 genuine duplicate probes (FNIR = 0.00%)."*

### The Structural Inconsistency:
1. **Partition Holdout Size:** The entire Holdout Partition C contains exactly **25 subjects** (`SUBJ-C-01` through `SUBJ-C-25`).
2. **Gallery Enrollment:** All 25 Holdout subjects were enrolled in the 1:N identification gallery.
3. **The Unresolved Question:** Where did the **100 non-enrolled probes** come from?
   - *Possibility A (Data Leakage):* If the probes were drawn from Partition A (10 subjects) or Partition B (15 subjects), those subjects were already seen during Development and Threshold Calibration. Reusing them as "holdout probes" violates the principle of independent blind testing.
   - *Possibility B (Multiple Probes per Subject):* If the probes were drawn from 25 subjects, 100 probes represent 4 captures per person. In this case, there are only 25 distinct identities, not 100 independent non-enrolled identities, invalidating the denominator for independent FPIR.
   - *Possibility C (Synthetic Vectors):* In the unit test `phase20_5_biometric_validation.test.ts`, the unenrolled probe was a synthetic vector generated from random seed `88888`. It did not correspond to a human being.

---

## 2. SCIENTIFIC IMPLICATIONS

1. **False Sense of Deduplication Robustness:** A gallery of 25 individuals tested with non-enrolled probes drawn from seen subjects or synthetic noise cannot prove that the system prevents duplicate account creation in an open population.
2. **FPIR Scalability Fallacy:** The False Positive Identification Rate scales with gallery size $N_G$:
   $$\text{FPIR}(N_G) \approx 1.0 - (1.0 - \text{FMR})^{N_G}$$
   Even if $\text{FMR} = 0.01\%$, a gallery of $N_G = 1,000$ identities yields:
   $$\text{FPIR} \approx 1.0 - (0.9999)^{1000} \approx 1.0 - 0.9048 = \mathbf{9.52\%}$$
   At $N_G = 10,000$, $\text{FPIR} \approx 63.2\%$. An evaluation on $N_G = 25$ cannot be extrapolated to a production marketplace without indexing and hierarchical clustering.

---

## 3. CANONICAL POPULATION PROTOCOL FOR CONTROLLED PILOT

To eliminate cross-partition contamination, the Phase 20.6.10 Controlled Pilot Protocol defines a 4-cohort population structure:

```
┌───────────────────────────────────────────────────────────────────────────────────────────────┐
│                       CANONICAL 4-COHORT 1:N POPULATION ARCHITECTURE                          │
├────────────────────┬───────────┬──────────────┬───────────────────────────────────────────────┤
│ Cohort Name        │ Subjects  │ Captures/Subj│ Role in Evaluation                            │
├────────────────────┼───────────┼──────────────┼───────────────────────────────────────────────┤
│ 1. DEVELOPMENT (A) │ 10        │ 3 sessions   │ Algorithm tuning & pipeline debugging         │
│ 2. CALIBRATION (B) │ 15        │ 3 sessions   │ Boundary exploration & threshold selection    │
│ 3. GALLERY (C_gal) │ 25        │ Session 0    │ Enrolled gallery identities ($N_G = 25$)      │
│ 4. NON-ENROLLED (D)│ 25        │ Session 0    │ Pure non-enrolled probes ($M = 25$ distinct)  │
│ 5. RE-ENROLL (C_pr)│ 25        │ Sessions 1,2 │ Genuine duplicate probes ($M = 50$ probes)    │
└────────────────────┴───────────┴──────────────┴───────────────────────────────────────────────┤
│ TOTAL PARTICIPANTS │ 75        │              │ ZERO SUBJECT OVERLAP BETWEEN ALL 4 COHORTS    │
└────────────────────────────────┴──────────────┴───────────────────────────────────────────────┘
```

### Protocol Rules:
1. **Strict Identity Disjointness:**
   $$\mathcal{S}_{\text{Dev}} \cap \mathcal{S}_{\text{Calib}} \cap \mathcal{S}_{\text{Gallery}} \cap \mathcal{S}_{\text{NonEnrolled}} = \emptyset$$
2. **Genuine Non-Enrolled Probes:** Cohort D participants are *never* enrolled in the gallery. Each probe from Cohort D represents a unique individual attempting to create an account for the first time.
3. **Genuine Duplicate Probes:** Cohort C participants submit subsequent sessions (Sessions 1 and 2) under simulated distinct account creation requests to measure duplicate detection sensitivity.
4. **Independent Denominators:**
   $$\text{FPIR} = \frac{\text{False Duplicate Flags in Cohort D}}{|\text{Cohort D}|}$$
   $$\text{FNIR} = \frac{\text{Missed Duplicates in Cohort C Probes}}{|\text{Cohort C Probes}|}$$
   The denominators represent distinct human individuals rather than repeated frames from the same subject.
