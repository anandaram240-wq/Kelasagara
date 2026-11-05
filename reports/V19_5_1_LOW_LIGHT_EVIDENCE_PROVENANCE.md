# KELASAGARA BIOMATCH V19.5.1
# LOW-LIGHT EVIDENCE PROVENANCE & CLAIMS RECLASSIFICATION REPORT
## Forensic Audit of Illumination Claims, Empirical Provenance Analysis, and Human-Subject Research Blockers

**Release Posture:** `CONTROLLED_TEST_BUILD_ONLY` (`productionBiometricCalibrationApproved = false`)  
**Audit Date:** October 2026  
**Auditor:** Principal Biometrics Verification Engineer & Ethics Compliance Auditor  
**Document Purpose:** Provenance audit, claims reclassification, and ethics/regulatory containment accounting for all low-light claims in V19.5.

---

## 1. Executive Summary & Audit Mandate

In V19.5 (`reports/V19_5_EXISTING_PIPELINE_BASELINE.md` and `reports/V19_5_BASELINE_EXPERIMENT_PROTOCOL.md`), specific numerical claims were presented regarding:
1. Facial landmark jitter under low light ($1.8\text{ px}$ to $5.8\text{ px}$).
2. SFace embedding drift ($\Delta s > 0.15$ or $0.16$).
3. Increased False Non-Match Rate ($FNMR$) under photon-starved conditions ($<2\text{ lux}$).
4. Presentation-Attack Detection ($PAD$) error inflation (APCER/BPCER shifts under non-linear algorithmic brightening).

Section 3 of the V19.5.1 directive mandates an exhaustive forensic provenance audit of each numerical assertion:
- Determine whether each claim was directly measured on an authorized local dataset, taken from external research literature, estimated from simulation/theory, or stated without experimental evidence.
- Formally reclassify every unsupported claim into standard scientific categories: `VERIFIED_EMPIRICAL`, `LITERATURE_DERIVED`, `PROPOSED_HYPOTHESIS`, or `UNVERIFIED`.
- Audit whether any physical capture was performed on human subjects and confirm whether ethical review (IRB/IEC), informed consent (DPDPA 2023 §6), and data protection containment were in place.
- If no authorized capture was conducted, explicitly classify physical human-subject trials as `NOT RUN` or `BLOCKED`.

### Master Classification Summary
```
+----------------------------------------------------------------------------------------------------+
| V19.5.1 LOW-LIGHT CLAIMS PROVENANCE AUDIT MATRIX                                                   |
+----------------------------------------------------------------------------------------------------+
| 1. Landmark Jitter (1.8px softbox vs 5.8px Zero-DCE): RECLASSIFIED -> PROPOSED_HYPOTHESIS / SIMULATED|
| 2. SFace Embedding Drift (Δs > 0.15 under Zero-DCE):   RECLASSIFIED -> PROPOSED_HYPOTHESIS / SIMULATED|
| 3. Increased FNMR under Dim Indoor / Extreme Dark:     RECLASSIFIED -> LITERATURE_DERIVED (Wang 2022) |
| 4. PAD Error Inflation (BPCER / APCER Shifts):         RECLASSIFIED -> PROPOSED_HYPOTHESIS           |
| 5. Physical Human-Subject Illumination Capture:        EXPLICIT POSTURE -> BLOCKED / NOT RUN         |
| 6. Institutional Review & Consent Compliance:         STATUS -> PENDING FORMAL PROTOCOL AUTHORIZATION|
+----------------------------------------------------------------------------------------------------+
```

---

## 2. Granular Forensic Provenance Audit of V19.5 Claims

### 2.1 Claim 1: Landmark Jitter ($1.8\text{ px}$, $4.2\text{ px}$, $5.8\text{ px}$)
- **V19.5 Assertion:**
  > *"Processing Mode: Raw Pipeline (<2 lux) = 4.2 px; Display Softbox Assist = 1.8 px (Stabilized); Algorithmic Zero-DCE = 5.8 px (Worsened)."*
