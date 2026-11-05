# PHASE 20.6 FTA AND FTE REANALYSIS
## Decoupling Biometric Acquisition Failures, Enrollment Rejections, and Matching Errors

**Project:** Kelasagara Major Project  
**System:** Worker Marketplace & Biometric Identity Platform  
**Phase:** 20.6 (Biometric Evidence Integrity & Controlled Pilot Readiness)  
**Standard:** ISO/IEC 19795-1:2021 (§7 Failure to Enroll & Acquire) & ISO/IEC 29794-5  
**Lead Auditor:** Senior Computer Vision Engineer & Independent Quality Assurance Engineer  
**Date:** 2026-10-31  

---

## 1. FORMAL METRIC DEFINITIONS

To eliminate conflation between image capture quality rejections and biometric recognition failures, the following formal definitions govern the Kelasagara biometric pipeline:

### 1. Failure-to-Acquire Rate (FTA)
The proportion of verification or enrollment attempts for which the biometric capture device or quality pre-filtering fails to capture or locate an acceptable biometric sample:
$$\text{FTA} = \frac{\text{Failed Acquisition Attempts}}{\text{Total Acquisition Attempts}}$$
- **Triggers:**
  * No face detected by YuNet ($C < 0.60$).
  * Inter-pupillary distance (IPD) below threshold ($\text{IPD} < 75\text{ px}$).
  * Severe motion blur (Laplacian variance $\sigma^2 < 110.0$).
  * Extreme head pose ($|\text{yaw}| > 25^\circ$, $|\text{pitch}| > 25^\circ$, or $|\text{roll}| > 25^\circ$).
  * Mean ROI luminance out of bounds ($\mu < 35.0$ or $\mu > 220.0$).

### 2. Failure-to-Enroll Rate (FTE)
The proportion of eligible candidates for whom the system fails to successfully create and store a permanent biometric enrollment template:
$$\text{FTE} = \frac{\text{Unsuccessful Enrollment Candidates}}{\text{Total Eligible Enrollment Candidates}}$$
- **Enrollment Failure Criteria:**
  * Persistent FTA across all permitted capture retries (maximum 3 burst attempts).
  * Inability to locate stable facial landmarks for 5-point Umeyama canonical alignment.
  * Incompatible template generation error or cryptographically rejected key binding.

### 3. False Non-Match Rate (FNMR)
The proportion of genuine matching comparisons that erroneously fail to meet the similarity matching threshold:
$$\text{FNMR}(\theta) = \frac{|\{ (u, v) \in \mathcal{G} : \text{Sim}(u, v) < \theta \}|}{|\mathcal{G}|}$$
*Note: FNMR is evaluated ONLY on successfully acquired, high-quality biometric samples that have already passed FTA.*

### 4. Bona Fide Presentation Classification Error Rate (BPCER)
The proportion of bona fide (live) presentations falsely classified as presentation attacks (spoofs) by the PAD module:
$$\text{BPCER} = \frac{\text{Live Presentations Classified as Attacks}}{\text{Total Live Presentations}}$$

### 5. Technical Capture Failure (TCF)
Hardware, sensor, or network level aborts that prevent an acquisition attempt from completing:
* Camera hardware busy or disconnected.
* Camera permission revoked by Android OS.
* Video frame stream timeout (> 5,000 ms).
* Out of memory (OOM) during buffer decoding.

---

## 2. REANALYSIS OF REPORTED VALUES

| Metric | Phase 20.5 Reported Value | Phase 20.6 Recomputed Value | Formula / Basis | Status |
| :--- | :--- | :--- | :--- | :--- |
| **Total Capture Attempts** | 450 bursts | 450 | Total bursts submitted | `VERIFIED_FIXTURE` |
| **Failed Acquisitions** | 14 bursts | 14 bursts | Quality filter rejections | `VERIFIED_FIXTURE` |
| **Failure-to-Acquire (FTA)**| **3.11%** | **3.111%** | $14 / 450$ | `VERIFIED_FIXTURE` |
| **Enrollment Candidates** | 50 subjects | 50 subjects | Total candidate pool | `VERIFIED_FIXTURE` |
| **Failed Enrollments** | 0 subjects | 0 subjects | Permanent enrollment failures | `VERIFIED_FIXTURE` |
| **Failure-to-Enroll (FTE)** | **0.00%** | **0.000%** | $0 / 50$ | `VERIFIED_FIXTURE` |
| **Technical Capture Fail** | 0 events | 0 events | Hardware / OS faults | `VERIFIED_FIXTURE` |

---

## 3. DECOUPLING VERIFICATION LEDGER

The following flowchart illustrates the strict separation of rejection gates in `backend/src/biometric-evaluation/image_quality_evaluator.ts`:

```
                 Incoming Camera Burst
                           │
                           ▼
          [ Gate 1: Technical Capture (TCF) ] ──────► REJECT: TCF_ERROR
                           │ (Pass)
                           ▼
          [ Gate 2: Face Quality Assessment ] ──────► REJECT: FTA_POOR_QUALITY
              (IPD >= 75px, Blur, Luma)
                           │ (Pass)
                           ▼
          [ Gate 3: Liveness & PAD (BPCER) ]  ──────► REJECT: PAD_SPOOF_FLAG
              (EAR Blink, Sobel Texture)
                           │ (Pass)
                           ▼
          [ Gate 4: SFace 1:1 Match (FNMR) ]  ──────► REJECT: BIOMETRIC_MISMATCH
              (Sim >= 0.363 Floor)
                           │ (Pass)
                           ▼
                 SUCCESSFUL VERIFICATION
```

### Invariant Enforced:
An attempt rejected at Gate 2 incremented `FTA` only. It did **not** increment `FNMR` or `BPCER`. An attempt rejected at Gate 3 incremented `BPCER` only. This architectural decoupling preserves exact mathematical tracking for each independent error rate.
