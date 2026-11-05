# PHASE 20.5 THRESHOLD INVENTORY
## Comprehensive Multi-Space Biometric Decision Boundary Inventory

**Project:** Kelasagara Major Project  
**System:** Worker Marketplace & Multi-Factor Biometric Identity Platform  
**Phase:** 20.5 (Advanced Biometric Scientific Validation Engine)  
**Parent Phase 20.4 Commit:** `41f95bf66bd09cda8ea63d3483e567b06ba6504e`  

---

## 1. MULTI-SPACE THRESHOLD MATRIX

Kelasagara operates with separate similarity spaces: `SFACE_NEURAL_SPACE` (128-D unit hypersphere) and `LEGACY_LANDMARK_SPACE` (geometric contours). These thresholds are fundamentally non-comparable across spaces:

```
┌───────────────────────────────────────────────────────────────────────────────────────────────┐
│                               DECISION THRESHOLD INVENTORY                                    │
├────────────────────┬─────────────────────┬───────────┬────────┬───────────┬───────────────────┤
│ Metric Name        │ Comparison Space    │ Direction │ Mode   │ Threshold │ Calling Service   │
├────────────────────┼─────────────────────┼───────────┼────────┼───────────┼───────────────────┤
│ Verification Floor │ SFACE_NEURAL_SPACE  │ Higher=Sim│ 1:1    │ 0.363     │ BiometricMatching │
│ Duplicate Warning  │ SFACE_NEURAL_SPACE  │ Higher=Sim│ 1:N    │ 0.740     │ GalleryIndex / V10│
│ Duplicate Hit/Block│ SFACE_NEURAL_SPACE  │ Higher=Sim│ 1:N    │ 0.780     │ GalleryIndex / V10│
│ Hard Block Ceiling │ SFACE_NEURAL_SPACE  │ Higher=Sim│ 1:N    │ 0.900     │ BiometricMatching │
│ Ambiguity Window   │ SFACE_NEURAL_SPACE  │ Higher=Sim│ 1:N    │ [0.65,0.74│ BiometricMatching │
│ Landmark Floor     │ LEGACY_LANDMARK_SPC │ Higher=Sim│ 1:N    │ 0.800     │ GalleryIndex / V10│
│ Landmark Duplicate │ LEGACY_LANDMARK_SPC │ Higher=Sim│ 1:N    │ 0.880     │ GalleryIndex / V10│
│ FIQA Min IPD       │ Pixel Geometry      │ Higher=Res│ Quality│ 75.0 px   │ FIQAGuardV11      │
│ FIQA Blur Min      │ Laplacian Variance  │ Higher=Shp│ Quality│ 110.0     │ TemporalPadVal    │
│ FIQA Blur Max      │ Laplacian Variance  │ Lower=Norm│ Quality│ 1800.0    │ TemporalPadVal    │
│ FIQA Min Luma      │ Photometric Mean    │ Higher=Brt│ Quality│ 35.0      │ TemporalPadVal    │
│ FIQA Max Luma      │ Photometric Mean    │ Lower=Dim │ Quality│ 220.0     │ TemporalPadVal    │
│ PAD Blink Ratio    │ Eye Aspect Ratio    │ Lower=Clsd│ PAD    │ <= 0.65x  │ ChallengeBurstPad │
│ PAD Open Eye Floor │ Eye Aspect Ratio    │ Higher=Opn│ PAD    │ >= 0.22   │ ChallengeBurstPad │
│ PAD Luma Flux Max  │ Photometric Delta   │ Lower=Stbl│ PAD    │ <= 0.15   │ ChallengeBurstPad │
│ PAD Anchor Cosine  │ SFace Inter-Frame   │ Higher=Sim│ PAD    │ >= 0.80   │ ChallengeBurstPad │
└────────────────────┴─────────────────────┴───────────┴────────┴───────────┴───────────────────┘
```

---

## 2. DETAILED THRESHOLD SPECIFICATIONS

### 1. `VERIFICATION_THRESHOLD = 0.363`
- **Matching Space:** `SFACE_NEURAL_SPACE`
- **Operation:** 1:1 Authentication (eKYC).
- **Direction:** Cosine similarity $\ge 0.363 \implies \text{Match}$.
- **Source:** Published reference operating threshold from OpenCV Zoo SFace 2021dec on LFW/CALFW benchmarks.
- **Decision:** Authenticates enrolled worker against their own reference template.

### 2. `DUPLICATE_WARNING_THRESHOLD = 0.74`
- **Matching Space:** `SFACE_NEURAL_SPACE`
- **Operation:** 1:N Duplicate Discovery during registration.
- **Direction:** Cosine similarity $\ge 0.74 \implies \text{Advisory Warning / Ambiguity Hold}$.
- **Decision:** Flags candidate for secondary human review or step-up ownership verification; does NOT automatically block.

### 3. `DUPLICATE_BLOCK_THRESHOLD = 0.78 / 0.90`
- **Matching Space:** `SFACE_NEURAL_SPACE`
- **Operation:** 1:N Duplicate Interception.
- **Direction:** Cosine similarity $\ge 0.78 \implies \text{Duplicate Hit}$; $\ge 0.90 \implies \text{Hard Block}$.
- **Decision:** Rejects creation of unlinked duplicate worker account. Prompts duplicate resolution flow (`CASE-XXXX`).

### 4. `LEGACY_LANDMARK_THRESHOLD = 0.88`
- **Matching Space:** `LEGACY_LANDMARK_SPACE`
- **Operation:** Legacy geometric contour fallback.
- **Direction:** Cosine similarity $\ge 0.88 \implies \text{Duplicate}$.
- **Isolation Invariant:** Never compared across spaces via `Math.max()`. Metrics in landmark space are handled strictly inside their own evaluation branch.
