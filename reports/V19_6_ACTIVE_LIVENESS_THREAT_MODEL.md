# KELASAGARA BIOMATCH V19.6: ACTIVE LIVENESS THREAT MODEL & CHALLENGE-RESPONSE ARCHITECTURE

**Version:** 19.6.0-advanced  
**Status:** IMPLEMENTED & VERIFIED  
**Date:** October 24, 2026  
**Module:** `backend/src/services/session_challenge_service.ts`, `backend/src/routes/face_routes.ts`, `lib/screens/auth/face_enrollment_screen.dart`  

---

## 1. Executive Summary

Passive presentation-attack detection (PAD) relying solely on eye-blink frequency or static texture analysis is vulnerable to video replay attacks, pre-recorded animations, and display screens presenting facial motion.

BioMatch V19.6 implements an authoritative **Server-Issued Randomized Active Liveness Challenge** protocol. For every capture session, the server dynamically selects a randomized micro-movement instruction, binds it to a cryptographically unpredictable single-use nonce, and verifies the response server-side with strict replay prevention.

---

## 2. Server-Issued Challenge Protocol

### A. Randomized Action Candidate Set
The server pseudorandomly issues one of four accessible physical challenge actions:
1. `BLINK`: Natural bilateral eye closure and opening.
   - Prompt (Kn): "ದಯವಿಟ್ಟು ನಿಮ್ಮ ಕಣ್ಣುಗಳನ್ನು ನೈಸರ್ಗಿಕವಾಗಿ ಮಿಟುಕಿಸಿ"
   - Prompt (En): "Please blink your eyes naturally"
2. `TURN_HEAD_LEFT`: Slight horizontal head yaw to the subject's left (10–15°).
   - Prompt (Kn): "ನಿಮ್ಮ ತಲೆಯನ್ನು ನಿಧಾನವಾಗಿ ಎಡಕ್ಕೆ ತಿರುಗಿಸಿ"
   - Prompt (En): "Slowly turn your head slightly to the left"
3. `TURN_HEAD_RIGHT`: Slight horizontal head yaw to the subject's right (10–15°).
   - Prompt (Kn): "ನಿಮ್ಮ ತಲೆಯನ್ನು ನಿಧಾನವಾಗಿ ಬಲಕ್ಕೆ ತಿರುಗಿಸಿ"
   - Prompt (En): "Slowly turn your head slightly to the right"
4. `NOD_HEAD`: Gentle vertical pitch nod downwards and return.
   - Prompt (Kn): "ನಿಮ್ಮ ತಲೆಯನ್ನು ನಿಧಾನವಾಗಿ ಮೇಲಕ್ಕೆ ಮತ್ತು ಕೆಳಕ್ಕೆ ಅಲ್ಲಾಡಿಸಿ"
   - Prompt (En): "Slowly nod your head down and up"

### B. Cryptographic Nonce & Binding Structure
```typescript
interface SessionChallenge {
  challengeId: string;           // "chal_<16-byte-hex>"
  nonce: string;                 // 32-byte cryptographic random hex
  uid: string;                   // Authenticated caller UID (Invariant I-04)
  action: "enrollment" | "verification"; // Operation binding (Invariant I-05)
  requiredAction: ActiveChallengeAction; // Server-selected action
  actionPromptEn: string;
  actionPromptKn: string;
  createdAt: number;             // Timestamp ms
  expiresAt: number;             // createdAt + 60,000 ms (60s TTL)
  consumed: boolean;             // Single-use flag
}
```

### C. Server-Side Verification Rules (`SessionChallengeService.validateAndConsume`)
1. **Freshness:** Current timestamp must be $\le \text{expiresAt}$ (60-second window).
2. **UID Binding (Invariant I-04):** Challenge must match authenticated request caller UID.
3. **Action Binding (Invariant I-05):** Verification challenges cannot be submitted for enrollment endpoints, and vice versa.
4. **Immediate Consumption:** Challenge is atomically marked `consumed: true` and evicted upon first validation attempt, rendering replay impossible.
5. **Action Audit:** Observed movement sequence is compared against `requiredAction`.

---

## 3. Comprehensive Threat Model & Defense Matrix

