# PHASE 20.5 DEMOGRAPHIC EVALUATION
## Demographic Parity Evaluation Across Voluntary Self-Reported Cohorts

**Project:** Kelasagara Major Project  
**System:** Worker Marketplace & Multi-Factor Biometric Identity Platform  
**Phase:** 20.5 (Advanced Biometric Scientific Validation Engine)  
**Parent Phase 20.4 Commit:** `41f95bf66bd09cda8ea63d3483e567b06ba6504e`  

---

## 1. ETHICAL AND METHODOLOGICAL BOUNDARIES

In strict accordance with ISO/IEC 19795-10 and algorithmic fairness best practices:
1. **Zero Attribute Inference**: Demographic variables (sex, skin-tone scale, glasses wear) were collected solely via **voluntary self-reporting** by participants. The system NEVER predicts or infers gender, race, or ethnicity from facial embeddings.
2. **Uniform Operating Thresholds**: All demographic cohorts are evaluated against the exact same operating verification threshold ($\theta = 0.363$). Under no circumstances are separate thresholds deployed for different population groups.

---

## 2. SUBGROUP PERFORMANCE BREAKDOWN

Evaluated on the 50-participant evaluation corpus:

| Demographic Cohort | Genuine Trials | Impostor Trials | FMR @ 0.363 | 95% FMR CI | FNMR @ 0.363 | 95% FNMR CI |
|---|---|---|---|---|---|---|
| **Self-Reported Female** | 50 | 150 | 0.00% (0/150) | [0.000, 0.024] | 0.00% (0/50) | [0.000, 0.071] |
| **Self-Reported Male** | 50 | 150 | 0.00% (0/150) | [0.000, 0.024] | 0.00% (0/50) | [0.000, 0.071] |
| **Monk Scale 1-3 (Light)** | 32 | 96 | 0.00% (0/96)  | [0.000, 0.038] | 0.00% (0/32) | [0.000, 0.109] |
| **Monk Scale 4-6 (Medium)**| 36 | 108 | 0.00% (0/108) | [0.000, 0.034] | 0.00% (0/36) | [0.000, 0.097] |
| **Monk Scale 7-10 (Dark)** | 32 | 96 | 0.00% (0/96)  | [0.000, 0.038] | 0.00% (0/32) | [0.000, 0.109] |
| **Spectacles / Glasses Worn**| 30 | 90 | 0.00% (0/90)  | [0.000, 0.040] | 0.00% (0/30) | [0.000, 0.116] |
| **Head Covering / Turban** | 20 | 60 | 0.00% (0/60)  | [0.000, 0.060] | 0.00% (0/20) | [0.000, 0.168] |

---

## 3. STATISTICAL ADEQUACY LIMITATIONS

- **Sample Size Warning**: ISO/IEC 19795-10 recommends at least 500 comparison trials per demographic subgroup for statistically definitive parity claims. The current volunteer cohort ($N=50$) provides 150 trials per sex cohort.
- **Disparity Ratios**: Empirical FMR and FNMR disparity ratios are $1.00$ (zero observed errors across all groups).
- **Formal Declaration**: While empirical performance shows no disparate impact on this research cohort, the wide confidence intervals reflect the finite volunteer sample. Full demographic fairness across diverse Indian worker populations requires ongoing field monitoring during expanded canary deployment.
