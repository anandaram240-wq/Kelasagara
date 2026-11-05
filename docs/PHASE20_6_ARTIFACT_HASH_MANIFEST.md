# PHASE 20.6 ARTIFACT HASH MANIFEST
## Cryptographic Integrity Manifest for Models and Evaluation Modules

**Project:** Kelasagara Major Project  
**Phase:** 20.6 (Biometric Evidence Integrity & Controlled Pilot Readiness)  
**Verification Date:** 2026-10-31  

---

## 1. NEURAL MODEL ARTIFACTS

The following table lists the exact SHA-256 cryptographic digests of all biometric neural models deployed in `backend/models/`:

| Artifact Name | Framework | Input Geometry | Output Vector | SHA-256 Digest | Status |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `face_detection_yunet_2023mar.onnx` | ONNX | `[1, 3, 300, 300]` | BBox + 5 Landmarks | `8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4` | VERIFIED |
| `face_recognition_sface_2021dec.onnx` | ONNX | `[1, 3, 112, 112]` | `[1, 128]` unit float32 | `0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79` | VERIFIED |
| `face_recognition_sface_2021dec_int8.onnx` | ONNX INT8 | `[1, 3, 112, 112]` | `[1, 128]` quant float32 | `2b0e941e6f16cc048c20aee0c8e31f569118f65d702914540f7bfdc14048d78a` | STANDBY |
| `kelasagara_mobilefacenet.onnx` | ONNX | `[1, 3, 112, 112]` | `[1, 128]` float32 | `cde3799f041eca6a6a99bfac53d9e97eb81ff34ac450d519aa41a9c99bef7d7c` | REFERENCE |

---

## 2. BIOMETRIC EVALUATION SOURCE MODULES

Cryptographic SHA-256 digests of all 12 evaluation engine modules under `backend/src/biometric-evaluation/`:

| Module Path | Primary Responsibility | SHA-256 Digest |
| :--- | :--- | :--- |
| `dataset_manifest.ts` | Dataset schema, partition definitions, and corpus verification | `1ce2cbe2300ee79ee5eef501bc586326e792942d99d14ec866df7b2d56a29f8f` |
| `participant_split_validator.ts` | Cross-partition subject-level leakage detection | `e6096f72ca933dcfe6b01b838e0816186937618c8a0f2e6e7c5b31c5b674fe17` |
| `confidence_interval_calculator.ts` | Clopper-Pearson exact binomial CIs, one-sided upper bounds, and clustering | `88c2f1f0a2846fe684be7604313b8606c1ec589574da9e47265bc7e7741d8e03` |
| `image_quality_evaluator.ts` | ISO/IEC 29794-5 FIQA metrics, IPD, sharpness, and FTA/FTE | `9ca95fa1bc787cf10f6ac22dcebddacea0254b44fcf9c57fd761b77b954f3a51` |
| `genuine_pair_generator.ts` | Intra-subject multi-session comparison pair generation | `aab339c8150d7521745100e30a3b9a1b1e9e920df006b2d4bac75c96fe3c340e` |
| `impostor_pair_generator.ts` | Inter-subject comparison pair generation with cluster tracking | `a5f1dd31f0c3c3bfd6d1d56ec6a8c5eea0e50cd84a9adfac564c88589fed9579` |
| `sface_score_collector.ts` | Full $[-1.0, 1.0]$ ROC sweep, DET, EER, and AUC integration | `efcb736b1d5136ff694d1480f36626ce99240e59840357b63d8e0c55821c76c9` |
| `one_to_one_evaluator.ts` | 1:1 eKYC authentication and model mismatch rejection | `96c6a88caa00202d161b86621cb639749d05cb3352bc29582475db495008de32` |
| `one_to_n_evaluator.ts` | 1:N deduplication, FPIR, FNIR, and Rank-1 identification | `9ed2753f5987ff16932eb692fc51cda48cbb451713aa8c25eec04f911ca97c78` |
| `pad_evaluator.ts` | ISO/IEC 30107-3 APCER/BPCER presentation attack detection | `6da1caef075627ceea7d1fc103af39bb10a1cbbf1454cb141838bb24134f9068` |
| `fairness_evaluator.ts` | ISO/IEC 19795-10 demographic parity and sample size warning | `4cf53abcd33ffd2d3663499633f1d08c33c636deca4fb7e9f7539699ce1df8cc` |
| `benchmark_report_generator.ts` | Provenance-guarded scientific benchmark report generator | `25531d04130097a8ec28876c1dc110f089679f18e95267123aa12d7c5ee3ce78` |

---

## 3. PROTECTED RELEASE BINARY

| Binary | Location | SHA-256 Digest |
| :--- | :--- | :--- |
| `Kelasagara-v19.2.3-release.apk` | Workspace Root | `739f85746df3cd1fb6c315590147907918a3829976d0381b8eae358c743176ce` |
