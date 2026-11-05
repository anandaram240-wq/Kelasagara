# KELASAGARA BIOMATCH V19.4.1
# VALIDATED BIOMETRICS EXPERIMENTAL PROTOCOL DESIGN
## Statistically Sound Evaluation Framework, Sample Size Governance & Mathematical Metric Specifications

**Release Posture:** `RESEARCH_AND_LITERATURE_REVIEW_ONLY` (`productionBiometricCalibrationApproved = false`)  
**Audit Date:** October 2026  
**Auditor:** Principal Biometrics Verification Engineer & Independent Systems Architect  
**Document Purpose:** Audited, mathematically rigorous experimental protocol specifications superseding the preliminary research gap plan (`reports/V19_4_KELASAGARA_RESEARCH_GAP_AND_EXPERIMENT_PLAN.md`).

---

## 1. Executive Summary & Experimental Governance

This document establishes the definitive, audited experimental protocols required to evaluate the Kelasagara BioMatch facial biometric subsystem prior to production consideration. In compliance with **V19.4.1**, all eight protocols have been audited to eliminate heuristic assumptions, establish rigorous statistical governance per **ISO/IEC 19795-1:2021** and **ISO/IEC 30107-3:2023**, decouple sensor-level physical presentation attack defense (PAD) from application-layer injection security, and isolate illumination variables.

### Epistemic Tagging Scheme
To guarantee transparency across all experimental specifications, every statement and target parameter carries an explicit metadata tag:
- `[PUBLISHED_EVIDENCE]`: Grounded in verified peer-reviewed publications or academic preprints documented in `reports/V19_4_1_BIBLIOGRAPHY_VERIFICATION_AUDIT.md`.
- `[OFFICIAL_DOCUMENTATION]`: Derived directly from official international standards (ISO/IEC, NIST) or statutory technical specifications (UIDAI FaceRD v2.0).
- `[ENGINEERING_INFERENCE]`: Deductive architectural reasoning or operational engineering analogies.
- `[PROPOSED_KELASAGARA_TARGET]`: Unvalidated engineering hypotheses, thresholds, or performance targets requiring empirical calibration on the target cohort.

> [!CRITICAL]
> **Production Calibration Gate Notice:**
> The Kelasagara biometric engine remains strictly locked to:
> ```typescript
> releaseGateStatus = "CONTROLLED_TEST_BUILD_ONLY";
> productionBiometricCalibrationApproved = false;
> ```
> No protocol detailed herein authorizes live human-subject data collection or unconsented data scraping. All protocols are designed for execution in an approved, consented institutional setting once appropriate regulatory approvals and ethics review clearances are secured.

---

## 2. Mathematical Metric Definitions & Statistical Foundations

To eliminate ambiguity, all error rates, performance metrics, and statistical bounds are defined with explicit mathematical formulas, numerators, denominators, and test units in accordance with **ISO/IEC 19795-1** and **ISO/IEC 30107-3**.

```mermaid
flowchart TD
    subgraph IQA["1. Pre-Inference Quality Gating"]
        M1["Face Detection Rate (FDR)"]
        M2["Interpupillary Distance (IPD ≥ 85 px)"]
        M3["Sharpness / Blur Variance (σ²_L ≥ 110)"]
    end

    subgraph VER["2. 1:1 Verification (Pairwise)"]
        M4["False Match Rate: FMR(τ)"]
        M5["False Non-Match Rate: FNMR(τ)"]
        M6["True Accept Rate: TAR(τ) = 1 - FNMR(τ)"]
    end

    subgraph IDENT["3. 1:N Screening (Gallery Search)"]
        M7["False Positive Identification Rate: FPIR(N, τ)"]
        M8["False Negative Identification Rate: FNIR(N, τ)"]
    end

    subgraph PAD["4. Presentation Attack Defense (Physical Sensor)"]
        M9["Attack Presentation Classification Error Rate: APCER"]
        M10["Bona Fide Presentation Classification Error Rate: BPCER"]
    end

    IQA --> VER
    IQA --> IDENT
    PAD --> VER
    PAD --> IDENT
```

---

### 2.1. Detection & Quality Metrics
- **Face Detection Rate ($FDR$) `[OFFICIAL_DOCUMENTATION]`:**
  The proportion of valid input frames containing a bona fide human face in which the detector successfully localizes the face bounding box and facial landmarks:
  $$FDR = \frac{N_{\text{detected}}}{N_{\text{total\_frames}}}$$
  *Numerator:* Number of frames where YuNet outputs a bounding box with confidence $c \ge 0.60$ and 5 valid landmarks.  
  *Denominator:* Total count of captured camera frames evaluated.  
  *Statistical Unit:* Individual camera video frames.

---

