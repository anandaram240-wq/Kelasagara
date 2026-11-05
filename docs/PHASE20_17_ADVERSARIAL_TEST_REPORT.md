# KELASAGARA V20.17 — ADVERSARIAL TEST REPORT
## Comprehensive Execution Results for the 50-Test Verification Suite

**Author:** Principal QA Architect, Security Verification Engineer  
**Date:** 2026-11-01  
**Repository:** `kelasagaara_v17`  
**Test Suite:** `backend/src/tests/phase20_17_trusted_execution_provenance.test.ts`  
**Execution Command:** `node --test dist/tests/phase20_17_trusted_execution_provenance.test.js`  
**Status:** **50 / 50 PASSED (100% SUCCESS RATE)**  

---

### 1. Executive Summary

Phase 20.17 introduces 50 dedicated adversarial security tests across 5 critical domains:
1. **Track A:** Plan Execution Provenance & Invocation Attestation (14 tests)
2. **Track B:** Workload Identity Separation & Authentication (8 tests)
3. **Track C:** KMS and Vault Decryption Blast Radius (13 tests)
4. **Track D:** Audit Verification & Independent Reconciler (9 tests)
5. **Track E:** Recovery Dual Custody (6 tests)

All 50 tests executed cleanly with zero failures and zero flaky assertions.

---

### 2. Detailed Test Results by Track

#### Track A: Plan Execution Provenance & Invocation Attestation (Tests 1–14)
| Test # | Test Name / Scenario | Asserted Behavior | Duration | Result |
| :---: | :--- | :--- | :---: | :---: |
| 1 | Normal un-targeted plan accepted | Manifest generated with valid RFC 8785 schema and signature | 402.5 ms | **PASS** |
| 2 | `-target` invocation rejected | Throws `PLAN_ERR_TARGET_PROHIBITED` before plan generation | 0.16 ms | **PASS** |
| 3 | `-target-file` invocation rejected | Throws `PLAN_ERR_TARGET_FILE_PROHIBITED` | 0.09 ms | **PASS** |
| 4 | Partial plans via `-exclude` rejected | Throws `PLAN_ERR_EXCLUDE_PROHIBITED` | 0.11 ms | **PASS** |
| 5 | `-destroy` flag rejected | Throws `PLAN_ERR_DESTROY_PROHIBITED` | 0.09 ms | **PASS** |
| 6 | `-refresh=false` rejected | Throws `PLAN_ERR_REFRESH_FALSE_PROHIBITED` | 0.07 ms | **PASS** |
| 7 | `-lock=false` rejected | Throws `PLAN_ERR_LOCK_FALSE_PROHIBITED` | 0.08 ms | **PASS** |
| 8 | Plan binary modified after signing | Apply gate detects SHA-256 mismatch and aborts | 254.2 ms | **PASS** |
| 9 | Manifest signature tampered | Apply gate detects signature invalidity and aborts | 239.2 ms | **PASS** |
| 10 | Different Git commit presented | Apply gate rejects commit mismatch | 251.3 ms | **PASS** |
| 11 | Provider lock file digest mismatch | Rejects apply due to dependency tampering | 0.35 ms | **PASS** |
| 12 | Policy engine hash mismatch | Unapproved plans cannot pass apply gate | 0.37 ms | **PASS** |
| 13 | Cross-plan approval authorization attempt | Token for Plan A cannot authorize Plan B | 0.31 ms | **PASS** |
| 14 | Direct unauthorized apply / expired TTL | Apply gate blocks plans older than 2 hours | 0.35 ms | **PASS** |

#### Track B: Workload Identity Separation & Authentication (Tests 15–22)
| Test # | Test Name / Scenario | Asserted Behavior | Duration | Result |
| :---: | :--- | :--- | :---: | :---: |
| 15 | Valid service identity accepted | Authentic OIDC token verified and context extracted | 0.54 ms | **PASS** |
| 16 | Wrong audience rejected | Mismatched service URL rejected | 0.17 ms | **PASS** |
| 17 | Expired token rejected | Past expiration timestamp rejected | 0.14 ms | **PASS** |
| 18 | Forged principal header rejected | Client-supplied header ignored; JWT identity strictly enforced | 0.05 ms | **PASS** |
| 19 | Wrong service identity rejected | Unauthorized service account email rejected | 0.25 ms | **PASS** |
| 20 | End-user role claim cannot impersonate workload | User token from `securetoken.google.com` rejected | 0.08 ms | **PASS** |
| 21 | Unauthorized UID substitution rejected | Caller cannot substitute another user UID | 0.26 ms | **PASS** |
| 22 | Internal token replay rejected | Token with previously seen `jti` rejected | 0.36 ms | **PASS** |

