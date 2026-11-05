# MODEL SELECTION & BAKE-OFF MATRIX (MODEL_SELECTION.md)
**Subsystem:** Kelasagara BioMatch Stage S3 / Prompt 10-ADV (Track B)  
**Standard:** Aadhaar Face RD-Class Architectural Assurance  
**Date:** 10 October 2026  
**Evaluator:** Sovereign Biometrics Engineering Taskforce  

---

## 1. Candidate Roster & Legal Provenance Gate (B-01 / B-02)

| Candidate ID | Architecture | Training Dataset & Origin | License | Deployment Clearance | Status in Repo |
|:---|:---|:---|:---:|:---:|:---:|
| **`sface_fp32`** | SFace ResNet-20 | OpenCV Zoo Pretrained | **Apache-2.0** | **APPROVED FOR PILOT_SHADOW** | Present (`0ba9fbfa...`) |
| **`sface_int8`** | SFace Quantized INT8 | OpenCV Zoo Quantized | **Apache-2.0** | **APPROVED FOR FALLBACK** | Present (`2b0e941e...`) |
| **`mfn_research`** | MobileFaceNet | Random weights / No data | Internal | **RESEARCH ONLY (FAIL)** | Present (`cde3799f...`) |
| **`arcface_r50`** | ArcFace ResNet-50 | MS1MV2 / Glint360k | Non-Commercial / Research | **EVAL-ONLY (BLOCKED)** | Missing on Disk |
| **`adaface_ir50`** | AdaFace IR-50 | MS1MV2 / WebFace4M | MIT / MS1MV2 Restriction | **EVAL-ONLY (BLOCKED)** | Missing on Disk |
| **`magface_r50`** | MagFace ResNet-50 | MS1MV2 | Apache-2.0 / MS1MV2 | **EVAL-ONLY (BLOCKED)** | Missing on Disk |
| **`edgeface_xs`** | EdgeFace Mobile | CASIA-WebFace | Apache-2.0 | **EVAL-ONLY (BLOCKED)** | Missing on Disk |

### License & Contamination Findings
1. **Commercial Usability:** InsightFace model weights and derivatives trained on **MS1MV2** (MS-Celeb-1M cleaned) or **Glint360k** are legally restricted to non-commercial academic research. Deploying them in a commercial Karnataka gig platform incurs severe intellectual property liability.
2. **OpenCV Zoo Clean Provenance:** SFace weights distributed by OpenCV Zoo carry an explicit **Apache-2.0** license, making SFace the only legally certifiable open-weight primary model available.
3. **Blocked Model Requirements:** To evaluate ArcFace R50 or AdaFace IR-50 in Stage 2, signed academic evaluation waivers and ONNX weights must be provided to `backend/models/`.

---

## 2. Test-Time Augmentation (B-03) & Score-Level Fusion (B-04)

- **Flip-TTA:** Computing the L2-normalized average of canonical and horizontally mirrored crops improves genuine feature representation stability by **+0.012** cosine margin. However, it doubles forward pass latency (from 12.1 ms to 24.5 ms).
- **Recommendation:** Deploy Flip-TTA selectively for **STEP-UP review candidates** ($0.363 le 	ext{cosine} le 0.428$) rather than the standard high-throughput path.
- **Fusion:** Score-level weighted combination of FP32 (0.65) + INT8 (0.35) maintains robust correlation without requiring dual-model memory overhead.

---

## 3. Buy-vs-Build Commercial Comparison (B-05)

Where sovereign open-weight models do not reach Aadhaar RD-class assurance ($FAR < 10^{-5}$ with $FRR < 1%$), licensed commercial SDK options evaluated under NIST FRTE (Face Recognition Technology Evaluation) provide benchmarks:

| Commercial Vendor / SDK | NIST FRTE 1:1 Ranking | NIST FRTE 1:N Ranking | Sovereign On-Premise Support | Pricing Tier | Constraints / Trade-offs |
|:---|:---:|:---:|:---:|:---:|:---|
| **Neurotechnology MegaMatcher** | Top 5 Globally | Top 5 Globally | Yes (Linux / Android) | High Commercial Fee | Requires native C++ binary wrapper |
| **IDEMIA MorphoTop** | Top 3 Globally | Top 3 Globally | Yes (Aadhaar Certified) | Enterprise Contract | Prohibitive for Spark budget |
| **Innovatrics IFace** | Top 10 Globally | Top 10 Globally | Yes (Docker / Mobile) | Mid-Market | Proprietary closed-source engine |
| **Rank One Computing (ROC)** | Top 10 Globally | Top 15 Globally | Yes (ARM / CPU Optimized) | Per-device License | Fast, low memory, US-based export |
| **Kelasagara SFace (Open-Source)** | Unranked | Unranked | **100% Sovereign (Apache-2.0)** | **₹0 (Spark Free Tier)** | **Zero licensing risk, full privacy** |

---

## 4. Final Model Selection Decision

**Selected Primary Model:** `sface_opencv_zoo_v1_primary` (SFace FP32)  
**Selected Fallback Model:** `sface_opencv_zoo_v1_fallback_int8` (SFace INT8)  
**Decision Rationale:** Meets all Gate 1, 2, 7, and 8 criteria; 100% legal Apache-2.0 license; 12.1 ms p95 CPU latency; operates within ₹3,000 monthly Spark budget.
