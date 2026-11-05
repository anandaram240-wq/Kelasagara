# KELASAGARA BIOMATCH V19.6.1
## Active Liveness Trust Boundary & Cryptographic Challenge-Response Integrity Audit

**Document Status:** COMPLETE & VERIFIED  
**Date:** October 24, 2026  
**Auditor:** BioMatch Security & Cryptographic Systems Group  
**Target Codebase:** `kelasagaara_v17` (Branch `ui/polish-v1`)  
**Release Gate Status:** `CONTROLLED_TEST_BUILD_ONLY`  
**Production Biometric Calibration Approved:** `false`  

---

## 1. Executive Summary & Core Cryptographic Verdict

A cryptographic challenge-response mechanism alone does **not** constitute an ISO/IEC 30107-3 compliant Presentation Attack Detection (PAD) system. While server-issued randomness proves *temporal freshness* and *session binding*, it does not prove physical human liveness unless the server independently verifies the physical execution of the action across unbroken sensor-originating evidence.

### Core Integrity Findings Summary

| Cryptographic Invariant | Target Property | Implementation Mechanism | Verified Status |
|:---|:---|:---|:---:|
| **Invariant I-04** | Caller Identity Binding | Challenge bound to authenticated Firebase `uid` | `VERIFIED` |
| **Invariant I-05** | Operation Context Binding | Challenge bound to intended operation (`ENROLLMENT` vs `VERIFICATION`) | `VERIFIED` |
| **Invariant I-05b** | Single-Use Anti-Replay | Immediate atomic consumption and eviction upon first verification | `VERIFIED` |
| **Invariant I-05c** | Temporal Freshness | Strict 60-second Time-To-Live (TTL) with deterministic memory sweep | `VERIFIED` |
| **Invariant I-23** | Anti-Bypass / Gate Integrity | Client cannot claim `challengePassed: true` unilaterally; server consumes nonce | `VERIFIED` |
| **Threat T-01** | Virtual Camera Video Injection | Rooted kernel V4L2/Camera2 HAL hooking streams synthetic frames to ML Kit | `NOT VERIFIED` (Vulnerable) |
| **Threat T-02** | High-Res Display Presentation | 4K iPad displaying pre-recorded video clip of target blinking | `NOT VERIFIED` (Vulnerable) |
| **Threat T-03** | Server-Side Action Verification | Server verifies kinematic 3D head movement from video stream | `NOT VERIFIED` (Missing) |

---

## 2. Cryptographic Challenge-Response Implementation Analysis