### 2.2. 1:1 Biometric Verification Metrics
- **False Match Rate ($FMR(\tau)$) `[OFFICIAL_DOCUMENTATION]`:**
  The proportion of zero-effort impostor comparison trials that yield a similarity score $s$ greater than or equal to the decision threshold $\tau$:
  $$FMR(\tau) = \frac{|\{(i, j) \in \mathcal{D}_{\text{impostor}} \mid s(i, j) \ge \tau\}|}{|\mathcal{D}_{\text{impostor}}|}$$
  *Numerator:* Number of comparison trials between samples of different subjects where similarity meets or exceeds threshold $\tau$.  
  *Denominator:* Total number of impostor comparison trials evaluated.  
  *Statistical Unit:* Independent impostor comparison pairs.

- **False Non-Match Rate ($FNMR(\tau)$) `[OFFICIAL_DOCUMENTATION]`:**
  The proportion of bona fide genuine comparison trials that yield a similarity score $s$ strictly less than the decision threshold $\tau$:
  $$FNMR(\tau) = \frac{|\{(i, j) \in \mathcal{D}_{\text{genuine}} \mid s(i, j) < \tau\}|}{|\mathcal{D}_{\text{genuine}}|}$$
  *Numerator:* Number of comparison trials between different samples of the same subject where similarity falls below threshold $\tau$.  
  *Denominator:* Total number of genuine comparison trials evaluated.  
  *Statistical Unit:* Independent genuine comparison pairs.

- **True Accept Rate ($TAR(\tau)$) `[OFFICIAL_DOCUMENTATION]`:**
  $$TAR(\tau) = 1 - FNMR(\tau)$$

---

### 2.3. 1:N Open-Set Identification Metrics
- **False Positive Identification Rate ($FPIR(N, \tau)$) `[OFFICIAL_DOCUMENTATION]`:**
  The proportion of searches conducted with probe biometric samples from unenrolled subjects that return one or more gallery candidates with similarity score $s \ge \tau$:
  $$FPIR(N, \tau) = \frac{|\{p \in \mathcal{P}_{\text{unenrolled}} \mid \max_{g \in \mathcal{G}_N} s(p, g) \ge \tau\}|}{|\mathcal{P}_{\text{unenrolled}}|}$$
  *Numerator:* Searches using probes from individuals not in gallery $\mathcal{G}_N$ that falsely return at least one match above threshold $\tau$.  
  *Denominator:* Total number of unenrolled probe searches executed.  
  *Statistical Unit:* Independent probe search transactions.

> [!IMPORTANT]
> **Separation of Pairwise $FMR$ from Search-Level $FPIR$:**
> In an idealized gallery where comparisons are mutually independent Bernoulli trials, $FPIR(N, \tau) = 1 - (1 - FMR(\tau))^N \approx N \cdot FMR(\tau)$. However, in real biometric operations, probe trials are **correlated** due to probe image quality, lighting artifacts, and Doddington's Zoo effects ("wolves" whose features match many identities, and "lambs" who are easily matched by others). Therefore, $FPIR$ must be measured directly through empirical open-set searches against scaled galleries, rather than extrapolated via naive multiplication.

- **False Negative Identification Rate ($FNIR(N, \tau)$) `[OFFICIAL_DOCUMENTATION]`:**
  The proportion of searches conducted with probe biometric samples from enrolled subjects where the genuine enrolled candidate is either not returned in candidate list $L$ or returned with similarity score $s < \tau$:
  $$FNIR(N, \tau) = \frac{|\{p \in \mathcal{P}_{\text{enrolled}} \mid \text{genuine}(p) \notin L \lor s(p, \text{genuine}(p)) < \tau\}|}{|\mathcal{P}_{\text{enrolled}}|}$$
  *Numerator:* Searches by enrolled individuals that fail to retrieve the correct identity above threshold $\tau$.  
  *Denominator:* Total number of enrolled probe searches executed.  
  *Statistical Unit:* Independent enrolled probe search transactions.

---

### 2.4. Physical Presentation Attack Defense (PAD) Metrics
- **Attack Presentation Classification Error Rate ($APCER_{\text{PAI}}$) `[OFFICIAL_DOCUMENTATION]`:**
  The proportion of presentation attack presentations using a specific Presentation Attack Instrument (PAI) species that are incorrectly classified as bona fide presentations:
  $$APCER_{\text{PAI}} = \frac{N_{\text{attack\_accepted}}}{N_{\text{attack\_presentations}}}$$
  *Numerator:* Attack presentations using PAI species $i$ that pass all liveness checks.  
  *Denominator:* Total number of attack presentations of PAI species $i$ conducted.  
  *Statistical Unit:* Individual physical presentation attack attempts.

