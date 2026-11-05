# PHASE 20.7 DATA RETENTION POLICY
## Research Data Lifecycle, Automated Retention Purge, and Cryptographic Erasure Procedures

**Project:** Kelasagara Major Project  
**System:** Multi-Factor Biometric Identity and Authentication Platform  
**Phase:** 20.7 (Controlled Physical Biometric Validation & PAD Hardening)  
**Standard:** DPDPA 2023 (§8 Data Fiduciary Obligations) & GDPR Article 5(1)(e)  
**Date:** 2026-11-01  

---

## 1. DATA RETENTION LIFECYCLE TIMELINE

Research biometric data collected during the controlled pilot is subject to a strict 90-day maximum retention schedule:

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                        90-DAY RESEARCH DATA RETENTION TIMELINE                         │
├────────────────────┬───────────────────────────────────────────────────────────────────┤
│ Day 0 (T_0)        │ Ingestion of consented biometric sample; AES-256-GCM encryption   │
│ Day 1 - 30         │ Feature extraction, 1:1 similarity matching & PAD evaluation      │
│ Day 31 - 60        │ Statistical confidence analysis, ROC/DET curves & peer review     │
│ Day 61 - 85        │ Academic thesis / report preparation with aggregated k-anonymity  │
│ Day 90 (T_purge)   │ AUTOMATED HARD PURGE & CRYPTOGRAPHIC ERASURE                      │
└────────────────────┴───────────────────────────────────────────────────────────────────┘
```

---

## 2. THE WITHDRAWAL AND CRYPTO-SHREDDING PROCEDURE

A research participant possesses the unconditional right to withdraw at any time prior to data destruction:

```
[Participant Requests Withdrawal]
               │
               ▼
   [Identify Opaque ID via Tier 1] (e.g. SUBJ-C-014)
               │
               ▼
   [Destroy Participant Key Envelope] (Crypto-shredding)
               │
               ▼
   [Over-write Raw Binary Samples in Storage] (NIST SP 800-88 Zero-Fill)
               │
               ▼
   [Mark Status in Consent Ledger] -> "WITHDRAWN_PURGED"
               │
               ▼
   [Issue Written Confirmation to Volunteer]
```

### Cryptographic Shredding Mechanism:
Every participant's biometric sample files are encrypted with an individual, participant-specific Data Encryption Key (DEK). When a withdrawal request is processed, the DEK is cryptographically shredded (erased from memory and overwriting key metadata with cryptographic random noise). Even if encrypted raw blocks exist on storage media, they become mathematically unrecoverable.

---

## 3. SCHEDULED POST-PILOT PURGE PROTOCOL

At Day 90 following the conclusion of the research study:
1. **Automated Audit Check:** The Principal Investigator runs the retention validator:
   ```bash
   node dist/scripts/purge_expired_research_samples.js --watermark=90days
   ```
2. **Physical Overwrite:** All temporary image buffers, aligned face crops, and raw feature arrays are purged using secure 3-pass zero-fill (`dd if=/dev/urandom of=target`).
3. **Audit Log Retention:** Only the cryptographic verification hashes and anonymized aggregate statistical tables are retained for university archiving.
