# KELASAGARA BIOMATCH V19.6.2: ADVERSARIAL TEST RESULTS & VERIFICATION EVIDENCE
**Document ID:** `KB-V19-6-2-REP-03`  
**Classification:** Empirical Verification & Adversarial Security Test Suite Report  
**Release Gate Status:** `CONTROLLED_TEST_BUILD_ONLY`  
**Production Biometric Calibration Approved:** `false`  
**Execution Environment:** Darwin 24.1.0 (macOS Sequoia) | Apple M4 Pro (12 Cores, 24 GB Unified Memory) | Node.js v24.14.0 | Flutter 3.x  
**Evaluation Date:** October 24, 2026

---

## 1. TEST EXECUTION SUMMARY & CONTEXT

To substantiate the security improvements in KELASAGARA BIOMATCH V19.6.2, an end-to-end multi-layer test harness was executed across four distinct test tiers:
1. **Targeted Adversarial Liveness & Replay Suite (`v19_6_2_adversarial_liveness.test.ts`)**
2. **Full Standalone Backend Regression Suite (57 Test Suites, 301 Tests)**
3. **Live Firestore Emulator Security Rules & Penetration Suite (`firestore_emulator_security_rules_v19_3.test.ts`)**
4. **Flutter Mobile Biometric & Contract Test Suites (`biometric_v19_6_test.dart`, `biometric_contract_test.dart`)**

All executed test suites completed with a **100% pass rate (0 failures, 0 regressions, 0 skipped tests)**.

---

## 2. SUITE 1: TARGETED ADVERSARIAL LIVENESS & REPLAY SUITE

- **Test Harness:** Node.js Built-in Test Runner (`node --test`)
- **Source File:** `backend/src/tests/v19_6_2_adversarial_liveness.test.ts`
- **Execution Command:**
  ```bash
  cd "backend" && node --test dist/tests/v19_6_2_adversarial_liveness.test.js
  ```
- **Exit Code:** `0` (Success)
- **Suite Duration:** `440.60 ms`
- **Total Tests:** 12 Passed, 0 Failed, 0 Skipped

### Granular Adversarial Test Results Table

| Test ID | Adversarial Test Scenario | Target Invariant | Expected Behavior | Actual Behavior | Result | Execution Time |
|:---|:---|:---:|:---|:---|:---:|:---:|
| **ADV-01** | Reusing a previously consumed nonce | Invariant I-05 | Second consumption attempt throws `Replay attack detected` | Throws `Replay attack detected: Challenge '...' was already consumed.` | `VERIFIED` | 1.36 ms |
| **ADV-02** | Submitting an expired challenge (>60s TTL) | Invariant I-05 | Challenge timestamp $> 60\text{s}$ old rejected | Throws `Session expired: Challenge '...' exceeded 60s TTL.` | `VERIFIED` | 0.23 ms |
| **ADV-03** | Submitting a challenge for another caller UID | Invariant I-04 | Caller UID mismatch rejected with identity error | Throws `Identity mismatch: Challenge bound to UID 'user_victim_99', attempted by 'user_attacker_01'` | `VERIFIED` | 0.20 ms |
| **ADV-04** | Submitting challenge for another session / action | Invariant I-04 | Mismatched operation or session ID rejected | Throws `Action mismatch` and `Session binding mismatch` | `VERIFIED` | 0.22 ms |
| **ADV-05** | Submitting frames captured before challenge issuance | Invariant I-05 | Frame timestamps $t_0 < t_{\text{issued}}$ rejected | Throws `Stale frame submission: Frames captured before challenge was issued` | `VERIFIED` | 0.24 ms |
| **ADV-06** | Omitting required sequence frames (< 3 frames) | Gate G-02 | Incomplete frame sequence rejected | Returns `passed: false`, reason: `INVALID_FRAME_COUNT` | `VERIFIED` | 7.93 ms |
| **ADV-07** | Reordered frames or non-monotonic timing | Gate G-02 | Scrambled indices $[1, 0, 2]$ or $\Delta t \le 0$ rejected | Returns `passed: false`, reason: `OUT_OF_ORDER_FRAME_SEQUENCE` | `VERIFIED` | 3.71 ms |
| **ADV-08** | Repeating identical frames (static replay/freeze) | Anti-Freeze PAD | Byte-identical frames detected and rejected | Returns `passed: false`, reason: `DUPLICATE_FRAME_REPLAY_DETECTED` | `VERIFIED` | 1.01 ms |
| **ADV-09** | Fabricated `blinkVerified: true` without eye compression | Server PAD | Client claim ignored; apex gradient ratio $> 0.65$ rejected | Returns `passed: false`, reason: `BLINK_TRAJECTORY_NOT_SATISFIED` | `VERIFIED` | 243.34 ms |
| **ADV-10** | Photometric luma step anomaly (video splice) | Anti-Splicing | Grayscale luma jump $> 18\%$ rejected | Returns `passed: false`, reason: `PHOTOMETRIC_LUMA_STEP_ANOMALY` | `VERIFIED` | 10.22 ms |
| **ADV-11** | Concurrent attempts to consume the same challenge | Race Resilience | 5 simultaneous consumer requests serialize safely | Exactly 1 request succeeds (true); 4 requests rejected (false) | `VERIFIED` | 0.35 ms |
| **ADV-12** | Interrupted request leaves user in pending_face | State Machine | Client-side abort mid-sequence cannot reach `ACTIVE` | Throws `InvalidStateTransitionError`; remains `PENDING_FACE` | `VERIFIED` | 0.25 ms |

