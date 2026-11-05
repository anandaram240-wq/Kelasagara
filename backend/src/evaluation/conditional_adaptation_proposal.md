# KELASAGARA BIOMATCH: CONDITIONAL ADAPTATION PROPOSAL (TICKET D-04)
**Status:** PROPOSAL ONLY (Zero Training Performed)  
**Date:** 10 October 2026  
**Governance:** Invariant I-01, I-02, Pre-Registration Gate GATE-08

---

## 1. Trigger Criteria & Preconditions

Under Pre-Registration Section 6 and Invariant I-02, fine-tuning or domain adaptation of the primary recognition model is **strictly prohibited** unless all of the following conditions are simultaneously met:

1. **Empirical Deficit Trigger:** In-domain $FNMR @ FMR=10^{-4} > 2.0 \times$ public benchmark level ($> 6.4\%$), OR any demographic group fails the Fairness Gate ($FNMR_{group} > 2.0 \times FNMR_{overall}$).
2. **Exhaustion of Cheaper Interventions:** Every one of the following non-training remedies must have been deployed, benchmarked, and proven insufficient in strict order:
   - *Stage 1:* Preprocessing & alignment fixes (Umeyama landmark residual audit, affine refinement).
   - *Stage 2:* Quality gating (strict ISO/IEC 29794-5 discard of degraded frames).
   - *Stage 3:* Test-Time Augmentation (Flip-TTA) and dual-model score fusion.
   - *Stage 4:* Score calibration ($C_{llr}$ optimization on TUNE).
   - *Stage 5:* Per-device / per-condition calibration (e.g. low-end camera sensor offsets).

---

## 2. Safe Adaptation Protocol & Architecture

If and only if the trigger criteria fire upon collection of consented Karnataka field data (Track H), the following training plan is authorized for review:

### 2.1 Model Architecture & Frozen Backbone
- **Base Architecture:** ResNet-34 / SFace backbone initialized with OpenCV Zoo Apache-2.0 weights.
- **Backbone Freezing:** Stages 1, 2, and 3 completely frozen to preserve general facial feature extraction capability and avoid catastrophic forgetting.
- **Adaptation Head:** Fine-tune only the final feature projection layer ($fc1$) using ArcFace loss ($s=64.0, m=0.50$).

### 2.2 Dataset & Sovereign Provenance Requirements
- **Dataset:** Consented in-domain Karnataka demographic cohort collected under Protocol H-01.
- **Provenance:** 100% verified DPDP Act 2023 consent records with specific consent for biometric feature tuning. No web-scraped or unverified datasets (e.g. MS1MV2, Glint360k) are permitted.
- **Partitioning:** Identical 40% TUNE, 40% VALIDATE, 20% LOCKBOX separation with zero subject identity leakage.

---

## 3. Risk Assessment & Mitigations

| Risk | Severity | Mitigation |
| :--- | :--- | :--- |
| **Catastrophic Forgetting** | High | Freeze layers 1-3; penalize L2 weight divergence from baseline weights: $\mathcal{L} = \mathcal{L}_{arc} + \lambda \|\theta - \theta_{orig}\|_2^2$. |
| **Overfitting to Sensor Artifacts** | High | Heavy data augmentation (random blur, brightness jitter, wire-codec compression). |
| **Fairness Regression** | Critical | Minimax fairness objective: stop optimization if any single demographic subgroup degrades. |
| **Licensing Contamination** | Critical | Absolute ban on third-party commercial training datasets. All data must be sovereign, consented, and on-premise. |
