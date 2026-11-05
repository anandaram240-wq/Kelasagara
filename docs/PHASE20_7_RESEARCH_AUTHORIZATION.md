# PHASE 20.7 RESEARCH AUTHORIZATION
## University Institutional Ethics Committee Protocol, Governance State Machine, and Pre-Approval Boundaries

**Project:** Kelasagara Major Project  
**System:** Multi-Factor Biometric Identity and Authentication Platform  
**Phase:** 20.7 (Controlled Physical Biometric Validation & PAD Hardening)  
**Regulatory Standards:** India Digital Personal Data Protection Act (DPDPA 2023), GDPR Article 9 & ICMR Ethical Guidelines for Biomedical Research  
**Current Governance State:** **`SUBMITTED` (DATA COLLECTION BLOCKED)**  

---

## 1. RESEARCH PURPOSE STATEMENT

The primary objective of this research study is to evaluate the empirical recognition accuracy, presentation attack detection (PAD) robustness, and environmental stability of the Kelasagara face authentication engine (integrating SFace 128-D neural embeddings and YuNet landmark detection). 

The investigation aims to establish:
1. Intra-subject facial similarity distributions across independent smartphone camera sessions under diverse ambient lighting regimes.
2. Inter-subject impostor rejection bounds on the 128-dimensional unit hypersphere.
3. Resilience against physical Presentation Attack Instruments (PAIs) including high-resolution printed photos, display screen video replays, and simulated blinks.
4. Non-punitive biometric deduplication workflows for blue-collar gig platform workers.

---

## 2. THE RESEARCH AUTHORIZATION STATE MACHINE

In accordance with university regulations and scientific ethics, human biometric data collection is strictly governed by a formal four-state transition engine:

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                        RESEARCH AUTHORIZATION STATE MACHINE                            │
└────────────────────────────────────────────────────────────────────────────────────────┘
          │
          ▼
     ┌───────────┐
     │   DRAFT   │ Protocol, Participant Information Sheet & Consent Forms prepared
     └─────┬─────┘
           │ Formal submission to Institutional Ethics Committee (IEC / IRB)
           ▼
     ┌───────────┐
     │ SUBMITTED │ ◄─── CURRENT KELASAGARA SYSTEM STATE (PHASE 20.7)
     └─────┬─────┘      (DATA COLLECTION STRICTLY BLOCKED)
           │
     ┌─────┴───────────────┐
     │                     │
     ▼                     ▼
┌──────────┐         ┌───────────┐
│ REJECTED │         │ APPROVED  │ Formal clearance certificate issued by IEC
└──────────┘         └─────┬─────┘
                           │ Principal Investigator registers approved protocol
                           ▼
             ┌───────────────────────────────┐
             │  DATA_COLLECTION_AUTHORIZED   │ (Only state permitting physical capture)
             └───────────────────────────────┘
```

### Mandatory Invariant Enforced:
Because formal written approval has **not yet been issued by the Institutional Ethics Committee**, the system remains in the **`SUBMITTED`** state:
- **Dataset acquisition remains BLOCKED.**
- **Physical attack-presentation experiments involving human subjects remain BLOCKED.**
- **Zero raw biometric facial captures may be stored on disk or cloud.**
- **Only synthetic software tests, mathematical evaluations, and system preparations are permitted.**

---

## 3. TEN MANDATORY RESEARCH GOVERNANCE PILLARS

1. **Research Purpose Statement:** Explicitly restricted to academic algorithmic validation; commercial exploitation of research samples is prohibited.
2. **Participant Information Sheet (PIS):** Plain-language explanation of technology, risks, rights, and voluntary nature (`docs/PHASE20_7_PARTICIPANT_INFORMATION_SHEET.md`).
3. **Informed Consent Document:** Written, un-coerced participant agreement with explicit checkboxes for biometric processing (`docs/PHASE20_7_CONSENT_PROTOCOL.md`).
4. **Data Collection Protocol:** Frontal capture protocol using standardized distance (40–60 cm) and lighting regimes (`docs/PHASE20_7_HUMAN_CAPTURE_PROTOCOL.md`).
5. **Data Retention Policy:** Automatic 90-day retention purge schedule (`docs/PHASE20_7_DATA_RETENTION_POLICY.md`).
6. **Withdrawal Procedure:** Unconditional right to withdraw via assigned opaque identifier (`SUBJ-X-YY`) triggering instantaneous cryptographic erasure.
7. **Data Access Policy:** Role-based access restricted strictly to the Principal Investigator and authorized biometric research auditors.
8. **Research Security Architecture:** Air-gapped local encrypted storage (AES-256-GCM); zero plain-text embeddings; zero raw facial images in Git.
9. **Data Breach Response Plan:** Immediate study suspension and data shredding within 4 hours if encryption key compromise or unauthorized access is detected.
10. **Publication & Anonymization Policy:** Research papers and academic defense presentations must report aggregated metrics only ($k$-anonymity); publication of identifiable raw facial imagery is strictly prohibited.

---

## 4. PROHIBITED DATA SOURCES & PRACTICES

To safeguard human rights and prevent ethical violations:
- **No Aadhaar Photographs:** Zero government identity card photos collected or processed.
- **No Web-Scraped Photos:** Zero social media or public internet scraping.
- **No Worker Marketplace Discrimination:** Participation in the research study is 100% voluntary. Declining to participate has zero effect on a worker's account status, job assignments, ratings, or payouts.
- **No Fake Consent:** No simulated string identifier (e.g. `CONSENT-HASH-SUBJ-01`) may be represented as a verified consent signature.
