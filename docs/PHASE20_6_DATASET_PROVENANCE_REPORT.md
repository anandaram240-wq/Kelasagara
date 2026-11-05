# PHASE 20.6 DATASET PROVENANCE REPORT
## Exhaustive Forensic Audit of Empirical Source Data vs Programmatic Fixtures

**Project:** Kelasagara Major Project  
**System:** Worker Marketplace & Biometric Identity Platform  
**Phase:** 20.6 (Biometric Evidence Integrity & Controlled Pilot Readiness)  
**Lead Investigator:** Principal Biometric Research Engineer & Independent Statistical Auditor  
**Date:** 2026-10-31  

---

## 1. INVESTIGATION OBJECTIVE

Phase 20.5 reported empirical biometric accuracy metrics for the Kelasagara SFace face recognition and YuNet detection pipeline based on an evaluation corpus described as:
- 50 consented human participants (`SUBJ-A-01` .. `SUBJ-C-25`).
- 450 multi-frame burst capture sessions (3 frames per burst = 1,350 total raw frames).
- 300 genuine matching pairs and 300 impostor matching pairs.
- 100 non-enrolled probe queries and 100 duplicate candidate probes.
- 120 presentation attacks across 8 attack instrument species.
- 150 bona fide presentations.

In accordance with Phase 20.6 research directives, an independent physical inspection of the repository, local filesystem, and data stores was conducted to establish the provenance of these observations.

---

## 2. PHYSICAL DISK AUDIT FINDINGS

An exhaustive search across the entire project root (`/Users/ananda/KELASAGARA MAJOR PROJECT`) and repository (`kelasagaara_v17`) was executed targeting image files (`.jpg`, `.jpeg`, `.png`, `.bmp`, `.tiff`), raw byte streams, and biometric feature archives:

```bash
# Forensic Search Commands:
find /Users/ananda/KELASAGARA\ MAJOR\ PROJECT -name "*.jpg" -o -name "*.jpeg"
find /Users/ananda/KELASAGARA\ MAJOR\ PROJECT/kelasagaara_v17 -name "*.png"
```

### Audit Findings:
1. **Zero Raw Facial Images on Disk:** There are **zero** raw human facial capture frames in the workspace. The only images in the repository are web assets (`web/favicon.png`, `web/icons/Icon-*.png`).
2. **Zero Physical Session Bundles:** No directory containing 450 multi-frame burst captures (`1,350` frames) exists on disk.
3. **No External Research Store:** No local SQLite database, parquet archive, or binary vector store containing 50 physical human subject captures is present.

---

## 3. PROVENANCE OF THE V20.5 EVALUATION CORPORE

Forensic code inspection of `backend/src/biometric-evaluation/dataset_manifest.ts` and `backend/src/tests/phase20_5_biometric_validation.test.ts` reveals the exact provenance of the evaluation data:

### A. Programmatic Metadata Generation (`dataset_manifest.ts`):
The 50 participant records (`SUBJ-A-01` to `SUBJ-C-25`) and 450 sample records (`SMP-0001` to `SMP-0450`) were generated dynamically by the function `createCanonicalEvaluationManifest()`:
```typescript
for (const part of partitions) {
  for (let i = 1; i <= part.count; i++) {
    const pId = `${part.prefix}-${String(i).padStart(2, '0')}`;
    participants.push({
      participantId: pId,
      partition: part.name,
      consentDocumentId: `CONSENT-HASH-${part.prefix}-${i}`,
      ...
    });
    // Programmatic generation of 3 sessions and 3 frames per session
  }
}
```
The records are in-memory TypeScript objects, not serialized records of actual physical human beings who sat before a camera.

### B. Synthetic Vector Generation (`phase20_5_biometric_validation.test.ts`):
The comparison embeddings evaluated in the test suite were generated programmatically using cryptographic SHA-256 hash projections onto the 128-dimensional unit hypersphere:
```typescript
function generateUnitVector(seed: number, dim = 128): Float32Array {
  const v = new Float32Array(dim);
  for (let i = 0; i < dim; i++) {
    const hash = createHash('sha256').update(`${seed}:${i}`).digest();
    v[i] = hash.readInt16LE(0) / 32768.0;
  }
  // L2 unit normalization: ||v||2 = 1.0
  ...
}
```
Genuine pairs were created via Gram-Schmidt spherical interpolation:
```typescript
function generateControlledGenuinePair(seed: number, targetSimilarity: number): [Float32Array, Float32Array] {
  // v2 = theta * v1 + sqrt(1 - theta^2) * v_perp
}
```

---

## 4. SCIENTIFIC EVIDENCE CLASSIFICATION

Based on physical evidence, the evaluation results must be rigorously classified:

| Evaluation Component | V20.5 Reported Claim | Actual Evidence Provenance | Honest Scientific Classification |
| :--- | :--- | :--- | :--- |
| **Manifest Pipeline** | 50 Subjects, 450 Samples | Programmatic TypeScript Generator | `BENCHMARK_FIXTURE` |
| **Image Frames** | 1,350 Raw Frames | 0 Physical Image Files on Disk | `UNVERIFIED_SOURCE` |
| **SFace ROC/AUC** | AUC = 0.9984, EER = 1.50% | Evaluated on SHA-256 Spherically Interpolated Vectors | `VERIFIED_SYNTHETIC` |
| **1:1 FMR / FNMR** | FMR = 0.00%, FNMR = 0.00% | Evaluated on Synthetic Hypersphere Pairs | `VERIFIED_SYNTHETIC` |
| **1:N FPIR / FNIR** | FPIR = 0.00%, FNIR = 0.00% | Evaluated on 30 Synthetic Gallery Entries | `VERIFIED_SYNTHETIC` |
| **PAD APCER / BPCER**| APCER = 1.67%, BPCER = 2.67%| Mocked Attack Presentations | `MOCKED_PIPELINE_TEST` |
| **Demographic Fairness**| Disparity Ratio 1.00 ± 0.06 | Mocked Subgroup Inputs ($N=50$) | `INSUFFICIENT_SAMPLE` |

---

## 5. GATE DECISION

In strict accordance with international scientific integrity standards and Phase 20.6 instructions:
> *"If the underlying source data does not exist or cannot be verified, classify the associated metric as UNVERIFIED. Never generate missing human data. Never substitute synthetic vectors for real biometric samples. Never claim that test fixtures establish human biometric accuracy."*

### Empirical Acceptance Gate Status: **BLOCKED**
- **Algorithmic Correctness:** The statistical formulas, Clopper-Pearson confidence interval logic, ROC calculation, and partition validators are **VERIFIED** as mathematically sound software implementations.
- **Empirical Biometric Accuracy:** Human biometric accuracy claims (e.g. "0.00% FMR on human subjects") are **UNVERIFIED** due to absence of physical source frames.
- **Remediation:** Implementation of Phase 20.6 Provenance Reporting Guard in `BenchmarkReportGenerator` to strictly disallow publishing human accuracy claims from synthetic fixtures.
