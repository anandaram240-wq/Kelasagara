# PHASE 20.5 DATASET GOVERNANCE
## Ethical Governance, Subject Isolation, and Privacy Protections

**Project:** Kelasagara Major Project  
**System:** Worker Marketplace & Multi-Factor Biometric Identity Platform  
**Phase:** 20.5 (Advanced Biometric Scientific Validation Engine)  
**Parent Phase 20.4 Commit:** `41f95bf66bd09cda8ea63d3483e567b06ba6504e`  

---

## 1. ETHICAL AND REGULATORY FRAMEWORK

The Kelasagara research evaluation corpus operates under strict compliance with:
- **India Digital Personal Data Protection Act (DPDPA 2023)**: Biometric data treated as sensitive personal data requiring informed, explicit consent (§6).
- **ISO/IEC 19795-1:2021 Biometric Performance Testing**: Standards for corpus separation, data protection, and subject clustering controls.
- **University Institutional Research Board (IRB) Protocol**: Opaque volunteer identifiers, explicit right to withdrawal, and automated data retention lifecycles.

---

## 2. STRICT 3-WAY PARTITION ISOLATION

### Core Invariant
**A subject's biometric presentations must NEVER appear across more than one partition.**

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                     STRICT SUBJECT-LEVEL PARTITION ISOLATION                     │
├──────────────────────────┬──────────────────────────┬───────────────────────────┤
│ DEVELOPMENT_A (10 Subj)  │ CALIBRATION_B (15 Subj)  │ HOLDOUT_C (25 Subj)       │
│ SUBJ-A-01 ... SUBJ-A-10  │ SUBJ-B-01 ... SUBJ-B-15  │ SUBJ-C-01 ... SUBJ-C-25   │
├──────────────────────────┼──────────────────────────┼───────────────────────────┤
│ Checked for preprocessing│ Used to explore threshold│ Evaluated BLIND.          │
│ & FIQA quality mechanics │ trade-offs & curves      │ Zero threshold tuning!    │
└──────────────────────────┴──────────────────────────┴───────────────────────────┘
```

### Verification Proof
Enforced programmatically by [`ParticipantSplitValidator.validatePartitionIntegrity()`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/backend/src/biometric-evaluation/participant_split_validator.ts):
- Zero duplicate participant declarations across partitions.
- Zero cross-partition subject leakage.
- Zero orphan samples.
- Zero session or burst frame leakage.

---

## 3. IDENTIFIER ANONYMIZATION & KEY ESCROW
1. **Opaque Identifiers**: Participants are identified solely by synthetic IDs (`SUBJ-A-01` to `SUBJ-C-25`).
2. **Key Escrow**: Linkage between real human identity and research IDs is stored in an encrypted offline file accessible only by the Principal Investigator.
3. **No Embedded Images**: Benchmark reports and test suites store numeric similarity scores and statistical metrics only; raw facial images are never checked into git or emitted in CI logs.
