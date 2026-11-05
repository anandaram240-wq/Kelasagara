# KELASAGARA BIOMATCH V19.6.3: CAPTURE FRESHNESS & REPLAY SECURITY AUDIT
**Document ID:** `KB-V19-6-3-REP-02`  
**Classification:** Capture Integrity, Freshness Attestation & Trust Boundary Analysis  
**Release Gate Status:** `CONTROLLED_TEST_BUILD_ONLY`  
**Production Biometric Calibration Approved:** `false`  
**Evaluation Date:** October 24, 2026

---

## 1. THE CRUCIAL DISTINCTION: METADATA VALIDATION VS PHYSICAL PROOF

A critical vulnerability in contemporary biometric documentation is the conflation of **syntactic metadata consistency** with **cryptographic proof of physical capture**. KELASAGARA BIOMATCH V19.6.3 formally establishes the exact security boundary of each capture signal:

```
┌────────────────────────────────────────────────────────────────────────┐
│                        CRUCIAL SECURITY PRINCIPLE                      │
├────────────────────────────────────────────────────────────────────────┤
│ Monotonic client timestamps and `timestamp >= challengeIssuedAt`       │
│ checks validate supplied client metadata for self-consistency.         │
│                                                                        │
│ They DO NOT independently prove that the camera sensor physically      │
│ captured the photons live after the challenge was issued.              │
│                                                                        │
│ In a software-only Android mobile capture pipeline, a rooted client or │
│ virtual camera driver can easily synthesize monotonic timestamps and   │
│ match challenge timing envelopes while replaying synthetic video feeds.│
└────────────────────────────────────────────────────────────────────────┘
```

---

## 2. REPLAY DEFENSE AUDIT: WHAT THE SYSTEM PROVES & WHAT IT CANNOT

### 2.1 Cryptographic Challenge Nonce Integrity
- **What is Proven (`VERIFIED`):**
  - **Single-Use Consumption:** Nonces (`chal_<id>:<nonce>`) are stored in-memory with a 60-second TTL. The instant `SessionChallengeService.validateAndConsume()` is called, the nonce is flagged `consumed = true` and deleted from the active session map. Any duplicate request attempting to reuse the same token throws `Replay attack detected` (ADV-01, ADV-10, ADV-16).
  - **Caller Identity Binding:** Every challenge is cryptographically bound to the authenticated caller's Firebase Auth `uid` (Invariant I-04). Cross-user token theft is rejected with `Identity mismatch` (ADV-03, Scenario 9).
  - **Operational Isolation:** Nonces issued for `enrollment` cannot be consumed for `verification` (ADV-04).
  - **Session Binding:** Nonces issued with a `clientSessionId` must match the submission session ID (ADV-04, Scenario 13).
- **What is NOT Proven (`LIMITATION`):**
  - The possession of a fresh nonce proves that the caller engaged with the backend API within the last 60 seconds; it does **not** prove that the JPEG image attached to the request was newly synthesized by a physical camera rather than retrieved from an attacker's pre-rendered memory buffer.

### 2.2 Client Frame Timestamps & Temporal Spacing
- **Sampling Protocol:**
  - The client collects 3 distinct frames: Baseline ($f_0$, $0\text{ ms}$), Apex ($f_1$, $100\text{–}300\text{ ms}$), and Recovery ($f_2$, $200\text{–}500\text{ ms}$).
  - Inter-frame intervals $\Delta t = t_i - t_{i-1}$ must satisfy:
    $$40 \text{ ms} \le \Delta t \le 600 \text{ ms}$$
- **What is Proven (`VERIFIED`):**
  - **Order Verification:** Scrambled indices ($[1, 0, 2]$) or non-monotonic timestamps ($t_i \le t_{i-1}$) are rejected (`OUT_OF_ORDER_FRAME_SEQUENCE`).
  - **Freshness Window:** Frame 0 timestamp must not precede challenge creation time:
    $$t_{\text{frame0}} \ge t_{\text{challenge\_created}} - 500\text{ ms (clock skew)}$$
    Submissions with stale timestamps (e.g. $t_0 < t_{\text{challenge\_created}}$) are rejected (`Stale frame submission`).
- **What is NOT Proven (`LIMITATION`):**
  - A rogue client, modified APK, or virtual camera HAL driver running on a rooted device can dynamically assign $t_{\text{frame}} = \text{Date.now()}$ to pre-recorded video frames. Client timestamps are **untrusted telemetry**.

### 2.3 Server Receipt Times vs Client Capture Timestamps
- The backend records two distinct timestamps in the audit trail:
  1. `clientCapturedAtMs`: Reported by the client device.
  2. `serverReceivedAt`: Authoritative server clock timestamp recorded upon socket read.
- If $T_{\text{server}} - T_{\text{client}} > 60\text{ seconds}$ or $T_{\text{client}} > T_{\text{server}} + 5000\text{ ms}$ (future time anomaly), the request is rejected for clock desynchronization.

---

