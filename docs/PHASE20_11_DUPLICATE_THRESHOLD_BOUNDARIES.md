# PHASE 20.11: DUPLICATE THRESHOLD BOUNDARIES & FLOATING-POINT AUDIT
**Role:** Biometric Statistical Evaluation Specialist & Security Auditor  
**System:** Kelasagara Multi-Factor Biometric Identity Platform  
**Branch:** `security/phase20.11-legacy-template-isolation`  
**Date:** November 1, 2026  

---

## 1. DEDUPLICATION THRESHOLD ARCHITECTURE

The Kelasagara SFace deduplication engine partitions candidate cosine similarities into three deterministic zones:

```
0.0000                      0.3630                      0.7200                      1.0000
  │                           │                           │                           │
  ├───────────────────────────┼───────────────────────────┼───────────────────────────┤
  │        CLEAN ZONE         │  AMBIGUOUS REVIEW ZONE    │    HARD DUPLICATE BLOCK   │
  │     (HTTP 200 / 201)      │        (HTTP 202)         │        (HTTP 409)         │
  │  No duplicate candidate   │  Manual review requested  │  Duplicate registration   │
  │  Registration proceeds    │  Case reference issued    │  Registration rejected    │
```

---

## 2. FLOATING-POINT BOUNDARY AUDIT RESULTS

Unit boundary tests were performed with floating-point values at the critical transition points:

| Boundary Value | Zone Classification | HTTP Status | Biometric Lifecycle State | Verification Outcome |
| :--- | :--- | :--- | :--- | :--- |
| `0.3629` | **CLEAN ZONE** | `200 / 201` | `ACTIVE` | **PASS:** Registration proceeds without case issuance |
| `0.3630` | **AMBIGUOUS REVIEW** | `202` | `REVIEW_REQUIRED` | **PASS:** Issues `CASE-XXXXXXXX` reference, non-blocking review |
| `0.3631` | **AMBIGUOUS REVIEW** | `202` | `REVIEW_REQUIRED` | **PASS:** Issues `CASE-XXXXXXXX` reference, non-blocking review |
| `0.5499` | **AMBIGUOUS REVIEW** | `202` | `REVIEW_REQUIRED` | **PASS:** Remains in review zone |
| `0.5500` | **AMBIGUOUS REVIEW** | `202` | `REVIEW_REQUIRED` | **PASS:** Remains in review zone |
| `0.5501` | **AMBIGUOUS REVIEW** | `202` | `REVIEW_REQUIRED` | **PASS:** Remains in review zone |
| `0.7199` | **AMBIGUOUS REVIEW** | `202` | `REVIEW_REQUIRED` | **PASS:** Strictly below hard block floor |
| `0.7200` | **HARD DUPLICATE BLOCK** | `409` | `UNENROLLED` | **PASS:** Blocks duplicate account registration (`FACE_ALREADY_LINKED`) |
| `0.7201` | **HARD DUPLICATE BLOCK** | `409` | `UNENROLLED` | **PASS:** Blocks duplicate account registration (`FACE_ALREADY_LINKED`) |

---

## 3. HISTORICAL CONTEXT OF 0.550

In early V10 calibration policies, the value `0.550` was labeled `dedupAmbiguousMax`. In an earlier implementation defect in `BiometricLifecycleCoordinatorV10`, `duplicateFloor` was incorrectly assigned to `this.thresholds.dedupAmbiguousMax` (0.550) rather than `this.thresholds.dedupHardBlockMin` (0.720).

This error had the catastrophic effect of completely eliminating the ambiguous review zone $[0.550, 0.720)$:
- Any similarity score $\ge 0.550$ was treated as a hard duplicate block (HTTP 409).
- When combined with unaligned full-photo resizing (which generated inter-subject background noise around $0.49 - 0.56$), innocent applicants were routinely blocked.

The hotfix and Phase 20.11 restored `duplicateFloor` to `0.720`, ensuring that the entire interval $[0.3630, 0.7200)$ functions correctly as the human review zone.