### 2.1 Unpredictability & Entropy
- **Implementation:** [`backend/src/services/session_challenge_service.ts:64-65`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/backend/src/services/session_challenge_service.ts#L64-L65)
- **Source Code:**
  ```typescript
  const challengeId = `chal_${crypto.randomBytes(16).toString("hex")}`;
  const nonce = crypto.randomBytes(32).toString("hex");
  ```
- **Evaluation:**
  - Employs Node.js standard `crypto.randomBytes()`, which draws from system CSPRNG (`/dev/urandom` on POSIX / `getrandom()` on Linux).
  - Entropy: 128 bits for `challengeId`, 256 bits for `nonce`. Total search space: $2^{256} \approx 1.15 \times 10^{77}$.
  - Invariant: Zero predictability; brute-force prediction of active challenge nonces is computationally infeasible.
- **Status:** `VERIFIED`

---

### 2.2 Invariant I-04: Caller Identity Binding
- **Implementation:** [`backend/src/services/session_challenge_service.ts:171-175`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/backend/src/services/session_challenge_service.ts#L171-L175)
- **Source Code:**
  ```typescript
  if (challenge.uid !== uid) {
    throw new Error(
      `Identity mismatch: Challenge bound to UID '${challenge.uid}', attempted by '${uid}'.`
    );
  }
  ```
- **Evaluation:**
  - A challenge requested by User A cannot be stolen or submitted by User B.
  - Verified under adversarial regression test:
    - Test: `TEST 4: Invariant I-05: Nonce replay & cross-action rejection`
    - Test: `v19_6_advanced_enrollment.test.ts: strictly blocks cross-user challenge theft (Invariant I-04)`
  - Exit outcome: Attacker receives HTTP 400 Bad Request with explicit injection intercept message.
- **Status:** `VERIFIED`

---

### 2.3 Invariant I-05: Operation Context Binding
- **Implementation:** [`backend/src/services/session_challenge_service.ts:177-182`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/backend/src/services/session_challenge_service.ts#L177-L182)
- **Source Code:**
  ```typescript
  const normAction = action.toLowerCase();
  if (challenge.action !== normAction) {
    throw new Error(
      `Action mismatch: Challenge bound to '${challenge.action}', attempted '${action}'.`
    );
  }
  ```
- **Evaluation:**
  - A challenge acquired for `verification` cannot be redirected to `enrollment` or `step_up` operations.
  - Verified under automated test:
    `v19_6_advanced_enrollment.test.ts: strictly blocks cross-action challenge reuse (Invariant I-05)`.
- **Status:** `VERIFIED`

---

### 2.4 Invariant I-05b: Single-Use Anti-Replay & Atomic Eviction
- **Implementation:** [`backend/src/services/session_challenge_service.ts:158-193`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/backend/src/services/session_challenge_service.ts#L158-L193)
- **Source Code:**
  ```typescript
  if (challenge.consumed) {
    throw new Error(`Replay attack detected: Challenge '${challengeId}' was already consumed.`);
  }
  // Single-use: Mark consumed and delete immediately
  challenge.consumed = true;
  this.challenges.delete(challengeId);
  ```
- **Evaluation:**
  - Every challenge token is destroyed from memory immediately upon its first verification.
  - A concurrent submission collision is serialized; the first thread consumes the token, causing the second thread to fail with `Session does not exist or expired`.
  - Repeated enrollment requests cannot reuse successful or failed challenge results.
- **Status:** `VERIFIED`

---

### 2.5 Invariant I-05c: Temporal Freshness & 60-Second TTL
- **Implementation:** [`backend/src/services/session_challenge_service.ts:48, 162-165, 242-249`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/backend/src/services/session_challenge_service.ts#L48)
- **Source Code:**
  ```typescript
  private static readonly TTL_MS = 60 * 1000; // 60 seconds TTL
  if (Date.now() > challenge.expiresAt) {
    this.challenges.delete(challengeId);
    throw new Error(`Session expired: Challenge '${challengeId}' exceeded 60s TTL.`);
  }
  ```
- **Evaluation:**
  - Expired nonces are purged on every access and periodically during clean-up sweeps.
  - An interrupted or aborted enrollment session leaves behind an expired challenge that is rejected if re-submitted later.
- **Status:** `VERIFIED`

---

## 3. The Trust Boundary Gap: Client Kinematics vs Server Verification

```
┌─────────────────────────────────────────────────────────────┐
│                       MOBILE DEVICE                         │
│                                                             │
│  [Camera Hardware] ──▶ [Google ML Kit Face Detector]        │
│                               │                             │
│                               ▼                             │
│                   [Ear Blink Kinematics]                    │
│                               │                             │
│                  (Passes locally on device)                 │
│                               │                             │
│                               ▼                             │
│            Capture 1 JPEG Frame (Burst Best Frame)          │
└───────────────────────────────┬─────────────────────────────┘
                                │
                    POST /api/biometrics/enroll
                    {
                      imageBase64: "<single_frame_base64>",
                      challengeNonce: "chal_...:nonce",
                      livenessAudit: { blinkVerified: true }
                    }
                                │
                                ▼
┌─────────────────────────────────────────────────────────────┐
│                      BACKEND SERVER                         │
│                                                             │
│  [Validate & Consume Nonce] ──▶ SUCCESS                     │
│  [Check imageBase64 presence] ──▶ SUCCESS                   │
│  [Run SFace Model on imageBase64] ──▶ Generates 128-D Vector│
│  [1:N Duplicate Screening] ──▶ Computes Cosine Match        │
│                                                             │
│  ⚠️ SERVER-SIDE VIDEO / MOTION VALIDATION: NOT PERFORMED!    │
└─────────────────────────────────────────────────────────────┘
```

### 3.1 Trust Boundary Gap Analysis
1. **Client Sends Single Image Frame:**
   - The Flutter client uploads only **one still image** (`imageBase64`) representing the highest-scoring burst frame, along with a metadata dictionary (`livenessAudit: {'blinkVerified': true, ...}`).
2. **Server Cannot Validate Action Execution:**
   - When the server issues `TURN_HEAD_LEFT`, `TURN_HEAD_RIGHT`, or `NOD_HEAD`, the client UI displays the instruction, but the server **receives only one still image**.
   - The server does **not** receive a continuous multi-frame video stream or optical flow motion field.
   - Consequently, the server **cannot cryptographically verify that the user turned their head or nodded**.
   - As mandated: **Trusted server-side action verification is marked `NOT VERIFIED`. Server-issued randomness alone does NOT constitute proof of liveness.**
3. **Client-Side Bypassability on Rooted Devices:**
   - Because action detection occurs entirely within client memory (Flutter/Java ML Kit), a modified APK or Frida script hooking `_padKinematics.processFrame()` or `evaluateIso29794Quality()` can report `isCompliant: true` and `kineticVerified: true` regardless of actual camera input.

---

## 4. Threat Model & Presentation Attack Vulnerabilities

### Threat 1: Virtual Camera Video Injection
- **Attack Vector:** An adversary runs the app on an Android emulator or rooted physical device with a virtual camera driver (e.g., Magisk `VirtualCam`, OBS Virtual Camera, Android `v4l2loopback`). The driver pipes a high-resolution pre-recorded MP4 video into the Android Camera2 HAL.
- **Client Defense Assessment:**
  - Google ML Kit processes the virtual camera stream and perceives human facial geometry.
  - The video includes blinks, satisfying local kinematic thresholds.
  - Laplacian variance filter measures pixel gradients. A crisp 1080p raw video file piped directly through the camera HAL can have high Laplacian variance ($\sigma^2 \in [200, 800]$), completely bypassing passive blur detection.
- **Status:** `NOT VERIFIED` (Vulnerable to OS-level HAL injection without hardware key attestation).

---

### Threat 2: High-Resolution Display / 2D Replay Attack
- **Attack Vector:** An attacker points the physical phone camera at an iPad Pro OLED display (264 ppi, 1000 nits) playing a 60 fps 4K video of the target blinking.
- **Client Defense Assessment:**
  - The passive texture filter attempts to catch digital screen moiré patterns ($\sigma^2 > 3800$).
  - However, at distances $> 40$ cm, high-density OLED screens with anti-reflective coatings produce minimal moiré interference within the camera's resolution limit.
  - Screen-fill illumination (softbox mode) produces reflections on the iPad glass, which can alter illumination symmetry. However, this is not currently evaluated as an explicit anti-spoofing heuristic.
- **Status:** `NOT VERIFIED` (Vulnerable to high-quality screen presentation).

---

### Threat 3: Steered Real-Time Deepfakes
- **Attack Vector:** An attacker uses a live generative neural avatar (e.g., LivePortrait / DeepFaceLive) driven by an operator wearing a webcam. When the server requests `TURN_HEAD_LEFT`, the operator turns left; when the server requests `BLINK`, the operator blinks.
- **Evaluation:**
  - The server challenge has a 60-second window. A live operator can easily execute the requested head gesture in 3 seconds.
  - Because the server only receives a still image, artifacts of neural synthesis (temporal jitter, boundary tearing) are completely invisible to the server.
- **Status:** `NOT VERIFIED` (Vulnerable to human-steered real-time generative puppets).

---

## 5. Required Production Hardening Architecture

To achieve true ISO/IEC 30107-3 Level 1/2 PAD compliance and eliminate the trust boundary gaps identified above, the following three architectural upgrades are required prior to production release:

```
                   PRODUCTION SECURE CAPTURE PIPELINE
┌────────────────────────────────────────────────────────────────────────┐
│ 1. Android KeyStore StrongBox Hardware Key Attestation                 │
│    - Generate EC P-256 keypair inside hardware Secure Element (TEE)    │
│    - Obtain Google-signed certificate chain verifying boot state       │
│    - Binds Play Integrity MEETS_STRONG_INTEGRITY                       │
├────────────────────────────────────────────────────────────────────────┤
│ 2. Hardware-Sealed Frame Signature (Secure Camera HAL)                 │
│    - Camera2 Secure Surface seals raw YUV frames inside TEE             │
│    - Sign (Nonce + Frame Hash + Monotonic Timestamp) with Private Key  │
├────────────────────────────────────────────────────────────────────────┤
│ 3. Server-Side Temporal Motion & 3D Neural PAD                         │
│    - Client streams 15 signed frames (0.5s temporal window)             │
│    - Server runs 3D ResNet / Video Transformer PAD model               │
│    - Validates optical flow field vector matches issued challenge      │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 6. Audit Verdict

1. **Cryptographic fresh-nonce issuance, single-use anti-replay, UID binding, and 60-second TTL are `VERIFIED` and mathematically sound.**
2. **Client-supplied vectors are strictly rejected via Ticket T-01 middleware (`VERIFIED`).**
3. **Server-side physical action validation is `NOT VERIFIED` because the backend only inspects a single still image.**
4. **Resistance against virtual camera HAL injection is `NOT VERIFIED` until Android hardware-backed key attestation is implemented.**
5. **No claims of Aadhaar FaceRD v2.0 certification or Level 2 PAD compliance may be made in this state.**
