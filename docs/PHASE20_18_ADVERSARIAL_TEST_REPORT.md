# KELASAGARA V20.18 — ADVERSARIAL TEST REPORT
## Comprehensive Execution Metrics for the 45-Test Pilot Readiness Corrections Suite

**Author:** Principal QA Architect, Security Verification Engineer  
**Date:** 2026-11-01  
**Repository:** `kelasagaara_v17`  
**Test Suite:** `backend/src/tests/phase20_18_pilot_readiness_corrections.test.ts`  
**Execution Command:** `node --test dist/tests/phase20_18_pilot_readiness_corrections.test.js`  
**Status:** **45 / 45 PASSED (100% SUCCESS RATE)**  

---

### 1. Executive Summary

Phase 20.18 introduces 45 dedicated adversarial test cases validating:
1. **Track A: Plan Execution Environment & Supply-Chain Attestation (Tests 1–10)**
2. **Track B: Workload Identity & Durable Replay Protection (Tests 11–20)**
3. **Track C: Vault Decryption Isolation & Best-Effort Memory Clearing (Tests 21–30)**
4. **Track D: Two-Person Dual Custody Recovery Assurance (Tests 31–38)**
5. **Track E: Audit Notary Create-Only & Reconciler Independence (Tests 39–45)**

All 45 tests executed cleanly in 1,049 ms with zero failures, zero retries, and zero timeouts.

---

### 2. Comprehensive Test Execution Breakdown

#### Track A: Plan Execution Environment & Supply-Chain Attestation (Tests 1–10)
| # | Test Scenario | Asserted Defense | Duration | Result |
| :-: | :--- | :--- | :-: | :-: |
| 1 | Injected `TF_CLI_ARGS_plan` | Rejected before launch (`ERR_PROHIBITED_ENV_VAR`) | 0.83 ms | **PASS** |
| 2 | Injected unapproved workspace (`prod`) | Rejected (`ERR_UNAPPROVED_WORKSPACE`) | 0.47 ms | **PASS** |
| 3 | Alternate CLI config (`.terraformrc`) | Rejected (`ERR_ALTERNATE_CLI_CONFIG`) | 0.49 ms | **PASS** |
| 4 | Unexpected variable injection (`TF_VAR_*`) | Rejected (`ERR_UNAPPROVED_TF_ENV_VAR`) | 0.10 ms | **PASS** |
| 5 | Unapproved CLI flag (`-target`) | Rejected (`ERR_PROHIBITED_CLI_FLAG`) | 0.31 ms | **PASS** |
| 6 | Modified plan binary | Apply gate detects SHA-256 mismatch (`ERR_PLAN_DIGEST_MISMATCH`) | 293.9 ms | **PASS** |
| 7 | Modified manifest signature | Apply gate rejects invalid signature (`ERR_MANIFEST_SIGNATURE_INVALID`) | 227.6 ms | **PASS** |
| 8 | Different OpenTofu executable digest | Apply gate rejects binary drift (`ERR_TOOLCHAIN_MISMATCH`) | 219.4 ms | **PASS** |
| 9 | Provider lock digest verified | Digest is 64-char SHA-256 string | 0.26 ms | **PASS** |
| 10 | Unauthorized apply (rejected policy) | Rejected by gate (`ERR_PLAN_NOT_APPROVED`) | 216.7 ms | **PASS** |

#### Track B: Workload Identity & Durable Replay Protection (Tests 11–20)
| # | Test Scenario | Asserted Defense | Duration | Result |
| :-: | :--- | :--- | :-: | :-: |
| 11 | Incorrect audience | Rejected with `ERR_AUDIENCE_MISMATCH` | 0.80 ms | **PASS** |
| 12 | Incorrect issuer | Rejected with `ERR_INVALID_TOKEN_ISSUER` | 0.24 ms | **PASS** |
| 13 | Expired token | Rejected with `ERR_INTERNAL_TOKEN_EXPIRED` | 0.17 ms | **PASS** |
| 14 | Invalid signature | Rejected with `ERR_INVALID_TOKEN_SIGNATURE` | 0.47 ms | **PASS** |
| 15 | Forged principal header | Rejected with `ERR_FORGED_PRINCIPAL_HEADER` | 0.06 ms | **PASS** |
| 16 | JTI missing | Accepted when valid claims and signature are present | 0.40 ms | **PASS** |
| 17 | Token reuse with unique nonce | Accepted across multiple distinct requests | 0.41 ms | **PASS** |
| 18 | Durable replay rejection | Replayed nonce blocked with `ERR_DURABLE_REQUEST_REPLAY` | 0.40 ms | **PASS** |
| 19 | Replay across two instances | Shared durable store blocks concurrent invocation | 0.43 ms | **PASS** |
| 20 | Replay after process restart | Persisted store preserves consumed nonces across restart | 0.47 ms | **PASS** |

