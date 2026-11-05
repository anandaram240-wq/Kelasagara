# PHASE 20.6 DATA TYPE CLASSIFICATION
## Mandatory Categorization and Separation of Evaluation Data Types

**Project:** Kelasagara Major Project  
**System:** Worker Marketplace & Biometric Identity Platform  
**Phase:** 20.6 (Biometric Evidence Integrity & Controlled Pilot Readiness)  
**Standard:** ISO/IEC 19795-1:2021 & Scientific Integrity Directive  

---

## 1. THE SIX MANDATORY DATA TYPE CLASSIFICATIONS

To prevent test fixtures or synthetic mathematical vectors from ever being misrepresented as empirical human recognition performance, Kelasagara enforces six mutually exclusive data classifications:

```
┌───────────────────────────────────────────────────────────────────────────────────────────────┐
│                           MANDATORY EVALUATION DATA CLASSIFICATIONS                           │
├───────────────────────────────────┬───────────────────────────────────┬───────────────────────┤
│ Classification Category           │ Permitted Use                     │ Prohibited Claim      │
├───────────────────────────────────┼───────────────────────────────────┼───────────────────────┤
│ 1. REAL_CONSENTED_HUMAN_DATA      │ Empirical FMR/FNMR, ROC, FIQA     │ Must NOT lack consent │
│ 2. SYNTHETIC_VECTOR_TEST          │ Algorithmic formulas, CI, ROC     │ CANNOT claim human acc│
│ 3. MOCKED_PIPELINE_TEST           │ Integration wiring, error paths   │ CANNOT claim liveness │
│ 4. BENCHMARK_FIXTURE              │ Partition logic, schema parsing   │ CANNOT claim real data│
│ 5. PHYSICAL_ATTACK_PRESENTATION   │ ISO 30107-3 APCER / BPCER         │ CANNOT mix w/ software│
│ 6. UNVERIFIED_SOURCE              │ Discovery, unverified archives    │ BLOCKED from report   │
└───────────────────────────────────┴───────────────────────────────────┴───────────────────────┘
```

---

## 2. DETAILED CLASSIFICATION DEFINITIONS

### 1. `REAL_CONSENTED_HUMAN_DATA`
- **Definition:** Physical raw image frames captured from consenting human participants under approved research protocols, accompanied by verified cryptographic consent records and physical camera sensor metadata.
- **Reporting Rights:** Authorizes empirical biometric accuracy reporting (FMR, FNMR, FPIR, FNIR).

### 2. `SYNTHETIC_VECTOR_TEST`
- **Definition:** High-dimensional mathematical vectors generated via pseudorandom algorithms (e.g. SHA-256 spherical projection or Gram-Schmidt orthogonalization) to test linear algebra, hypersphere geometry, or scoring algorithms.
- **Reporting Rights:** Permitted for software unit verification and mathematical calculation correctness. Strictly prohibited from claiming real-world human face recognition accuracy.

### 3. `MOCKED_PIPELINE_TEST`
- **Definition:** In-memory mocks of downstream services (e.g. `MockCloudKmsProvider`, `MockPlayIntegrityService`, simulated HTTP endpoints) used to verify API routing and failure state handling.
- **Reporting Rights:** Permitted for regression and architectural invariant checks. Prohibited from being aggregated into real-world latency or throughput measurements.

### 4. `BENCHMARK_FIXTURE`
- **Definition:** Programmatically constructed dataset manifests (such as `createCanonicalEvaluationManifest()`) used to test partitioning rules, sample indexing, and schema validity.
- **Reporting Rights:** Verifies software pipeline logic. Cannot be claimed as an empirical corpus of human subjects.

### 5. `PHYSICAL_ATTACK_PRESENTATION_TEST`
- **Definition:** Physical presentations made to an active camera sensor using genuine physical attack instruments (e.g. printed paper, curved masks, display screens).
- **Reporting Rights:** Authorizes ISO/IEC 30107-3 PAD error metric reporting (APCER, BPCER). Must never be conflated with software API injection attacks.

### 6. `UNVERIFIED_SOURCE`
- **Definition:** Any biometric dataset, file archive, or third-party sample whose chain of custody, sensor metadata, or consent documentation cannot be independently verified.
- **Reporting Rights:** Automatically fails closed; completely blocked from publishing empirical claims.

---

## 3. AUDIT MAPPING OF KELASAGARA TEST SUITES

Every test suite in the Kelasagara repository is now explicitly mapped to its appropriate classification:

| Test Suite / Source File | Operational Category | Empirical Human Accuracy Claims? |
| :--- | :--- | :--- |
| `backend/src/tests/phase20_5_biometric_validation.test.ts` | `SYNTHETIC_VECTOR_TEST` & `BENCHMARK_FIXTURE` | **STRICTLY PROHIBITED** |
| `backend/src/tests/phase20_6_evidence_integrity.test.ts` | `BENCHMARK_FIXTURE` | **STRICTLY PROHIBITED** |
| `backend/src/tests/test_play_integrity_binding.test.ts` | `MOCKED_PIPELINE_TEST` | **STRICTLY PROHIBITED** |
| `backend/src/tests/test_device_key_attestation.test.ts` | `MOCKED_PIPELINE_TEST` | **STRICTLY PROHIBITED** |
| `flutter test test/biometric*` | `MOCKED_PIPELINE_TEST` | **STRICTLY PROHIBITED** |
| Future Controlled Research Pilot (Phase 20.6.10) | `REAL_CONSENTED_HUMAN_DATA` | **PERMITTED (Upon Verification)** |

---

## 4. SCIENTIFIC REPORTING ENFORCEMENT

The evaluation engine enforces separation at compile time and runtime:
1. `DatasetManifest.dataSourceType` must match one of the six valid types.
2. `BenchmarkReportGenerator.generateReport()` inspects `dataSourceType`. If it is not `REAL_CONSENTED_HUMAN_DATA`, the report is forced into `SYNTHETIC_PIPELINE_BENCHMARK` mode, and `empiricalHumanAccuracyClaimsAllowed` is locked to `false`.
3. Calling `BenchmarkReportGenerator.generateEmpiricalHumanAccuracyReport()` on synthetic data throws a runtime `PROVENANCE_ERROR`.
