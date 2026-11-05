# PHASE 20.5 THRESHOLD CHANGE PROPOSAL
## Formal Governance Review: Threshold Preservation vs Modification Decision

**Project:** Kelasagara Major Project  
**System:** Worker Marketplace & Multi-Factor Biometric Identity Platform  
**Phase:** 20.5 (Advanced Biometric Scientific Validation Engine)  
**Parent Phase 20.4 Commit:** `41f95bf66bd09cda8ea63d3483e567b06ba6504e`  

---

## 1. PROPOSAL EVALUATION

The research team investigated whether to propose altering the baseline decision thresholds for Phase 20.6:

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                       THRESHOLD PROPOSAL COMPARISON                             │
├──────────────────────┬──────────────────┬──────────────────┬────────────────────┤
│ Operating Parameter  │ Current Baseline │ Proposed Tuning  │ Governance Action  │
├──────────────────────┼──────────────────┼──────────────────┼────────────────────┤
│ 1:1 Verification     │ 0.363            │ 0.400            │ REJECTED (Keep 0.363│
│ 1:N Duplicate Warning│ 0.740            │ 0.740            │ APPROVED (Preserve)│
│ 1:N Duplicate Block  │ 0.780            │ 0.780            │ APPROVED (Preserve)│
│ 1:N Hard Block       │ 0.900            │ 0.900            │ APPROVED (Preserve)│
│ Ambiguity Window     │ [0.65, 0.74)     │ [0.65, 0.74)     │ APPROVED (Preserve)│
└──────────────────────┴──────────────────┴──────────────────┴────────────────────┘
```

---

## 2. FORMAL JUSTIFICATION FOR REJECTING THRESHOLD CHANGE

1. **Absence of Observed Impostor Leakage**: Zero impostors passed the existing $0.363$ verification floor across all partitions (0/300 holdout, 0/200 calibration). Raising the threshold provides zero empirical security improvement on the tested corpus.
2. **Protection Against Demographic FNMR Spikes**: Volunteers presenting in difficult lighting conditions (backlit windows, low lux) achieved genuine similarities between $0.76$ and $0.81$. While safely above $0.363$, raising the threshold prematurely could inadvertently impact disadvantaged workers operating in poor lighting environments.
3. **Strict University Baseline Constraint**: The directive explicitly mandates: "Do not modify existing matching thresholds during baseline testing."

---

## 3. GOVERNANCE CONCLUSION
**DECISION: PRESERVE THE FROZEN BASELINE THRESHOLDS.**
The current threshold hierarchy (0.363 verify, 0.74 warning, 0.78 block, 0.90 hard block) is formally approved and locked for the final submission release.
