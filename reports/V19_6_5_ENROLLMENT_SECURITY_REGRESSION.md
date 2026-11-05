# KELASAGARA BIOMATCH V19.6.5
## Enrollment Security Regression & Adversarial Threat Report

**Date:** 2026-10-24  
**Project:** Kelasagara BioMatch Face Recognition & Temporal Liveness  
**Release Gate Status:** `CONTROLLED_TEST_BUILD_ONLY`  
**Biometric Calibration Approved:** `false`  

---

## 1. Automated Test Execution Evidence

| Suite / Component | Test Command | Suites | Tests | Passed | Failed | Skipped | Status |
|---|---|---|---|---|---|---|---|
| **Flutter Burst Integration** | `flutter test test/v19_6_5_burst_integration_test.dart` | 4 groups | 11 | 11 | 0 | 0 | **PASS** |
| **Flutter Biometric Contracts** | `flutter test test/biometric_contract_test.dart test/face_enrollment_burst_stream_test.dart` | 4 groups | 14 | 14 | 0 | 0 | **PASS** |
| **Backend Integration & Adversarial Suite** | `node --test dist/tests/v19_6_5_real_burst_integration.test.js` | 1 | 10 | 10 | 0 | 0 | **PASS** |
| **Backend Master Test Suite** | `npm test` (`node --test dist/tests/*.test.js`) | 66 | 346 | 346 | 0 | 0 | **PASS** |
| **Dart Static Analysis** | `flutter analyze lib/... test/...` | N/A | 3 files | 3 clean | 0 | 0 | **PASS** |

---

## 2. Adversarial Security Attack Matrix

Each attack was subjected to rigorous verification using deterministic test cases:

| Attack Vector | Threat Scenario | Mechanism of Evaluation | Result | Defensive Classification |
|---|---|---|---|---|
| **ST-01: Still Photo Replay** | Attacker presents printed photo or static portrait | Single image cannot generate 3 non-identical frames with monotonic timestamps | **REJECTED** | Blocked by `INVALID_FRAME_COUNT` / `DUPLICATE_FRAME_REPLAY_DETECTED` |
| **ST-02: Freeze-Frame Replay** | Attacker sends identical frame 3 times with altered indices | Server checks `buffers[0].equals(buffers[1])` etc. | **REJECTED** | Blocked by `DUPLICATE_FRAME_REPLAY_DETECTED` |
| **ST-03: Video Replay of Blink** | Attacker replays genuine recording of user blinking on tablet | Video satisfies 2D Sobel aperture compression heuristic ($ApexRatio \le 0.65$) | **ACCEPTED (Known Risk)** | **Documented Residual Vulnerability**: 2D edge energy cannot distinguish digital screen moiré or glass surface reflection from genuine human face without hardware attestation |
| **ST-04: Nonce Replay Attack** | Attacker intercepts valid burst and re-submits with consumed nonce | Server checks `challenge.consumed` in atomic lookup | **REJECTED** | Blocked by `Replay attack detected: Challenge was already consumed` |
| **ST-05: Cross-User Challenge Theft** | Attacker Mallory attempts to submit burst under challenge issued to Alice | Server verifies `challenge.uid === req.user.uid` | **REJECTED** | Blocked by `Identity mismatch: Challenge bound to Alice, attempted by Mallory` |
| **ST-06: Timestamp Manipulation** | Attacker backdates timestamps to simulate historical capture | Server checks `timestamps[0] >= challenge.createdAt - 500` | **REJECTED** | Blocked by `Stale frame submission: Frames captured before challenge was issued` |
| **ST-07: Rapid Synthetic Injection** | Software attacker injects 3 frames with $dt = 10\text{ ms}$ | Server checks `dt >= 40` and `dt <= 600` | **REJECTED** | Blocked by `INTER_FRAME_TIMING_OUT_OF_BOUNDS` |
| **ST-08: Cross-Identity Splice** | Attacker uses Alice's open eyes and Bob's closed eyes | Server checks SFace identity continuity `cosineSimilarity(emb0, emb2) >= 0.80` | **REJECTED** | Blocked by `CROSS_FRAME_IDENTITY_SPLICE_DETECTED` |
| **ST-09: Challenge Concurrency Racing** | Two parallel HTTP requests race to consume the same challenge | Atomic in-memory test verifies exactly 1 winner and 1 rejection | **REJECTED** | Concurrency safety verified; duplicate consumption prevented |
| **ST-10: Candidate PII Enumeration** | Attacker probes 1:N gallery to uncover existing worker identity | Server response masks candidate phone, name, and deletes matched UID | **REJECTED** | DPDPA 2023 compliance verified; zero candidate PII exposed |

---

## 3. Privacy & Cryptographic Bounds

1. **DPDPA 2023 Candidate Privacy:** When 1:N duplicate interception flags a collision ($sim \ge 0.74$), the server-side serializer completely strips the existing user's internal UID, raw phone number, and embedding vectors. Only masked representations (`USR***78`, `******9876`, `A***a`) and integer similarity percentages are returned to the client.
2. **Transient Embedding Destruction:** In `FaceEnrollmentScreen._captureAndSave()`, the local client embedding array is strictly zero-filled immediately following network submission (`nativeResult.embedding.fillRange(0, len, 0.0)`).
3. **Key-Management Environment Note:** In the local development and controlled test environment, envelope encryption uses `LocalDevKeyProvider`. Production deployment strictly requires configuration of Google Cloud KMS (`CloudKmsKeyProvider`) before processing real-world citizen biometric data.
4. **Audit Immutability Note:** The in-process SHA-256 hash-chain provides tamper evidence within an operating instance. True regulatory immutability requires replication to an append-only, write-once-read-many (WORM) storage bucket or Cloud KMS-backed ledger.
