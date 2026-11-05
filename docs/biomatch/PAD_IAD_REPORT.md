# KELASAGARA BIOMATCH V7: PRESENTATION & INJECTION ATTACK EVALUATION REPORT

**Document ID:** `PIR-BIOMATCH-V7-001`  
**Phase:** Phase 6 (Liveness, Presentation-Attack and Injection-Attack Defense)  
**As-of Date:** 2026-10-10  
**Release Readiness Level:** **RRL-0 (Research Prototype)**  
**Classification:** Security Evaluation & Attack Matrix  
**Regulatory Standards:** ISO/IEC 30107-3 (Presentation Attack Detection) & CEN/TS 18099 (Injection Attack Detection).

---

## 1. APPENDIX G: COMPREHENSIVE ATTACK MATRIX

Every attack species identified in the V7 execution specification is evaluated below with its concrete technical classification (`TESTED | NOT TESTED | OUT OF SCOPE`), rationale, and owning test ID.

| Attack Track | Attack Category / Species | Attack Instrument / Method | Classification | Technical Rationale & Current State | Owning Test ID |
|---|---|---|---|---|---|
| **PAD** | **Printed Photograph (2D Print)** | High-res color photo on A4 paper presented to lens. | **`TESTED`** | Rejected by multi-frame EAR blink dynamics and texture frequency check. Verified in unit tests. | `TEST-PAD-001` |
| **PAD** | **On-Screen Photo (Digital Replay)** | Smartphone / tablet AMOLED screen displaying static selfie. | **`TESTED`** | Rejected by absence of eye blink transition and high specular screen reflection. | `TEST-PAD-001` |
| **PAD** | **Replayed Video on Screen** | Tablet screen playing high-res video of victim blinking. | **`NOT TESTED`** | Requires active chromatic reflection challenge to reliably defeat. Planned for hardware test bench. | `TEST-PAD-002` (Planned) |
| **PAD** | **Cut-out Photo with Eye Holes** | Printed photo with eye apertures worn by attacker to fake blinks. | **`NOT TESTED`** | Requires depth / edge contrast analysis along eyelid margins. Planned for physical testing. | `TEST-PAD-003` (Planned) |
| **PAD** | **2D Paper Mask** | Curved photo contoured around attacker's face. | **`NOT TESTED`** | Rejection requires 3D landmark mesh curvature validation. | `TEST-PAD-004` (Planned) |
| **PAD** | **3D Latex / Silicone Mask** | Anatomically accurate 3D facial mask. | **`OUT OF SCOPE`** | Requires specialized lab manufacturing (costs > ₹50,000 per mask); out of scope for software dev prototype. | N/A |
| **PAD** | **Extreme Low Light / Underexposure** | Presentation in dark room to hide photo boundaries. | **`TESTED`** | Caught by IQA quality gate (mean luminance $< 35$). Frame rejected before liveness. | `TEST-IQA-004` |
| **PAD** | **Multiple Faces in Frame** | Two persons attempting simultaneous presentation. | **`TESTED`** | Caught by face count filter ($N_{\text{faces}} > 1$). Frame rejected. | `TEST-IQA-006` |
| **PAD** | **Challenge Replay Attack** | Intercepting a valid video burst and replaying in next session. | **`TESTED`** | Defeated by server-side nonce binding: replayed session fails nonce check. | `TEST-NONCE-001` |
| **IAD** | **Cryptographic Nonce Replay Attack** | Intercepting a valid challenge nonce and reusing it for 2nd registration. | **`TESTED`** | Verified in red-team suite: `validateAndConsume` deletes nonce on first use; 2nd attempt throws "Replay attack detected". | `TEST-NONCE-001` |
| **IAD** | **Cross-User Token Theft** | Attacker steals victim's issued challenge token and sends it under attacker UID. | **`TESTED`** | Verified in red-team suite: Server asserts `challenge.uid === authenticated.uid`; throws "Identity mismatch". | `TEST-AUTH-001` |
| **IAD** | **Cross-Action Token Replay** | Replaying verification challenge token on enrollment endpoint. | **`TESTED`** | Verified in red-team suite: Server asserts `challenge.action === attemptedAction`; throws "Action mismatch". | `TEST-NONCE-001` |
| **IAD** | **Tampered Cryptographic Nonce** | Submitting an altered or forged 64-character hex nonce string. | **`TESTED`** | Verified in red-team suite: Server rejects string mismatch. | `TEST-NONCE-001` |
| **IAD** | **Software Virtual Camera Injection** | Routing video stream via OBS VirtualCam or v4l2loopback on Android. | **`NOT TESTED`** | Defended by Play Integrity device attestation (`MEETS_DEVICE_INTEGRITY`). Requires physical Android test runner. | `TEST-IAD-001` (Planned) |
| **IAD** | **Hooked Camera HAL / Frida Injection** | Injecting raw video frames directly into camera driver memory via Frida. | **`NOT TESTED`** | Requires Play Integrity hardware key attestation. Standalone Node dev backend tests logical rejection. | `TEST-IAD-002` (Planned) |
| **IAD** | **Repackaged / Modified APK** | Recompiling Kelasagara APK to bypass client-side liveness checks. | **`TESTED`** | Defeated by architecture: All authoritative decisions are made by server-side ONNX runtime; client liveness flags are advisory only. | `TEST-SRV-001` |
| **IAD** | **Hardware Capture-Card / UVC Injection** | Injecting digital HDMI video through USB-C UVC video grabber. | **`NOT TESTED`** | Requires native camera hardware enumeration checks (`isExternalCamera == false`). | `TEST-IAD-003` (Planned) |
| **IAD** | **Face-Swap / Deepfake Synthetic Stream** | Real-time generative AI face replacement on injected video stream. | **`NOT TESTED`** | Research-only artifact forensics; server-side challenge nonce reflection breaks pre-rendered deepfakes. | `TEST-IAD-004` (Planned) |

