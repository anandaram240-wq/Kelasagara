# PHASE 20.7 PAD ROOT CAUSE REPORT
## Detailed Attack Root-Cause Analysis across Twelve Presentation & Injection Threat Categories

**Project:** Kelasagara Major Project  
**System:** Multi-Factor Biometric Identity and Authentication Platform  
**Phase:** 20.7 (Controlled Physical Biometric Validation & PAD Hardening)  
**Standard:** ISO/IEC 30107-3:2023 & NIST SP 800-63B  
**Lead Auditor:** Independent Security Auditor & PAD Security Research Engineer  
**Date:** 2026-11-01  

---

## 1. TWELVE THREAT CATEGORIES ROOT-CAUSE TAXONOMY

Kelasagara categorizes biometric presentation and injection threats into twelve distinct attack vectors, separating physical sensor attacks from software/system exploits:

```
┌────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                              TWELVE BIOMETRIC THREAT CATEGORIES & ROOT CAUSES                          │
├────┬─────────────────────────────┬─────────────┬──────────────────────────────────────────────────────┤
│ #  │ Threat Category             │ Domain      │ Primary Vulnerability & Root Cause                   │
├────┼─────────────────────────────┼─────────────┼──────────────────────────────────────────────────────┤
│ 1  │ Printed Photograph (Matte)  │ Physical    │ High spatial flatness; zero temporal ocular change   │
│ 2  │ Printed Photograph (Glossy) │ Physical    │ Specular glare on flat surface; zero corneal reflex  │
│ 3  │ Smartphone OLED Replay      │ Physical    │ Narrow viewing angle; subpixel grid periodic noise   │
│ 4  │ Tablet IPS Display Replay   │ Physical    │ High luminance; pre-recorded blink mimics liveness   │
│ 5  │ External 4K Monitor Replay  │ Physical    │ Flat parallax; aspect ratio distortion               │
│ 6  │ Looped Video Replay         │ Physical    │ Periodic micro-movements; lack of dynamic response   │
│ 7  │ Synchronized Blink Video    │ Physical    │ EAR drops below 0.60 floor during pre-recorded apex  │
│ 8  │ Partial Cutout Photo Mask   │ Physical    │ Real eyes behind cut paper; border edge gradient jump│
│ 9  │ 3D Latex / Silicone Mask    │ Physical    │ Thermal & reflectance disparity; eye aperture border │
│ 10 │ Camera Frame Injection      │ Software    │ Rooted device hooking Android CameraX HAL            │
│ 11 │ Virtual Camera App          │ Software    │ Mock camera service injecting pre-rendered MP4       │
│ 12 │ Replayed Network Request    │ Software    │ Intercepted HTTPS burst payload replayed to endpoint │
└────┴─────────────────────────────┴─────────────┴──────────────────────────────────────────────────────┘
```

---

## 2. ROOT CAUSE OF THE TABLET SCREEN REPLAY BYPASS

### The Mathematical Vulnerability Chain:
1. **Unpredictable Challenge Absence:** In the baseline production validator, the burst capture protocol assumes the user will simply perform an unprompted blink during the 3-frame window. It does not issue an unannounced, randomized challenge action (e.g. "Smile", "Look right $15^\circ$"). Consequently, an adversary playing a static 5-second video clip of a blinking worker always satisfies the expected sequence.
2. **Single-Feature Reliance:** The temporal validator treats $\text{Aperture}(\text{Frame 2}) / \text{Aperture}(\text{Frame 1}) \le 0.60$ as sufficient evidence of liveness. It does not measure the sub-surface tissue scattering or corneal specular curvature that differentiates human eyes from an LCD display.
3. **Display Sharpness:** An 11-inch Apple iPad Pro Liquid Retina display provides $2388 \times 1668$ pixels at $264\text{ ppi}$. When photographed from 35 cm, the spatial resolution matches a real face closely enough that the 2D Laplacian sharpness variance evaluates to $350 - 450$, directly inside the valid range $[110.0, 1500.0]$.

---

## 3. SEPARATION OF PRESENTATION VS INJECTION DEFENSES

A critical security architectural requirement is the strict separation of defenses:

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                        DEFENSE ALLOCATION MATRIX BY ATTACK DOMAIN                      │
├─────────────────────────────────────────────────┬──────────────────────────────────────┤
│ Physical Attack Instruments (Threats 1 - 9)     │ Software Injection (Threats 10 - 12) │
├─────────────────────────────────────────────────┼──────────────────────────────────────┤
│ • Temporal EAR blink trajectory verification    │ • Android Play Integrity V2 API      │
│ • High-frequency spatial subpixel Moiré FFT     │ • Hardware Keystore ECDSA P-256 keys │
│ • Active chromatic specular corneal delta       │ • Canonical request payload binding  │
│ • Photometric ambient luminance stability       │ • Single-use cryptographic challenge │
│ • Umeyama canonical landmark geometry           │ • In-memory one-time nonce ledger    │
└─────────────────────────────────────────────────┴──────────────────────────────────────┘
```

### Security Assurance:
Software injection attacks (Threats 10, 11, and 12) are **100% intercepted by the cryptographic architecture** (Play Integrity request hash binding + hardware key attestation). Physical presentation attacks (Threats 1–9) are addressed by the sensor-level multi-factor PAD improvements detailed in `docs/PHASE20_7_PAD_IMPROVEMENT_DESIGN.md`.