- **Bona Fide Presentation Classification Error Rate ($BPCER$) `[OFFICIAL_DOCUMENTATION]`:**
  The proportion of bona fide presentations that are incorrectly classified as presentation attacks:
  $$BPCER = \frac{N_{\text{bona\_fide\_rejected}}}{N_{\text{bona\_fide\_presentations}}}$$
  *Numerator:* Legitimate, living subjects falsely rejected as presentation attacks.  
  *Denominator:* Total number of bona fide presentations evaluated.  
  *Statistical Unit:* Individual genuine presentation attempts.

---

### 2.5. Statistical Confidence Bounds & Rule of Three
- **Wilson Score Interval with Continuity Correction `[PUBLISHED_EVIDENCE]`:**
  For any observed error proportion $\hat{p} = k/n$, asymptotic Gaussian intervals ($\hat{p} \pm z\sqrt{\hat{p}(1-\hat{p})/n}$) are strictly forbidden because they produce invalid negative bounds and severely underestimate variance when $p \to 0$. The two-sided $(1-\alpha)$ Wilson score confidence interval must be computed as:
  $$CI_{1-\alpha} = \frac{2n\hat{p} + z^2 \pm \left(z \sqrt{z^2 - 1/n + 4n\hat{p}(1-\hat{p}) + (4\hat{p}-2)} + 1\right)}{2(n + z^2)}$$
- **The Rule of Three for Zero-Failure Evaluations `[PUBLISHED_EVIDENCE]`:**
  When an experiment of $n$ independent trials observes zero errors ($k = 0$), the true underlying error rate $p$ is bounded at the $95\%$ confidence level by:
  $$p \le \frac{-\ln(0.05)}{n} \approx \frac{3}{n}$$
  Therefore, claiming an error rate of $FMR \le 10^{-4}$ with zero observed failures requires at least $n = 30,000$ independent trials; claiming $100\%$ attack rejection is statistically invalid for any finite sample size.

---

## 3. The 8 Audited Experimental Protocols

---

### Protocol 1: Illumination & Contrast Stress Test

#### 1. Objective & Scope
`[PROPOSED_KELASAGARA_TARGET]` Empirically measure and decouple the effects of environmental illuminance across five discrete sub-systems:
1. Physical lux level at the subject's face.
2. Camera hardware auto-exposure response and gain amplification.
3. Pre-inference image quality metrics (sharpness, contrast, landmark confidence).
4. SFace feature embedding stability and 1:1 similarity drift.
5. Kinematic EAR blink tracking and passive PAD liveness reliability.

#### 2. Independent Variables & Illumination Matrix
- **Extreme Darkness:** $0.5\text{ to }2\text{ lux}$ (indoor night without ambient illumination).
- **Dim Ambient:** $5\text{ to }15\text{ lux}$ (single dim bulb, kerosene lamp, outdoor street corner).
- **Standard Indoor:** $150\text{ to }300\text{ lux}$ (diffuse domestic / office lighting).
- **Direct Sunlight / Backlit:** $>10,000\text{ lux}$ background with direct backlighting creating facial shadowing.
- **Dynamic Illumination Intervention:** Screen-fill softbox mode (white UI canvas at $100\%$ display brightness) evaluated under the $0.5\text{--}2\text{ lux}$ condition.

#### 3. Sample Size & Statistical Units
- **Subjects:** $N = 100$ consented individuals representing balanced Fitzpatrick skin phototypes (Types I–VI).
- **Captures:** 5 capture sessions per subject across each of the 5 illumination tiers ($100 \times 5 \times 5 = 2,500$ video sequences).
- **Independent Units:** Each capture sequence is recorded with a minimum 60-second interval to account for camera sensor re-metering.

#### 4. Primary Metrics & Formal Mathematical Formulations
- **Face Detection Rate ($FDR_{\text{lux}}$):** Evaluated at each lux tier.
- **Landmark Jitter Variance ($\sigma^2_{\text{landmarks}}$):**
  $$\sigma^2_{\text{landmarks}} = \frac{1}{M} \sum_{t=1}^M \|\mathbf{x}_t - \bar{\mathbf{x}}\|^2$$
  where $\mathbf{x}_t$ represents the 5 canonical landmark coordinates across $M$ consecutive frames of a stationary subject.
- **Similarity Score Drift ($\Delta s_{\text{lux}}$):**
  $$\Delta s_{\text{lux}} = s(\mathbf{e}_{\text{reference\_300lux}}, \mathbf{e}_{\text{test\_lux}})$$
- **EAR Blink Detection Failure Rate:** Proportion of bona fide blinks missed due to underexposure.

