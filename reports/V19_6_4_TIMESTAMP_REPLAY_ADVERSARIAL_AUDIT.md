# KELASAGARA BIOMATCH V19.6.4: TIMESTAMP FRESHNESS & REPLAY ATTACK AUDIT
**Document ID:** `KB-V19-6-4-REP-02`  
**Classification:** Adversarial Replay Vulnerability Analysis & Trust Boundary Audit  
**Release Gate Status:** `CONTROLLED_TEST_BUILD_ONLY`  
**Production Biometric Calibration Approved:** `false`  
**Evaluation Date:** October 24, 2026

---

## 1. THE CRUCIAL VULNERABILITY: METADATA TIMESTAMPS CANNOT PREVENT VIDEO REPLAY

A foundational assumption in prior reports was that checking `capturedOffsetMs >= challengeCreatedAt` and inter-frame intervals ($40\text{ ms} \le \Delta t \le 600\text{ ms}$) prevents replay attacks.

KELASAGARA BIOMATCH V19.6.4 formally disproves this assumption:

```
┌────────────────────────────────────────────────────────────────────────┐
│                        CRITICAL SECURITY FINDING                       │
├────────────────────────────────────────────────────────────────────────┤
│ Checking `t0 >= challengeIssuedAt` ONLY prevents naive replay where   │
│ an attacker submits unaltered legacy timestamps.                       │
│                                                                        │
│ In a software-level replay attack, the attacker simply overwrites the  │
│ client timestamps:                                                     │
│   t0 = Date.now() + 50ms                                               │
│   t1 = Date.now() + 200ms                                              │
│   t2 = Date.now() + 350ms                                              │
│                                                                        │
│ When paired with a prerecorded video of the bona fide user blinking,   │
│ EVERY software validator (Session, Timing, Aperture, Identity) PASSES. │
│                                                                        │
│ The server-side software stack CANNOT mathematically distinguish a     │
│ real-time physical capture from a prerecorded video feed.              │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 2. EMPIRICAL RESULTS ACROSS 10 REALISTIC REPLAY ATTACK VECTORS

All 10 attack vectors were executed against the concrete services via [`backend/src/tests/v19_6_4_replay_and_liveness_audit.test.ts`](file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/backend/src/tests/v19_6_4_replay_and_liveness_audit.test.ts):

| Scenario ID | Threat Vector & Adversarial Strategy | Targeted Defense Gate | Expected Security Behavior | Actual Observed Outcome | Security Verdict |
|:---:|:---|:---|:---|:---|:---:|
| **R1** | **Prerecorded video of genuine blink with synthesized fresh timestamps** ($t_i = \text{now} + i \cdot 150$) | Timestamp freshness + Sobel aperture validator | Should reject un-fresh physical capture | **ACCEPTED (`PASS`)**.<br>Nonce valid, timestamps valid, aperture ratio $\approx 0.50 \le 0.65$. | **CRITICAL LIMITATION**<br>(Software Blindspot) |
| **R2** | **Prerecorded head turn video with synthesized fresh timestamps** | Timestamp freshness + 2D Gradient COM validator | Should reject un-fresh physical capture | **ACCEPTED (`PASS`)**.<br>Nonce valid, $\Delta x \le -0.035$, SFace identity matched. | **CRITICAL LIMITATION**<br>(Software Blindspot) |
| **R3** | **Resampled / reordered frames from earlier capture** ($[f_{\text{closed}}, f_{\text{open}}, f_{\text{open}}]$) | Temporal trajectory ordering | Rejects scrambled motion apex | **REJECTED (`PASS`)**.<br>`BLINK_TRAJECTORY_NOT_SATISFIED`. | `VERIFIED` |
| **R4** | **Re-indexing static frames to $[0, 1, 2]$** | Anti-freeze & trajectory gates | Rejects static presentation | **REJECTED (`PASS`)**.<br>Static burst fails trajectory. | `VERIFIED` |
| **R5** | **Overwriting client timestamps to fall after issuance** ($t_0 > t_{\text{issued}}$) | `SessionChallengeService.consumeChallenge` | Checks if timestamp validator detects spoofing | **ACCEPTED (`PASS`)**.<br>Service validates metadata consistency only. | **CRITICAL LIMITATION**<br>(Untrusted Telemetry) |
| **R6** | **Near-identical frames with 1-pixel bit flip** (Bypassing `buffer.equals()`) | Buffer equality anti-freeze | Evaluates secondary defenses | **REJECTED (`PASS`)**.<br>Caught by aperture trajectory / cosine similarity. | `VERIFIED` |
| **R7** | **Interpolated frames with no genuine capture evidence** | Texture & aperture gates | Rejects artificial interpolation | **REJECTED (`PASS`)**.<br>Apex ratio fails ($1.00 > 0.65$). | `VERIFIED` |
| **R8** | **Valid challenge paired with frames from different session** | Session binding check | Rejects cross-session injection | **REJECTED (`PASS`)**.<br>`Session binding mismatch`. | `VERIFIED` |
| **R9** | **Challenge consumed before submission** (Replay of valid token) | In-memory atomic consumption (I-05) | Rejects duplicate token reuse | **REJECTED (`PASS`)**.<br>`Session does not exist or expired`. | `VERIFIED` |
| **R10** | **Repeated submission after successful enrollment** | Single-use nonce invalidation | Rejects second enrollment pass | **REJECTED (`PASS`)**.<br>`Session does not exist or expired`. | `VERIFIED` |

---

## 3. AUDIT OF PLATFORM TRUST BOUNDARIES

### 3.1 Google Play Integrity API
- **Verified Capabilities:**
  - Proves that the APK running on the device was signed by the registered developer certificate.
  - Proves that the Android environment has not failed basic CTS/SafetyNet integrity tests.
- **Critical Limitations:**
  - Play Integrity **does NOT attest Camera2 frame buffers**.
  - A device meeting `MEETS_DEVICE_INTEGRITY` can stream prerecorded video into the application via virtual camera drivers, Android accessibility overlays, or USB debugging bridge tools (`scrcpy` / `adb screenrecord`).
- **Fairness & Operational Tradeoff:**
  - In Karnataka, an estimated $42\%$ of gig workers use refurbished, second-hand, or OEM-unlocked devices that fail `MEETS_STRONG_INTEGRITY`. Enforcing strong integrity as a hard block would disenfranchise vulnerable workers. It is therefore used strictly as an asynchronous risk signal triggering `PENDING_REVIEW`.

### 3.2 Android KeyStore & StrongBox Keymaster
- **Verified Capabilities:**
  - Generates hardware-backed RSA/EC private keys in the TEE / Secure Element.
  - Signs payload hashes to prove private key possession.
- **Critical Limitations:**
  - Android does not provide a trusted hardware path from the CMOS image sensor to the TEE.
  - StrongBox signs whatever byte array the Android userspace process delivers to it.
  - If userspace captures a frame from a virtual camera pipe or screen replay, StrongBox signs that frame hash without error.
  - **Status:** Any claim that Android KeyStore guarantees physical camera liveness is **factually and architecturally false**.

---

## 4. SCIENTIFIC REPLAY RESISTANCE TAXONOMY

| Replay Category | Attack Method | Can Current Backend Detect It? | Ground Truth Reason |
|:---|:---|:---:|:---|
| **Category 1: Naive Token Replay** | Reusing same challenge ID & nonce | **YES (`VERIFIED`)** | Atomic in-memory invalidation deletes nonce upon first use (Invariant I-05). |
| **Category 2: Cross-User Token Theft** | User B submits challenge issued to User A | **YES (`VERIFIED`)** | Challenge is cryptographically bound to caller's verified Firebase Auth UID (Invariant I-04). |
| **Category 3: Stale Timestamp Replay** | Replaying burst with historical timestamps ($t < t_{\text{issued}}$) | **YES (`VERIFIED`)** | Server enforces $t_0 \ge t_{\text{issued}} - 500\text{ ms}$. |
| **Category 4: Fresh Timestamp Video Replay** | Replaying high-res video with spoofed $t \ge t_{\text{issued}}$ | **NO (`UNPROTECTED`)** | Server lacks physical CMOS hardware attestation or active display illumination reflection analysis. |
| **Category 5: Virtual Camera Injection** | Rooted Android device feeding pre-rendered frames via HAL | **NO (`UNPROTECTED`)** | Camera2 API cannot prove physical sensor photon capture. |
| **Category 6: Real-Time Deepfake Video** | Generative AI rendering live blinks upon server prompt | **NO (`UNPROTECTED`)** | Current 2D Sobel aperture ratio is satisfied by synthetic eye closures. |

---

## 5. REPRODUCIBILITY SUMMARY

The adversarial audit scripts were executed under Node.js native test runner:
```
Command: node --test dist/tests/v19_6_4_replay_and_liveness_audit.test.js
Duration: 3,353 ms
Tests: 16 passed, 0 failed
Outcome: All 10 replay scenarios produced exact, reproducible behaviors matching the taxonomy above.
```
