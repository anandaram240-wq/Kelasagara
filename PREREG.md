# PRE-REGISTRATION PROTOCOL (PREREG.md)
**Subsystem:** Kelasagara BioMatch Stage S3 / Prompt 10-ADV  
**Protocol Version:** 1.0.0 (Pre-Experimental Registration)  
**Registered Date:** 10 October 2026  
**Git Baseline Commit:** `215c44501b178422da8fc9233f4f10329d16b76a`  
**Execution Environment:** Node.js v24.14.0 + ONNXRuntime v1.20.1 (CPU Provider)  

---

## 1. Context & Scientific Principles

Per the BioMatch Stage S3 Mandate ("Earn, Defend and Ship the Number"), all hypotheses, candidates, metrics, numeric pass/fail gates, data partitions, statistical tests, and stopping rules must be committed **prior to inspecting benchmark results**.

### Core Evidence Rules
1. **Zero Synthetic Substitution:** Synthetic, self-generated, or mocked images never count toward recognition accuracy. Every recognition metric must specify dataset, version, manifest SHA-256, genuine/impostor sample counts, point estimates, and 95% confidence intervals.
2. **Rule of Three Error Ceiling:** Zero observed errors on $N$ trials is reported as an empirical upper bound $\le 3/N$, never as "0%".
3. **Data Availability Gate:** If licensed dataset files or model weights are missing from disk, the ticket is explicitly marked **BLOCKED** with precise data/weight requirements, rather than fabricating results.
4. **Negative Result Valued:** Any hypothesis rejected by evidence is recorded as a valid engineering deliverable.

---

## 2. Research Hypotheses

- **$H_1$ (Baseline Recognition Capability):** SFace FP32 (OpenCV Zoo, Apache-2.0) achieves $\text{TAR@FAR}=10^{-3} \ge 95.0\%$ and $\text{EER} \le 2.0\%$ on standard public benchmarks, whereas uncalibrated random weights (`kelasagara_mobilefacenet.onnx`) fail completely ($\text{AUC} \approx 0.50$, $\text{TAR@FAR}=10^{-3} < 1\%$).
- **$H_2$ (Quantization Efficiency vs. Parity):** SFace INT8 static quantization reduces forward inference latency by $\ge 30\%$ on CPU while maintaining $\Delta\text{TAR@FAR}=10^{-3} \le 0.8\%$ compared to FP32.
- **$H_3$ (Test-Time Augmentation Gain):** Flip-TTA (horizontal flip averaging) improves genuine-pair cosine stability and yields a statistically significant increase in $\text{TAR@FAR}=10^{-4}$ ($\Delta \ge 0.3\%$, $p < 0.05$ under paired identity bootstrap).
- **$H_4$ (Score Calibration Quality):** Mapping raw cosine similarity to calibrated Log-Likelihood Ratios (LLR) via logistic regression on TUNE achieves $C_{llr} < 0.15$ on VALIDATE, ensuring decision thresholds are transferable across model upgrades.
- **$H_5$ (Fairness Parity Constraint):** Under demographically matched impostor evaluation, the worst demographic subgroup error rates do not exceed $2.0\times$ overall FNMR and $3.0\times$ overall FMR at the operating threshold.
- **$H_6$ (1:N Sub-Millisecond Search):** In-memory 128-D cosine indexing maintains $100.0\%$ top-k candidate parity with exhaustive brute force while achieving sub-millisecond query time ($\le 2\text{ms}$) up to $N = 10,000$ identities.

---

## 3. Evaluated Model Candidates

| Candidate ID | Model Architecture | Weights Source / SHA-256 | License | Tier Status | Input Contract |
|:---|:---|:---|:---:|:---:|:---:|
| **`sface_fp32`** | SFace ResNet-20 (OpenCV Zoo) | `0ba9fbfa01b5270c...` | Apache-2.0 | **PRIMARY PRODUCTION** | 112x112 RGB [0..255] float |
| **`sface_int8`** | SFace Quantized INT8 | `2b0e941e6f16cc04...` | Apache-2.0 | **FALLBACK PRODUCTION** | 112x112 RGB [0..255] float |
| **`mfn_research`** | MobileFaceNet (Random export) | `cde3799f041eca6a...` | Internal / No Data | **RESEARCH ONLY** | 112x112 RGB [0..255] float |
| **`arcface_r50`** | ArcFace ResNet-50 (InsightFace) | External Reference | Non-Commercial | **EVAL-ONLY (BLOCKED)** | 112x112 BGR / RGB norm |
| **`adaface_ir50`** | AdaFace IR-50 | External Reference | MIT / MS1MV2 Data | **EVAL-ONLY (BLOCKED)** | 112x112 RGB [-1..1] |
| **`magface_r50`** | MagFace ResNet-50 | External Reference | Apache-2.0 / MS1MV2 | **EVAL-ONLY (BLOCKED)** | 112x112 RGB |
| **`edgeface_xs`** | EdgeFace-XS (Mobile) | External Reference | Apache-2.0 | **EVAL-ONLY (BLOCKED)** | 112x112 RGB |

---