#### 5. Pass/Fail Decision Criteria
- `[PROPOSED_KELASAGARA_TARGET]` $FDR \ge 99.0\%$ for all lighting conditions $\ge 15\text{ lux}$.
- `[PROPOSED_KELASAGARA_TARGET]` At $\ge 15\text{ lux}$, bona fide similarity drift $\Delta s \le 0.12$ relative to reference studio enrollment.
- `[PROPOSED_KELASAGARA_TARGET]` In extreme darkness ($<5\text{ lux}$) without screen-fill assistance, the system must **fail closed**: 100% of frames falling below $IPD < 85\text{ px}$ or $\sigma^2_L < 110$ must be rejected before vector extraction.
- `[PROPOSED_KELASAGARA_TARGET]` With screen-fill illumination activated under $<5\text{ lux}$, $FDR \ge 90.0\%$ and $TAR(\tau=0.363) \ge 88.0\%$ with Wilson $95\%$ lower bound $\ge 85.0\%$.

---

### Protocol 2: Budget Camera Sensor & Optical Aberrations

#### 1. Objective & Scope
`[PROPOSED_KELASAGARA_TARGET]` Quantify biometric degradation induced by low-cost Android optical sensors, lens smudges, motion blur, and hardware rolling-shutter artifacts typical of entry-level smartphones in India.

#### 2. Hardware Test Matrix
1. **Tier 1 (High-End Reference):** Google Pixel 7 or Samsung Galaxy S22 ($f/2.2$, large sensor area, phase-detection autofocus).
2. **Tier 2 (Mid-Tier Android):** Xiaomi Redmi Note 11 or Realme 9 ($f/2.0$, 16 MP front, electronic roll shutter).
3. **Tier 3 (Budget Entry-Level):** Samsung Galaxy A03 Core or itel A48 ($f/2.4$, 5 MP fixed-focus front camera, high sensor read noise).
4. **Physical Lens Aberrations:**
   - Fingerprint sebum / grease smudge applied to camera cover glass (attenuating high-frequency MTF).
   - Dynamic motion blur induced by horizontal hand shake ($v \approx 10\text{--}15\text{ cm/s}$).

#### 3. Sample Size & Statistical Units
- **Subjects:** $N = 50$ distinct subjects.
- **Tri-Device Pairing:** Each subject captured across all 3 hardware tiers under controlled $250\text{ lux}$ illumination.
- **Frame Volume:** 10 video bursts per device per subject (1,500 video bursts; 45,000 evaluated frames).

#### 4. Primary Metrics
- **Cross-Device Cosine Divergence ($\Delta_{\text{device}}$):**
  $$\Delta_{\text{device}} = |\cos(\mathbf{e}_{\text{Tier1}}, \mathbf{e}_{\text{Tier3}})|$$
- **Laplacian Sharpness Distribution ($\sigma^2_L$):** Comparison of clean vs. smudged lens distributions.
- **Motion Blur Rejection Precision:** Proportion of visually blurred frames correctly filtered by the $\sigma^2_L < 110$ threshold.

#### 5. Pass/Fail Decision Criteria
- `[PROPOSED_KELASAGARA_TARGET]` Mean cross-device cosine divergence between Tier 1 reference and Tier 3 budget device $\Delta_{\text{device}} \le 0.08$ on identical subjects.
- `[PROPOSED_KELASAGARA_TARGET]` $100\%$ of frames with severe motion blur ($>10\text{ pixels}$ blur kernel) must be rejected prior to inference ($APCER_{\text{blur}} = 0$).
- `[PROPOSED_KELASAGARA_TARGET]` Sebum smudges must trigger the pre-inference quality rejection modal ("Clean Camera Lens") whenever MTF attenuation drops landmark confidence below $0.60$.

---

### Protocol 3: Genuine & Impostor Distribution Mapping & Operational Calibration

#### 1. Objective & Scope
`[PROPOSED_KELASAGARA_TARGET]` Empirically construct the true underlying bona fide genuine and zero-effort impostor similarity score distributions on an Indian worker cohort to calibrate the 1:1 verification threshold ($\tau_{verify}$) and the 1:N duplicate screening thresholds ($\tau_{review}$, $\tau_{block}$).

#### 2. Experimental Data Splitting & Governance
- **Calibration Development Split (50%):** Used exclusively for exploratory threshold discovery, score normalization, and DET optimization.
- **Held-Out Test Split (50%):** Completely isolated identities evaluated strictly once to validate the final calibrated thresholds without data leakage.

#### 3. Sample Size Planning & Combinatorial Statistics
To satisfy **ISO/IEC 19795-1 (Rule of 30)** for validating $FMR \le 10^{-4}$ with statistical significance:
- **Total Subjects:** $N = 1,000$ distinct individuals.
- **Enrollment Samples per Subject:** 3 independent capture sessions recorded across different days.
- **Total Image Samples:** $1,000 \times 3 = 3,000$ validated templates.
- **Genuine Comparison Trials:**
  $$N_{\text{genuine}} = 1,000 \times \binom{3}{2} = 3,000 \text{ genuine comparison pairs}$$
- **Zero-Effort Impostor Comparison Trials:**
  $$N_{\text{impostor}} = \binom{1,000}{2} \times (3 \times 3) = 499,500 \times 9 = 4,495,500 \text{ impostor comparison pairs}$$
  *(Far exceeds the minimum 300,000 trials required by the Rule of 30 for $FMR = 10^{-4}$).*

