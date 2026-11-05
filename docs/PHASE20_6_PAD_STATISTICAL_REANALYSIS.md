# PHASE 20.6 PAD STATISTICAL REANALYSIS
## Disaggregated ISO/IEC 30107-3 Presentation Attack Detection Re-evaluation and Software Injection Separation

**Project:** Kelasagara Major Project  
**System:** Worker Marketplace & Biometric Identity Platform  
**Phase:** 20.6 (Biometric Evidence Integrity & Controlled Pilot Readiness)  
**Standard:** ISO/IEC 30107-3:2023 (Biometric Presentation Attack Detection)  
**Lead Auditor:** Presentation Attack Detection Research Engineer & Independent Security Evaluator  
**Date:** 2026-10-31  

---

## 1. PRESENTATION ATTACK DETECTION METRICS RECALCULATION

Phase 20.5 aggregated all Presentation Attack Instruments (PAIs) into a single headline number: $\text{APCER} = 1.67\%$ (2 misses in 120 attempts) and $\text{BPCER} = 2.67\%$ (4 false rejections in 150 bona fide presentations).

In accordance with ISO/IEC 30107-3:2023, reporting an aggregate APCER across heterogeneous attack species obscures critical vulnerabilities in specific instruments. The Attack Presentation Classification Error Rate must be computed individually per PAI species $i$:
$$\text{APCER}_i = \frac{\text{Accepted Attack Presentations for Species } i}{\text{Total Attack Presentations for Species } i}$$
$$\text{APCER}_{\text{overall}} = \max_i (\text{APCER}_i) \quad \text{or weighted sum}$$

---

## 2. DISAGGREGATED PAI EVALUATION TABLE

Recalculated metrics across all 8 PAI species evaluated in the test framework:

```
┌────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                        DISAGGREGATED ISO/IEC 30107-3 PAI PERFORMANCE MATRIX                            │
├────────────────────────────┬──────────┬──────────┬──────────┬──────────┬───────────────┬───────────────┤
│ Attack Instrument Species  │ Attempts │ Accepted │ Rejected │ APCER    │ 95% Two-Sided │ 95% One-Sided │
├────────────────────────────┼──────────┼──────────┼──────────┼──────────┼───────────────┼───────────────┤
│ 1. PRINTED_PHOTO_MATTE     │ 15       │ 0        │ 15       │ 0.00%    │ [0.00%, 21.8%]│ 18.1%         │
│ 2. PRINTED_PHOTO_GLOSSY    │ 15       │ 0        │ 15       │ 0.00%    │ [0.00%, 21.8%]│ 18.1%         │
│ 3. SCREEN_REPLAY_SMARTPHONE│ 15       │ 0        │ 15       │ 0.00%    │ [0.00%, 21.8%]│ 18.1%         │
│ 4. SCREEN_REPLAY_TABLET    │ 15       │ 2        │ 13       │ 13.33%   │ [1.66%, 40.5%]│ 33.7%         │
│ 5. SCREEN_REPLAY_4K_MONITOR│ 15       │ 0        │ 15       │ 0.00%    │ [0.00%, 21.8%]│ 18.1%         │
│ 6. PRE_RECORDED_VIDEO_LOOP │ 15       │ 0        │ 15       │ 0.00%    │ [0.00%, 21.8%]│ 18.1%         │
│ 7. SYNTHETIC_DEEPFAKE_VIDEO│ 15       │ 0        │ 15       │ 0.00%    │ [0.00%, 21.8%]│ 18.1%         │
│ 8. PARTIAL_FACIAL_CUTOUT   │ 15       │ 0        │ 15       │ 0.00%    │ [0.00%, 21.8%]│ 18.1%         │
├────────────────────────────┼──────────┼──────────┼──────────┼──────────┼───────────────┼───────────────┤
│ OVERALL AGGREGATE          │ 120      │ 2        │ 118      │ 1.67%    │ [0.20%, 5.89%]│ 4.98%         │
└────────────────────────────┴──────────┴──────────┴──────────┴──────────┴───────────────┴───────────────┘
```

### Critical Finding:
When disaggregated, **Species 4 (SCREEN_REPLAY_TABLET)** exhibits an empirical $\text{APCER} = \mathbf{13.33\%}$ ($2 / 15$). Presenting the headline error as $1.67\%$ diluted the true vulnerability of the temporal blink detector when confronted with a high-brightness tablet display displaying a synchronized eye-blink video.

---

## 3. BONA FIDE EVALUATION (BPCER)

- **Total Bona Fide Capture Presentations:** 150
- **False Rejections (Live User Rejected as Spoof):** 4
- **Bona Fide Presentation Classification Error Rate (BPCER):**
  $$\text{BPCER} = \frac{4}{150} = \mathbf{2.67\%}$$
- **Exact Clopper-Pearson 95% Two-Sided CI:** $[0.73\%, 6.69\%]$
- **One-Sided 95% Upper Bound:** $5.75\%$
- **Root Cause of Bona Fide Rejections:**
  * 2 occurrences: Involuntary rapid eye tremor / incomplete blink cycle yielding $\text{EAR}_{\text{ratio}} > 0.65$.
  * 2 occurrences: Extreme top-down warehouse lighting where deep ocular shadows degraded Sobel edge energy below the live aperture floor.

---

## 4. SEPARATION OF PRESENTATION ATTACKS VS SOFTWARE INJECTION

A critical failure in biometric reporting is presenting ISO/IEC 30107-3 PAD compliance as evidence of resistance against software-level cyber attacks.

Kelasagara enforces strict conceptual and architectural separation:

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                  PHYSICAL PAD (ISO 30107-3) vs SOFTWARE INJECTION ATTACKS               │
├───────────────────────────────────┬────────────────────────────────────────────────────┤
│ Physical Presentation Attacks     │ Software / Protocol Injection Attacks              │
├───────────────────────────────────┼────────────────────────────────────────────────────┤
│ • Matte & glossy printed photos   │ • Request payload tampering (`requestHash`)        │
│ • Smartphone / tablet replay      │ • Replay of previously consumed challenge nonces   │
│ • Cutout masks & prosthetic eyes  │ • Forged Android Key Attestation certificates      │
│ • Deepfake video screens          │ • Stolen Firebase Auth ID tokens                   │
├───────────────────────────────────┼────────────────────────────────────────────────────┤
│ DEFENSE: Sensor-Level Analysis    │ DEFENSE: Cryptographic Architecture                │
│ • Temporal EAR blink compression  │ • Play Integrity binding (`PLAY_INTEGRITY_V2`)     │
│ • Photometric luma step stability │ • Device-bound ECDSA P-256 signatures              │
│ • Sobel high-frequency texture    │ • One-time nonce consumption ledger                │
└───────────────────────────────────┴────────────────────────────────────────────────────┘
```

### Mandatory Compliance Rule:
Passing the Android Keystore Attestation and Play Integrity test suite **does not** prove Presentation Attack Detection. Passing the PAD liveness tests **does not** prove network injection security. The two disciplines must be audited and reported separately.

---

## 5. DISCLAIMER ON CERTIFICATION

**The existing Kelasagara biometric engine is NOT certified under ISO/IEC 30107-3 or ISO/IEC 19795-1 by any accredited independent laboratory (e.g. iBeta, FIDO, or NIST).** The evaluation performed herein represents internal academic and research testing. No marketing or compliance claims of third-party certification may be made.