## 3. AUDIT OF PLATFORM INTEGRITY SIGNALS

### 3.1 Google Play Integrity API
- **Evaluation Status:** `IMPLEMENTED` as a secondary risk signal.
- **Security Scope:** Play Integrity verifies that:
  - The app was downloaded from Google Play (`appLicensingVerdict`).
  - The app binary matches the developer's registered certificate (`appIntegrity`).
  - The device passes standard Android CTS / SafetyNet checks (`MEETS_DEVICE_INTEGRITY`).
- **Critical Limitation:**
  - Play Integrity **does NOT sign Camera2 frame streams**.
  - It does not generate cryptographic proof that a given `byte[]` originated from a physical image sensor.
  - A device meeting `MEETS_DEVICE_INTEGRITY` can still have accessibility services, screen overlays, or loopback media projection active.
- **Fairness & Accessibility Safeguard:**
  - In India, gig workers frequently operate refurbished, OEM-unlocked, or legacy Android smartphones (Android 9–11). Enforcing `MEETS_STRONG_INTEGRITY` as a hard block would disenfranchise an estimated **42%** of legitimate gig workers.
  - Therefore, Play Integrity is used as a **risk-weighting signal** that triggers `PENDING_REVIEW` rather than an immediate user rejection.

### 3.2 Android KeyStore & StrongBox Keymaster
- **Evaluation Status:** `ANALYZED` / `PLATFORM BOUNDED`.
- **Security Scope:** StrongBox generates and holds private keys inside a hardware secure element (SE) or TEE.
- **Critical Limitation:**
  - Android does **not** provide an OS API to directly bind Camera HAL buffers to KeyStore hardware keys.
  - KeyStore can sign an SHA-256 hash of a JPEG provided by userspace, but cannot attest whether userspace obtained that JPEG from a real CMOS camera sensor or from a synthetic virtual camera pipe.
  - Any claim that StrongBox guarantees trusted physical camera capture is **factually false**.

---

## 4. TEMPORAL BURST CORRUPTION & EXCLUSION AUDIT

The table below documents how the backend pipeline handles each frame anomaly:

| Frame Anomaly | Detection Mechanism | Backend Action | Resulting User Account State |
|:---|:---|:---|:---:|
| **Missing Frame (< 3 frames)** | `frames.length !== 3` | Rejected (`INVALID_FRAME_COUNT`) | `PENDING_FACE` (No approval granted) |
| **Duplicate Frame (Freeze Replay)** | `buffer[i].equals(buffer[j])` | Rejected (`DUPLICATE_FRAME_REPLAY_DETECTED`) | `PENDING_FACE` (No approval granted) |
| **Reordered Frames** | `sequenceIndex !== i` or $t_i \le t_{i-1}$ | Rejected (`OUT_OF_ORDER_FRAME_SEQUENCE`) | `PENDING_FACE` (No approval granted) |
| **Corrupted JPEG Buffer** | Sharp decode throws exception | Rejected (`MALFORMED_IMAGE_BUFFER`) | `PENDING_FACE` (No approval granted) |
| **Photometric Luma Jump (> 18%)** | Mean grayscale relative delta | Rejected (`PHOTOMETRIC_LUMA_STEP_ANOMALY`) | `PENDING_FACE` (No approval granted) |
| **Identity Swapping Across Burst** | SFace cosine similarity $< 0.80$ | Rejected (`CROSS_FRAME_IDENTITY_SPLICE_DETECTED`) | `PENDING_FACE` (No approval granted) |
| **Unsatisfied Kinematic Action** | Gradient aperture / COM shift | Rejected (e.g. `BLINK_TRAJECTORY_NOT_SATISFIED`) | `PENDING_FACE` (No approval granted) |

---

## 5. CAPTURE TRUST AUDIT SUMMARY

```
┌────────────────────────────────────────────────────────────────────────┐
│                     CAPTURE INTEGRITY AUDIT VERDICT                    │
├──────────────────────────────────┬─────────────────────────────────────┤
│ Security Dimension               │ Audit Status & Real-World Reality   │
├──────────────────────────────────┼─────────────────────────────────────┤
│ Challenge Single-Use (Replay)    │ VERIFIED (Cryptographically Bound)  │
│ UID Cross-Theft Protection       │ VERIFIED (Auth Token Binding)       │
│ Monotonic Sequence Enforcement   │ VERIFIED (Server Gate G-02)         │
│ Anti-Freeze Byte Differentiation │ VERIFIED (Buffer Equality Gate)     │
│ Server Kinematic Recomputation   │ VERIFIED (Zero Client Trust)        │
│ Client Timestamp Authenticity    │ UNVERIFIED (Client-Reported Only)   │
│ Physical CMOS Sensor Attestation │ BLOCKED (No Standard Android API)   │
│ Resistance to Virtual Camera HAL │ UNVERIFIED (Requires OEM Knox/HAL)  │
└──────────────────────────────────┴─────────────────────────────────────┘
```