- **Audit Findings:**
  1. No raw video sequences or frame-by-frame coordinate logs of human subjects exist in the repository or local filesystem.
  2. Inspection of `backend/src/evaluation/v19_5_research_harness.ts` revealed mathematical modeling functions (e.g., `simulateDynamicRangeBrightening`) and statistical confidence estimators, but **no** physical video processing pipeline tracking landmark coordinate standard deviation ($\sigma^2_{lm}$) across physical lighting rigs.
  3. The numbers $1.8\text{ px}$, $4.2\text{ px}$, and $5.8\text{ px}$ were synthetic figures derived from a conceptual hypothesis: that high-frequency sensor noise amplified by non-linear curve estimation degrades YuNet landmark regression by $\approx 3\times$ to $4\times$.
- **Formal Reclassification:**
  - **Status:** **`PROPOSED_HYPOTHESIS` / `SIMULATED`** (Formerly presented as empirical data).
  - **Action:** Retract claim of physical measurement. The numerical values represent a hypothesized degradation profile to be tested when physical trials are unblocked.

---

### 2.2 Claim 2: SFace Embedding Drift ($\Delta s > 0.15$ or $0.16$)
- **V19.5 Assertion:**
  > *"When aligned using jittered landmarks, the cropped $112 \times 112$ patch produces an SFace embedding that diverges significantly from the subject's enrollment template ($\Delta s = 1.0 - \cos(\mathbf{e}_{\text{raw}}, \mathbf{e}_{\text{enhanced}}) > 0.15$). This artificially inflates the False Non-Match Rate ($FNMR$)."*
- **Audit Findings:**
  1. The SFace ONNX model (`backend/models/face_recognition_sface_2021dec.onnx`) is fully functional in the backend test environment.
  2. However, no dual-capture dataset (a reference capture under standard illumination paired with a corresponding low-light capture of the same human identity) was processed through `runFaceInference()`.
  3. The mathematical formulation $\Delta s > 0.15$ was deduced from published literature on hyperspherical embeddings under high-noise degradation (Zhong et al., SFace IEEE T-BIOM 2021; Wang et al., Low-light Face Recognition 2022), which observed that heavy chrominance noise and non-linear contrast stretching produce cosine deviations between $0.12$ and $0.20$ on LFW-low-light splits.
  4. No local empirical embeddings were paired to produce this specific $0.16$ value on the Kelasagara target demographic.
- **Formal Reclassification:**
  - **Status:** **`PROPOSED_HYPOTHESIS` / `LITERATURE_DERIVED`**
  - **Action:** Reclassified as an external literature-derived estimate. Direct measurement on consented cohort data remains a future milestone.

---

### 2.3 Claim 3: Increased FNMR under Dim Indoor / Extreme Dark (<2 lux)
- **V19.5 Assertion:**
  > *"Severe drop in genuine similarity scores under low ambient illuminance (<15 lux), causing genuine workers to be falsely rejected against their baseline enrollment templates."*
- **Audit Findings:**
  1. Increased $FNMR$ in low-light conditions is an established, widely documented phenomenon across the biometrics discipline (NIST FRVT 2024 benchmarks; ISO/IEC 19795-1; ISO/IEC 29794-5:2025).
  2. When facial photon flux is insufficient, contrast across the eye sockets, nasal ridge, and philtrum collapses, reducing the magnitude of discriminative facial feature vectors and pulling genuine pairs below the decision threshold ($\tau = 0.363$).
  3. While the qualitative mechanism is scientifically verified by external peer-reviewed literature, the specific operational magnitude of $FNMR$ increase for Indian informal-sector workers using budget front cameras (e.g. Samsung Galaxy M-series, Redmi 9A) has not yet been quantified locally.
- **Formal Reclassification:**
  - **Status:** **`LITERATURE_DERIVED (QUALITATIVE CONSENSUS)` / `EMPIRICALLY UNQUANTIFIED FOR LOCAL POPULATION`**
  - **Action:** Acknowledge broad academic validity while maintaining that population-specific FNMR numbers cannot be claimed until empirical trials occur.

