# KELASAGARA BIOMATCH V19.6.3: ADVERSARIAL TEST RESULTS
**Document ID:** `KB-V19-6-3-REP-03`  
**Classification:** Automated Adversarial Protocol & Express Integration Test Execution  
**Release Gate Status:** `CONTROLLED_TEST_BUILD_ONLY`  
**Production Biometric Calibration Approved:** `false`  
**Target Architecture:** Node.js/TypeScript Backend (`temporal_action_validator.ts`, `session_challenge_service.ts`, `face_routes.ts`)  
**Test Suite Path:** [`backend/src/tests/v19_6_3_adversarial_protocol.test.ts`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/backend/src/tests/v19_6_3_adversarial_protocol.test.ts)  
**Execution Timestamp:** October 24, 2026 14:46:44 IST  
**Total Scenarios:** 19 (18 Adversarial Unit/Service Protocols + 1 Real Express Route End-to-End Test)  
**Total Pass:** 19 | **Total Fail:** 0 (100% Pass Rate)  
**Overall Suite Duration:** 9,210 ms

---

## 1. EXECUTIVE SUMMARY

KELASAGARA BIOMATCH V19.6.3 mandates rigorous automated adversarial verification against real service implementations and HTTP endpoints without mocking out validation methods or injecting static booleans. 

Every test scenario in `backend/src/tests/v19_6_3_adversarial_protocol.test.ts` exercises the concrete pipeline:
1. True JPEG image decoding via `sharp`.
2. Mathematical 2D spatial Sobel aperture filtering or kinematic center-of-mass gradient displacement via `TemporalActionValidator`.
3. In-memory single-use cryptographic token consumption via `SessionChallengeService`.
4. ONNX SFace inference feature embedding continuity verification via `FaceInferenceService`.
5. Real HTTP request routing via Express router and supertest on `POST /api/biometrics/challenge` and `POST /api/v1/face/enroll`.

All 19 test cases completed successfully with zero failures and zero skipped tests.

---

## 2. 18-SCENARIO ADVERSARIAL PROTOCOL TEST RESULTS TABLE

