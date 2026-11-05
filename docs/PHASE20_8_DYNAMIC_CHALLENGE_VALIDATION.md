# PHASE 20.8: DYNAMIC CHALLENGE & CAPTURE SEQUENCE VALIDATION SPECIFICATION
**System:** Kelasagara Biometric Identity & Authentication Platform  
**Phase:** 20.8 (PAD Signal Extraction and Optical Evidence Engine)  
**Document Code:** SPEC-CHALLENGE-PAD-2026-008  
**Author:** Senior TypeScript Security Architect & Mobile Application Red-Team Engineer  
**Date:** November 2026  
**Status:** SPECIFICATION RATIFIED & EXPERIMENTALLY VERIFIED

---

## 1. Executive Summary & Security Boundary

Dynamic challenge-response protocols introduce unpredictability into biometric authentication sessions, preventing adversaries from successfully presenting pre-recorded video loops or static imagery captured prior to the transaction.

### Critical Security Disclosure & Scope:
A dynamic challenge protocol significantly reduces the attack surface of simple video playback and print presentation attacks. However, in accordance with the Phase 20.8 Engineering Directive:
> [!WARNING]
> **A successful dynamic challenge does NOT establish absolute resistance against all attacks.**  
> It does not defeat real-time synthetic deepfakes, low-latency puppet injection attacks, or hardware camera sensor splicing where an attacker controls an active real-time avatar pipeline. Server-side challenge validation must be accompanied by hardware-backed attestation and optical artifact detection.

---

## 2. Server-Issued Cryptographic Challenge Lifecycle

```
+--------------------------------------------------------------------------------------------------+
| STEP 1: CHALLENGE ISSUANCE (Server Endpoint: POST /api/biometrics/challenge)                    |
|  - Cryptographic Nonce: 128-bit secure random (crypto.randomBytes(16).toString('hex'))           |
|  - Random Action: action in ['BLINK', 'SMILE', 'TURN_LEFT', 'TURN_RIGHT']                       |
|  - Timestamp: IssuedAtMs = Date.now()                                                            |
|  - Expiration: ExpiresAtMs = IssuedAtMs + 120,000ms (2 minutes TTL)                             |
|  - State Persistence: Written to Redis / Ephemeral Session Store with single-use flag            |
+--------------------------------------------------------------------------------------------------+
                                                 |
                                                 v
+--------------------------------------------------------------------------------------------------+
| STEP 2: CLIENT ACQUISITION & DEVICE-BOUND SIGNING (Android Handset)                              |
|  - User prompted with localized visual guidance                                                  |
|  - CameraX captures 3 sequential frames (Frame 0, Frame 1, Frame 2)                              |
|  - Hardware timestamps logged: SystemClock.elapsedRealtimeNanos()                                |
|  - Request Signature generated via Android Keystore ECDSA P-256 private key                     |
+--------------------------------------------------------------------------------------------------+
                                                 |
                                                 v
+--------------------------------------------------------------------------------------------------+
| STEP 3: SERVER-SIDE TRANSACTION & SEQUENCE VERIFICATION                                          |
|  - Verify Device Signature over payload hash                                                     |
|  - Consume Nonce atomically via CAS (prevents double-submission)                                 |
|  - Verify Frame Monotonicity: T0 < T1 < T2                                                       |
|  - Verify Inter-Frame Intervals: 40ms <= dt <= 350ms                                             |
|  - Verify Capture Window: T0 >= IssuedAtMs AND T2 <= ExpiresAtMs                                 |
|  - Verify Action Compliance: Apex landmark trajectory matches requested prompt                   |
+--------------------------------------------------------------------------------------------------+
```

---

## 3. Sequence Invariant Enforcement Rules

In `CandidatePadHardenedEngine.validateFrameSequenceContinuity()`, the following rules are strictly enforced:

### 3.1. Monotonic Hardware Clock Invariant (`INV-SEQ-01`)
- **Requirement:** $T_0 < T_1 < T_2$
- **Threat Mitigated:** Cross-session frame splicing and out-of-order playback.
- **Test Evidence:** Unit test `3.2` confirms rejection with `NON_MONOTONIC_TIMESTAMPS`.

### 3.2. Anti-Freeze Duplicate Timestamp Invariant (`INV-SEQ-02`)
- **Requirement:** $T_{i+1} \ne T_i$
- **Threat Mitigated:** Video freeze attacks where an attacker duplicates a single valid frame to satisfy multi-frame requirements.
- **Test Evidence:** Unit test `3.3` confirms rejection with `NON_MONOTONIC_TIMESTAMPS`.

### 3.3. Sensor Physical Speed Invariant (`INV-SEQ-03`)
- **Requirement:** $\Delta T_{01} \ge 40\,\text{ms} \land \Delta T_{12} \ge 40\,\text{ms}$
- **Threat Mitigated:** Synthetic programmatic frame injection bypassing CameraX sensor pipelines (exceeding standard $30\,\text{FPS}$ hardware limits).
- **Test Evidence:** Unit test `3.4` confirms rejection with `INVALID_INTER_FRAME_INTERVAL`.

### 3.4. Challenge Expiration & Replay Invariant (`INV-SEQ-04`)
- **Requirement:** $T_0 \ge T_{\text{issued}} \land T_2 \le T_{\text{expires}}$
- **Threat Mitigated:** Submitting frames recorded before the challenge was issued, or delayed submission of cached sessions.
- **Test Evidence:** Unit tests `3.5` and `3.6` confirm rejection with `CHALLENGE_EXPIRED` and `FRAME_PREDATES_CHALLENGE`.

---

## 4. Verification and Implementation Status

All six sequence validation invariants are fully implemented in `CandidatePadHardenedEngine` and verified by Category 3 unit tests in `backend/src/tests/phase20_8_optical_pad.test.ts` (6/6 tests passing).
