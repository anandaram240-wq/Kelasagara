# KELASAGARA BIOMATCH: IN-DOMAIN DATA COLLECTION PROTOCOL (TICKET H-01)
**Document Version:** 1.0.0  
**Date:** 10 October 2026  
**System:** Kelasagara Sovereign Biometric Stack (`kelasagaara_v17`)  
**Compliance:** Digital Personal Data Protection Act 2023 (DPDPA 2023), Sovereign Alignment  
**Operational Status:** TOOLING COMPLETE / FIELD SCORING BLOCKED PENDING REAL CONSENTED COHORT

---

## 1. Statutory Mandate & DPDP Act 2023 Consent Architecture

Under Section 6 and Section 7 of the Digital Personal Data Protection Act (DPDPA) 2023, collection of biometric facial data requires specific, informed, unconditional, and revocable consent.

### 1.1 Informed Consent Requirements
Every data collection participant must be presented with a bilingual (Kannada and English) plain-language Notice stating:
1. **Specific Purpose:** Biometric evaluation, threshold calibration, and fairness auditing for the Karnataka blue-collar worker platform.
2. **Right to Withdraw:** The participant may withdraw consent at any time via an in-app button, SMS, or verbal request to the field enumerator.
3. **Data Erasure on Withdrawal:** Upon withdrawal, all derived biometric templates and index entries are immediately purged, and encryption keys crypto-shredded within 24 hours.
4. **No Raw Image Retention by Default:** Under Invariant I-04, raw images are transformed to 128-D embeddings in-memory and immediately discarded. Raw image retention is prohibited unless the participant provides separate, explicit consent for calibration storage.

---

## 2. Statistical Power Analysis & Cohort Sizing

To validate a False Match Rate target of $FMR = 10^{-4}$ with statistical power $1 - \beta \ge 0.90$ and observe $\ge 30$ genuine and impostor errors for narrow confidence intervals:
- **Minimum Subjects ($N$):** 200 distinct consented individuals.
- **Sessions per Subject:** At least 2 independent acquisition sessions conducted on different days (inter-session interval $\ge 48$ hours) to capture natural physiological and lighting variance.
- **Frames per Session:** 5 multi-sample frames (yaw diversity: center, left $-15^\circ$, right $+15^\circ$).
- **Total Comparisons Generated:**
  - Genuine comparisons: $200 \times 1 = 200$ cross-session genuine pairs.
  - Impostor comparisons: $\frac{200 \times 199}{2} = 19,900$ demographically matched and cross-matched impostor pairs.

---

## 3. Device Diversity & Environmental Stratification

To guarantee real-world field robustness on inexpensive consumer hardware:
1. **Target Hardware Stratification (Minimum 3 Devices):**
   - Device A (Low-End Entry Android): e.g. Redmi 9A / Realme C-series (MediaTek Helio, 5MP front camera, fixed focus).
   - Device B (Mid-Range Android): e.g. Samsung Galaxy M/F-series (Exynos, 13MP front camera).
   - Device C (Standard Android): e.g. Motorola G-series / OnePlus Nord CE.
2. **Environmental Lighting Conditions:**
   - Indoor ambient domestic lighting (100 - 300 lux).
   - Low-light outdoor dusk / early morning (30 - 80 lux).
   - High-contrast direct sun / backlight (with auto-exposure evaluation).
3. **Demographic Representation:**
   - 50% Male / 50% Female.
   - Age distribution: 40% (18-30), 40% (31-50), 20% (51+).
   - Skin tone distribution: Representative Karnataka spectrum (Fitzpatrick Type III, IV, and V).
   - Natural occupational factors: Direct inclusion of masonry dust, sun-tan, turbans, headscarves, and beards.

---

## 4. Ingestion Tool Architecture (`in_domain_ingest_tool.ts`)

The automated data ingest tool guarantees:
1. Validates digital consent token before processing any subject folder.
2. Applies ISO/IEC 29794-5 quality gates.
3. Computes 128-D SFace embedding using primary ONNX session.
4. Immediately wipes raw image buffers from memory (`buf.fill(0)`).
5. Emits sealed manifest record with SHA-256 hashes into `in_domain_manifest.jsonl`.
6. Enforces partition assignment: 40% TUNE, 40% VALIDATE, 20% LOCKBOX.
