# KELASAGARA BIOMATCH · STAGE S7 BIOMETRIC INCIDENT RESPONSE PLAN (S7_INCIDENT_RESPONSE_PLAN.md)

**Classification:** Security Incident Response, Containment Protocols & CERT-In / DPDPA Breach Handling  
**Stage:** S7  
**Date:** 2026-10-11  

---

## 1. Incident Severity Classification

| Severity Level | Triggering Event | Containment Action | Notification Window |
| :--- | :--- | :--- | :---: |
| **SEV-1 (Critical)** | Suspected disclosure of master encryption key or encrypted template vault | Trigger global biometric kill switch (<60s); rotate all KMS keys; initiate Document KYC cutover | Statutory 6-hour CERT-In notification; Data Protection Board of India notification |
| **SEV-2 (High)** | Sustained 1:N duplicate detection anomaly or sudden FNMR spike (>10%) | Pause automated candidate matching; route all applicants to manual review queue | 24-hour internal escalation; pilot suspension review |
| **SEV-3 (Medium)**| Capture session nonce collision or replay attempt surge | Flush IP rate limiters; update challenge entropy seed; inspect bot traffic | 48-hour engineering remediation |

---

## 2. Containment and Key Rotation Runbook

### Step 1: Immediate Triage & Kill Switch
1. Invoke global kill switch via Remote Config: `biometrics_enabled = false`.
2. Confirm propagation across server instances within 60 seconds.
3. Validate that client traffic routes 100% to Document/OTP KYC without dropping worker requests.

### Step 2: Master Key Compromise & Sovereign Re-Encryption
1. Generate new master secret: `MASTER_KEY_SECRET_V2`.
2. Deploy new key version reference: `keyVersion = "k2"`.
3. Background re-encryption worker decrypts existing envelopes under `k1` and writes fresh envelopes under `k2` with updated salt and AAD.
4. Once migration completes, permanently destroy `MASTER_KEY_SECRET_V1`.

---

## 3. Exit Gate S7-G11 Sign-Off

**Status:** `DONE-VERIFIED`  
**Artifact:** `S7_INCIDENT_RESPONSE_PLAN.md`  
**Summary:** Tested incident response runbook, containment SLAs, and statutory breach reporting protocols established.
