# KELASAGARA DUPLICATE THRESHOLD AUDIT REPORT
## EVALUATION OF THREE-ZONE DECISION BOUNDARIES AND SOFTWARE DEFECT REPAIR

**Phase:** Biometric Enrollment Hotfix  
**Branch:** `security/hotfix-canonical-face-preprocessing`  
**Classification:** Decision Policy & Threshold Governance  
**Date:** November 1, 2026  
**Auditors:** Biometric Statistical Evaluation Specialist, Principal Biometric Systems Architect

---

## 1. THRESHOLD SYSTEM CONFIGURATION

The Kelasagara V10 biometric architecture defines three operational thresholds in `CalibrationPolicyThresholdsV10`:

```typescript
export const DEFAULT_CANDIDATE_THRESHOLDS_V10: CalibrationPolicyThresholdsV10 = {
  verify1to1Min: 0.363,      // Lower bound for 1:1 genuine eKYC verification
  dedupCleanMax: 0.363,      // Upper bound of Clean Zone (< 0.363 -> No duplicate)
  dedupAmbiguousMax: 0.550,  // Intermediate calibration boundary
  dedupHardBlockMin: 0.720,  // Lower bound of High-Confidence Duplicate Zone (>= 0.720)
  isEmpiricallyValidatedForProduction: false,
};
```

---

## 2. THE THREE CANONICAL DECISION ZONES

```
 0.000                     0.363                   0.720                     1.000
   ├─────────────────────────┼───────────────────────┼─────────────────────────┤
   │       ZONE 1            │        ZONE 2         │         ZONE 3          │
   │     CLEAN ZONE          │    AMBIGUOUS ZONE     │     DUPLICATE ZONE      │
   │                         │                       │                         │
   │  Max Similarity < 0.363 │ 0.363 <= Sim < 0.720  │   Max Similarity >= 0.720
   │  Classification:        │ Classification:       │ Classification:         │
   │  UNIQUE APPLICANT       │ AMBIGUOUS_MATCH       │ FACE_ALREADY_LINKED     │
   │  HTTP: 200 / 201        │ HTTP: 202             │ HTTP: 409               │
   │  Action:                │ Action:               │ Action:                 │
   │  Commit enrollment to   │ Log case to review    │ Block enrollment.       │
   │  biometric_vault        │ queue. Do not commit. │ Return opaque case ref. │
```

---

## 3. AUDIT OF THE SOFTWARE THRESHOLD INVERSION BUG

### Defect Identified in Source Code
In `backend/src/services/biometric_lifecycle_coordinator_v10.ts` lines 460–469 (pre-hotfix):
```typescript
const duplicateFloor = (topHit?.comparisonSpace === 'LEGACY_LANDMARK_SPACE')
  ? (topHit?.calibratedThreshold ?? 0.88)
  : this.thresholds.dedupAmbiguousMax; // <-- DEFECT: 0.550 was assigned!

if (maxSim >= cleanFloor) {
  const isDuplicateBlock = maxSim >= duplicateFloor;
  const rejectionCode: StructuredBiometricCode = isDuplicateBlock
    ? 'FACE_ALREADY_LINKED'
    : 'AMBIGUOUS_MATCH';
```

### Analysis of the Defect
1. `dedupAmbiguousMax` (0.550) was erroneously used as the threshold for `isDuplicateBlock`.
2. As a result, any applicant whose facial similarity score was $\ge 0.550$ was treated as a confirmed duplicate and blocked with HTTP 409 `FACE_ALREADY_LINKED`.
3. The true high-confidence duplicate floor, `dedupHardBlockMin` (0.720), was completely bypassed in code.
4. Candidates in the ambiguous review band ($0.550 \le s < 0.720$) were denied the right to administrative human review under DPDPA §8(3) and ISO/IEC 19795.

### Software Correction Applied
In `backend/src/services/biometric_lifecycle_coordinator_v10.ts`:
```typescript
const cleanFloor = (topHit?.comparisonSpace === 'LEGACY_LANDMARK_SPACE')
  ? 0.80
  : this.thresholds.dedupCleanMax; // 0.363

const duplicateFloor = (topHit?.comparisonSpace === 'LEGACY_LANDMARK_SPACE')
  ? (topHit?.calibratedThreshold ?? 0.88)
  : this.thresholds.dedupHardBlockMin; // 0.720 [CORRECTED]
```

---

## 4. VERIFICATION EVIDENCE

- **Regression Test 29:** Proves scores $< 0.363$ fall strictly in Clean Zone (PASS).
- **Regression Test 30:** Proves score $0.450$ ($0.363 \le s < 0.720$) yields `AMBIGUOUS_MATCH` (HTTP 202, NOT 409) (PASS).
- **Regression Test 31:** Proves score $0.850 \ge 0.720$ yields `FACE_ALREADY_LINKED` (HTTP 409) (PASS).
- **Regression Test 32:** Explicitly verifies that intermediate scores (e.g. $0.600$) do NOT trigger a hard 409 block (PASS).
