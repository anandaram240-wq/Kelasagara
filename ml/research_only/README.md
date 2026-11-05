# WARNING: RESEARCH-ONLY MODEL EXPORT SCRIPTS
**Status:** STRICTLY RESEARCH / NON-PRODUCTION  
**Compliance Mandate:** Invariant I-01, I-02, I-18  
**Defect Resolved:** Defect D5 (Ticket T-16)

---

## CRITICAL NOTICE: RANDOM / UNTRAINED WEIGHT HAZARD

The script `export_mobilefacenet_onnx.py` located in this directory generates a MobileFaceNet ONNX graph with randomly initialized weights (or untrained checkpoints) unless a pre-trained, licensed, and empirically calibrated checkpoint is explicitly provided.

### Invariant Rules:
1. **Never Load into Production:** Models exported with uncalibrated random weights possess zero genuine facial identity discrimination (AUC ≈ 0.50, random guessing).
2. **Never Grant Automated Clearance:** Any model tagged as `RESEARCH_ONLY` is rejected at registry startup from ever issuing an `isApproved: true` decision.
3. **Pilot Recognition Standard:** Authoritative production pilot recognition is served strictly by OpenCV Zoo SFace (`sface_opencv_zoo_v1_primary` with FP32 weights SHA-256 `0ba9fbfa...` and INT8 fallback SHA-256 `2b0e941e...`).
