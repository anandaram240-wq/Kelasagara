# PHASE 20.11: SYNTHETIC REGRESSION TEST REPORT
**Role:** Biometric Quality Assurance Engineer & Data Integrity Auditor  
**System:** Kelasagara Multi-Factor Biometric Identity Platform  
**Branch:** `security/phase20.11-legacy-template-isolation`  
**Test File:** `backend/src/tests/phase20_11_legacy_template_isolation.test.ts`  
**Date:** November 1, 2026  

---

## 1. EXECUTIVE TEST SUMMARY

A total of 33 specialized regression tests across 7 test suites were authored and executed against the Phase 20.11 codebase. In addition, the full backend regression suite (913 tests across 199 suites) was executed without a single failure or regression.

| Test Category | Tests Planned | Tests Executed | Tests Passed | Tests Failed | Execution Time |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Workstream B: Embedding Space Spec** | 2 | 2 | 2 | 0 | 0.45 ms |
| **Workstream A: Template Classification** | 4 | 4 | 4 | 0 | 0.39 ms |
| **Workstream F: Runtime Safety & Validation** | 6 | 6 | 6 | 0 | 65.32 ms |
| **Workstream D: Threshold Boundary Tests** | 10 | 10 | 10 | 0 | 0.29 ms |
| **Workstream G: Case Reference Security** | 2 | 2 | 2 | 0 | 2.38 ms |
| **Workstream H: End-to-End Scenarios 1–10** | 9 | 9 | 9 | 0 | 22.15 ms |
| **Phase 20.11 Master Suite Total** | **33** | **33** | **33** | **0** | **91.46 ms** |
| **Full Repository Backend Suite** | **913** | **913** | **913** | **0** | **23.12 s** |

---

## 2. DETAILED SCENARIO REGRESSION BREAKDOWN

### Scenario 1: Orthogonal Faces in Clean Zone
- **Input:** Two orthogonal canonical 128-D vectors ($L_2$ normalized).
- **Cosine Similarity:** $0.0000 < 0.3630$.
- **Outcome:** PASS — Maps strictly to Clean Zone (HTTP 200/201).

### Scenario 2: Correlated Variations in Hard Block Zone
- **Input:** High-correlation canonical face vectors.
- **Cosine Similarity:** $0.7845 \ge 0.7200$.
- **Outcome:** PASS — Maps strictly to Hard Duplicate Block Zone (HTTP 409).

### Scenario 3: Intermediate Similarity in Review Zone
- **Input:** Intermediate candidate vector.
- **Cosine Similarity:** $0.5200 \in [0.3630, 0.7200)$.
- **Outcome:** PASS — Maps strictly to Ambiguous Review Zone (HTTP 202) without hard-blocking.

### Scenario 4 & 5: Gallery Isolation (Cross-Space Evasion Defense)
- **Input:** Canonical V2 probe queried against mixed gallery containing:
  - `enr_legacy_landmark_1` (Legacy landmark space)
  - `enr_defective_sface_2` (Defective full-photo resize)
  - `enr_unknown_3` (Unknown legacy record)
  - `enr_canonical_v2_4` (Canonical V2 record)
- **Outcome:** PASS — Candidates 1, 2, and 3 were filtered out by `INCOMPATIBLE_EMBEDDING_SPACE = NEVER_COMPARE` before computing cosine similarity. Only candidate 4 was evaluated. Zero false duplicate errors.

### Scenario 6: Authorized Replacement & Template Upgrade
- **Input:** Existing user with legacy template undergoes re-enrollment with secondary auth proof.
- **Outcome:** PASS — Legacy record atomically superseded (`status: 'SUPERSEDED'`) and replaced by active Canonical V2 record.

### Scenario 7: Malformed / Unaligned Image Runtime Rejection
- **Input:** Raw unaligned JPEG buffer passed to `CanonicalAlignedFace112Factory.create()`.
- **Outcome:** PASS — Rejected with typed `BiometricPreprocessingError: INVALID_BYTE_LENGTH`.

### Scenario 8: Exhaustive Floating-Point Boundary Tests
- **Input:** Boundaries at $0.3629, 0.3630, 0.3631, 0.5499, 0.5500, 0.5501, 0.7199, 0.7200, 0.7201$.
- **Outcome:** PASS — Every boundary matched its exact designated zone.

### Scenario 9: Privacy Leak Elimination
- **Input:** Hard duplicate response payload inspection.
- **Outcome:** PASS — Zero PII fields present (`maskedOriginalName`, `maskedOriginalPhone`, `primarySkill`, `maskedUid` undefined). Valid `CASE-XXXXXXXX` reference present.

### Scenario 10: In-Memory Mixed Gallery Space Isolation
- **Input:** In-memory array of mixed-space templates.
- **Outcome:** PASS — Filtered strictly to `CANONICAL_V2` records.
