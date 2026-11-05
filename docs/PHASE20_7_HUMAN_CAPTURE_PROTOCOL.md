# PHASE 20.7: CONTROLLED HUMAN BIOMETRIC CAPTURE PROTOCOL
**System:** Kelasagara Biometric Identity & Authentication Platform  
**Phase:** 20.7 (Controlled Physical Biometric Validation & PAD Hardening)  
**Document Code:** SOP-BIO-2026-007  
**Author:** Principal Biometric Research Engineer & Android Camera Systems Architect  
**Review Status:** Ethical Review Board Protocol (Standard Operating Procedure)  
**Execution Gate Status:** **BLOCKED** (Pending Institutional Ethics Committee Formal Sign-off)

---

## 1. Scope & Research Objective

This Standard Operating Procedure (SOP) governs all prospective physical biometric data acquisition sessions for the empirical validation of the Kelasagara SFace 128-D biometric recognition engine and Presentation Attack Detection (PAD) subsystems.

The primary objective is to obtain high-integrity, statistically valid, and ethically compliant biometric test samples across realistic field operating conditions representative of informal economy workers in Karnataka, India, while maintaining zero permanent retention of raw imagery.

> [!CAUTION]
> **GATE LOCKOUT ACTIVE:**  
> In compliance with the Phase 20.7 Research Directive, the Digital Personal Data Protection Act (DPDPA 2023), and the Declaration of Helsinki, **NO PHYSICAL CAPTURE SESSIONS MAY COMMENCE** until the Institutional Ethics Committee (IEC) status transitions from `SUBMITTED` to `APPROVED` and physical Android hardware passes qualification.

---

## 2. Participant Pre-Requisites & Consent Protocol

Before any sensor feed is initiated or participant enters the capture perimeter:
1. **Participant Information Sheet (PIS):** The volunteer must be presented with the official PIS in English or Kannada.
2. **Voluntary Informed Consent Form (ICF):** The volunteer must execute the dual-language consent agreement (`docs/PHASE20_7_CONSENT_PROTOCOL.md`).
3. **Cryptographic Consent Token Generation:** The capture coordinator records the consent execution on an offline administrative ledger. The system generates a salted SHA-256 session hash:
   $$\text{SessionHash} = \text{HMAC-SHA256}(K_{\text{audit}}, \text{ParticipantID} \parallel \text{Timestamp} \parallel \text{ConsentID})$$
4. **Automated Gating:** The capture application will refuse to unlock CameraX preview buffers unless the session initialization payload contains a valid, non-expired consent token.

---

## 3. Environmental & Optical Capture Matrix

Each participant undergoes a standardized capture sequence across five distinct environmental illumination regimes and three optical distance intervals.

### 3.1. Standardized Lighting Regimes

| Regime Code | Environment Name | Target Illuminance (Lux) | Illuminance Source & Placement | Primary Stress Target |
| :--- | :--- | :--- | :--- | :--- |
| **L1** | Indoor Standard Diffuse | $350 - 500\,\text{lux}$ | Overhead 4000K commercial LED panels, diffuse | Baseline reference operating point |
| **L2** | Direct Outdoor Sunlight | $8,000 - 12,000\,\text{lux}$ | Natural direct sunlight, solar noon $\pm 2\,\text{hrs}$ | Sensor saturation, contrast blowout, squint |
| **L3** | Low Ambient (Dim Light) | $10 - 25\,\text{lux}$ | Enclosed room, single indirect nightlight | Shot noise, sensor gain, underexposure |
| **L4** | Directional Harsh Sidelight | $800 - 1,200\,\text{lux}$ | 45° oblique desk lamp, opposite side in shadow | Asymmetric shadow, landmark misdetection |
| **L5** | Backlit Silhouette | Background $> 4,000\,\text{lux}$, Face $< 150\,\text{lux}$ | Subject positioned directly in front of sunny window | Dynamic range clipping, specular blowout |

*Illuminance is measured and verified at the participant's nose tip using a calibrated digital lux meter (accuracy $\pm 3\%$) prior to each recording sequence.*

---

### 3.2. Optical Distance & Pose Intervals

To simulate real-world mobile device usage across varying arm lengths and user heights:

