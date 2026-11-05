# KELASAGARA BIOMATCH · ETHICS & HARM REGISTER (HARM_REGISTER.md)
**Audit Date:** 2026-10-10  
**Status:** COMPLETE (Track E Closure)  
**Governing Rule:** DPDPA 2023 & Gate GATE-S6-11  

---

## 1. Catalog of Biometric Harms & Protections

| ID | Harm Name | Stakeholder | Severity | Probability | Key Mitigation & Safeguard | Residual Risk |
| :---: | :--- | :--- | :---: | :---: | :--- | :---: |
| **H-01** | Wrongful Worker Lockout | Worker | HIGH | LOW | 100% Document KYC Fallback; zero automated rejection | CONTROLLED |
| **H-02** | Lost Daily Wages from Delayed Verification | Worker | HIGH | LOW | Target resolution < 15 minutes via priority phone callback | CONTROLLED |
| **H-03** | Demographic Bias on Darker Skin Tones (Fitzpatrick VI) | Worker | HIGH | LOW | Calibrated thresholds; disparity ratio monitored <= 2.0x | CONTROLLED |
| **H-04** | Harsh Outdoor Glare / Shadow Acquisition Failure | Worker | MEDIUM | MEDIUM | Real-time UI Kannada lighting prompts | CONTROLLED |
| **H-05** | Presentation Attack / Photo Spoofing of Legitimate Worker | Worker | HIGH | LOW | Server-side landmark optical flow + passive challenge-response | CONTROLLED |
| **H-06** | Virtual Camera Injection Bypass | Worker | CRITICAL | LOW | Cryptographic nonce binding + hardware attestation | CONTROLLED |
| **H-07** | Biometric Template Database Breach | Worker | CRITICAL | VERY_LOW | Per-user AES-256-GCM envelope encryption + KMS key wrapping | CONTROLLED |
| **H-08** | Unlawful Retention of Raw Facial Images | Worker | HIGH | ZERO | Invariant I-04 zero-retention; in-memory buffer zeroing | CONTROLLED |
| **H-09** | Coerced Enrollment by Exploitative Hirers | Worker | HIGH | LOW | Worker rights notices in Kannada; voluntary opt-in guarantee | CONTROLLED |
| **H-10** | Identity Theft via Stolen Phone / Session Hijack | Worker | HIGH | LOW | Step-up face auth on high-value bookings or device change | CONTROLLED |
| **H-11** | Corrupt Support Agent Overriding Duplicate Flags | Worker | HIGH | LOW | Dual-control manual override; 2-sigma anomaly monitor | CONTROLLED |
| **H-12** | Cross-Tenant Tracking of Enrolled Workers | Worker | HIGH | LOW | Tenant isolation; unique per-tenant AES-GCM data encryption keys | CONTROLLED |
| **H-13** | Network Outage at Rural Job Site Blocking Authentication | Worker | MEDIUM | MEDIUM | Fail-closed with cached offline Document KYC voucher | CONTROLLED |
| **H-14** | Inability to Delete Biometric Profile upon Resignation | Worker | HIGH | ZERO | Automated DPDPA crypto-shredding key destruction endpoint | CONTROLLED |

---

## 2. Institutional Ethics Committee Status (Ticket E-01)
- **Status:** `BLOCKED` (Formal review pending with institutional IRB).
- **Bilingual Consent Forms:** Prepared in `ETHICS_PACKAGE/` (Kannada and English).
- **Lead Time:** 4-6 weeks for committee review and issuance of `ETHICS_APPROVAL_ID`.
