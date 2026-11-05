# KELASAGARA BIOMATCH · SPEC-DRIFT WATCH REPORT (DRIFT_REPORT.md)
**Audit Date:** 2026-10-10
**Corpus Definition SHA-256:** `a7a4c18ea327a13fec07aaa1a466299859a1a9026f7c97c6618a0fb5e9c55647`
**Total Standards Audited:** 7

## 1. Regulatory & Standards Alignment Matrix

| Standard ID | Title & Edition | Key Cited Requirement | Kelasagara Repository Status | Drift Action |
| :--- | :--- | :--- | :--- | :---: |
| **ISO-19794-5** | ISO/IEC 19794-5:2011 / ISO/IEC 29794-5:2024 (Biometric data interchange formats - Face) | Frontal face capture, inter-pupillary distance >= 60px, pose deviation <= 15 deg | COMPLIANT (Quality gate checks IPD and yaw/pitch) | ALIGNED |
| **ISO-30107-3** | ISO/IEC 30107-3:2023 (Presentation attack detection - Testing and reporting) | APCER / BPCER reporting, Level 1 & Level 2 2D print/replay attack types | COMPLIANT (PAD evaluator logs APCER/BPCER) | ALIGNED |
| **ISO-24745** | ISO/IEC 24745:2022 (Biometric information protection) | Irreversibility, Unlinkability, Renewability of biometric templates | RESTATED (S3 claimed keyed rotation achieves 24745; S6 attack T-02/T-03 refutes cryptographic security) | DRIFT NOTED (Restated) |
| **ISO-30136** | ISO/IEC 30136:2018 (Performance testing of biometric template protection schemes) | Mated vs non-mated distance distributions, Gomez-Barrero D_lr unlinkability metric | APPLIED (Implemented in Track T unlinkability evaluation) | ALIGNED |
| **UIDAI-FACE-RD-2.0** | UIDAI Face RD Service Specification v2.1 | PID block encryption using UIDAI public certificate, signed device info, PID XML schema | MAPPED (Contract stubbed; production requires STQC certification) | ALIGNED |
| **STQC-BDCS** | STQC Biometric Device Certification Scheme for Face RD | Hardware security environment, key storage in TEE/SE, anti-spoofing certification | NOT CERTIFIED (Documented as gap in Scorecard B) | ALIGNED |
| **DPDPA-2023** | Digital Personal Data Protection Act, 2023 (India) | Section 4-9 (Notice, Consent, Purpose Limitation), Section 12 (Erasure), Section 15 (Fiduciary obligations) | COMPLIANT (Zero raw image retention, envelope crypto-shredding, purpose-limited embeddings) | ALIGNED |

## 2. Critical Standard Drift Notes

1. **ISO/IEC 24745 (Template Protection):**
   - S3 classified keyed orthogonal rotation $R \in O(d)$ as providing ISO/IEC 24745 'irreversibility and unlinkability'.
   - Under rigorous cryptographic review in S6 Track T, this is **RESTATED**: an orthogonal rotation preserves inner products and distance metrics exactly, leaving templates susceptible to Known-Plaintext Attack (KPA) and cross-tenant linkability.
   - The true protection mechanism in production is envelope encryption with AES-256-GCM and individual per-user ephemeral data keys, not the geometric rotation.

2. **ISO/IEC 29794-5 (Quality Interchange):**
   - Transition from 19794-5 to 29794-5:2024 is ongoing across international standards bodies.
   - Quality gates in `biometric_quality_assessment.ts` adhere to 60px inter-pupillary distance, which remains stable across both editions.

3. **DPDP Act 2023 (India):**
   - Section 6 notice requirements require unambiguous bilingual (Kannada + English) opt-in consent before capturing facial biometric data.
   - Section 12 right to erasure requires immediate crypto-shredding of individual data encryption keys.
