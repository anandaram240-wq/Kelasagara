# KELASAGARA BIOMATCH
# STAGE S8: REMAINING WORK & PRE-DEPLOYMENT PREREQUISITES

**Document ID:** `KB-ROADMAP-S8-09`  
**Classification:** Post-S8 Engineering Roadmap & Release Prerequisites  
**Target Release Stage:** Stage S9 (Pre-Production Cloud Staging)  
**Effective Date:** 11 October 2026  

---

## 1. Overview

While Stage S8 has successfully achieved 100% test verification across cryptographic hardening, canonical AAD encoding, Play Integrity binding, and cross-tenant isolation, public production deployment is intentionally held under an **Engineering Recommendation of NO-GO** until external cloud, legal, and operational prerequisites are completed.

This document outlines the actionable roadmap required to achieve unrestricted production release.

---

## 2. Actionable Engineering & Infrastructure Checklist

### 2.1 Google Cloud KMS Provisioning (Priority: P0)
- [ ] Create Google Cloud KMS KeyRing in region `asia-south1` (Mumbai):
  ```bash
  gcloud kms keyrings create biomatch-vault-ring \
    --location asia-south1 \
    --project kelasagara-prod
  ```
- [ ] Create Hardware Security Module (HSM) backed Master KEK:
  ```bash
  gcloud kms keys create biomatch-master-kek \
    --location asia-south1 \
    --keyring biomatch-vault-ring \
    --purpose encryption \
    --protection-level hsm
  ```
- [ ] Configure Workload Identity Federation for GKE/Cloud Run backend service account with `roles/cloudkms.cryptoKeyEncrypterDecrypter`.
- [ ] Execute `TemplateMigrationService.migrateRecord` in dry-run mode against staging Firestore to verify live Cloud KMS unwrap latency.

### 2.2 Google Play Console Integrity Setup (Priority: P0)
- [ ] Enable Play Integrity API in Google Cloud Project `kelasagara-prod`.
- [ ] Link Google Play Console app application ID (`com.kelasagara.app`) to Google Cloud Project.
- [ ] Generate and bind Google Service Account key with `roles/playintegrity.viewer` to backend environment variable `PLAY_INTEGRITY_SERVICE_ACCOUNT_KEY`.
- [ ] Conduct live device integrity test on genuine Android devices (Samsung Galaxy, Redmi, Realme) to verify CTS-certified token decoding.

### 2.3 Empirical In-Domain Demographic Calibration (Priority: P1)
- [ ] Acquire IRB / Independent Ethics Committee protocol approval for voluntary biometric calibration research in Karnataka.
- [ ] Collect synthetic or consenting pilot participant captures across Fitzpatrick skin types IV, V, and VI under variable sunlight and outdoor labor conditions.
- [ ] Re-calculate empirical ROC curves, False Non-Match Rate (FNMR), and False Match Rate (FMR) to calibrate the production operational threshold ($\theta$) from pilot shadow floor (0.60) to production target ($\theta \approx 0.72$).

### 2.4 DPDPA 2023 Legal & Compliance Filing (Priority: P0)
- [ ] Publish multilingual Data Privacy Notice (Kannada and English) complying with Section 6 of the Digital Personal Data Protection Act, 2023.
- [ ] Validate Data Protection Impact Assessment (DPIA) covering biometric template crypto-shredding (DPDPA Section 12).
- [ ] Obtain formal countersignatures from DPO and Legal Counsel on `S8_RELEASE_GATES.md`.

### 2.5 Physical Presentation Attack Red-Teaming (Priority: P1)
- [ ] Commission independent hardware red-team assessment testing presentation attack resistance against:
  - High-resolution matte photo printouts.
  - 4K OLED mobile screen video replays.
  - 3D silicone portrait masks.
- [ ] Measure Presentation Attack Correct Classification Rate (PACCR) against ISO/IEC 30107-3 benchmarks.

### 2.6 Operational Support & Manual Review Workflow (Priority: P1)
- [ ] Deploy the Administrative KYC Review Dashboard for processing profiles routed to `pending_review` under Invariant I-14 (Non-Punitive Escalation).
- [ ] Train compliance review staff on Document KYC verification (Aadhaar Offline QR / Voter ID) for workers on uncertified devices.