## 4. Primary Metrics & Numeric Pass/Fail Gates

| Gate ID | Metric Description | Mathematical Definition | Minimum Passing Threshold |
|:---:|:---|:---|:---:|
| **GATE-01** | Verification TAR at FAR = $10^{-3}$ | $\text{TAR} = 1 - \text{FNMR at } \text{FMR} \le 0.001$ | $\ge 95.0\%$ |
| **GATE-02** | Equal Error Rate (EER) | Operating point where $\text{FMR} = \text{FNMR}$ | $\le 2.0\%$ |
| **GATE-03** | Quantization Parity Loss | $\Delta\text{TAR} = \text{TAR}_{\text{FP32}} - \text{TAR}_{\text{INT8}}$ at FAR=$10^{-3}$ | $\le 0.8\%$ |
| **GATE-04** | Calibration Loss ($C_{llr}$) | Log-likelihood ratio cost metric | $C_{llr} \le 0.150$ |
| **GATE-05** | Demographic FNMR Disparity | $\max_g(\text{FNMR}_g) / \text{FNMR}_{\text{overall}}$ | $\le 2.0\times$ |
| **GATE-06** | Demographic FMR Disparity | $\max_g(\text{FMR}_g) / \text{FMR}_{\text{overall}}$ (Demographically matched) | $\le 3.0\times$ |
| **GATE-07** | Forward Inference Latency (p95) | Single-image latency on CPU (Concurrency 1) | $\le 100\text{ ms}$ |
| **GATE-08** | Numerical Parity vs. Golden Vector | Cosine similarity between repeated runs | $\ge 0.99999$ |
| **GATE-09** | 1:N Top-K Candidate Parity | $\text{Top-3 Candidate Overlap with Brute Force}$ | $\mathbf{100.0\%}$ |

---

## 5. Partitioning Strategy (Zero Identity Overlap)

To prevent data leakage and optimistic bias, data is strictly split by **subject identity** into three mutually exclusive sets:

```
[Available Dataset Identities]
       │
       ├─► 40% Identities ──► [TUNE PARTITION]
       │                         ├─ Threshold Search (FMR 1e-3, 1e-4)
       │                         ├─ LLR Calibration (Logistic / Isotonic)
       │                         ├─ Score Normalization Cohort (S-norm)
       │                         ├─ Fusion Weight Optimization
       │                         └─ Quality Gate Calibration
       │
       ├─► 40% Identities ──► [VALIDATE PARTITION]
       │                         ├─ Model Candidate Screen & Bake-Off
       │                         ├─ Component Ablations (Detectors, Aligners)
       │                         ├─ Test-Time Augmentation (Flip-TTA)
       │                         └─ Cross-Architecture Selection
       │
       └─► 20% Identities ──► [LOCKBOX PARTITION]
                                 ├─ Untouched during development
                                 ├─ Manifest SHA-256 pre-committed
                                 ├─ Single evaluation of final chosen pipeline
                                 └─ Access logged immutably
```

### Contamination & Data Overlap Disclosure
Modern face recognition models trained on large web-scraped datasets (CASIA-WebFace, MS1MV2/MS-Celeb-1M, Glint360k, WebFace42M) carry known identity overlap with public academic benchmarks (LFW, CFP-FP, AgeDB-30, IJB-C). Any reported benchmark accuracy on these sets reflects a ceiling that incorporates training-evaluation contamination. Real-world deployed error rates on sovereign Karnataka cohorts must be assumed to be substantially higher until measured directly on un-contaminated in-domain data.

---

## 6. Statistical Engine & Multiplicity Control

1. **Identity-Level Cluster Bootstrap:** Resampling is performed with replacement at the **subject/identity level** (not pair level) with $B = 2,000$ iterations to produce empirical 95% confidence intervals $[Q_{0.025}, Q_{0.975}]$.
2. **Paired Comparisons:** When comparing Model A vs. Model B, paired bootstrap evaluates the distribution of $\Delta = \text{Score}_A - \text{Score}_B$ on identical identity clusters.
3. **Holm-Bonferroni Correction:** When testing multiple candidate models against the primary baseline, $p$-values are sorted ascendingly $p_{(1)} \le p_{(2)} \le \dots \le p_{(m)}$ and evaluated against adjusted significance levels $\alpha / (m - k + 1)$ with family-wise error rate $\alpha = 0.05$.
4. **Rule of Three Sample Bounds:**
   - To statistically observe error rates at $\text{FAR} = 10^{-4}$ with at least 30 errors: $N_{\text{impostor}} \ge 300,000$ comparisons.
   - Where dataset size is insufficient, the metric is mathematically reported as an upper bound:
     $$\text{Error Rate} \le \frac{3}{N} \quad (\text{at } 95\% \text{ confidence})$$

---

## 7. Stopping Rules & Amendment Log

- No hyperparameter, threshold, or model selection may be altered after LOCKBOX access.
- If a pre-registered gate fails, the failure must be declared as a negative result; gates may not be relaxed post-hoc.
- Amendments are permitted only prior to LOCKBOX evaluation and must state the timestamp, rationale, and exact modified parameters.
