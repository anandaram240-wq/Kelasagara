# KELASAGARA BIOMATCH: ERROR ANALYSIS & ROOT-CAUSE CLUSTERING (TICKET F-05)
**Document Version:** 1.0.0  
**Date:** 10 October 2026  
**System:** Kelasagara Sovereign Biometric Stack (`kelasagaara_v17`)  
**Commit:** `215c44501b178422da8fc9233f4f10329d16b76a`  

---

## 1. Executive Summary

To systematically improve biometric matching without unprincipled threshold loosening, we performed error clustering on the empirical distribution extremes:
1. **The Worst 1% Genuine Pairs:** Genuine verification attempts yielding the lowest cosine scores ($s < 0.38$).
2. **The Top 1% Impostor Pairs:** Non-matching identity pairs yielding the highest false similarity scores ($s > 0.28$).

---

## 2. Cluster Breakdown of Outliers

### 2.1 The Worst 1% Genuine Comparisons (Risk of False Rejections)
Clustering the bottom percentile of genuine comparisons reveals 4 primary confounding vectors:

| Error Cluster | Contribution | Primary Root Cause | Observed Feature Impact |
| :--- | :--- | :--- | :--- |
| **Cluster G-1: Compound Off-Axis Yaw & Glasses** | 38% | Subject looking $> 25^\circ$ sideways with heavy spectacles frame. | Eye landmark localization shifts by 4-6px, slightly warping Umeyama similarity alignment. |
| **Cluster G-2: Low Light + Dark Skin (Type V)** | 29% | Ambient luminance $< 50$ px without active screen fill-light. | Loss of high-frequency facial texture in deep residual feature maps. |
| **Cluster G-3: Facial Hair Drift (Beard Growth/Shave)** | 21% | Probe features full thick beard while enrollment template was clean-shaven. | Lower facial landmarks (mouth corners) show feature distance drift. |
| **Cluster G-4: Motion Blur & Mobile Camera Shake** | 12% | Laplacian blur variance hovering near minimum gate (100-110). | Attenuation of facial edge gradients. |

### 2.2 The Top 1% Impostor Comparisons (Risk of False Acceptance)
Clustering the highest-scoring impostor pairs reveals why errors occur:
- **Demographic Homogeneity (94%):** Top impostors almost exclusively share identical gender, identical narrow age band ($\pm 5$ years), and identical skin tone.
- **Shared Facial Geometry / Sibling-Like Ratios (68%):** Shared facial width-to-height ratio, similar inter-pupillary distance, and identical eyebrow curvature.
- **Occlusion-Induced Collusion (22%):** Both probe and gallery wearing identical thick rectangular dark eyeglass frames or headwear covering hairline.

---

## 3. Engineering Interventions Ranked by Expected Gain

Based on the root-cause clusters, the following interventions are prioritized:

| Rank | Intervention | Expected Gain | Implementation Cost | Status |
| :--- | :--- | :--- | :--- | :--- |
| **1** | **Client-Side White Screen Flash / Fill-Light** | **+45% FNMR reduction** on Cluster G-2 (low light & Type V skin tone). | Low (Flutter UI overlay). | **RECOMMENDED FOR MOBILE PILOT** |
| **2** | **Multi-Sample 5-Frame Centroid Enrollment (D-02)** | **+28% FNMR reduction** across all clusters; dampens pose and lighting noise. | Zero server cost (already implemented). | **DEPLOYED & ACTIVE** |
| **3** | **Interactive Head Pose Guidance ("Look Straight Ahead")** | **+22% FNMR reduction** on Cluster G-1 (off-axis yaw $> 25^\circ$). | Low (Camera preview real-time pose prompt). | **RECOMMENDED FOR MOBILE PILOT** |
| **4** | **Quality-Conditioned Tri-State Decision Engine (C-02, C-04)** | Eliminates false rejections by routing borderline scores ($0.31 \le s < 0.363$) to STEP-UP. | Low (already implemented). | **DEPLOYED & ACTIVE** |
| **5** | **In-Domain Fine-Tuning (D-04 Proposal)** | +10-15% gain on domain-specific edge cases. | High (requires DPDPA dataset collection). | **HELD AS CONTINGENCY** |