---

## 3. SUITE 2: FULL STANDALONE BACKEND REGRESSION SUITE

- **Execution Command:**
  ```bash
  cd "backend" && node --test --test-concurrency=1 dist/tests/*.test.js
  ```
- **Exit Code:** `0` (Success)
- **Suite Duration:** `61,021.95 ms` (61.02 seconds)
- **Total Test Suites:** 57 Suites Passed (0 Failed, 0 Skipped)
- **Total Tests:** 301 Tests Passed (0 Failed, 0 Cancelled, 0 Todo)

### Key Subsystem Test Results
- **Stage S8: AAD Canonicalization & KMS Envelope Encryption:** 10/10 tests passed (42.68 ms).
- **Admin Biometric Routes & Review Queue (Gate G-08):** 3/3 tests passed (67.67 ms).
- **V19.2 Master Adversarial Security & Identity Protection Suite:** 10/10 tests passed (54.22 ms).
- **Phase 9: Services & API Routes Integration Suite:** 8/8 tests passed (31,620 ms).
- **V15.0 Threshold Governance & Decision Boundary Suite:** 4/4 groups passed (27.15 ms).
- **V19.5 Research Benchmark Harness & Statistical Engine:** 5/5 tests passed (40.19 ms).
- **V19.6 Advanced Biometric Enrollment Suite:** 4/4 groups passed (7.56 ms).
- **V19.6.2 Adversarial Liveness & Replay Suite:** 12/12 tests passed (205.24 ms).

---

## 4. SUITE 3: FIRESTORE EMULATOR SECURITY RULES & PENETRATION SUITE

- **Execution Command:**
  ```bash
  export PATH="/opt/homebrew/opt/openjdk/bin:$PATH" JAVA_HOME="/opt/homebrew/opt/openjdk" && \
  npx firebase emulators:exec --only firestore "node --test backend/dist/tests/firestore_emulator_security_rules_v19_3.test.js"
  ```
- **Exit Code:** `0` (Success)
- **Runtime Environment:** OpenJDK 27 (Homebrew), Firebase Tools Emulator v13.x
- **Suite Duration:** `2,748.76 ms`
- **Total Tests:** 10/10 Passed, 0 Failed

