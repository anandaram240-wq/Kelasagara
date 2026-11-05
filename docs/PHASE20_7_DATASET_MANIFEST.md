# PHASE 20.7: CONTROLLED BIOMETRIC DATASET MANIFEST SPECIFICATION
**System:** Kelasagara Biometric Identity & Authentication Platform  
**Phase:** 20.7 (Controlled Physical Biometric Validation & PAD Hardening)  
**Schema Version:** 1.0.0-PROSPECTIVE  
**Author:** Biometric Dataset Governance Specialist & Senior TypeScript Engineer  
**Date:** November 2026  
**Status:** SPECIFICATION DEFINED (Execution Gated Pending IEC Approval)

---

## 1. Overview & Partition Architecture

To ensure unimpeachable statistical rigor, prevent data leakage, and guarantee that testing reflects genuine unseen operational distributions, the Kelasagara Phase 20.7 physical validation dataset is structured into four **strictly disjoint participant cohorts** comprising $N = 50$ total subjects.

Under no circumstances may subjects or feature vectors from one cohort be mixed into another.

```
+--------------------------------------------------------------------------------------------------+
|                           TOTAL POPULATION: 50 PARTICIPANTS (100% DISJOINT)                      |
+--------------------------------------------------------------------------------------------------+
   |                               |                               |                             |
   v                               v                               v                             v
+------------------+    +--------------------+    +-------------------+    +--------------------+
|     COHORT A     |    |      COHORT B      |    |     COHORT C      |    |      COHORT D      |
| Calibration &    |    | 1:1 eKYC           |    | 1:N Enrolled      |    | Non-Enrolled       |
| Parameter Tuning |    | Verification       |    | Gallery (Dedup)   |    | Probes (Novel)     |
|                  |    |                    |    |                   |    |                    |
| N = 10 Subjects  |    | N = 20 Subjects    |    | N = 15 Subjects   |    | N = 5 Subjects     |
| 20% Population   |    | 40% Population     |    | 30% Population    |    | 10% Population     |
| 90 Captures      |    | 180 Captures       |    | 135 Captures      |    | 45 Captures        |
| 450 Vector Frames|    | 900 Vector Frames  |    | 675 Vector Frames |    | 225 Vector Frames  |
+------------------+    +--------------------+    +-------------------+    +--------------------+
```

---

## 2. Cohort Definitions and Isolation Rules

### 2.1. Cohort A: Algorithm Calibration & Parameter Tuning ($N = 10$)
- **Participant Identifiers:** `SUBJ-CAL-001` through `SUBJ-CAL-010`
- **Purpose:** Hyperparameter tuning for candidate PAD high-frequency spectral thresholds, corneal curvature cutoffs, and facial quality filtering.
- **Isolation Constraint:** Never used for reporting reported verification accuracy (FMR/FNMR) or deduplication metrics.

### 2.2. Cohort B: 1:1 eKYC Verification Benchmark ($N = 20$)
- **Participant Identifiers:** `SUBJ-VER-001` through `SUBJ-VER-020`
- **Purpose:** Independent evaluation of 1:1 eKYC authentication against the production SFace cosine similarity threshold $\theta_{\text{verify}} = 0.363$.
- **Test Structure:**
  - **Genuine Pairs:** Session 1 (Enrollment) vs. Session 2–9 (Subsequent Verification) for the same subject ($M_{\text{genuine}} = 160$ comparisons).
  - **Impostor Pairs:** Cross-subject pair matching across different identities ($M_{\text{impostor}} = 380$ comparisons).

### 2.3. Cohort C: 1:N Enrolled Gallery for Deduplication ($N = 15$)
- **Participant Identifiers:** `SUBJ-GAL-001` through `SUBJ-GAL-015`
- **Purpose:** Primary gallery population for 1:N biometric de-duplication testing.
- **Structure:** 15 distinct identities enrolled with multi-frame centroid feature vectors into the isolated evaluation gallery.

### 2.4. Cohort D: Non-Enrolled Impostor / Novel Probe Identities ($N = 5$)
- **Participant Identifiers:** `SUBJ-NOVEL-001` through `SUBJ-NOVEL-005`
- **Purpose:** Testing true non-enrolled false positive identification rate (FPIR).
- **Structure:** 5 distinct subjects completely absent from Cohort C gallery. Probes are submitted to verify they trigger zero false-positive duplicate flags ($\max(\text{similarity}) < 0.74$).

---

## 3. Dataset Record Schema (TypeScript Interface)

```typescript
export interface BiometricDatasetRecord {
  /** Unique session identifier */
  sessionId: string; // UUIDv4

  /** Disjoint cohort assignment */
  cohort: 'COHORT_A' | 'COHORT_B' | 'COHORT_C' | 'COHORT_D';

  /** Anonymized subject identifier */
  subjectId: string; // e.g. "SUBJ-VER-012"

  /** Capture sequence number for subject (1 to 9) */
  sequenceNumber: number;

  /** Standardized lighting condition */
  lightingRegime: 'L1_DIFFUSE' | 'L2_SUNLIGHT' | 'L3_LOW_LIGHT' | 'L4_SIDELIGHT' | 'L5_BACKLIT';

  /** Ground-truth measured lux at nose tip */
  measuredLux: number;

  /** Optical capture distance category */
  distanceCategory: 'D1_NEAR_25CM' | 'D2_CANONICAL_45CM' | 'D3_FAR_65CM';

  /** Optical capture distance measured (cm) */
  measuredDistanceCm: number;

  /** Evaluated presentation type */
  presentationType: 'BONA_FIDE_LIVE' | 'PAI_1_MATTE' | 'PAI_2_GLOSSY' | 'PAI_3_OLED' | 'PAI_4_TABLET' | 'PAI_5_CURVED';

  /** SHA-256 hash of the 128-D float32 SFace feature vector */
  sfaceVectorSha256: string;

  /** Extracted 128-D L2-normalized feature vector (stored in memory during eval, encrypted in vault) */
  embedding128D: number[];

  /** High-frequency electronic display grid energy score [0.0 - 1.0] */
  displayGridEnergy: number;

  /** Active chromatic specular corneal curvature delta [0.0 - 1.0] */
  cornealCurvatureDelta: number;

  /** Facial landmark detection confidence (YuNet) */
  faceConfidence: number;

  /** Inter-pupillary distance in pixels (IPD) */
  ipdPixels: number;

  /** Laplacian variance sharpness score */
  laplacianSharpness: number;

  /** Cryptographic hash of the executed consent agreement */
  consentAgreementHash: string;

  /** ISO 8601 UTC timestamp of acquisition */
  timestampUtc: string;
}
```

---

## 4. Privacy, Anonymization & Data Hygiene Rules

1. **Zero Raw Image Storage:**
   No photographic imagery, video frames, uncompressed bitmaps, or lossy compressed JPEGs may be written to disk. All raw frames reside in volatile RAM buffers and are zeroized immediately following SFace vector extraction.
2. **Deterministic Pseudonymization:**
   Subject names, phone numbers, email addresses, and Aadhaar numbers are strictly decoupled. The cross-reference ledger is stored on an encrypted, air-gapped physical drive in the custody of the Principal Investigator.
3. **Immutability & Checksum Ledger:**
   The entire dataset manifest is exported as an append-only JSON Lines file (`manifest.jsonl`), with a companion SHA-256 manifest integrity signature:
   $$\text{Checksum} = \text{SHA-256}(\text{manifest.jsonl})$$
   Any modification, reordering, or tampering with records alters the checksum and invalidates the audit suite.
