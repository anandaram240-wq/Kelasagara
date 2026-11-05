# PHASE 20.5 CONSENT AND RETENTION
## Volunteer Informed Consent, Rights of Withdrawal, and Data Lifecycle Policy

**Project:** Kelasagara Major Project  
**System:** Worker Marketplace & Multi-Factor Biometric Identity Platform  
**Phase:** 20.5 (Advanced Biometric Scientific Validation Engine)  
**Parent Phase 20.4 Commit:** `41f95bf66bd09cda8ea63d3483e567b06ba6504e`  

---

## 1. INFORMED CONSENT SPECIFICATION

Every participating volunteer executed a standard biometric evaluation consent agreement specifying:
1. **Explicit Purpose**: Evaluation of algorithmic accuracy, presentation attack detection, and demographic fairness for the Kelasagara University Major Project.
2. **Voluntary Participation**: Participation is strictly voluntary with zero academic, employment, or financial penalties for refusal.
3. **No Commercial Use**: Biometric captures will not be sold, licensed, or utilized for commercial model training.
4. **Scope of Data Collected**: Multi-frame facial burst captures, voluntarily disclosed demographic categories (sex, skin-tone scale, glasses wear), and device sensor metadata.

---

## 2. PARTICIPANT RIGHTS & WITHDRAWAL PROTOCOL

Under DPDPA 2023 §6(4) and GDPR Art 17, volunteers retain the unconditional right to withdraw consent at any time:
- **Withdrawal Mechanism**: Volunteer submits written withdrawal referencing their participant code or signed consent hash.
- **Immediate De-identification & Purge**:
  - The offline key escrow entry linking the subject to their identity is permanently shredded.
  - All raw image bursts in the encrypted research bucket are cryptographically erased.
  - Opaque similarity scores in historical benchmark runs are retained in anonymized, aggregated statistical form only.

---

## 3. RETENTION AND SECURE DESTRUCTION SCHEDULE

| Data Asset | Storage Location | Encryption | Retention Limit | Destruction Method |
|---|---|---|---|---|
| **Raw Capture Bursts** | Isolated research bucket | AES-256-GCM | 90 days post-submission | Cryptographic erasure |
| **Participant Linkage Ledger** | Offline air-gapped volume | AES-256 (KMS wrapped) | 30 days post-submission | Physical overwrite |
| **Evaluation Metrics / Manifests** | Git repository (`docs/`) | Plaintext JSON / MD | Project archive | Indefinite (Zero PII) |
| **Model Weight Artifacts** | `backend/models/` | Immutable ONNX | Baseline preservation | Indefinite |