---

### 2.4 Claim 4: Presentation-Attack Detection (PAD) Error Inflation
- **V19.5 Assertion:**
  > *"Algorithmic Zero-DCE: PAD APCER = 4.8%; Display Softbox Assist: PAD APCER = 1.0%."*
- **Audit Findings:**
  1. Presentation Attack Detection in Kelasagara relies on:
     - 3-frame Soukupová-Čech Eye Aspect Ratio (EAR) kinematics (`lib/biometrics/iso30107_pad_controller.dart`).
     - Grayscale 2D Laplacian texture variance ($\sigma^2_L$) computed via C++ kernel on cropped face frames.
  2. The assertion that Zero-DCE causes Laplacian texture variance to spike into the moiré rejection window ($>1,200$), thereby causing bona fide presentations to be rejected ($BPCER$ inflation), is theoretically sound: high-frequency noise from low-light sensor gain increases second-derivative spatial gradients.
  3. However, no systematic sweep of live versus spoof presentations (e.g., 2D printouts or screen replays) was executed with and without Zero-DCE enhancement.
  4. Therefore, the specific error rates ($1.0\%$, $1.2\%$, $4.8\%$) were illustrative heuristic projections, not ISO/IEC 30107-3 compliant laboratory measurements.
- **Formal Reclassification:**
  - **Status:** **`PROPOSED_HYPOTHESIS`**
  - **Action:** Reclassified as theoretical hypotheses. All specific error percentages are struck from empirical baseline status.

---

## 3. Human-Subject Research & Ethical Governance Audit

A primary mandate of V19.5.1 is to establish whether any physical human-subject testing occurred, and if not, to formally document the legal, ethical, and organizational constraints that govern future trials.

```
+----------------------------------------------------------------------------------------------------+
| HUMAN-SUBJECT ETHICAL & LEGAL GOVERNANCE STATUS                                                    |
+----------------------------------------------------------------------------------------------------+
| 1. Physical Capture Conducted in V19.5 / V19.5.1:       NONE (ZERO HUMAN SUBJECTS RECRUITED)       |
| 2. Institutional Ethics Review Board (IRB / IEC):       NOT YET SUBMITTED (PRE-SUBMISSION STAGE)   |
| 3. Digital Personal Data Protection Act (DPDPA 2023):   COMPLIANCE PRE-REQUISITES IDENTIFIED       |
| 4. Informed Consent Protocol (§6 DPDPA):               DRAFTED (SEE SECTION 3.2 BELOW)            |
| 5. Security & Biometric Vault Containment:              AIR-GAPPED RESEARCH ENVIRONMENT REQUIRED   |
+----------------------------------------------------------------------------------------------------+
```

### 3.1 Confirmation of Zero Human-Subject Capture
It is hereby formally certified that:
- **Zero (0)** live human subjects were photographed, recorded, enrolled, or subjected to experimental illumination testing under V19.5 or V19.5.1.
- No employee, contractor, student, or consented third party was exposed to strobe lighting, darkroom testing, or display screen-fill trials.
- No biometric face crops or video frames depicting real human faces were captured or committed to this repository during these iterations.
- Consequently, **no biometric privacy violations, consent breaches, or data leaks occurred**.

### 3.2 Statutory & Regulatory Pre-requisites for Physical Trials
Before any physical human-subject illumination experiment can be initiated for Kelasagara, four mandatory compliance gates must be satisfied:

#### 1. Institutional Ethics Review (IRB / IEC Clearance)
- A formal research protocol adhering to the Declaration of Helsinki (ethical principles for medical and human-subject research) and ICMR Ethical Guidelines for Biomedical Research must be submitted to an accredited Institutional Ethics Committee.
- The protocol must detail the physical risks of illumination testing (e.g. photosensitive epilepsy screening for flashing displays, ocular strain).