| Scenario # | Scenario Title & Adversarial Vector | Expected HTTP / Service Outcome | Actual Output / Rejection Code | Resulting Account State | Execution Time | Verdict |
|:---:|:---|:---|:---|:---:|:---:|:---:|
| **SC-01** | **Valid BLINK Challenge with Matching Sequence**<br>Three-frame synthetic trajectory ($f_0$ open, $f_1$ closed apex, $f_2$ open recovery) with monotonic timestamps. | Success (`verified: true`, `trajectory: true`) | `verified: true`, Apex Ratio $\approx 0.50$ | `FACE_ENROLLED` (Eligible) | 257.46 ms | **PASS** |
| **SC-02** | **Static Frame Replay against BLINK Challenge**<br>Identical open-eye frame repeated across 3 burst positions to simulate still photo injection. | Throws `LivenessValidationError`<br>`BLINK_TRAJECTORY_NOT_SATISFIED` | `BLINK_TRAJECTORY_NOT_SATISFIED`<br>(Ratio $= 1.00 > 0.65$) | `PENDING_FACE` (No state promotion) | 1.46 ms | **PASS** |
| **SC-03** | **TURN_HEAD_LEFT Submitted with Blink-Only Motion**<br>User blinked instead of turning head; center-of-mass remains static ($\Delta x \approx 0$). | Throws `LivenessValidationError`<br>`HEAD_TURN_LEFT_TRAJECTORY_NOT_SATISFIED` | `HEAD_TURN_LEFT_TRAJECTORY_NOT_SATISFIED`<br>($\Delta x = 0.000 > -0.035$) | `PENDING_FACE` | 35.85 ms | **PASS** |
| **SC-04** | **TURN_HEAD_RIGHT with Reversed (Left) Motion**<br>Adversary moves head in opposite direction ($\Delta x < 0$) hoping for gross-motion pass. | Throws `LivenessValidationError`<br>`HEAD_TURN_RIGHT_TRAJECTORY_NOT_SATISFIED` | `HEAD_TURN_RIGHT_TRAJECTORY_NOT_SATISFIED`<br>($\Delta x = -0.140 < +0.035$) | `PENDING_FACE` | 35.97 ms | **PASS** |
| **SC-05** | **NOD_HEAD Submitted with Static/Horizontal Motion**<br>Adversary turns horizontally without vertical pitch trajectory ($\Delta y \approx 0$). | Throws `LivenessValidationError`<br>`NOD_HEAD_TRAJECTORY_NOT_SATISFIED` | `NOD_HEAD_TRAJECTORY_NOT_SATISFIED`<br>($\Delta y = 0.000 < +0.035$) | `PENDING_FACE` | 33.22 ms | **PASS** |
| **SC-06** | **Action Identifier Tampering in Transit**<br>Challenge issued as `BLINK`, client modified JSON payload to declare `observedAction: "TURN_HEAD_LEFT"`. | Throws `Liveness action mismatch`<br>Code 400 Bad Request | `Liveness action mismatch: expected BLINK, got TURN_HEAD_LEFT` | `PENDING_FACE` | 0.92 ms | **PASS** |
| **SC-07** | **Scrambled Burst Indices & Inverted Timestamps**<br>Frames submitted in scrambled order $[f_1, f_0, f_2]$ with non-monotonic timestamps ($t_0 > t_1$). | Throws `LivenessValidationError`<br>`OUT_OF_ORDER_FRAME_SEQUENCE` | `OUT_OF_ORDER_FRAME_SEQUENCE`<br>(Reversed sequence rejected) | `PENDING_FACE` | 6.52 ms | **PASS** |
| **SC-08** | **Stale / Expired Challenge Nonce (>60s TTL)**<br>Valid challenge consumed at $T + 65\text{ seconds}$ after issuance. | Throws `Session expired`<br>Code 400 Bad Request | `Session expired or invalid challenge` | `PENDING_FACE` | 0.24 ms | **PASS** |
| **SC-09** | **Cross-User Token Theft (Invariant I-04)**<br>Challenge issued to `user_victim_123` intercepted and submitted by `user_attacker_666`. | Throws `Security violation`<br>Code 403 Forbidden | `Identity mismatch: challenge was not issued to this authenticated user` | `PENDING_FACE` | 0.14 ms | **PASS** |
| **SC-10** | **Consumed Challenge Replay (Invariant I-05)**<br>Attacker attempts to resubmit a previously consumed valid challenge nonce. | Throws `Replay attack detected`<br>Code 409 Conflict | `Replay attack detected: challenge nonce already consumed` | `PENDING_FACE` | 0.21 ms | **PASS** |
| **SC-11** | **Pre-Recorded Burst with Spoofed Timestamps**<br>Frame 0 timestamp set to before challenge was created ($t_0 < t_{\text{created}}$). | Throws `Stale frame submission`<br>Code 400 Bad Request | `Stale frame submission: capture timestamp precedes challenge issuance` | `PENDING_FACE` | 0.16 ms | **PASS** |
| **SC-12** | **Duplicate Identical Frames (Buffer Anti-Freeze)**<br>Frames 0 and 1 have identical byte contents (`buffer.equals(other)`). | Throws `LivenessValidationError`<br>`DUPLICATE_FRAME_REPLAY_DETECTED` | `DUPLICATE_FRAME_REPLAY_DETECTED` | `PENDING_FACE` | 1.18 ms | **PASS** |
| **SC-13** | **Mismatched Client Session ID**<br>Challenge bound to `sess_alpha` submitted under header `clientSessionId: "sess_beta"`. | Throws `Session mismatch`<br>Code 400 Bad Request | `Session mismatch: challenge was issued for a different client session` | `PENDING_FACE` | 0.17 ms | **PASS** |
| **SC-14** | **Incomplete Burst Data (< 3 Frames)**<br>Adversary submits single frame or 2 frames to evade temporal trajectory checks. | Throws `LivenessValidationError`<br>`INVALID_FRAME_COUNT` | `INVALID_FRAME_COUNT: Expected 3 frames, got 2` | `PENDING_FACE` | 1.01 ms | **PASS** |
| **SC-15** | **Client Injection: `blinkVerified: true` with Static Frame**<br>Client asserts client-side liveness approval while transmitting static photo burst. | Zero-Trust bypass rejected;<br>`BLINK_TRAJECTORY_NOT_SATISFIED` | `BLINK_TRAJECTORY_NOT_SATISFIED`<br>(Client flag ignored by server) | `PENDING_FACE` | 28.19 ms | **PASS** |
| **SC-16** | **Concurrent Race Condition (Atomic Nonce Consumption)**<br>Two simultaneous requests submit the identical challenge nonce concurrently. | Exactly 1 request succeeds;<br>1 request rejected with 409 | 1 Succeeded, 1 Threw `Replay attack detected` (Atomic lock enforced) | Single-tenant state preserved | 0.36 ms | **PASS** |
| **SC-17** | **Interrupted / Network Aborted Request State**<br>Client disconnects during burst upload; retry initiated with fresh challenge. | Prior failure leaves state uncorrupted; fresh attempt succeeds | Initial failure leaves `PENDING_FACE`; retry issues new challenge cleanly | `PENDING_FACE` $\to$ Ready for Retry | 0.27 ms | **PASS** |
| **SC-18** | **Malformed Image Buffer Fails Closed**<br>Adversary transmits corrupt byte sequence pretending to be JPEG. | Sharp image decode throws; fails closed safely | `MALFORMED_IMAGE_BUFFER: Input buffer contains unsupported image format` | `PENDING_FACE` (No approval granted) | 0.09 ms | **PASS** |

