# PHASE 20.5 REPRODUCIBLE EVALUATION PIPELINE
## Architecture and Execution Guide for the Automated Biometric Benchmark Pipeline

**Project:** Kelasagara Major Project  
**System:** Worker Marketplace & Multi-Factor Biometric Identity Platform  
**Phase:** 20.5 (Advanced Biometric Scientific Validation Engine)  
**Parent Phase 20.4 Commit:** `41f95bf66bd09cda8ea63d3483e567b06ba6504e`  

---

## 1. COMPONENT ARCHITECTURE (`backend/src/biometric-evaluation/`)

The evaluation pipeline is modularized into 12 decoupled, typed TypeScript components:

```
backend/src/biometric-evaluation/
├── dataset_manifest.ts               # Manifest schema, participant metadata, capture specs
├── participant_split_validator.ts    # Enforces 3-way partition isolation (zero leakage)
├── image_quality_evaluator.ts        # ISO 29794-5 FIQA, blur, IPD, pose, FTA/FTE
├── genuine_pair_generator.ts         # Generates intra-subject cross-session/camera pairs
├── impostor_pair_generator.ts        # Generates inter-subject pairs with subject clustering
├── sface_score_collector.ts          # Computes cosine similarity, FMR, FNMR, ROC, AUC, EER
├── one_to_one_evaluator.ts           # 1:1 eKYC verification and edge case simulator
├── one_to_n_evaluator.ts             # 1:N gallery deduplication, FPIR, FNIR, Rank-1
├── pad_evaluator.ts                  # ISO 30107-3 PAD evaluation, APCER, BPCER across PAIs
├── confidence_interval_calculator.ts # Clopper-Pearson exact & cluster-adjusted intervals
├── fairness_evaluator.ts             # Subgroup disparity ratios and fairness metrics
└── benchmark_report_generator.ts     # Generates reproducible JSON/MD benchmark summaries
```

---

## 2. REPRODUCIBLE EXECUTION INSTRUCTIONS

To execute the scientific validation pipeline and verify all invariants:

```bash
cd "/Users/ananda/KELASAGARA MAJOR PROJECT/kelasagaara_v17/backend"

# 1. Compile TypeScript modules
npm run build

# 2. Run dedicated Phase 20.5 scientific evaluation suite
node --test dist/tests/phase20_5_biometric_validation.test.js

# 3. Run full platform regression including cryptographic trust and biometrics
npm test
```

### Invariants Enforced
- **Zero Production Mutations**: The pipeline never writes to production Firestore collections.
- **Deterministic Evaluation**: Given identical input seeds, pairwise scores and ROC metrics reproduce identically down to the 8th decimal place.
- **No Embedded Images**: Raw facial images are excluded from output artifacts.
