# KELASAGARA BIOMATCH · STAGE S7 REMAINING WORK & ROADMAP (S7_REMAINING_WORK.md)

**Classification:** Outstanding Work Items, External Blockers & Production Cutover Roadmap  
**Stage:** S7  
**Date:** 2026-10-11  

---

## 1. Actionable Next Engineering Steps (In-Repo)

| Work Item ID | Discipline | Description | Effort | Prerequisite |
| :--- | :--- | :--- | :---: | :--- |
| **ENG-01** | Mobile Client | Integrate Google Play Integrity API in Flutter client (`lib/services/biometric_service.dart`) to acquire hardware-backed device attestation tokens before capture requests. | 3-4 days | Google Cloud Console project link |
| **ENG-02** | Backend / DevOps | Provision Cloud KMS service account and integrate remote KMS key encryption for `MASTER_KEY_SECRET` in `backend/src/services/template_privacy.ts`. | 2-3 days | GCP KMS KeyRing provisioning |
| **ENG-03** | Automated Testing | Add end-to-end integration test simulating multi-tenant enrollment and cross-tenant decryption rejection using live emulators. | 1 day | None |

---

## 2. External Blockers Requiring Human Action

| Human Action ID | Target Deliverable | Responsible Party | Estimated Lead Time | Releases Blocked |
| :--- | :--- | :--- | :---: | :---: |
| **H-01** | Institutional Ethics Review sign-off (`ETHICS_APPROVAL_ID`) | Legal & Ethics Officer / University IRB | 4–6 weeks | Unlocks H-02, Scorecard A > 40%, and Stage S-2 |
| **H-02** | Consented Karnataka blue-collar field cohort collection ($N \ge 200$) across Fitzpatrick IV–VI | Field Operations Lead / Community Partners | 3–4 weeks | Unlocks field benchmark and Stage S-2 |
| **H-03** | Third-party red-team presentation attack penetration test | External Certified Security Lab | 2–3 weeks | Unlocks Stage S-1 full scale |
| **H-04** | Peer review sign-off of frozen statistical engine and protocol | Independent Academic Biometrician | 2 weeks | Unlocks Stage S-2 certification |

---

## 3. Summary Assessment

The local software engineering and cryptographic architecture are production-grade and ready for **Stage S-0 (Shadow Mode)** and **Stage S-1 (Opt-In Limited Pilot)**. Full consequential enforcement (**Stage S-2**) is strictly blocked pending human actions H-01 and H-02.