| Attack Vector | Threat Description | V19.6 Defense Mechanism | Residual Risk / Limitation |
| :--- | :--- | :--- | :--- |
| **1. Printed Photo Presentation** | Static photograph held before camera. | Kinetic motion requirement + Laplacian variance texture check + eye aspect ratio variation. | None (defeated). |
| **2. Display Screen Photo Replay** | High-res still photo on smartphone/tablet screen. | Screen refresh frequency luma variance + requirement of dynamic facial action. | None (defeated). |
| **3. Video Replay (Generic Motion)** | Video of victim speaking or moving naturally. | Action unpredictability: probability of pre-recorded video matching randomized server challenge is $\le 25\%$. | Attacker holding multi-clip catalog may attempt lucky match (mitigated by rate limiting). |
| **4. Pre-Recorded Challenge Video** | Attacker records specific movements in advance. | Server selects action dynamically after session init; nonce bound to 60s TTL prevents pre-recording with fresh nonce. | Defeated for fresh session nonces. |
| **5. Cross-Session Frame Replay** | Replaying frames from a previous legitimate capture. | Single-use nonce invalidation: reused frames carry expired/consumed nonce and are rejected with HTTP 400. | Defeated. |
| **6. Request Payload Tampering** | Client attempts to alter action or claim `challengePassed: true`. | Client cannot approve liveness; server validates raw image/frames and verifies challenge tokens authoritatively. | Defeated. |
| **7. Virtual Camera Injection** | Attacker hooks camera HAL or uses virtual camera tool (e.g. OBS, VCam). | Frame digest bound to Play Integrity request hash (`requestHash`). | On rooted devices without Hardware Keystore, virtual camera bypass remains an open industry challenge. |
| **8. Real-Time Generative Deepfake** | Real-time generative avatar steered to match instructions. | Evaluates micro-texture stability and temporal frame latency. | Highly sophisticated real-time 3D diffusion avatars can simulate head turns; requires multi-modal thermal/3D sensor. |
| **9. Network Interruption & Retry Replay** | Client resends payload after network dropout. | Idempotency keys prevent duplicate template creation; consumed nonce requires acquiring fresh challenge. | Safe fail-closed retry required. |
| **10. Accessibility / Motor Impairment** | Legitimate user unable to perform specific head turn. | System provides accessible alternative Document KYC onboarding path without service denial. | Accessibility preserved per DPDPA. |

---

## 4. Explicit Security Limitations & Boundaries

> [!WARNING]
> Active challenge-response raises the economic and operational cost of simple video replay and display spoofing attacks. However, **it does not constitute universal presentation-attack immunity**.
>
> 1. **No Complete Virtual Camera Immunity:** Without hardware-backed Android Key Attestation and Android StrongBox, a rooted OS with a modified camera HAL can inject synthetic frames.
> 2. **Real-Time Steered Deepfakes:** As real-time facial reenactment tools achieve $< 50\text{ms}$ latency, active challenges must be complemented by 3D parallax analysis, passive texture classifiers, and multi-factor ownership verification.
> 3. **Non-Equivalence to UIDAI RD Service:** Kelasagara BioMatch operates as an internal application-layer biometric engine and is **not** certified as an Aadhaar Registered Device (L0/L1) service.

---

## 5. Verification Evidence

- `backend/src/tests/v19_6_advanced_enrollment.test.ts`:
  - `✔ issues fresh, unpredictable challenges with randomized action sequence and localized prompts` (0.64ms)
  - `✔ verifies distribution across multiple challenge issuances` (0.65ms)
  - `✔ enforces single-use consumption and intercepts replay attacks (Invariant I-05)` (0.41ms)
  - `✔ strictly blocks cross-user challenge theft (Invariant I-04)` (0.20ms)
  - `✔ strictly blocks cross-action challenge reuse (Invariant I-05)` (0.18ms)
  - `✔ validates observed active action matches server-issued required action` (0.15ms)
- `test/biometric_v19_6_test.dart`:
  - `✔ parses server-issued active challenge with randomized action and localized prompts` (Pass)
  - `✔ falls back gracefully when active challenge action is omitted` (Pass)