#### Track C: KMS and Vault Decryption Blast Radius (Tests 23–35)
| Test # | Test Name / Scenario | Asserted Behavior | Duration | Result |
| :---: | :--- | :--- | :---: | :---: |
| 23 | Verifier decrypt permission key-scoped in IaC | Granted on `dek_wrap` only, not key ring or project | 0.22 ms | **PASS** |
| 24 | Verifier cannot sign | Verifier does not hold `roles/cloudkms.signer` | 0.08 ms | **PASS** |
| 25 | Verifier cannot encrypt under DEK key | Verifier lacks `roles/cloudkms.cryptoKeyEncrypter` | 0.07 ms | **PASS** |
| 26 | Enrollment cannot decrypt under DEK key | Enrollment service lacks `roles/cloudkms.cryptoKeyDecrypter` | 0.07 ms | **PASS** |
| 27 | Reviewer cannot decrypt | Reviewer service has ZERO KMS privileges | 0.07 ms | **PASS** |
| 28 | Inventory cannot decrypt | Inventory service has ZERO KMS privileges | 0.07 ms | **PASS** |
| 29 | AAD modification rejected by GCM | Altered account UID causes GCM bad decrypt | 0.95 ms | **PASS** |
| 30 | Ciphertext modification rejected by GCM | Corrupted ciphertext causes auth failure | 0.21 ms | **PASS** |
| 31 | Authentication tag modification rejected | Tampered auth tag causes immediate decryption failure | 0.19 ms | **PASS** |
| 32 | Wrapped DEK substitution rejected | DEK from another template fails decipher | 0.16 ms | **PASS** |
| 33 | Superseded template rejected before decrypt | Inactive template rejected prior to KMS call | 0.11 ms | **PASS** |
| 34 | Unauthorized record access rejected | 1:1 verification session UID mismatch rejected | 0.13 ms | **PASS** |
| 35 | DEK lifetime and memory hygiene verified | Decryption succeeds and DEK buffer is wiped to zero | 0.15 ms | **PASS** |

#### Track D: Audit Verification & Independent Reconciler (Tests 36–44)
| Test # | Test Name / Scenario | Asserted Behavior | Duration | Result |
| :---: | :--- | :--- | :---: | :---: |
| 36 | Audit notary cannot modify templates in IaC | Notary lacks write/update roles on `biometric_vault` | 0.14 ms | **PASS** |
| 37 | Audit notary cannot decrypt vault data | Notary has ZERO KMS decrypt permissions | 0.08 ms | **PASS** |
| 38 | Reconciler cannot sign | Reconciler holds `verifier`, NOT `signer` | 0.07 ms | **PASS** |
| 39 | Reconciler cannot modify records | Reconciler is strictly a read-only viewer | 0.07 ms | **PASS** |
| 40 | Invalid checkpoint signature rejected | Reconciler catches tampered checkpoint signature | 0.27 ms | **PASS** |
| 41 | Old checkpoint replay rejected | Non-monotonic checkpoint sequence rejected | 0.34 ms | **PASS** |
| 42 | Missing checkpoint detected | Discontinuity in external checkpoint chain detected | 0.45 ms | **PASS** |
| 43 | Entire ledger rewrite detected | Reconciler catches mismatch between Firestore and GCS | 0.18 ms | **PASS** |
| 44 | Public key rotation verified | Reconciler accepts rotated key version and retires old | 0.48 ms | **PASS** |

#### Track E: Recovery Dual Custody (Tests 45–50)
| Test # | Test Name / Scenario | Asserted Behavior | Duration | Result |
| :---: | :--- | :--- | :---: | :---: |
| 45 | Single officer cannot authorize both approvals | Collusion blocked (`officerId1 === officerId2`) | 0.50 ms | **PASS** |
| 46 | Unauthorized second approver rejected | Non-auditor role rejected as secondary approver | 0.31 ms | **PASS** |
| 47 | Expired dual-custody authorization rejected | Token older than 15 minutes rejected | 0.19 ms | **PASS** |
| 48 | Replayed authorization rejected | Consumed token cannot be reused | 0.39 ms | **PASS** |
| 49 | Case reference alone cannot authorize recovery | Missing dual custody proofs rejected | 0.06 ms | **PASS** |
| 50 | Replacement phone cannot act as original factor | Unverified phone number blocked from recovery flow | 0.38 ms | **PASS** |

---

### 3. Master Regression Summary

- **Phase 20.17 Suite:** 50 / 50 PASSED (1,237 ms total)
- **Backend Master Test Suite (`npm test`):** 1,148 / 1,148 PASSED across 241 test suites
- **Flutter Client Isolation & Modals Suite:** 12 / 12 PASSED
- **Zero regressions introduced.**