#### Track C: Vault Decryption Isolation & Best-Effort Memory Clearing (Tests 21–30)
| # | Test Scenario | Asserted Defense | Duration | Result |
| :-: | :--- | :--- | :-: | :-: |
| 21 | Wrong UID in AAD | Fails decipher (`AUTHENTICATION_TAG_VERIFICATION_FAILED`) | 0.64 ms | **PASS** |
| 22 | Wrong template ID in AAD | Fails decipher (`AUTHENTICATION_TAG_VERIFICATION_FAILED`) | 0.15 ms | **PASS** |
| 23 | Wrong vault version in AAD | Fails decipher (`AUTHENTICATION_TAG_VERIFICATION_FAILED`) | 0.21 ms | **PASS** |
| 24 | Wrong embedding space | Rejected before decryption (`EMBEDDING_SPACE_MISMATCH`) | 0.06 ms | **PASS** |
| 25 | Modified wrapped DEK | Rejected by KMS unwrap (`KMS_UNWRAP_FAILED`) | 0.10 ms | **PASS** |
| 26 | Modified ciphertext | Fails AES-GCM tag verification | 0.13 ms | **PASS** |
| 27 | Modified authentication tag | Fails AES-GCM tag verification | 0.10 ms | **PASS** |
| 28 | Superseded template | Rejected before KMS call (`LIFECYCLE_GATE_REJECTED`) | 0.06 ms | **PASS** |
| 29 | Revoked template | Rejected before KMS call (`LIFECYCLE_GATE_REJECTED`) | 0.06 ms | **PASS** |
| 30 | Pre-KMS session mismatch | Blocked before KMS unwrap (`UNAUTHORIZED_RECORD_ACCESS`) | 0.10 ms | **PASS** |

#### Track D: Two-Person Dual Custody Recovery Assurance (Tests 31–38)
| # | Test Scenario | Asserted Defense | Duration | Result |
| :-: | :--- | :--- | :-: | :-: |
| 31 | Same officer twice | Blocked with `ERR_DUAL_CUSTODY_SAME_OFFICER` | 0.49 ms | **PASS** |
| 32 | Same IdP subject twice | Blocked with `ERR_DUAL_CUSTODY_SAME_IDP_SUBJECT` | 0.49 ms | **PASS** |
| 33 | Distinct BCO + ISA with separate MFA | Accepted with valid auditRecordId | 0.69 ms | **PASS** |
| 34 | Requester self-approval | Blocked with `ERR_REQUESTER_SELF_APPROVAL` | 0.39 ms | **PASS** |
| 35 | Replayed approval | Consumed token rejected with `ERR_RECOVERY_TOKEN_REPLAYED` | 0.54 ms | **PASS** |
| 36 | Expired approval (>15 min) | Rejected with `ERR_RECOVERY_TOKEN_EXPIRED` | 0.32 ms | **PASS** |
| 37 | Modified operation | Context mismatch blocked (`ERR_OPERATION_TYPE_MISMATCH`) | 0.32 ms | **PASS** |
| 38 | Concurrent consumption | Atomically locked; exactly one succeeds | 0.52 ms | **PASS** |

#### Track E: Audit Notary Create-Only & Reconciler Independence (Tests 39–45)
| # | Test Scenario | Asserted Defense | Duration | Result |
| :-: | :--- | :--- | :-: | :-: |
| 39 | Duplicate checkpoint name | Rejected with `ERR_PRECONDITION_FAILED_OBJECT_EXISTS` | 0.15 ms | **PASS** |
| 40 | Checkpoint overwrite attempt | Precondition `ifGenerationMatch=0` blocks overwrite | 0.36 ms | **PASS** |
| 41 | Invalid signature on checkpoint | Flagged during reconciliation (`SIGNATURE_INVALID`) | 0.30 ms | **PASS** |
| 42 | Missing checkpoint in sequence | Flagged as chain gap (`CHAIN_DISCONTINUITY`) | 0.47 ms | **PASS** |
| 43 | Notary read/delete attempt | Blocked by `roles/storage.objectCreator` boundary | 0.14 ms | **PASS** |
| 44 | Reconciler write attempt | Blocked by `roles/storage.objectViewer` boundary | 0.05 ms | **PASS** |
| 45 | Firestore ledger mutation | Detected against signed checkpoints (`HISTORICAL_REWRITE`) | 0.14 ms | **PASS** |

---

### 3. Master Regression Suite Summary

- **Phase 20.18 Suite:** 45 / 45 PASSED (1,049 ms)
- **Phase 20.17 Suite:** 50 / 50 PASSED (1,086 ms)
- **Flutter Client Suite:** 12 / 12 PASSED (2,000 ms)
- **Android Gradle Task Evaluation:** BUILD SUCCESSFUL in 16s
- **Zero regressions detected.**
