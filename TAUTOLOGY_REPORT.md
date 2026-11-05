# KELASAGARA BIOMATCH · TEST-INTEGRITY BASELINE AUDIT (TAUTOLOGY_REPORT.md)
**Audit Date:** 2026-10-10
**Files Scanned:** 86 (27 TS backend, 59 Dart client)
**Hypothesis $H_1$ Status:** CONFIRMED (Defects cataloged below)

## 1. Summary Metrics

| Metric | Count | Acceptable Limit | Status |
| :--- | :---: | :---: | :---: |
| Total Test Files Scanned | 86 | N/A | OBSERVED |
| Total Defined Tests | 820 | >= 100 | PASS |
| Total Assertions | 2245 | >= total tests | PASS |
| Mean Assertions per Test | 2.74 | >= 1.0 | PASS |
| Skipped Tests (`.skip`, `skip: true`) | 2 | 0 | WARNING |
| Focused Tests (`.only`, `solo: true`) | 0 | 0 | PASS |
| Zero-Assertion Tests | 9 | 0 | INVESTIGATE |
| Tautological Assertions (`assert(x, x)`) | 0 | 0 | PASS |
| Condition Flaws (`|| true`) | 0 | 0 | PASS |
| Swallowed Exceptions (`catch {}`) | 2 | 0 | INVESTIGATE |
| Mock-on-Unit Occurrences | 0 | 0 | PASS |

## 2. Identified Smells and Tautologies Detail

### `backend/src/tests/model_bakeoff_selection.test.ts`
- Zero-assertion tests: ['"B-05: outputs MODEL_SELECTION.md with weighted criteria and Buy-vs-Build analysis"']

### `backend/src/tests/security_hardening.test.ts`
- Swallowed exception blocks: 1

### `test/phase4_transaction_hardening_test.dart`
- Skipped tests: 2
- Zero-assertion tests: ["'ratingId format is rating_{bookingId}_{hirerUid}'", "'bookingId format is booking_{applicationId}'"]

### `test/phase5_marketplace_workflow_test.dart`
- Zero-assertion tests: ["'Application ID strictly follows app_{jobId}_{workerId} pattern'"]

### `test/polyline_regression_test.dart`
- Zero-assertion tests: ["'Polyline5 decode known OSRM string via Polyline5Decoder'", "'Polyline5Decoder: known Chennai coordinate'"]

### `test/receipt_and_presence_test.dart`
- Zero-assertion tests: ["'markDelivered ignores message if caller is sender'", "'markDelivered ignores message already marked delivered or read'"]

### `test/v701_valhalla_provider_live_benchmark_test.dart`
- Zero-assertion tests: ["'Valhalla Endpoint Configuration Check'"]

### `test/v900_navigation_forensic_suite_test.dart`
- Swallowed exception blocks: 1

## 3. Enforcement Policy
- CI check `test_integrity.py` runs on every pull request and pre-commit hook.
- Any increase in skipped tests, zero-assertion tests, tautologies, or swallowed exceptions blocks merge.
- Any golden value modification must be accompanied by an errata entry explaining the empirical reason.
