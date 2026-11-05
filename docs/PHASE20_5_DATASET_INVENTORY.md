# PHASE 20.5 DATASET INVENTORY
## Inventory of Controlled Biometric Evaluation Datasets and Partitions

**Project:** Kelasagara Major Project  
**System:** Worker Marketplace & Multi-Factor Biometric Identity Platform  
**Phase:** 20.5 (Advanced Biometric Scientific Validation Engine)  
**Parent Phase 20.4 Commit:** `41f95bf66bd09cda8ea63d3483e567b06ba6504e`  

---

## 1. EVALUATION CORPUS OVERVIEW

The evaluation dataset consists of a controlled, privacy-preserving research cohort of 50 consenting adult volunteers contributing 450 multi-frame biometric capture bursts across 3 capture sessions and varying environmental conditions:

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                       DATASET PARTITION DISTRIBUTION                            │
├────────────────────┬───────────┬──────────────┬──────────────┬──────────────────┤
│ Partition Name     │ Subjects  │ Bursts/Subj  │ Total Samples│ Primary Purpose  │
├────────────────────┼───────────┼──────────────┼──────────────┼──────────────────┤
│ DEVELOPMENT_A      │ 10        │ 9 (3 sess x3)│ 90 samples   │ Pipeline check   │
│ CALIBRATION_B      │ 15        │ 9 (3 sess x3)│ 135 samples  │ Threshold search │
│ HOLDOUT_C          │ 25        │ 9 (3 sess x3)│ 225 samples  │ Blind holdout eval│
├────────────────────┼───────────┼──────────────┼──────────────┼──────────────────┤
│ TOTAL EVAL CORPUS  │ 50        │ 9            │ 450 samples  │ 100% Consented   │
└────────────────────┴───────────┴──────────────┴──────────────┴──────────────────┘
```

---

## 2. ENVIRONMENTAL & SENSOR DIVERSITY

### Illumination Environments
1. **INDOOR_UNIFORM**: Controlled office ceiling lighting (300-500 lux).
2. **OUTDOOR_DIRECT_SUN**: Natural direct midday daylight (> 10,000 lux).
3. **LOW_ILLUMINATION_NIGHT**: Dim evening / indoor ambient lighting (< 20 lux).
4. **BACKLIT_STRONG_WINDOW**: High dynamic range backlighting with facial silhouette challenge.
5. **DIFFUSE_FLUORESCENT**: Mixed commercial warehouse fluorescent illumination.

### Mobile Sensor Profiles
1. **ENTRY_720P_FIXED**: Low-end smartphone fixed-focus sensor (1280x720).
2. **MID_1080P_AUTOFOCUS**: Standard consumer Android mid-range front camera (1920x1080).
3. **FLAGSHIP_4K_SENSOR**: High-performance flagship smartphone sensor (3840x2160).

---

## 3. ZERO UNCONSENTED DATA PROVENANCE
- **No Aadhaar Images**: Zero government identity images utilized.
- **No Web-Scraped Photos**: Zero scraped social media images.
- **No Real Worker Production Data**: Zero live production database records used for evaluation.
- **Volunteer Consent**: Every participant signed a formal university biometric research consent form with assigned opaque identifier (`SUBJ-X-YY`).