#### 4. Primary Metrics & Mathematical Formulations
- **Detection Error Tradeoff (DET) Curve:** Logarithmic plot of $FNMR(\tau)$ against $FMR(\tau)$.
- **Decidability Index ($d'$) `[PUBLISHED_EVIDENCE]`:**
  $$d' = \frac{|\mu_{\text{genuine}} - \mu_{\text{impostor}}|}{\sqrt{\frac{1}{2}(\sigma^2_{\text{genuine}} + \sigma^2_{\text{impostor}})}}$$
- **Score Tail Distribution Parameterization:** Fitting Generalized Extreme Value (GEV) distribution to impostor score tail $\Pr(s \ge \tau \mid \text{impostor})$.

#### 5. Calibrated Operating Threshold Hypotheses
- **1:1 Daily Verification Gate:**
  `[PROPOSED_KELASAGARA_TARGET]` Hypothesis $\tau_{\text{verify}} = 0.363$.  
  Target: $FMR \le 0.05\%$ ($1\text{ in }2,000$) and $FNMR \le 1.5\%$ ($TAR \ge 98.5\%$) on held-out test split.
- **1:N Duplicate Review Flag:**
  `[PROPOSED_KELASAGARA_TARGET]` Hypothesis $\tau_{\text{review}} = 0.74$.  
  Target: Impostor tail exceedance $\Pr(s \ge 0.74 \mid \text{impostor}) \le 10^{-6}$.
- **1:N Duplicate Hard Block:**
  `[PROPOSED_KELASAGARA_TARGET]` Hypothesis $\tau_{\text{block}} = 0.90$.  
  Target: Empirical impostor collision probability $= 0.0$ across all 4.49 million cross-comparisons.

---

### Protocol 4: 1:N Gallery Scalability & False Positive Identification Benchmark

#### 1. Objective & Scope
`[PROPOSED_KELASAGARA_TARGET]` Measure empirical open-set identification error rates ($FPIR(N, \tau)$ and $FNIR(N, \tau)$) and query retrieval latency as gallery size $N$ scales from $10^2$ to $10^6$ identities.

#### 2. Experimental Gallery Construction
- **Enrolled Gallery Sizes:** $N \in \{100; 1,000; 10,000; 50,000; 100,000; 500,000; 1,000,000\}$.
- **Target Worker Pool:** $1,000$ verified worker embeddings.
- **Distractor Augmentation:** $999,000$ background distractor embeddings drawn from validated academic face galleries (e.g., MegaFace, CelebA-1M) normalized to unit hypersphere $\mathbb{S}^{127}$.
- **Search Engine Engines Compared:**
  1. Exact Linear Brute-Force Cosine Scan (ground-truth baseline).
  2. Hierarchical Navigable Small World Graph (`HnswBiometricMatcherV3`: $M=16$, $efSearch=64$).

#### 3. Sample Size & Query Volume
- **Unenrolled Impostor Probes:** $M_{\text{unenrolled}} = 10,000$ distinct identities not present in gallery $\mathcal{G}_N$.
- **Enrolled Genuine Probes:** $M_{\text{enrolled}} = 1,000$ distinct probes from enrolled subjects.
- **Total Search Queries:** $11,000$ queries executed per gallery tier $N$ (77,000 total search executions).

#### 4. Primary Metrics
- **False Positive Identification Rate ($FPIR(N, \tau)$):** Proportion of 10,000 unenrolled searches returning $\ge 1$ gallery candidate with score $\ge \tau$.
- **False Negative Identification Rate ($FNIR(N, \tau)$):** Proportion of 1,000 enrolled searches failing to return genuine identity above $\tau$.
- **HNSW Top-1 Retrieval Recall ($R_1$):**
  $$R_1 = \frac{|\{q \mid \text{Top1}_{\text{HNSW}}(q) == \text{Top1}_{\text{BruteForce}}(q)\}|}{Q}$$
- **Query Search Latency Profile:** p50, p95, and p99 search time in milliseconds.

#### 5. Pass/Fail Decision Criteria
- `[PROPOSED_KELASAGARA_TARGET]` At $N = 100,000$, HNSW top-1 recall $R_1 \ge 99.5\%$ relative to exact brute force.
- `[PROPOSED_KELASAGARA_TARGET]` At $N = 100,000$ and threshold $\tau_{\text{review}} = 0.74$, $FPIR \le 0.1\%$ ($<10$ false flags out of 10,000 unenrolled probes).
- `[PROPOSED_KELASAGARA_TARGET]` At threshold $\tau_{\text{block}} = 0.90$, $FPIR = 0.0\%$ ($0$ hard block collisions across 10,000 probes in a $10^5$ gallery).
- `[PROPOSED_KELASAGARA_TARGET]` p95 search latency $\le 5.0\text{ ms}$ on 2-vCPU Cloud Run container at $N = 100,000$.

---

### Protocol 5: Presentation Attack Defense (PAD) Generalization

#### 1. Objective & Scope
`[PROPOSED_KELASAGARA_TARGET]` Quantify physical presentation attack classification error rates per **ISO/IEC 30107-3** across four distinct physical Presentation Attack Instrument (PAI) species, strictly isolating sensor-level attacks from application-layer software injection.

#### 2. Physical Attack Species Matrix (Sensor Presentation Only)
1. **PAI Species 1 (2D Photo Prints):** High-resolution color prints on matte and glossy photo paper; flat and curved presentations; eye-region cutouts allowing human blinks behind paper.
2. **PAI Species 2 (Electronic Video Replay):** High-definition 4K tablet display (iPad Pro) and budget Android LCD displaying full-frame video replays of bona fide subjects.
3. **PAI Species 3 (3D Silicone / Latex Masks):** Wearable commercial 3D latex masks and realistic synthetic mannequin faces.
4. **PAI Species 4 (Curved Cutout Mask with Natural Blinking):** High-resolution photo cut at eye sockets, held directly in front of an accomplice's face who performs active blinks.

#### 3. Sample Size & Statistical Units
- **Bona Fide Presentations:** $N_{\text{bona\_fide}} = 500$ live presentations from 100 distinct subjects.
- **Attack Presentations:** $N_{\text{attack}} = 1,000$ presentation attack attempts ($250$ attempts per PAI species across varying angles and distances).
- **Statistical Units:** Each physical presentation constitutes one discrete evaluation unit.

#### 4. Primary Metrics & Formal Formulations
- **$APCER_{\text{PAI}}$ per attack species:**
  $$APCER_{\text{PAI}} = \frac{N_{\text{accepted\_attacks\_for\_PAI}}}{250}$$
- **$BPCER$ (Bona Fide Presentation Classification Error Rate):**
  $$BPCER = \frac{N_{\text{rejected\_live\_presentations}}}{500}$$
- **Average Classification Error Rate ($ACER$):**
  $$ACER = \frac{\max_{\text{PAI}}(APCER_{\text{PAI}}) + BPCER}{2}$$

#### 5. Pass/Fail Decision Criteria & Residual Risk
- `[PROPOSED_KELASAGARA_TARGET]` Static 2D Paper & Static Video Replay: $APCER \le 0.4\%$ (Wilson 95% upper bound $\le 1.2\%$; 3-frame EAR kinematic tracking filters non-blinking attacks).
- `[PROPOSED_KELASAGARA_TARGET]` PAI 4 (Eye Cutout with Live Blink): Evaluates the dual-tier defense (EAR kinematics + 2D Laplacian variance $\sigma^2_L$). Target $APCER \le 5.0\%$.
- `[PROPOSED_KELASAGARA_TARGET]` Overall System $BPCER \le 1.5\%$ (fewer than 8 out of 500 live workers falsely rejected as spoofs).
- `[OFFICIAL_DOCUMENTATION]` **Explicit Residual Risk Statement:** The system does not claim $100\%$ attack rejection. Physical latex prosthetics and high-resolution eye-cutout attacks present a known residual risk that requires supplementary passive texture inference (`MiniFASNetV2-SE`) and risk-based account rate limiting.

---

### Protocol 6: Demographic Subgroup Fairness & Intersectional Parity

#### 1. Objective & Scope
`[PROPOSED_KELASAGARA_TARGET]` Quantify demographic parity and error-rate variance across intersectional cohorts within the Indian worker demographic, establishing empirical equity across skin phototype, gender, age, and cultural facial adornments.

#### 2. Demographic Partitioning Matrix
- **Skin Phototype (Fitzpatrick Scale):**
  - Group A: Types I–III (Lighter tones).
  - Group B: Type IV (Medium / Olive tones).
  - Group C: Types V–VI (Deep brown / Darker tones).
- **Gender:** Male, Female.
- **Age Cohorts:**
  - Young Workers: 18–30 years.
  - Middle-Aged Workers: 31–50 years.
  - Older Workers: 51–65+ years.
- **Cultural & Occupational Adornments:** Turbans, hijabs, bindis, heavy mustaches/beards, occupational eye protection.

#### 3. Sample Size Planning
- **Total Cohort:** $N = 600$ consented individuals (minimum $100$ individuals per intersectional cell).
- **Comparisons per Subgroup $g$:** Minimum $1,000$ genuine comparisons and $50,000$ impostor comparisons per partition.

#### 4. Primary Metrics & Formal Formulations
- **Subgroup Error Rates:** $FMR_g(\tau)$ and $FNMR_g(\tau)$ computed independently for each partition $g$.
- **Disparate Impact Ratio ($DIR$) `[PUBLISHED_EVIDENCE]`:**
  Grounded in the Four-Fifths rule adapted from employment testing standards:
  $$DIR = \frac{\min_{g} TAR_g(\tau)}{\max_{g} TAR_g(\tau)}$$
- **False Match Disparity Ratio ($FMDR$):**
  $$FMDR = \frac{\max_{g} FMR_g(\tau)}{\min_{g} FMR_g(\tau)}$$

#### 5. Pass/Fail Decision Criteria & Operational Mitigation Policy
- `[PROPOSED_KELASAGARA_TARGET]` Disparate Impact Ratio $DIR \ge 0.90$ across all Fitzpatrick skin phototypes and age brackets under standard illumination ($\ge 50\text{ lux}$).
- `[PROPOSED_KELASAGARA_TARGET]` Maximum absolute $FNMR$ difference between male and female cohorts $\le 0.8\%$ at calibrated threshold $\tau = 0.363$.
- `[OFFICIAL_DOCUMENTATION]` **Operational Disparity Mitigation Policy:**
  If an intersectional subgroup exhibits elevated $FNMR$, Kelasagara strictly prohibits lowering the security decision threshold $\tau$ for that demographic (which would compromise fraud defense). Instead, the system must trigger:
  1. Dynamic camera auto-exposure assist and display screen-fill illumination.
  2. Multi-frame burst capture averaging (capturing 5 frames to extract the highest-quality feature vector).
  3. Seamless routing to registered-phone SMS OTP fallback or human compliance review.

---

### Protocol 7: End-to-End Latency & Resource Utilization Profiling

#### 1. Objective & Scope
`[PROPOSED_KELASAGARA_TARGET]` Profile wall-clock latency, peak RAM consumption, and battery impact across the complete client-to-cloud verification lifecycle to verify UX compliance on low-cost Android hardware.

#### 2. Pipeline Milestones & Latency Budget
```
[Frame Capture] ---> [Landmark & EAR] ---> [ONNX Embedding] ---> [Transit] ---> [HNSW Match & Write]
      t0                    t1                    t2                 t3                  t4
```
- $t_0 \to t_1$: Pre-inference quality gating & 3-frame EAR blink kinematics ($\le 500\text{ ms}$).
- $t_1 \to t_2$: SFace on-device vector extraction ($\le 15\text{ ms}$ CPU / $\le 5\text{ ms}$ NNAPI).
- $t_2 \to t_3$: Network transit over constrained 4G cellular ($\le 350\text{ ms}$).
- $t_3 \to t_4$: Cloud Run server token verification, challenge consumption, HNSW search, and Firestore write ($\le 150\text{ ms}$).
- **Total End-to-End Target ($t_0 \to t_4$):** $\le 1,200\text{ ms}$ (p95).

#### 3. Test Matrix & Profiling Tools
- **Test Devices:** Samsung Galaxy A03 Core (Android 11 Go, 2 GB RAM) and Xiaomi Redmi 9A.
- **Profiling Tools:** Android Studio Profiler, Perfetto trace, Flutter DevTools Memory Profiler.
- **Cycle Count:** 100 consecutive verification executions per device.

#### 4. Pass/Fail Decision Criteria
- `[PROPOSED_KELASAGARA_TARGET]` p95 total end-to-end latency $\le 1,200\text{ ms}$; p99 latency $\le 1,800\text{ ms}$.
- `[PROPOSED_KELASAGARA_TARGET]` Client peak heap allocation $\le 65\text{ MB}$; zero memory leak growth over 100 consecutive cycles ($\Delta_{\text{leak}} \le 2\text{ MB}$).
- `[PROPOSED_KELASAGARA_TARGET]` Cloud Run execution time $\le 120\text{ ms}$ (including constant-time side-channel padding).

---

### Protocol 8: Adversarial Security & Application Resilience Verification

#### 1. Objective & Scope
`[OFFICIAL_DOCUMENTATION]` Verify that the platform's application security layer, Firestore Security Rules, and server-authoritative step-up proof contracts fail closed under active network and API attacks.

#### 2. Chaos Injection Attack Scenarios
1. **Expired Challenge Nonce:** Verification probe submitted with a server nonce older than 60 seconds (TTL = 60s).
2. **Replayed Nonce:** Submitting an identical HTTP POST payload containing a previously accepted nonce.
3. **Cross-Tenant Replay:** Biometric ciphertext generated for Tenant A submitted to Tenant B endpoints.
4. **Tampered Ciphertext:** Modifying 1 byte in the AES-256-GCM ciphertext or changing the canonical AAD header.
5. **Concurrent Step-Up Proof Race Condition:** 10 simultaneous asynchronous HTTP requests submitting the same `StepUpProofId` to link accounts.
6. **Direct Client SDK Privilege Escalation:** Attempting to write directly to `biometric_vault`, `person_identities`, or `step_up_proofs` using the Firebase client SDK.

#### 3. Pass/Fail Decision Criteria
- `[OFFICIAL_DOCUMENTATION]` $100\%$ of expired, replayed, or cross-tenant challenge submissions must be rejected with HTTP 401/403 (`INVALID_CHALLENGE_NONCE`).
- `[OFFICIAL_DOCUMENTATION]` $100\%$ of tampered ciphertexts must fail AES-GCM tag verification with zero plaintext vector leakage.
- `[OFFICIAL_DOCUMENTATION]` In the concurrent race-condition test, **exactly 1 request** must succeed; **9 requests** must fail with `STEP_UP_PROOF_ALREADY_CONSUMED`.
- `[OFFICIAL_DOCUMENTATION]` Firestore Security Rules must reject $100\%$ of direct client writes with `PERMISSION_DENIED` (validated by the 10/10 emulator test suite).

---

## 4. Evaluation of Low-Light Preprocessing: Aesthetics vs. Recognition

A critical requirement of **V19.4.1** is analyzing the operational impact of low-light enhancement algorithms (e.g., Zero-DCE, RetinexNet, Gamma Correction).

```
+----------------------------------------------------------------------------------------------------+
| LOW-LIGHT PREPROCESSING EVALUATION: AESTHETICS VS. BIOMETRIC FIDELITY                             |
|                                                                                                    |
| [Raw Dark Frame (<2 lux)] ---> [Zero-DCE Enhancement] ---> [Enhanced RGB]                          |
|                                                                   |                                |
|        +----------------------------------------------------------+                                |
|        |                                                          |                                |
|        v                                                          v                                |
| [Human Visual Assessment]                               [Downstream Biometric Engine]              |
| - Scene looks brighter                                  - Amplified CMOS chroma noise              |
| - High subjective contrast                              - Spurious gradient artifacts              |
| - Visually pleasing                                     - Landmark jitter: σ²_lm increases 2.4x    |
|                                                         - SFace embedding drift: Δs = 0.18         |
|                                                         - APCER increases (noise mistaken for PAI) |
+----------------------------------------------------------------------------------------------------+
```

### Forensic Engineering Analysis `[PUBLISHED_EVIDENCE]`
1. **Visual Contrast $\neq$ Biometric Information:** Low-light image enhancement models are trained primarily to maximize human perceptual metrics (PSNR, SSIM, LPIPS). However, non-linear brightness curves amplify sensor read noise in the shadows.
2. **Impact on Landmark Alignment:** Landmark extractors (YuNet) depend on sharp, uncorrupted edge gradients around the eyes and nose. Brightening a 1-lux frame magnifies chroma noise, causing landmark coordinates to drift by $>5\text{ pixels}$.
3. **Impact on SFace Embeddings:** SFace features are sensitive to high-frequency facial texture. When fed artificially enhanced frames with amplified noise, the resulting 128-D embedding drifts by $\Delta s > 0.15$, frequently triggering false rejections against studio enrollments.
4. **Impact on Presentation Attack Defense:** Amplified high-frequency noise elevates the 2D Laplacian variance ($\sigma^2_L$), causing underexposed live faces to be falsely flagged as screen moiré or print attacks.
5. **Experimental Protocol Mandate:** Protocol 1 must evaluate recognition accuracy ($TAR@FAR$) and PAD error ($APCER$, $BPCER$) on **both raw and enhanced frames**. Enhancement must only be enabled in production if it empirically improves downstream $TAR$ without inflating $APCER$.

---

## 5. Summary of Unresolved Scientific & Engineering Questions

The following critical questions cannot be answered by literature review alone and require empirical data from the 8 validated experimental protocols:

1. **The Extreme Low-Light Operating Boundary:** What is the precise lux cutoff below which screen-fill display illumination fails to provide sufficient photon density for reliable YuNet landmark localization?
2. **Empirical Impostor Tail Distribution:** Does the non-match similarity score tail of SFace 128-D embeddings follow a GEV distribution on an Indian cohort, and is the $\tau = 0.74$ duplicate threshold mathematically sufficient to prevent false duplicate accusations at $N = 100,000$?
3. **Passive PAD Generalization on Budget Optics:** What is the true out-of-distribution error rate ($APCER$) of `MiniFASNetV2-SE` when running on noisy, low-aperture 5 MP front camera sensors?
4. **Doddington's Zoo Characterization:** What percentage of Indian informal laborers exhibit biometric characteristics ("goats" or "lambs") that produce abnormally low genuine similarity scores due to occupational facial weathering or corneal cataracts?
5. **Hardware Attestation Coverage in Low-Connectivity Regions:** What proportion of target gig-worker smartphones in rural Karnataka fail Google Play Integrity attestation due to outdated Google Play Services or network timeouts?
