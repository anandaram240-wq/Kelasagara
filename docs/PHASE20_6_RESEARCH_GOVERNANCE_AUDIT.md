# PHASE 20.6 RESEARCH GOVERNANCE AUDIT
## Ethical Research Framework, Participant Data Rights, and Secure Biometric Information Management

**Project:** Kelasagara Major Project  
**System:** Worker Marketplace & Biometric Identity Platform  
**Phase:** 20.6 (Biometric Evidence Integrity & Controlled Pilot Readiness)  
**Governance Framework:** DPDPA 2023, GDPR Article 9 & University Research Ethics Protocols  
**Lead Auditor:** Privacy and Security Architect & Biometric Dataset Governance Specialist  
**Date:** 2026-10-31  

---

## 1. ETHICAL AND REGULATORY BASELINE

Biometric data (facial images and high-dimensional neural embeddings) constitutes sensitive personal data under India's Digital Personal Data Protection Act (DPDPA 2023) and special category personal data under GDPR Article 9.

This audit evaluates the ten mandatory research governance controls in the Kelasagara platform:

---

## 2. AUDIT OF THE TEN MANDATORY GOVERNANCE CONTROLS

```
┌───────────────────────────────────────────────────────────────────────────────────────────────┐
│                             RESEARCH GOVERNANCE COMPLIANCE MATRIX                             │
├───────────────────────────────────┬──────────────┬────────────────────────────────────────────┤
│ Governance Control Requirement    │ Status       │ Audit Evidence & Enforced Policy           │
├───────────────────────────────────┼──────────────┼────────────────────────────────────────────┤
│ 1. Voluntary Informed Consent     │ VERIFIED     │ Written consent required prior to capture  │
│ 2. Institutional Ethics Approval  │ PROVISIONAL  │ University IRB submission package prepared │
│ 3. Participant Withdrawal Workflow│ VERIFIED     │ One-click cryptographic erasure hook       │
│ 4. Data Retention Schedule        │ VERIFIED     │ Mandatory 90-day retention purge watermark │
│ 5. Secure Offline Storage         │ VERIFIED     │ AES-256 encrypted local volume only        │
│ 6. Role-Based Access Restriction  │ VERIFIED     │ Principal Investigator authorization only  │
│ 7. Evaluation Audit Trail         │ VERIFIED     │ Append-only cryptographic execution log    │
│ 8. Secure Deletion Procedure      │ VERIFIED     │ Crypto-shredding (key destruction)         │
│ 9. Dataset Backup Policy          │ VERIFIED     │ Air-gapped cold storage (zero cloud backup)│
│ 10. Research Reporting Policy     │ VERIFIED     │ Zero PII, k-anonymity aggregation only     │
└───────────────────────────────────┴──────────────┴────────────────────────────────────────────┘
```

---

## 3. CORE GOVERNANCE RULES & DATA BOUNDARIES

### A. Zero Raw Biometric Data in Source Control
- **Strict Rule:** Raw facial images (`.jpg`, `.png`, `.bmp`) and unencrypted floating-point embedding arrays are permanently excluded from Git tracking via `.gitignore`:
  ```gitignore
  # Biometric Research & Raw Imagery Isolation
  /data/biometric-research/
  *.raw_frame
  *.face_crop
  consent_ledger.db*
  ```
- **Audit Verification:** Git history inspection confirms **zero** raw facial images or unencrypted biometric vectors have ever been committed.

### B. Prohibition on Third-Party AI Data Transmission
- In accordance with privacy principles, biometric facial crops and embeddings **must never** be transmitted to commercial third-party LLMs (e.g. OpenAI, Anthropic, or external Gemini endpoints) or cloud vision APIs.
- All detection (YuNet), alignment (Umeyama), and recognition (SFace) processing runs exclusively inside the local, self-hosted Node.js / C++ runtime.

### C. Isolation of Production Worker Records
- Production worker identity records and biometric templates stored in Firestore (`biometric_vault_v3`) are **strictly prohibited** from being extracted or re-used as research evaluation datasets.
- Research studies must rely exclusively on consented research cohorts who have signed dedicated academic research consent forms.

### D. Participant Withdrawal Protocol
If a participant withdraws consent:
1. The participant provides their opaque assigned ID (`SUBJ-X-YY`).
2. The Principal Investigator invokes `revokeResearchParticipantConsent(pId)`.
3. The system executes cryptographic shredding: destroying the ephemeral encryption key binding that participant's samples, rendering raw byte streams permanently unrecoverable.
4. The participant's record is marked `WITHDRAWN_PURGED` in the offline consent ledger.
