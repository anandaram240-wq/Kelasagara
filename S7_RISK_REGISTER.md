# KELASAGARA BIOMATCH · STAGE S7 RISK REGISTER (S7_RISK_REGISTER.md)

**Classification:** Enterprise Risk Management & Residual Risk Catalog  
**Stage:** S7  
**Date:** 2026-10-11  

---

## 1. Residual Risk Matrix

| Risk ID | Risk Title | Likelihood | Impact | Inherent Severity | Residual Risk Score | Mitigating Safeguard | Owner |
| :--- | :--- | :---: | :---: | :---: | :---: | :--- | :--- |
| **RISK-01** | In-domain demographic accuracy gap for darker skin tones (Fitzpatrick IV–VI) | High | High | **CRITICAL** | **CONTROLLED (Pilot Capped)** | Score capped at 40.0%; S-2 locked; Document KYC fallback guaranteed | Chief Biometrics Architect |
| **RISK-02** | Sensor-level deepfake video injection on rooted Android devices | Medium | High | **HIGH** | **ACCEPTED FOR PILOT** | Allowed in S-1 with human review; Play Integrity hardware attestation required for S-2 | Mobile Security Lead |
| **RISK-03** | 1:N cumulative false positive candidate rate at scale ($G \ge 100\text{k}$) | High | Medium | **HIGH** | **NEGLIGIBLE FOR WORKERS** | **Invariant I-14:** Biometric duplicate hits NEVER auto-reject; routes to manual review | SRE & Operations Lead |
| **RISK-04** | Master KMS encryption key disclosure via host server memory breach | Low | Critical | **CRITICAL** | **LOW** | Host memory isolation; per-user salt derivation; tested kill switch and key rotation runbook | Chief Information Security Officer |
| **RISK-05** | Legal challenge under DPDP Act 2023 for biometric processing | Low | High | **HIGH** | **LOW** | Zero raw image storage; explicit bilingual consent; tested Right to Erasure crypto-shredding | Legal & Privacy Counsel |

---

## 2. Risk Acceptance and Pilot Authorization

The residual risks identified above are strictly acceptable for **Stage S-0 (Shadow Mode)** and **Stage S-1 (Opt-In Limited Pilot)** because:
1. No applicant can be denied marketplace access based on a biometric non-match or duplicate candidate.
2. 100% non-biometric Document KYC is operational.
3. Biometric auth can be taken offline within 18.5 seconds without dropping user traffic.
4. Stage S-2 consequential enforcement remains blocked until RISK-01 and RISK-02 are resolved.
