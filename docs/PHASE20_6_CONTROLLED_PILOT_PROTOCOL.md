# PHASE 20.6 CONTROLLED PILOT PROTOCOL
## Ethical, Privacy-Preserving Research Protocol for Empirical Biometric Data Acquisition

**Project:** Kelasagara Major Project  
**System:** Worker Marketplace & Biometric Identity Platform  
**Phase:** 20.6 (Biometric Evidence Integrity & Controlled Pilot Readiness)  
**Standard:** DPDPA 2023, GDPR Article 9 & ISO/IEC 19795-1:2021  
**Lead Protocol Architect:** Privacy and Security Architect & Principal Biometric Research Engineer  
**Date:** 2026-10-31  

---

## 1. MISSION & ETHICAL PRINCIPLES

Rather than launching premature or unconsented telemetry across the production worker population, Kelasagara establishes a **Controlled, Voluntary Research Pilot**. 

A fundamental rule of scientific biometric evaluation is that **routine production login events cannot be automatically labeled as genuine or impostor comparisons**. In a commercial marketplace, a login comparison is an unverified operational event; claiming that 30,000 routine production logins demonstrate a 1:10,000 FMR is scientifically invalid, because true impostor identities in the wild are unknown without ground-truth labels. 

True FMR validation requires a **defensible known-impostor trial design** conducted under controlled, consented conditions.

---

## 2. THE TWELVE MANDATORY PILOT REQUIREMENTS

```
┌───────────────────────────────────────────────────────────────────────────────────────────────┐
│                           TWELVE MANDATORY RESEARCH PILOT CONTROLS                            │
├──────────────────────────────────────┬────────────────────────────────────────────────────────┤
│ Requirement Control                  │ Operational Policy & Engineering Implementation        │
├──────────────────────────────────────┼────────────────────────────────────────────────────────┤
│ 1. Voluntary Enrollment              │ Participation is strictly opt-in; no marketplace impact│
│ 2. Clear Research Consent            │ Dedicated informed consent explaining biometric capture│
│ 3. Explicit Telemetry Opt-In         │ Separate consent toggle for research telemetry logging │
│ 4. Static Decision Thresholds        │ No automated or dynamic threshold shifting during study│
│ 5. Zero Raw Image Transmission       │ Routine telemetry transmits similarity scores, not raw │
│ 6. No Unnecessary Embedding Holding  │ Research embeddings purged immediately after trial     │
│ 7. No Automated Account Suspension   │ Experimental score triggers NEVER lock worker accounts │
│ 8. Production Engine Isolation       │ Production auth logic untouched; runs in shadow sandbox│
│ 9. No Cross-Account Scraping         │ Research probes NEVER scrape live worker vaults        │
│ 10. Unconditional Right to Withdraw  │ One-click participant erasure via opaque ID            │
│ 11. Restricted Record Access         │ Principal Investigator PKI-restricted access only      │
│ 12. Documented Incident Response     │ Immediate study freeze upon cryptographic alert        │
└──────────────────────────────────────┴────────────────────────────────────────────────────────┘
```

---

## 3. TRIAL DESIGN: GROUND-TRUTH KNOWN-IMPOSTOR COHORTS

To achieve mathematically defensible validation without exposing user accounts:

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                        KNOWN-GROUND-TRUTH RESEARCH TRIAL DESIGN                        │
├────────────────────────────────────────────────────────────────────────────────────────┤
│ 1. RECRUITMENT: 100 Consenting Volunteers recruited under university ethics approval.  │
│ 2. GROUND TRUTH IDENTITIES: Each volunteer assigned an opaque research ID:             │
│    • Cohort G (Gallery Enrollees): 50 subjects ($N_G = 50$).                           │
│    • Cohort N (Known Impostor Non-Enrollees): 50 subjects ($N_I = 50$).                │
│ 3. CAPTURE PROTOCOL:                                                                   │
│    • 3 Multi-frame bursts per volunteer across 3 environmental lighting setups.        │
│ 4. GENUINE TRIALS: 50 Cohort G subjects compared against their own enrolled templates  │
│    ($N_{\text{gen}} = 50 \times 2 = 100$ intra-subject cross-session pairs).          │
│ 5. KNOWN IMPOSTOR TRIALS:                                                              │
│    • 50 Cohort N subjects attempt verification against all 50 Cohort G templates:      │
│      $$N_{\text{imp}} = 50 \times 50 = \mathbf{2,500 \text{ Known Impostor Trials}}$$ │
│ 6. GROUND-TRUTH CERTAINTY: Every comparison has a mathematically certain label:        │
│    Cohort N probe vs Cohort G gallery is 100% known ground-truth impostor.             │
└────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 4. INCIDENT RESPONSE & ETHICAL SAFEGUARDS

1. **Safety Trigger:** If an anomaly (e.g., unexpected biometric cluster collision or false match at $\theta \ge 0.74$) occurs:
   - The trial session is immediately suspended.
   - An immutable audit snapshot is exported to the offline research vault.
   - Zero production worker records are modified or inspected.
2. **Post-Trial Data Destruction:** Upon completion of statistical analysis:
   - All ephemeral test crops are zero-filled and deleted.
   - The Tier 1 mapping table is permanently crypto-shredded following university archival retention guidelines (90 days).