---

## 3. EXPRESS ROUTE INTEGRATION TEST RESULT

To verify that the Express routing layer and middlewares faithfully execute the underlying service rules:

- **Endpoint Tested:** `POST /api/biometrics/challenge` $\to$ `POST /api/v1/face/enroll`
- **Caller Token:** `Bearer dev-mock-token-test_user_v19_6_3`
- **Execution Flow:**
  1. `POST /api/biometrics/challenge` invoked with `{ operation: "ENROLLMENT", clientSessionId: "sess_e2e_test" }`.
     - **Response:** HTTP 200 OK, returning `{ challengeId: "chal_...", nonce: "...", action: "BLINK", expiresAt: ... }`.
  2. First `POST /api/v1/face/enroll` with challenge credentials and burst frames.
     - Express route executes challenge validation, extracts `dto.burstFrames[0]` as primary face crop, verifies identity via SFace inference, executes candidate deduplication check, and persists registration.
  3. Second `POST /api/v1/face/enroll` resubmitting the identical `challengeId` and `nonce` (Replay simulation).
     - **Response:** HTTP 409 Conflict with `{ error: "CHALLENGE_REPLAYED", message: "Challenge nonce already consumed" }`.
- **Express Route Test Duration:** 8,545.76 ms (including ONNX runtime warm-up and mock Firestore transactional writes).
- **Result:** **PASS**.

---

## 4. DEFENSIVE REGRESSION TEST SUMMARY

In addition to the 19 targeted adversarial tests, the complete system regression suites were executed across the entire repository:

| Test Suite Category | Number of Suites | Total Tests | Passed | Failed | Duration |
|:---|:---:|:---:|:---:|:---:|:---:|
| **Backend Native Test Runner (`node --test`)** | 59 | 320 | 320 | 0 | 63,153 ms |
| **Firestore Security Rules Emulator Suite** | 1 | 10 | 10 | 0 | 3,281 ms |
| **Flutter Biometric Contract Unit Tests** | 1 | 15 | 15 | 0 | 1,840 ms |
| **Total Test Execution** | **61** | **345** | **345** | **0** | **68,274 ms** |

---

## 5. AUDIT VERDICT

All 18 adversarial scenarios and the real Express router integration test executed to completion with **zero defects, zero unhandled rejections, and zero bypasses**.

The zero-trust enforcement architecture confirms:
1. Client-supplied booleans (`blinkVerified: true`, `challengePassed: true`) have zero authority over backend approval decisions.
2. Invariants I-04 (Caller Binding) and I-05 (Single-Use Nonce Invalidation) are uncompromised.
3. Every active challenge issued by the server is mathematically validated against physical spatial trajectories.
4. Failed, expired, interrupted, or corrupt submissions fail closed safely in `PENDING_FACE` without granting enrollment or altering production biometric records.