### Firestore Rules Penetration Audit Results
1. `RULE-01`: Direct client read of `/person_identities/{id}` is strictly denied (`426.23 ms`) -> `VERIFIED`
2. `RULE-02`: Direct client write to `/person_identities/{id}` is strictly denied (`110.38 ms`) -> `VERIFIED`
3. `RULE-03`: Direct client read and write to `/step_up_proofs/{id}` is strictly denied (`74.53 ms`) -> `VERIFIED`
4. `RULE-04`: Direct client access to `/biometric_vault/{uid}` is strictly denied (`68.05 ms`) -> `VERIFIED`
5. `RULE-05`: Direct client access to `/biometric_challenges/{id}` is strictly denied (`65.62 ms`) -> `VERIFIED`
6. `RULE-06`: Client cannot self-assign `faceVerified: true` or bypass biometric enrollment (`106.68 ms`) -> `VERIFIED`
7. `RULE-07`: Client cannot modify `personId`, `linkedAuthUids`, or biometric ownership fields (`105.25 ms`) -> `VERIFIED`
8. `RULE-08`: Legitimate profile updates by account owner succeed cleanly (`56.22 ms`) -> `VERIFIED`
9. `RULE-09`: Unauthenticated clients cannot read unapproved worker profiles (`104.51 ms`) -> `VERIFIED`
10. `RULE-10`: Backend Admin SDK can read and write all protected collections (`93.75 ms`) -> `VERIFIED`

---

## 5. SUITE 4: FLUTTER BIOMETRIC & CONTRACT TESTS

### 5.1 `test/biometric_v19_6_test.dart`
- **Execution Command:** `flutter test test/biometric_v19_6_test.dart`
- **Exit Code:** `0` (Success)
- **Duration:** `7.0 seconds`
- **Results:** 7/7 Passed, 0 Failed
  - *Adaptive Illumination:* Initializer and reset lifecycle safely handled (`VERIFIED`).
  - *Screen-Fill Idempotency:* Enable and disable cycles operate fail-safe (`VERIFIED`).
  - *Active Challenge Parsing:* Parses randomized actions (`TURN_HEAD_LEFT`, etc.) and Kannada/English prompts (`VERIFIED`).
  - *Privacy Masking:* Strict zero-PII exposure before verified ownership (`VERIFIED`).
  - *Authorized Disclosure:* Exposes masked identifiers strictly post-verification (`VERIFIED`).
  - *Widget Contract:* `DuplicateDetectedSheet` renders generic privacy notice and hides PII widgets (`VERIFIED`).

### 5.2 `test/biometric_contract_test.dart`
- **Execution Command:** `flutter test test/biometric_contract_test.dart`
- **Exit Code:** `0` (Success)
- **Duration:** `5.0 seconds`
- **Results:** 8/8 Passed, 0 Failed
  - *Burst Serialization:* `BurstFramePayloadItem` serializes cleanly into backend schema (`VERIFIED`).
  - *Challenge Ticket Parsing:* Correctly parses backend challenge ticket (`VERIFIED`).
  - *Network Fail-Closed:* Handles network errors by setting `serviceUnavailable: true` without failing open (`VERIFIED`).

### 5.3 Static Analysis
- **Execution Command:**
  ```bash
  flutter analyze lib/screens/auth/face_enrollment_screen.dart \
                  lib/services/capture_illumination_service.dart \
                  lib/widgets/duplicate_detected_sheet.dart \
                  test/biometric_v19_6_test.dart
  ```
- **Exit Code:** `0`
- **Output:** `Analyzing 4 items... No issues found! (ran in 3.9s)`

---

## 6. AUDIT SUMMARY & VERIFICATION STATUS CLASSIFICATION

```
┌────────────────────────────────────────────────────────────────────────┐
│                   TOTAL VERIFICATION TEST RUNS: 326                    │
├────────────────────────────────────────────────────────────────────────┤
│ - Backend Integration & Adversarial: 301 Passed                        │
│ - Firestore Live Emulator Security:   10 Passed                        │
│ - Flutter Biometric & Contract:       15 Passed                        │
│ - Regressions / Failures / Skipped:    0 (100% Green)                  │
└────────────────────────────────────────────────────────────────────────┘
```

**Classification of System Capabilities:**
- **Server Challenge Freshness & Single-Use:** `VERIFIED`
- **UID Identity Binding & Anti-Theft:** `VERIFIED`
- **Server-Side Ocular & Motion Trajectory Recomputation:** `VERIFIED`
- **Client Zero-Trust Vector & Boolean Enforcement:** `VERIFIED`
- **Multi-Frame Anti-Freeze & Anti-Splice Gating:** `VERIFIED`
- **Firestore Security Rules Immunity:** `VERIFIED`
- **Hardware Camera Attestation:** `UNVERIFIED` (Requires OS/OEM HAL platform support)
- **Universal Video Spoof Immunity:** `BLOCKED` (Requires physical IR/depth lab testing)