---

## 2. METRICS METHODOLOGY (ISO/IEC 30107-3 & CEN/TS 18099)

In adherence to ISO/IEC 30107-3:
1. **Attack Presentation Classification Error Rate (APCER):**
   Proportion of presentation attacks of a specific attack-instrument *species* incorrectly classified as bona fide presentations:
   $$\text{APCER}_{\text{species}} = \frac{|\text{Successful Spoofs of Species}|}{|\text{Total Attempts of Species}|}$$
   *Rule:* **APCER is never averaged across different species.** A system with 0% error on paper prints and 100% error on tablet screens has an overall vulnerability; reporting must break down APCER per species.
2. **Bona Fide Presentation Classification Error Rate (BPCER):**
   Proportion of genuine bona fide presentations incorrectly classified as presentation attacks (false rejection of real users).
3. **Statistical Sample Bounds on APCER (Rule of Three):**
   - 0 successful attacks in $30$ trials $\implies$ APCER is bounded at $\le 10.0\%$ at 95% confidence.
   - 0 successful attacks in $60$ trials $\implies$ APCER is bounded at $\le 5.0\%$ at 95% confidence.

---

## 3. RESIDUAL RISKS (OUTSIDE PAD / IAD SCOPE)

The following attack vectors are not presentation or injection attacks and represent acknowledged residual risks:

1. **Identical Twins & Close Lookalikes:**
   - Deep facial recognition algorithms exhibit intrinsic error rates on identical twins.
   - *Mitigation:* Mitigated by ADR-005 tri-state policy: Borderline similarities ($0.65 \le S < 0.74$) route to manual review where human inspectors cross-reference secondary demographic records (Aadhaar / Voter ID, date of birth, address).
2. **Coerced or Mule Enrollments:**
   - A genuine individual physical presents their own live face on behalf of a banned fraudster (proxy enrollment).
   - *Mitigation:* Liveness detection cannot distinguish a willing live accomplice from the account owner. Mitigated by operational platform safeguards: 1:1 on-site physical re-verification at high-value job sites and random step-up verification.
3. **Stolen Live-Present Victims:**
   - Victim physically coerced to look at a phone under duress.
   - *Mitigation:* Duress emergency reporting button and cooling-off periods on bank detail updates.