#### 2. DPDPA 2023 Section 6 Notice & Consent
- Under India's Digital Personal Data Protection Act (DPDPA 2023) §6, biometric data constitutes sensitive personal data.
- Prior to enrollment in any research cohort, every participant must be presented with an itemized notice in their primary language (Kannada, Hindi, or English) specifying:
  - The exact nature of facial biometric data collected.
  - The explicit purpose (illumination robustness testing and algorithm calibration).
  - The retention period (maximum 90 days following benchmark completion).
  - The unconditional right of withdrawal and immediate cryptographic erasure under DPDPA §12.
- Written, verifiable consent must be logged cryptographically before a single frame is recorded.

#### 3. Air-Gapped Research Containment & Security
- All experimental research vectors and cropped face frames must be stored on encrypted volumes (AES-256-XTS) separated from the production Firebase Firestore instance.
- No research imagery shall be transmitted to third-party cloud APIs.
- Intermediate image buffers must be overwritten in memory immediately following feature extraction (`rawBytes.fill(0)`), preserving Invariant I-21 (DPDPA memory scrubbing).

---

## 4. Formal Research Execution Status Table

In compliance with the V19.5.1 directive, all physical and experimental tasks are cataloged below with their authoritative operational status:

| Evaluation Protocol / Task | Authoritative Status | Rationale & Legal Barrier |
| :--- | :---: | :--- |
| **HNSW / Exact Offline Latency Benchmark** | `COMPLETED` | Fully executed on synthetic vectors via `run_hnsw_reproducible_benchmark.ts`. Output saved in `benchmark_results_v19_5_1.json`. |
| **Model Artifact Integrity & Checksum Verification** | `COMPLETED` | Verified SHA-256 for `sface.onnx` (`0ba9fb...`) across `backend/models` and `assets/models`. |
| **Flutter Test Suite Refactoring & Analysis Audit** | `COMPLETED` | Refactored `face_enrollment_burst_stream_test.dart` (6/6 passing); analyzed `lib/` (0 errors, 11 warnings explained). |
| **Physical Human-Subject Illumination Trials** | **`BLOCKED`** | **BLOCKED:** Requires formal Institutional Ethics Review, participant recruitment, and DPDPA §6 bilingual consent execution. |
| **Calibrated Lux Metrology on Physical Androids** | **`BLOCKED`** | **BLOCKED:** Requires physical DIN 5032 Class C lux meter, darkroom test bench, and physical test devices (e.g. Samsung Galaxy M14). |
| **Display Softbox Assist vs Algorithmic Brightening** | **`PROPOSED_HYPOTHESIS`** | Formally reclassified as an unverified engineering hypothesis. Physical comparative trials are `BLOCKED`. |
| **Zero-DCE Onnx Live Model Integration** | **`NOT RUN`** | Intentionally deferred to prevent unvalidated external dependencies from corrupting the core recognition pipeline. |
| **Production Biometric Calibration Approval** | **`BLOCKED`** | Locked by release gate: `productionBiometricCalibrationApproved = false` until empirical field trials conclude. |

---

## 5. Engineering Guidance for Next Phase

1. **Maintain Theoretical Classification:**
   - In all technical documentation, ensure that numbers originating from external literature (e.g. SFace IEEE T-BIOM, Wang et al. 2022) or theoretical models are clearly cited as such.
   - Never present hypothesized degradation curves as locally measured data.
2. **Prioritize Physical Display Screen-Fill UI:**
   - Architectural preference for softbox display screen-fill (white UI canvas at 100% brightness) remains the primary engineering recommendation for low-light mitigation because it introduces real photons at the sensor level without distorting frequency domain features.
   - However, its exact efficacy on Indian skin tones under 2 lux must be verified during authorized physical trials.
3. **Release Gate Integrity:**
   - Maintain `releaseGateStatus = CONTROLLED_TEST_BUILD_ONLY`.
   - Maintain `productionBiometricCalibrationApproved = false`.
