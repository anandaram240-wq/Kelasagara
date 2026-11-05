# KELASAGARA V20.9: OPTICAL BENCH PROTOCOL
## Standard Operating Procedure for Physical Non-Biometric Hardware Testing

**Document Ref:** `docs/PHASE20_9_OPTICAL_BENCH_PROTOCOL.md`  
**Phase:** 20.9  
**Auditor:** Independent Security Evaluator & Lab Metrology Engineer  
**Date:** November 1, 2026

---

### 1. Purpose & Ethics Boundary

This standard operating procedure governs physical laboratory calibration of camera capture devices using **strictly non-biometric optical targets** (ISO 12233 resolution targets, Macbeth ColorChecker charts, calibrated matte reflectance fixtures).
- **Zero Human Subjects:** No human biometric features or facial imagery are acquired under this protocol.
- **IEC Boundary:** Institutional Ethics Committee protocol `IEC-KELA-2026-003` governs human subject testing and remains in `SUBMITTED` status. This protocol operates independently within non-biometric optical physics.

---

### 2. Optical Fixture Setup

1. **Illumination Chamber:**
   - Dual D65 calibrated light sources (correlated color temperature $6500\text{ K} \pm 200\text{ K}$).
   - Variable illuminance levels: $20\text{ lux}$ (low-light), $150\text{ lux}$ (office indoor), $800\text{ lux}$ (bright retail).
   - Color Rendering Index ($R_a > 95$).

2. **Target Placement:**
   - Target mounted on non-reflective optical breadboard.
   - Fixed working distance: $35\text{ cm} \pm 1\text{ cm}$ (standard smartphone selfie interaction distance).
   - Perpendicular alignment to optical axis verified via laser level ($\theta < 1.0^\circ$).

3. **Handset Fixturing:**
   - Handset secured in 3-axis precision kinematic mount.
   - Front-facing camera centered on target optical crosshair.

---

### 3. Measurement Metrics

- **Spatial Frequency Response (SFR / MTF50):** Nyquist frequency response measured across horizontal and vertical slanted edges.
- **Color Accuracy ($\Delta E_{00}$):** Evaluated against 24 standard Macbeth color patches.
- **Dynamic Range:** Evaluated against 36-patch grayscale step tablet.
- **Temporal Frame Monotonicity:** Frame interval stability ($30\text{ fps} \pm 2\text{ fps}$, jitter $\sigma < 3\text{ ms}$).