1. **Distance Intervals:**
   - **D1 (Near):** $25 \pm 2\,\text{cm}$ (Tight framing, macro lens distortion).
   - **D2 (Canonical):** $45 \pm 3\,\text{cm}$ (Natural arm's length, standard enrollment distance).
   - **D3 (Far):** $65 \pm 5\,\text{cm}$ (Extended reach, reduced inter-pupillary distance in pixels).

2. **Pose Invariants & Limits:**
   - **Frontal Baseline:** Yaw $0^\circ \pm 5^\circ$, Pitch $0^\circ \pm 5^\circ$, Roll $0^\circ \pm 3^\circ$.
   - **Yaw Stress:** Controlled yaw rotation to $\pm 15^\circ$ (guided by on-screen protractor UI).
   - **Pitch Stress:** Controlled tilt upward/downward to $\pm 10^\circ$.
   - **Expression Stress:** Neutral face $\rightarrow$ Natural smile $\rightarrow$ Mouth slightly open.

---

## 4. Hardware Sensor Qualification & Capture Pipeline

The capture software operates through an Android CameraX pipeline configured under strict privacy controls:

```
+--------------------------------------------------------------------------------------------------+
| CameraX ImageAnalysis UseCase (YUV_420_888 Native Buffer)                                       |
+--------------------------------------------------------------------------------------------------+
                                                 |
                                                 v
+--------------------------------------------------------------------------------------------------+
| Ephemeral Frame Processor (In-Memory Direct ByteBuffer)                                         |
|  - Frame Dimensions: 640 x 480 @ 30 FPS                                                          |
|  - YuNet Face Detection + 5 Landmark Localization (Le, Re, N, Lm, Rm)                            |
|  - Umeyama Similarity Transform (112 x 112 aligned RGB crop)                                     |
|  - SFace 128-D Inference Pool (ONNX Runtime Local Session)                                       |
|  - L2 Feature Vector Normalization (||v||_2 = 1.0)                                               |
+--------------------------------------------------------------------------------------------------+
                                                 |
                                                 v
+--------------------------------------------------------------------------------------------------+
| Ephemeral Memory Shredder                                                                        |
|  - Native ByteBuffer zeroized via java.util.Arrays.fill((byte) 0)                                |
|  - Aligned crop garbage-collected immediately                                                    |
|  - NO JPEG / PNG WRITTEN TO LOCAL FLASH STORAGE                                                  |
+--------------------------------------------------------------------------------------------------+
                                                 |
                                                 v
+--------------------------------------------------------------------------------------------------+
| Output: Telemetry Record Only                                                                    |
|  { sessionHash, cohortId, lux, distanceCm, poseYaw, sfaceVector128D, padMetrics }                |
+--------------------------------------------------------------------------------------------------+
```

---

## 5. Presentation Attack Detection (PAD) Evaluation Capture Procedure

Following genuine bona fide captures, a standardized suite of Presentation Attack Instruments (PAIs) is evaluated against the same capture sensor under identical lighting:

1. **PAI-1: Matte 2D Paper Printout:** High-resolution color laser print ($1200\,\text{DPI}$) on matte $120\,\text{GSM}$ paper.
2. **PAI-2: Glossy 2D Photo Printout:** Professional photo lab print on high-gloss resin-coated photographic paper.
3. **PAI-3: Smartphone Screen Replay:** 6.1" OLED display ($1170 \times 2532$ pixels, $460\,\text{PPI}$, $> 800\,\text{nits}$) replaying 4K uncompressed genuine enrollment video.
4. **PAI-4: Tablet Screen Video Replay:** 11" Liquid Retina IPS display ($2388 \times 1668$ pixels, $264\,\text{PPI}$, $600\,\text{nits}$) replaying continuous eye-blink video.
5. **PAI-5: Curved Flexible Screen:** Dynamic screen replay curved around a $300\,\text{mm}$ radius cylindrical fixture to simulate face contours.

---

## 6. Audit Trail & Cryptographic Verification

Every completed session generates an immutable JSON session manifest:
- **Session ID:** Cryptographic UUIDv4.
- **Timestamp:** ISO 8601 UTC.
- **Hardware Profile:** Phone model, Android OS version, Camera sensor ID, Exposure time, ISO gain.
- **Environmental Lux:** Ground-truth lux reading.
- **Integrity Seal:** HMAC-SHA256 signature calculated across all extracted vectors and metadata using the air-gapped auditor key.

Any modification to telemetry or vectors invalidates the signature, guaranteeing absolute evidential integrity.
