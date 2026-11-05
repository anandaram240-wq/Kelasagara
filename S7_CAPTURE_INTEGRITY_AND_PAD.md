# KELASAGARA BIOMATCH · STAGE S7 CAPTURE INTEGRITY AND PRESENTATION ATTACK DETECTION (S7_CAPTURE_INTEGRITY_AND_PAD.md)

**Classification:** Biometric Presentation Attack Detection (PAD) & Capture Integrity Audit  
**Stage:** S7  
**Date:** 2026-10-11  
**Reference Framework:** ISO/IEC 30107-3:2023 (Testing and Reporting)  

---

## 1. Executive Summary & Honest Capability Characterization

Biometric presentation attack detection is frequently overstated in commercial marketing. In accordance with Stage S7 directives:
- **No False Certification Claims:** The Kelasagara mobile capture flow does **NOT** claim STQC Level-0 or Level-1 hardware certification.
- **Accurate Classification:** The implemented system consists of **heuristic multi-action challenge-response sequences** coupled with **server-side landmark trajectory verification** and **cryptographic nonce binding**.
- **Separation of Layers:** Backend replay attacks and physical camera sensor presentation attacks represent distinct threat classes governed by different security controls.

---

## 2. Capture Integrity & Replay Defenses (Software Security)

```mermaid
sequenceDiagram
    autonumber
    actor Attacker
    participant API as BioMatch API (/verify-1to1)
    participant DB as Cloud Firestore Nonce Ledger

    Attacker->>API: Resubmit intercepted valid payload with nonce "chal_98a2..."
    API->>DB: Check nonce status in atomic transaction
    DB-->>API: Nonce marked "CONSUMED" at 2026-10-11T00:43:05Z
    API-->>Attacker: 400 Bad Request (CHALLENGE_ALREADY_CONSUMED)
    Note over API: Replay attack intercepted; zero template access
```

### 2.1 Single-Use Nonce Ledger (`chal_*`)
- **Generation:** 96-bit CSPRNG entropy issued at `POST /api/biometrics/challenge`.
- **Identity & Action Binding:** Every nonce records `{uid, action, issuedAt, expiresAt}`.
- **Atomic Consumption:** Consumed within a Firestore transaction prior to model inference. Replay attempts receive HTTP 400 (`CHALLENGE_ALREADY_CONSUMED`).
- **Cross-Action / Cross-User Rejection:** Verification nonces cannot be used for enrollment; User A's nonce cannot be consumed by User B.

---

## 3. Presentation Attack Detection (PAD) Evaluation (ISO/IEC 30107-3)

Laboratory evaluation against controlled presentation attack species:

| Attack Category | Attack Instrument | Defense Mechanism | Test Attempts | APCER | BPCER | Defensive Effectiveness |
| :--- | :--- | :--- | :---: | :---: | :---: | :--- |
| **Level 1 (Low)** | 2D Printed Color Photo (Paper/Cardstock) | Server landmark variance threshold ($< 0.5\text{px}$ flags static attack) | 50 | 2.0% | 1.5% | **Highly Effective** (Catches static presentation) |
| **Level 1 (Low)** | Video Replay on iPad / Tablet Screen | Randomized multi-gesture sequence (e.g. smile $\to$ turn left, 4s timeout) | 50 | 4.0% | 2.0% | **Effective** (Defeats pre-recorded video loops) |
| **Level 2 (Medium)**| Virtual Camera Injection / Deepfake Stream | None at sensor layer (Software client only) | 20 | 30.0% | 2.5% | **Known Residual Risk** (Requires hardware attestation) |

### 3.1 Known Residual Risk: Sensor Trust Boundary
Without Android Hardware KeyMint / Google Play Integrity API attestation, a rooted Android device or modified emulator can hook the camera HAL driver (`CameraX`) and inject synthetic video frames into the application process.

### 3.2 Mitigation Roadmap for Release Stage S-2
For full consequential enforcement (Stage S-2):
1. Integrate Google Play Integrity API (`backend/src/services/device_attestation.ts`).
2. Verify hardware attestation token on backend before issuing capture nonces.
3. Restrict biometric verification to unrooted physical devices passing `MEETS_STRONG_INTEGRITY`.

---

## 4. Exit Gate S7-G06 Sign-Off

**Status:** `DONE-VERIFIED`  
**Evidence Artifacts:**
- `evidence/s7/pad_test_matrix.json`
- `evidence/s7/capture_replay_tests.json`
**Summary:** Physical and replay defenses characterized honestly. Software replay is fully mitigated; sensor-level deepfake injection is documented as a known prerequisite for Stage S-2.
